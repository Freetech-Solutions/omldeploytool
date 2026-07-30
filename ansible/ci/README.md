# CI helpers (GitLab runner / GitLab CI variables)

Scripts usados por [`.gitlab-ci.yml`](../../.gitlab-ci.yml) y por [`ansible/ci/`](../ci/).

## Ejecutores

| Executor | `image: python:3.11-slim` | Setup |
| -------- | ------------------------- | ----- |
| **Docker** | Se usa la imagen | `ansible-setup.sh` instala paquetes con `apt-get` |
| **Shell / SSH** (tag `deploy`) | Se ignora la imagen | `lib.sh` normaliza `CI_PROJECT_DIR` (GitLab 12 SSH usa rutas relativas) |

GitLab Runner 12.x con **SSH executor** define `CI_PROJECT_DIR` como ruta relativa (`builds/.../omldeploytool`). Los scripts en [`.gitlab/ci/lib.sh`](../../.gitlab/ci/lib.sh) resuelven la ruta absoluta antes de entrar en `ansible/`.

En ambos casos el entorno Ansible queda en `ansible/.ci-venv/` (no hace falta `bootstrap.sh` en CI).

## Variables de GitLab CI/CD (Settings → CI/CD → Variables)

### DigitalOcean (deploy jobs)

| Variable | Tipo | Requerida |
| -------- | ---- | --------- |
| `DIGITALOCEAN_ACCESS_TOKEN` | Variable (masked) | Sí |
| `DIGITALOCEAN_DROPLET_IMG` | Variable | Sí |
| `DIGITALOCEAN_DROPLET_SIZE` | Variable | Sí (jobs AIO de un solo droplet en este repo) |
| `DIGITALOCEAN_DROPLET_SIZE_AIO` | Variable | Sí (enterprise QA: droplet compute / AIO+Edge) |
| `DIGITALOCEAN_DROPLET_SIZE_EDGE` | Variable | Sí (enterprise QA: droplet edge) |
| `DIGITALOCEAN_REGION` | Variable | Sí |
| `DIGITALOCEAN_SSH_KEY` | Variable | Sí |
| `DIGITALOCEAN_DROPLET_ROCKY_IMG` | Variable | Solo `deploy-aio-cloud-rocky` |

### Ansible Vault (deploy jobs)

**Opción A — variables CI (recomendada con Docker executor):**

| Variable | Tipo | Descripción |
| -------- | ---- | ----------- |
| `ANSIBLE_VAULT_PASSWORD` | Variable (masked) | Password del vault |
| `ANSIBLE_VAULT_YML` | **File** | `vault.yml` cifrado completo |

**Opción B — archivos en el runner (shell executor):**

| Recurso | Ruta por defecto |
| ------- | ---------------- |
| Password | `$HOME/.config/omnileads/vault_pass` |
| Vault cifrado | `$HOME/.config/omnileads/vault.yml` |

Override: `ANSIBLE_VAULT_PASSWORD_FILE`, `OML_ANSIBLE_VAULT_FILE`.

El vault debe incluir `vault_tenant_test_aio_*` (ver `inventory_example_1.yml`) para jobs AIO de un solo host. El job enterprise QA `deploy-qa-aio-digitalocean` usa `inventory_example_2.yml` (AIO+Edge: 2 droplets) y parchea `vault_tenant_example_2_node_*`, `vault_tenant_example_2_edge_*` y `vault_tenant_example_2_fqdn` vía [`patch_vault_cicd.sh`](patch_vault_cicd.sh) (`--node-*` / `--edge-*`).

`DO_URL` es el FQDN que el job escribe en `vault_tenant_example_2_fqdn` y usa en la verificación HTTPS final. El pipeline **no** crea ni modifica registros DNS en DigitalOcean (`doctl compute domain records` quedó fuera del job); el registro A correspondiente a `DO_URL` debe administrarse fuera del pipeline y resolver a la IP pública del **edge** (HAProxy con TLS custom).

### Overrides del tenant QA (`vars.yml`)

El job enterprise `deploy-qa-aio-digitalocean` requiere un archivo persistente
en el runner:

```text
$HOME/.config/omnileads/instances/gitlab/vars.yml
```

En cada corrida lo copia a `ansible/instances/gitlab/vars.yml`, donde
`deploy.sh --tenant=gitlab` lo carga automáticamente como `extra-vars`. La
variable CI `OML_CI_TENANT_VARS_FILE` permite indicar otra ruta.

El archivo debe contener configuración común al tenant y referencias a Vault,
pero no secretos en claro. Las variables exclusivas del node o edge deben
permanecer en `inventory.yml`.

### Certificados TLS (`certs: custom`)

| Variable | Tipo | Alternativa en runner |
| -------- | ---- | --------------------- |
| `OML_CI_TENANT_CERT_PEM` | File | `$HOME/.config/omnileads/instances/gitlab/cert.pem` |
| `OML_CI_TENANT_KEY_PEM` | File | `.../key.pem` |
| `OML_CI_TENANT_CERTS` | — | Directorio con `cert.pem`/`key.pem` (o `FTS_Sephir_*.pem`) |
| `OML_CI_TENANT_FOLDER` | Variable | Carpeta bajo `instances/` (default `gitlab`) |
| `OML_CI_CERT_FILE_NAME` | Variable | Nombre extra del cert en `instances/<tenant>/` (default `cert.pem`) |
| `OML_CI_KEY_FILE_NAME` | Variable | Nombre extra de la key (default `key.pem`) |

Los archivos se copian a `ansible/instances/<tenant>/cert.pem` y `key.pem`. En inventario, `ssl_cert_file_name` / `ssl_key_file_name` en `group_vars` deben coincidir (default global: `cert.pem` / `key.pem`).

El job enterprise QA `deploy-qa-aio-digitalocean` **exige** esos PEM persistentes
en `$HOME/.config/omnileads/instances/gitlab/` (o las variables File equivalentes).
Tras `ansible-vault-setup.sh` valida que no estén vacíos y genera el inventario con
`certs: custom` + `ssl_cert_file_name` / `ssl_key_file_name` en **node y edge**.
Usar el mismo certificado en ambos hosts alinea la verificación TLS de HAProxy
hacia Nginx (`node:443`) y evita backends DOWN por certificados distintos.

### Disparo manual del pipeline

| Variable | Valor | Efecto |
| -------- | ----- | ------ |
| `RUN_RM_DEPLOY` | `true` | Ejecuta `deploy-aio-cloud` |
| `RUN_RM_DEPLOY_DOCKER` | `true` | Ejecuta `deploy-aio-cloud-docker` |

### Opcionales

| Variable | Uso |
| -------- | --- |
| `OMLAPP_IMG` | Override de `APP_IMG` en `group_vars/all/images.yml` |
| `OMLOSS_BRANCH` | Checkout de otra rama antes del deploy (si coincide con la rama del pipeline, se omite). En `deploy-aio-cloud-docker` también define la rama que el droplet clona (default: `CI_COMMIT_REF_NAME`) |
| `NIC` | Interfaz de red del droplet para `deploy-aio-cloud-docker` (default en `deploy.sh`: `eth0`; en algunas imágenes DO usar `ens3`) |
| `DOCTL_VERSION` | Versión de doctl (default `1.118.0` en `.gitlab-ci.yml`) |
| `OML_CI_SKIP_APT` | `1` para no usar `apt-get` en el runner (útil si otro proceso tiene el lock) |
| `OML_CI_SKIP_DOCTL` | `1` para omitir doctl (job `ansible_lint`) |

## Job `ansible_lint`

Corre en stage `lint` (MR, push, pipeline web). **No** necesita Vault ni DigitalOcean.

- `yamllint` sobre inventarios de ejemplo y `group_vars` principales
- `ansible-playbook --syntax-check` en smoke playbooks (sin vault)

No se ejecuta `ansible-lint` sobre `site_core.yml` en CI: el árbol de roles 3.X tiene cientos de avisos de estilo preexistentes que no indican fallo de deploy. Los `inventory_example_*.yml` referencian Vault y no se validan con `ansible-inventory` sin password.

## Job `deploy-aio-cloud-docker`

Smoke test de Docker Compose en DigitalOcean. **No** usa `docker-compose/test-env/` (stack local/QA); despliega [`docker-compose/prod-env/`](../../docker-compose/prod-env/) mediante [`deploy.sh`](../../docker-compose/prod-env/deploy.sh) como cloud-init `user-data`.

### Disparo

Variable `RUN_RM_DEPLOY_DOCKER=true` en un pipeline manual (web o API).

### Requisitos del droplet

| Aspecto | Recomendación |
| ------- | ------------- |
| **RAM** | ≥ 4 GB (`DIGITALOCEAN_DROPLET_SIZE`, p. ej. `s-2vcpu-4gb`) |
| **Imagen** | Debian/Ubuntu o RHEL-like compatible con `deploy.sh` (`DIGITALOCEAN_DROPLET_IMG`) |
| **Timeout job** | 90 min (build completo de imágenes + `compose up`) |

El droplet clona `omldeploytool` en la rama `OMLOSS_BRANCH` o, si no está definida, `CI_COMMIT_REF_NAME`. El runner parchea `branch=` en `deploy.sh` antes de subirlo como `user-data`.

### Flujo resumido

1. Runner: checkout opcional (`oml-checkout-branch.sh`), `sed` en `deploy.sh` (rama + `NIC`).
2. Droplet: instala Docker, clona repo + submódulos, `set_img_local.sh`, `compose build`, `compose up -d`.
3. Runner: espera HTTPS 302 en la IP pública, borra el droplet (también en `after_script` si el job falla).

### Variables adicionales

| Variable | Uso |
| -------- | --- |
| `NIC` | Override de `oml_nic` (interfaz para IP privada en cloud-init) |
| `OMLOSS_BRANCH` | Rama a clonar en el droplet (además del checkout en el runner) |

No requiere Ansible Vault ni certificados TLS del job `deploy-aio-cloud`.

## Verificación en el runner (shell)

```bash
export ANSIBLE_VAULT_PASSWORD_FILE="$HOME/.config/omnileads/vault_pass"
ansible-vault view "$HOME/.config/omnileads/vault.yml" | grep vault_tenant_test_aio
```

O con variables CI simuladas localmente:

```bash
export CI_PROJECT_DIR="$(pwd)"
export ANSIBLE_VAULT_PASSWORD='...'
export ANSIBLE_VAULT_YML=/ruta/al/vault.yml.cifrado
bash .gitlab/ci/ansible-setup.sh
source .gitlab/ci/ansible-vault-setup.sh
# Deja .ci-omnileads/vault.env para los pasos siguientes del job (patch_vault_cicd, deploy.sh)
```
