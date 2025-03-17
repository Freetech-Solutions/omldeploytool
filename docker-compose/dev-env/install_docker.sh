#!/bin/bash

set -e

log_info() {
    echo -e "\033[0;32m$1\033[0m"  # Mensaje en verde
}

log_error() {
    echo -e "\033[0;31m$1\033[0m" >&2  # Mensaje en rojo
    exit 1
}
sudo rm /etc/apt/trusted.gpg.d/spotify.gpg
setup_os_dependencies() {
    log_info "*** Instalando dependencias del sistema operativo ***"
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS_ID=$ID
    else
        log_error "No se puede determinar el sistema operativo."
    fi

    if [[ "$OS_ID" =~ (debian|ubuntu) ]]; then
        apt update && apt install -y git curl
        curl -fsSL https://get.docker.com -o ~/get-docker.sh
        bash ~/get-docker.sh
    elif [[ "$OS_ID" =~ (rhel|almalinux|rocky|centos) ]]; then
        dnf check-update
        dnf config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
        dnf install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin git
        systemctl start docker
        systemctl enable docker
    else
        log_error "Distribución no soportada."
    fi

    ln -sf /usr/libexec/docker/cli-plugins/docker-compose /usr/bin/docker-compose
}

setup_os_dependencies
