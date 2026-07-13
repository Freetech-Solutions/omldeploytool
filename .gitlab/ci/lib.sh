#!/bin/bash
# Resuelve CI_PROJECT_DIR en ruta absoluta (GitLab 12 SSH executor usa rutas relativas).
set -euo pipefail

_oml_ci_lib_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

oml_ci_init_paths() {
  local root="" candidate

  for candidate in \
    "${CI_PROJECT_DIR:-}" \
    "${HOME}/${CI_PROJECT_DIR:-}" \
    "$(pwd)" \
    "${_oml_ci_lib_dir}/../.."
  do
    [ -n "$candidate" ] || continue
    if [ -d "${candidate}/ansible" ]; then
      root="$(cd "$candidate" && pwd)"
      break
    fi
  done

  if [ -z "$root" ]; then
    echo "ERROR: no se encontró ansible/ (CI_PROJECT_DIR=${CI_PROJECT_DIR:-<unset>}, pwd=$(pwd))" >&2
    exit 1
  fi

  export CI_PROJECT_DIR="$root"
  export ANSIBLE_DIR="${root}/ansible"
  export OML_CI_CONFIG_DIR="${root}/.ci-omnileads"
  export PATH="${HOME}/.local/bin:/usr/local/bin:${PATH}"
  export PIP_CACHE_DIR="${root}/.cache/pip"
  export ANSIBLE_LOCAL_TEMP="${root}/.cache/ansible-local"
  export ANSIBLE_LOG_DIR="${root}/.cache/oml_install_logs"
  mkdir -p "$PIP_CACHE_DIR" "$ANSIBLE_LOCAL_TEMP" "$ANSIBLE_LOG_DIR"
}
