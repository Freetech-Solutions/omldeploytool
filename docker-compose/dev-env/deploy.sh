#!/usr/bin/env bash
#
# Despliegue del entorno de desarrollo (dev-env).
#
# Uso:
#   ./deploy.sh [rama]
#
# Si se ejecuta desde una copia existente de omldeploytool, actualiza esa copia.
# Si no, clona el repositorio en ./omldeploytool (relativo al directorio actual).
#

set -Eeuo pipefail
IFS=$'\n\t'

REPO_URL="${OMLDEPLOYTOOL_REPO_URL:-https://gitlab.com/omnileads/omldeploytool.git}"
REPO_DIR="${OMLDEPLOYTOOL_DIR:-omldeploytool}"
BRANCH="${1:-main}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

compose_cmd=()

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

usage() {
  cat <<EOF
Uso: $(basename "$0") [rama]

Despliega el entorno de desarrollo OMniLeads (dev-env).

Argumentos:
  rama    Rama de omldeploytool a desplegar (default: main)

Variables de entorno:
  OMLDEPLOYTOOL_REPO_URL   URL del repositorio (default: $REPO_URL)
  OMLDEPLOYTOOL_DIR        Directorio destino del clone (default: $REPO_DIR)

Pasos:
  1. Clona o actualiza omldeploytool
  2. Checkout de la rama indicada
  3. Inicializa submódulos
  4. Ejecuta git_sanity.sh --list-submodules
  5. Copia oml_manage.sh y env -> dev-env/.env
  6. Ejecuta docker compose build
EOF
}

resolve_compose_cmd() {
  if docker compose version >/dev/null 2>&1; then
    compose_cmd=(docker compose)
  elif command -v docker-compose >/dev/null 2>&1; then
    compose_cmd=(docker-compose)
  else
    log_error "No se encontró 'docker compose' ni 'docker-compose'."
  fi
}

check_dependencies() {
  local missing=()
  for dep in git docker; do
    command -v "$dep" >/dev/null 2>&1 || missing+=("$dep")
  done
  (( ${#missing[@]} == 0 )) || log_error "Dependencias faltantes: ${missing[*]}"
  resolve_compose_cmd
}

resolve_repo_root() {
  if git -C "$SCRIPT_DIR" rev-parse --show-toplevel >/dev/null 2>&1 \
    && [[ -f "$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel)/.gitmodules" ]]; then
    git -C "$SCRIPT_DIR" rev-parse --show-toplevel
    return 0
  fi

  if [[ -d "$REPO_DIR/.git" ]]; then
    (cd "$REPO_DIR" && pwd)
    return 0
  fi

  echo "$REPO_DIR"
}

clone_or_update_repo() {
  local repo_root="$1"

  if [[ -d "$repo_root/.git" ]]; then
    log_info "Actualizando repositorio en $repo_root (rama: $BRANCH)"
    git -C "$repo_root" fetch --all --prune
    git -C "$repo_root" checkout "$BRANCH"
    if git -C "$repo_root" show-ref --verify --quiet "refs/remotes/origin/$BRANCH"; then
      git -C "$repo_root" reset --hard "origin/$BRANCH"
    fi
  else
    log_info "Clonando $REPO_URL (rama: $BRANCH) en $repo_root"
    git clone --branch "$BRANCH" --recurse-submodules "$REPO_URL" "$repo_root"
    return 0
  fi

  log_info "Inicializando submódulos"
  git -C "$repo_root" submodule sync --recursive
  git -C "$repo_root" submodule update --init --recursive
}

list_submodules() {
  local repo_root="$1"
  log_info "Estado de submódulos (git_sanity.sh --list-submodules)"
  (cd "$repo_root" && ./git_sanity.sh --list-submodules)
}

prepare_dev_env() {
  local repo_root="$1"
  local dev_env_dir="$2"

  log_info "Copiando oml_manage.sh y env a dev-env"
  cp "$repo_root/docker-compose/oml_manage.sh" "$dev_env_dir/oml_manage.sh"
  chmod +x "$dev_env_dir/oml_manage.sh"
  cp "$repo_root/docker-compose/env" "$dev_env_dir/.env"

  log_info "Ajustando variables para dev-env (set_dev_env.sh)"
  (cd "$dev_env_dir" && ./set_dev_env.sh)
}

build_stack() {
  local dev_env_dir="$1"

  log_info "Construyendo imágenes (docker compose build)"
  (cd "$dev_env_dir" && "${compose_cmd[@]}" build)
}

main() {
  case "${1:-}" in
    -h|--help)
      usage
      exit 0
      ;;
  esac

  check_dependencies

  local repo_root dev_env_dir
  repo_root="$(resolve_repo_root)"
  clone_or_update_repo "$repo_root"
  repo_root="$(cd "$repo_root" && pwd)"
  dev_env_dir="$repo_root/docker-compose/dev-env"

  [[ -f "$dev_env_dir/docker-compose.yml" ]] \
    || log_error "No se encontró docker-compose.yml en $dev_env_dir"

  list_submodules "$repo_root"
  prepare_dev_env "$repo_root" "$dev_env_dir"
  build_stack "$dev_env_dir"

  log_info "Despliegue de dev-env completado."
  log_info "Para levantar el stack: cd $dev_env_dir && ./oml_manage.sh up -d"
}

main "$@"
