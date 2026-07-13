#!/bin/bash
# Prepara vault.yml y ANSIBLE_VAULT_PASSWORD_FILE para jobs de deploy.
set -euo pipefail

_oml_ci_script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "${_oml_ci_script_dir}/lib.sh"
oml_ci_init_paths

CI_CONFIG_DIR="${OML_CI_CONFIG_DIR}"
VAULT_DEST="${ANSIBLE_DIR}/group_vars/all/vault.yml"
VAULT_PASS_FILE="${CI_CONFIG_DIR}/vault_pass"

mkdir -p "$CI_CONFIG_DIR"
chmod 700 "$CI_CONFIG_DIR"

resolve_vault_password_file() {
  if [ -n "${ANSIBLE_VAULT_PASSWORD:-}" ]; then
    printf '%s' "${ANSIBLE_VAULT_PASSWORD}" > "$VAULT_PASS_FILE"
    chmod 600 "$VAULT_PASS_FILE"
    export ANSIBLE_VAULT_PASSWORD_FILE="$VAULT_PASS_FILE"
    return 0
  fi

  if [ -n "${ANSIBLE_VAULT_PASSWORD_FILE:-}" ] && [ -f "${ANSIBLE_VAULT_PASSWORD_FILE}" ]; then
    export ANSIBLE_VAULT_PASSWORD_FILE
    return 0
  fi

  local runner_pass="${HOME}/.config/omnileads/vault_pass"
  if [ -f "$runner_pass" ]; then
    export ANSIBLE_VAULT_PASSWORD_FILE="$runner_pass"
    return 0
  fi

  echo "No Ansible Vault password found." >&2
  echo "Set GitLab CI variable ANSIBLE_VAULT_PASSWORD (masked) or install vault_pass on the runner." >&2
  exit 1
}

resolve_vault_file() {
  if [ -n "${ANSIBLE_VAULT_YML:-}" ] && [ -f "${ANSIBLE_VAULT_YML}" ]; then
    cp "${ANSIBLE_VAULT_YML}" "$VAULT_DEST"
    return 0
  fi

  local runner_vault="${OML_ANSIBLE_VAULT_FILE:-${HOME}/.config/omnileads/vault.yml}"
  if [ -f "$runner_vault" ]; then
    cp "$runner_vault" "$VAULT_DEST"
    return 0
  fi

  echo "No vault.yml source found." >&2
  echo "Set GitLab CI File variable ANSIBLE_VAULT_YML or place vault.yml on the runner." >&2
  exit 1
}

setup_tenant_certs() {
  local tenant="${OML_CI_TENANT_FOLDER:-gitlab}"
  local cert_dir="${ANSIBLE_DIR}/instances/${tenant}"
  mkdir -p "$cert_dir"

  local cert_src="" key_src=""
  local cert_alias="${OML_CI_CERT_FILE_NAME:-cert.pem}"
  local key_alias="${OML_CI_KEY_FILE_NAME:-key.pem}"

  if [ -n "${OML_CI_TENANT_CERT_PEM:-}" ] && [ -f "${OML_CI_TENANT_CERT_PEM}" ] \
    && [ -n "${OML_CI_TENANT_KEY_PEM:-}" ] && [ -f "${OML_CI_TENANT_KEY_PEM}" ]; then
    cert_src="${OML_CI_TENANT_CERT_PEM}"
    key_src="${OML_CI_TENANT_KEY_PEM}"
  else
    local runner_certs="${OML_CI_TENANT_CERTS:-${HOME}/.config/omnileads/instances/${tenant}}"
    for cert_name in cert.pem FTS_Sephir_cert.pem "${cert_alias}"; do
      if [ -f "${runner_certs}/${cert_name}" ]; then
        cert_src="${runner_certs}/${cert_name}"
        break
      fi
    done
    for key_name in key.pem FTS_Sephir_key.pem "${key_alias}"; do
      if [ -f "${runner_certs}/${key_name}" ]; then
        key_src="${runner_certs}/${key_name}"
        break
      fi
    done
  fi

  if [ -z "$cert_src" ] || [ -z "$key_src" ]; then
    echo "WARNING: TLS certs not found for CI tenant ${tenant} (custom certs expected)." >&2
    return 0
  fi

  cp "$cert_src" "${cert_dir}/cert.pem"
  cp "$key_src" "${cert_dir}/key.pem"
  chmod 644 "${cert_dir}/cert.pem"
  chmod 600 "${cert_dir}/key.pem"

  if [ "$cert_alias" != "cert.pem" ]; then
    cp "${cert_dir}/cert.pem" "${cert_dir}/${cert_alias}"
  fi
  if [ "$key_alias" != "key.pem" ]; then
    cp "${cert_dir}/key.pem" "${cert_dir}/${key_alias}"
    chmod 600 "${cert_dir}/${key_alias}"
  fi

  echo "Tenant TLS certs ready: ${cert_dir}/cert.pem ${cert_dir}/key.pem"
}

resolve_vault_password_file
resolve_vault_file
setup_tenant_certs

cat > "${CI_CONFIG_DIR}/vault.env" <<EOF
export ANSIBLE_VAULT_PASSWORD_FILE='${ANSIBLE_VAULT_PASSWORD_FILE}'
EOF
chmod 600 "${CI_CONFIG_DIR}/vault.env"

VAULT_BIN="${ANSIBLE_DIR}/.ci-venv/bin/ansible-vault"
if [ ! -x "$VAULT_BIN" ]; then
  VAULT_BIN="$(command -v ansible-vault)"
fi

"$VAULT_BIN" view "$VAULT_DEST" >/dev/null
echo "Vault ready: $VAULT_DEST"
