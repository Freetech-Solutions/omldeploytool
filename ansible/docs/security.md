# Seguridad de red en el deploy Ansible (OMniLeads 3.X)

Este documento describe los controles de perímetro **gestionados por Ansible**
en los hosts del tenant: allowlists **nftables** por servicio, fail2ban y
referencias a TLS en el edge.

Complementa (no reemplaza) el security group / firewall de la nube: SSH,
HTTP(S) público, SIP ITSP y RTP de RTPengine siguen siendo responsabilidad
del perímetro cloud + inventario (`itsp_nodes`, bastion, etc.).

Controles relacionados:

| Control | Doc / rol |
|---------|-----------|
| Allowlists TCP/UDP por servicio (este doc) | Roles `postgresql`, `redis`, `minio`, `gearman`, `observability_prometheus`, `acd`, `nginx` |
| Brute-force SSH / SIP / probes HTTPS | Rol `fail2ban` — ver [README](../README.md) sección Fail2ban |
| TLS en HAProxy (ISO 27001 A.8.24) | [haproxy_tls_iso27001.md](haproxy_tls_iso27001.md) |
| Tabla de puertos por layout | [README](../README.md) — Network exposure |

---

## 1. Allowlists nftables (opt-in)

### Propósito

Los pods publican muchos servicios solo en `omni_ip_lan` (no en `0.0.0.0`),
pero **cualquier host de la misma LAN/VPC** que enrute hasta esa IP puede
abrir el puerto. Las allowlists nftables cierran ese hueco: solo aceptan
orígenes del inventario del tenant (y extras explícitos).

### Estado por defecto

**Desactivadas** (`*_nftables: false` en `group_vars/all/tenants_global.yml`).
Hay que activarlas por tenant (o globalmente) de forma explícita.

```yaml
# instances/<tenant>/vars.yml — ejemplo: activar todo el lote de datos + obs + ACD
postgres_nftables: true
redis_nftables: true
minio_nftables: true
gearman_nftables: true
observability_nftables: true
acd_nftables: true
nginx_nftables: true

# Bastion / red de admin (opcional, por servicio)
postgres_nftables_extra_src: ["10.0.0.5/32"]
observability_nftables_extra_src: ["10.0.0.5/32"]
acd_nftables_extra_src: []
nginx_nftables_extra_src: []
```

Cada rol también saltea las reglas si `oml_devenv: true`.

### Diseño técnico común

- Tabla dedicada (`inet oml_<servicio>`). **No** se usa `nftables.service` de
  la distro ni `flush ruleset` (eso borraría netavark/Podman y fail2ban).
- Archivo renderizado en `/etc/omnileads/oml-<servicio>.nft`.
- Unit oneshot systemd (`oml-<servicio>-nft.service`) que recarga el archivo
  al boot, `Before=` del pod correspondiente.
- Idempotencia: el archivo empieza con `destroy table inet oml_<servicio>` y
  recrea la tabla (hosts que salen del inventario dejan de estar permitidos).
- IPv6 hacia esos puertos: **drop** (el allowlist es IPv4).

Dos hooks según cómo escucha el servicio:

| Hook | Cuándo | Roles |
|------|--------|-------|
| `filter hook prerouting priority -150` | Puerto publicado con Podman `PublishPort` (DNAT). Hay que filtrar **antes** del DNAT (`-100`) | postgres, redis, minio, gearman, observability, nginx |
| `filter hook input priority filter` | `Network=host` (sin DNAT); el socket escucha en el host | acd |

### Clientes permitidos (regla general)

Para servicios de datos y exporters:

1. LAN de cada host en `groups['all']`: `omni_ip_lan` si está definida y no vacía;
   si no, **`ansible_host`** (mismo criterio que `topology_normalize`). Se resuelve en
   un solo `set_fact` (`to_json`/`from_json`) y siempre se suma también la LAN del
   host actual. No hace falta declarar `omni_ip_lan` cuando coincide con la IP SSH.
2. Subnet IPv4 del bridge Podman `omnileads` (leída con `podman network inspect`).
   Sin esto fallan el exporter u otros contenedores del mismo host (AIO).
3. `*_nftables_extra_src` (CIDRs/IPs opcionales).
4. En ACD además siempre entra `127.0.0.1/8` (co-locación AIO / edge+ACD).

No se añaden `omni_ip_wan` ni IP de ITSP a estas tablas (salvo que las pongas
en `*_extra_src`).

---

## 2. Inventario por servicio

### 2.1 PostgreSQL — `inet oml_postgres`

| | |
|--|--|
| **Rol** | `postgresql` |
| **Host** | `data_statefull`, `omnileads_aio` |
| **Hook** | prerouting |
| **Puertos** | TCP/`postgres_port` (5432) |
| **Flag** | `postgres_nftables` |
| **Extras** | `postgres_nftables_extra_src` |
| **Archivos** | `roles/postgresql/tasks/nftables.yml`, `templates/oml-postgres.nft.j2` |
| **Deploy** | `./deploy.sh --action=postgres --tenant=<tenant>` |

### 2.2 Redis — `inet oml_redis`

| | |
|--|--|
| **Rol** | `redis` |
| **Host** | `data_stateless`, `omnileads_aio` |
| **Hook** | prerouting |
| **Puertos** | TCP/`redis_port` (6379) |
| **Flag** | `redis_nftables` |
| **Extras** | `redis_nftables_extra_src` |
| **Deploy** | `./deploy.sh --action=redis --tenant=<tenant>` |

### 2.3 MinIO — `inet oml_minio`

| | |
|--|--|
| **Rol** | `minio` |
| **Host** | `data_statefull`, `omnileads_aio` (solo si MinIO local; no aplica con `bucket_url` externo) |
| **Hook** | prerouting |
| **Puertos** | TCP/`minio_api_port` (9000) y TCP/`minio_console_port` (9001) |
| **Flag** | `minio_nftables` |
| **Extras** | `minio_nftables_extra_src` |
| **Deploy** | `./deploy.sh --action=minio --tenant=<tenant>` |

### 2.4 Gearman — `inet oml_gearman`

| | |
|--|--|
| **Rol** | `gearman` |
| **Host** | `data_stateless`, `omnileads_aio` |
| **Hook** | prerouting |
| **Puertos** | TCP/`gearman_port` (4730) |
| **Flag** | `gearman_nftables` |
| **Extras** | `gearman_nftables_extra_src` |
| **Deploy** | `./deploy.sh --action=gearman --tenant=<tenant>` |

Activar el lote de datos de una vez:

```bash
./deploy.sh --action=data --tenant=<tenant>
```

### 2.5 Observability — `inet oml_observability`

Una sola tabla por host; los puertos dependen del **tier** (misma lógica que
`roles/pods/templates/observability.pod.j2` + node_exporter).

| Condición en el host | Puertos TCP |
|----------------------|-------------|
| Rol activo (siempre) | 9100 (node), 9882 (podman) |
| `oml_runs_omlapp_web` | 9090 (Prometheus), 9117 (uwsgi exporter) |
| `oml_runs_data_statefull` | 9187 (postgres exporter) |
| `oml_runs_data_stateless` | 9121 (redis), 9418 (gearman) |
| + `dialer_engine == omnidialer` | 7099 (dialer pacing) |

| | |
|--|--|
| **Rol** | `observability_prometheus` |
| **Hook** | prerouting |
| **Flag** | `observability_nftables` |
| **Extras** | `observability_nftables_extra_src` (p. ej. bastion para `curl :9090`) |
| **Deploy** | `./deploy.sh --action=observability --tenant=<tenant>` |

El acceso humano a Prometheus sigue siendo `https://<fqdn>/prom` en el edge
(`haproxy_prom_allowed_src`). El allowlist protege el `:9090` directo en LAN.
Tras aplicar, el mismo rol corre `validate_scrape.yml` desde el host Prometheus.

### 2.6 ACD — `inet oml_acd`

`Network=host`: hook **input**. Varios sets porque cada puerto tiene clientes distintos.

| Puerto | Proto | Set | Orígenes permitidos |
|--------|-------|-----|---------------------|
| `acd_ari_port` (7088) | TCP | `acd_ari_clients` | Inventario `omni_ip_lan` + `127.0.0.1/8` + extras |
| `acd_app_metrics_port` (7098) | TCP | `acd_metrics_clients` | Idem |
| `acd_agent_sip_port` (5160) | UDP | `acd_agent_sip_clients` | Idem (LAN / localhost; Kamailio WebRTC en edge) |
| `acd_trunk_sip_port` (5070) | UDP | `acd_trunk_clients` | `omni_ip_lan` de `edge` + `omnileads_aio` + `127.0.0.1/8` + extras |
| `acd_rtp_port_min`–`max` (40000–50000) | UDP | `acd_rtp_clients` | Igual que trunk (solo edge ↔ ACD) |

| | |
|--|--|
| **Rol** | `acd` |
| **Flag** | `acd_nftables` |
| **Extras** | `acd_nftables_extra_src` |
| **Deploy** | `./deploy.sh --action=acd --tenant=<tenant>` (o `voice`) |

**No** se filtra aquí Kamailio PSTN `:5060` ni el rango RTP de RTPengine
(edge / Internet / ITSP).

Riesgo: alto (rompe llamadas si el set de edge está mal). Validar PSTN + WebRTC
después de activar.

### 2.7 Nginx / omlapp_web — `inet oml_nginx`

PublishPort en el pod `omlapp_web`; hook **prerouting**. Dos sets:

| Puerto | Proto | Set | Orígenes permitidos |
|--------|-------|-----|---------------------|
| 9191 | TCP | `nginx_stats_clients` | Inventario `omni_ip_lan` + bridge `omnileads` + extras (siempre) |
| 80 / 443 | TCP | `nginx_edge_clients` | Solo si hay grupo `edge`: LAN de `edge` + `omnileads_aio` + `127.0.0.1/8` + extras |

Sin grupo `edge` (AIO clásico con nginx en `0.0.0.0`): **no** se filtran 80/443;
solo se cierra `:9191`.

| | |
|--|--|
| **Rol** | `nginx` |
| **Flag** | `nginx_nftables` |
| **Extras** | `nginx_nftables_extra_src` |
| **Archivos** | `roles/nginx/tasks/nftables.yml`, `templates/oml-nginx.nft.j2` |
| **Deploy** | `./deploy.sh --action=nginx --tenant=<tenant>` (o `app`) |

Validar HTTPS vía FQDN (HAProxy → nginx LAN) tras activar en cluster.

---

## 3. Qué no cubren estas reglas

| Puerto / plano | Motivo |
|----------------|--------|
| 80/443 en edge | Tráfico de usuarios / Internet |
| UDP 5060 Kamailio PSTN | Allowlist de ITSP (`itsp_nodes`), no VMs OML |
| UDP 20000–30000 RTPengine | WebRTC + PSTN desde Internet |
| TCP 22 | Bastion / fail2ban `sshd`; no es inventario de pods |
| TCP 10060 WSS Kamailio | Backend local de HAProxy en el edge |
| TCP 8404 / 9273 / 9274 / 22223 | Métricas edge (candidato futuro; 8404 ya tiene ACL en HAProxy) |
| TCP 80/443 en `omlapp_web` sin grupo `edge` | Nginx público en AIO; el allowlist no aplica a esos puertos |

---

## 4. Operación

### Activar en un tenant existente

1. Poner `*_nftables: true` en `instances/<tenant>/vars.yml`.
2. Redeploy del rol o del lote (`postgres`, `redis`, `minio`, `gearman`,
   `data`, `observability`, `acd` / `voice`, `nginx` / `app`).
3. Comprobar tablas:

```bash
nft list table inet oml_postgres
nft list table inet oml_redis
nft list table inet oml_minio
nft list table inet oml_gearman
nft list table inet oml_observability
nft list table inet oml_acd
nft list table inet oml_nginx
```

4. Smoke:
   - Datos: conectar desde una VM del inventario y desde una IP LAN ajena.
   - Obs: `./deploy.sh --action=observability` y revisar validate scrape.
   - ACD: llamada PSTN + WebRTC.
   - Nginx (con `edge`): HTTPS vía FQDN; `:9191` solo desde inventario.

### Desactivar

```yaml
postgres_nftables: false   # (etc.)
```

Redeploy del rol. La unit oneshot en stop ejecuta `nft delete table inet oml_*`
(con `-` para no fallar si la tabla ya no existe). Si hace falta limpieza
manual: `nft delete table inet oml_postgres`.

### Fallos típicos

| Síntoma | Causa probable |
|---------|----------------|
| Assert “allowlist vacío” | Sin `omni_ip_lan` / `ansible_host` en inventario |
| Exporter o AIO no llega a Postgres/Redis | Bridge `omnileads` no existía al aplicar; re-correr tras `prerequisitos` |
| PSTN cae tras `acd_nftables: true` | Falta el host `edge` en inventario o su `omni_ip_lan` |
| HTTPS cae tras `nginx_nftables: true` (con edge) | Falta LAN del edge en el set; HAProxy debe salir con `omni_ip_lan` del edge |
| Bastion no abre `:9090` / `:5432` / `:9191` | Añadir CIDR en el `*_nftables_extra_src` del servicio |

---

## 5. Fail2ban (resumen)

Habilitado por defecto (`fail2ban: true`). Usa **banaction nftables** sobre
jails, independiente de las tablas `oml_*`:

- `sshd` en hosts de pods
- `kamailio-pstn` en edge/AIO (PIKE / origen no autorizado)
- `nginx-https` o `haproxy-https` (probes)

`ignoreip` incluye localhost, todas las `omni_ip_lan`, `omni_ip_wan` (edge),
IPv4 de `itsp_nodes` y `fail2ban_ignoreip_extra`.

```bash
./deploy.sh --action=fail2ban --tenant=<tenant>
```

Detalle: [README](../README.md) — Fail2ban.

---

## 6. Mapa rápido variables → tabla nft

| Variable | Default | Tabla | Host típico |
|----------|---------|-------|-------------|
| `postgres_nftables` | `false` | `oml_postgres` | data_statefull / AIO |
| `redis_nftables` | `false` | `oml_redis` | data_stateless / AIO |
| `minio_nftables` | `false` | `oml_minio` | data_statefull / AIO |
| `gearman_nftables` | `false` | `oml_gearman` | data_stateless / AIO |
| `observability_nftables` | `false` | `oml_observability` | todo host con el rol |
| `acd_nftables` | `false` | `oml_acd` | acd / AIO |
| `nginx_nftables` | `false` | `oml_nginx` | omlapp_web / AIO |

ISO/IEC 27001: evidencia de **gestión de configuración** (A.8.9) y
**segmentación de red** (A.8.22) cuando estas allowlists están activas y
documentadas por tenant.
