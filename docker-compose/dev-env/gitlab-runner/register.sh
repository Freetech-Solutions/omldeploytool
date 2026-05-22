#!/bin/sh
set -eu

GITLAB_URL="${GITLAB_URL:-http://gitlab}"
GITLAB_ROOT_TOKEN="${GITLAB_ROOT_TOKEN:-glpat-oml-local-gitlab-root}"
RUNNER_CONFIG_DIR="${RUNNER_CONFIG_DIR:-/etc/gitlab-runner}"
RUNNER_CONFIG="${RUNNER_CONFIG_DIR}/config.toml"
TEMPLATE="/register/config.toml.template"
RUNNER_DESCRIPTION="${RUNNER_DESCRIPTION:-local-docker-dind}"
MAX_WAIT="${MAX_WAIT:-600}"

log() {
  printf '[gitlab-runner-register] %s\n' "$*"
}

wait_for_gitlab() {
  elapsed=0
  log "Esperando GitLab en ${GITLAB_URL} (max ${MAX_WAIT}s)..."
  while [ "$elapsed" -lt "$MAX_WAIT" ]; do
    if curl -sf "${GITLAB_URL}/-/readiness" >/dev/null 2>&1; then
      log "GitLab listo."
      return 0
    fi
    sleep 5
    elapsed=$((elapsed + 5))
  done
  log "ERROR: GitLab no respondió a tiempo."
  exit 1
}

runner_token_from_config() {
  if [ ! -f "${RUNNER_CONFIG}" ]; then
    return 1
  fi
  # shellcheck disable=SC2002
  token=$(grep -E '^\s*token\s*=' "${RUNNER_CONFIG}" | head -n1 | sed -E "s/^[[:space:]]*token[[:space:]]*=[[:space:]]*['\"]?([^'\"]+)['\"]?.*/\1/")
  case "${token}" in
    glrt-*|GR1348941*) printf '%s' "${token}"; return 0 ;;
    *) return 1 ;;
  esac
}

verify_runner_token() {
  token="$1"
  # Verificar que el runner puede autenticarse contra GitLab.
  http_code=$(curl -s -o /dev/null -w '%{http_code}' \
    --request POST "${GITLAB_URL}/api/v4/runners/verify" \
    --form "token=${token}" 2>/dev/null || printf '000')
  [ "${http_code}" = "200" ] || [ "${http_code}" = "201" ]
}

create_runner_token() {
  log "Creando runner authentication token via API..."
  response=$(curl -sf --request POST "${GITLAB_URL}/api/v4/user/runners" \
    --header "PRIVATE-TOKEN: ${GITLAB_ROOT_TOKEN}" \
    --form "runner_type=instance_type" \
    --form "description=${RUNNER_DESCRIPTION}" \
    --form "tag_list=docker,dind" \
    --form "run_untagged=true" \
    --form "locked=false") || {
    log "ERROR: no se pudo crear el runner. ¿El token root PAT es válido?"
    exit 1
  }

  # Respuesta JSON: {"id":...,"token":"glrt-...","token_expires_at":null}
  runner_token=$(printf '%s' "${response}" | sed -n 's/.*"token":"\([^"]*\)".*/\1/p')
  if [ -z "${runner_token}" ]; then
    log "ERROR: respuesta inesperada de la API: ${response}"
    exit 1
  fi
  printf '%s' "${runner_token}"
}

write_config() {
  runner_token="$1"
  mkdir -p "${RUNNER_CONFIG_DIR}"
  sed "s/__RUNNER_TOKEN__/${runner_token}/g" "${TEMPLATE}" > "${RUNNER_CONFIG}.tmp"
  mv "${RUNNER_CONFIG}.tmp" "${RUNNER_CONFIG}"
  chmod 600 "${RUNNER_CONFIG}"
  log "config.toml escrito en ${RUNNER_CONFIG}"
}

main() {
  wait_for_gitlab

  if existing_token=$(runner_token_from_config 2>/dev/null); then
    if verify_runner_token "${existing_token}"; then
      log "Runner ya registrado y token válido; omitiendo registro."
      exit 0
    fi
    log "Token existente inválido; registrando de nuevo..."
  fi

  runner_token=$(create_runner_token)
  write_config "${runner_token}"
  log "Registro completado."
}

main "$@"
