#!/usr/bin/env bash

set -euo pipefail

AUTHOR="Italo Nogueira"
YEAR="2024"
SUDO_CMD=()
EXECUTED_STEPS=()
SKIPPED_STEPS=()
SYSTEM_SNAPSHOT=""
FLATPAK_UNIT=""

if [[ -t 1 ]]; then
  HEADER_COLOR='\033[1;37;45m'
  SUBHEADER_COLOR='\033[37;45m'
  INFO_COLOR='\033[34m'
  SUCCESS_COLOR='\033[32m'
  WARN_COLOR='\033[33m'
  ERROR_COLOR='\033[31m'
  RESET_COLOR='\033[0m'
else
  HEADER_COLOR=''
  SUBHEADER_COLOR=''
  INFO_COLOR=''
  SUCCESS_COLOR=''
  WARN_COLOR=''
  ERROR_COLOR=''
  RESET_COLOR=''
fi

print_banner() {
  printf "%b========== ATUALIZADOR DE PROGRAMAS ==========%b\n" "$HEADER_COLOR" "$RESET_COLOR"
  printf "Autor: %s /\nAno: %s\n" "$AUTHOR" "$YEAR"
  printf "%b====================================================================%b\n" "$SUBHEADER_COLOR" "$RESET_COLOR"
  printf "O script atualiza pacotes .deb com nala e, quando disponiveis, flatpaks e snaps.\n"
  printf "Etapas ausentes no sistema serao puladas automaticamente.\n"
}

info() {
  printf "%b[INFO]%b %s\n" "$INFO_COLOR" "$RESET_COLOR" "$1"
}

success() {
  printf "%b[OK]%b %s\n" "$SUCCESS_COLOR" "$RESET_COLOR" "$1"
}

warn() {
  printf "%b[AVISO]%b %s\n" "$WARN_COLOR" "$RESET_COLOR" "$1"
}

error() {
  printf "%b[ERRO]%b %s\n" "$ERROR_COLOR" "$RESET_COLOR" "$1" >&2
}

warn_snapshot_rollback() {
  if [[ -n "$SYSTEM_SNAPSHOT" ]]; then
    warn "Snapshot Btrfs disponivel para rollback manual: $SYSTEM_SNAPSHOT"
  fi
}

die() {
  error "$1"
  warn_snapshot_rollback
  exit 1
}

interrupt_update() {
  if [[ -n "$FLATPAK_UNIT" ]]; then
    systemctl --user stop "$FLATPAK_UNIT" || true
  fi
  warn_snapshot_rollback
  exit "$1"
}

has_command() {
  command -v "$1" >/dev/null 2>&1
}

join_by() {
  local separator="$1"
  shift || true
  local first=1 item

  for item in "$@"; do
    if (( first )); then
      printf "%s" "$item"
      first=0
    else
      printf "%s%s" "$separator" "$item"
    fi
  done
}

run_privileged() {
  if (( ${#SUDO_CMD[@]} > 0 )); then
    "${SUDO_CMD[@]}" "$@"
  else
    "$@"
  fi
}

backup_dir() {
  printf "/var/backups/update-tux"
}

archive_old_source_backups() {
  local source_dir="/etc/apt/sources.list.d"
  local target_dir
  target_dir="$(backup_dir)"

  shopt -s nullglob
  local old_backups=("$source_dir"/*.bak.*)
  shopt -u nullglob

  if (( ${#old_backups[@]} == 0 )); then
    return 0
  fi

  warn "Backups antigos .bak.* encontrados em $source_dir. Movendo para $target_dir para remover avisos do apt."
  run_privileged mkdir -p "$target_dir"

  local backup_file
  for backup_file in "${old_backups[@]}"; do
    run_privileged mv "$backup_file" "$target_dir/"
  done
}

prune_old_snapshots() {
  local snapshot_dir="$1"
  local keep=3

  shopt -s nullglob
  local snapshots=("$snapshot_dir"/root-*)
  shopt -u nullglob

  # O nome root-AAAAMMDDHHMMSS faz a ordem do glob ser cronologica.
  local excess=$(( ${#snapshots[@]} - keep ))
  (( excess > 0 )) || return 0

  info "Removendo $excess snapshot(s) Btrfs antigo(s); mantendo os $keep mais recentes."
  local snapshot
  for snapshot in "${snapshots[@]:0:excess}"; do
    run_privileged btrfs subvolume delete "$snapshot" >/dev/null \
      || warn "Nao foi possivel remover o snapshot $snapshot."
  done
}

create_system_snapshot() {
  if ! has_command findmnt || ! has_command btrfs; then
    SKIPPED_STEPS+=("snapshot btrfs (ferramentas ausentes)")
    warn "Snapshot Btrfs indisponivel. A etapa sera pulada."
    return 0
  fi

  if [[ "$(findmnt -n -o FSTYPE /)" != "btrfs" ]]; then
    SKIPPED_STEPS+=("snapshot btrfs (raiz nao usa btrfs)")
    warn "Sistema raiz nao esta em Btrfs. Snapshot sera pulado."
    return 0
  fi

  local snapshot_dir="/.update-tux-snapshots"
  local snapshot_path="$snapshot_dir/root-$(date +%Y%m%d%H%M%S)"

  info "Criando snapshot Btrfs somente leitura antes da atualizacao..."
  if run_privileged mkdir -p "$snapshot_dir" \
    && run_privileged btrfs subvolume snapshot -r / "$snapshot_path"; then
    SYSTEM_SNAPSHOT="$snapshot_path"
    EXECUTED_STEPS+=("snapshot btrfs")
    success "Snapshot Btrfs criado em $snapshot_path."
    prune_old_snapshots "$snapshot_dir"
  else
    SKIPPED_STEPS+=("snapshot btrfs (falhou)")
    warn "Nao foi possivel criar snapshot Btrfs. Continuando sem snapshot."
  fi
}

fix_pop_ubuntu_mirror() {
  local source_file="/etc/apt/sources.list.d/system.sources"

  # Arquivo exclusivo do Pop!_OS: em outras distros a etapa nao se aplica.
  [[ -e "$source_file" ]] || return 0

  if [[ ! -r "$source_file" ]]; then
    warn "Nao foi possivel ler $source_file. A troca de mirror sera pulada."
    return 0
  fi

  if grep -q '^URIs: http://apt.pop-os.org/ubuntu[[:space:]]*$' "$source_file"; then
    local backup_file
    backup_file="$(backup_dir)/system.sources.$(date +%Y%m%d%H%M%S)"

    warn "Mirror Ubuntu do Pop detectado com pacotes 404. Trocando para archive.ubuntu.com."
    run_privileged mkdir -p "$(backup_dir)"
    run_privileged cp -a "$source_file" "$backup_file"
    run_privileged sed -i 's#^URIs: http://apt.pop-os.org/ubuntu[[:space:]]*$#URIs: http://archive.ubuntu.com/ubuntu#' "$source_file"
    success "Fonte Ubuntu ajustada. Backup criado em $backup_file."
  fi
}

wait_for_apt_locks() {
  has_command fuser || return 0

  local locks=(/var/lib/dpkg/lock-frontend /var/lib/dpkg/lock /var/lib/apt/lists/lock /var/cache/apt/archives/lock)
  local waited=0
  while run_privileged fuser -s "${locks[@]}" 2>/dev/null; do
    if (( waited == 0 )); then
      warn "Outro processo do APT/dpkg esta em andamento (ex.: atualizacao automatica). Aguardando a liberacao do lock..."
    fi
    if (( waited >= 300 )); then
      warn "O lock do APT continua ocupado apos 5 minutos. Tentando mesmo assim."
      return 0
    fi
    sleep 5
    waited=$((waited + 5))
  done
}

# Toda chamada ao APT/dpkg espera o lock: apt-daily e apt-daily-upgrade podem iniciar entre um comando e outro.
run_apt() {
  wait_for_apt_locks
  run_privileged "$@"
}

repair_deb_state() {
  warn "Tentando reparar estado dos pacotes .deb antes de repetir a atualizacao."
  run_apt dpkg --configure -a \
    && run_apt apt-get -f install -y \
    && { run_apt nala clean || warn "Nao foi possivel limpar o cache do nala durante o reparo."; }
}

run_deb_upgrade() {
  run_apt nala update -o Acquire::AllowReleaseInfoChange::Label=true \
    && run_apt nala full-upgrade -y \
    && run_apt nala autoremove -y \
    && run_apt nala clean
}

prepare_environment() {
  if (( EUID == 0 )); then
    info "Executando como root. Nenhuma autenticacao adicional sera solicitada."
  else
    has_command sudo || die "O comando 'sudo' nao foi encontrado. Execute como root ou instale o sudo."
    info "Validando credenciais de administrador..."
    sudo -v || die "Nao foi possivel autenticar com sudo."
    SUDO_CMD=(sudo)
  fi

  has_command nala || die "O comando 'nala' nao foi encontrado. Este branch exige o nala para atualizar pacotes .deb."

  if has_command flatpak; then
    info "Flatpak detectado: a etapa sera executada."
  else
    SKIPPED_STEPS+=("flatpak (nao instalado)")
    warn "Flatpak nao encontrado. A etapa sera pulada."
  fi

  if has_command snap; then
    info "Snap detectado: a etapa sera executada."
  else
    SKIPPED_STEPS+=("snap (nao instalado)")
    warn "Snap nao encontrado. A etapa sera pulada."
  fi
}

update_deb_packages() {
  info "Atualizando pacotes .deb com nala..."
  run_apt nala clean || warn "Nao foi possivel limpar o cache do nala antes da atualizacao."

  if run_deb_upgrade; then
    EXECUTED_STEPS+=(".deb (nala)")
    success "Pacotes .deb atualizados com sucesso."
  elif repair_deb_state && run_deb_upgrade; then
    EXECUTED_STEPS+=(".deb (nala, com reparo)")
    success "Pacotes .deb atualizados com sucesso apos reparo."
  else
    die "Falha na atualizacao dos pacotes .deb."
  fi
}

update_flatpak_packages() {
  if ! has_command flatpak; then
    return 0
  fi

  info "Atualizando pacotes flatpak..."
  local attempt status
  local flatpak_command=(flatpak update -y --noninteractive)
  for attempt in 1 2; do
    if "${flatpak_command[@]}"; then
      EXECUTED_STEPS+=("flatpak")
      FLATPAK_UNIT=""
      success "Pacotes flatpak atualizados com sucesso."
      return 0
    else
      status=$?
    fi

    if (( status >= 128 )); then
      error "Atualizacao flatpak interrompida (codigo $status)."
      interrupt_update "$status"
    fi
    FLATPAK_UNIT=""

    if (( attempt == 1 )); then
      warn "Flatpak falhou (codigo $status). Repetindo a atualizacao em 5 segundos..."
      if has_command systemd-run && has_command systemctl \
        && systemctl --user is-active --quiet default.target; then
        info "A nova tentativa usara IPv4 apenas neste processo para contornar falhas de IPv6."
        FLATPAK_UNIT="update-tux-flatpak-$$"
        flatpak_command=(systemd-run --user --quiet --pipe --wait --collect
          '--property=RestrictAddressFamilies=AF_UNIX AF_INET AF_NETLINK'
          "--unit=$FLATPAK_UNIT" "${flatpak_command[@]}")
      fi
      sleep 5
    fi
  done

  die "Falha na atualizacao dos pacotes flatpak apos 2 tentativas (codigo $status). Consulte os erros acima."
}

update_snap_packages() {
  if ! has_command snap; then
    return 0
  fi

  info "Atualizando pacotes snap..."
  if run_privileged snap refresh; then
    EXECUTED_STEPS+=("snap")
    success "Pacotes snap atualizados com sucesso."
  else
    die "Falha na atualizacao dos pacotes snap."
  fi
}

print_summary() {
  printf "\n"
  success "Todas as atualizacoes foram concluidas com sucesso."
  printf "Etapas executadas: %s\n" "$(join_by ', ' "${EXECUTED_STEPS[@]}")"

  if [[ -n "$SYSTEM_SNAPSHOT" ]]; then
    printf "Snapshot Btrfs de seguranca: %s\n" "$SYSTEM_SNAPSHOT"
  fi

  if (( ${#SKIPPED_STEPS[@]} > 0 )); then
    printf "Etapas puladas: %s\n" "$(join_by ', ' "${SKIPPED_STEPS[@]}")"
  fi

  if [[ -f /var/run/reboot-required ]]; then
    warn "Reinicie o sistema para concluir atualizacoes de kernel, drivers ou servicos essenciais."

    if [[ -r /var/run/reboot-required.pkgs ]]; then
      printf "Pacotes que solicitaram reinicio:\n"
      while IFS= read -r package_name; do
        printf "- %s\n" "$package_name"
      done < /var/run/reboot-required.pkgs
    fi
  fi
}

main() {
  trap 'interrupt_update 130' INT
  trap 'interrupt_update 143' TERM
  print_banner
  prepare_environment
  create_system_snapshot
  archive_old_source_backups
  fix_pop_ubuntu_mirror
  update_deb_packages
  update_flatpak_packages
  update_snap_packages
  print_summary
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
