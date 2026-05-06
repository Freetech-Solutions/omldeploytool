#!/bin/bash
set -euo pipefail

ANSIBLE_DIR="$(cd "$(dirname "$0")" && pwd)"
DEFAULT_ACTION="install"

print_help() {
  cat <<'EOF'
How to use it:

./deploy.sh --action=<action> --tenant=<tenant>
./deploy.sh --action=<action> --inventory=/abs/path/to/inventory.yml

With --inventory only, tenant_folder for instances/<tenant>/ files (certs, keys) is
derived from the inventory filename (e.g. /path/prod.yml -> tenant_folder=prod).
You can still set --tenant=<name> explicitly to override.

Primary actions:
  install
  upgrade
  update
  restart
  prerequisitos
  voice
  omlapp
  omlapp-workers
  observability
  postgres
  redis
  minio
  kamailio
  telephony-edge
  acd

Layout validation then full site.yml (use matching topology for your inventory):
  layout-cluster   -> playbooks/cluster.yml
  layout-aio       -> playbooks/aio.yml

Operational playbooks (require real content under ansible/components/; see ansible/components/README.md):
  backup
  restore
  recycle

Legacy component actions (ansible/components/):
  haproxy
  sentinel

prerequisitos runs the full prerequisitos role (packages, Podman quadlets base, checks,
os_configuration) without other components; use for base OS prep or re-applying prerequisites.

Partial actions (voice, postgres, redis, …) assume a working node or a prior install.
They run only tasks tagged for that action; Podman + omnileads network are included for
component tags via the prerequisitos role. For brand-new servers, run install first.

update is the recommended action for repeated deploys after the first install. It keeps the
deployment reconciled without re-running the full bootstrap path unless relevant inputs changed.

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

# When using a custom inventory path, derive tenant_folder from the filename if --tenant omitted.
derive_tenant_folder() {
  if [ -n "${oml_tenant}" ] || [ -z "${inventory_file:-}" ]; then
    return 0
  fi
  local base
  base="$(basename "${inventory_file}")"
  oml_tenant="${base%.yml}"
  oml_tenant="${oml_tenant%.yaml}"
}

release_value() {
  git -C "$ANSIBLE_DIR" describe --tags --exact-match 2>/dev/null || git -C "$ANSIBLE_DIR" rev-parse --short HEAD
}

build_date_value() {
  git -C "$ANSIBLE_DIR" log -1 --date=iso-strict --format=%cd 2>/dev/null || LC_ALL=C date
}

run_playbook() {
  local playbook="$1"
  shift
  local inventory_path
  inventory_path="$(resolve_inventory)"

  mkdir -p /tmp/ansible-local /tmp/ansible-remote "${ANSIBLE_LOG_DIR:-/tmp/oml_install_logs}"

  ANSIBLE_CONFIG="$ANSIBLE_DIR/ansible.cfg" \
  ANSIBLE_LOCAL_TEMP="${ANSIBLE_LOCAL_TEMP:-/tmp/ansible-local}" \
  ANSIBLE_REMOTE_TEMP="${ANSIBLE_REMOTE_TEMP:-/tmp/ansible-remote}" \
  ANSIBLE_LOG_PATH="${ANSIBLE_LOG_PATH:-/tmp/oml_install_logs}" \
  ansible-playbook "$playbook" -i "$inventory_path" "$@"
}

oml_action="$DEFAULT_ACTION"
oml_tenant=""
inventory_file=""

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

common_extra_vars=(
  --extra-vars "tenant_folder=${oml_tenant}"
  --extra-vars "commit=$(git -C "$ANSIBLE_DIR" rev-parse HEAD)"
  --extra-vars "omnileads_release=$(release_value)"
  --extra-vars "build_date=$(build_date_value)"
)

rc=0
case "$oml_action" in
  backup)
    run_playbook "$ANSIBLE_DIR/playbooks/backup.yml" \
      --tags "$oml_action" \
      --extra-vars "file_timestamp=$(date +%s)" \
      "${common_extra_vars[@]}" || rc=$?
    ;;
  restore|recycle)
    run_playbook "$ANSIBLE_DIR/playbooks/${oml_action}.yml" \
      --tags "$oml_action" \
      "${common_extra_vars[@]}" || rc=$?
    ;;
  haproxy)
    run_playbook "$ANSIBLE_DIR/components/haproxy/playbook.yml" \
      --tags "$oml_action" \
      --extra-vars "haproxy_repo_path=$ANSIBLE_DIR/components/haproxy/" \
      "${common_extra_vars[@]}" || rc=$?
    ;;
  sentinel)
    run_playbook "$ANSIBLE_DIR/components/sentinel/playbook.yml" \
      --tags "$oml_action" \
      --extra-vars "sentinel_repo_path=$ANSIBLE_DIR/components/sentinel/" \
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
    # Role tag must match; gather_facts is otherwise skipped when filtering by --tags
    run_playbook "$ANSIBLE_DIR/playbooks/site.yml" \
      --tags "omlapp-workers,gather_facts" \
      "${common_extra_vars[@]}" || rc=$?
    ;;
  observability)
    # Incluye gather_facts; Promtail sin loki_host en inventario vía oml_observability_deploy
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
  *)
    run_playbook "$ANSIBLE_DIR/playbooks/site.yml" \
      --tags "$oml_action" \
      "${common_extra_vars[@]}" || rc=$?
    ;;
esac

banner "$rc"
exit "$rc"
