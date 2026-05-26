#### This project is part of OMniLeads

![Diagrama deploy tool](./png/omnileads_logo_1.png)

#### 100% Open-Source Contact Center Software
#### [Community Forum](https://forum.omnileads.net/)

---

# Index

* [Overview](#overview)
* [Prerequisites](#prerequisites)
* [Bash + Ansible](#bash-ansible)
* [Bash Script deploy.sh](#bash-script-deploy)
* [Inventory model (pod groups)](#inventory-model)
* [Tenant tracking under instances/](#subscriber-traking)
* [AIO deploy](#aio-deploy)
* [Automatic Dialer](#dialer)
* [TLS Certs provisioning](#tls-cert-provisioning)
* [Security](#security)
* [OMniLeads Podman containers (Quadlet)](#podman-systemd)
* [Asterisk Dialplan & other customizations](#asterisk_customizations)
* [Container image & tag customizations](#components_img)
* [Deploy OMniLeads Enterprise](#oml_enterprise)
* [Backups](#backups)
* [Restore](#restore)
* [Upgrades](#upgrades)
* [Rollback](#rollback)
* [Observability](#observability)
* [Scalability](#scalability)
* [Cluster deployments (AIT, AIO+Edge, fully split)](#ait-deploy)
* [Upgrade from OMniLeads 2.X](#upgrade_from_oml2)
* [User docs](#user-docs)

---

# Overview <a name="overview"></a>

In this section you will find a tool manager for OMniLeads that allows you to:

* Deploy new tenants (AIO or cluster).
* Apply upgrades & rollbacks.
* Run on-demand backups (and restores on the new instance).

It is possible to manage hundreds of OMniLeads instances by keeping one inventory per tenant under `instances/`. The same toolchain renders all the [Podman Quadlet](#podman-systemd) units that implement each OMniLeads component on the target Linux hosts.

![Diagrama deploy tool](./png/deploy-tool-ansible-deploy-instances-multiples.png)

Each OMniLeads tenant is built out of a fixed set of Podman **pods** (one pod = one Quadlet `.pod` file). Those pods can all live on a single host (AIO) or be distributed across multiple hosts (cluster), depending on which inventory pod group you assign each host to.

> Note: If working on a VPS with a public IP address, it is a mandatory requirement that it also has a network interface with the ability to associate a private IP address (`omni_ip_lan`).

# Prerequisites <a name="prerequisites"></a>

```
git clone https://gitlab.com/omnileads/omldeploytool.git
cd omldeploytool/ansible
```

Before running `deploy.sh` you **must** complete the bootstrap, which covers Python venv, Ansible collections and the **Ansible Vault** required by every 3.X tenant: see [ANSIBLE_BOOTSTRAP.md](ANSIBLE_BOOTSTRAP.md).

Quick summary of what bootstrap leaves ready:

* Python venv at `ansible/venv/` with `ansible-core`, `mitogen`, `ansible-lint`, `yamllint` and `black` (pinned in `requirements.txt`).
* Collections installed from `requirements.yml` (at minimum `community.postgresql` and `containers.podman`).
* `group_vars/all/vault.yml` encrypted and `ANSIBLE_VAULT_PASSWORD_FILE` (or `vault_password_file` in `ansible.cfg`) configured.

If you are migrating from a 2.X inventory, first read [UPGRADE_YOUR_INVENTORY.md](UPGRADE_YOUR_INVENTORY.md): the group names, the use of Vault and several variable names changed between 2.X and 3.X.

## Bash + Ansible 📋 <a name="bash-ansible"></a>

An OMniLeads tenant is launched on Linux server(s) running Systemd + Podman by invoking the bash wrapper `deploy.sh`. The wrapper passes the inventory and the action tag(s) to `ansible-playbook` and resolves the right playbook (`playbooks/site.yml`, `playbooks/aio.yml`, `playbooks/cluster.yml`, …).

## Bash Script deploy.sh 📄 <a name="bash-script-deploy"></a>

```
./deploy.sh --help
```

Typical parameters:

* `--action=<action>` (default `install`). Supported actions are listed below.
* `--tenant=<tenant-folder>` to use `instances/<tenant>/inventory.yml`.
* `--inventory=/abs/path/to/inventory.yml` to point at an inventory outside `instances/`. If you omit `--tenant`, `tenant_folder` (used to locate certs/keys under `instances/<tenant>/`) is derived from the inventory path: `instances/<tenant>/inventory.yml` → `<tenant>`, or the filename without extension for other paths (e.g. `/srv/inventories/prod.yml` → `prod`). Pass `--tenant=` to override.
* `--ask-vault-pass` to prompt for the Vault password interactively (otherwise `deploy.sh` uses `ANSIBLE_VAULT_PASSWORD_FILE` or `vault_password_file` from `ansible.cfg`; see [ANSIBLE_BOOTSTRAP.md](ANSIBLE_BOOTSTRAP.md)).

### Supported actions

| Action | Underlying playbook | Notes |
|--------|---------------------|-------|
| `install` | `playbooks/site.yml` | First-time deploy on fresh hosts. Required before partial actions. |
| `update` | `playbooks/site.yml` | Reconcile a deployed tenant without re-running the full bootstrap path. Recommended for routine re-deploys. |
| `upgrade` | `playbooks/site.yml` | Apply a new release / image bump. |
| `prerequisitos` | `playbooks/site.yml` (tags `prerequisitos,gather_facts`) | OS packages, Podman + `omnileads` network, swap, journald, base Quadlet, certs. |
| `voice` | `playbooks/site.yml` | Telephony tasks (`telephony_edge`, `acd`, `interaction_processor`). |
| `omlapp` | `playbooks/site.yml` | Django/uWSGI + Daphne + Nginx + websockets. |
| `omlapp-workers` | `playbooks/site.yml` (tags `omlapp-workers,gather_facts`) | Workers of the omlapp pod. |
| `observability` | `playbooks/site.yml` (tags `observability,gather_facts`, `oml_observability_deploy=true`) | Prometheus + exporters + Promtail. |
| `postgres` / `redis` / `minio` / `gearman` | `playbooks/site.yml` | Single data role re-run. |
| `data` | `playbooks/site.yml` | All data roles (postgres, redis, minio, gearman). |
| `telephony-edge` | `playbooks/site.yml` | Edge telephony role (`rtpengine`, Kamailio WebRTC/PSTN). |
| `kamailio` | `playbooks/site.yml` | Alias for `telephony-edge` (compatibility). |
| `haproxy` | `playbooks/site.yml` | HAProxy on the edge host (role in `site_core.yml`). |
| `edge` | `playbooks/site.yml` | Edge layer (`haproxy` + `telephony-edge`). |
| `acd` / `interaction_processor` / `nginx` / `websockets` / `dialer` / `qa` / `addons` | `playbooks/site.yml` | Single role re-run. |
| `layout-aio` | `playbooks/aio.yml` | Assert AIO layout, then run `site.yml`. |
| `layout-cluster` | `playbooks/cluster.yml` | Assert cluster layout (`oml_layout == "cluster"`, mandatory pod groups), then run `site.yml`. |

> **Removed in 3.X** — `backup`, `restore`, `recycle`, `sentinel` and `restart` are no longer available in `deploy.sh`. Use `oml_manage` on the target host for backup/restore operations.

`prerequisitos` reconciles base OS prep (packages, Quadlet base, swap, certs, `os_configuration`, Podman + `omnileads` network) without touching components. Partial actions (`voice`, `postgres`, …) assume `install` already ran on the host: they only run tasks tagged for that action and rely on `prerequisitos` to bring up Podman/network when needed.

Example:

```
./deploy.sh --action=install --tenant=cloud_oml
./deploy.sh --action=update  --tenant=cloud_oml          # routine reconciliation
./deploy.sh --action=upgrade --inventory=/srv/inventories/prod.yml
```

### Logs

`ansible.cfg` writes the log to `${ANSIBLE_LOG_DIR}/ansible.log` (defaults to `/tmp/oml_install_logs/`). `deploy.sh` creates that directory before each run.

# Inventory model (pod groups) <a name="inventory-model"></a>

OMniLeads 3.X uses a **pod-based inventory**: each Podman pod is associated to one inventory group, and `topology_normalize` infers `data_host`, `edge_host`, `aio_host` and every service endpoint from the host membership.

| Inventory group     | Podman Quadlet pod(s) running there                                                        |
|---------------------|---------------------------------------------------------------------------------------------|
| `omnileads_aio`     | **All pods** below on a single host (AIO).                                                  |
| `data_statefull`    | `data_statefull.pod` → PostgreSQL + MinIO.                                                  |
| `data_stateless`    | `data_stateless.pod` → Redis + Gearman.                                                     |
| `edge`              | `telephony_edge.pod` (RTPengine + Kamailio WebRTC + Kamailio PSTN) + HAProxy front.         |
| `omlapp_web`        | `omlapp_web.pod` → Django/uWSGI, Daphne, Nginx, websockets, Dialer API.                     |
| `omlapp_workers`    | `omlapp_workers.pod` + `interaction_processor`.                                             |
| `dialer_workers`    | `dialer_workers.pod` (OMniDialer workers).                                                  |
| `acd`               | `acd.pod` (Asterisk, ACD app/ARI, FastAGI).                                                 |
| `callrec_processor` | `callrec_processor.pod` (callrec compressor + transcriber).                                 |
| *(implicit)*        | `observability.pod` is added automatically wherever any compute/data/edge pod runs.         |

Co-location rule: **a host can belong to multiple pod groups**, which means several Quadlet pods will run on that host. AIO is just a shortcut for "this single host is in every pod group" — declaring the host under `omnileads_aio` is enough.

> The legacy groups `omnileads_data`, `omnileads_edge`, `omnileads_nodes`, `omnileads_web`, `omnileads_workers` and `omnileads_acd` are **no longer used** by Ansible — see [UPGRADE_YOUR_INVENTORY.md](UPGRADE_YOUR_INVENTORY.md). They are kept only as documentation pointers for users still migrating.

### Two-section inventory

The inventory has two main sections:

1. **Tenant definitions** (`all.children.aio_instances` and `all.children.cluster_instances`) — declare each host with `tenant_id`, `ansible_host`, `omni_ip_lan`, and any per-host overrides.
2. **Pod group memberships** at the bottom of the file: drop each host into the pod groups that should run on it.

AIO example:

![inventory deploy example header](./png/inventory_aio_section.png)

Cluster example:

![inventory deploy 2 section](./png/inventory_cluster_section.png)

### What `topology_normalize` derives

For every host the role computes, based on its group membership:

* `oml_layout` (`aio` or `cluster`).
* Service endpoints used by the templates: `postgres_host`, `redis_host`, `gearman_host`, `kamailio_host`, `kamailio_pstn_host`, `rtpengine_host`, `nginx_host`, `acd_host`, `dialer_host`.
* External service overrides (`postgres_host`, `bucket_url`, `rtpengine_host`, `kamailio_pstn_host`) when you declare them in the inventory.
* The per-component switches (`component_postgresql_enabled`, `component_acd_enabled`, `component_haproxy_enabled`, …) that gate the roles in `playbooks/site_core.yml`.

You normally only need to declare those `*_host` variables manually if you point at services **outside** of the OMniLeads stack (managed Postgres, external S3, etc.).

### Minimal AIO inventory (last section)

```yaml
omnileads_aio:
  hosts:
    algarrobo:
```

### Minimal cluster inventory (last section)

```yaml
omnileads_aio:
  hosts:

data_statefull:
  hosts:
    tenant_example_data:

data_stateless:
  hosts:
    tenant_example_data:

edge:
  hosts:
    tenant_example_edge:

omlapp_web:
  hosts:
    tenant_example_node:

omlapp_workers:
  hosts:
    tenant_example_node:

dialer_workers:
  hosts:
    tenant_example_node:

acd:
  hosts:
    tenant_example_node:

callrec_processor:
  hosts:
    tenant_example_node:
```

The validation playbook `playbooks/cluster.yml` (action `layout-cluster`) asserts that `data_statefull` (or external `postgres_host`), `data_stateless` (or external `redis_host`/`gearman_host`), `edge` (or external `rtpengine_host`/`kamailio_pstn_host`), `omlapp_web` and `acd` are populated. `playbooks/aio.yml` (action `layout-aio`) asserts `oml_layout == "aio"`.

# Tenant tracking under instances/ :office: <a name="subscriber-traking"></a>

Each tenant lives in its own folder under `ansible/instances/`. The folder is in `.gitignore` so sensitive inventories, TLS certs and per-tenant keys stay out of the repository.

```
mkdir -p instances/cloud_oml
cp inventory.yml instances/cloud_oml/inventory.yml
```

For each new tenant, copy the reference `inventory.yml` and customize it.

```
mkdir -p instances/onpremise_oml
cp inventory.yml instances/onpremise_oml/inventory.yml
```

Once the inventory is in place, trigger the deploy:

```
./deploy.sh --action=install --tenant=cloud_oml
```

# Install on a single Linux host (AIO) 🚀 <a name="aio-deploy"></a>

You need a Linux host (Debian / Ubuntu / Rocky / Alma; Debian 13 is the reference) with internet access and your public SSH key authorized for the user declared as `ansible_user` (defaults to `omnileads` with `become: sudo`).

Edit the tenant inventory:

```yaml
all:
  children:
    aio_instances:
      hosts:
        algarrobo:
          tenant_id: algarrobo
          ansible_host: 190.19.150.18
          omni_ip_lan: 172.16.101.44
          fqdn: tenant_name.omnileads.net
          certs: certbot
```

### `omni_ip_lan` and `omni_ip_wan`

* `omni_ip_lan` is the **private** IP every pod publishes ports against and uses to reach its peers.
* `omni_ip_wan` is computed from `nat_ip_addr` (when defined) or, in its absence, from `ansible_host`. Use it for templates that need to advertise a public address.

### `nat_ip_addr` (optional)

If the host is behind NAT and you need PSTN connectivity over the Internet, set `nat_ip_addr: X.X.X.X` with the public IP. RTPengine/Kamailio templates will use it.

### External services

If you want to plug OMniLeads into externally-managed services, declare these variables under the host (or under `cluster_instances:vars`):

* `postgres_host` → skip the bundled PostgreSQL (`component_postgresql_enabled` becomes `false`).
* `bucket_url` → skip MinIO (`component_minio_enabled` becomes `false`) and use that URL as the S3 endpoint.
* `rtpengine_host` and/or `kamailio_pstn_host` → reuse an external SBC / media proxy.

### Generic runtime variables

In the `vars:` block at the bottom of the inventory you set the values that affect every host of the inventory unless overridden per host or per tenant group:

```yaml
vars:
  ansible_user: omnileads
  ansible_become: true
  ansible_become_method: sudo
  ansible_become_user: root

  fqdn: omnileads.example.com
  TZ: America/Argentina/Cordoba
  certs: selfsigned
  notification_email: your_email@domain.com
  ...
```

Finally assign the host to a pod group:

```yaml
omnileads_aio:
  hosts:
    algarrobo:
```

Deploy:

```
./deploy.sh --action=install --tenant=algarrobo
```

Then log in:

```
https://tenant_name.omnileads.net
user: admin
password: admin
```

> ℹ️ The legacy `infra_env` variable (`lan`, `cloud`, `nat`, `custom`, `all`) is **deprecated** and no longer changes the deploy. Use `omni_ip_lan`, `nat_ip_addr`, `rtpengine_env` and the pod-group membership instead.

# Automatic Dialer 📞 <a name="dialer"></a>

In the DIALER section of the inventory you can pick the Dialer engine:

* OMniDialer (FLOSS, default and bundled with OMniLeads).
* Wombat Dialer (Loway commercial alternative).

If you keep OMniDialer the most relevant parameters are:

```yaml
# --- The Dialer Engine: omnidialer or wombat.
dialer_engine: omnidialer
# --- Call attempts per second
dialer_caps: 1
# --- Number of dialer container replicas
dialer_process_campaign_replicas: 5
dialer_process_contact_replicas: 1
dialer_process_event_replicas: 1
# --- Log level for Dialer, 0: Error, 1: Warning, 2: Debug
dialer_log_level: 1
# --- Dialer API password (vaulted)
dialer_password: "{{ vault_dialer_password }}"
```

The `dialer` role installs:

* `dialer_api` inside the `omlapp_web` pod.
* The auxiliary services (`incidence_rules`, `manage_campaign`, `scheduler`, `send_reports`, `render_template`) inside `dialer_workers`.
* Template-based workers (`dialer_process_campaign@`, `dialer_process_contact@`, `dialer_process_event@`) instantiated by replica count.

# TLS/SSL certs provisioning :closed_lock_with_key: <a name="tls-cert-provisioning"></a>

The inventory variable `certs` controls how the TLS material is provided:

### `selfsigned`

Generates and installs self-signed certificates (not recommended for production).

### `certbot`

Provisions Let's Encrypt certificates via certbot. Requirements:

* The instance must resolve its `fqdn` via public DNS.
* TCP/80 must be reachable from the Let's Encrypt CA for the HTTP-01 challenge.
* `notification_email` must be a valid mailbox to receive renewal notifications.

```yaml
certs: certbot
fqdn: omlinstance.domain.com
notification_email: your_email@domain.com
```

### `custom`

Use your own certificate / key pair. Place them inside `instances/<tenant>/` named `cert.pem` and `key.pem`. If your files have different names, declare them per host:

```yaml
aio_instances:
  hosts:
    algarrobo:
      tenant_id: algarrobo
      ansible_host: 190.19.150.18
      omni_ip_lan: 172.16.101.44
      fqdn: tenant_name.omnileads.net
      certs: custom
      cert_file_name: cert_custom_filename.pem
      key_file_name: key_custom_filename.pem
```

```
./deploy.sh --action=install --tenant=cloud_oml
```

# Security 🛡️ <a name="security"></a>

OMniLeads combines Web (HTTPS), WebRTC (WSS + SRTP) and VoIP (SIP + RTP) technologies. Production deployments exposed to the Internet should sit behind:

* A **Reverse Proxy / Load Balancer** in front of Nginx on TCP/443.
* A **Session Border Controller (SBC)** terminating PSTN SIP toward your trunks.

A well-configured **Cloud Firewall** keeps the attack surface small.

![Diagrama security](./png/security.png)

### Firewall rules for an AIO host

| Port              | Protocol | Component                       | Scope                                |
|-------------------|----------|---------------------------------|--------------------------------------|
| 443               | TCP      | Nginx (Web + WebRTC TLS)        | Open to Internet                     |
| `rtpengine_rtp_port_min`–`rtpengine_rtp_port_max` (default 20000–30000) | UDP | RTPengine / WebRTC SRTP | Open to Internet |
| `acd_rtp_port_min`–`acd_rtp_port_max` (default 40000–50000) | UDP | Asterisk PSTN RTP | Open to Internet |
| 5060              | UDP      | Kamailio PSTN / Asterisk SIP    | Restrict to ITSP IP(s)               |
| 9090              | TCP      | Prometheus (`omlapp_web` / AIO) | LAN-only **or** front by HAProxy at `https://<fqdn>/prom` |
| 8404              | TCP      | HAProxy metrics (`/metrics`, edge) | LAN-only (RFC1918 scrape)            |
| 9273              | TCP      | Kamailio PSTN metrics (`/metrics`, edge) | LAN-only                         |
| 9274              | TCP      | Kamailio WebRTC metrics (`/metrics`, edge) | LAN-only                       |
| 22223             | TCP      | RTPengine metrics (edge)        | LAN-only                             |
| 9100              | TCP      | Node exporter (todos los hosts con `observability.pod`) | LAN-only inter-nodo      |
| 9882              | TCP      | Podman exporter (todos los hosts con `observability.pod`) | LAN-only inter-nodo    |
| 9187              | TCP      | Postgres exporter (`data_statefull`) | LAN-only inter-nodo           |
| 9121              | TCP      | Redis exporter (`data_stateless`) | LAN-only inter-nodo              |
| 9418              | TCP      | Gearman exporter (`data_stateless`) | LAN-only inter-nodo            |
| 9117              | TCP      | uWSGI exporter (`omlapp_web`)   | LAN-only inter-nodo                  |

Prometheus is published on `omni_ip_lan:9090` by the Podman `PublishPort` of the observability pod. External access is recommended through HAProxy on the edge host, gated by `haproxy_prom_allowed_src` (list of CIDRs allowed at `/prom`). If `haproxy_prom_allowed_src` is empty or undefined, HAProxy **denies `/prom` by default**.

**Cluster inter-node scrape:** the tenant Prometheus runs on `omlapp_web` / AIO and scrapes every peer via `omni_ip_lan`. The `observability.pod` publishes exporter ports on the LAN IP of each host (see [`observability.pod.j2`](roles/pods/templates/observability.pod.j2)). OS firewalls (`ufw`/`firewalld`) are disabled by Ansible; if your cloud provider filters the **private VPC**, allow the ports above **between tenant nodes only** (not from the Internet). After deploy, Ansible runs a TCP reachability check from the Prometheus host (tag `validate`).

```bash
# From the omlapp_web / AIO host (example PortaVoice)
for t in 10.10.0.14:9100 10.10.0.15:9187 10.10.0.14:8404; do
  nc -zv "${t%:*}" "${t#*:}" || echo "FAIL $t"
done
```

## OMniLeads Podman containers (Quadlet) 🔧 <a name="podman-systemd"></a>

Each pod and each container is defined declaratively under `/etc/containers/systemd/` (Quadlet). systemd auto-generates the matching `*.service` units so you keep using the standard commands:

```bash
systemctl start  nginx.service
systemctl status nginx.service
systemctl stop   nginx.service
```

Behind the scenes the Podman container is rebuilt from the Quadlet definition + its env file every time the service is started.

Example — Nginx Quadlet `/etc/containers/systemd/nginx.container`:

```ini
[Unit]
Description=OMniLeads nginx reverse proxy (Podman Quadlet)
Wants=network-online.target
After=network-online.target
RequiresMountsFor=%t/containers

[Container]
ContainerName=oml-nginx-server
Image=docker.io/freetechsolutions/nginx:20260403-72e1ff68
Pod=omlapp_web.pod
EnvironmentFile=/etc/default/nginx.env
Volume=/etc/omnileads/certs:/etc/omnileads/certs
Volume=django_static:/opt/omnileads/static
Volume=django_callrec_zip:/opt/omnileads/asterisk/var/spool/asterisk/monitor
Label=tier=omlapp
LogDriver=journald
PodmanArgs=--cgroups=no-conmon
Notify=true

[Service]
Restart=on-failure
TimeoutStopSec=70

[Install]
WantedBy=default.target
```

`/etc/default/nginx.env` carries the runtime variables:

```ini
DJANGO_HOSTNAME=172.16.101.221
DAPHNE_HOSTNAME=172.16.101.221
KAMAILIO_HOSTNAME=127.0.0.1
WEBSOCKETS_HOSTNAME=172.16.101.221
S3_ENDPOINT=http://172.16.101.221:9000
```

### Networking model

* All pods run on the internal Podman bridge `omnileads`, **except `telephony_edge`** which uses `Network=host` because it needs full control of SIP/RTP interfaces.
* The data and compute pods publish their ports explicitly on `omni_ip_lan` (PostgreSQL 5432, MinIO 9000/9001, Redis 6379, Gearman 4730, Nginx 80/443, ACD 5060/udp, …).
* When you reboot, **always start the pod service first** (`*-pod.service`); restarting individual containers without an active pod fails in Podman 5.x.

# Asterisk dialplan and other customizations 🛡️ <a name="asterisk_customizations"></a>

Because OMniLeads components are containerized, any customization made *inside* a container is ephemeral. To make permanent modifications to the Asterisk dialplan, scripts or configurations, build a custom image on top of `ACD_IMG`.

An example of how to do this is outlined here: [acd-customizations-example](https://gitlab.com/omnileads/acd-customizations-example/).

# Use your own container registry & images <a name="components_img"></a>

The default image tags for each component are centralized in [`group_vars/all/images.yml`](./group_vars/all/images.yml):

```yaml
# --- OMniLeads images WEB
APP_IMG: docker.io/freetechsolutions/omlapp:20260512-bef97fc2
NGINX_IMG: docker.io/freetechsolutions/nginx:20260403-72e1ff68
WS_IMG: docker.io/freetechsolutions/websockets:20260306-13838d19

# --- OMniLeads images TEL
ACD_IMG: docker.io/freetechsolutions/acd:20260506-c0ce912a
KAMAILIO_IMG: docker.io/freetechsolutions/kamailio:20260408-0292f718
RTPENGINE_IMG: docker.io/freetechsolutions/rtpengine:20260218-4e51bf30
CALLREC_COMPRESSOR_IMG: docker.io/freetechsolutions/callrec_compressor:...
CALLREC_TRANSCRIBER_IMG: docker.io/freetechsolutions/callrec_transcriber:...
FASTAGI_IMG: docker.io/freetechsolutions/fastagi:...

# --- OMniLeads images DIALER
DIALER_API_IMG: docker.io/freetechsolutions/dialer_api:...
DIALER_WORKER_IMG: docker.io/freetechsolutions/dialer_worker:...

# --- Backend & observability
REDIS_IMG: docker.io/redislabs/redisgears:1.0.9
POSTGRES_IMG: docker.io/library/postgres:18-trixie
MINIO_IMG: docker.io/minio/minio:RELEASE.2025-05-24T17-08-30Z
GEARMAN_IMG: docker.io/artefactual/gearmand:1.1.21.2-alpine
HAPROXY_IMG: docker.io/library/haproxy:3.3
PROMETHEUS_IMG: docker.io/prom/prometheus:v3.0.1
...
```

You can override any of these per inventory by re-declaring them under `vars:` (tenant- or host-scoped). For example to deploy the Enterprise edition (see below) or a custom registry:

```yaml
vars:
  APP_IMG: registry.example.com/omlapp:240117.01-enterprise
  ACD_IMG: registry.example.com/acd:240102.01
```

To **force a re-pull** during the next deploy:

```yaml
vars:
  force_image_pull: true
```

## OMniLeads Enterprise :office: <a name="oml_enterprise"></a>

OMniLeads Enterprise adds modules on top of the Community edition (advanced reports, wallboards, automated satisfaction surveys, …).

Override `APP_IMG` so it points at the `-enterprise` tag of the omlapp image:

```yaml
vars:
  APP_IMG: docker.io/your_registry/omlapp:<TAG>-enterprise
```

Then deploy or upgrade as usual:

```
./deploy.sh --action=upgrade --tenant=<tenant>
```

# Backups :floppy_disk: <a name="backups"></a>

The backup workflow dumps both SQL databases (`omnileads` and `omnidialer`) and ships them to a centralized object storage bucket.

### Prerequisites

You need an S3-compatible bucket **external to the OML instance** to hold the backups. Configure the `BACKUP AUTOMATIONS` block in the inventory:

```yaml
# backup_bucket_url: https://sfo3.digitaloceanspaces.com
# backup_bucket_name: your-tenants-backup-bucket
# backup_bucket_access_key: "{{ vault_backup_bucket_access_key }}"
# backup_bucket_secret_key: "{{ vault_backup_bucket_secret_key }}"

# --- if your bucket use a selfsigned SSL cert, uncomment and put this value to true
# backup_bucket_dont_verify_ssl: False

# Time format from 00:00 to 23:59
# cron_backup_mm: 00
# cron_backup_hh: 01

# For restore of OMniLeads DB from backup, uncomment and put here the backup filename
# backup_filename: backup/<tenant>/pgsql-backup-<ts>.sql
# For restore of OMniDialer DB from backup, uncomment and put here the backup filename
# backup_filename_OMD: backup/<tenant>/pgsql-backup-<ts>-OMD.sql
```

Secrets must go through Vault (see [ANSIBLE_BOOTSTRAP.md](ANSIBLE_BOOTSTRAP.md#2-archivo-vaultyml-ansible-vault)).

### Scheduled backups

When the block above is filled the deploy installs a CRON entry on the data host that runs at `cron_backup_hh:cron_backup_mm` and pushes the dump to the bucket.

### On-demand backups

Use `oml_manage` on the data host for on-demand backup/restore operations. The `backup`, `restore` and `recycle` actions were removed from `deploy.sh` in 3.X.

### Backup layout

Each on-demand backup writes a `.sql` file + a timestamped directory under `backup/<tenant>/`.

![Diagrama deploy backup](./png/deploy-backup.png)

# Restore :clock9: <a name="restore"></a>

You can restore on a fresh installation **or** on an already productive instance.

For a **fresh** instance, point at the file with `backup_filename` (and optionally `backup_filename_OMD`):

```yaml
aio_instances:
  hosts:
    algarrobo:
      tenant_id: algarrobo
      ansible_host: 190.19.150.18
      omni_ip_lan: 172.16.101.44
      backup_filename: backup/GML_AIO/pgsql-backup-1762353574.sql
      backup_filename_OMD: backup/GML_AIO/pgsql-backup-1762353574-OMD.sql
```

Then:

```
./deploy.sh --action=install --tenant=algarrobo
```

For a **productive** instance, use `oml_manage` on the target host for restore operations (the `restore` action was removed from `deploy.sh` in 3.X).

# Upgrades :arrows_counterclockwise: <a name="upgrades"></a>

OMniLeads ships a versioned stack of container images for every release. The reference image tags are tracked in [`group_vars/all/images.yml`](./group_vars/all/images.yml) and the mapping per release lives in `Releases-Notes.md` at the root of this repository.

To upgrade:

```
git pull origin main
git checkout <release-tag>
```

Optionally pin specific image versions in the tenant inventory `vars:`:

```yaml
vars:
  APP_IMG: docker.io/freetechsolutions/omlapp:<NEW_TAG>
  ACD_IMG: docker.io/freetechsolutions/acd:<NEW_TAG>
  force_image_pull: true
```

Run the upgrade:

```
./deploy.sh --action=upgrade --tenant=<tenant>
```

For routine re-deploys (no image bump, just configuration drift) prefer `--action=update`:

```
./deploy.sh --action=update --tenant=<tenant>
```

# Rollback :leftwards_arrow_with_hook: <a name="rollback"></a>

A rollback is just an upgrade pointing back at an older image set. Override the relevant `*_IMG` variables in the tenant inventory:

```yaml
vars:
  APP_IMG: docker.io/freetechsolutions/omlapp:<PREVIOUS_TAG>
  ACD_IMG: docker.io/freetechsolutions/acd:<PREVIOUS_TAG>
  NGINX_IMG: docker.io/freetechsolutions/nginx:<PREVIOUS_TAG>
  WS_IMG: docker.io/freetechsolutions/websockets:<PREVIOUS_TAG>
  KAMAILIO_IMG: docker.io/freetechsolutions/kamailio:<PREVIOUS_TAG>
  RTPENGINE_IMG: docker.io/freetechsolutions/rtpengine:<PREVIOUS_TAG>
  FASTAGI_IMG: docker.io/freetechsolutions/fastagi:<PREVIOUS_TAG>
  REDIS_IMG: docker.io/redislabs/redisgears:1.0.9
  force_image_pull: true
```

Then:

```
./deploy.sh --action=upgrade --tenant=<tenant>
```

# Observability :mag_right: :bar_chart: <a name="observability"></a>

Each tenant host gets an `observability.pod` that exposes OS metrics, Redis/Postgres/Asterisk/uWSGI/Gearman exporters and Promtail. This lets you build a multi-tenant observability centre and centralize:

* **Metrics**: scrape each tenant Prometheus from a central Prometheus/Grafana.
* **Logs**: parse log files with Promtail and ship them to Loki.

![Diagrama deploy tool zoom](./png/observability_boxes.png)

Relevant variables:

* `loki_host`: when set, Promtail is deployed and configured to push to that Loki endpoint.
* `oml_observability_deploy=true` (passed automatically by `--action=observability`): allows deploying Promtail even when `loki_host` is not set yet (handy for templating in QA).
* `haproxy_prom_allowed_src`: list of CIDRs allowed at `https://<fqdn>/prom` (defaults to deny-all).
* `haproxy_metrics_port` / `haproxy_metrics_allowed_src`: HAProxy native Prometheus exporter on the edge (default `:8404/metrics`, LAN-only).
* `kamailio_pstn_metrics_port` / `kamailio_webrtc_metrics_port`: Kamailio `prometheus` module on the edge (defaults `9273` / `9274`). Requires a `KAMAILIO_IMG` rebuilt after config changes in `components-git-repo/kamailio`.
* `prometheus_*_exporter_port` / `prometheus_server_port`: ports published on `omni_ip_lan` by `observability.pod` for inter-node scrape (defaults in `group_vars/all/runtime.yml`).
* `homer_host` / `homer_port`: enable HEP packet capture from Asterisk and Kamailio (PSTN + WebRTC) when you operate a Homer instance.
* `homer_kamailio_pstn_capture_id` / `homer_kamailio_webrtc_capture_id`: numeric HEP agent IDs (defaults `2002` / `2003`) to distinguish PSTN vs WebRTC traffic in Homer.
* `homer_pstn_node_name` / `homer_webrtc_node_name`: optional string labels for HEP correlation (defaults `{{ tenant_id }}-pstn` / `{{ tenant_id }}-webrtc`).

![Diagrama deploy tool zoom](./png/observability_MT.png)

Run just the observability layer on existing hosts:

```
./deploy.sh --action=observability --tenant=<tenant>
```

### Promtail / Loki — validación post-deploy

Promtail envía logs de contenedores core (journald, unidades Quadlet `*.service`) a Loki. Tras cambios en [`roles/observability_promtail/templates/promtail.yml`](roles/observability_promtail/templates/promtail.yml), ejecutá el smoke test local:

```bash
cd ansible
ansible-playbook playbooks/smoke_promtail_template.yml
```

En cada host del tenant, confirmá que journald recibe logs del servicio:

```bash
journalctl -u nginx.service -n 3 --no-pager
journalctl -u whatsapp.service -n 3 --no-pager
```

En Grafana / Loki (usar el `tenant_id` del inventario, p. ej. `KonectaPortaVoice`):

```logql
{tenant="<tenant_id>", job="nginx"}
{tenant="<tenant_id>", job="whatsapp"}
{tenant="<tenant_id>", job="dialer_scheduler"}
{tenant="<tenant_id>", job="dialer_api"}
```

Listar jobs activos en el host:

```bash
systemctl list-units 'acd-*.service' 'nginx.service' 'dialer_*.service' 'omnileads.service' --state=running
```

# Scalability settings <a name="scalability"></a>

The default installation is tuned for tenants with 20–30 concurrent users. To scale beyond that, tweak the following blocks in the inventory.

### Asterisk:

```yaml
# RTP port range
acd_rtp_port_min: 40000
acd_rtp_port_max: 50000

# If you set scale_asterisk to true, then you must assign values to
# asterisk_mem_limit, pjsip_threadpool_idle_timeout & pjsip_threadpool_max_size
# https://docs.asterisk.org/Deployment/Performance-Tuning/

# scale_asterisk: true
# acd_pod_cpus: 1
# asterisk_mem_limit: 1G
# pjsip_threadpool_idle_timeout: 120
# pjsip_threadpool_max_size: 25 # 25 for 4 cores, 50 for 8 cores
# pjsip_threadpool_initial_size=8 # number of cores x 2
# pjsip_threadpool_auto_increment=5
# pjsip_timer_t1=100
# pjsip_timer_b=6400
# stasis_initial_size = 10
# stasis_idle_timeout_sec = 120
# stasis_max_size = 60
```

### OMniLeads App uWSGI:

```yaml
# scale_uwsgi: true
# uwsgi_processes: 8
# uwsgi_threads: 1
# uwsgi_listen_queue_size: 2048
# uwsgi_worker_reload_mercy: 60
# uwsgi_evil_reload_on_rss: 3096
```

### PostgreSQL:

```yaml
# scale_postgres: True
# postgres_max_connections: 20 # max(4 * number of CPU cores, 100)
# postgres_shared_buffers: 1GB # Min 128kB, Max 25% of total RAM
# postgres_idle_in_transaction_session_timeout: 60000
# postgres_statement_timeout: 60000
# postgres_effective_cache_size: 4GB # 50%-75% of total RAM
# postgres_wal_buffers: 32MB # between 64KB and 16MB
# postgres_checkpoint_timeout: 10min
# postgres_work_mem: 12MB
# postgres_maintenance_work_mem: 128MB
```

### Redis:

```yaml
# scale_redis: True
# redis_maxmemory: 2gb
# redis_maxmemory_policy: allkeys-lru
# redis_tcp_backlog: 511
# redis_maxclients: 2000
# redis_lazyfree_lazy_eviction: yes
# redis_lazyfree_lazy_expire: yes
```

### Kamailio:

```yaml
# kamailio_shm_size: 64
# kamailio_pkg_size: 8
```

### RTPEngine:

```yaml
rtpengine_rtp_port_min: 20000
rtpengine_rtp_port_max: 30000

# If you set scale_rtpengine to true, assign values to
# rtpengine_timeout, rtpengine_offer_timeout, rtpengine_silent_timeout and rtpengine_final_timeout.
# rtpengine_timeout: 15
# rtpengine_offer_timeout: 15
# rtpengine_silent_timeout: 120
# rtpengine_final_timeout: 3600
```

# Cluster deployments (AIT, AIO+Edge, fully split) 🚀 <a name="ait-deploy"></a>

You can spread the OMniLeads pods across multiple Linux hosts by declaring each host under the right pod groups. The validation playbook (`./deploy.sh --action=layout-cluster --tenant=<tenant>`) enforces that mandatory groups are populated.

![Diagrama deploy cloud services](./png/deploy-tool-tenant-components-ait.png)

### Tenant block under `cluster_instances`

```yaml
cluster_instances:
  children:
    tenant_example_5:
      hosts:
        tenant_example_5_data:
          ansible_host: 164.92.101.39
          omni_ip_lan: 10.10.10.23
        tenant_example_5_edge:
          ansible_host: 143.198.142.25
          omni_ip_lan: 10.10.10.21
        tenant_example_5_node_A:
          ansible_host: 165.232.137.234
          omni_ip_lan: 10.10.10.22
        tenant_example_5_node_B:
          ansible_host: 143.198.151.31
          omni_ip_lan: 10.10.10.20
      vars:
        tenant_id: tenant_example_5
```

`ansible_host` is the SSH endpoint. `omni_ip_lan` is the private IP each pod publishes its ports on and uses to reach the rest of the cluster.

> Note: `data_host`, `edge_host` and `aio_host` are inferred automatically by the `topology_normalize` role from the pod groups (intersected with the tenant group). You only need to declare them under `vars:` to override the inferred value.

### Layout 1 — Two hosts (AIO + Edge)

One host runs every pod **except** `telephony_edge`; a separate edge host runs the telephony edge + HAProxy.

```yaml
omnileads_aio:
  hosts:

data_statefull:
  hosts:
    tenant_example_aio_edge_aio:

data_stateless:
  hosts:
    tenant_example_aio_edge_aio:

edge:
  hosts:
    tenant_example_aio_edge_edge:

omlapp_web:
  hosts:
    tenant_example_aio_edge_aio:

omlapp_workers:
  hosts:
    tenant_example_aio_edge_aio:

dialer_workers:
  hosts:
    tenant_example_aio_edge_aio:

acd:
  hosts:
    tenant_example_aio_edge_aio:

callrec_processor:
  hosts:
    tenant_example_aio_edge_aio:
```

> Do **not** put the AIO host inside `omnileads_aio` in this layout: that would also try to spawn `telephony_edge` on it. The compute host is just listed in every pod group except `edge`.

Quick post-deploy check on the AIO host: `data_statefull-pod.service`, `data_stateless-pod.service`, `acd-pod.service`, `dialer_workers-pod.service`, `omlapp_web-pod.service`, `omlapp_workers-pod.service`, `callrec_processor-pod.service`, `observability-pod.service` should all be active, **and `telephony_edge-pod.service` should NOT be**. On the edge: `telephony_edge-pod.service`, `observability-pod.service` and `haproxy.service` active.

Connectivity: HAProxy on the edge must reach Nginx on the AIO via `omni_ip_lan` (TCP/443 backend). The ACD on the AIO publishes 5060/udp on the LAN so the edge Kamailio PSTN can dial it (`kamailio_pstn_out` in `acd.pod.j2`).

### Layout 2 — AIT (data + edge + compute monolithic)

```yaml
omnileads_aio:
  hosts:

data_statefull:
  hosts:
    tenant_example_5_data:

data_stateless:
  hosts:
    tenant_example_5_data:

edge:
  hosts:
    tenant_example_5_edge:

omlapp_web:
  hosts:
    tenant_example_5_node_A:

omlapp_workers:
  hosts:
    tenant_example_5_node_A:

dialer_workers:
  hosts:
    tenant_example_5_node_A:

acd:
  hosts:
    tenant_example_5_node_A:

callrec_processor:
  hosts:
    tenant_example_5_node_A:
```

If you want to spread compute across `node_A` and `node_B`, list each one in the pod groups you want them to host (e.g. ACD only on `node_A`, dialer workers on `node_B`, etc.).

### Layout 3 — Five hosts (data + edge + web + workers + acd)

A more aggressive split where every compute concern has its own host:

```yaml
omnileads_aio:
  hosts:

data_statefull:
  hosts:
    tenant_example_split_data:

data_stateless:
  hosts:
    tenant_example_split_data:

edge:
  hosts:
    tenant_example_split_edge:

omlapp_web:
  hosts:
    tenant_example_split_web:

omlapp_workers:
  hosts:
    tenant_example_split_workers:

dialer_workers:
  hosts:
    tenant_example_split_workers:

acd:
  hosts:
    tenant_example_split_acd:

callrec_processor:
  hosts:
    tenant_example_split_workers:
```

In this layout `topology_normalize` infers:

* `nginx_host` and `dialer_host` from the host in `omlapp_web`.
* `acd_host` from the host in `acd` (FastAGI corre dentro del pod `acd`, acd-server lo invoca como `127.0.0.1`).
* `data_host` from the host(s) in `data_statefull` / `data_stateless`.
* `edge_host` from the host in `edge`.

Deploy the cluster:

```
./deploy.sh --action=layout-cluster --tenant=<tenant>   # optional validation
./deploy.sh --action=install        --tenant=<tenant>
```

# Upgrade from OMniLeads 2.X :arrows_counterclockwise: <a name="upgrade_from_oml2"></a>

OMniLeads 3.X breaks compatibility with the 2.X inventory layout and runtime. To migrate a 2.X tenant:

1. Follow the variable / group renames documented in [UPGRADE_YOUR_INVENTORY.md](UPGRADE_YOUR_INVENTORY.md). Highlights:
   * Switch from the legacy `omnileads_data` / `omnileads_voice` / `omnileads_app` / `omnileads_dialer` groups to the pod groups documented above.
   * Centralize secrets in `group_vars/all/vault.yml` (Vault).
   * Drop deprecated variables (`infra_env`, `omnileads_img`, `asterisk_img`, `upgrade_from_oml_1`, `restore_file_timestamp`, `callrec_transcriptions`, `acd_pjsip_transport_*`, `acd_api_listen_ip`, `dialer_user`).
   * Re-set image references through `APP_IMG`, `ACD_IMG`, `NGINX_IMG`, etc. (or rely on the defaults of `group_vars/all/images.yml`).
2. Keep the same `postgres_user`, `postgres_password` and `postgres_database` you had on 2.X (now wired through Vault).
3. Make sure the variables match between the 2.X source and the new 3.X tenant before pointing the new instance at the backup files (`backup_filename` and `backup_filename_OMD`).
4. Enable the migration flag in the host vars:

```yaml
upgrade_from_2X: true
```

5. Run the install/upgrade. The `upgrade_from_2X` role handles the cleanup of the legacy systemd units, the OS upgrade Debian 12 → Debian 13 and the SQL restore (`omnileads` and optionally `omnidialer`).

```
./deploy.sh --action=install --tenant=<new_tenant>
```

# User docs <a name="user-docs"></a>

This section covered the application deployment. The user manual is available at:

https://docs.omnileads.net/

Enjoy OMniLeads!
