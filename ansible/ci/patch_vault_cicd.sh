#!/bin/bash
# Patch vault_tenant_test_aio_* keys in an encrypted vault.yml for ephemeral CI droplets.
set -euo pipefail

vault_file=""
ansible_host=""
omni_ip_lan=""
fqdn=""

usage() {
  cat <<'EOF'
Usage: patch_vault_cicd.sh --vault-file PATH --ansible-host IP --omni-ip-lan IP [--fqdn HOST]

Patches vault_tenant_test_aio_ansible_host, vault_tenant_test_aio_omni_ip_lan and
vault_tenant_test_aio_fqdn (defaults fqdn to ansible-host) in an Ansible Vault file.

Requires ANSIBLE_VAULT_PASSWORD_FILE (or vault_password_file in ansible.cfg).
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --vault-file)
      vault_file="$2"
      shift 2
      ;;
    --ansible-host)
      ansible_host="$2"
      shift 2
      ;;
    --omni-ip-lan)
      omni_ip_lan="$2"
      shift 2
      ;;
    --fqdn)
      fqdn="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

if [ -z "$vault_file" ] || [ -z "$ansible_host" ] || [ -z "$omni_ip_lan" ]; then
  echo "Missing required arguments." >&2
  usage >&2
  exit 1
fi

if [ -z "$fqdn" ]; then
  fqdn="$ansible_host"
fi

if [ ! -f "$vault_file" ]; then
  echo "Vault file not found: $vault_file" >&2
  exit 1
fi

ansible_dir="$(cd "$(dirname "$0")/.." && pwd)"
for venv_bin in "$ansible_dir/.ci-venv/bin" "$ansible_dir/venv/bin"; do
  if [ -f "${venv_bin}/ansible-vault" ]; then
    PATH="${venv_bin}:$PATH"
    break
  fi
done

resolve_vault_password_file() {
  if [ -n "${ANSIBLE_VAULT_PASSWORD_FILE:-}" ] && [ -f "${ANSIBLE_VAULT_PASSWORD_FILE}" ]; then
    return 0
  fi

  local vault_env="${ansible_dir}/../.ci-omnileads/vault.env"
  if [ -f "$vault_env" ]; then
    # shellcheck source=/dev/null
    source "$vault_env"
    if [ -n "${ANSIBLE_VAULT_PASSWORD_FILE:-}" ] && [ -f "${ANSIBLE_VAULT_PASSWORD_FILE}" ]; then
      return 0
    fi
  fi

  local candidate
  for candidate in \
    "${ansible_dir}/../.ci-omnileads/vault_pass" \
    "${HOME}/.config/omnileads/vault_pass"
  do
    if [ -f "$candidate" ]; then
      export ANSIBLE_VAULT_PASSWORD_FILE="$candidate"
      return 0
    fi
  done

  echo "ANSIBLE_VAULT_PASSWORD_FILE is not set or file is missing." >&2
  echo "Run .gitlab/ci/ansible-vault-setup.sh or set ANSIBLE_VAULT_PASSWORD in CI." >&2
  exit 1
}

resolve_vault_password_file
_vault_pass_file="${ANSIBLE_VAULT_PASSWORD_FILE}"
export ANSIBLE_CONFIG="${ansible_dir}/ansible.cfg"
# Evitar vault-id "default" duplicado (env + CLI) tras source vault.env en CI.
unset ANSIBLE_VAULT_PASSWORD_FILE ANSIBLE_VAULT_IDENTITY_LIST

tmp_file="$(mktemp)"
trap 'rm -f "$tmp_file"' EXIT

ansible-vault decrypt "$vault_file" --output "$tmp_file" --vault-password-file "$_vault_pass_file"

patch_var() {
  local key="$1"
  local value="$2"
  local file="$3"
  if grep -q "^${key}:" "$file"; then
    sed -i "s|^${key}:.*|${key}: \"${value}\"|" "$file"
  else
    printf '%s: "%s"\n' "$key" "$value" >> "$file"
  fi
}

patch_var vault_tenant_test_aio_ansible_host "$ansible_host" "$tmp_file"
patch_var vault_tenant_test_aio_omni_ip_lan "$omni_ip_lan" "$tmp_file"
patch_var vault_tenant_test_aio_fqdn "$fqdn" "$tmp_file"

ansible-vault encrypt "$tmp_file" --output "$vault_file" --vault-password-file "$_vault_pass_file"

echo "Patched vault tenant keys for CI: ansible_host=${ansible_host} omni_ip_lan=${omni_ip_lan} fqdn=${fqdn}"
