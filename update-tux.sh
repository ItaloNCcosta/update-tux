#!/usr/bin/env bash

set -euo pipefail

AUTHOR="Italo Nogueira"
YEAR="2024"
SUDO_CMD=()
EXECUTED_STEPS=()
SKIPPED_STEPS=()

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

die() {
  error "$1"
  exit 1
}

has_command() {
  command -v "$1" >/dev/null 2>&1
}

join_by() {
  local separator="$1"
  shift || true
  local first=1

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
  if run_privileged nala update \
    && run_privileged nala full-upgrade -y \
    && run_privileged nala autoremove -y \
    && run_privileged nala clean; then
    EXECUTED_STEPS+=(".deb (nala)")
    success "Pacotes .deb atualizados com sucesso."
  else
    die "Falha na atualizacao dos pacotes .deb."
  fi
}

update_flatpak_packages() {
  if ! has_command flatpak; then
    return 0
  fi

  info "Atualizando pacotes flatpak..."
  if flatpak update -y; then
    EXECUTED_STEPS+=("flatpak")
    success "Pacotes flatpak atualizados com sucesso."
  else
    die "Falha na atualizacao dos pacotes flatpak."
  fi
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

  if (( ${#SKIPPED_STEPS[@]} > 0 )); then
    printf "Etapas puladas: %s\n" "$(join_by ', ' "${SKIPPED_STEPS[@]}")"
  fi
}

main() {
  print_banner
  prepare_environment
  update_deb_packages
  update_flatpak_packages
  update_snap_packages
  print_summary
}

main "$@"
