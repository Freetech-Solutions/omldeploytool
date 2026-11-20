#!/usr/bin/env python3
"""Copia ansible_host y omni_ip_lan desde el state de Terraform al inventario.

Uso, desde cualquier directorio:

    terraform/digitalocean/sync_inventory.py <inventory.yml>

Lee `terraform output -json ansible_hosts` del último init (el Space de ese
tenant) y rellena el inventory.yml cuyo path absoluto se pasa como argumento.
No crea hosts ni grupos: si un nombre del output no está en el inventario,
termina con error.
"""

import json
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
TERRAFORM_DIR = ROOT / "terraform" / "digitalocean"


def fail(message):
    print(message, file=sys.stderr)
    sys.exit(1)


def inventory_path(argv):
    if len(argv) != 2 or not argv[1]:
        fail("Uso: sync_inventory.py <inventory.yml>")
    path = Path(argv[1])
    if not path.is_absolute():
        fail("El inventario tiene que ser un path absoluto.")
    if not path.is_file():
        fail("No existe {0}".format(path))
    return path


def load_ansible_hosts():
    result = subprocess.run(
        ["terraform", "output", "-json", "ansible_hosts"],
        cwd=TERRAFORM_DIR,
        capture_output=True,
        text=True,
        check=False,
    )
    if result.returncode != 0:
        fail(result.stderr.strip() or "terraform output ansible_hosts falló")
    try:
        hosts = json.loads(result.stdout)
    except json.JSONDecodeError as exc:
        fail("terraform output no devolvió JSON: {0}".format(exc))
    if not isinstance(hosts, dict) or not hosts:
        fail("ansible_hosts está vacío. ¿compute_enabled=false o el state es de otro tenant?")
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
        fail("Estos hosts están en el state y no en el inventario: {0}".format(", ".join(missing)))
    path.write_text("\n".join(out) + "\n")


def main():
    inventory = inventory_path(sys.argv)
    hosts = load_ansible_hosts()
    fill_inventory(inventory, hosts)
    print("Inventario actualizado: {0} ({1} hosts)".format(inventory, len(hosts)))


if __name__ == "__main__":
    main()
