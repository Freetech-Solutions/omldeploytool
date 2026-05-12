# Guía de Actualización del Inventario (2.X a 3.X)

Este documento describe paso a paso las modificaciones necesarias para migrar un archivo `inventory.yml` de la versión 2.X de OMniLeads a la nueva estructura requerida por la versión 3.X.

> [!IMPORTANT]
> A partir de la versión 3.X, OMniLeads requiere el uso de **Ansible Vault** para el manejo de secretos. Asegúrese de tener configurado su Vault y las contraseñas correspondientes antes de proceder con el despliegue.

## Paso 1: Variables Generales y de Conexión

Se han modificado los parámetros básicos de conexión por SSH para utilizar un usuario estándar en lugar de `root`, implementando escalamiento de privilegios por seguridad.

1. **Cambio de usuario:** Reemplace `ansible_user: root` por `ansible_user: omnileads_admin`.
2. **Escalamiento de privilegios:** Habilite o descomente las siguientes directivas de `sudo`:
   ```yaml
   ansible_become: true
   ansible_become_method: sudo
   ansible_become_user: root
   ```
3. **Control de Upgrade:** Agregue la nueva variable para denotar que está actualizando desde 2.X:
   ```yaml
   upgrade_from_2X: true
   ```
4. **Limpieza:** Elimine la variable `infra_env`, ya que no se utiliza más en la arquitectura 3.X.
5. **FQDN:** Asegúrese de descomentar y definir la variable `fqdn` si accede mediante nombre de dominio (ej. `fqdn: omnileads.midominio.com`).

## Paso 2: Centralización de Secretos con Ansible Vault

Todas las contraseñas, claves y tokens que antes se guardaban en texto plano en el inventario ahora deben referenciar variables desencriptadas desde Vault. Reemplace los valores estáticos por su equivalente `vault_`:

*   **Base de Datos:**
    *   `postgres_password: "{{ vault_postgres_password }}"`
*   **Almacenamiento en S3 (MinIO o Externo):**
    *   `s3_http_admin_pass: "{{ vault_s3_http_admin_pass }}"`
    *   `bucket_access_key: "{{ vault_bucket_access_key }}"`
    *   `bucket_secret_key: "{{ vault_bucket_secret_key }}"`
*   **Telefonía (Asterisk):**
    *   `ami_password: "{{ vault_ami_password }}"`
*   **Campañas (Dialer):**
    *   `dialer_password: "{{ vault_dialer_password }}"`
*   **Integraciones y Transcripción:**
    *   `google_api_key: "{{ vault_google_api_key }}"`
    *   `callrec_transcriber_api_key: "{{ vault_callrec_transcriber_api_key }}"`
*   **Backups en S3:**
    *   `backup_bucket_access_key: "{{ vault_backup_bucket_access_key }}"`
    *   `backup_bucket_secret_key: "{{ vault_backup_bucket_secret_key }}"`

## Paso 3: Topología de Nodos y Grupos

La forma en que se agrupan los nodos y clústeres ha cambiado sustancialmente.

1.  **AIO (All in One):** Utilice una estructura simplificada bajo `omnileads_aio`. Se eliminaron los ejemplos de `tenant_example`.
2.  **Clústeres (Reemplazo de HA):** El bloque `ha_instances` ha sido removido a favor de `cluster_instances`.
3.  **Renombramiento de Grupos de Componentes:**
    *   Cambie `omnileads_voice` por `omnileads_edge`.
    *   Combine o reemplace los grupos `omnileads_app` y `omnileads_dialer` utilizando el nuevo grupo `omnileads_nodes`.

### Modelo actual: grupos pod (1 grupo = 1 Quadlet `.pod`)

> [!WARNING]
> **Compatibilidad rota:** los grupos `omnileads_data`, `omnileads_edge`, `omnileads_web`, `omnileads_workers`, `omnileads_acd` y `omnileads_nodes` **ya no** controlan el despliegue. Debés migrar al modelo por **grupos pod** listados abajo. Si un mismo host debe albergar varios pods, incluilo en **varios** de estos grupos (misma convención que antes con el host repetido en `omnileads_data` + `omnileads_nodes`).

| Grupo inventario | Contenido (Podman Quadlet) |
|--------------------|----------------------------|
| `data_statefull` | `data_statefull.pod` (PostgreSQL, MinIO) |
| `data_stateless` | `data_stateless.pod` (Redis, Gearman) |
| `edge` | `telephony_edge.pod` + HAProxy (sólo hosts en este grupo) |
| `omlapp_web` | `omlapp_web.pod` (Django/uWSGI, Daphne, websockets, nginx, …) |
| `omlapp_workers` | `omlapp_workers.pod` + interaction processor |
| `dialer_workers` | `dialer_workers.pod` |
| `acd` | `acd.pod` |
| `callrec_processor` | `callrec_processor.pod` |
| `omnileads_aio` | Todos los anteriores en un solo host (stack completo) |

**Mapeo desde el modelo anterior (referencia rápida):**

| Antes | Ahora |
|-------|--------|
| `omnileads_data` (todo en un nodo) | Mismo host en `data_statefull` **y** `data_stateless` (o separar en dos hosts) |
| `omnileads_edge` | `edge` |
| `omnileads_web` | `omlapp_web` |
| `omnileads_workers` | Uno o más de: `omlapp_workers`, `dialer_workers`, `callrec_processor` según segregación deseada |
| `omnileads_acd` | `acd` |
| `omnileads_nodes` (cómputo monolítico) | Mismo host en `omlapp_web`, `omlapp_workers`, `dialer_workers`, `acd`, `callrec_processor` (y observabilidad se añade automáticamente con esos pods) |

**Ejemplos canónicos** (ver `instances/test_3.0/inventory.yml`): `tenant_example_A` (2 hosts, cómputo+datos colocalizados), `tenant_example_B`–`E` con distinto grado de split.

*Ejemplo de estructura 3.X:*
```yaml
cluster_instances:
  children:
    mi_cluster:
      hosts:              
        mi_cluster_aio_A:
          tenant_id: mi_cluster_aio_A
          ansible_host: 172.16.101.101
          omni_ip_lan: 172.16.101.101
        mi_cluster_edge:
          tenant_id: mi_cluster_edge
          ansible_host: 172.16.101.103
          omni_ip_lan: 172.16.101.103
...
```

## Paso 4: Ajustes en Base de Datos y S3

1.  **PostgreSQL:** Cambie el valor de `postgres_maintenance_db` de `defaultdb` a `postgres`.
2.  **Variables S3:** Agregue y referencie los endpoints directamente a la URL de su bucket. Agregue las siguientes líneas debajo de su `bucket_url`:
    ```yaml
    bucket_endpoint: "{{ bucket_url }}"
    bucket_endpoint_internal: "{{ bucket_url }}"
    ```

## Paso 5: Telefonía (Asterisk, Kamailio y RTPengine)

1.  **ACD:** Modifique `acd_log_level` para que utilice strings en lugar de enteros. Cambie `1` por `debug` o `info`.
2.  **Kamailio:** Reemplace el guión medio en la variable de certificados por un guión bajo: de `kamailio-certs-location` a `kamailio_certs_location`.
3.  **Reubicación de RTPengine:** Toda la sección de parámetros de RTPengine (ej. `rtpengine_rtp_port_min`, `rtpengine_log_level`, etc.) que antes estaba bajo Asterisk **debe moverse** dentro del nuevo bloque **TELEPHONY EDGE PROXY**, junto a las configuraciones de Kamailio. Se han incorporado las variables `rtpengine_env` y `rtpengine_custom_net_cfg` para manejar NAT dinámicamente.

## Paso 6: Variables Obsoletas (Cleanup)

Elimine las siguientes variables de su archivo, ya que no tienen efecto en la versión 3.X y pueden causar confusión:

*   **Imágenes base (Docker):** `omnileads_img` y `asterisk_img`. Las versiones de las imágenes ahora se controlan desde adentro del deploy tool.
*   **Variables antiguas de migración:** `upgrade_from_oml_1` y `restore_file_timestamp`.
*   **Parámetros específicos de transporte en Asterisk:** `acd_pjsip_transport_dialer`, `acd_pjsip_transport_agent`, `acd_pjsip_transport_trunk`, y `acd_api_listen_ip`.
*   **TTS / Transcripción legacy:** `callrec_transcriptions`.
*   **Dialer:** Elimine la variable `dialer_user`. Adicionalmente, evalúe reducir `dialer_process_campaign_replicas` (por defecto bajó de 10 a 5).
