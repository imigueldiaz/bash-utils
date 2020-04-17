#!/bin/bash
# Install docker service on debian machine and prepare basic stuff.


# exit on any error.
set -e

# Colors
COL_NC='\e[0m' # No Color
COL_LIGHT_GREEN='\e[1;32m'
COL_LIGHT_RED='\e[1;31m'

# Marks
TICK="[${COL_LIGHT_GREEN}✓${COL_NC}]"
CROSS="[${COL_LIGHT_RED}✗${COL_NC}]"
INFO="[${COL_LIGHT_GREEN}i${COL_NC}]"
DONE="${TICK} Done!"

# User to add to docker group if it is passed as argument.
USUARIO="$1"

### Test if we are sudo or root user ###
test_sudo() {
    
    printf "  %b Testing root user.\\n" "${INFO}"
    if [[ $(id -u) -ne 0 ]] ; then
        printf "  %b Please run me as root :(.\\n"  "${CROSS}"; exit 1 ;
    fi
}

### Install of docker service and docker repository. ###
install_docker() {
    
    printf "  %b Updating packages.\\n" "${INFO}"
    DEBIAN_FRONTEND=noninteractive sudo apt update && DEBIAN_FRONTEND=noninteractive sudo apt upgrade -y
    
    printf "  %b Installling prerequisites.\\n" "${INFO}"
    sudo  debconf-apt-progress -- apt install -y apt-transport-https ca-certificates curl gnupg2 software-properties-common
    
    printf "  %b Installing GPG key from docker repository.\\n" "${INFO}"
    curl -fsSL https://download.docker.com/linux/debian/gpg | sudo apt-key add -
    
    printf "  %b Adding docker repository .\\n" "${INFO}"
    sudo add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/debian $(lsb_release -cs) stable"
    
    printf "  %b Installing Docker CE and client.\\n" "${INFO}"
    sudo DEBIAN_FRONTEND=noninteractive apt update && sudo  debconf-apt-progress -- apt install -y docker-ce docker-ce-cli containerd.io
}

### Add user to docker group on demand ###
add_docker_user() {
    
    if [[ -n "$USUARIO" ]]; then
        if [[ -z "$(getent group docker)" ]]; then
            printf "  %b Creating docker group.\\n" "${INFO}" ; sudo groupadd docker;
        fi
        
        printf "  %b Adding %s on docker group.\\n"  "${INFO}" "$USUARIO"
        sudo usermod -aG docker "$USUARIO"
        
    fi
}

### Enable docker service ###
enable_docker_service() {
    
    printf "  %b Enabling docker at boot.\\n" "${INFO}"
    sudo systemctl enable docker
}


### Install docker service ###
install_docker_compose() {
    
    printf "  %b Installing  Docker Compose.\\n" "${INFO}"
    sudo curl -s https://api.github.com/repos/docker/compose/releases/latest \
    | grep browser_download_url \
    | grep docker-compose-Linux-x86_64 \
    | cut -d '"' -f 4 \
    | wget -qi -
    
    sudo mv docker-compose-Linux-x86_64 /usr/local/bin/docker-compose
    
    sudo chmod 755 /usr/local/bin/docker-compose
    
}



test_sudo
install_docker
add_docker_user
enable_docker_service
install_docker_compose

printf "  %b.\\n" "${DONE}"


