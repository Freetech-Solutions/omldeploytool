#!/bin/bash
set -euo pipefail

ANSIBLE_DIR="$(cd "$(dirname "$0")" && pwd)"

if [ -f "$ANSIBLE_DIR/.ci-venv/bin/activate" ]; then
  # shellcheck source=/dev/null
  source "$ANSIBLE_DIR/.ci-venv/bin/activate"
elif [ -f "$ANSIBLE_DIR/venv/bin/activate" ]; then
  # shellcheck source=/dev/null
  source "$ANSIBLE_DIR/venv/bin/activate"
fi

if ! command -v ansible-playbook >/dev/null 2>&1; then
  echo "ansible-playbook not found. Complete bootstrap first (see ANSIBLE_BOOTSTRAP.md)." >&2
  exit 1
fi

DEFAULT_ACTION="install"
VAULT_FILE="$ANSIBLE_DIR/group_vars/all/vault.yml"

ask_vault_pass=false
skip_confirm=false
oml_action="$DEFAULT_ACTION"
oml_tenant=""
inventory_file=""
vault_args=()

print_help() {
  cat <<'EOF'
How to use it:

./deploy.sh --action=<action> --tenant=<tenant>
./deploy.sh --action=<action> --inventory=/abs/path/to/inventory.yml
./deploy.sh --action=<action> --tenant=<tenant> --ask-vault-pass
./deploy.sh --action=<action> --tenant=<tenant> --yes   # skip confirmation prompt

Options:
  --yes, -y           Run without interactive confirmation (for CI/automation)

Ansible Vault (required before any run):
  Set ANSIBLE_VAULT_PASSWORD_FILE to a local password file, uncomment vault_password_file
  in ansible.cfg, or pass --ask-vault-pass. See ANSIBLE_BOOTSTRAP.md.

With --inventory only, tenant_folder for instances/<tenant>/ files (certs, keys) is derived:
  - instances/<tenant>/inventory.yml  -> tenant_folder=<tenant>
  - /path/to/prod.yml                 -> tenant_folder=prod
Pass --tenant=<name> to override.

Primary actions (playbooks/site.yml unless noted):
  install, upgrade, update
  prerequisitos
  voice, telephony-edge, acd, interaction_processor
  omlapp, omlapp-workers, nginx, websockets, dialer, qa, addons
  observability
  postgres, redis, minio, gearman
  haproxy, edge
  data
  backup            (playbooks/backup.yml — PostgreSQL dump on demand to S3)
  kamailio          (alias for telephony-edge)

Layout validation then full site.yml (match topology to your inventory):
  layout-cluster   -> playbooks/cluster.yml
  layout-aio       -> playbooks/aio.yml

prerequisitos runs the full prerequisitos role (packages, Podman quadlets base, checks,
os_configuration) without other components; use for base OS prep or re-applying prerequisites.

Partial actions assume a working node or a prior install. They run only tasks tagged for
that action; Podman + omnileads network are included for component tags via prerequisitos.
For brand-new servers, run install first.

update is the recommended action for repeated deploys after the first install.

Removed in 3.X (use oml_manage on the host or a future deploy action when available):
  restore, recycle, sentinel, restart

Ansible log (ansible.cfg log_path): directory ANSIBLE_LOG_DIR (default /tmp/oml_install_logs)
is created before each run; log file ansible.log inside that directory.
EOF
}

banner() {
  local rc="$1"
  if [ "$rc" -eq 0 ]; then
    echo "#############################################################"
    echo "#         OMniLeads installation ended successfully         #"
    echo "#############################################################"
  else
    echo "#######################################################################################"
    echo "#         OMniLeads installation failed. Check what happened and try it again         #"
    echo "#######################################################################################"
  fi
}

parse_vault_password_file_from_cfg() {
  local line path
  while IFS= read -r line || [ -n "$line" ]; do
    line="${line%%#*}"
    line="${line#"${line%%[![:space:]]*}"}"
    line="${line%"${line##*[![:space:]]}"}"
    case "$line" in
      vault_password_file=*)
        path="${line#vault_password_file=}"
        path="${path#"${path%%[![:space:]]*}"}"
        path="${path%"${path##*[![:space:]]}"}"
        path="${path%\"}"
        path="${path#\"}"
        path="${path%\'}"
        path="${path#\'}"
        if [ -n "$path" ]; then
          printf '%s\n' "$path"
          return 0
        fi
        ;;
    esac
  done < "$ANSIBLE_DIR/ansible.cfg"
  return 1
}

resolve_vault_args() {
  vault_args=()

  if [ "$ask_vault_pass" = true ]; then
    vault_args=(--ask-vault-pass)
    return 0
  fi

  if [ -n "${ANSIBLE_VAULT_PASSWORD_FILE:-}" ] && [ -f "${ANSIBLE_VAULT_PASSWORD_FILE}" ]; then
    vault_args=(--vault-password-file "${ANSIBLE_VAULT_PASSWORD_FILE}")
    return 0
  fi

  local cfg_vault_file
  if cfg_vault_file="$(parse_vault_password_file_from_cfg)"; then
    if [ -f "$cfg_vault_file" ]; then
      vault_args=(--vault-password-file "$cfg_vault_file")
      return 0
    fi
  fi

  cat >&2 <<EOF
Ansible Vault password not configured.

Set ANSIBLE_VAULT_PASSWORD_FILE to a local password file, uncomment vault_password_file
in ansible.cfg, or pass --ask-vault-pass.

See ANSIBLE_BOOTSTRAP.md for bootstrap steps.
EOF
  exit 1
}

preflight_vault() {
  if [ ! -f "$VAULT_FILE" ]; then
    echo "Missing vault file: $VAULT_FILE (see ANSIBLE_BOOTSTRAP.md)." >&2
    exit 1
  fi

  if ! ansible-vault view "$VAULT_FILE" "${vault_args[@]}" >/dev/null 2>&1; then
    echo "Cannot decrypt $VAULT_FILE. Check your Vault password (see ANSIBLE_BOOTSTRAP.md)." >&2
    exit 1
  fi
}

resolve_inventory() {
  if [ -n "${inventory_file:-}" ]; then
    printf '%s\n' "$inventory_file"
    return
  fi

  if [ -z "${oml_tenant:-}" ]; then
    echo "Missing inventory source. Use --tenant or --inventory." >&2
    exit 1
  fi

  printf '%s/instances/%s/inventory.yml\n' "$ANSIBLE_DIR" "$oml_tenant"
}

derive_tenant_folder() {
  if [ -n "${oml_tenant}" ]; then
    return 0
  fi

  if [ -z "${inventory_file:-}" ]; then
    return 0
  fi

  local base dir
  base="$(basename "${inventory_file}")"
  dir="$(dirname "${inventory_file}")"

  case "$base" in
    inventory.yml|inventory.yaml)
      oml_tenant="$(basename "$dir")"
      ;;
    *)
      oml_tenant="${base%.yml}"
      oml_tenant="${oml_tenant%.yaml}"
      ;;
  esac
}

validate_inventory() {
  local inventory_path
  inventory_path="$(resolve_inventory)"

  if [ ! -f "$inventory_path" ]; then
    if [ -n "${oml_tenant:-}" ] && [ -z "${inventory_file:-}" ]; then
      echo "Inventory not found: instances/${oml_tenant}/inventory.yml" >&2
    else
      echo "Inventory not found: $inventory_path" >&2
    fi
    exit 1
  fi
}

unsupported_action() {
  local action="$1"
  echo "Action '$action' is not available in deploy.sh 3.X." >&2
  echo "Use oml_manage on the target host for restore/recycle operations." >&2
  exit 1
}

release_value() {
  git -C "$ANSIBLE_DIR" describe --tags --exact-match 2>/dev/null || git -C "$ANSIBLE_DIR" rev-parse --short HEAD
}

confirm_action() {
  if [ "$skip_confirm" = true ]; then
    return 0
  fi

  local inventory_path
  inventory_path="$(resolve_inventory)"

  echo
  echo "Deploy summary:"
  echo "  Action:    $oml_action"
  if [ -n "${oml_tenant:-}" ]; then
    echo "  Tenant:    $oml_tenant"
  fi
  echo "  Inventory: $inventory_path"
  echo "  Release:   $(release_value)"
  echo
  read -r -p "Continue with this deploy? [yes/no]: " reply
  reply="$(printf '%s' "$reply" | tr '[:upper:]' '[:lower:]')"

  case "$reply" in
    yes|y)
      return 0
      ;;
    no|n)
      echo "Deploy cancelled."
      exit 0
      ;;
    *)
      echo "Invalid response. Deploy cancelled (expected 'yes' or 'no')."
      exit 1
      ;;
  esac
}

run_playbook() {
  local playbook="$1"
  shift
  local inventory_path
  inventory_path="$(resolve_inventory)"

  mkdir -p /tmp/ansible-local /tmp/ansible-remote "${ANSIBLE_LOG_DIR:-/tmp/oml_install_logs}"

  ANSIBLE_CONFIG="$ANSIBLE_DIR/ansible.cfg" \
  ANSIBLE_LOCAL_TEMP="${ANSIBLE_LOCAL_TEMP:-/tmp/ansible-local}" \
  ANSIBLE_REMOTE_TEMP="/tmp/ansible-remote" \
  ansible-playbook "$playbook" -i "$inventory_path" "${vault_args[@]}" "$@"
}

for arg in "$@"; do
  case "$arg" in
    --action=*)
      oml_action="${arg#*=}"
      ;;
    --tenant=*)
      oml_tenant="${arg#*=}"
      ;;
    --inventory=*)
      inventory_file="${arg#*=}"
      ;;
    --ask-vault-pass)
      ask_vault_pass=true
      ;;
    --yes|-y)
      skip_confirm=true
      ;;
    --help|-h)
      print_help
      exit 0
      ;;
    *)
      echo "Invalid option: $arg" >&2
      print_help
      exit 1
      ;;
  esac
done

derive_tenant_folder
validate_inventory

case "$oml_action" in
  restore|recycle|sentinel|restart)
    unsupported_action "$oml_action"
    ;;
esac

resolve_vault_args
preflight_vault
confirm_action

common_extra_vars=(
  "--extra-vars=tenant_folder=${oml_tenant}"
  "--extra-vars=commit=$(git -C "$ANSIBLE_DIR" rev-parse HEAD)"
  "--extra-vars=omnileads_release=$(release_value)"
)

TENANT_OVERRIDES_FILE="$ANSIBLE_DIR/instances/${oml_tenant}/vars.yml"
if [ -f "$TENANT_OVERRIDES_FILE" ]; then
  common_extra_vars+=("--extra-vars=@${TENANT_OVERRIDES_FILE}")
fi

rc=0
case "$oml_action" in
  kamailio)
    run_playbook "$ANSIBLE_DIR/playbooks/site.yml" \
      --tags "telephony-edge" \
      "${common_extra_vars[@]}" || rc=$?
    ;;
  layout-cluster)
    run_playbook "$ANSIBLE_DIR/playbooks/cluster.yml" \
      "${common_extra_vars[@]}" || rc=$?
    ;;
  layout-aio)
    run_playbook "$ANSIBLE_DIR/playbooks/aio.yml" \
      "${common_extra_vars[@]}" || rc=$?
    ;;
  omlapp-workers)
    run_playbook "$ANSIBLE_DIR/playbooks/site.yml" \
      --tags "omlapp-workers,gather_facts" \
      "${common_extra_vars[@]}" || rc=$?
    ;;
  observability)
    run_playbook "$ANSIBLE_DIR/playbooks/site.yml" \
      --tags "observability,gather_facts" \
      --extra-vars "oml_observability_deploy=true" \
      "${common_extra_vars[@]}" || rc=$?
    ;;
  prerequisitos)
    run_playbook "$ANSIBLE_DIR/playbooks/site.yml" \
      --tags "prerequisitos,gather_facts" \
      "${common_extra_vars[@]}" || rc=$?
    ;;
  backup)
    run_playbook "$ANSIBLE_DIR/playbooks/backup.yml" \
      --tags "backup,always" \
      "${common_extra_vars[@]}" || rc=$?
    ;;
  install|upgrade|update|voice|telephony-edge|acd|interaction_processor|omlapp|nginx|websockets|dialer|qa|addons|postgres|redis|minio|gearman|haproxy|edge|data)
    run_playbook "$ANSIBLE_DIR/playbooks/site.yml" \
      --tags "$oml_action" \
      "${common_extra_vars[@]}" || rc=$?
    ;;
  *)
    echo "Unknown action: $oml_action" >&2
    print_help
    exit 1
    ;;
esac

banner "$rc"
exit "$rc"
