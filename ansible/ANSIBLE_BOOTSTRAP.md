# Bootstrap del entorno Ansible

Esta guía describe los pasos mínimos para dejar operativa la herramienta de deploy
de OMniLeads (`ansible/`) en una estación de trabajo nueva. Cubre:

1. [Entorno virtual de Python](#1-entorno-virtual-de-python)
2. [Archivo `vault.yml` (Ansible Vault)](#2-archivo-vaultyml-ansible-vault)
3. [Carpeta `instances/` e inventarios por tenant](#3-carpeta-instances-e-inventarios-por-tenant)
4. [Verificación final](#4-verificación-final)

> [!IMPORTANT]
> Todos los comandos se ejecutan desde la raíz del subdirectorio `ansible/` del
> repositorio. Si trabajás desde la raíz del repo, anteponé `cd ansible`.

## Prerrequisitos del host

| Herramienta | Versión mínima |
| ----------- | -------------- |
| Python      | 3.10           |
| pip         | 23.x           |
| git         | 2.x            |
| openssh     | 8.x            |

En distribuciones Debian/Ubuntu suele alcanzar con:

```bash
sudo apt-get update
sudo apt-get install -y python3 python3-venv python3-pip git openssh-client
```

En macOS, con Homebrew:

```bash
brew install python git
```

---

## 1. Entorno virtual de Python

Toda la cadena (Ansible, mitogen, linters) se instala dentro de un **venv local**
para no contaminar el sistema. La carpeta `ansible/venv/` está incluida en
[`.gitignore`](../.gitignore).

```bash
cd ansible

# Crear el venv (la convención del repo es ansible/venv)
python3 -m venv venv

# Activar el venv
source venv/bin/activate

# Actualizar pip y instalar dependencias Python
pip install --upgrade pip
pip install -r requirements.txt

# Instalar las collections de Ansible declaradas en requirements.yml
ansible-galaxy collection install -r requirements.yml
```

Verificá que todo quede a mano:

```bash
ansible --version
ansible-playbook --version
ansible-vault --version
ansible-lint --version
```

> [!TIP]
> Para reactivar el venv en una nueva sesión: `cd ansible && source venv/bin/activate`.
> Para salir: `deactivate`.

### Re-ejecuciones futuras

Cuando se actualice `requirements.txt` o `requirements.yml`:

```bash
source venv/bin/activate
pip install -r requirements.txt --upgrade
ansible-galaxy collection install -r requirements.yml --upgrade
```

---

## 2. Archivo `vault.yml` (Ansible Vault)

A partir de OMniLeads 3.X, **todos los secretos** del inventario se referencian
como `{{ vault_<nombre> }}` y se desencriptan desde
`./group_vars/all/vault.yml` (ver `ansible/UPGRADE_YOUR_INVENTORY.md`).

El archivo está versionado en el repo solo a modo de plantilla cifrada compartida;
**cada operador debe poseer la password de Vault para poder desencriptarlo y/o
generarlo desde cero**.

### 2.1 Definir el archivo de password

Creá un archivo local con la password del Vault (fuera del repo). Ejemplo:

```bash
mkdir -p ~/.config/omnileads
printf '%s' 'TU_PASSWORD_DE_VAULT' > ~/.config/omnileads/vault_pass
chmod 600 ~/.config/omnileads/vault_pass
```

Y exportalo para que Ansible lo use automáticamente:

```bash
export ANSIBLE_VAULT_PASSWORD_FILE="$HOME/.config/omnileads/vault_pass"
```

> [!TIP]
> Agregá ese `export` a tu `~/.bashrc` / `~/.zshrc` para tenerlo en cada sesión.
> Alternativamente, podés descomentar `vault_password_file` en
> [`ansible/ansible.cfg`](./ansible.cfg) (líneas ~126-128) y apuntarlo a la ruta
> elegida; recordá que ese archivo SÍ está versionado, así que evitá rutas que
> revelen información sensible.

### 2.2 Variables que debe contener `vault.yml`

El conjunto mínimo de claves esperadas por los playbooks es:

```yaml
---
# --- Postgres
vault_postgres_password: "..."

# --- Object Storage / S3 (MinIO o externo)
vault_s3_http_admin_pass: "..."
vault_bucket_access_key: "..."
vault_bucket_secret_key: "..."

# --- Telefonía (Asterisk AMI)
vault_ami_password: "..."

# --- Dialer
vault_dialer_password: "..."

# --- Django
vault_django_secret_key: "..."

# --- Telefonía WebRTC (auth efímera Kamailio + SIP_SECRET_KEY en Django)
vault_kamailio_webrtc_auth_eph_key: "..."

# --- Integraciones
vault_google_api_key: "..."
vault_callrec_transcriber_api_key: "..."

# --- Observabilidad (Promtail → Loki central; URL base sin path de push)
vault_loki_url: "http://loki.example.com:3100"
# --- HAProxy edge: CIDRs permitidos para https://<fqdn>/prom
vault_haproxy_prom_allowed_src: ["10.0.0.0/8", "192.168.0.0/16"]

# --- Backups en S3
vault_backup_bucket_access_key: "..."
vault_backup_bucket_secret_key: "..."
```

> El listado completo y las referencias `{{ vault_* }}` en el inventario están
> documentados en [`UPGRADE_YOUR_INVENTORY.md`](./UPGRADE_YOUR_INVENTORY.md#paso-2-centralización-de-secretos-con-ansible-vault).

### 2.3 Crear o editar el `vault.yml`

#### Opción A — Crearlo desde cero

```bash
# Desde ansible/
ansible-vault create ./group_vars/all/vault.yml
```

Se abre `$EDITOR`; pegá el bloque YAML con los `vault_*` y guardá. El archivo
queda cifrado en disco (cabecera `$ANSIBLE_VAULT;1.1;AES256`).

#### Opción B — Editarlo si ya existe

```bash
ansible-vault edit ./group_vars/all/vault.yml
```

#### Opción C — Inspeccionarlo en claro (sin abrir editor)

```bash
ansible-vault view ./group_vars/all/vault.yml
```

#### Opción D — Recifrar con otra password

```bash
ansible-vault rekey ./group_vars/all/vault.yml
```

---

## 3. Carpeta `instances/` e inventarios por tenant

Cada **tenant** (instancia o conjunto de instancias) vive en su propia carpeta
bajo `ansible/instances/<tenant>/`. La carpeta `instances/` está completa en
`.gitignore` para que la información sensible (inventarios reales, certificados,
keys) no se publique en el repo.

### 3.1 Estructura esperada

```text
ansible/
├── inventory.yml                 # plantilla de referencia (versionada)
└── instances/                    # ignorado por git
    ├── tenant_aio_demo/
    │   ├── inventory.yml         # copia personalizada para el tenant
    │   ├── cert.pem              # opcional, si certs: custom
    │   └── key.pem               # opcional, si certs: custom
    └── cluster_prod/
        └── inventory.yml
```

### 3.2 Crear un tenant nuevo

```bash
# Desde ansible/
mkdir -p instances/<tenant>
cp inventory.yml instances/<tenant>/inventory.yml
```

Editá `instances/<tenant>/inventory.yml` y ajustá como mínimo:

- IPs / FQDNs de los hosts (`ansible_host`, `omni_ip_lan`).
- `tenant_id`.
- `fqdn` y `notification_email` si vas a usar `certs: certbot`.
- Variables de runtime (`TZ`, etc.).
- Layout final: agrupar los hosts bajo `omnileads_aio` o
  `omnileads_data` / `omnileads_edge` / `omnileads_nodes` según corresponda
  (ver [`README.md`](./README.md#ansible-)).

> [!NOTE]
> Las referencias `{{ vault_<nombre> }}` dentro del `inventory.yml` se resuelven
> automáticamente con las variables del `vault.yml` del paso anterior. No hay
> que duplicar nada por tenant — el vault es global a `group_vars/all/`.

### 3.3 Certificados TLS por tenant (opcional)

Si vas a usar `certs: custom` en el inventario, copiá los archivos al tenant:

```bash
cp /ruta/a/cert.pem instances/<tenant>/cert.pem
cp /ruta/a/key.pem  instances/<tenant>/key.pem
chmod 600 instances/<tenant>/key.pem
```

Si los archivos tienen otros nombres, declaralos en el host del inventario con
`ssl_cert_file_name` y `ssl_key_file_name` (ver `README.md`).

---

## 4. Verificación final

Con el venv activo, la password del Vault disponible y el tenant creado:

```bash
# 1) ¿Ansible "ve" los hosts del tenant?
ansible -i instances/<tenant>/inventory.yml all --list-hosts

# 2) ¿Se desencripta correctamente el vault y se resuelven las variables?
ansible -i instances/<tenant>/inventory.yml all \
  -m debug -a 'var=vault_postgres_password' \
  --vault-password-file "$ANSIBLE_VAULT_PASSWORD_FILE"

# 3) ¿Hay conectividad SSH a los nodos?
ansible -i instances/<tenant>/inventory.yml all -m ping
```

Si los tres comandos responden OK, podés disparar el deploy. `deploy.sh` activa el venv automáticamente si existe, resuelve la password del Vault desde `ANSIBLE_VAULT_PASSWORD_FILE` (o `vault_password_file` en `ansible.cfg`) y valida `group_vars/all/vault.yml` antes de ejecutar el playbook — no hace falta pasar `--ask-vault-pass` ni `--vault-password-file` manualmente si ya exportaste la variable en el paso 2.1:

```bash
./deploy.sh --action=install --tenant=<tenant>
```

O bien, apuntando a un inventario fuera de `instances/`:

```bash
./deploy.sh --action=install --inventory=/ruta/absoluta/al/inventory.yml
```

Para inventarios bajo `instances/<tenant>/inventory.yml`, `deploy.sh` deriva `tenant_folder=<tenant>` sin necesidad de `--tenant=`.

Para la lista completa de acciones, ver `./deploy.sh --help` y la sección
[Bash Script deploy.sh](./README.md#bash-script-deploysh-) del README.

---

## Troubleshooting rápido

| Síntoma | Causa probable | Solución |
| ------- | -------------- | -------- |
| `ERROR! Attempting to decrypt but no vault secrets found` | No exportaste `ANSIBLE_VAULT_PASSWORD_FILE` ni configuraste `vault_password_file` en `ansible.cfg`. | Reexportar la variable, descomentar `vault_password_file` en `ansible.cfg`, o usar `./deploy.sh --ask-vault-pass`. |
| `Ansible Vault password not configured` (al invocar `deploy.sh`) | `deploy.sh` no encontró ninguna fuente de password del Vault. | Completar el paso 2.1 (`export ANSIBLE_VAULT_PASSWORD_FILE=...`) o pasar `--ask-vault-pass`. |
| `ERROR! Decryption failed` | Password incorrecta o archivo cifrado con otra clave. | Validar la password (`ansible-vault view ./group_vars/all/vault.yml`) o re-cifrar con `rekey`. |
| `Missing inventory source. Use --tenant or --inventory.` | `deploy.sh` invocado sin `--tenant=` ni `--inventory=`. | Pasar uno de los dos. |
| `instances/<tenant>/inventory.yml: No such file or directory` | El tenant no fue creado o tipeaste mal el nombre. | Revisar `ls instances/`. |
| Cambios en `./group_vars/all/vault.yml` aparecen en `git status` aunque esté en `.gitignore` | El archivo ya está trackeado en la historia del repo. | `git rm --cached ansible/./group_vars/all/vault.yml` (ver sección 2.3). |
| `command not found: ansible` después de cerrar la terminal | El venv se desactivó al cerrar la shell. | `source ansible/venv/bin/activate`. |
