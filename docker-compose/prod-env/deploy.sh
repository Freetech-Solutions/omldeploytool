#!/bin/bash

set -e

######################################################
####################  NETWORKING #####################
######################################################

oml_nic=${NIC}
lan_addr=${PRIVATE_IP}
nat_addr=${NAT_IP}

######################################################
###################### STAGE #########################
######################################################

# --- "cloud" instance (access through public IP)
# --- "lan" instance (access through private IP)
# --- "nat" instance (access through Public NAT IP)    
# --- or "all" in order to access through all NICs
env=docker-compose

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

setup_networking() {
    log_info "*** Configurando direcciones de red ***"
    if [[ -z "$lan_addr" ]]; then
        lan_ipv4=$(ip addr show "$oml_nic" | grep "inet\b" | awk '{print $2}' | cut -d/ -f1) || log_error "No se pudo obtener la dirección privada."
    else
        lan_ipv4="$lan_addr"
    fi

    if [[ -z "$nat_addr" ]]; then
        nat_addr=$(curl -s http://ipinfo.io/ip) || log_error "No se pudo obtener la dirección pública."
    fi
}

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

deploy_omnileads() {
    log_info "*** Clonando y desplegando Omnileads ***"
    git clone https://gitlab.com/omnileads/omldeploytool.git || log_error "Error al clonar el repositorio."

    cd omldeploytool || log_error "No se pudo acceder al directorio 'omldeploytool'."
    
    if [[ "$branch" != "main" ]]; then
        git checkout "$branch" || log_error "Error al cambiar a la rama '$branch'."
    fi
    
    cp docker-compose/oml_manage /usr/local/bin/oml_manage
    cd docker-compose/prod-env || log_error "No se pudo acceder al directorio 'prod-env'."

    cp ../env ./.env
    sed -i "s/ENV=devenv/ENV=${env}/g" .env
    sed -i "s/PRIVATE_IP=/PRIVATE_IP=${lan_ipv4}/g" .env

    docker-compose up -d || log_error "Error al iniciar los contenedores con Docker Compose."
}

setup_iptables() {
    log_info "*** Configurando iptables y persistencia con rc.local ***"

    # Crear reglas de iptables
    iptables -t nat -A PREROUTING -p udp --dport 5060 -j DNAT --to-destination 10.22.22.99
    iptables -A FORWARD -p udp -d 10.22.22.99 --dport 5060 -j ACCEPT
    iptables -t nat -A PREROUTING -p udp --dport 40000:50000 -j DNAT --to-destination 10.22.22.99
    iptables -A FORWARD -p udp -d 10.22.22.99 --dport 40000:50000 -j ACCEPT
    iptables -t nat -A PREROUTING -p udp --dport 20000:30000 -j DNAT --to-destination 10.22.22.98
    iptables -A FORWARD -p udp -d 10.22.22.98 --dport 20000:30000 -j ACCEPT

    # Crear o modificar rc.local
    if [[ ! -f /etc/rc.local ]]; then
        echo -e "#!/bin/bash\nexit 0" > /etc/rc.local
        chmod +x /etc/rc.local
    fi

    # Añadir reglas a rc.local si no existen
    if ! grep -q "iptables -t nat -A PREROUTING -p udp --dport 5060" /etc/rc.local; then
        sed -i '/^exit 0$/i \
iptables -t nat -A PREROUTING -p udp --dport 5060 -j DNAT --to-destination 10.22.22.99\n\
iptables -A FORWARD -p udp -d 10.22.22.99 --dport 5060 -j ACCEPT\n\
iptables -t nat -A PREROUTING -p udp --dport 40000:50000 -j DNAT --to-destination 10.22.22.99\n\
iptables -A FORWARD -p udp -d 10.22.22.99 --dport 40000:50000 -j ACCEPT\n\
iptables -t nat -A PREROUTING -p udp --dport 20000:30000 -j DNAT --to-destination 10.22.22.98\n\
iptables -A FORWARD -p udp -d 10.22.22.98 --dport 20000:30000 -j ACCEPT' /etc/rc.local
        log_info "Reglas de iptables añadidas a rc.local."
    else
        log_info "Las reglas de iptables ya están configuradas en rc.local."
    fi
}

wait_for_env() {
    log_info "*** Esperando que el entorno se inicie ***"
    until curl -sk --head --request GET "https://${lan_ipv4}" | grep "302" > /dev/null; do
        log_info "El entorno aún se está inicializando, esperando 10 segundos..."
        sleep 10
    done
    log_info "¡Deploy ready!"
}

reset_admin_password() {
    log_info "*** Reseteando la contraseña de administrador ***"
    /usr/local/bin/oml_manage --reset_pass || log_error "Error al resetear la contraseña de administrador."
}

######################################################
####################### EXEC #########################
######################################################

setup_networking
setup_os_dependencies
deploy_omnileads
setup_iptables
wait_for_env
reset_admin_password
