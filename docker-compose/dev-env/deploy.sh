#!/bin/bash

set -e

# Colores para mensajes
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Función para mostrar mensajes de error
function error_exit {
  echo -e "${RED}[ERROR] $1${NC}"
  exit 1
}

# Función para mostrar mensajes de advertencia
function warning_msg {
    echo -e "${YELLOW}[WARN] $1${NC}"
}

# Función para clonar un repositorio
function clone_repo {
  local repo_name=$1
  local repo_path=$2

  if [ ! -d "$repo_path" ]; then
    if [ "$gitlab_clone" == "ssh" ]; then
      git clone git@gitlab.com:omnileads/"$repo_name".git "$repo_path" || error_exit "Failed to clone $repo_name"
    else
      git clone https://gitlab.com/omnileads/"$repo_name".git "$repo_path" || error_exit "Failed to clone $repo_name"
    fi
    echo -e "${GREEN}[INFO] Cloned $repo_name${NC}"
  else
    echo -e "${YELLOW}[INFO] $repo_name already exists. Skipping clone.${NC}"
  fi
}

# Función para preparar el directorio omnileads-repos
function prepare_dir {
  local dir_name="omnileads-repos"

  if [ -d "$dir_name" ]; then
    rm -rf "$dir_name" || error_exit "Failed to remove existing $dir_name"
  fi
  mkdir "$dir_name" || error_exit "Failed to create $dir_name"
  cd "$dir_name" || error_exit "Failed to enter $dir_name"
}

# Función para hacer checkout de una rama, con manejo de errores
function checkout_branch {
  local repo_name="$1"
  local branch_name="$2"

  if [[ -d "$repo_name" ]]; then
    cd "$repo_name" || error_exit "Failed to enter $repo_name directory."

    if git show-ref --verify --quiet refs/heads/"$branch_name" || git show-ref --verify --quiet refs/remotes/origin/"$branch_name"; then
      git checkout "$branch_name" || error_exit "Failed to checkout branch $branch_name in $repo_name."
    else
      warning_msg "Branch '$branch_name' not found in '$repo_name'. Skipping checkout."
    fi
    cd ..
  else
    warning_msg "Repository '$repo_name' not found. Skipping checkout."
  fi
}


# Función principal de despliegue
function deploy {
  prepare_dir

  echo "***[OML devenv] Cloning the repositories of modules"

  # Lista de repositorios
  local main_repos=("omlacd" "omlkamailio" "omlnginx" "omlpgsql" "omlrtpengine" "omlfastagi" "omlami" "oml_interactions_processor" "oml_sentiment_analysis" "omnileads-websockets" "ominicontacto" "acd_retrieve_conf" "omlqa" "omnidialer" "tel_call_logger")
  for repo in "${main_repos[@]}"; do
    if [ "$repo" == "ominicontacto" ]; then
      clone_repo "$repo" "omlapp"
    elif [ "$repo" == "omnileads-websockets" ]; then
      clone_repo "$repo" "omlwebsockets"
    else
      clone_repo "$repo" "$repo"
    fi
  done

  echo -e "${GREEN}[INFO] All repositories were cloned in $(pwd)${NC}"
  sleep 2

  # Checkout de ramas específicas
  local branch_repos=("omlacd" "omnidialer" "omlapp")
  local branch_name="oml-2679-dev-discador-oml"
  for repo in "${branch_repos[@]}"; do
    checkout_branch "$repo" "$branch_name"
  done

  cd ../..
  cp ../env .env || warning_msg "Could not copy .env file. Ensure it exists in the parent directory."
  docker-compose build || error_exit "docker-compose build failed."
  docker-compose up -d || error_exit "docker-compose up -d failed."

  echo -e "${GREEN}[INFO] Deployment finished.${NC}"
}

# Manejo de parámetros de entrada
function parse_arguments {
  for arg in "$@"; do
    case $arg in
      --gitlab_clone=ssh|--gitlab_clone=https)
        gitlab_clone="${arg#*=}"
        shift
        ;;
      --help|-h)
        echo "
Usage: $0 --gitlab_clone=<ssh|https>

Options:
  --gitlab_clone   Specify cloning method (ssh or https)
  --help           Show this help message
"
        exit 0
        ;;
      *)
        echo -e "${YELLOW}[INFO] Default parameters: --gitlab_clone=https${NC}"
        gitlab_clone="https"
        ;;
    esac
  done

  # Validar si se estableció `gitlab_clone`
  if [[ -z "$gitlab_clone" ]]; then
    error_exit "Missing --gitlab_clone parameter. Use --help for usage."
  fi
}

# Script principal
function main {
  parse_arguments "$@"
  deploy
}

main "$@"