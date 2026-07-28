# Stack de observabilidad OMniLeads

Documentación operativa de la capa de observabilidad desplegada por Ansible en cada tenant: **métricas** (Prometheus + exporters), **logs** (journald + Promtail → Loki), **captura SIP/QoS** (Homer HEP desde Kamailio) y **seguridad del host** (Wazuh Agent → Manager central).

**Roles Ansible involucrados:**

- `roles/observability_prometheus`
- `roles/observability_promtail`
- `roles/wazuh-agent`
- `roles/pods/templates/observability.pod.j2`

**Despliegue:**

```bash
# Métricas + Promtail
./deploy.sh --action=observability --tenant=<tenant>

# Wazuh Agent (FIM / logs SO / vulnerabilidades)
./deploy.sh --action=wazuh-agent --tenant=<tenant>
```

- `observability` equivale a `site.yml` con tags `observability` y `oml_observability_deploy=true`.
- `wazuh-agent` equivale a `site.yml` con tags `wazuh-agent,gather_facts`. También se incluye en `install` / `upgrade` / `update` cuando está habilitado.

---

## Visión general

OMniLeads implementa un modelo **multi-tenant de observabilidad distribuida**:

1. **En cada host del tenant** corre un `observability.pod` (Podman Quadlet) con exporters locales y Promtail.
2. **En el host de cómputo web** (`omlapp_web` o AIO) corre además el servidor **Prometheus del tenant**, que hace scrape de todos los componentes del deploy vía `omni_ip_lan`.
3. **Logs** de los contenedores Quadlet (`*.service`) se escriben en **journald** y Promtail los reenvía a un **Loki central** (`loki_url`).
4. **Tráfico SIP** de Kamailio PSTN y WebRTC se duplica en **HEP v3** hacia **Homer** cuando `homer_host` está definido en el inventario.
5. **Seguridad del SO** en cada host del tenant: el **Wazuh Agent** se enrolla a un **Wazuh Manager** central cuando `wazuh_manager` está definido (FIM, logs del host, detección de vulnerabilidades). Complementa Loki/Prometheus; no reemplaza el flujo de logs de aplicación.

El acceso externo a Prometheus del tenant se expone en `https://<fqdn>/prom` a través de HAProxy en el host edge, restringido por `haproxy_prom_allowed_src`.

Grafana, Loki, Homer y el Wazuh Manager suelen operarse como **centro de observabilidad/seguridad central** que consume datos de uno o más tenants. Los dashboards Grafana provisionados en el rol `observability_prometheus` están pensados para ese centro (métricas `heplify_*`, SIP KPIs, PostgreSQL, Redis, etc.).

### Diagrama de componentes (tenant)

```
┌───────────────────────────────────────────────────────────────────────────┐
│                           TENANT OMniLeads                                │
│                                                                           │
│  ┌──────── edge ────────┐    ┌──── omlapp_web / AIO ───────────────────┐  │
│  │ HAProxy :443 /prom   │    │ Prometheus :9090 (scrape all nodes)     │  │
│  │ Kamailio PSTN :9273  │    │ uwsgi_exporter :9117                    │  │
│  │ Kamailio WebRTC:9274 │    │ observability.pod                       │  │
│  │ RTPengine :22223     │    └─────────────────────────────────────────┘  │
│  │ HEP                                               │
│  │ observability.pod    │       ┌── data_statefull ─┐  ┌data_stateless  ┐ │
│  └──────────────────────┘       │ postgres_exp :9187│  │ redis_exp :9121│ │
│                                 │ observability.pod │  │ gearman :9418  │ │
│  ┌──────── acd ──────────┐      └───────────────────┘  │ observability  │ │
│  │ Asterisk :7088        │                             └────────────────┘ │
│  │ observability.pod     │                                                │
│  └───────────────────────┘     Cada host: Promtail → journald → Loki      │
│                                Cada host: wazuh-agent → Manager (si ON)   │
│                                                                           │
└───────────────────────────────────────────────────────────────────────────┘
                             |                              |
                             |                              |
                  ┌─────────────────────────────┐  ┌──────────────────────┐
                  │  CENTRO OBSERVABILIDAD      │  │  WAZUH MANAGER       │
                  │  Loki | Grafana | Homer     │  │  (SIEM / FIM / CVE)  │
                  |(heplify → heplify_* metrics)│  │  grupo agentes       │
                  └─────────────────────────────┘  └──────────────────────┘

```

---

## Arquitectura por capas

### Pod `observability.pod`

El pod se crea automáticamente en **todo host** que ejecute algún pod de cómputo, datos o edge. Publica los puertos de exporters en `omni_ip_lan` para permitir scrape inter-nodo (solo LAN).

Plantilla: `roles/pods/templates/observability.pod.j2`

| Puerto | Servicio         | Hosts |
|--------|-----------------|-------|
| 9100   | node_exporter    | todos |
| 9882   | podman_exporter  | todos |
| 9090   | prometheus | omlapp_web \| omnileads_aio |
| 9117   | uwsgi_exporter | omlapp_web \| omnileads_aio |
| 9187   | postgres_exporter | data_statefull \| omnileads_aio |
| 9121   | redis_exporter | data_stateless \| omnileads_aio |
| 9418   | gearman_exporter | data_stateless \| omnileads_aio |

### Prometheus del tenant

Prometheus corre **solo** en el tier web (`oml_runs_omlapp_web`). La configuración se genera desde la plantilla `prometheus.yml` con un job por componente, etiquetado con `tenant`, `component` y `host`.

| Parámetro | Valor |
|-----------|-------|
| Retención | 30 días |
| Ruta web | `/prom` |
| URL externa | `https://{{ fqdn }}/prom` |
| Plantilla | `roles/observability_prometheus/templates/prometheus.yml` |
| Intervalo de scrape | 10 s |

### Acceso externo

- **UI Prometheus:** `https://<fqdn>/prom` → backend `prometheus_cluster` en HAProxy.
- **Métricas HAProxy:** `:8404/metrics` (LAN, restringido por `haproxy_metrics_allowed_src`).

Si `haproxy_prom_allowed_src` está vacío, HAProxy **deniega** `/prom` por defecto. Definir CIDRs permitidos en el inventario del tenant.

---

## Prometheus exporters

### Cómo funciona

Los exporters son contenedores Podman Quadlet miembros de `observability.pod`, salvo los nativos de edge/telephony que corren en sus propios pods. Prometheus del tenant scrapea cada target en `omni_ip_lan` cada **10 segundos**.

El rol `observability_prometheus` se habilita cuando el host ejecuta algún tier de cómputo/datos/edge (`component_observability_prometheus_enabled` en `topology_normalize`). Los quadlets concretos dependen del tier:

| Tier | Exporters adicionales |
|------|----------------------|
| Todos los hosts | node_exporter + podman_exporter |
| omlapp_web / AIO | + prometheus + uwsgi_exporter |
| data_statefull | + postgres_exporter |
| data_stateless | + redis_exporter + gearman_exporter |

Además, Prometheus scrapea endpoints nativos (no presisan de un container exporter) en edge, ACD y telephony que no viven en `observability.pod`.

### Exporters en `observability.pod`

#### node_exporter (9100)

- **Imagen:** `prom/node-exporter:v1.7.0`
- **Propósito:** Métricas del sistema operativo: CPU, memoria, disco, red, load average. Monta `/proc`, `/sys` y `/` del host en modo read-only.
- **Job Prometheus:** `{{ tenant_id }}_node`
- **Labels:** `tenant`, `component=os`, `host`

#### podman_exporter (9882)

- **Imagen:** `quay.io/navidys/prometheus-podman-exporter`
- **Propósito:** Métricas de contenedores Podman: estado, CPU/memoria por contenedor, labels de imagen. Usa el socket `/run/podman/podman.sock`.
- **Job Prometheus:** `{{ tenant_id }}_podman`
- **Labels:** `tenant`, `component=podman`, `host`

#### postgres_exporter (9187)

- **Host:** data_statefull
- **Imagen:** `prometheuscommunity/postgres-exporter`
- **Propósito:** Conexiones activas, transacciones, bloqueos, tamaño de BD, replicación. Credenciales en `/etc/default/prometheus_postgres.env`.
- **Job Prometheus:** `{{ tenant_id }}_postgres`
- **Labels:** `tenant`, `component=postgres`
- **Dashboard:** `PostgreSQL.json`

#### redis_exporter (9121)

- **Host:** data_stateless
- **Imagen:** `oliver006/redis_exporter`
- **Propósito:** Memoria, keys, comandos/s, clientes conectados, persistencia.
- **Job Prometheus:** `{{ tenant_id }}_redis`
- **Labels:** `tenant`, `component=redis`
- **Dashboard:** `Redis.json`

#### gearman_exporter (9418)

- **Host:** data_stateless
- **Imagen:** `gearmanexporter/gearman-exporter:v0.5.0`
- **Propósito:** Colas Gearman: jobs en espera, workers activos, funciones registradas.
- **Job Prometheus:** `{{ tenant_id }}_gearman`
- **Labels:** `tenant`, `component=gearman`

#### uwsgi_exporter (9117)

- **Host:** omlapp_web
- **Imagen:** `timonwong/uwsgi-exporter`
- **Propósito:** Stats del proceso uWSGI de Django (workers, requests, backlog). Apunta al socket HTTP de stats de uWSGI en el pod web.
- **Job Prometheus:** `{{ tenant_id }}_uwsgi`
- **Labels:** `tenant`, `component=uwsgi`

### Exporters nativos (fuera del pod observability)

#### asterisk_metrics (7088)

- **Host:** acd
- **Propósito:** Métricas nativas expuestas por el módulo `res_prometheus` de Asterisk (acd-server).
- **Job Prometheus:** `{{ tenant_id }}_asterisk`
- **Labels:** `tenant`, `component=asterisk`

#### acd_app_metrics (7098)

- **Host:** acd (contenedor `acd-app`, pod `acd`)
- **Propósito:** Métricas ARI del proceso Python: cola de eventos, eventos recibidos/procesados/descartados, latencias.
- **Job Prometheus:** `{{ tenant_id }}_acd_app`
- **Labels:** `tenant`, `component=acd_app`
- **Puerto:** `acd_app_metrics_port` (default `7098`), publicado en `omni_ip_lan` vía `acd.pod`

#### rtpengine_metrics (22223)

- **Host:** edge (pod `telephony_edge`)
- **Propósito:** Métricas de sesiones RTP, packet loss, MOS estimado.
- **Job Prometheus:** `{{ tenant_id }}_rtpengine`
- **Labels:** `tenant`, `component=rtpengine`

#### haproxy_metrics (8404, ruta `/metrics`)

- **Host:** edge
- **Propósito:** Exporter nativo de HAProxy (frontend `prometheus_metrics`). Restringido a redes privadas (`haproxy_metrics_allowed_src`).
- **Job Prometheus:** `{{ tenant_id }}_haproxy`
- **Labels:** `tenant`, `component=haproxy`, `host`

#### kamailio_pstn_metrics (9273, ruta `/metrics`)

- **Host:** edge (kamailio_pstn)
- **Propósito:** Módulo `xhttp_prom` de Kamailio PSTN: counters SIP, transacciones TM, estadísticas de módulos cargados.
- **Job Prometheus:** `{{ tenant_id }}_kamailio_pstn`
- **Labels:** `tenant`, `component=kamailio_pstn`
- **Nota:** Requiere imagen `KAMAILIO_IMG` reconstruida con la config actual.

#### kamailio_webrtc_metrics (9274, ruta `/metrics`)

- **Host:** edge (kamailio_webrtc)
- **Propósito:** Igual que PSTN pero para el proxy WebRTC (registro de softphones, autenticación efímera AUTHEPH, enrutamiento hacia Asterisk).
- **Job Prometheus:** `{{ tenant_id }}_kamailio_webrtc`
- **Labels:** `tenant`, `component=kamailio_webrtc`

### Validación post-deploy

Tras el deploy, Ansible ejecuta `validate_scrape.yml` desde el host Prometheus: verifica reachability TCP a todos los puertos de scrape en `omni_ip_lan` (tag: `validate`).

Ejemplos manuales desde omlapp_web/AIO:

```bash
curl -s http://<omni_ip_lan>:9100/metrics | head
curl -s http://<edge_ip>:9273/metrics | head
```

### Federación central

Un Prometheus/Grafana central puede hacer **federation** o scrape directo de `https://<tenant-fqdn>/prom` (con ACL en HAProxy) para consolidar métricas multi-tenant.

---

## Promtail y journald

### Cómo funciona

Todos los contenedores Quadlet de OMniLeads usan `LogDriver=journald`. Los logs **no** se escriben en archivos planos sino en el journal del host. Promtail lee ese journal, filtra por unidad systemd (`*.service`) y empuja los eventos a Loki central con labels de tenant, host y servicio.

```
┌─────────────────┐     ┌──────────────┐     ┌─────────────┐     ┌──────┐
│ Contenedor      │     │ journald     │     │  Promtail   │     │ Loki │
│ Quadlet         │────▶│ (host)       │────▶│  (host)     │────▶│centr.│
│ LogDriver=      │     │ _SYSTEMD_UNIT│     │  filtra por │     │:3100 │
│ journald        │     │ =nginx.svc   │     │  unit+labels│     └──────┘
└─────────────────┘     └──────────────┘     └─────────────┘
```

### Activación

Promtail se despliega cuando:

- `loki_url` está definido en el inventario, o
- `oml_observability_deploy=true` (acción observability del `deploy.sh`)

Variable de topología: `component_observability_promtail_enabled` (`topology_normalize`).

### Configuración de journald

Definida en `group_vars/all/observability.yml` y aplicada por `roles/prerequisitos/tasks/os_configuration.yml`:

| Parámetro | Valor |
|-----------|-------|
| Storage | volatile |
| RuntimeMaxUse | 192M |
| RuntimeKeepFree | 32M |
| SystemMaxUse | 5G |
| SystemMaxFileSize | 200M |
| SystemKeepFree | 2G |

`Storage=volatile` mantiene el journal en tmpfs (`/run/log/journal`) para reducir desgaste de disco. Los logs persistentes de negocio deben fluir a Loki vía Promtail; no depender del journal en disco.

### Contenedor Promtail

| Parámetro | Valor |
|-----------|-------|
| Unit | `promtail.service` |
| Imagen | `grafana/promtail` |
| Puerto HTTP | 9080 |
| Plantilla | `roles/observability_promtail/templates/promtail.container` |

**Volúmenes:**

- `/etc/default/promtail.yml` → config
- `/run/log/journal/` → `/var/log/journal/` (ro)
- `/etc/machine-id` (ro)

### Scrape por topología

La plantilla `promtail.yml` genera jobs distintos según los grupos de inventario del host. Cada job usa el driver `journal` con match `_SYSTEMD_UNIT=<servicio>.service`.

| Tier | Servicios monitoreados (ejemplos) |
|------|-----------------------------------|
| omnileads_aio | Stack completo: acd, kamailio, nginx, postgres, redis, dialer workers, etc. |
| edge | haproxy, kamailio_pstn, kamailio_webrtc, rtpengine |
| data_statefull | postgresql, minio |
| data_stateless | redis, gearman |
| omlapp_web | omnileads, daphne, nginx, websockets, dialer_api |
| omlapp_workers | call_logger, whatsapp, supervision_*, background_* … |
| dialer_workers | `dialer_process_{campaign,contact,event}@N.service` (instancias) |

### Labels en Loki

| Label | Origen |
|-------|--------|
| `tenant` | `tenant_id` del inventario (multi-tenancy en Loki) |
| `host` | `inventory_hostname` |
| `job` | Nombre lógico del servicio (ej. `nginx`, `kamailio_pstn`) |
| `node_type` | `aio` \| `edge` \| `web` \| `workers` \| `acd` \| … |
| `service_family` | `acd` \| `telephony` \| `infrastructure` \| `dialer` \| … |
| `unit` | Unidad systemd completa (relabel desde `__journal__systemd_unit`) |
| `container_name` / `container_id` | Metadata del contenedor Podman |

Promtail envía `tenant_id` como header `X-Scope-OrgID` a Loki cuando está definido.

### Consultas LogQL (ejemplos)

```logql
{tenant="<tenant_id>", job="nginx"}
{tenant="<tenant_id>", job="kamailio_webrtc"} |= "ERROR"
{tenant="<tenant_id>", service_family="dialer", worker_type="campaign"}
```

### Validación

- Ansible verifica `<loki_url>/ready` post-deploy.
- Smoke test local: `make smoke-promtail` en `ansible/`.
- Verificar journal en host: `journalctl -u nginx.service -n 20`.

---

## Homer HEP — Kamailio PSTN y WebRTC

### Cómo funciona

Cuando `homer_host` está definido en el inventario del tenant, Kamailio PSTN y WebRTC activan el módulo `siptrace` con **HEP v3** para duplicar el tráfico SIP hacia un colector Homer (típicamente `heplify-server`). Esto habilita análisis de llamadas, correlación SIP y métricas QoS (`heplify_*`) consumidas por dashboards Grafana centrales.

```
┌──────────────┐   SIP normal    ┌─────────────┐
│ ITSP /       │◀──────────────▶│ Kamailio    │
│ Softphone    │                │ PSTN/WebRTC │
└──────────────┘                └──────┬──────┘
                                       │ HEP v3 (UDP/TCP)
                                       │ duplicate_uri
                                       ▼
                                ┌─────────────┐
                                │ Homer       │
                                │ heplify     │──▶ Prometheus (heplify_*)
                                └─────────────┘──▶ Grafana SIP/QoS dashboards
```

La captura SIP activa en producción es vía **Kamailio en edge**, no directamente desde Asterisk (ver sección Asterisk HEP más abajo).

### Activación en inventario

| Variable | Descripción |
|----------|-------------|
| `homer_host` | IP/hostname del colector HEP (heplify-server / Homer) |
| `homer_port` | Puerto HEP (default `9060`) |
| `homer_kamailio_pstn_capture_id` | ID numérico agente PSTN (default `2002`) |
| `homer_kamailio_webrtc_capture_id` | ID numérico agente WebRTC (default `2003`) |
| `homer_pstn_node_name` | Label correlación PSTN (default `{{ tenant_id }}-pstn`) |
| `homer_webrtc_node_name` | Label correlación WebRTC (default `{{ tenant_id }}-webrtc`) |

Plantillas de entorno:

- `roles/telephony_edge/templates/kamailio_pstn.env`
- `roles/telephony_edge/templates/kamailio_webrtc.env`

Si `homer_host` no está definido, `HOMER_ENABLE=false` y no se compila la config HEP.

### Kamailio PSTN

| Parámetro | Valor |
|-----------|-------|
| Servicio | `kamailio_pstn.service` |
| Pod | `telephony_edge` |
| Plantilla config | `roles/telephony_edge/templates/kamailio_pstn.cfg` |

**Función:** Proxy SIP hacia carriers/ITSP. Maneja INVITE inbound/outbound, NAT, RTPengine, discriminación OMniLeadsOutbound. Es el punto de entrada PSTN del tenant.

**Activación runtime:** `entrypoint_pstn.sh` evalúa `HOMER_ENABLE`. Si es `true`, agrega `-A WITH_HOMER` a los argumentos de Kamailio, lo que incluye la config HEP en compile-time.

**Config HEP (`siptrace.so`):**

| Parámetro | Valor |
|-----------|-------|
| `trace_to_database` | 0 |
| `duplicate_uri` | `sip:{{ homer_host }}:{{ homer_port }}` |
| `trace_on` | 1 |
| `trace_flag` | `FLB_HOMER` (24) |
| `hep_mode_on` | 1 |
| `hep_version` | 3 |
| `hep_capture_id` | `{{ homer_kamailio_pstn_capture_id \| default(2002) }}` |

**Captura en `request_route`:** En cada request (excepto OPTIONS):

1. `setflag(FLB_HOMER)`
2. `sip_trace("", "$env(HOMER_NODE_NAME)")` → incluye node name en HEP

**Defaults:**

- `HOMER_CAPTURE_ID`: 2002
- `HOMER_NODE_NAME`: `{{ tenant_id }}-pstn`

### Kamailio WebRTC

| Parámetro | Valor |
|-----------|-------|
| Servicio | `kamailio_webrtc.service` |
| Pod | `telephony_edge` |
| Plantilla config | `components-git-repo/kamailio/source/kamailio_webrtc.cfg` |

**Función:** Proxy SIP para clientes WebRTC: registro de extensiones, autenticación efímera (`AUTHEPH_SK`), WebSocket/WSS, enrutamiento hacia Asterisk/ACD.

**Activación runtime:** `entrypoint_webrtc.sh` — igual que PSTN, `-A WITH_HOMER` cuando `HOMER_ENABLE=true`.

**Config HEP:** Idéntica a PSTN, con distinto `capture_id`.

**Captura:** Misma lógica que PSTN en `route(REQINIT)`: flag `FLB_HOMER` + `sip_trace` con `HOMER_NODE_NAME`. También se invoca `sip_trace` en rutas de reply para capturar respuestas SIP.

**Defaults:**

- `HOMER_CAPTURE_ID`: 2003
- `HOMER_NODE_NAME`: `{{ tenant_id }}-webrtc`

### Diferenciación PSTN vs WebRTC

Homer distingue el origen del tráfico por:

1. **`hep_capture_id` numérico** (2002 PSTN / 2003 WebRTC) — obligatorio entero 32-bit.
2. **`HOMER_NODE_NAME`** — string legible en la UI de Homer (ej. `KonectaPortaVoice-pstn`).

En Grafana, los dashboards SIP filtran por label `target_name` derivado de esos identificadores (`SIP_Overview`, `SIP_KPIs`, `SIP_Error_Rates`, etc.).

### Asterisk HEP (deshabilitado por defecto)

`acd-server.env` define `HOMER_ENABLE=False` aunque `homer_host` exista. El archivo `hep.conf` de Asterisk existe en `components-git-repo/acd` pero con `enabled=no`. Para habilitar HEP en Asterisk se requiere intervención explícita (comentario en inventory: *"Request by Asterisk hep module"*).

### Métricas QoS y dashboards Grafana

Origen: `heplify-server` exporta métricas Prometheus (prefijo `heplify_`).

| Dashboard | Contenido |
|-----------|-----------|
| `SIP_Overview.json` | ASR, NER, tasas INVITE/REGISTER |
| `SIP_KPIs.json` | KPIs con comparación semanal |
| `SIP_Error_Rates.json` | 4xx/5xx/6xx |
| `SIP_Methods&Responses.json` | Métodos y respuestas SIP |
| `SIP_Calls&Registers.json` | Llamadas y registros |
| `QOS_RTCP.json` | Jitter, packet loss, RTT |
| `QOS_XRTP.json` | MOS, packet loss rate, delay |
| `QOS_Horaclifix.json` | QoS Horaclifix |
| `Host_Overview.json` | Incluye `heplify_packets_total` |

---

## Wazuh Agent — seguridad del host

### Cómo funciona

Wazuh aporta la capa de **monitoreo de seguridad del sistema operativo** en cada nodo del tenant. El rol Ansible `wazuh-agent` instala el paquete oficial (`wazuh-agent` 4.x) desde los repos de Wazuh (apt/yum), enrolla el agente contra un **Manager externo** y deja el servicio `wazuh-agent` habilitado en systemd.

No corre dentro de `observability.pod`: es un agente nativo del host (Debian/RedHat). El Manager (fuera del tenant) centraliza:

- **FIM** (integridad de archivos)
- **Logs del SO** y detección de eventos
- **Vulnerabilidades** (CVE) reportadas desde el agente

```
┌─────────────────┐     enroll + report      ┌─────────────────┐
│ Host tenant     │ ───────────────────────▶ │ Wazuh Manager   │
│ wazuh-agent     │   (authd :1515, agent)   │ grupo agentes   │
│ (systemd)       │                          │ FIM / logs / CVE│
└─────────────────┘                          └─────────────────┘
```

Relación con el resto del stack:

| Capa | Qué monitorea | Destino |
|------|---------------|---------|
| Prometheus + exporters | Métricas de app/infra | Prometheus tenant → Grafana |
| Promtail + journald | Logs de contenedores Quadlet | Loki central |
| Homer HEP | Señalización SIP | Homer / heplify |
| **Wazuh Agent** | **SO del host (FIM, logs, CVE)** | **Wazuh Manager** |

### Activación

Flag de topología: `component_wazuh_agent_enabled` (`topology_normalize`).

Se habilita cuando:

1. `wazuh` es verdadero (default `true` en `tenants_global.yml`), **y**
2. `wazuh_manager` tiene un valor no vacío, **o** se ejecuta con tag `wazuh-agent` (acción dedicada; el assert del rol falla si falta el manager).

Desactivar por tenant o por host:

```yaml
# inventory.yml o instances/<tenant>/vars.yml
wazuh: false
```

### Variables necesarias

Fuente operativa: `group_vars/all/tenants_global.yml` (defaults del rol en `roles/wazuh-agent/defaults/main.yml`). Override por tenant en `instances/<tenant>/vars.yml` o en el inventario. Secretos vía Vault.

| Variable | Obligatoria | Default | Descripción |
|----------|-------------|---------|-------------|
| `wazuh_manager` | **Sí** (para instalar) | `""` | IP o FQDN del Wazuh Manager. Preferible por tenant o `{{ vault_wazuh_manager }}`. |
| `wazuh` | No | `true` | Master switch. `false` desactiva el rol aunque exista `wazuh_manager`. |
| `wazuh_agent_group` | No | `omnileads_prod` | Grupo de agentes en el Manager. **Debe existir exactamente** antes del enrollment. |
| `wazuh_registration_password` | Condicional | `""` | Password de authd. Usar Vault (`vault_wazuh_registration_password`). Vacío si el Manager no exige password. |
| `wazuh_agent_name` | No | `{{ inventory_hostname }}` | Nombre del agente en el Manager. |
| `wazuh_agent_authd_port` | No | `1515` | Puerto authd; solo si el paquete ya estaba instalado sin `client.keys`. |
| `wazuh_agent_package_state` | No | `present` | Estado del paquete (`present` / `absent`). |
| `wazuh_agent_service_enabled` | No | `true` | Servicio systemd enabled. |
| `wazuh_agent_service_state` | No | `started` | Estado deseado del servicio. |

Ejemplo mínimo en `instances/<tenant>/vars.yml`:

```yaml
wazuh_manager: "{{ vault_wazuh_manager }}"
wazuh_agent_group: omnileads_prod
wazuh_registration_password: "{{ vault_wazuh_registration_password }}"
```

### Flujo de enrollment (idempotente)

1. **Assert:** `wazuh_manager` definido y no vacío.
2. **Estado:** package facts + existencia de `/var/ossec/etc/client.keys` (agente ya registrado).
3. **Si no hay paquete:** añade repo oficial 4.x (GPG), instala `wazuh-agent` con env de postinst:
   - `WAZUH_MANAGER`
   - `WAZUH_AGENT_GROUP`
   - `WAZUH_AGENT_NAME` (si está definido)
   - `WAZUH_REGISTRATION_PASSWORD` (si está definido)
4. **Si hay paquete pero no `client.keys`:** enrollment diferido con `/var/ossec/bin/agent-auth` contra authd (`-m`, `-p`, `-G`, opcional `-A` / `-P`).
5. **Si ya instalado y registrado:** no reintenta enrollment (idempotente).
6. **Servicio:** `wazuh-agent` enabled + started.

Las variables `WAZUH_*` del entorno **solo aplican en el postinst del primer install**; por eso existe el camino `agent-auth` para hosts con paquete previo sin registro.

### Despliegue

```bash
# Solo Wazuh (todos los hosts del inventario del tenant)
./deploy.sh --action=wazuh-agent --tenant=<tenant>

# Incluido automáticamente en install / upgrade / update
# cuando component_wazuh_agent_enabled es true
./deploy.sh --action=install --tenant=<tenant>
```

Playbook: `site_core.yml` → rol `wazuh-agent` (tags `install`, `upgrade`, `update`, `wazuh-agent`).

### Validación post-deploy

En cada host del tenant:

```bash
systemctl status wazuh-agent
# Agente registrado si client.keys tiene contenido
sudo test -s /var/ossec/etc/client.keys && echo registered
```

En el Manager: el agente debe aparecer en el grupo `wazuh_agent_group` (p. ej. `omnileads_prod`) con el nombre `wazuh_agent_name`.

---

## Variables de referencia rápida

### Observabilidad

| Variable | Descripción |
|----------|-------------|
| `loki_url` | URL base del Loki central para Promtail (ej. `http://host:3100`) |
| `oml_observability_deploy` | `true` fuerza deploy de Promtail sin `loki_url` |
| `homer_host` / `homer_port` | Activa HEP en Kamailio PSTN + WebRTC |
| `haproxy_prom_allowed_src` | CIDRs permitidos para `https://<fqdn>/prom` |
| `haproxy_metrics_allowed_src` | CIDRs para `:8404/metrics` en edge |
| `wazuh_manager` | Activa e enrolla Wazuh Agent (IP/FQDN del Manager) |
| `wazuh` | `false` desactiva Wazuh aunque exista `wazuh_manager` |
| `wazuh_agent_group` | Grupo de agentes en el Manager (default `omnileads_prod`) |
| `wazuh_registration_password` | Password authd (Vault); opcional |
| `wazuh_agent_name` | Nombre del agente (default `inventory_hostname`) |

### Puertos de exporters

Fuente: `group_vars/all/runtime.yml`

| Variable | Puerto |
|----------|--------|
| `prometheus_server_port` | 9090 |
| `prometheus_node_exporter_port` | 9100 |
| `prometheus_podman_exporter_port` | 9882 |
| `prometheus_postgres_exporter_port` | 9187 |
| `prometheus_redis_exporter_port` | 9121 |
| `prometheus_gearman_exporter_port` | 9418 |
| `prometheus_uwsgi_exporter_port` | 9117 |
| `acd_app_metrics_port` | 7098 |
| `kamailio_pstn_metrics_port` | 9273 |
| `kamailio_webrtc_metrics_port` | 9274 |
| `haproxy_metrics_port` | 8404 |
| `rtpengine_metrics_port` | 22223 |

### journald

Fuente: `group_vars/all/observability.yml`
