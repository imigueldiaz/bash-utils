#!/bin/bash

#Si cualquier proceso da error, salimos
set -e

# Colores
COL_NC='\e[0m' # No Color
COL_LIGHT_GREEN='\e[1;32m'
COL_LIGHT_RED='\e[1;31m'

#Marcas informativas
TICK="[${COL_LIGHT_GREEN}✓${COL_NC}]"
CROSS="[${COL_LIGHT_RED}✗${COL_NC}]"
INFO="[${COL_LIGHT_GREEN}i${COL_NC}]"
# shellcheck disable=SC2034
DONE="${COL_LIGHT_GREEN} ${TICK} ¡Proceso terminado!${COL_NC}"

USUARIO="$1"

printf "  %b Comprobando si soy root o sudo.\\n" "${INFO}"
if [[ $(id -u) -ne 0 ]] ; then
    printf "  %b Por favor, ejecutame como root o sudo.\\n"  "${CROSS}"; exit 1 ;
fi

printf "  %b Actualizando paquetes.\\n" "${INFO}"
DEBIAN_FRONTEND=noninteractive sudo apt update && DEBIAN_FRONTEND=noninteractive sudo apt upgrade -y

printf "  %b Instalando prerequisitos.\\n" "${INFO}"
sudo  debconf-apt-progress -- apt install -y apt-transport-https ca-certificates curl gnupg2 software-properties-common

printf "  %b Instalando clave GPG del repositorio de Docker.\\n" "${INFO}"
curl -fsSL https://download.docker.com/linux/debian/gpg | sudo apt-key add -

printf "  %b Añadiendo repositorio de docker a sources.list.\\n" "${INFO}"
sudo add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/debian $(lsb_release -cs) stable"

printf "  %b instalando Docker engine.\\n" "${INFO}"
sudo DEBIAN_FRONTEND=noninteractive apt update && sudo  debconf-apt-progress -- apt install -y docker-ce docker-ce-cli containerd.io

if [[ -n "$USUARIO" ]]; then
    if [[ -z "$(getent group docker)" ]]; then
        printf "  %b Creando el grupo docker.\\n" "${INFO}" ; sudo groupadd docker;
    fi
    
    printf "  %b Añadiendo a %s al grupo docker.\\n"  "${INFO}" "$USUARIO"
    sudo usermod -aG docker "$USUARIO"
    
fi

printf "  %b Habilitando Docker en el arranque del sistema.\\n" "${INFO}"
sudo systemctl enable docker


printf "  %b Descargando e instalando  Docker Compose.\\n" "${INFO}"

sudo curl -s https://api.github.com/repos/docker/compose/releases/latest \
| grep browser_download_url \
| grep docker-compose-Linux-x86_64 \
| cut -d '"' -f 4 \
| wget -qi -

sudo mv docker-compose-Linux-x86_64 /usr/local/bin/docker-compose

sudo chmod 755 /usr/local/bin/docker-compose

printf "  %b.\\n" "${DONE}"


