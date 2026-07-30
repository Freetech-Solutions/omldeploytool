#!/bin/bash
# Patch vault tenant keys in an encrypted vault.yml for ephemeral CI droplets.
#
# Modes:
#   AIO (inventory_example_1): --ansible-host + --omni-ip-lan [--fqdn]
#   Edge+node (inventory_example_2): --node-ansible-host + --node-omni-ip-lan
#                                    + --edge-ansible-host + --edge-omni-ip-lan [--fqdn]
set -euo pipefail

vault_file=""
ansible_host=""
omni_ip_lan=""
fqdn=""
node_ansible_host=""
node_omni_ip_lan=""
edge_ansible_host=""
edge_omni_ip_lan=""

usage() {
  cat <<'EOF'
Usage:
  AIO (inventory_example_1):
    patch_vault_cicd.sh --vault-file PATH --ansible-host IP --omni-ip-lan IP [--fqdn HOST]

  Edge+node (inventory_example_2):
    patch_vault_cicd.sh --vault-file PATH \
      --node-ansible-host IP --node-omni-ip-lan IP \
      --edge-ansible-host IP --edge-omni-ip-lan IP \
      [--fqdn HOST]

AIO patches vault_tenant_test_aio_ansible_host, vault_tenant_test_aio_omni_ip_lan and
vault_tenant_test_aio_fqdn (defaults fqdn to ansible-host).

Edge+node patches vault_tenant_example_2_node_*, vault_tenant_example_2_edge_* and
vault_tenant_example_2_fqdn (defaults fqdn to edge ansible-host).

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
    --node-ansible-host)
      node_ansible_host="$2"
      shift 2
      ;;
    --node-omni-ip-lan)
      node_omni_ip_lan="$2"
      shift 2
      ;;
    --edge-ansible-host)
      edge_ansible_host="$2"
      shift 2
      ;;
    --edge-omni-ip-lan)
      edge_omni_ip_lan="$2"
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

edge_node_mode=0
if [ -n "$node_ansible_host" ] || [ -n "$node_omni_ip_lan" ] \
  || [ -n "$edge_ansible_host" ] || [ -n "$edge_omni_ip_lan" ]; then
  edge_node_mode=1
fi

if [ -z "$vault_file" ]; then
  echo "Missing required arguments." >&2
  usage >&2
  exit 1
fi

if [ "$edge_node_mode" -eq 1 ]; then
  if [ -z "$node_ansible_host" ] || [ -z "$node_omni_ip_lan" ] \
    || [ -z "$edge_ansible_host" ] || [ -z "$edge_omni_ip_lan" ]; then
    echo "Edge+node mode requires --node-ansible-host, --node-omni-ip-lan, --edge-ansible-host and --edge-omni-ip-lan." >&2
    usage >&2
    exit 1
  fi
  if [ -z "$fqdn" ]; then
    fqdn="$edge_ansible_host"
  fi
else
  if [ -z "$ansible_host" ] || [ -z "$omni_ip_lan" ]; then
    echo "Missing required arguments." >&2
    usage >&2
    exit 1
  fi
  if [ -z "$fqdn" ]; then
    fqdn="$ansible_host"
  fi
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

if [ "$edge_node_mode" -eq 1 ]; then
  patch_var vault_tenant_example_2_node_ansible_host "$node_ansible_host" "$tmp_file"
  patch_var vault_tenant_example_2_node_private_ip "$node_omni_ip_lan" "$tmp_file"
  patch_var vault_tenant_example_2_edge_ansible_host "$edge_ansible_host" "$tmp_file"
  patch_var vault_tenant_example_2_edge_private_ip "$edge_omni_ip_lan" "$tmp_file"
  patch_var vault_tenant_example_2_fqdn "$fqdn" "$tmp_file"
else
  patch_var vault_tenant_test_aio_ansible_host "$ansible_host" "$tmp_file"
  patch_var vault_tenant_test_aio_omni_ip_lan "$omni_ip_lan" "$tmp_file"
  patch_var vault_tenant_test_aio_fqdn "$fqdn" "$tmp_file"
fi

ansible-vault encrypt "$tmp_file" --output "$vault_file" --vault-password-file "$_vault_pass_file"

if [ "$edge_node_mode" -eq 1 ]; then
  echo "Patched vault tenant keys for CI (edge+node): node=${node_ansible_host}/${node_omni_ip_lan} edge=${edge_ansible_host}/${edge_omni_ip_lan} fqdn=${fqdn}"
else
  echo "Patched vault tenant keys for CI: ansible_host=${ansible_host} omni_ip_lan=${omni_ip_lan} fqdn=${fqdn}"
fi
