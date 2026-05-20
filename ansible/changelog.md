# Changelog tecnico Ansible: `oml-773-dev-oml-3`

Comparacion analizada: `main...oml-773-dev-oml-3` sobre `ansible/`.

## Resumen Ejecutivo

La rama `oml-773-dev-oml-3` transforma el deploy Ansible de OMniLeads hacia una arquitectura 3.X basada en roles, topologia normalizada y servicios Podman gestionados por systemd/Quadlet. El cambio reduce el acoplamiento del antiguo arbol `components/*`, separa responsabilidades por dominio (`data`, `edge`, `nodes`, `aio`) y prepara el despliegue para escenarios AIO y cluster mas claros. Tambien centraliza secretos con Ansible Vault y reordena la capa de telefonia para separar WebRTC, PSTN y RTPengine.

## Nuevas Funcionalidades (Features)

- `deploy.sh` 3.X: integracion obligatoria de Ansible Vault (pre-vuelo `ansible-vault view`, `ANSIBLE_VAULT_PASSWORD_FILE` / `ansible.cfg` / `--ask-vault-pass`), activacion automatica del venv, derivacion correcta de `tenant_folder` desde `instances/<tenant>/inventory.yml`, acciones alineadas con tags de `site_core.yml` (`data`, `edge`, `gearman`, `nginx`, `qa`, …), alias `kamailio` → `telephony-edge`, y eliminacion de acciones legacy (`backup`, `restore`, `recycle`, `sentinel`, `restart`, `components/haproxy`).
- Deploy por topologia: se agregan `playbooks/site.yml`, `site_core.yml`, `aio.yml` y `cluster.yml`, con validacion explicita de layout antes de desplegar.
- Inventario 3.X: se introducen grupos `omnileads_data`, `omnileads_edge`, `omnileads_nodes` y `omnileads_aio`, reemplazando el patron anterior de `omnileads_voice`, `omnileads_app` y `omnileads_dialer`.
- Normalizacion automatica de topologia: el rol `topology_normalize` infiere `data_host`, `edge_host`, `aio_host`, endpoints de servicios y switches de componentes segun el grupo donde vive cada host.
- Gestion de pods Podman con Quadlet: se agregan pods declarativos para `data_statefull`, `data_stateless`, `telephony_edge`, `acd`, `omlapp_web`, `omlapp_workers`, `dialer_workers`, `callrec_processor` y `observability`.
- Telefonia de borde: se agrega el rol `telephony_edge`, que administra `rtpengine`, `kamailio_webrtc` y el nuevo `kamailio_pstn`.
- Dialer simplificado: se elimina la dependencia operativa de contenedores propios de dialer para Asterisk/dialplan/listener y se reduce el rol a API, workers y jobs de Omnidialer.
- Ansible Vault obligatorio: los secretos del inventario pasan a variables `vault_*` resueltas desde `group_vars/all/vault.yml`, que queda fuera de git.
- Upgrade desde 2.X: se agrega el rol `upgrade_from_2X` con limpieza de unidades legacy, upgrade Debian 12 -> Debian 13 y restore de bases `omnileads` y opcionalmente `omnidialer`.
- Operacion local: se agrega `oml_manage` orientado a Podman/Quadlet para status, health, logs, reinicios, consola Django, Redis, PostgreSQL, Asterisk y flujos de backup/restore.
- Dependencias declaradas: se agregan `requirements.txt` para el entorno Python/Ansible y `requirements.yml` para collections de Ansible.

## Cambios Arquitectonicos / Tecnicos

### Cambio hacia roles

El cambio mas importante es la migracion desde playbooks monoliticos por componente en `ansible/components/*` hacia roles Ansible en `ansible/roles/*`. La composicion ahora ocurre en `playbooks/site_core.yml`, donde cada rol se activa con condiciones calculadas por `topology_normalize`.

Roles principales introducidos o reestructurados:

- `prerequisitos`: paquetes, red Podman, checks, certificados, swap, journald, backup env y `oml_manage`.
- `topology_normalize`: deteccion de layout, hosts de servicio y componentes habilitados.
- `pods`: render y arranque de `.pod` Quadlets por topologia.
- `data`: `postgresql`, `redis`, `gearman`, `minio`.
- `edge`: `telephony_edge`, `haproxy`.
- `compute/nodes`: `acd`, `omlapp`, `omlapp_workers`, `websockets`, `dialer`, `nginx`, `interaction_processor`, `addons`, `qa`.
- `observability`: `observability_prometheus` y `observability_promtail`.
- `upgrade_from_2X`: migracion operativa desde despliegues 2.X.

El valor tecnico es que cada componente queda encapsulado con defaults, handlers, templates y tareas propias. Esto facilita despliegues parciales por tags, reduce parametros `*_repo_path` y permite razonar por capas: primero data, luego edge, luego nodos de compute y finalmente AIO.

### Introduccion de Quadlet (Qualet)

La rama introduce Podman Quadlet como mecanismo principal para definir contenedores y pods bajo `/etc/containers/systemd/`. En lugar de generar unidades systemd manuales con `podman run`, los roles renderizan archivos `.container`, `.pod` y `.network`; systemd genera las unidades finales (`*.service`) a partir de esas definiciones.

Ejemplos:

- `roles/pods/templates/*.pod.j2` define la infraestructura de pods.
- `roles/omlapp/templates/django.service` se instala como `/etc/containers/systemd/omnileads.container`.
- `roles/nginx/templates/nginx.container` se instala como `/etc/containers/systemd/nginx.container`.
- `roles/telephony_edge/templates/kamailio_pstn.service` se instala como `/etc/containers/systemd/kamailio_pstn.container`.

Esto cambia el modelo operativo: DevOps sigue usando `systemctl start|stop|restart <servicio>.service`, pero el origen declarativo vive en Quadlet. Tambien aparecen handlers que reinician pods completos cuando el contenedor pertenece a un pod, porque reiniciar servicios individuales puede dejar inestable la infra del pod en Podman 5.x.

### Networking: bridge por defecto, host solo para el Pod Edge

En `main`, muchos contenedores usaban `--network=host`. En esta rama se crea la red Podman `omnileads` con driver `bridge` (`roles/prerequisitos/templates/omnileads.network`) y los pods internos se conectan a esa red.

Pods en bridge:

- `data_statefull`: PostgreSQL y MinIO; publica `5432`, `9000` y `9001` sobre `omni_ip_lan`.
- `data_stateless`: Redis y Gearman; publica `6379` y `4730` sobre `omni_ip_lan`.
- `acd`: Asterisk/ACD, app ARI, config y FastAGI; publica `5060/udp` de forma controlada.
- `omlapp_web`: Django/uWSGI, Daphne, Nginx, Websockets y API del Dialer; publica `80` y `443`.
- `omlapp_workers`, `dialer_workers`, `callrec_processor` y `observability`.

Excepcion principal:

- `telephony_edge` usa `Network=host`. Ese pod contiene `rtpengine`, `kamailio_webrtc` y `kamailio_pstn`, porque necesita control fino de interfaces, puertos SIP/RTP y exposicion hacia redes externas.

La implicancia es una superficie de red mas acotada: los servicios internos quedan en bridge y solo se publican puertos especificos, mientras que la exposicion telefonica queda concentrada en el pod de edge.

### Introduccion de Kamailio PSTN

Antes existia un Kamailio mas general asociado a la telefonia. Ahora el rol `telephony_edge` separa dos responsabilidades:

- `kamailio_webrtc`: proxy WebRTC/SIP para agentes y trafico asociado a WebRTC.
- `kamailio_pstn`: proxy SIP PSTN para interconexion con ITSP/trunks.

`kamailio_pstn` consume variables como `ITSP_NODES`, `IPADDR_PUBLIC`, `IPADDR_PRIVATE`, `FQDN`, `RTPENGINE_SOCKET` y `KAMAILIO_CERTS_LOCATION`. ACD apunta a este proxy mediante `VOIP_PROXY_HOSTNAME` y `VOIP_PROXY_PORT`, y `topology_normalize` calcula `kamailio_pstn_host` por defecto: local en AIO/edge y `edge_host` para nodos de compute en cluster.

Esto permite que la capa ACD deje de resolver directamente todos los escenarios de red y derive la salida PSTN al edge.

### Advertencia sobre `infra_env`

`infra_env` deja de formar parte del flujo ejecutable de Ansible 3.X. En `main` se usaba para decidir escenarios `cloud`, `lan`, `nat`, `custom`, `hybrid` o `all` dentro de templates de Asterisk, Kamailio y RTPengine; en esta rama esa logica se reemplaza por variables mas explicitas:

- `omni_ip_lan` y `omni_ip_wan`.
- `nat_ip_addr` como fallback para calcular `omni_ip_wan`.
- `rtpengine_env` y `rtpengine_custom_net_cfg`.
- `kamailio_pstn_host` y `kamailio_pstn_port`.
- grupos de inventario `omnileads_data`, `omnileads_edge`, `omnileads_nodes`, `omnileads_aio`.

La mejora es que la topologia ya no depende de una variable global ambigua. El rol `topology_normalize` infiere endpoints por rol de nodo y solo deja override manual cuando hay servicios externos (`postgres_host`, `bucket_url`, `rtpengine_host`, `kamailio_pstn_host`).

Importante: quedan referencias legacy a `infra_env` en documentacion, pero los roles nuevos no la consumen. QA y DevOps no deben validar inventarios nuevos esperando que `infra_env` cambie el comportamiento del deploy.

### Pods principales

- `data_statefull`: agrupa servicios con estado persistente, principalmente PostgreSQL y MinIO. Publica puertos de base y bucket sobre `omni_ip_lan`.
- `data_stateless`: agrupa Redis y Gearman. Aunque son servicios de datos, el pod separa colas/cache de almacenamiento persistente.
- `telephony_edge`: agrupa `rtpengine`, `kamailio_webrtc` y `kamailio_pstn` en `Network=host`.
- `acd`: agrupa `acd-server`, `acd-app`, `acd-conf` y `acd-fastagi` en bridge. Maneja Asterisk/ARI/FastAGI y habla con Kamailio PSTN/WebRTC.
- `omlapp_web`: agrupa la capa web y HTTP: Django/uWSGI, Daphne, Nginx, Websockets y API del Dialer.
- `omlapp_workers`: agrupa procesos async de Django: call logger, WhatsApp, supervision, dashboard scheduler, Redis cleanup, dialer events listener y callrec tasks.
- `dialer_workers`: agrupa workers de Omnidialer para campañas, contactos, eventos y jobs auxiliares.
- `callrec_processor`: agrupa compresion y transcripcion de grabaciones.
- `observability`: agrupa Prometheus y exporters.

### Dialer simplificado

El Dialer deja de desplegar servicios propios para Asterisk, dialplan y listener. El rol nuevo se enfoca en:

- `dialer_api` dentro del pod `omlapp_web`.
- Servicios auxiliares (`incidence_rules`, `manage_campaign`, `scheduler`, `send_reports`, `render_template`) dentro de `dialer_workers`.
- Workers parametrizados `dialer_process_campaign@`, `dialer_process_contact@` y `dialer_process_event@`.
- Un unico `dialer.env` con Redis, PostgreSQL, Gearman, WebSocket y CAPS.

Tambien se reduce el default de `dialer_process_campaign_replicas` de 10 a 5 en el inventario de ejemplo y se elimina `dialer_user`. La integracion con Django se refuerza mediante `background_dialer_tasks` en `omlapp_workers` y `OML_OMNIDIALER_SECRET` en `django.env`.

Consideracion: el rol renderiza las unidades templated `dialer_process_*@.container`; QA debe confirmar en despliegue que las replicas esperadas queden iniciadas/habilitadas segun `dialer_process_*_replicas`, porque ese es el punto funcional critico del escalado del Dialer.

### Ansible Vault

Los secretos dejan de estar en texto plano dentro del inventario. El inventario referencia variables como:

- `vault_postgres_password`.
- `vault_s3_http_admin_pass`.
- `vault_bucket_access_key` y `vault_bucket_secret_key`.
- `vault_ami_password`.
- `vault_dialer_password`.
- `vault_google_api_key`.
- `vault_callrec_transcriber_api_key`.
- `vault_backup_bucket_access_key` y `vault_backup_bucket_secret_key`.

El playbook principal carga `group_vars/all/vault.yml`, y `.gitignore` lo excluye del repositorio. Esto mejora seguridad y portabilidad, pero vuelve obligatorio que cada entorno tenga configurada la password de Vault antes de ejecutar `deploy.sh` o `ansible-playbook`.

### Dependencias, imagenes y configuracion Ansible

- `requirements.txt` fija `ansible-core==2.17.14`, `mitogen`, `ansible-lint`, `yamllint` y `black`.
- `requirements.yml` declara al menos `community.postgresql` y `containers.podman`.
- `ansible.cfg` activa `roles_path=./roles`, fact caching, `forks=25`, callbacks de profiling/timer, `pipelining` y ControlMaster SSH con mayor persistencia.
- Las imagenes pasan de un unico `group_vars/all` plano a `group_vars/all/images.yml`, usando nombres en mayusculas como `APP_IMG`, `ACD_IMG`, `KAMAILIO_IMG`, `POSTGRES_IMG`, `REDIS_IMG`, etc.

### Base de datos y migraciones

No se observa un cambio de esquema Ansible propio, pero el rol `omlapp` sigue ejecutando migraciones Django mediante `django_migrations.sh` cuando cambia el env o los Quadlets de la app. PostgreSQL cambia de imagen base hacia `postgres:18-trixie` y el inventario refuerza `postgres_maintenance_db: postgres`.

La base `omnidialer` queda contemplada en templates SQL y en restore de `upgrade_from_2X`; si `backup_filename_OMD` no se define, el restore de Omnidialer se omite de forma explicita.

## Impacto y Consideraciones para Despliegue

### Para QA

- Probar ambos layouts: `layout-aio` y `layout-cluster`, ademas de corridas `install`, `update` y `upgrade`.
- Validar que `topology_normalize` resuelva correctamente `postgres_host`, `redis_host`, `gearman_host`, `kamailio_host`, `kamailio_pstn_host`, `rtpengine_host`, `nginx_host`, `acd_host` y `dialer_host`.
- Verificar servicios generados por Quadlet con `systemctl status <servicio>.service` y pods con `systemctl status <pod>-pod.service`.
- Validar networking: servicios internos en bridge `omnileads`, puertos publicados en `omni_ip_lan` y `telephony_edge` en host network.
- Probar llamadas WebRTC y PSTN por separado: registros WebRTC contra `kamailio_webrtc`, llamadas PSTN contra `kamailio_pstn` y RTP por `rtpengine`.
- Probar Dialer extremo a extremo: creacion/ejecucion de campanas, workers `process_campaign/contact/event`, Gearman, Redis DB 3, WebSocket y eventos hacia Django.
- Verificar que los secretos faltantes en Vault fallen temprano y con mensajes claros.
- Ejecutar pruebas de upgrade desde 2.X en entorno descartable: limpieza de servicios legacy, Debian 12 -> 13, restore `omnileads` y restore opcional `omnidialer`.
- Validar observabilidad: Prometheus, exporters, Promtail con `loki_host` o `oml_observability_deploy=true`, y dashboards provisionados.

### Para DevOps

- Migrar inventarios antes del merge: eliminar `infra_env`, mover hosts a `omnileads_data`, `omnileads_edge`, `omnileads_nodes` o `omnileads_aio`, y reemplazar secretos planos por `vault_*`.
- Crear y distribuir de forma segura `group_vars/all/vault.yml` y configurar `ANSIBLE_VAULT_PASSWORD_FILE` o `vault_password_file`.
- Ejecutar `pip install -r requirements.txt` y `ansible-galaxy collection install -r requirements.yml` en el entorno de deploy.
- En despliegues nuevos, correr primero `install`; los tags parciales asumen que paquetes, red Podman y pods base ya existen o que `prerequisitos` puede reconciliarlos.
- Revisar firewall/security groups: abrir solo los puertos publicados por pods y la superficie SIP/RTP del edge.
- Considerar que `POSTGRES_IMG` sube a PostgreSQL 18/Trixie; validar compatibilidad, backups y restore antes de actualizar entornos con datos reales.
- Usar `telephony-edge` o `voice` para validar telefonia. No asumir que variables legacy de `infra_env` sigan modificando templates.
- Cuidado con acciones legacy de `deploy.sh`: `backup`, `restore`, `recycle`, `haproxy` y `sentinel` aun referencian rutas `components/*`, pero ese arbol fue removido en la rama. Antes de depender de esas acciones en produccion, hay que corregirlas o reemplazarlas por roles/playbooks vigentes.
- Revisar documentacion antes de publicar: existen referencias legacy a `infra_env` y algunos ejemplos aun pueden no representar exactamente la estructura final 3.X.

### Variables nuevas o relevantes

- Secretos Vault: `vault_postgres_password`, `vault_s3_http_admin_pass`, `vault_bucket_access_key`, `vault_bucket_secret_key`, `vault_ami_password`, `vault_dialer_password`, `vault_google_api_key`, `vault_callrec_transcriber_api_key`, `vault_backup_bucket_access_key`, `vault_backup_bucket_secret_key`.
- Topologia/upgrade: `upgrade_from_2X`, `omni_ip_lan`, `omni_ip_wan`, `nat_ip_addr`.
- Edge/RTP: `kamailio_pstn_host`, `kamailio_pstn_port`, `rtpengine_host`, `rtpengine_ctl_port`, `rtpengine_env`, `rtpengine_custom_net_cfg`.
- Bucket: `bucket_endpoint`, `bucket_endpoint_internal`.
- Dialer: `dialer_engine`, `dialer_caps`, `dialer_process_campaign_replicas`, `dialer_process_contact_replicas`, `dialer_process_event_replicas`.
- Observability: `loki_host`, `oml_observability_deploy`.
- Runtime: `force_image_pull`, `pods_role_tags`.

## Changelog resumido

- Eliminado: arbol `ansible/components/*` como mecanismo principal de deploy.
- Agregado: `ansible/roles/*` como nueva unidad de composicion.
- Agregado: `topology_normalize` para inferir layout, endpoints y componentes habilitados.
- Agregado: pods Podman/Quadlet por dominio de servicio.
- Cambiado: networking de host network generalizado a bridge interno, con excepcion del pod `telephony_edge`.
- Agregado: `kamailio_pstn` como proxy SIP PSTN separado de `kamailio_webrtc`.
- Cambiado: Dialer reducido a API, workers y jobs de Omnidialer.
- Agregado: Vault para secretos y exclusion de `group_vars/all/vault.yml` en git.
- Agregado: upgrade operativo desde 2.X, incluyendo Debian 13 y restore de DBs.
- Cambiado: `deploy.sh` usa playbooks en `ansible/playbooks`, acepta `--inventory` y agrega acciones de layout.
- Riesgo abierto: acciones legacy que aun apuntan a `components/*` deben corregirse o validarse antes de uso operativo.
