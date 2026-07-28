#### This project is part of OMniLeads

![Diagrama deploy tool](./png/omnileads_logo_1.png)

#### 100% Open-Source Contact Center Software
#### [Community Forum](https://forum.omnileads.net/)

---

# Index

* [Overview](#overview)
* [Prerequisites](#prerequisites)
* [Target Linux host preparation](#target-host-prep)
* [Bash + Ansible](#bash-ansible)
* [Bash Script deploy.sh](#bash-script-deploy)
* [Configuration model (group_vars)](#group-vars)
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

It is possible to manage hundreds of OMniLeads instances by keeping one inventory per tenant under `instances/`, while shared configuration and secrets live under `group_vars/all/` ([details](#group-vars)). The same toolchain renders all the [Podman Quadlet](#podman-systemd) units that implement each OMniLeads component on the target Linux hosts.

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
* Shared operator settings in [`group_vars/all/tenants_global.yml`](group_vars/all/tenants_global.yml) (TLS, dialer, Postgres tuning, telephony edge, integrations, …).
* Internal runtime constants in [`group_vars/all/runtime.yml`](group_vars/all/runtime.yml) (ports, pod names, container names, journald, …).

If you are migrating from a 2.X inventory, first read [UPGRADE_YOUR_INVENTORY.md](UPGRADE_YOUR_INVENTORY.md): the group names, the use of Vault, the split of `group_vars/` and several variable names changed between 2.X and 3.X.

## Target Linux host preparation <a name="target-host-prep"></a>

Before running `./deploy.sh --action=install`, each target Linux host must expose a dedicated **Ansible admin user** over SSH. The install playbook creates and owns the `omnileads` OS user (`usuario: omnileads` in `group_vars/all/runtime.yml`); **`root` and `omnileads` are reserved** and must not be used as `ansible_user`.

Pick any other non-root username (the examples below use `omladmin`).

### 1. Create the admin user

On the target host (initial bootstrap as `root` or your cloud provider's default user):

```bash
sudo adduser omladmin
```

On Debian/Ubuntu you may also add the user to the `sudo` group:

```bash
sudo usermod -aG sudo omladmin
```

### 2. Authorize the Ansible deployer's SSH key

Create the `.ssh` directory and populate `authorized_keys` with the **public key** from the machine that runs Ansible (your deployer workstation or CI runner):

```bash
sudo mkdir -p /home/omladmin/.ssh
sudo chmod 700 /home/omladmin/.ssh
```

On the **deployer** machine, display the public key you will use:

```bash
cat ~/.ssh/id_ed25519.pub
# or: cat ~/.ssh/id_rsa.pub
```

Back on the **target host**, install that key:

```bash
sudo tee /home/omladmin/.ssh/authorized_keys <<'EOF'
ssh-ed25519 AAAA...your-deployer-public-key... deployer@workstation
EOF
sudo chmod 600 /home/omladmin/.ssh/authorized_keys
sudo chown -R omladmin:omladmin /home/omladmin/.ssh
```

Verify passwordless SSH from the deployer:

```bash
ssh omladmin@<target-host-ip>
```

### 3. Grant passwordless sudo

Ansible escalates privileges with `become: sudo`. Add a sudoers drop-in (validate with `visudo -c` after editing):

```bash
echo 'omladmin ALL=(ALL) NOPASSWD:ALL' | sudo tee /etc/sudoers.d/omladmin
sudo chmod 440 /etc/sudoers.d/omladmin
sudo visudo -c
```

Alternatively, edit `/etc/sudoers` with `visudo` and append the same line.

### 4. Configure the Ansible admin user

SSH connection settings live in [`group_vars/all/tenants_global.yml`](group_vars/all/tenants_global.yml). Set `ansible_user` to the admin account you created above and store the username in Vault:

```yaml
# group_vars/all/tenants_global.yml
ansible_user: "{{ vault_ansible_user }}"
ansible_become: true
ansible_become_method: sudo
ansible_become_user: root
```

```yaml
# group_vars/all/vault.yml (encrypted)
vault_ansible_user: omladmin
```

> **Do not** set `ansible_user: omnileads` or `ansible_user: root`. The install role will create the `omnileads` system account for running OMniLeads services and containers.

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
| `wazuh-agent` | `playbooks/site.yml` (tags `wazuh-agent,gather_facts`) | Wazuh Agent OS (repo oficial + enrollment). Requiere `wazuh_manager`. Desactivar con `wazuh: false` en el inventario. |
| `postgres` / `redis` / `minio` / `gearman` | `playbooks/site.yml` | Single data role re-run. |
| `data` | `playbooks/site.yml` | All data roles (postgres, redis, minio, gearman). |
| `telephony-edge` | `playbooks/site.yml` | Edge telephony role (`rtpengine`, Kamailio WebRTC/PSTN). |
| `kamailio` | `playbooks/site.yml` | Alias for `telephony-edge` (compatibility). |
| `haproxy` | `playbooks/site.yml` | HAProxy on the edge host (role in `site_core.yml`). |
| `edge` | `playbooks/site.yml` | Edge layer (`haproxy` + `telephony-edge`). |
| `acd` / `interaction_processor` / `nginx` / `websockets` / `dialer` / `qa` / `addons` | `playbooks/site.yml` | Single role re-run. |
| `layout-aio` | `playbooks/aio.yml` | Assert AIO layout, then run `site.yml`. |
| `layout-cluster` | `playbooks/cluster.yml` | Assert cluster layout (`oml_layout == "cluster"`, mandatory pod groups), then run `site.yml`. |

> **Removed in 3.X** — `recycle`, `sentinel` and `restart` are no longer available in `deploy.sh`. Use `oml_manage` on the target host for backup/restore operations.

`prerequisitos` reconciles base OS prep (packages, Quadlet base, swap, certs, `os_configuration`, Podman + `omnileads` network) without touching components. Partial actions (`voice`, `postgres`, …) assume `install` already ran on the host: they only run tasks tagged for that action and rely on `prerequisitos` to bring up Podman/network when needed.

Example:

```
./deploy.sh --action=install --tenant=cloud_oml
./deploy.sh --action=update  --tenant=cloud_oml          # routine reconciliation
./deploy.sh --action=upgrade --inventory=/srv/inventories/prod.yml
```

### Logs

`ansible.cfg` writes the log to `${ANSIBLE_LOG_DIR}/ansible.log` (defaults to `/tmp/oml_install_logs/`). `deploy.sh` creates that directory before each run.

# Configuration model (group_vars) <a name="group-vars"></a>

OMniLeads 3.X separates **what runs where** (tenant inventory) from **how it is configured** (shared `group_vars`). `playbooks/site_core.yml` loads the files below on every run, in this order:

| File | Scope | What to edit |
|------|-------|--------------|
| [`group_vars/all/runtime.yml`](group_vars/all/runtime.yml) | All tenants | Rarely. Internal constants: Podman network (`oml_network: omnileads`), component ports, Quadlet pod/container names, journald limits, `dialer_engine`, `pods_role_tags`, … |
| [`group_vars/all/vault.yml`](group_vars/all/vault.yml) | All tenants | **Secrets only** (encrypted). Passwords, API keys, bucket credentials, per-operator SSH user, optional Loki/Homer/backup keys. See [ANSIBLE_BOOTSTRAP.md](ANSIBLE_BOOTSTRAP.md#2-archivo-vaultyml-ansible-vault). |
| [`group_vars/all/images.yml`](group_vars/all/images.yml) | All tenants | Container image tags (`APP_IMG`, `ACD_IMG`, …). Bump on upgrade or pin a rollback set. |
| [`group_vars/all/tenants_global.yml`](group_vars/all/tenants_global.yml) | All tenants | **Main operator config**: `TZ`, `certs`, Postgres/Redis/uWSGI tuning, bucket defaults, dialer caps, Kamailio/RTPengine, observability hooks, backup CRON, integrations. Values reference `{{ vault_* }}` where sensitive. |

The tenant inventory (`instances/<tenant>/inventory.yml`) should declare only **per-tenant / per-host** data:

* Host identity and connectivity: `tenant_id`, `ansible_host`, `omni_ip_lan`.
* Layout: pod-group membership (section 2 of the inventory).
* Overrides that differ from `tenants_global.yml` for one tenant: `fqdn`, `bucket_url`, `kamailio_webrtc_iface`, `certs`, external `postgres_host` / `rtpengine_host`, upgrade flags, restore filenames, …

Ansible precedence applies as usual: a variable set on a host or under a tenant group in the inventory **wins** over the same key in `tenants_global.yml`.

### Secrets in `vault.yml`

Global secrets referenced from `tenants_global.yml` include:

| Vault key | Used for |
|-----------|----------|
| `vault_ansible_user` | SSH admin user (`ansible_user`) |
| `vault_notification_email` | Certbot / notification mailbox |
| `vault_postgres_password` | Bundled PostgreSQL |
| `vault_minio_http_admin_user` / `vault_minio_http_admin_pass` | MinIO console |
| `vault_bucket_name` / `vault_bucket_url` / `vault_bucket_access_key` / `vault_bucket_secret_key` | Object storage (defaults) |
| `vault_django_secret_key` / `vault_kamailio_webrtc_auth_eph_key` | Django sessions & WebRTC auth |
| `vault_acd_api_user` / `vault_acd_api_password` | Asterisk AMI |
| `vault_dialer_password` | Dialer API |
| `vault_google_api_key` / `vault_google_cloud_projectid` | Maps / GCP integrations |
| `vault_callrec_transcriber_api_key` | Call recording transcription |
| `vault_loki_url` / `vault_haproxy_prom_allowed_src` | Observability (optional) |
| `vault_homer_host` / `vault_homer_port` | HEP capture (optional) |
| `vault_backup_bucket_name` | Backup bucket name (optional) |

Per-tenant endpoints (SSH IP, LAN IP, tenant-specific FQDN or bucket) can live in Vault too — the shipped [`inventory_example_*.yml`](inventory_example_1.yml) files reference them as `vault_tenant_<name>_*` on each host.

# Inventory model (pod groups) <a name="inventory-model"></a>

OMniLeads 3.X uses a **pod-based inventory**: each Podman pod is associated to one inventory group, and `topology_normalize` infers `data_host`, `edge_host`, `aio_host` and every service endpoint from the host membership.

| Inventory group     | Podman Quadlet pod(s) running there                                                        |
|---------------------|---------------------------------------------------------------------------------------------|
| `omnileads_aio`     | **All pods** below on a single host (AIO).                                                  |
| `data_statefull`    | `data_statefull.pod` → PostgreSQL + MinIO.                                                  |
| `data_stateless`    | `data_stateless.pod` → Redis + Gearman.                                                     |
| `edge`              | `telephony_edge.pod` (RTPengine + Kamailio WebRTC + Kamailio PSTN) + HAProxy front.         |
| `omlapp_web`        | `omlapp_web.pod` → Django/uWSGI, Daphne, Nginx, websockets, Dialer API.                     |
| `omlapp_workers`    | `omlapp_workers.pod`. (Django workers )                                                     |
| `dialer_workers`    | `dialer_workers.pod` (OMniDialer workers).                                                  |
| `acd`               | `acd.pod` (Asterisk, ACD app/ARI, FastAGI).                                                 |
| `callrec_processor` | `callrec_processor.pod` (callrec compressor + transcriber).                                 |
| *(implicit)*        | `observability.pod` is added automatically wherever any compute/data/edge pod runs.         |

Co-location rule: **a host can belong to multiple pod groups**, which means several Quadlet pods will run on that host. AIO is just a shortcut for "this single host is in every pod group" — declaring the host under `omnileads_aio` is enough.

> The legacy groups `omnileads_data`, `omnileads_edge`, `omnileads_nodes`, `omnileads_web`, `omnileads_workers` and `omnileads_acd` are **no longer used** by Ansible — see [UPGRADE_YOUR_INVENTORY.md](UPGRADE_YOUR_INVENTORY.md). They are kept only as documentation pointers for users still migrating.

### Two-section inventory

Every tenant `inventory.yml` is a **single file with two sections**. Ansible loads both; `topology_normalize` intersects them to derive `oml_layout`, service endpoints and component switches.

| Section | Location in the file | Purpose |
|---------|----------------------|---------|
| **1 — Tenant definitions** | Top, under `all:` | Register each Linux host: SSH endpoint, LAN IP, tenant identity and optional overrides. |
| **2 — Pod topology** | Bottom, after the comment blocks | Map each host name into pod groups so Quadlet knows which pods run on which machine. |

Host names in section 2 **must match** the keys declared in section 1.

#### Section 1 — `all:` tenant block

Use **`aio_instances`** when the tenant runs on a single host (All-in-One). Use **`cluster_instances`** when pods are spread across multiple hosts.

**AIO** — one host under `aio_instances`:

```yaml
all:
  children:
    aio_instances:
      hosts:
        test_aio:
          tenant_id: test_aio
          ansible_host: "{{ vault_tenant_test_aio_ansible_host }}"
          omni_ip_lan: "{{ vault_tenant_test_aio_omni_ip_lan }}"
          fqdn: "{{ vault_tenant_test_aio_fqdn }}"
          bucket_name: "{{ vault_tenant_test_aio_bucket_name }}"
          itsp_nodes: "{{ vault_tenant_test_aio_itsp_nodes }}"
          kamailio_webrtc_iface: eth1
```

**Cluster** — one nested group per tenant under `cluster_instances`, with shared settings in `vars:`:

```yaml
all:
  children:
    cluster_instances:
      children:
        tenant_z:
          hosts:
            tenant_z_data_statefull:
              tenant_id: tenant_z_data_statefull
              ansible_host: "{{ vault_tenant_z_data_statefull_ansible_host }}"
              omni_ip_lan: "{{ vault_tenant_z_data_statefull_omni_ip_lan }}"
            tenant_z_edge:
              tenant_id: tenant_z_edge
              ansible_host: "{{ vault_tenant_z_edge_ansible_host }}"
              omni_ip_lan: "{{ vault_tenant_z_edge_omni_ip_lan }}"
            # … one entry per Linux host in the cluster
          vars:
            tenant_id: tenant_z
            fqdn: "{{ vault_tenant_z_fqdn }}"
            bucket_url: "{{ vault_tenant_z_bucket_url }}"
            bucket_name: "{{ vault_tenant_z_bucket_name }}"
            itsp_nodes: "{{ vault_tenant_z_itsp_nodes }}"
            kamailio_webrtc_iface: ens18
```

Variables typically set **in the inventory** (section 1):

| Variable | When to set |
|----------|-------------|
| `tenant_id`, `ansible_host`, `omni_ip_lan` | Always — identity, SSH target and private IP for inter-pod traffic. |
| `fqdn`, `bucket_url`, `itsp_nodes`, `kamailio_webrtc_iface`, `certs` | When this tenant differs from [`tenants_global.yml`](group_vars/all/tenants_global.yml); otherwise inherit the global default. |
| `upgrade_from_2X`, `postgres_user`, `postgres_password`, `bucket_url` | Upgrading an existing 2.x AIO install (see [`inventory_example_2.yml`](inventory_example_2.yml)); overrides the global `upgrade_from_2X: false`. |
| `postgres_host`, `rtpengine_host`, `kamailio_pstn_host` | Pointing at services **outside** the OMniLeads stack (skips the bundled component). |
| `backup_filename` / `backup_filename_OMD` | Restore workflow (see [Restore](#restore)). |

Everything else (dialer caps, Postgres tuning, uWSGI scale, TLS defaults, backup CRON schedule, observability hooks, …) is edited in [`group_vars/all/tenants_global.yml`](group_vars/all/tenants_global.yml), not in the inventory.

#### Section 2 — Pod groups

The bottom of the file always lists the same pod groups, separated by comment headers. Only populate the groups that match your layout; leave the rest empty.

**AIO** — list the host only under `omnileads_aio`; every pod runs on that machine:

```yaml
omnileads_aio:
  hosts:
    test_aio:

data_statefull:
  hosts:

# … remaining pod groups left empty
```

**Cluster** — leave `omnileads_aio` empty and assign each host to the pod groups it should run. A host can appear in **multiple** groups (co-location):

```yaml
omnileads_aio:
  hosts:

data_statefull:
  hosts:
    tenant_c_data:

data_stateless:
  hosts:
    tenant_c_data:    # same host as data_statefull → one machine runs both pods

edge:
  hosts:
    tenant_c_edge:

omlapp_web:
  hosts:
    tenant_c_node:    # compute host runs every app/ACD/dialer pod
# …
```

> In an **AIO + Edge** layout the compute host must **not** be listed under `omnileads_aio` — that would also spawn `telephony_edge` on it. Instead, put data/stateless/compute pods on the AIO host via the individual pod groups and reserve `edge` for the edge host only (see [Layout 1 — Two hosts (AIO + Edge)](#ait-deploy)).

#### Reference examples

Copy and adapt one of the shipped examples into `instances/<tenant>/inventory.yml`:

| File | Layout | Section 1 | Section 2 |
|------|--------|-----------|-----------|
| [`inventory_example_1.yml`](inventory_example_1.yml) | **AIO** — fresh install | `aio_instances` → `test_aio` | Host under `omnileads_aio` only |
| [`inventory_example_2.yml`](inventory_example_2.yml) | **AIO** — upgrade from 2.x | `aio_instances` → `test_b` with `upgrade_from_2X` and legacy DB/bucket vars | Host under `omnileads_aio` only |
| [`inventory_example_3.yml`](inventory_example_3.yml) | **Fully split cluster** — one host per pod tier | `cluster_instances` → `tenant_z` with 8 dedicated hosts | Each pod group points at its own host; `omnileads_aio` empty |
| [`inventory_example_4.yml`](inventory_example_4.yml) | **AIT** — data + edge + monolithic compute (3 hosts) | `cluster_instances` → `tenant_c` with `tenant_c_data`, `tenant_c_edge`, `tenant_c_node` | Data + stateless co-located on `tenant_c_data`; edge on `tenant_c_edge`; all compute pods on `tenant_c_node` |
| [`inventory_example_5.yml`](inventory_example_5.yml) | **AIO + Edge** — compute + telephony split (2 hosts) | `cluster_instances` → `tenant_x` with `tenant_x_node` and `tenant_x_edge` | Data/stateless and every compute pod on `tenant_x_node`; `edge` on `tenant_x_edge`; `omnileads_aio` empty |

Workflow for a new tenant:

```
cp inventory_example_<N>.yml instances/<tenant>/inventory.yml
# edit section 1 (hosts, IPs, vault refs) and section 2 (pod-group membership)
./deploy.sh --action=install --tenant=<tenant>
```

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
cp inventory_example_1.yml instances/cloud_oml/inventory.yml
```

For each new tenant, copy the closest [`inventory_example_*.yml`](inventory_example_1.yml) and customize section 1 (hosts) and section 2 (pod groups). Shared settings belong in [`group_vars/all/tenants_global.yml`](group_vars/all/tenants_global.yml).

```
mkdir -p instances/onpremise_oml
cp inventory_example_4.yml instances/onpremise_oml/inventory.yml
```

Once the inventory is in place, trigger the deploy:

```
./deploy.sh --action=install --tenant=cloud_oml
```

# Install on a single Linux host (AIO) 🚀 <a name="aio-deploy"></a>

You need a Linux host (Debian / Ubuntu / Rocky / Alma; Debian 13 is the reference) with internet access and a dedicated Ansible admin user prepared as described in [Target Linux host preparation](#target-host-prep) (`ansible_user`, e.g. `omladmin`, with passwordless `sudo`).

Edit the tenant inventory (hosts + topology) and, if needed, [`tenants_global.yml`](group_vars/all/tenants_global.yml) / [`vault.yml`](group_vars/all/vault.yml):

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
          # certs: certbot   # optional override; default comes from tenants_global.yml
```

### `omni_ip_lan` and `omni_ip_wan`

* `omni_ip_lan` is the **private** IP every pod publishes ports against and uses to reach its peers.
* `omni_ip_wan` is computed from `nat_ip_addr` (when defined) or, in its absence, from `ansible_host`. Use it for templates that need to advertise a public address.

### `nat_ip_addr` (optional)

If the host is behind NAT and you need PSTN connectivity over the Internet, set `nat_ip_addr: X.X.X.X` with the public IP in the inventory host vars or in [`tenants_global.yml`](group_vars/all/tenants_global.yml) (see the `TELEPHONY EDGE PROXY` block). RTPengine/Kamailio templates will use it.

### External services

If you want to plug OMniLeads into externally-managed services, declare these variables under the host (or under `cluster_instances:vars`):

* `postgres_host` → skip the bundled PostgreSQL (`component_postgresql_enabled` becomes `false`).
* `bucket_url` → skip MinIO (`component_minio_enabled` becomes `false`) and use that URL as the S3 endpoint.
* `rtpengine_host` and/or `kamailio_pstn_host` → reuse an external SBC / media proxy.

### Global tenant configuration

Shared settings for every tenant live in [`group_vars/all/tenants_global.yml`](group_vars/all/tenants_global.yml). Edit that file (and the matching `vault_*` keys in [`vault.yml`](group_vars/all/vault.yml)) instead of duplicating a `vars:` block in each inventory.

Example excerpt:

```yaml
# group_vars/all/tenants_global.yml
TZ: America/Argentina/Cordoba
certs: custom
ssl_cert_file_name: FTS_Sephir_cert.pem
ssl_key_file_name: FTS_Sephir_key.pem
notification_email: "{{ vault_notification_email }}"

scale_uwsgi: true
uwsgi_processes: 4

dialer_caps: 3
dialer_process_campaign_replicas: 5
dialer_log_level: 1

kamailio_webrtc_iface: eth1
rtpengine_env: prod
rtpengine_rtp_port_min: 20000
rtpengine_rtp_port_max: 30000
```

Internal ports, pod names and container names are **not** duplicated here — they stay in [`group_vars/all/runtime.yml`](group_vars/all/runtime.yml) (`websocket_port`, `oml_network`, `nginx_container_name`, `prometheus_server_port`, …).

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

Dialer settings are centralized in [`group_vars/all/tenants_global.yml`](group_vars/all/tenants_global.yml) (`DIALER` block). The engine default (`dialer_engine: omnidialer`) is set in [`runtime.yml`](group_vars/all/runtime.yml).

* OMniDialer (FLOSS, default and bundled with OMniLeads).
* Wombat Dialer (Loway commercial alternative) — set `dialer_engine: wombat` in `runtime.yml`.

If you keep OMniDialer the most relevant parameters are:

```yaml
# group_vars/all/tenants_global.yml
# --- Call attempts per second
dialer_caps: 3
# --- Number of dialer container replicas
dialer_process_campaign_replicas: 5
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

The `certs` variable in [`group_vars/all/tenants_global.yml`](group_vars/all/tenants_global.yml) controls how TLS material is provided (`selfsigned`, `certbot` or `custom`). Override it per host in the inventory when a single tenant needs a different mode.

### `selfsigned`

Generates and installs self-signed certificates (not recommended for production).

### `certbot`

Provisions Let's Encrypt certificates via certbot. Requirements:

* The instance must resolve its `fqdn` via public DNS.
* TCP/80 must be reachable from the Let's Encrypt CA for the HTTP-01 challenge.
* `notification_email` must be a valid mailbox to receive renewal notifications (`vault_notification_email` in [`vault.yml`](group_vars/all/vault.yml)).

```yaml
# tenants_global.yml
certs: certbot
# fqdn per tenant still comes from the inventory host / tenant vars block
notification_email: "{{ vault_notification_email }}"
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
      ssl_cert_file_name: cert_custom_filename.pem
      ssl_key_file_name: key_custom_filename.pem
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
| 5060              | UDP      | Kamailio PSTN SIP               | Restrict to ITSP IP(s)               |
| `acd_trunk_sip_port` (default 6070) | UDP | Asterisk trunk SIP (desde Kamailio) | LAN / inter-nodo según topología |
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

Prometheus is published on `omni_ip_lan:9090` by the Podman `PublishPort` of the observability pod. External access is recommended through HAProxy on the edge host, gated by `haproxy_prom_allowed_src` (uncomment in [`tenants_global.yml`](group_vars/all/tenants_global.yml) with `vault_haproxy_prom_allowed_src` — list of CIDRs allowed at `/prom`). If `haproxy_prom_allowed_src` is empty or undefined, HAProxy **denies `/prom` by default**.

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

* All pods run on the internal Podman bridge `omnileads` (`oml_network` in [`runtime.yml`](group_vars/all/runtime.yml)), **except `telephony_edge` and `acd`** which use `Network=host` for SIP/RTP and telephony ports on the host namespace.
* The data and compute pods publish their ports explicitly on `omni_ip_lan` (PostgreSQL 5432, MinIO 9000/9001, Redis 6379, Gearman 4730, Nginx 80/443, …). The ACD pod listens natively on the host: Kamailio PSTN uses `:5060`, Asterisk trunk `:6070` (`acd_trunk_sip_port`), ARI `:7088`, metrics `:7098`.
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

You can override any of these in [`group_vars/all/images.yml`](group_vars/all/images.yml) or, for a one-off tenant, re-declare them under the tenant `vars:` block in the inventory. For example to deploy the Enterprise edition (see below) or a custom registry:

```yaml
# group_vars/all/images.yml — or tenant inventory vars: for a single tenant
APP_IMG: registry.example.com/omlapp:240117.01-enterprise
ACD_IMG: registry.example.com/acd:240102.01
```

To **force a re-pull** during the next deploy, set `force_image_pull: true` in [`runtime.yml`](group_vars/all/runtime.yml) or override it per tenant in the inventory.

## OMniLeads Enterprise :office: <a name="oml_enterprise"></a>

OMniLeads Enterprise adds modules on top of the Community edition (advanced reports, wallboards, automated satisfaction surveys, …).

Override `APP_IMG` in [`images.yml`](group_vars/all/images.yml) so it points at the `-enterprise` tag of the omlapp image:

```yaml
APP_IMG: docker.io/your_registry/omlapp:<TAG>-enterprise
```

`topology_normalize` sets `component_addons_enabled` only when that tag ends with `-enterprise` (and the host runs `omlapp_web` / AIO). That gates the `enterprise` Quadlet pod and the `addons` role (wallboard, bulk messages). A community `APP_IMG` skips both.

Then deploy or upgrade as usual:

```
./deploy.sh --action=upgrade --tenant=<tenant>
```

# Backups :floppy_disk: <a name="backups"></a>

The backup workflow dumps both SQL databases (`omnileads` and `omnidialer`) and ships them to a centralized object storage bucket.

### Prerequisites

You need an S3-compatible bucket **external to the OML instance** to hold the backups. Uncomment and fill the `BACKUP AUTOMATIONS` block in [`group_vars/all/tenants_global.yml`](group_vars/all/tenants_global.yml):

```yaml
# group_vars/all/tenants_global.yml
backup_bucket_url: "{{ vault_bucket_url }}"
backup_bucket_name: "{{ vault_backup_bucket_name }}"
backup_bucket_access_key: "{{ vault_bucket_access_key }}"
backup_bucket_secret_key: "{{ vault_bucket_secret_key }}"

# --- if your bucket use a selfsigned SSL cert, uncomment and put this value to true
# backup_bucket_dont_verify_ssl: False

# Time format from 00:00 to 23:59
cron_backup_mm: 00
cron_backup_hh: 01

# For restore of OMniLeads DB from backup, set backup_filename on the host in the inventory instead
# backup_filename: backup/<tenant>/pgsql-backup-<ts>.sql
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

Optionally pin specific image versions in [`group_vars/all/images.yml`](group_vars/all/images.yml):

```yaml
APP_IMG: docker.io/freetechsolutions/omlapp:<NEW_TAG>
ACD_IMG: docker.io/freetechsolutions/acd:<NEW_TAG>
force_image_pull: true   # runtime.yml default, or set here temporarily
```

Run the upgrade:

```
./deploy.sh --action=upgrade --tenant=<tenant>
```

#### Upgrade: ACD host network + Asterisk trunk `:6070`

This release moves the `acd` pod to `Network=host` and listens for PSTN trunk SIP on `acd_trunk_sip_port` (default **6070**); Kamailio PSTN stays on **5060**. Before upgrading:

1. Bump **`ACD_IMG`** in [`group_vars/all/images.yml`](group_vars/all/images.yml) to a build that honors `PJSIP_TRUNK_PORT` (deploying Ansible alone without a new ACD image leaves Asterisk on `:5060` and can conflict with Kamailio on AIO).
2. Run a **full** `./deploy.sh --action=upgrade` (not `--action=acd` alone on multi-host clusters unless edge hosts are upgraded too). Ansible applies, in order:
   - **`pods` role**: recreates `acd.pod` (tear-down + host network) when the Quadlet changes.
   - **`telephony_edge` role**: refreshes `kamailio_pstn.env` (`acd_nodes` with `:6070`) and `kamailio_webrtc.env` (`ACD_NET_ADDR`), then reinit `telephony_edge-pod.service`.
   - **`acd` role**: refreshes `acd-server.env` / `acd-app.env`, reinit `acd-pod.service`, restarts Asterisk/FastAGI/ARI.
3. Open **UDP 6070** between edge and ACD nodes in cluster layouts (firewall / cloud SG).

Post-upgrade checks on each ACD/edge host:

```bash
ss -ulnp | grep -E '5060|6070|5160|7088|7098'
systemctl is-active acd-pod.service telephony_edge-pod.service
```

For routine re-deploys (no image bump, just configuration drift) prefer `--action=update`:

```
./deploy.sh --action=update --tenant=<tenant>
```

# Rollback :leftwards_arrow_with_hook: <a name="rollback"></a>

A rollback is just an upgrade pointing back at an older image set. Override the relevant `*_IMG` variables in [`group_vars/all/images.yml`](group_vars/all/images.yml):

```yaml
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

Relevant variables (defaults and toggles in [`tenants_global.yml`](group_vars/all/tenants_global.yml); ports in [`runtime.yml`](group_vars/all/runtime.yml)):

* `loki_url`: uncomment in `tenants_global.yml` as `loki_url: "{{ vault_loki_url }}"` — Promtail pushes to that Loki endpoint (base URL, e.g. `http://host:3100`).
* `oml_observability_deploy=true` (passed automatically by `--action=observability`): allows deploying Promtail even when `loki_url` is not set yet (handy for templating in QA).
* `haproxy_prom_allowed_src`: uncomment as `haproxy_prom_allowed_src: "{{ vault_haproxy_prom_allowed_src }}"` — list of CIDRs allowed at `https://<fqdn>/prom` (defaults to deny-all when unset).
* `haproxy_metrics_port` / `haproxy_metrics_allowed_src`: HAProxy native Prometheus exporter on the edge (default `:8404/metrics` from `runtime.yml`, LAN-only).
* `kamailio_pstn_metrics_port` / `kamailio_webrtc_metrics_port`: Kamailio `prometheus` module on the edge (defaults `9273` / `9274` in `runtime.yml`). Requires a `KAMAILIO_IMG` rebuilt after config changes in `components-git-repo/kamailio`.
* `prometheus_*_exporter_port` / `prometheus_server_port`: ports published on `omni_ip_lan` by `observability.pod` for inter-node scrape (defaults in [`runtime.yml`](group_vars/all/runtime.yml)).
* `homer_host` / `homer_port`: uncomment in `tenants_global.yml` with `vault_homer_*` — enable HEP packet capture from Asterisk and Kamailio (PSTN + WebRTC) when you operate a Homer instance.
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

The default installation is tuned for tenants with 20–30 concurrent users in [`group_vars/all/tenants_global.yml`](group_vars/all/tenants_global.yml). To scale beyond that, edit the matching blocks in that file (not the inventory).

### Asterisk:

```yaml
# group_vars/all/tenants_global.yml — ACD block
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
# group_vars/all/tenants_global.yml — defaults already enable scale_uwsgi
scale_uwsgi: true
uwsgi_processes: 8
uwsgi_threads: 1
uwsgi_listen_queue_size: 2048
uwsgi_worker_reload_mercy: 60
uwsgi_evil_reload_on_rss: 3096
```

### PostgreSQL:

```yaml
# group_vars/all/tenants_global.yml
scale_postgres: True
postgres_max_connections: 100
postgres_shared_buffers: 1GB
```

### Redis:

```yaml
# group_vars/all/tenants_global.yml — REDIS block
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
# group_vars/all/tenants_global.yml — TELEPHONY EDGE PROXY block
# kamailio_shm_size: 64
# kamailio_pkg_size: 8
```

### RTPEngine:

```yaml
# group_vars/all/tenants_global.yml — TELEPHONY EDGE PROXY block
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

Connectivity: HAProxy on the edge must reach Nginx on the AIO via `omni_ip_lan` (TCP/443 backend). Agent WebSocket (`wss://<fqdn>/ws`): HAProxy routes `GET /ws` to `kamailio-webrtc` on `omni_ip_lan:10060` on the edge host (`haproxy_kamailio_ws_enabled`, default on). In cluster layouts, edge Kamailio PSTN reaches the ACD at `omni_ip_lan:6070/udp` (`acd_nodes` / `acd_trunk_sip_port`). On co-located AIO/edge+ACD hosts, `acd_nodes` uses `127.0.0.1:6070`.

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
   * Centralize secrets in `group_vars/all/vault.yml` (Vault) and shared settings in `group_vars/all/tenants_global.yml`.
   * Drop deprecated variables (`infra_env`, `omnileads_img`, `asterisk_img`, `upgrade_from_oml_1`, `restore_file_timestamp`, `callrec_transcriptions`, `acd_pjsip_transport_*`, `acd_api_listen_ip`, `dialer_user`).
   * Re-set image references through `APP_IMG`, `ACD_IMG`, `NGINX_IMG`, etc. in `group_vars/all/images.yml` (or rely on the shipped defaults).
2. Keep the same `postgres_user`, `postgres_password` and `postgres_database` you had on 2.X (`postgres_password` now comes from `vault_postgres_password` via `tenants_global.yml`).
3. Make sure the variables match between the 2.X source and the new 3.X tenant before pointing the new instance at the backup files (`backup_filename` and `backup_filename_OMD` on the inventory host).
4. Enable the migration flag on the inventory host (overrides the global `upgrade_from_2X: false` in `tenants_global.yml`):

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
