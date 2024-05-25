#!/bin/bash

# -*- ENCODING: UTF-8 -*-
# Atualizador de Programas
# Autor: Italo Nogueira
# Ano: 2023

printf "\e[01;37;45m========== ATUALIZADOR DE PROGRAMAS ==========\e[0m\n"
printf "Autor: Italo Nogueira  / \nAno: 2023\n"
printf "\e[37;45m====================================================================\e[0m\n"
printf "Olá Usuário, bem-vindo ao utilitário de atualização.\n"
printf "Esse script vai atualizar seus arquivos .deb, flatpaks e snaps.\n"
printf "O programa fechará automaticamente quando as atualizações forem concluídas.\n"
printf "Digite sua senha para começar\n"

# Atualização de pacotes .deb
printf "\nAtualizando pacotes .deb...\n"
sudo apt update && sudo apt full-upgrade -y && sudo apt autoremove -y && sudo apt clean
if [ $? -eq 0 ]; then
  printf "Pacotes .deb atualizados com sucesso.\n"
else
  printf "\e[31mFalha na atualização dos pacotes .deb.\e[0m\n"
  exit 1
fi

# Atualização de pacotes flatpak
printf "\nAtualizando pacotes flatpak...\n"
flatpak update -y
if [ $? -eq 0 ]; then
  printf "Pacotes flatpak atualizados com sucesso.\n"
else
  printf "\e[31mFalha na atualização dos pacotes flatpak.\e[0m\n"
  exit 1
fi

# Atualização de pacotes snap
printf "\nAtualizando pacotes snap...\n"
sudo snap refresh
if [ $? -eq 0 ]; then
  printf "Pacotes snap atualizados com sucesso.\n"
else
  printf "\e[31mFalha na atualização dos pacotes snap.\e[0m\n"
  exit 1
fi

printf "\e[32m\nTodas as atualizações foram concluídas com sucesso.\e[0m\n"
exit 0
