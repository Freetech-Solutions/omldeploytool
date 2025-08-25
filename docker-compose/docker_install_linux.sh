#!/bin/bash

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
