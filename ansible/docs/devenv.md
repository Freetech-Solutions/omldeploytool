# Devenv local (Podman Quadlet)

Entorno de desarrollo AIO desplegado con el mismo camino que producción
(`matrix.yml` → `playbooks/site.yml`), sin usar `docker-compose/`.

Flag clave: **`oml_devenv: true`** (en `instances/devenv/vars.yml`).

## Requisitos

| Requisito | Nota |
|-----------|------|
| Linux + systemd + Podman | Quadlet no corre en macOS/Darwin. En Mac usá una VM Linux y ejecutá Ansible **dentro** de ella (`ansible_connection: local`). |
| Paquetes OS **preinstalados** | Con `oml_devenv`, Ansible **no** instala nada vía apt/dnf (ni `podman`). El host debe traer al menos Podman ≥ 4.4; en producción el rol `prerequisitos` suele instalar también `curl`, `wget`, `jq`, `python3-psycopg2`, `python3-boto3`, `cron`/`cronie`, etc. |
| Bootstrap Ansible | [ANSIBLE_BOOTSTRAP.md](../ANSIBLE_BOOTSTRAP.md) (venv, collections, Vault). |
| Submódulos | `git submodule update --init --recursive` en la raíz del monorepo. |
| Usuario admin | `ansible_user` con sudo NOPASSWD (**no** `root`, **no** `omnileads`). |
| Certs TLS | `certs: custom` → `instances/devenv/cert.pem` y `key.pem`. |
| `omni_ip_lan` | IPv4 **real** del host (nunca `127.0.0.1`). Los `PublishPort` y el SDP/SIP lo necesitan. |

## Setup rápido

```bash
cd ansible
mkdir -p instances/devenv
cp inventory_example_devenv.yml instances/devenv/inventory.yml
cp inventory_example_devenv_vars.yml instances/devenv/vars.yml
# Editar inventory: omni_ip_lan, ansible_user
# Copiar cert.pem / key.pem a instances/devenv/

./deploy.sh --action=install --tenant=devenv --yes
# equivalente:
./deploy.sh --action=devenv --tenant=devenv --yes
```

Si falta el inventario, `deploy.sh` muestra los `cp` exactos.

## Qué cambia con `oml_devenv`

| Aspecto | Producción | Devenv |
|---------|------------|--------|
| Paquetes OS (`prerequisitos`) | apt/dnf: podman, curl, jq, … | **No instala** paquetes; exige Podman ya presente |
| Imágenes OML | Pull de registry (`images.yml`) | `roles/devenv_images` hace `podman build` desde `components-git-repo/` → tags `localhost/*:devenv` |
| Django settings | `ominicontacto.settings.production` | `ominicontacto.settings.develop` |
| Código Django | Contenido de la imagen | Bind `django_src_host_path` → `/opt/omnileads/ominicontacto` en uWSGI/runserver, Daphne y workers `APP_IMG` |
| Entrypoint web | `init_uwsgi.sh` | `init_devenv.sh` (`runserver 0.0.0.0:8099`) |
| Vue | — | Contenedores `vue-cli` / `vue-build` en `omlapp_web`; UI en host `:8081` |
| `telephony_edge` / `acd` | `Network=host` | Bridge `omnileads` + `PublishPort` SIP/RTP |
| `acd_nodes` | `127.0.0.1:5070` (host net) | `{{ omni_ip_lan }}:5070` (pods distintos en bridge) |
| HAProxy | Solo grupo `edge` | Off en AIO puro |
| QA PSTN | Opcional (`qa_env`) | Activado en vars de ejemplo |

Producción **no** se ve afectada: todas las ramas Jinja usan `oml_devenv | default(false)`.

## Paths de código

Por defecto (relativos al playbook):

```yaml
oml_src_root: "{{ playbook_dir }}/../../components-git-repo"
django_src_host_path: "{{ oml_src_root }}/django"
vue_src_host_path: "{{ oml_src_root }}/django/omnileads_ui"
```

El bind usa opción SELinux `:z` (shared) porque varios contenedores montan el mismo árbol.

## Rebuild de imágenes

- `--action=install` / `upgrade` / `devenv`: rebuild siempre.
- `--action=update`: no rebuild salvo `devenv_rebuild_images: true` en vars.

Upstream (Postgres, Redis, MinIO, Gearman, `vue-cli`) se hace pull, no build.

## Acceso típico

| Servicio | URL / puerto |
|----------|----------------|
| Web (Nginx) | `https://localhost` o `https://{{ omni_ip_lan }}` |
| Vue CLI | `http://{{ omni_ip_lan }}:8081` (mapeo host `8081` → contenedor `8080`) |
| Kamailio WebRTC SIP | `{{ omni_ip_lan }}:10060` |
| Kamailio PSTN | `{{ omni_ip_lan }}:5060` |
| RTP RTPengine | rango `rtpengine_rtp_port_min`–`max` (default 20000–30000) |
| ACD trunk / agent | `:5070` / `:5160` en `omni_ip_lan` |

## Telefonía en bridge

En devenv, Kamailio+RTPengine (`telephony_edge`) y Asterisk (`acd`) son **pods distintos** sobre la bridge `omnileads`. Por eso:

- Intra-pod (p. ej. Kamailio → RTPengine): `127.0.0.1`.
- Inter-pod (Kamailio → Asterisk): `omni_ip_lan` + puertos publicados.
- `PUBLIC_IP` / advertise de Kamailio y RTPengine: `omni_ip_lan` (alcanzable desde el browser del host).

Si el media WebRTC no arma audio, revisá firewall, que `omni_ip_lan` sea la IP correcta del host, y que los rangos RTP estén publicados.

## Fuera de alcance (esta entrega)

pgAdmin, RedisInsight, GitLab runner local, voice_ai. El stack Compose legacy en `docker-compose/dev-env/` no se modifica.

## Archivos relacionados

| Archivo | Rol |
|---------|-----|
| [`inventory_example_devenv.yml`](../inventory_example_devenv.yml) | Inventario AIO local |
| [`inventory_example_devenv_vars.yml`](../inventory_example_devenv_vars.yml) | Overrides (`oml_devenv`, imágenes, binds) |
| [`roles/devenv_images/`](../roles/devenv_images/) | `podman build` de submódulos |
| [`deploy.sh`](../deploy.sh) | Acciones `install` / `devenv` |
| [`docs/pods.md`](pods.md) | Modelo Quadlet de producción |
