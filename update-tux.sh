#!/bin/bash

# -*- ENCODING: UTF-8 -*-
echo -e "\e[01;37;45m========== ATUALIZADOR DE PROGRAMAS MELHOR QUE A POP SHOP ==========\e[0m"
echo -e "Autor: Italo Nogueira  / \nAno: 2023"
echo -e "\e[37;45m====================================================================\e[0m"
echo -e "Olá Usuário, bem vindo ao utilitário de atualização.\nEsse script vai atualizar seus arquivos .deb, flatpaks e snaps \nO programa fechará automáticamente quando as atualizações forem concluídas. \nDigite sua senha para começar"

#.deb
sudo apt update
sudo apt full-upgrade
sudo apt dist-upgrade

#flatpak
flatpak update

#snap
snap refresh

