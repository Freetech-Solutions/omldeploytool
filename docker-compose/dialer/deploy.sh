#!/bin/bash

set -e

######################################################
####################### HELP #########################
######################################################
function show_help {
    echo "Usage: PSQL_PASSWORD=<password> OML_IP=<ip> PRIVATE_IP=<ip> PUBLIC_IP=<ip> ./script.sh"
    echo ""
    echo "This script deploys the OmniLeads dialer environment."
    echo ""
    echo "Required environment variables:"
    echo "  PSQL_PASSWORD       PostgreSQL database password"
    echo "  OML_IP              OmniLeads server IP"
    echo "  PRIVATE_IP          Private IP address for networking"
    echo "  PUBLIC_IP           Public IP address for networking"
    echo ""
    echo "Optional environment variables (default values are provided):"
    echo "  SIP_NAT_MODE        SIP NAT mode (default: private)"
    echo "  PGSQL_HOST          PostgreSQL host (default: OML_IP)"
    echo "  PGSQL_PORT          PostgreSQL port (default: 5432)"
    echo "  PGDATABASE          PostgreSQL database name (default: omnileads)"
    echo "  PGSQL_USER          PostgreSQL user (default: omnileads)"
    echo "  BRANCH              Git branch to deploy (default: main)"
    echo ""
    exit 0
}

######################################################
############### VALIDATION & ENV VARIABLES ###########
######################################################
# Validating required environment variables
function validate_params {
    local missing_vars=()

    [[ -z "$PSQL_PASSWORD" ]] && missing_vars+=("PSQL_PASSWORD")
    [[ -z "$OML_IP" ]] && missing_vars+=("OML_IP")
    [[ -z "$PRIVATE_IP" ]] && missing_vars+=("PRIVATE_IP")
    [[ -z "$PUBLIC_IP" ]] && missing_vars+=("PUBLIC_IP")

    if [[ ${#missing_vars[@]} -gt 0 ]]; then
        echo -e "\033[0;31m[ERROR] Missing required environment variables:\033[0m ${missing_vars[*]}"
        echo "Use --help for more information."
        exit 1
    fi
}

# Load environment variables with defaults
oml_hostname=${OML_IP}
lan_addr=${PRIVATE_IP}
wan_addr=${PUBLIC_IP}
sip_nat_mode=${SIP_NAT_MODE:-private}

branch=${BRANCH:-main}  # Default to "main" if not specified

# PostgreSQL settings with defaults
postgres_host=${PGSQL_HOST:-$oml_hostname}
postgres_port=${PGSQL_PORT:-5432}
postgres_db=${PGDATABASE:-omnileads}
postgres_user=${PGSQL_USER:-omnileads}
postgres_password=${PSQL_PASSWORD}

######################################################
###################### FUNC ##########################
######################################################
log_info() {
    echo -e "\033[0;32m$1\033[0m"  # Green log message
}

log_error() {
    echo -e "\033[0;31m$1\033[0m" >&2  # Red log message
    exit 1
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

    docker network create -d bridge --subnet=22.22.22.0/24 oml_omnileads || true
}

deploy_omnileads() {
    log_info "Cloning the OML deploy tool repository"
    git clone https://gitlab.com/omnileads/omldeploytool.git || log_error "Error cloning repository."

    cd omldeploytool || log_error "Cannot access the 'omldeploytool' directory."
    
    if [[ "$branch" != "main" ]]; then
        git checkout "$branch" || log_error "Error switching to branch '$branch'."
    fi
    
    cd docker-compose/dialer || log_error "Cannot access the 'dialer' directory."

    cp ./env ./.env
    sed -i "s/PRIVATE_IP_DOCKER_ENGINE=/PRIVATE_IP_DOCKER_ENGINE=${lan_addr}/g" .env
    sed -i "s/PUBLIC_IP_DOCKER_ENGINE=/PUBLIC_IP_DOCKER_ENGINE=${wan_addr}/g" .env
    sed -i "s/SIP_NAT_MODE=/SIP_NAT_MODE=${sip_nat_mode}/g" .env    
    sed -i "s/\([A-Z_]*_SERVER\)=.*/\1=${oml_hostname}/g" .env

    docker-compose up -d || log_error "Error while executing docker-compose up -d."
}

######################################################
####################### EXEC #########################
######################################################
# Show help if --help is passed
if [[ "$1" == "--help" ]]; then
    show_help
fi

validate_params
setup_os_dependencies
deploy_omnileads
