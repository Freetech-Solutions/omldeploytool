#!/bin/bash

set -e

######################################################
####################  NETWORKING #####################
######################################################

# Check if either NIC or DOCKER_ENGINE_IPV4 is provided
if [[ -z "$NIC" && -z "$DOCKER_ENGINE_IPV4" ]]; then
    echo "Error: You must to pass NIC or DOCKER_ENGINE_IPV4 as argument." >&2
    exit 1
fi

oml_nic=${NIC}
docker_engine_ip=${DOCKER_ENGINE_IPV4}
wan_addr=${NAT_IPV4}

######################################################
###################### STAGE #########################
######################################################

env=docker

# --- branch is about specific omnileads release
branch=${BRANCH:-main}  # Default to "main" if not specified

######################################################
##### External Object Storage Bucket integration #####
######################################################
bucket_url=${BUCKET_URL}
bucket_access_key=${BUCKET_ACCESS_KEY}
bucket_secret_key=${BUCKET_SECRET_KEY}
bucket_region=${BUCKET_REGION}
bucket_name=${BUCKET_NAME}

# External PostgreSQL engine integration
postgres_host=${PGSQL_HOST}
postgres_port=${PGSQL_PORT}
postgres_user=${PGSQL_USER}
postgres_password=${PGSQL_PASSWORD}
postgres_db=${PGDATABASE}

######################################################
###################### FUNC ##########################
######################################################

log_info() {
    echo -e "\033[0;32m$1\033[0m"  # Mensaje en verde
}

log_error() {
    echo -e "\033[0;31m$1\033[0m" >&2  # Mensaje en rojo
    exit 1
}

disable_firewalls() {
    log_info "*** Checking and disabling firewall services ***"
    
    # Check for UFW (Debian/Ubuntu)
    if command -v ufw &> /dev/null; then
        if systemctl is-active --quiet ufw; then
            log_info "UFW is active. Disabling..."
            systemctl stop ufw
            systemctl disable ufw
            ufw disable
            log_info "UFW has been disabled"
        else
            log_info "UFW is installed but not active"
        fi
    fi
    
    # Check for FirewallD (RHEL/CentOS/Fedora)
    if command -v firewall-cmd &> /dev/null; then
        if systemctl is-active --quiet firewalld; then
            log_info "FirewallD is active. Disabling..."
            systemctl stop firewalld
            systemctl disable firewalld
            log_info "FirewallD has been disabled"
        else
            log_info "FirewallD is installed but not active"
        fi
    fi
    
    # Check iptables as fallback
    if command -v iptables &> /dev/null; then
        log_info "Clearing any iptables rules..."
        iptables -F
        log_info "iptables rules cleared"
    fi
}

setup_networking() {
    log_info "*** Network settings ***"
    if [[ -z "$docker_engine_ip" ]]; then
        docker_engine_ip=$(ip addr show "$oml_nic" | grep "inet\b" | awk '{print $2}' | cut -d/ -f1) || log_error "No se pudo obtener la dirección privada."
    else
        docker_engine_ip="$docker_engine_ip"
    fi

    if [[ -z "$wan_addr" ]]; then
        wan_addr=$(curl -s http://ipinfo.io/ip) || log_error "No se pudo obtener la dirección pública."
    fi
}

setup_os_dependencies() {
    log_info "*** Install docker and others dependencies ***"
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
        log_error "Linux distro not found. Please install Docker manually."
    fi

    ln -sf /usr/libexec/docker/cli-plugins/docker-compose /usr/bin/docker-compose
}

deploy_omnileads() {
    log_info "Cloning the OML deploy tool repository"
    git clone https://gitlab.com/omnileads/omldeploytool.git || log_error "Error al clonar el repositorio."

    cd omldeploytool || log_error "Canot access the 'omldeploytool' directory."
    
    if [[ "$branch" != "main" ]]; then
        git checkout "$branch" || log_error "Error al cambiar a la rama '$branch'."
    fi
    
    cp docker-compose/oml_manage /usr/local/bin/oml_manage
    cd docker-compose/prod-env || log_error "Canot access the 'prod-env' directory."

    cp ../env ./.env
    sed -i "s/ENV=devenv/ENV=${env}/g" .env
    sed -i "s/OML_HOSTNAME=/OML_HOSTNAME=${docker_engine_ip}/g" .env
    sed -i "s/PUBLIC_IP=/PUBLIC_IP=${wan_addr}/g" .env
    sed -i "s/ASTERISK_HOSTNAME=acd/ASTERISK_HOSTNAME=${docker_engine_ip}/g" .env
    sed -i "s/FASTAGI_HOSTNAME=fastagi/FASTAGI_HOSTNAME=${docker_engine_ip}/g" .env
    sed -i "s/RTPENGINE_HOSTNAME=rtpengine/RTPENGINE_HOSTNAME=${docker_engine_ip}/g" .env
    sed -i "s/KAMAILIO_HOSTNAME=kamailio/KAMAILIO_HOSTNAME=${docker_engine_ip}/g" .env
    sed -i "s/https:\/\/localhost/https:\/\/${docker_engine_ip}/g" .env

    if [[ -n "$NAT_IPV4" ]]; then
        sed -i "s/#SIP_NAT_IPADDR/SIP_NAT_IPADDR/g" .env
        sed -i "s/#RTP_NAT_IPADDR/RTP_NAT_IPADDR/g" .env
    fi

    docker-compose up -d || log_error "Error while executing docker-compose up -d."
}

wait_for_env() {
    log_info "*** The environment is currently starting up. Please wait. ***"
    until curl -sk --head --request GET "https://${docker_engine_ip}" | grep "302" > /dev/null; do
        log_info "The system is in the process of starting up. Please wait ..."
        sleep 10
    done
    log_info "¡Deploy ready!"
}

reset_admin_password() {
    log_info "*** Password reset ***"
    /usr/local/bin/oml_manage --reset_pass || log_error "Error al resetear la contraseña de administrador."
}

######################################################
####################### EXEC #########################
######################################################

setup_networking
# Agregamos la función de deshabilitación de firewalls antes de la instalación
disable_firewalls
setup_os_dependencies
deploy_omnileads
wait_for_env
reset_admin_password