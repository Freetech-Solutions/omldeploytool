#!/bin/bash
#
# Deploy for CI/CD in DigitalOcean and other envs
#

set -Eeuo pipefail
IFS=$'\n\t'

########################################
# Logging & error handling
########################################
log_info()  { echo -e "\033[0;32m$1\033[0m"; }
log_warn()  { echo -e "\033[0;33m$1\033[0m"; }
log_error() { echo -e "\033[0;31m$1\033[0m" >&2; exit 1; }

on_error() {
  local code=$?
  echo -e "\033[0;31mFallo en la línea $LINENO ejecutando: '$BASH_COMMAND' (código $code)\033[0m" >&2
}
trap on_error ERR

# Requiere root
if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
  log_error "Este script debe ejecutarse como root."
fi

########################################
# Config
########################################
oml_nic=eth0

# Inputs opcionales por entorno (si no existen, se calculan)
docker_engine_ip=${DOCKER_ENGINE_IPV4:-}
wan_addr=${NAT_IPV4:-}

# Rama a desplegar
branch=main

# Comando compose elegido dinámicamente
compose_cmd=()

########################################
# Funciones
########################################
disable_firewalls() {
  log_info "*** Checking and disabling firewall services ***"

  # UFW (Debian/Ubuntu)
  if command -v ufw >/dev/null 2>&1; then
    systemctl stop ufw 2>/dev/null || true
    systemctl disable ufw 2>/dev/null || true
    ufw disable 2>/dev/null || true
    log_info "UFW desactivado (si estaba presente)."
  fi

  # FirewallD (RHEL-like)
  if command -v firewall-cmd >/dev/null 2>&1; then
    systemctl stop firewalld 2>/dev/null || true
    systemctl disable firewalld 2>/dev/null || true
    log_info "FirewallD desactivado (si estaba presente)."
  fi
}

setup_networking() {
  log_info "*** Network settings ***"

  if [[ -z "${docker_engine_ip:-}" ]]; then
    docker_engine_ip=$(
      ip -4 -o addr show "$oml_nic" | awk '{print $4}' | cut -d/ -f1 | head -n1
    ) || true
  fi
  [[ -z "${docker_engine_ip:-}" ]] && log_error "No se pudo obtener la IP privada en $oml_nic."

  if [[ -z "${wan_addr:-}" ]]; then
    # Intenta varios servicios, con HTTPS y timeout
    wan_addr=$(curl -fsS --max-time 5 https://api.ipify.org || true)
    [[ -z "${wan_addr:-}" ]] && wan_addr=$(curl -fsS --max-time 5 https://ifconfig.me || true)
    [[ -z "${wan_addr:-}" ]] && wan_addr=$(curl -fsS --max-time 5 https://ipinfo.io/ip || true)
  fi
  [[ -z "${wan_addr:-}" ]] && log_error "No se pudo obtener la IP pública."

  log_info "IP privada: ${docker_engine_ip}"
  log_info "IP pública (WAN): ${wan_addr}"
}

setup_os_dependencies() {
  log_info "*** Install docker and other dependencies ***"
  if [[ -f /etc/os-release ]]; then
    . /etc/os-release
    OS_ID=$ID
  else
    log_error "No se puede determinar el sistema operativo."
  fi

  if [[ "$OS_ID" =~ (debian|ubuntu) ]]; then
    apt-get update -y
    apt-get install -y git curl jq
    curl -fsSL --max-time 30 https://get.docker.com -o /tmp/get-docker.sh
    bash /tmp/get-docker.sh
  elif [[ "$OS_ID" =~ (rhel|almalinux|rocky|centos) ]]; then
    dnf -y check-update || true
    dnf config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
    dnf install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin git jq
    systemctl enable --now docker
  else
    log_error "Linux distro no soportada automáticamente. Instala Docker manualmente."
  fi

  # Elegir docker compose
  if docker compose version >/dev/null 2>&1; then
    compose_cmd=(docker compose)
  elif command -v docker-compose >/dev/null 2>&1; then
    compose_cmd=(docker-compose)
  else
    # Intentar crear symlink al plugin si existe en rutas comunes
    for p in \
      /usr/lib/docker/cli-plugins/docker-compose \
      /usr/libexec/docker/cli-plugins/docker-compose; do
      if [[ -x "$p" ]]; then
        ln -sf "$p" /usr/local/bin/docker-compose
        compose_cmd=(docker-compose)
        break
      fi
    done
    [[ ${#compose_cmd[@]} -eq 0 ]] && log_error "No se encontró ni 'docker compose' ni 'docker-compose'."
  fi

  log_info "Docker: $(docker --version)"
  if [[ "${compose_cmd[0]}" == "docker" ]]; then
    log_info "Compose: $(docker compose version)"
  else
    log_info "Compose: $(${compose_cmd[@]} version)"
  fi
}

deploy_omnileads() {
  log_info "Cloning the OML deploy tool repository"

  if [[ -d omldeploytool/.git ]]; then
    pushd omldeploytool >/dev/null
    git fetch --all --prune
    git checkout "$branch"
    git reset --hard "origin/$branch"
  else
    git clone --depth=1 --branch "$branch" https://gitlab.com/omnileads/omldeploytool.git
    pushd omldeploytool >/dev/null
  fi

  # Submódulos shallow para acelerar
  git submodule update --init --depth=1 --recursive

  # Instalar helper
  cp docker-compose/oml_manage.sh /usr/local/bin/oml_manage.sh
  chmod +x /usr/local/bin/oml_manage.sh

  # Preparar .env
  pushd docker-compose/prod-env >/dev/null
  cp ../env ./.env

  # Reemplazos robustos en .env (anclados y con delimitador '|')
  sed -i "s|^OML_HOSTNAME=.*$|OML_HOSTNAME=${docker_engine_ip}|" .env

  if grep -qE '^PUBLIC_IP=\${OML_HOSTNAME}$' .env; then
    sed -i "s|^PUBLIC_IP=\${OML_HOSTNAME}$|PUBLIC_IP=${wan_addr}|" .env
  else
    # Fallback: asegura que exista PUBLIC_IP
    if grep -qE '^PUBLIC_IP=' .env; then
      sed -i "s|^PUBLIC_IP=.*$|PUBLIC_IP=${wan_addr}|" .env
    else
      echo "PUBLIC_IP=${wan_addr}" >> .env
    fi
  fi

  # NAT opcional (fuerza valor, comente o no la línea original)
  if [[ -n "${NAT_IPV4:-}" ]]; then
    sed -i "s|^#\?SIP_NAT_IPADDR=.*$|SIP_NAT_IPADDR=${NAT_IPV4}|" .env
    sed -i "s|^#\?RTP_NAT_IPADDR=.*$|RTP_NAT_IPADDR=${NAT_IPV4}|" .env
  fi

  # Construir e iniciar
  bash set_img_local.sh

  "${compose_cmd[@]}" build
  "${compose_cmd[@]}" up -d

  popd >/dev/null   # docker-compose/prod-env
  popd >/dev/null   # omldeploytool
}

wait_for_env() {
  log_info "*** The environment is currently starting up. Please wait. ***"
  # Espera hasta ~10 minutos (60 * 10s)
  for i in {1..60}; do
    code=$(curl -sk -o /dev/null -w "%{http_code}" "https://${docker_engine_ip}" || echo 000)
    if [[ "$code" =~ ^(200|301|302|403)$ ]]; then
      log_info "Aplicación arriba con HTTP ${code}"
      return 0
    fi
    log_info "Aún no está listo (HTTP ${code}). Reintentando..."
    sleep 10
  done
  log_error "Timeout esperando el servicio web en https://${docker_engine_ip}"
}

########################################
# Ejecución
########################################
setup_networking
disable_firewalls
setup_os_dependencies
deploy_omnileads
wait_for_env
