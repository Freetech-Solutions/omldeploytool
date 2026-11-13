#!/usr/bin/env python3
"""Copia ansible_host y omni_ip_lan desde el state de Terraform al inventario.

Uso, desde cualquier directorio:

    terraform/vultr/sync_inventory.py <tenant>

Lee `terraform output -json ansible_hosts` del ultimo init (el Space de ese
tenant) y rellena ansible/instances/<tenant>/inventory.yml. No crea hosts ni
grupos: si un nombre del output no esta en el inventario, termina con error.
"""

import json
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
TERRAFORM_DIR = ROOT / "terraform" / "vultr"


def fail(message):
    print(message, file=sys.stderr)
    sys.exit(1)


def tenant_name(argv):
    if len(argv) != 2 or not argv[1]:
        fail("Uso: sync_inventory.py <tenant>")
    name = argv[1]
    if any(char not in "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-" for char in name):
        fail("El tenant solo puede tener letras, numeros, _ y -.")
    return name


def load_ansible_hosts():
    result = subprocess.run(
        ["terraform", "output", "-json", "ansible_hosts"],
        cwd=TERRAFORM_DIR,
        capture_output=True,
        text=True,
        check=False,
    )
    if result.returncode != 0:
        fail(result.stderr.strip() or "terraform output ansible_hosts fallo")
    try:
        hosts = json.loads(result.stdout)
    except json.JSONDecodeError as exc:
        fail("terraform output no devolvio JSON: {0}".format(exc))
    if not isinstance(hosts, dict) or not hosts:
        fail("ansible_hosts esta vacio. compute_enabled=false o el state es de otro tenant?")
    return hosts


def fill_inventory(path, hosts):
    lines = path.read_text().splitlines()
    known = set()
    current = None
    out = []
    for line in lines:
        name = line.strip().rstrip(":").strip()
        if name in hosts and line.strip().endswith(":"):
            current = name
            known.add(name)
        elif current and line.strip().startswith("ansible_host:"):
            line = "{0}: {1}".format(line.split(":", 1)[0], hosts[current]["ansible_host"])
        elif current and line.strip().startswith("omni_ip_lan:"):
            line = "{0}: {1}".format(line.split(":", 1)[0], hosts[current]["omni_ip_lan"])
            current = None
        out.append(line)

    missing = sorted(set(hosts) - known)
    if missing:
        fail("Estos hosts estan en el state y no en el inventario: {0}".format(", ".join(missing)))
    path.write_text("\n".join(out) + "\n")


def main():
    tenant = tenant_name(sys.argv)
    inventory = ROOT / "ansible" / "instances" / tenant / "inventory.yml"
    if not inventory.is_file():
        fail("No existe {0}".format(inventory))
    hosts = load_ansible_hosts()
    fill_inventory(inventory, hosts)
    print("Inventario actualizado: {0} ({1} hosts)".format(inventory, len(hosts)))


if __name__ == "__main__":
    main()
