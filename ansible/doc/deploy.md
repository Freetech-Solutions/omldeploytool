# Deploy con Ansible

Este documento explica cómo lanzar un deploy usando la estructura actual de `ansible/`, basada en `playbooks/`, `roles/` e inventarios externos.

## 1. Requisitos previos

Trabajar desde:

```bash
cd /Users/fpignataro/repos/omldeploytool/ansible
```

Herramientas recomendadas:

- `ansible-playbook`
- `ansible-galaxy`
- `ansible-lint`

Dependencias declaradas:

- `collections/requirements.yml`
- `requirements-dev.txt`

Instalación típica:

```bash
pip install -r requirements-dev.txt
ansible-galaxy collection install -r collections/requirements.yml -p ./collections
```

## 2. Preparar el inventario

Tomar como base el ejemplo:

```bash
mkdir -p instances/mi_tenant
cp inventories/examples/inventory.yml instances/mi_tenant/inventory.yml
```

También podés usar cualquier inventario externo y pasarlo por path absoluto.

`instances/mi_tenant/inventory.yml` es solo un ejemplo. Si ese path no existe, Ansible no va a poder parsear el inventario.

Referencias:

- `inventories/examples/inventory.yml`
- `inventories/README.md`

## 3. Validar antes de desplegar

Validación rápida de sintaxis:

```bash
make syntax INVENTORY=inventories/examples/inventory.yml
```

Por escenario:

```bash
make syntax-aio INVENTORY=inventories/examples/inventory.yml
make syntax-cluster INVENTORY=inventories/examples/inventory.yml
```

Lint:

```bash
make lint
```

## 4. Log de Ansible

Por defecto, `ansible.cfg` escribe en `/tmp/oml_install_logs/ansible.log` (el directorio lo crea `deploy.sh`). Si el archivo crece mucho, conviene truncarlo o rotarlo antes de corridas largas, por ejemplo:

```bash
: > /tmp/oml_install_logs/ansible.log
# o logrotate con copytruncate
```

## 5. Deploy usando `deploy.sh`

El entrypoint principal es:

```bash
./deploy.sh --action=<accion> --tenant=<tenant>
```

O con inventario explícito:

```bash
./deploy.sh --action=<accion> --inventory=/ruta/absoluta/inventory.yml
```

Acciones principales:

- `install`
- `upgrade`
- `update`
- `restart`
- `voice`
- `app`
- `observability`
- `postgres`
- `redis`
- `minio`
- `kamailio`
- `rtpengine`
- `asterisk`
- `cron`

Acciones operativas:

- `backup`
- `restore`
- `recycle`

Ejemplos:

```bash
./deploy.sh --action=install --tenant=mi_tenant
./deploy.sh --action=update --tenant=mi_tenant
./deploy.sh --action=upgrade --tenant=mi_tenant
./deploy.sh --action=app --tenant=mi_tenant
./deploy.sh --action=observability --inventory=/abs/path/inventory.yml
./deploy.sh --action=backup --tenant=mi_tenant
```

Uso recomendado:

- `install`: bootstrap completo de primera vez.
- `update`: redeploy incremental e idempotente para corridas repetidas.
- `upgrade`: cambios operativos más amplios o actualizaciones de release.

## 6. Deploy directo con `ansible-playbook`

Playbook principal:

```bash
ansible-playbook playbooks/site.yml -i instances/mi_tenant/inventory.yml --tags install
ansible-playbook playbooks/site.yml -i instances/mi_tenant/inventory.yml --tags update
```

Ejemplos por acción:

```bash
ansible-playbook playbooks/site.yml -i instances/mi_tenant/inventory.yml --tags upgrade
ansible-playbook playbooks/site.yml -i instances/mi_tenant/inventory.yml --tags app
ansible-playbook playbooks/site.yml -i instances/mi_tenant/inventory.yml --tags voice
ansible-playbook playbooks/site.yml -i instances/mi_tenant/inventory.yml --tags postgres
```

Playbooks por escenario:

```bash
ansible-playbook playbooks/aio.yml -i instances/mi_tenant/inventory.yml --tags install
ansible-playbook playbooks/cluster.yml -i instances/mi_tenant/inventory.yml --tags install
```

Playbooks operativos:

```bash
ansible-playbook playbooks/backup.yml -i instances/mi_tenant/inventory.yml --tags backup
ansible-playbook playbooks/restore.yml -i instances/mi_tenant/inventory.yml --tags restore
ansible-playbook playbooks/recycle.yml -i instances/mi_tenant/inventory.yml --tags recycle
```

## 7. Qué playbook usar

- Usar `playbooks/site.yml` para la mayoría de los deploys.
- Usar `playbooks/aio.yml` si el inventario es AIO.
- Usar `playbooks/cluster.yml` si el inventario es cluster.
- Usar los playbooks `backup`, `restore` y `recycle` para operaciones puntuales.

## 8. Estructura relevante

- `playbooks/site.yml`: composición principal.
- `roles/topology_normalize/tasks/main.yml`: normalización de topología y activación de componentes.
- `roles/prerequisitos/tasks/`: preflight, validaciones y configuración base.
- `group_vars/all/`: defaults globales separados por dominio.
- `deploy.sh`: wrapper operativo para acciones frecuentes.
