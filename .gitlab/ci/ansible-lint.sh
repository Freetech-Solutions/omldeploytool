#!/bin/bash
set -euo pipefail

# shellcheck source=lib.sh
source "$(dirname "$0")/lib.sh"
oml_ci_init_paths

cd "$ANSIBLE_DIR"

if [ -d .ci-venv ]; then
  # shellcheck source=/dev/null
  source .ci-venv/bin/activate
fi

export ANSIBLE_CONFIG="${ANSIBLE_DIR}/ansible.cfg"
export ANSIBLE_LOCAL_TEMP="${CI_PROJECT_DIR}/.cache/ansible-local"
mkdir -p "$ANSIBLE_LOCAL_TEMP" "${ANSIBLE_LOG_DIR}" /tmp/oml_install_logs 2>/dev/null || true

echo "==> YAML syntax (yamllint)"
yamllint -c "${CI_PROJECT_DIR}/.gitlab/ci/yamllint-ci.yml" \
  inventory_example_1.yml \
  inventory_example_2.yml \
  inventory_example_3.yml \
  inventory_example_4.yml \
  inventory_example_5.yml \
  group_vars/all/runtime.yml \
  group_vars/all/images.yml \
  group_vars/all/tenants_global.yml

echo "==> Playbook syntax-check (smoke, sin vault)"
ansible-playbook playbooks/smoke_prometheus_template.yml --syntax-check
ansible-playbook playbooks/smoke_promtail_template.yml --syntax-check

# Los inventory_example_*.yml referencian vault.yml; ansible-inventory requiere Vault.
echo "Lint OK (yamllint + syntax-check)"
