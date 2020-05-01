#!/usr/bin/env bash

# Install docker service on debian machine and prepare basic stuff, as
# docker-compose and TLS daemon.

# exit on any error.
set -e

# Name of the debian based distro. Testing (bullseye currently) is not available
# on https://download.docker.com/linux/debian so we must use stable (buster
# currently). 
BRANCH="buster"

# Colors
COL_NC='\e[0m' # No Color
COL_LIGHT_GREEN='\e[1;32m'
COL_LIGHT_RED='\e[1;31m'

# Marks
TICK="[${COL_LIGHT_GREEN}✓${COL_NC}]"
CROSS="[${COL_LIGHT_RED}✗${COL_NC}]"
INFO="[${COL_LIGHT_GREEN}i${COL_NC}]"
DONE="${TICK} Done!"
OK="[${COL_LIGHT_GREEN}OK${COL_NC}]"
KO="[${COL_LIGHT_RED}KO${COL_NC}]"

# User to add to docker group if it is passed as argument.
USUARIO="$1"
USUARIO_HOME=""
# TLS Certificates related variables
CA_PWD=""
PASS_FILE="CertPass"
CERT_IPS=""
CERT_DOMAIN=""
CERT_CONF_FILE="Cert.conf"
SUBJECT_ALT_NAME=""
PASS_METHOD="pass"
CERT_METHOD="-subj"
CERT_SUBJ=""

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
    sudo  debconf-apt-progress -- apt install -y apt-transport-https ca-certificates curl gnupg2 software-properties-common whiptail
    
    printf "  %b Installing GPG key from docker repository.\\n" "${INFO}"
    curl -fsSL https://download.docker.com/linux/debian/gpg | sudo apt-key add -
    
    printf "  %b Adding docker repository .\\n" "${INFO}"
    sudo add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/debian ${BRANCH} stable"
    
    printf "  %b Installing Docker CE and client.\\n" "${INFO}"
    sudo DEBIAN_FRONTEND=noninteractive apt update && sudo  debconf-apt-progress -- apt install -y docker-ce docker-ce-cli containerd.io
}

### Add user to docker group on demand ###
add_docker_user() {
    
    if [[ -n "${USUARIO}" ]]; then

        USUARIO_HOME=$(sudo awk -F: -v v="${USUARIO}" '{if ($1==v) print $6}' /etc/passwd)

        if [[ -z "$(getent group docker)" ]]; then
            printf "  %b Creating docker group.\\n" "${INFO}" 
            sudo groupadd docker
        
        fi
        
        printf "  %b Adding %s on docker group.\\n"  "${INFO}" "${USUARIO}"
        sudo usermod -aG docker "$USUARIO"
        
    fi
}

### Enable docker service ###
enable_docker_service() {
    
    printf "  %b Enabling docker at boot.\\n" "${INFO}"
    sudo systemctl daemon-reload
    sudo systemctl enable docker
}


### Install docker service ###
install_docker_compose() {
    
    printf "  %b Installing  Docker Compose.\\n" "${INFO}"
    sudo curl -s https://api.github.com/repos/docker/compose/releases/latest \
    | grep browser_download_url \
    | grep "docker-compose-Linux-x86_64" \
    | cut -d '"' -f 4 \
    | wget -qi -
    
    if sha256sum --quiet --check docker-compose-Linux-x86_64.sha256; then
        printf "  %b Docker Compose SHA256 checksum is %b.\\n" "${INFO}" "${OK}"
        sudo mv docker-compose-Linux-x86_64 /usr/local/bin/docker-compose
        sudo chmod 755 /usr/local/bin/docker-compose
        sudo rm -f docker-compose-Linux-x86_64.sha256
    else
        printf "  %b Docker Compose SHA256 checksum is %b :().\\n" "${CROSS}" "${KO}"
        exit 1
    fi
}


### Unsets variables and prints end of process
process_done() {

     if [[ -r "$PASS_FILE" ]]; then

        printf "%b PLEASE REMEMBER TO DELETE %s IF YOU ARE NOT USING IT ANY LONGER %b" "${COL_LIGHT_RED}" "${PASS_FILE}" "${COL_NC}\\n"
 
     fi

     if [[ -r "$CERT_CONF_FILE" ]]; then

        printf "%b PLEASE REMEMBER TO DELETE %s IF YOU ARE NOT USING IT ANY LONGER %b" "${COL_LIGHT_RED}" "${CERT_CONF_FILE}" "${COL_NC}\\n"
 
     fi

    printf "  %b.\\n" "${DONE}"
}


### Cleans stuff
mr_proper() {
    
    printf "  %b Cleaning variables.\\n" "${INFO}"

    unset CA_PWD
    unset PASS_FILE
    unset CERT_IPS
    unset CERT_DOMAIN
    unset CERT_CONF_FILE
    unset SUBJECT_ALT_NAME
    unset PASS_METHOD
    unset CERT_METHOD
    unset CERT_SUBJ

}

 ### Prepares certificates ###
prepare_certificates() {

    if [[ -r "${PASS_FILE}" ]]; then

        CA_PWD=${PASS_FILE}
        PASS_METHOD="file"

    else
    
        CA_PWD=$(whiptail --passwordbox "please enter your password for CA certificate, or cancel to omit TLS configuration on Docker " 8 78 --title "CA certificate password" 3>&1 1>&2 2>&3)

    fi

    CERT_IPS=$( ip -4 -br addr show | sed -e 's/\s\+\|\//*/g' | cut -d'*' -f 3 | sed -e 's/^/IP:/' |  tr '\n' ',' | sed 's/.$//')
    CERT_DOMAIN=$(hostname --fqdn)
    SUBJECT_ALT_NAME="DNS:${CERT_DOMAIN},${CERT_IPS}"

    exitstatus=$?
    
    if [ $exitstatus = 0 ] && [ -n "$CA_PWD" ]; then
        printf "  %b User entered not empty password, so TLS configuration begins.\\n" "${INFO}"
        generate_ca_keys
    else
        printf "  %b User canceled, so TLS configuration is omited.\\n" "${CROSS}"
        process_done
        exit 1
    fi
    
}

### Generates the TLS certificates ###
generate_ca_keys() {
    
    printf "  %b Generating certificates with supplied password.\\n" "${INFO}"

    generate_ca_keys_server

    generate_ca_keys_client

    clean_certs_files

    fix_certs_permissions

    move_certs

    override_docker_systemd

}

### Generates the client certificates ###
generate_ca_keys_client() {

    printf "  %b Generating client certificates.\\n" "${INFO}"

    openssl genrsa -out key.pem 4096
    openssl req -subj '/CN=client' -new -key key.pem -out client.csr

    echo "extendedKeyUsage = clientAuth" > extfile-client.cnf
    openssl x509 -req -days 365 -sha256 -in client.csr -CA ca.pem -CAkey ca-key.pem \
    -CAcreateserial -out cert.pem -extfile extfile-client.cnf -passin "${PASS_METHOD}":"${CA_PWD}"

}

### Generates the CA and server certeficates ###
generate_ca_keys_server() {

    
    printf "  %b Generating CA and server certificates.\\n" "${INFO}"
    
    openssl genrsa -aes256 -passout "${PASS_METHOD}":"${CA_PWD}" -out ca-key.pem 4096
    
    
    if [[ -r "${CERT_CONF_FILE}" ]]; then

        CERT_METHOD=" -config ${CERT_CONF_FILE}"
    else

        ask_cert_subject

    fi

    openssl req -new -x509 -days 365 -key ca-key.pem -sha256 -passin "${PASS_METHOD}":"${CA_PWD}" "${CERT_METHOD}" "${CERT_SUBJ}"  -batch  -out ca.pem
    openssl genrsa -out server-key.pem 4096
    openssl req -subj "/CN=${CERT_DOMAIN}" -sha256 -new -key server-key.pem -out server.csr

    echo "subjectAltName = ${SUBJECT_ALT_NAME}" >> extfile.cnf
    echo "extendedKeyUsage = serverAuth ">> extfile.cnf

    openssl x509 -req -days 365 -sha256 -in server.csr -CA ca.pem -CAkey ca-key.pem \
    -CAcreateserial -out server-cert.pem -extfile extfile.cnf -passin "${PASS_METHOD}":"${CA_PWD}"

}

### Asks about server certificate details ###
ask_cert_subject() {

    COUNTRY=$(whiptail --inputbox "Please, insert you Country code" 8 78 "ES"  --title "Country Code" 3>&1 1>&2 2>&3)
    STATE=$(whiptail --inputbox "Please, insert your State" 8 78 "Madrid"  --title "State Code" 3>&1 1>&2 2>&3)
    LOCATION=$(whiptail --inputbox "Please, insert your Location" 8 78 "Madrid"  --title "Location" 3>&1 1>&2 2>&3)
    ORGANIZATION=$(whiptail --inputbox "Please, insert you Organization" 8 78 "Personal Tests"  --title "Organization Name" 3>&1 1>&2 2>&3)
    UNIT=$(whiptail --inputbox "Please, insert you Unit" 8 78 "Simple developer"  --title "Organization Unit" 3>&1 1>&2 2>&3)
    NAME=$(whiptail --inputbox "Please, insert a user friendly name for this certificate" 8 78 "Personal Docker Certificate"  --title "Common Name" 3>&1 1>&2 2>&3)
    SUBJECT_ALT_NAME=$(whiptail --inputbox "Please, edit the names and Ips valid for the certificate" 8 78 "${SUBJECT_ALT_NAME}"  --title "Valid FQDNs and IPs" 3>&1 1>&2 2>&3)
    CERT_SUBJ="/C=${COUNTRY}/ST=${STATE}/L=${LOCATION}/O=${ORGANIZATION}/OU=${UNIT}/CN=${NAME}"

}

### cleans unneeded cert files. ###
clean_certs_files() {

    printf "  %b Cleaning files.\\n" "${INFO}"
    
    rm -vf client.csr server.csr extfile.cnf extfile-client.cnf ./*.srl

}

### Fixes files permissions ###
fix_certs_permissions() {

    printf "  %b Setting correct permissions.\\n" "${INFO}"

    chmod -v 0400 ca-key.pem key.pem server-key.pem
    chmod -v 0444 ca.pem server-cert.pem cert.pem
}

### Moves certificates
move_certs() {

    printf "  %b Copying certificates.\\n" "${INFO}"
    
    sudo mkdir -p /etc/docker/certs
    sudo cp ca-key.pem key.pem server-key.pem ca.pem server-cert.pem cert.pem /etc/docker/certs
    
    if [[ -n "${USUARIO_HOME}" ]]; then
    
        sudo mkdir -p "${USUARIO_HOME}"/.docker/
        sudo cp -v {ca,cert,key}.pem "${USUARIO_HOME}"/.docker/
        sudo chown -vR "${USUARIO}:${USUARIO}" "${USUARIO_HOME}/.docker/"
    fi
}

override_docker_systemd() {

    printf "  %b Overriding docker.service with TLS configuration.\\n" "${INFO}"

    local override_path="/etc/systemd/system/docker.service.d/"

    sudo mkdir -p "$override_path"

cat  <<OVERRIDE | sudo tee  "$override_path/override.conf" > /dev/null
[Service]
ExecStart=
ExecStart=/usr/bin/dockerd -H tcp://0.0.0.0:2376 --tlsverify --tlscacert=/etc/docker/certs/ca.pem  --tlscert=/etc/docker/certs/server-cert.pem --tlskey=/etc/docker/certs/server-key.pem 

OVERRIDE
}

### HERE BEGINS THE MAGIC ###

test_sudo
install_docker
add_docker_user
install_docker_compose
prepare_certificates
enable_docker_service
process_done
mr_proper
