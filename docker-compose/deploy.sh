#!/usr/bin/env bash
#
# Despliegue de una instancia por defecto del stack OMniLeads (Docker Compose).
#
# El modelo es de stack único: docker-compose/docker-compose-template.yml define
# todos los componentes y docker-compose/env las variables. Este script deja
# docker-compose/ listo para `./oml_manage.sh up -d`.
#
# Uso:
#   ./deploy.sh [rama]
#   ./deploy.sh --repo=github.com/Freetech-Solutions [rama]
#

set -Eeuo pipefail
IFS=$'\n\t'

REPO_DIR=""
DEPLOY_PATH=""
REPO_MIRROR=""
BRANCH="main"
NO_BUILD=0
USE_GITHUB_MIRROR=0
REPO_URL=""

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
Uso: $(basename "$0") [opciones] [rama]

Despliega una instancia por defecto del stack OMniLeads (stack único en
docker-compose/). Luego se ajusta docker-compose/.env según el escenario
(desarrollo, producción, edge o data externos — ver deploy.md).

Opciones:
  --repo=HOST/ORG   Usa mirror GitHub (ej: github.com/Freetech-Solutions)
  --path=DIR        Directorio base del clone (default: ./omldeploytool)
  --no-build        Omite docker compose build (solo prepara repo y .env)
  -h, --help        Muestra esta ayuda

Argumentos:
  rama              Rama a desplegar (default: main). Acepta --rama o rama.

Variables de entorno:
  OMLDEPLOYTOOL_DIR   Directorio destino del clone (si no se usa --path)

Ejemplos:
  $(basename "$0")
  $(basename "$0") --path=/tmp/
  $(basename "$0") develop-3.0
  $(basename "$0") --no-build --develop-3.0
  $(basename "$0") --repo=github.com/Freetech-Solutions --path=/tmp/ --no-build
  $(basename "$0") --repo=github.com/Freetech-Solutions develop-3.0

Pasos:
  1. Clona o actualiza omldeploytool
  2. Checkout de la rama indicada (+ reescritura de .gitmodules si --repo)
  3. Inicializa submódulos
  4. Ejecuta git_sanity.sh --list-submodules
  5. Genera docker-compose/docker-compose.yml y .env desde las plantillas
  6. Ejecuta docker compose build (omitido con --no-build)
EOF
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -h|--help)
        usage
        exit 0
        ;;
      --repo=*)
        REPO_MIRROR="${1#--repo=}"
        shift
        ;;
      --repo)
        [[ $# -ge 2 ]] || log_error "Falta valor para --repo"
        REPO_MIRROR="$2"
        shift 2
        ;;
      --path=*)
        DEPLOY_PATH="${1#--path=}"
        shift
        ;;
      --path)
        [[ $# -ge 2 ]] || log_error "Falta valor para --path"
        DEPLOY_PATH="$2"
        shift 2
        ;;
      --no-build)
        NO_BUILD=1
        shift
        ;;
      --no-build=*)
        log_error "Opción desconocida: $1"
        ;;
      --*)
        BRANCH="${1#--}"
        shift
        ;;
      *)
        BRANCH="$1"
        shift
        ;;
    esac
  done
}

configure_deploy_path() {
  if [[ -n "$DEPLOY_PATH" ]]; then
    DEPLOY_PATH="${DEPLOY_PATH%/}"
    [[ -n "$DEPLOY_PATH" ]] || log_error "El valor de --path no puede estar vacío"
    if [[ "$(basename "$DEPLOY_PATH")" == "omldeploytool" ]]; then
      REPO_DIR="$DEPLOY_PATH"
    else
      REPO_DIR="${DEPLOY_PATH}/omldeploytool"
    fi
  else
    REPO_DIR="${OMLDEPLOYTOOL_DIR:-omldeploytool}"
  fi
}

configure_repo_url() {
  if [[ -n "$REPO_MIRROR" ]]; then
    REPO_MIRROR="${REPO_MIRROR#https://}"
    REPO_MIRROR="${REPO_MIRROR#http://}"
    REPO_MIRROR="${REPO_MIRROR%/}"
    REPO_URL="https://${REPO_MIRROR}/omldeploytool.git"
    USE_GITHUB_MIRROR=1
  else
    REPO_URL="${OMLDEPLOYTOOL_REPO_URL:-https://gitlab.com/omnileads/omldeploytool.git}"
    USE_GITHUB_MIRROR=0
  fi
}

sed_inplace() {
  if sed --version >/dev/null 2>&1; then
    sed -i "$@"
  else
    sed -i '' "$@"
  fi
}

gitlab_down_message() {
  cat >&2 <<EOF
ERROR: GitLab no está disponible (caído o no se puede resolver la URL).

Reintentá con el mirror de GitHub:
  ./deploy.sh --repo=github.com/Freetech-Solutions${BRANCH:+ $BRANCH}
EOF
  exit 1
}

check_gitlab_available() {
  local url="$1"
  if ! git ls-remote --heads "$url" >/dev/null 2>&1; then
    gitlab_down_message
  fi
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
  command -v git >/dev/null 2>&1 || missing+=(git)
  if [[ "$NO_BUILD" -eq 0 ]]; then
    command -v docker >/dev/null 2>&1 || missing+=(docker)
    resolve_compose_cmd
  fi
  (( ${#missing[@]} == 0 )) || log_error "Dependencias faltantes: ${missing[*]}"
}

resolve_repo_root() {
  if [[ -z "$DEPLOY_PATH" ]]; then
    if git -C "$SCRIPT_DIR" rev-parse --show-toplevel >/dev/null 2>&1 \
      && [[ -f "$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel)/.gitmodules" ]]; then
      git -C "$SCRIPT_DIR" rev-parse --show-toplevel
      return 0
    fi
  fi

  if [[ -d "$REPO_DIR/.git" ]]; then
    (cd "$REPO_DIR" && pwd)
    return 0
  fi

  echo "$REPO_DIR"
}

rewrite_gitmodules_for_mirror() {
  local repo_root="$1"

  [[ -f "$repo_root/.gitmodules" ]] || log_error "No se encontró .gitmodules en $repo_root"

  log_info "Reescribiendo .gitmodules -> ${REPO_MIRROR}"
  sed_inplace "s|gitlab.com/omnileads|${REPO_MIRROR}|g" "$repo_root/.gitmodules"
  sed_inplace "s|^url = \\([a-zA-Z0-9_.-]*\\.git\\)|url = https://${REPO_MIRROR}/\\1|" "$repo_root/.gitmodules"
}

init_submodules() {
  local repo_root="$1"

  log_info "Inicializando submódulos"
  git -C "$repo_root" submodule sync --recursive
  if ! git -C "$repo_root" submodule update --init --recursive; then
    if [[ "$USE_GITHUB_MIRROR" -eq 0 ]]; then
      gitlab_down_message
    fi
    log_error "No se pudieron inicializar los submódulos desde $REPO_URL"
  fi
}

clone_or_update_repo() {
  local repo_root="$1"

  if [[ -d "$repo_root/.git" ]]; then
    log_info "Actualizando repositorio en $repo_root (rama: $BRANCH)"
    if [[ "$USE_GITHUB_MIRROR" -eq 1 ]]; then
      git -C "$repo_root" remote set-url origin "$REPO_URL"
    else
      check_gitlab_available "$REPO_URL"
    fi

    if ! git -C "$repo_root" fetch --all --prune; then
      [[ "$USE_GITHUB_MIRROR" -eq 0 ]] && gitlab_down_message
      log_error "No se pudo hacer fetch desde $REPO_URL"
    fi

    git -C "$repo_root" checkout "$BRANCH"
    if git -C "$repo_root" show-ref --verify --quiet "refs/remotes/origin/$BRANCH"; then
      git -C "$repo_root" reset --hard "origin/$BRANCH"
    fi

    if [[ "$USE_GITHUB_MIRROR" -eq 1 ]]; then
      rewrite_gitmodules_for_mirror "$repo_root"
    fi
  else
    if [[ "$USE_GITHUB_MIRROR" -eq 0 ]]; then
      check_gitlab_available "$REPO_URL"
    fi

    log_info "Clonando $REPO_URL (rama: $BRANCH) en $repo_root"
    mkdir -p "$(dirname "$repo_root")"
    if ! git clone --branch "$BRANCH" "$REPO_URL" "$repo_root"; then
      if [[ "$USE_GITHUB_MIRROR" -eq 0 ]]; then
        gitlab_down_message
      fi
      log_error "No se pudo clonar desde $REPO_URL"
    fi

    if [[ "$USE_GITHUB_MIRROR" -eq 1 ]]; then
      rewrite_gitmodules_for_mirror "$repo_root"
    fi
  fi

  init_submodules "$repo_root"
}

list_submodules() {
  local repo_root="$1"
  log_info "Estado de submódulos (git_sanity.sh --list-submodules)"
  (cd "$repo_root" && ./git_sanity.sh --list-submodules)
}

prepare_instance() {
  local repo_root="$1"
  local compose_dir="$2"

  log_info "Generando docker-compose.yml y .env desde las plantillas"
  # rm previo: no escribir a través de symlinks preexistentes
  rm -f "$compose_dir/docker-compose.yml" "$compose_dir/.env"
  cp "$repo_root/docker-compose/docker-compose-template.yml" "$compose_dir/docker-compose.yml"
  cp "$repo_root/docker-compose/env" "$compose_dir/.env"
  chmod +x "$compose_dir/oml_manage.sh"
}

build_stack() {
  local compose_dir="$1"

  log_info "Construyendo imágenes (docker compose build)"
  (cd "$compose_dir" && "${compose_cmd[@]}" build)
}

main() {
  parse_args "$@"
  configure_deploy_path
  configure_repo_url
  check_dependencies

  local repo_root compose_dir
  repo_root="$(resolve_repo_root)"
  log_info "Directorio destino: $repo_root"
  clone_or_update_repo "$repo_root"
  repo_root="$(cd "$repo_root" && pwd)"
  compose_dir="$repo_root/docker-compose"

  [[ -f "$compose_dir/docker-compose-template.yml" ]] \
    || log_error "No se encontró docker-compose-template.yml en $compose_dir"
  [[ -f "$compose_dir/env" ]] \
    || log_error "No se encontró env en $compose_dir"

  list_submodules "$repo_root"
  prepare_instance "$repo_root" "$compose_dir"

  if [[ "$NO_BUILD" -eq 0 ]]; then
    build_stack "$compose_dir"
  else
    log_info "Omitiendo docker compose build (--no-build)"
  fi

  log_info "Despliegue preparado en $compose_dir"
  log_info "Para levantar el stack: cd $compose_dir && ./oml_manage.sh up -d"
  log_info "Luego: ./oml_manage.sh reset-pass (admin/admin)"
  if [[ "$NO_BUILD" -ne 0 ]]; then
    log_info "Recordá construir antes: docker compose build"
  fi
}

main "$@"
