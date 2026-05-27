---
# =============================================================================
# Stack de observabilidad OMniLeads — documentación operativa
# =============================================================================
#
# Este documento describe cómo funciona la capa de observabilidad desplegada
# por Ansible en cada tenant: métricas (Prometheus + exporters), logs
# (journald + Promtail → Loki) y captura SIP/QoS (Homer HEP desde Kamailio).
#
# Roles Ansible involucrados:
#   - roles/observability_prometheus
#   - roles/observability_promtail
#   - roles/pods/templates/observability.pod.j2
#
# Despliegue:
#   ./deploy.sh --action=observability --tenant=<tenant>
#   (equivale a site.yml con tags observability y oml_observability_deploy=true)
#
# =============================================================================

overview: |
  OMniLeads implementa un modelo **multi-tenant de observabilidad distribuida**:

  1. **En cada host del tenant** corre un `observability.pod` (Podman Quadlet) con
     exporters locales y, opcionalmente, Promtail.
  2. **En el host de cómputo web** (`omlapp_web` o AIO) corre además el servidor
     **Prometheus del tenant**, que hace scrape de todos los nodos vía `omni_ip_lan`.
  3. **Logs** de los contenedores Quadlet (`*.service`) se escriben en **journald**
     y Promtail los reenvía a un **Loki central** (`loki_url`).
  4. **Tráfico SIP** de Kamailio PSTN y WebRTC se duplica en **HEP v3** hacia
     **Homer** cuando `homer_host` está definido en el inventario.

  El acceso externo a Prometheus del tenant se expone en `https://<fqdn>/prom`
  a través de HAProxy en el host edge, restringido por `haproxy_prom_allowed_src`.

  Grafana, Loki y Homer suelen operarse como **centro de observabilidad central**
  que consume datos de uno o más tenants. Los dashboards Grafana provisionados en
  el rol `observability_prometheus` están pensados para ese centro (métricas
  `heplify_*`, SIP KPIs, PostgreSQL, Redis, etc.).

# -----------------------------------------------------------------------------
# Arquitectura por capas
# -----------------------------------------------------------------------------

architecture:

  observability_pod:
    description: |
      El pod `observability.pod` se crea automáticamente en **todo host** que
      ejecute algún pod de cómputo, datos o edge. Publica los puertos de
      exporters en `omni_ip_lan` para permitir scrape inter-nodo (LAN-only).

    ubicacion: roles/pods/templates/observability.pod.j2

    puertos_publicados:
      - puerto: 9100
        servicio: node_exporter
        hosts: todos
      - puerto: 9882
        servicio: podman_exporter
        hosts: todos
      - puerto: 9090
        servicio: prometheus
        hosts: omlapp_web | omnileads_aio
      - puerto: 9117
        servicio: uwsgi_exporter
        hosts: omlapp_web | omnileads_aio
      - puerto: 9187
        servicio: postgres_exporter
        hosts: data_statefull | omnileads_aio
      - puerto: 9121
        servicio: redis_exporter
        hosts: data_stateless | omnileads_aio
      - puerto: 9418
        servicio: gearman_exporter
        hosts: data_stateless | omnileads_aio

  prometheus_tenant:
    description: |
      Prometheus corre **solo** en el tier web (`oml_runs_omlapp_web`). La
      configuración se genera desde la plantilla `prometheus.yml` con un job
      por componente, etiquetado con `tenant`, `component` y `host`.

    retencion: 30d
    ruta_web: /prom
    url_externa: "https://{{ fqdn }}/prom"
    plantilla: roles/observability_prometheus/templates/prometheus.yml

  acceso_externo:
    haproxy:
      prometheus_ui: "https://<fqdn>/prom → backend prometheus_cluster"
      metricas_haproxy: ":8404/metrics (LAN, haproxy_metrics_allowed_src)"
    nota: |
      Si `haproxy_prom_allowed_src` está vacío, HAProxy **deniega** `/prom`
      por defecto. Definir CIDRs permitidos en el inventario del tenant.

# -----------------------------------------------------------------------------
# Prometheus exporters
# -----------------------------------------------------------------------------

prometheus_exporters:

  resumen: |
    Los exporters son contenedores Podman Quadlet miembros de `observability.pod`
    (salvo los nativos de edge/telephony que corren en sus propios pods).
    Prometheus del tenant scrapea cada target en `omni_ip_lan` cada 10 segundos.

  activacion: |
    El rol `observability_prometheus` se habilita cuando el host ejecuta algún
    tier de cómputo/datos/edge (`component_observability_prometheus_enabled` en
    topology_normalize). Los quadlets concretos dependen del tier:

      - Todos los hosts: node_exporter + podman_exporter
      - omlapp_web / AIO: + prometheus + uwsgi_exporter
      - data_statefull: + postgres_exporter
      - data_stateless: + redis_exporter + gearman_exporter

  exporters:

    node_exporter:
      puerto: 9100
      imagen: prom/node-exporter:v1.7.0
      proposito: |
        Métricas del sistema operativo: CPU, memoria, disco, red, load average.
        Monta `/proc`, `/sys` y `/` del host en modo read-only.
      job_prometheus: "{{ tenant_id }}_node"
      labels: [tenant, component=os, host]

    podman_exporter:
      puerto: 9882
      imagen: quay.io/navidys/prometheus-podman-exporter
      proposito: |
        Métricas de contenedores Podman: estado, CPU/memoria por contenedor,
        labels de imagen. Usa el socket `/run/podman/podman.sock`.
      job_prometheus: "{{ tenant_id }}_podman"
      labels: [tenant, component=podman, host]

    postgres_exporter:
      puerto: 9187
      imagen: prometheuscommunity/postgres-exporter
      host: data_statefull
      proposito: |
        Conexiones activas, transacciones, bloqueos, tamaño de BD, replicación.
        Credenciales en `/etc/default/prometheus_postgres.env`.
      job_prometheus: "{{ tenant_id }}_postgres"
      labels: [tenant, component=postgres]
      dashboard: PostgreSQL.json

    redis_exporter:
      puerto: 9121
      imagen: oliver006/redis_exporter
      host: data_stateless
      proposito: |
        Memoria, keys, comandos/s, clientes conectados, persistencia.
      job_prometheus: "{{ tenant_id }}_redis"
      labels: [tenant, component=redis]
      dashboard: Redis.json

    gearman_exporter:
      puerto: 9418
      imagen: gearmanexporter/gearman-exporter:v0.5.0
      host: data_stateless
      proposito: |
        Colas Gearman: jobs en espera, workers activos, funciones registradas.
      job_prometheus: "{{ tenant_id }}_gearman"
      labels: [tenant, component=gearman]

    uwsgi_exporter:
      puerto: 9117
      imagen: timonwong/uwsgi-exporter
      host: omlapp_web
      proposito: |
        Stats del proceso uWSGI de Django (workers, requests, backlog).
        Apunta al socket HTTP de stats de uWSGI en el pod web.
      job_prometheus: "{{ tenant_id }}_uwsgi"
      labels: [tenant, component=uwsgi]

    asterisk_metrics:
      puerto: 7088
      host: acd
      proposito: |
        Métricas nativas expuestas por el módulo ARI/metrics de Asterisk
        (acd-server). No es un exporter sidecar: es el endpoint HTTP del ACD.
      job_prometheus: "{{ tenant_id }}_asterisk"
      labels: [tenant, component=asterisk]

    rtpengine_metrics:
      puerto: 22223
      host: edge (telephony_edge pod)
      proposito: Métricas de sesiones RTP, packet loss, MOS estimado.
      job_prometheus: "{{ tenant_id }}_rtpengine"
      labels: [tenant, component=rtpengine]

    haproxy_metrics:
      puerto: 8404
      ruta: /metrics
      host: edge
      proposito: |
        Exporter nativo de HAProxy (frontend `prometheus_metrics`).
        Restringido a redes privadas (`haproxy_metrics_allowed_src`).
      job_prometheus: "{{ tenant_id }}_haproxy"
      labels: [tenant, component=haproxy, host]

    kamailio_pstn_metrics:
      puerto: 9273
      ruta: /metrics
      host: edge (kamailio_pstn)
      proposito: |
        Módulo `xhttp_prom` de Kamailio PSTN: counters SIP, transacciones TM,
        estadísticas de módulos cargados.
      job_prometheus: "{{ tenant_id }}_kamailio_pstn"
      labels: [tenant, component=kamailio_pstn]
      nota: Requiere imagen KAMAILIO_IMG reconstruida con la config actual.

    kamailio_webrtc_metrics:
      puerto: 9274
      ruta: /metrics
      host: edge (kamailio_webrtc)
      proposito: |
        Igual que PSTN pero para el proxy WebRTC (registro de softphones,
        autenticación efímera AUTHEPH, enrutamiento hacia Asterisk).
      job_prometheus: "{{ tenant_id }}_kamailio_webrtc"
      labels: [tenant, component=kamailio_webrtc]

  validacion_post_deploy: |
    Tras el deploy, Ansible ejecuta `validate_scrape.yml` desde el host Prometheus:
    verifica reachability TCP a todos los puertos de scrape en `omni_ip_lan`.
    Tag: `validate`. Ejemplo manual desde omlapp_web/AIO:

      curl -s http://<omni_ip_lan>:9100/metrics | head
      curl -s http://<edge_ip>:9273/metrics | head

  federacion_central: |
    Un Prometheus/Grafana central puede hacer **federation** o scrape directo
    de `https://<tenant-fqdn>/prom` (con ACL en HAProxy) para consolidar
    métricas multi-tenant.

# -----------------------------------------------------------------------------
# Promtail y journald
# -----------------------------------------------------------------------------

promtail_journald:

  resumen: |
    Todos los contenedores Quadlet de OMniLeads usan `LogDriver=journald`.
    Los logs no se escriben en archivos planos sino en el journal del host.
    Promtail lee ese journal, filtra por unidad systemd (`*.service`) y empuja
    los eventos a Loki central con labels de tenant, host y servicio.

  activacion: |
    Promtail se despliega cuando:
      - `loki_url` está definido en el inventario, o
      - `oml_observability_deploy=true` (acción observability del deploy.sh)

    Variable: component_observability_promtail_enabled (topology_normalize)

  journald_configuracion:
    archivo: group_vars/all/observability.yml
    parametros:
      Storage: volatile
      RuntimeMaxUse: 192M
      RuntimeKeepFree: 32M
      SystemMaxUse: 5G
      SystemMaxFileSize: 200M
      SystemKeepFree: 2G
    rol_aplicacion: roles/prerequisitos/tasks/os_configuration.yml
    nota: |
      `Storage=volatile` mantiene el journal en tmpfs (/run/log/journal) para
      reducir desgaste de disco. Los logs persistentes de negocio deben fluir
      a Loki vía Promtail, no depender del journal en disco.

  promtail_container:
    unit: promtail.service
    imagen: grafana/promtail
    volumenes:
      - /etc/default/promtail.yml → config
      - /run/log/journal/ → /var/log/journal/ (ro)
      - /etc/machine-id (ro)
    puerto_http: 9080
    plantilla: roles/observability_promtail/templates/promtail.container

  flujo_datos: |
    ┌─────────────────┐     ┌──────────────┐     ┌─────────────┐     ┌──────┐
    │ Contenedor      │     │ journald     │     │  Promtail   │     │ Loki │
    │ Quadlet         │────▶│ (host)       │────▶│  (host)     │────▶│centr.│
    │ LogDriver=      │     │ _SYSTEMD_UNIT│     │  filtra por │     │:3100 │
    │ journald        │     │ =nginx.svc   │     │  unit+labels│     └──────┘
    └─────────────────┘     └──────────────┘     └─────────────┘

  scrape_por_topologia: |
    La plantilla `promtail.yml` genera jobs distintos según los grupos de
    inventario del host. Cada job usa el driver `journal` con match
    `_SYSTEMD_UNIT=<servicio>.service`.

    Ejemplos por tier:

      omnileads_aio:
        Todos los servicios del stack completo (acd, kamailio, nginx, postgres,
        redis, dialer workers, etc.)

      edge:
        haproxy, kamailio_pstn, kamailio_webrtc, rtpengine

      data_statefull:
        postgresql, minio

      data_stateless:
        redis, gearman

      omlapp_web:
        omnileads, daphne, nginx, websockets, dialer_api

      omlapp_workers:
        call_logger, whatsapp, supervision_*, background_* ...

      dialer_workers:
        dialer_process_{campaign,contact,event}@N.service (instancias)

  labels_loki:
    estandar:
      - tenant      → tenant_id del inventario (multi-tenancy en Loki)
      - host        → inventory_hostname
      - job         → nombre lógico del servicio (ej. nginx, kamailio_pstn)
      - node_type   → aio | edge | web | workers | acd | ...
      - service_family → acd | telephony | infrastructure | dialer | ...
      - unit        → unidad systemd completa (relabel desde __journal__systemd_unit)
      - container_name / container_id → metadata del contenedor Podman

  consultas_logql_ejemplos: |
    {tenant="<tenant_id>", job="nginx"}
    {tenant="<tenant_id>", job="kamailio_webrtc"} |= "ERROR"
    {tenant="<tenant_id>", service_family="dialer", worker_type="campaign"}

  variables:
    loki_url: "URL base del Loki central, ej. http://host:3100 (vault_loki_url en inventario)"
    tenant_id: "Identificador del tenant; se envía como X-Scope-OrgID a Loki"

  validacion: |
    - Ansible verifica `<loki_url>/ready` post-deploy.
    - Smoke test local: `make smoke-promtail` en ansible/
    - Verificar journal en host: `journalctl -u nginx.service -n 20`

# -----------------------------------------------------------------------------
# Homer HEP — Kamailio PSTN y WebRTC
# -----------------------------------------------------------------------------

homer_hep:

  resumen: |
    Cuando `homer_host` está definido en el inventario del tenant, Kamailio
    PSTN y WebRTC activan el módulo `siptrace` con **HEP v3** para duplicar
    el tráfico SIP hacia un colector Homer (típicamente heplify-server).
    Esto habilita análisis de llamadas, correlación SIP y métricas QoS
    (`heplify_*`) consumidas por dashboards Grafana centrales.

  activacion_inventario:
    variables:
      homer_host: "IP/hostname del colector HEP (heplify-server / Homer)"
      homer_port: "Puerto HEP (default 9060)"
      homer_kamailio_pstn_capture_id: "ID numérico agente PSTN (default 2002)"
      homer_kamailio_webrtc_capture_id: "ID numérico agente WebRTC (default 2003)"
      homer_pstn_node_name: "Label correlación PSTN (default {{ tenant_id }}-pstn)"
      homer_webrtc_node_name: "Label correlación WebRTC (default {{ tenant_id }}-webrtc)"
    plantillas_env:
      - roles/telephony_edge/templates/kamailio_pstn.env
      - roles/telephony_edge/templates/kamailio_webrtc.env

  flujo_hep: |
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

  kamailio_pstn:
    servicio: kamailio_pstn.service
    pod: telephony_edge
    funcion: |
      Proxy SIP hacia carriers/ITSP. Maneja INVITE inbound/outbound, NAT,
      RTPengine, discriminación OMniLeadsOutbound. Es el punto de entrada
      PSTN del tenant.

    activacion_runtime: |
      entrypoint_pstn.sh evalúa HOMER_ENABLE. Si es true, agrega `-A WITH_HOMER`
      a los argumentos de Kamailio, lo que incluye la config HEP en compile-time.

    config_hep:
      modulo: siptrace.so
      parametros:
        trace_to_database: 0
        duplicate_uri: "sip:{{ homer_host }}:{{ homer_port }}"
        trace_on: 1
        trace_flag: FLB_HOMER (24)
        hep_mode_on: 1
        hep_version: 3
        hep_capture_id: "{{ homer_kamailio_pstn_capture_id | default(2002) }}"
      plantilla: roles/telephony_edge/templates/kamailio_pstn.cfg

    captura_en_request_route: |
      En cada request (excepto OPTIONS):
        1. setflag(FLB_HOMER)
        2. sip_trace("", "$env(HOMER_NODE_NAME)")  → incluye node name en HEP

    defaults:
      HOMER_CAPTURE_ID: 2002
      HOMER_NODE_NAME: "{{ tenant_id }}-pstn"

  kamailio_webrtc:
    servicio: kamailio_webrtc.service
    pod: telephony_edge
    funcion: |
      Proxy SIP para clientes WebRTC: registro de extensiones, autenticación
      efímera (AUTHEPH_SK), WebSocket/WSS, enrutamiento hacia Asterisk/ACD.

    activacion_runtime: |
      entrypoint_webrtc.sh: igual que PSTN, `-A WITH_HOMER` cuando HOMER_ENABLE=true.

    config_hep:
      modulo: siptrace.so
      parametros: "(idénticos a PSTN, distinto capture_id)"
      plantilla: components-git-repo/kamailio/source/kamailio_webrtc.cfg

    captura_en_request_route: |
      Misma lógica que PSTN en route(REQINIT): flag FLB_HOMER + sip_trace con
      HOMER_NODE_NAME. También se invoca sip_trace en rutas de reply para
      capturar respuestas SIP.

    defaults:
      HOMER_CAPTURE_ID: 2003
      HOMER_NODE_NAME: "{{ tenant_id }}-webrtc"

  diferenciacion_pstn_vs_webrtc: |
    Homer distingue el origen del tráfico por:
      1. hep_capture_id numérico (2002 PSTN / 2003 WebRTC) — obligatorio entero 32-bit
      2. HOMER_NODE_NAME — string legible en la UI de Homer (ej. KonectaPortaVoice-pstn)

    En Grafana, los dashboards SIP filtran por label `target_name` derivado
    de esos identificadores (SIP_Overview, SIP_KPIs, SIP_Error_Rates, etc.).

  asterisk_hep:
    estado: deshabilitado por defecto en despliegue Ansible
    nota: |
      acd-server.env define HOMER_ENABLE=False aunque homer_host exista.
      El archivo hep.conf de Asterisk existe en components-git-repo/acd pero con
      enabled=no. La captura SIP activa en producción es vía Kamailio (edge),
      no directamente desde Asterisk. Para habilitar HEP en Asterisk se requiere
      intervención explícita (comentario en inventory: "Request by Asterisk hep module").

  metricas_qos_grafana:
    origen: heplify-server exporta métricas Prometheus (prefijo heplify_)
    dashboards:
      - SIP_Overview.json      → ASR, NER, tasas INVITE/REGISTER
      - SIP_KPIs.json          → KPIs con comparación semanal
      - SIP_Error_Rates.json   → 4xx/5xx/6xx
      - SIP_Methods&Responses.json
      - SIP_Calls&Registers.json
      - QOS_RTCP.json          → jitter, packet loss, RTT
      - QOS_XRTP.json          → MOS, packet loss rate, delay
      - QOS_Horaclifix.json
      - Host_Overview.json     → incluye heplify_packets_total

# -----------------------------------------------------------------------------
# Variables de referencia rápida
# -----------------------------------------------------------------------------

variables:

  observabilidad:
    loki_url: "URL base del Loki central para Promtail (ej. http://host:3100)"
    oml_observability_deploy: "true fuerza deploy de Promtail sin loki_url"
    homer_host / homer_port: "Activa HEP en Kamailio PSTN + WebRTC"
    haproxy_prom_allowed_src: "CIDRs permitidos para https://<fqdn>/prom"
    haproxy_metrics_allowed_src: "CIDRs para :8404/metrics en edge"

  puertos_exporter:
    fuente: group_vars/all/runtime.yml
    mapa:
      prometheus_server_port: 9090
      prometheus_node_exporter_port: 9100
      prometheus_podman_exporter_port: 9882
      prometheus_postgres_exporter_port: 9187
      prometheus_redis_exporter_port: 9121
      prometheus_gearman_exporter_port: 9418
      prometheus_uwsgi_exporter_port: 9117
      kamailio_pstn_metrics_port: 9273
      kamailio_webrtc_metrics_port: 9274
      haproxy_metrics_port: 8404
      rtpengine_metrics_port: 22223

  journald:
    fuente: group_vars/all/observability.yml

# -----------------------------------------------------------------------------
# Diagrama de componentes (tenant)
# -----------------------------------------------------------------------------

diagrama: |
  ┌─────────────────────────────────────────────────────────────────────────────┐
  │                           TENANT OMniLeads                                  │
  │                                                                             │
  │  ┌──────── edge ────────┐    ┌──── omlapp_web / AIO ────────────────────┐  │
  │  │ HAProxy :443 /prom   │    │ Prometheus :9090 (scrape all nodes)     │  │
  │  │ Kamailio PSTN :9273  │    │ uwsgi_exporter :9117                    │  │
  │  │ Kamailio WebRTC:9274 │    │ observability.pod                         │  │
  │  │ RTPengine :22223     │    └──────────────────────────────────────────┘  │
  │  │ HEP ─────────────────┼──┐                                                 │
  │  │ observability.pod    │  │    ┌── data_statefull ──┐  ┌ data_stateless ┐ │
  │  └──────────────────────┘  │    │ postgres_exp :9187│  │ redis_exp :9121│ │
  │                             │    │ observability.pod │  │ gearman :9418  │ │
  │  ┌──────── acd ──────────┐  │    └───────────────────┘  │ observability  │ │
  │  │ Asterisk :7088        │  │                           └────────────────┘ │
  │  │ observability.pod     │  │                                              │
  │  └───────────────────────┘  │    Cada host: Promtail → journald → Loki    │
  │                              │                                              │
  └──────────────────────────────┼──────────────────────────────────────────────┘
                                 │ HEP v3
                                 ▼
                    ┌────────────────────────────┐
                    │  CENTRO OBSERVABILIDAD     │
                    │  Loki | Grafana | Homer    │
                    │  (heplify → heplify_* metrics)
                    └────────────────────────────┘
