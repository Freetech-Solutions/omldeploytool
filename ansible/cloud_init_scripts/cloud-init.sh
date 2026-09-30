#!/bin/bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "Uso: $0 <nombre_usuario>" >&2
  exit 1
fi

nuevo_usuario="$1"

if ! id "${nuevo_usuario}" &>/dev/null; then
  useradd -m -s /bin/bash "${nuevo_usuario}"
fi

sudoers_file="/etc/sudoers.d/${nuevo_usuario}"
echo "${nuevo_usuario}    ALL=(ALL:ALL) ALL" > "${sudoers_file}"
chmod 440 "${sudoers_file}"
visudo -c -f "${sudoers_file}"

home_dir="/home/${nuevo_usuario}"
ssh_dir="${home_dir}/.ssh"
authorized_keys="${ssh_dir}/authorized_keys"

mkdir -p "${ssh_dir}"
cp /root/.ssh/authorized_keys "${authorized_keys}"

chown -R "${nuevo_usuario}:${nuevo_usuario}" "${home_dir}"
chmod 755 "${home_dir}"
chmod 700 "${ssh_dir}"
chmod 600 "${authorized_keys}"
