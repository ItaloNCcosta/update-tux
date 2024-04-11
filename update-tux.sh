#!/bin/bash

# -*- ENCODING: UTF-8 -*-
echo -e "\e[01;37;45m========== ATUALIZADOR DE PROGRAMAS ==========\e[0m"
echo -e "Autor: Italo Nogueira  / \nAno: 2023"
echo -e "\e[37;45m====================================================================\e[0m"
echo -e "Olá Usuário, bem vindo ao utilitário de atualização.\nEsse script vai atualizar seus arquivos .deb, flatpaks e snaps \nO programa fechará automáticamente quando as atualizações forem concluídas. \nDigite sua senha para começar"

#.deb
echo "sudo apt update"
sudo apt update

echo "sudo apt full-upgrade"
sudo apt full-upgrade

echo "sudo apt dist-upgrade"
sudo apt dist-upgrade

#flatpak
echo "flatpak update"
flatpak update

#snap
echo "snap refresh"
snap refresh

