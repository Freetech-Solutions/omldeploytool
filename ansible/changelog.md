# Changelog tecnico Ansible: `develop-3.0`

Comparacion analizada: `main...develop-3.0` sobre `ansible/` (HEAD actual de la rama).

## Resumen Ejecutivo

La rama `develop-3.0` transforma el deploy Ansible de OMniLeads hacia una arquitectura 3.X basada en roles, topologia normalizada por **grupos pod** y servicios Podman gestionados por systemd/Quadlet. El cambio elimina el arbol `components/*` como mecanismo principal, separa responsabilidades por capas (`data`, `edge`, compute) y prepara despliegues AIO y cluster con inventarios explicitos. Tambien centraliza secretos con Ansible Vault, reordena la telefonia (WebRTC, PSTN, RTPengine), incorpora observabilidad tenant con validacion de scrape y captura SIP opcional hacia Homer (HEP), y documenta la migracion de inventarios legacy en `UPGRADE_YOUR_INVENTORY.md`.

## Nuevas Funcionalidades (Features)

- `deploy.sh` 3.X: integracion obligatoria de Ansible Vault (pre-vuelo `ansible-vault view`, `ANSIBLE_VAULT_PASSWORD_FILE` / `ansible.cfg` / `--ask-vault-pass`), activacion automatica del venv, derivacion de `tenant_folder` desde `instances/<tenant>/inventory.yml` o basename de `--inventory`, acciones alineadas con tags de `site_core.yml` (`data`, `edge`, `gearman`, `nginx`, `qa`, `observability`, `interaction_processor`, …), alias `kamailio` → `telephony-edge`, accion dedicada `--action=observability` (fuerza `oml_observability_deploy=true`) y **rechazo explicito** de acciones legacy (`backup`, `restore`, `recycle`, `sentinel`, `restart`) con mensaje orientando a `oml_manage`.
- Deploy por topologia: `playbooks/site.yml` (capas data → edge → compute → AIO), `site_core.yml`, `aio.yml` y `cluster.yml`.
- Inventario 3.X por **grupos pod**: `data_statefull`, `data_stateless`, `edge`, `omlapp_web`, `omlapp_workers`, `dialer_workers`, `acd`, `callrec_processor` y `omnileads_aio`. Un host puede repetirse en varios grupos para co-localizar pods. Los grupos legacy `omnileads_data`, `omnileads_edge`, `omnileads_nodes`, `omnileads_voice`, `omnileads_app` y `omnileads_dialer` **ya no controlan el deploy** (ver `UPGRADE_YOUR_INVENTORY.md`).
- Normalizacion automatica de topologia: el rol `topology_normalize` infiere layout (`aio` vs `cluster`), `data_host`, `edge_host`, endpoints de servicios y switches `component_*_enabled` segun membresia pod del host.
- Gestion de pods Podman con Quadlet: pods declarativos para `data_statefull`, `data_stateless`, `telephony_edge`, `acd`, `omlapp_web`, `omlapp_workers`, `dialer_workers`, `callrec_processor`, `observability` y `qa` (cuando `qa_env` esta definido).
- Telefonia de borde: rol `telephony_edge` con `rtpengine`, `kamailio_webrtc` y `kamailio_pstn`; captura HEP v3 opcional hacia Homer cuando `homer_host` esta definido.
- Procesamiento de grabaciones: rol `interaction_processor` despliega compresor y transcriptor en el pod `callrec_processor.pod` (accion/tag `interaction_processor`).
- Dialer simplificado: sin contenedores propios de Asterisk/dialplan/listener; API, workers y jobs de Omnidialer.
- Observabilidad tenant: roles `observability_prometheus` y `observability_promtail`, pod `observability` en cada host con tier activo, validacion TCP de targets de scrape desde el host Prometheus, acceso externo a `/prom` via HAProxy en edge con ACL `haproxy_prom_allowed_src`, y plantillas de dashboards Grafana de referencia en el rol Prometheus.
- Ansible Vault obligatorio: secretos como `vault_*` en `group_vars/all/vault.yml` (fuera de git).
- Upgrade desde 2.X: rol `upgrade_from_2X` (limpieza systemd legacy, Debian 12 → 13, restore `omnileads` y opcionalmente `omnidialer`).
- Operacion local: `oml_manage` para status, health, logs, reinicios, consola Django, Redis, PostgreSQL, Asterisk y backup/restore en el host.
- Bootstrap documentado: `ANSIBLE_BOOTSTRAP.md`, script `bootstrap.sh`, `requirements.txt` y `requirements.yml`.
- Roles opcionales fuera de `site_core.yml`: `traefik_lb` (balanceo Traefik v3 hacia backends nginx) y `sentiment_analysis` (`component_sentiment_analysis_enabled: false` por defecto).

## Cambios Arquitectonicos / Tecnicos

### Cambio hacia roles

La migracion va de playbooks monoliticos en `ansible/components/*` (eliminado) hacia roles en `ansible/roles/*`. La composicion ocurre en `playbooks/site_core.yml`, donde cada rol se activa con condiciones de `topology_normalize`.

Roles principales introducidos o reestructurados:

- `prerequisitos`: paquetes, red Podman, checks de inventario, certificados, swap, journald, backup env y `oml_manage`.
- `topology_normalize`: layout, peers de cluster, hosts de servicio y componentes habilitados.
- `pods`: render y arranque de `.pod` Quadlets por topologia.
- Datos: `postgresql`, `redis`, `gearman`, `minio`.
- Edge: `telephony_edge`, `haproxy` (solo en hosts del grupo `edge` explicito, no en AIO sin grupo `edge`).
- Compute: `acd`, `omlapp`, `omlapp_workers`, `websockets`, `dialer`, `nginx`, `interaction_processor`, `addons`, `qa`.
- Observabilidad: `observability_prometheus`, `observability_promtail`.
- Migracion: `upgrade_from_2X`.

Cada componente queda encapsulado con defaults, handlers, templates y tareas propias. Esto facilita despliegues parciales por tags, elimina parametros `*_repo_path` y permite razonar por capas: data → edge → compute → AIO.

### Introduccion de Quadlet

Podman Quadlet define contenedores y pods bajo `/etc/containers/systemd/`. Los roles renderizan `.container`, `.pod` y `.network`; systemd genera las unidades `*.service`.

Ejemplos:

- `roles/pods/templates/*.pod.j2` define la infraestructura de pods.
- `roles/omlapp/templates/django.service` → `/etc/containers/systemd/omnileads.container`.
- `roles/nginx/templates/nginx.container` → `/etc/containers/systemd/nginx.container`.
- `roles/telephony_edge/templates/kamailio_pstn.service` → `/etc/containers/systemd/kamailio_pstn.container`.

DevOps sigue operando con `systemctl start|stop|restart <servicio>.service`, pero el origen declarativo vive en Quadlet. Los handlers reinician pods completos cuando el contenedor pertenece a un pod, porque reiniciar unidades individuales puede dejar inestable la infra del pod en Podman 5.x.

### Networking: bridge por defecto, host solo para el Pod Edge

En `main`, muchos contenedores usaban `--network=host`. En esta rama se crea la red Podman `omnileads` con driver `bridge` (`roles/prerequisitos/templates/omnileads.network`) y los pods internos se conectan a esa red.

Pods en bridge:

- `data_statefull`: PostgreSQL y MinIO; publica `5432`, `9000` y `9001` sobre `omni_ip_lan`.
- `data_stateless`: Redis y Gearman; publica `6379` y `4730` sobre `omni_ip_lan`.
- `acd`: Asterisk/ACD, app ARI, config y FastAGI; publica `5060/udp` de forma controlada.
- `omlapp_web`: Django/uWSGI, Daphne, Nginx, Websockets y API del Dialer; publica `80` y `443`.
- `omlapp_workers`, `dialer_workers`, `callrec_processor` y `observability`.

Excepcion principal:

- `telephony_edge` usa `Network=host` (`rtpengine`, `kamailio_webrtc`, `kamailio_pstn`) por requisitos de interfaces, puertos SIP/RTP y exposicion hacia redes externas.

### Introduccion de Kamailio PSTN

Antes existia un Kamailio mas general asociado a la telefonia. Ahora el rol `telephony_edge` separa:

- `kamailio_webrtc`: proxy WebRTC/SIP para agentes.
- `kamailio_pstn`: proxy SIP PSTN para ITSP/trunks.

`kamailio_pstn` consume variables como `ITSP_NODES`, `IPADDR_PUBLIC`, `IPADDR_PRIVATE`, `FQDN`, `RTPENGINE_SOCKET` y `KAMAILIO_CERTS_LOCATION`. ACD apunta via `VOIP_PROXY_HOSTNAME` / `VOIP_PROXY_PORT`, y `topology_normalize` calcula `kamailio_pstn_host` por defecto: local en AIO/edge y `edge_host` para nodos de compute en cluster.

### Captura SIP hacia Homer (HEP)

Cuando `homer_host` esta definido en el inventario, `kamailio_pstn` y `kamailio_webrtc` activan `siptrace` con HEP v3 hacia el colector (`homer_port`, default `9060`). Variables relevantes:

- `homer_kamailio_pstn_capture_id` / `homer_kamailio_webrtc_capture_id` (defaults `2002` / `2003`).
- `homer_pstn_node_name` / `homer_webrtc_node_name` (defaults `{{ tenant_id }}-pstn` / `{{ tenant_id }}-webrtc`).

Sin `homer_host`, `HOMER_ENABLE=false` y no se compila la config HEP. Asterisk mantiene `HOMER_ENABLE=False` por defecto; habilitar HEP en ACD requiere intervencion explicita.

### Advertencia sobre `infra_env`

`infra_env` deja de formar parte del flujo ejecutable de Ansible 3.X. En `main` se usaba para escenarios `cloud`, `lan`, `nat`, `custom`, `hybrid` o `all`; en esta rama esa logica se reemplaza por variables explicitas:

- `omni_ip_lan` y `omni_ip_wan`.
- `nat_ip_addr` como fallback para calcular `omni_ip_wan`.
- `rtpengine_env` y `rtpengine_custom_net_cfg`.
- `kamailio_pstn_host` y `kamailio_pstn_port`.
- **Grupos pod** del inventario (`data_statefull`, `edge`, `omlapp_web`, …) y `omnileads_aio`.

Los roles nuevos no consumen `infra_env`. QA y DevOps no deben validar inventarios nuevos esperando que cambie el comportamiento del deploy.

### Pods principales

- `data_statefull`: PostgreSQL y MinIO con puertos publicados sobre `omni_ip_lan`.
- `data_stateless`: Redis y Gearman (colas/cache separadas del almacenamiento persistente).
- `telephony_edge`: `rtpengine`, `kamailio_webrtc` y `kamailio_pstn` en `Network=host`.
- `acd`: `acd-server`, `acd-app`, `acd-conf` y `acd-fastagi` en bridge.
- `omlapp_web`: capa web/HTTP (Django, Daphne, Nginx, Websockets, API Dialer).
- `omlapp_workers`: procesos async de Django (call logger, WhatsApp, supervision, schedulers, dialer events listener, etc.).
- `dialer_workers`: workers y jobs auxiliares de Omnidialer.
- `callrec_processor`: pod para compresion y transcripcion; contenedores desplegados por el rol `interaction_processor` (habilitado en hosts `omlapp_workers`; co-localizar con grupo `callrec_processor` o usar `omnileads_aio`).
- `observability`: Prometheus (solo en tier web/AIO), exporters por tier y Promtail cuando corresponde.

### Dialer simplificado

El Dialer deja de desplegar Asterisk, dialplan y listener propios. El rol nuevo se enfoca en:

- `dialer_api` dentro del pod `omlapp_web`.
- Servicios auxiliares en `dialer_workers` (`incidence_rules`, `manage_campaign`, `scheduler`, `send_reports`, `render_template`).
- Workers templated `dialer_process_campaign@`, `dialer_process_contact@` y `dialer_process_event@`.
- Un unico `dialer.env` con Redis, PostgreSQL, Gearman, WebSocket y CAPS.

Default de `dialer_process_campaign_replicas` reducido de 10 a 5 en el inventario de ejemplo; se elimina `dialer_user`. Integracion con Django via `background_dialer_tasks` en `omlapp_workers` y `OML_OMNIDIALER_SECRET` en `django.env`.

Consideracion: QA debe confirmar que las replicas `dialer_process_*_replicas` queden iniciadas/habilitadas segun inventario.

### Observabilidad

Capa tenant desacoplada del centro Grafana/Loki/Homer central:

- Pod `observability` automatico en hosts con cualquier tier data/edge/compute activo.
- Prometheus server y scrape config solo en hosts `omlapp_web` / AIO; exporters (node, podman, postgres, redis, gearman, uwsgi) segun tier del host.
- Publicacion de Prometheus en `omni_ip_lan:9090`; acceso externo recomendado via `https://<fqdn>/prom` en HAProxy edge, restringido por `haproxy_prom_allowed_src` (lista vacia = `/prom` denegado por defecto).
- Validacion post-deploy (`validate_scrape.yml`): comprobacion TCP de puertos de scrape inter-nodo desde el host Prometheus (tag `validate`).
- Promtail hacia `loki_url` cuando esta definido, o forzado con `--action=observability` / `oml_observability_deploy=true`.
- Plantillas JSON de dashboards (SIP, QoS, PostgreSQL, Redis, MinIO, etc.) incluidas como referencia para provisioning Grafana central; no se instalan en el tenant por defecto.
- Smoke tests locales: `playbooks/smoke_prometheus_template.yml` y `playbooks/smoke_promtail_template.yml`.

### Ansible Vault

Secretos fuera del inventario en texto plano. Referencias tipicas:

- `vault_postgres_password`, `vault_s3_http_admin_pass`, `vault_bucket_access_key`, `vault_bucket_secret_key`.
- `vault_ami_password`, `vault_dialer_password`, `vault_google_api_key`, `vault_google_cloud_projectid`.
- `vault_callrec_transcriber_api_key`, `vault_autheph_sk`.
- `vault_backup_bucket_access_key`, `vault_backup_bucket_secret_key`, `vault_loki_url`.

`site_core.yml` carga `group_vars/all/vault.yml` junto con `runtime.yml`, `images.yml`, `observability.yml` y `qa.yml`. El archivo vault queda en `.gitignore`.

### Dependencias, imagenes y configuracion Ansible

- `requirements.txt`: `ansible-core==2.17.14`, `mitogen==0.3.47`, `ansible-lint==24.12.2`, `yamllint==1.38.0`, `black==26.3.1`.
- `requirements.yml`: `community.postgresql`, `containers.podman`, `ansible.posix`, `community.general`, `ansible.netcommon`, `ansible.utils`.
- `ansible.cfg`: `roles_path=./roles`, fact caching, `forks=25`, callbacks profile/timer, pipelining, ControlMaster SSH.
- Imagenes centralizadas en `group_vars/all/images.yml` (`APP_IMG`, `ACD_IMG`, `KAMAILIO_IMG`, `POSTGRES_IMG`, etc.).
- Runtime y puertos de observabilidad en `group_vars/all/runtime.yml`.

### Base de datos y migraciones

El rol `omlapp` ejecuta migraciones Django via `django_migrations.sh` cuando cambia el env o los Quadlets. PostgreSQL apunta a imagen `postgres:18-trixie`; inventario refuerza `postgres_maintenance_db: postgres`.

La base `omnidialer` esta en templates SQL y en restore de `upgrade_from_2X`; si `backup_filename_OMD` no se define, el restore de Omnidialer se omite explicitamente.

## Impacto y Consideraciones para Despliegue

### Para QA

- Probar layouts `layout-aio` y `layout-cluster`, mas corridas `install`, `update` y `upgrade`.
- Validar resolucion de `topology_normalize`: `postgres_host`, `redis_host`, `gearman_host`, `kamailio_host`, `kamailio_pstn_host`, `rtpengine_host`, `nginx_host`, `acd_host`, `dialer_host`.
- Verificar Quadlets: `systemctl status <servicio>.service` y pods `systemctl status <pod>-pod.service`.
- Validar networking: bridge `omnileads`, puertos en `omni_ip_lan`, `telephony_edge` en host network.
- Telefonia: WebRTC vs PSTN por separado; RTP via `rtpengine`.
- Homer: con `homer_host` definido, verificar HEP desde Kamailio PSTN/WebRTC (IDs `2002`/`2003` por defecto).
- Dialer E2E: campanas, workers `process_campaign/contact/event`, Gearman, Redis DB 3, WebSocket y eventos hacia Django.
- Vault: secretos faltantes deben fallar temprano con mensajes claros (`prerequisitos` / pre-vuelo `deploy.sh`).
- Upgrade 2.X en entorno descartable: limpieza legacy, Debian 13, restore DBs.
- Observabilidad: exporters por host, scrape inter-nodo, mensaje de `validate_scrape`, Promtail → Loki, `/prom` en HAProxy solo con CIDRs en `haproxy_prom_allowed_src`.

### Para DevOps

- Migrar inventarios segun `UPGRADE_YOUR_INVENTORY.md`: eliminar `infra_env`, reemplazar grupos legacy por **grupos pod**, mover secretos a `vault_*`.
- Crear `group_vars/all/vault.yml` y configurar `ANSIBLE_VAULT_PASSWORD_FILE` o `vault_password_file` (ver `ANSIBLE_BOOTSTRAP.md`).
- Ejecutar `./bootstrap.sh` o equivalente (`pip install -r requirements.txt`, `ansible-galaxy collection install -r requirements.yml`).
- Despliegues nuevos: correr `install` primero; tags parciales asumen prerequisitos y pods base reconciliados.
- Firewall/security groups: puertos publicados por pods + superficie SIP/RTP del edge + scrape LAN entre nodos del tenant.
- PostgreSQL 18/Trixie: validar compatibilidad y backups antes de actualizar produccion.
- Telefonia: usar `--action=telephony-edge`, `--action=voice` o `--action=kamailio`; no depender de `infra_env`.
- Backup/restore operativo: usar `oml_manage` en el host; `deploy.sh` rechaza `backup`/`restore`/`recycle`/`sentinel`/`restart`.
- Playbooks `backup.yml`, `restore.yml` y `recycle.yml` aun existen pero importan rutas `components/*` eliminadas; no usar hasta reimplementarlos.
- Documentacion ampliada: `README.md`, `Docs/observability.md`, `Docs/pods.md`, `UPGRADE_YOUR_INVENTORY.md`.

### Variables nuevas o relevantes

- Secretos Vault: `vault_postgres_password`, `vault_s3_http_admin_pass`, `vault_bucket_access_key`, `vault_bucket_secret_key`, `vault_ami_password`, `vault_dialer_password`, `vault_google_api_key`, `vault_google_cloud_projectid`, `vault_callrec_transcriber_api_key`, `vault_autheph_sk`, `vault_backup_bucket_access_key`, `vault_backup_bucket_secret_key`, `vault_loki_url`.
- Topologia/upgrade: `upgrade_from_2X`, `omni_ip_lan`, `omni_ip_wan`, `nat_ip_addr`.
- Edge/RTP: `kamailio_pstn_host`, `kamailio_pstn_port`, `rtpengine_host`, `rtpengine_ctl_port`, `rtpengine_env`, `rtpengine_custom_net_cfg`, `kamailio_webrtc_iface`.
- Homer: `homer_host`, `homer_port`, `homer_kamailio_pstn_capture_id`, `homer_kamailio_webrtc_capture_id`, `homer_pstn_node_name`, `homer_webrtc_node_name`.
- Bucket: `bucket_endpoint`, `bucket_endpoint_internal`, `bucket_url`.
- Dialer: `dialer_engine`, `dialer_caps`, `dialer_process_campaign_replicas`, `dialer_process_contact_replicas`, `dialer_process_event_replicas`.
- Observabilidad: `loki_url`, `oml_observability_deploy`, `haproxy_prom_allowed_src`, `prometheus_*_exporter_port`, `prometheus_server_port`.
- Runtime: `force_image_pull`, `pods_role_tags`.

## Changelog resumido

- Eliminado: arbol `ansible/components/*` como mecanismo principal de deploy.
- Agregado: `ansible/roles/*` como unidad de composicion en `site_core.yml`.
- Agregado: inventario por **grupos pod** (reemplaza grupos legacy `omnileads_*` operativos).
- Agregado: `topology_normalize` para layout, endpoints y componentes habilitados.
- Agregado: pods Podman/Quadlet por dominio de servicio.
- Cambiado: networking bridge interno, con excepcion `telephony_edge` en host network.
- Agregado: `kamailio_pstn` separado de `kamailio_webrtc`; captura HEP opcional hacia Homer.
- Agregado: rol `interaction_processor` para callrec en pod `callrec_processor`.
- Cambiado: Dialer reducido a API, workers y jobs Omnidialer.
- Agregado: observabilidad tenant (Prometheus, exporters, Promtail, validate scrape, ACL `/prom`).
- Agregado: Vault, bootstrap documentado y upgrade operativo desde 2.X (Debian 13).
- Cambiado: `deploy.sh` con Vault obligatorio, `--inventory`, acciones de layout y rechazo de acciones legacy.
- Riesgo abierto: playbooks `backup.yml` / `restore.yml` / `recycle.yml` rotos (importan `components/*`); usar `oml_manage` hasta reimplementacion.
