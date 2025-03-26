#!/bin/bash

set -e

# Messages colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Show error messages
function error_exit {
  echo -e "${RED}[ERROR] $1${NC}"
  exit 1
}

# Show warning messages
function warning_msg {
  echo -e "${YELLOW}[WARN] $1${NC}"
}

# Clone repos function
function clone_repo {
  local repo_name=$1
  local repo_path=$2

  if [ ! -d "$repo_path" ]; then
    local clone_command
    if [ "$gitlab_clone" == "ssh" ]; then
      clone_command="git clone git@gitlab.com:omnileads/${repo_name}.git ${repo_path}"
    else
      clone_command="git clone https://gitlab.com/omnileads/${repo_name}.git ${repo_path}"
    fi
    eval "$clone_command" || error_exit "Failed to clone $repo_name"
    echo -e "${GREEN}[INFO] Cloned $repo_name${NC}"
  else
    echo -e "${YELLOW}[INFO] $repo_name already exists. Skipping clone.${NC}"
  fi
}

# Prepare omnileads-repos directory
function prepare_dir {
  local dir_name="omnileads-repos"
  if [ -d "$dir_name" ]; then
    rm -rf "$dir_name" || error_exit "Failed to remove existing $dir_name"
  fi
  mkdir "$dir_name" || error_exit "Failed to create $dir_name"
  cd "$dir_name" || error_exit "Failed to enter $dir_name"
}

# Wait devenv up function
function wait_for_environment {
  echo -e "${YELLOW}[INFO] Waiting for the environment to be up and running...${NC}"
  until curl -sk --head --request GET https://localhost | grep "302" > /dev/null; do
    echo -e "${YELLOW}[INFO] Environment still being installed, sleeping 60 seconds...${NC}"
    sleep 60
  done
  echo -e "${GREEN}[INFO] Environment is up and ready!${NC}"
}

# Build Vue.js function
function build_vuejs {
  echo -e "${YELLOW}[INFO] Building Vue.js project...${NC}"
  if docker ps --format '{{.Names}}' | grep -q "oml-vuejs-cli"; then
    docker exec -it oml-vuejs-cli npm install || error_exit "npm install failed"
    docker exec -it oml-vuejs-cli npm run build || error_exit "npm build failed"
    echo -e "${GREEN}[INFO] Vue.js project built successfully!${NC}"
  else
    error_exit "Vue.js container 'oml-vuejs-cli' is not running. Ensure it is available."
  fi
}

# main deploy function
function deploy {
  if [ ! -f ../env ]; then
    warning_msg "Could not find '../env' file. Ensure it exists in the parent directory."
  else
    cp ../env .env
    sed -i "s/ENV=docker/ENV=devenv/g" .env
  fi

  prepare_dir
  echo "***[OML devenv] Cloning the repositories of modules"

  # Repositories to clone
  local repos=(
    "omlacd" "omlkamailio" "omlnginx" "omlpgsql" "omlrtpengine" 
    "omlfastagi" "omlami" "oml_interactions_processor" "oml_sentiment_analysis"
    "omnileads-websockets" "ominicontacto" "acd_retrieve_conf"
    "omlqa" "omnidialer" "tel_call_logger"
  )
  for repo in "${repos[@]}"; do
    case $repo in
      "ominicontacto") clone_repo "$repo" "omlapp" ;;
      "omnileads-websockets") clone_repo "$repo" "omlwebsockets" ;;
      *) clone_repo "$repo" "$repo" ;;
    esac
  done

  echo -e "${GREEN}[INFO] All repositories were cloned in $(pwd)${NC}"
  sleep 2

  docker-compose build || error_exit "docker-compose build failed."
  docker-compose up -d || error_exit "docker-compose up -d failed."

  echo -e "${GREEN}[INFO] Deployment finished.${NC}"
}

# input parameters management
function parse_arguments {
  for arg in "$@"; do
    case $arg in
      --gitlab_clone=ssh|--gitlab_clone=https)
        gitlab_clone="${arg#*=}"
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
        error_exit "Invalid parameter: $arg. Allowed values are '--gitlab_clone=<ssh|https>'"
        ;;
    esac
  done

  # check `gitlab_clone` argument
  if [[ "$gitlab_clone" != "ssh" && "$gitlab_clone" != "https" ]]; then
    error_exit "Invalid value for --gitlab_clone. Allowed values are 'ssh' or 'https'."
  fi
}

# main Script
function main {
  parse_arguments "$@"
  deploy
  wait_for_environment
  build_vuejs
}

main "$@"
