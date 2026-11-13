# Inventario OMniLeads 3.0 (un directorio, un `inventory.yml`)

En 3.0 **cada instancia tiene su propia carpeta** bajo `ansible/instances/`. Dentro de esa carpeta hay **un solo** `inventory.yml`. Ese archivo declara la asignación de Pods a hosts. Esos Pods son los de [docs/pods.md](docs/pods.md#topología-qué-pods-corre-cada-host): `data_statefull`, `data_stateless`, `edge`, `omlapp_web`, `omlapp_workers`, `dialer_workers`, `acd`, `callrec_processor` y `omnileads_aio`. Un host puede alojar a varios a la vez. `omnileads_aio` corre todos los pods del tenant en una sola máquina. El grupo `edge` despliega el pod `telephony_edge` (HAProxy va en ese host, fuera del pod). El resto de grupos usan el mismo nombre que el pod Quadlet. `observability` no es un grupo: se agrega en todo host que ya corre alguno de esos pods. `enterprise` sale solo si `APP_IMG` termina en `-enterprise`, en el mismo host que `omlapp_web`.

El nombre de la carpeta es el tenant que recibe `deploy.sh`:

```bash
./deploy.sh --action=install --tenant=<carpeta>
# usa instances/<carpeta>/inventory.yml
# y, si existe, instances/<carpeta>/vars.yml
```

No se mantiene un inventario global con varios tenants, ni bloques `ha_instances` / `cluster_instances` que mezclen instancias distintas. Si en 2.X un mismo `inventory.yml` listaba varios clientes, hay que **partirlo**: una carpeta y un `inventory.yml` por instancia.

`instances/` está en `.gitignore`. Los inventarios reales, los certificados y las claves no se versionan en este repositorio.

## Cómo armar la carpeta

```
mkdir ./omldeploytool/ansible/instances
mkdir ./omldeploytool/ansible/instances/tenant_example
```
`inventory.yml` solo nombra los hosts y dice en qué Pod entra en cada host.


```yaml
# instances/<instancia>/inventory.yml
---
all:
  children:
    MiInstancia:
      hosts:
        MiInstancia_Data:
          ansible_host: 192.0.2.11
          omni_ip_lan: 10.10.0.11
        MiInstancia_AIO: 
          ansible_host: 192.0.2.12
          omni_ip_lan: 10.10.0.12
        MiInstancia_Edge:
          ansible_host: 192.0.2.13
          omni_ip_lan: 10.10.0.13
        MiInstancia_ACD:
          ansible_host: 192.0.2.14
          omni_ip_lan: 10.10.0.14     
        MiInstancia_Heavy_Workers:
          ansible_host: 192.0.2.15
          omni_ip_lan: 10.10.0.15    
data_statefull:
  hosts:
    MiInstancia_Data:

data_stateless:
  hosts:
    MiInstancia_Data:

edge:
  hosts:
    MiInstancia_Edge:

omlapp_web:
  hosts:
    MiInstancia_AIO: 

omlapp_workers:
  hosts:
    MiInstancia_AIO: 

dialer_workers:
  hosts:
    MiInstancia_AIO: 

acd:
  hosts:
    MiInstancia_ACD:

callrec_processor:
  hosts:
    MiInstancia_heavy_workers:
```

El grupo `MiInstancia` (bajo `all.children`) junta todos los hosts de **esa** carpeta. Los bloques de abajo son los grupos pod: el mismo nombre de host tiene que aparecer en los dos lados. FQDN, certificados, tuning y secretos no van en este archivo; van en `vars.yml`.

```text
ansible/instances/<instancia>/
├── inventory.yml     # hosts + grupos pod. Uno por carpeta.
├── vars.yml          # configuración de esa instancia (fqdn, tenant_id, tuning, refs a Vault)
├── cert.pem          # solo si certs: custom (el nombre puede ser otro; se declara en vars.yml)
└── key.pem
```

| Archivo | Qué va | Qué no va |
|---------|--------|-----------|
| `inventory.yml` | Nombre de cada host, `ansible_host`, membresía de grupos pod; `omni_ip_lan` es opcional (si falta, se usa `ansible_host`) | Contraseñas, `fqdn`, réplicas, imágenes, parámetros de Postgres/uWSGI/Kamailio |
| `vars.yml` | Overrides de esa instancia. Los secretos se referencian como `{{ vault_* }}` | Topología (qué pod corre en qué máquina) |
| `group_vars/all/tenants_global.yml` | Defaults compartidos por todas las instancias (usuario SSH, `become`, TZ, TLS, dialer, telefonía) | Datos de un solo cliente |
| `group_vars/all/vault.yml` | Secretos cifrados | — |
| `group_vars/all/images.yml` | Tags de imágenes | — |

`deploy.sh` carga `vars.yml` con `--extra-vars`, así que sus valores pisan `tenants_global.yml`. Si el archivo no existe, el deploy sigue con los defaults globales.

Crear una instancia nueva, desde `ansible/`:

```bash
mkdir -p instances/<instancia>
# copiar el inventory.yml de la carpeta en instances/ cuyo layout más se parezca
# y vaciar hosts / IPs. Completar vars.yml aparte.
```

El grupo bajo `all.children` es **el nombre de esa instancia** (un solo grupo, con todos sus hosts). No uses `aio_instances` ni `cluster_instances` para agrupar varias instancias en el mismo archivo: Ansible toma el grupo que no es de pod como el grupo del tenant y, en cluster, cruza ese grupo con los grupos pod para resolver peers.

Los nombres de host de la sección de grupos pod tienen que coincidir con las claves declaradas en `all.children`.

### AIO — un solo host

Patrón de `instances/test_local` y `instances/Skycell_Carvacell`. El host va solo en `omnileads_aio`: ese grupo despliega el stack completo.

```yaml
# instances/<instancia>/inventory.yml
---
all:
  children:
    MiInstancia:
      hosts:
        MiInstancia:
          ansible_host: 192.0.2.10
          omni_ip_lan: 192.0.2.10

omnileads_aio:
  hosts:
    MiInstancia:
```

Si SSH y la LAN usan la misma IPv4, podés omitir `omni_ip_lan`: `topology_normalize` la toma de `ansible_host`.

`ansible_user`, `ansible_become` y `ansible_become_method` ya salen de `tenants_global.yml` (`ansible_user: "{{ vault_ansible_user }}"`, `sudo` a `root`). No hace falta repetirlos. Si esta instancia usa otro usuario admin, declaralo en `vars.yml`, nunca `root` ni `omnileads`.

### Tres hosts: datos + cómputo + edge


```yaml
# instances/<instancia>/inventory.yml
---
all:
  children:
    MiInstancia:
      hosts:
        MiInstancia_Data:
          ansible_host: 192.0.2.11
          omni_ip_lan: 10.10.0.11
        MiInstancia_AIO: 
          ansible_host: 192.0.2.12
          omni_ip_lan: 10.10.0.12
        MiInstancia_Edge:
          ansible_host: 192.0.2.13
          omni_ip_lan: 10.10.0.13

data_statefull:
  hosts:
    MiInstancia_Data:

data_stateless:
  hosts:
    MiInstancia_Data:

edge:
  hosts:
    MiInstancia_Edge:

omlapp_web:
  hosts:
    MiInstancia_AIO: 

omlapp_workers:
  hosts:
    MiInstancia_AIO: 

dialer_workers:
  hosts:
    MiInstancia_AIO: 

acd:
  hosts:
    MiInstancia_AIO: 

callrec_processor:
  hosts:
    MiInstancia_AIO: 
```

En este ejemplo los Pods data (MiInstancia_Data) y edge (MiInstancia_Edge) son desplegados sobre hosts aparte del resto de los pods que comparten mismo host (MiInstancia_App).
OMniLeads se reparte en tres Host linux.

### Cluster con pods separados

```yaml
# instances/<instancia>/inventory.yml
---
all:
  children:
    MiInstancia:
      hosts:
        MiInstancia_Data:
          ansible_host: 192.0.2.11
          omni_ip_lan: 10.10.0.11
        MiInstancia_AIO: 
          ansible_host: 192.0.2.12
          omni_ip_lan: 10.10.0.12
        MiInstancia_Edge:
          ansible_host: 192.0.2.13
          omni_ip_lan: 10.10.0.13
        MiInstancia_ACD:
          ansible_host: 192.0.2.14
          omni_ip_lan: 10.10.0.14     
        MiInstancia_Heavy_Workers:
          ansible_host: 192.0.2.15
          omni_ip_lan: 10.10.0.15    
data_statefull:
  hosts:
    MiInstancia_Data:

data_stateless:
  hosts:
    MiInstancia_Data:

edge:
  hosts:
    MiInstancia_Edge:

omlapp_web:
  hosts:
    MiInstancia_AIO: 

omlapp_workers:
  hosts:
    MiInstancia_AIO: 

dialer_workers:
  hosts:
    MiInstancia_AIO: 

acd:
  hosts:
    MiInstancia_ACD:

callrec_processor:
  hosts:
    MiInstancia_heavy_workers:
```

En este ejemplo los Pods data (MiInstancia_Data), edge (MiInstancia_Edge), ACD (MiInstancia_ACD) y Heavy_Workers (MiInstancia_Heavy_Workers) son desplegados sobre hosts aparte del resto de los pods que comparten mismo host (MiInstancia_App).
OMniLeads se reparte en cinco Host linux.

Se podria ir dividiendo hasta llegar a un Pod por host:

| Grupo inventario | Pod Quadlet |
|------------------|-------------|
| `omnileads_aio` | Todos los pods de abajo, en un solo host |
| `data_statefull` | `data_statefull` |
| `data_stateless` | `data_stateless` |
| `edge` | `telephony_edge` (HAProxy en el mismo host, fuera del pod) |
| `omlapp_web` | `omlapp_web` (y `enterprise` si `APP_IMG` termina en `-enterprise`) |
| `omlapp_workers` | `omlapp_workers` |
| `dialer_workers` | `dialer_workers` |
| `acd` | `acd` |
| `callrec_processor` | `callrec_processor` |

`observability` no se declara: se agrega en cada host que ya corre alguno de esos pods. El detalle de contenedores, red y puertos está en [docs/pods.md](docs/pods.md).

### `vars.yml` de la instancia

Lo que en 2.X estaba mezclado en el inventario (FQDN, bucket, tuning, certificados) va acá. Ejemplo alineado con las carpetas de `instances/`:

```yaml
---
tenant_id: MiInstancia
fqdn: omnileads.midominio.com
TZ: America/Argentina/Cordoba

certs: custom
ssl_cert_file_name: cert.pem
ssl_key_file_name: key.pem
# django_allowed_hosts_extra: "alias.cliente.com,otro.dominio.com"

postgres_password: "{{ vault_mi_instancia_postgres_password }}"
bucket_url: "{{ vault_mi_instancia_bucket_url }}"
bucket_endpoint: "{{ bucket_url }}"
bucket_endpoint_internal: "{{ bucket_url }}"
bucket_name: "{{ vault_mi_instancia_bucket_name }}"
bucket_access_key: "{{ vault_mi_instancia_bucket_access_key }}"
bucket_secret_key: "{{ vault_mi_instancia_bucket_secret_key }}"

itsp_nodes: "{{ vault_mi_instancia_itsp_nodes }}"
kamailio_webrtc_iface: eth1

dialer_caps: 10
dialer_process_campaign_replicas: 5
uwsgi_processes: 4
uwsgi_threads: 2
```

Si la instancia usa el MinIO que despliega OMniLeads, no declares `bucket_url`: `topology_normalize` arma el endpoint desde el host de `data_statefull`.

Certificados con `certs: custom`:

```bash
cp /ruta/cert.pem instances/<instancia>/cert.pem
cp /ruta/key.pem  instances/<instancia>/key.pem
chmod 600 instances/<instancia>/key.pem
```

Los nombres tienen que coincidir con `ssl_cert_file_name` y `ssl_key_file_name`.

Secretos que antes iban en texto plano (`postgres_password`, claves S3, `django_secret_key`, `kamailio_webrtc_auth_eph_key`, AMI, dialer, API keys) viven en `group_vars/all/vault.yml` y se referencian como `{{ vault_* }}`. Los defaults globales ya están cableados en `tenants_global.yml`; en `vars.yml` solo se pisa lo que es propio de la instancia (password de Postgres, bucket, ITSP, FQDN).

## Qué cambia respecto de un inventario 2.X

1. **Un archivo por instancia.** Separá cada tenant o cluster del inventario viejo en `instances/<instancia>/inventory.yml`.
2. **Sacá la configuración del inventario** y pasala a `vars.yml` (FQDN, TZ, certificados, réplicas, bucket, passwords vía Vault).
3. **Reemplazá los grupos viejos** por grupos pod. Estos ya no despliegan nada: `omnileads_data`, `omnileads_edge`, `omnileads_web`, `omnileads_workers`, `omnileads_acd`, `omnileads_nodes`, `omnileads_voice`, `omnileads_app`, `omnileads_dialer`, `ha_instances`.

| Antes | Ahora |
|-------|--------|
| `omnileads_data` en un nodo | El mismo host en `data_statefull` y `data_stateless` |
| `omnileads_voice` / `omnileads_edge` | `edge` |
| `omnileads_app` | `omlapp_web` |
| `omnileads_dialer` / `omnileads_workers` | `omlapp_workers`, `dialer_workers` y/o `callrec_processor` |
| `omnileads_acd` | `acd` |
| `omnileads_nodes` (cómputo junto) | El mismo host en `omlapp_web`, `omlapp_workers`, `dialer_workers`, `acd` y `callrec_processor` |
| AIO de un solo host | Solo `omnileads_aio` |

4. **Usuario SSH.** `ansible_user: root` sale del inventario. El default 3.0 es el admin de Vault con `sudo`. El usuario de servicio en el host sigue siendo `omnileads` y lo crea el rol de install.
5. **Borrá variables que 3.0 no usa:** `infra_env`, `omnileads_img`, `asterisk_img` (las imágenes están en `group_vars/all/images.yml`), `upgrade_from_oml_1`, `restore_file_timestamp`, `dialer_user`, `acd_pjsip_transport_dialer`, `acd_pjsip_transport_agent`, `acd_pjsip_transport_trunk`, `acd_api_listen_ip`, `callrec_transcriptions`.
6. **No hace falta reescribir** en el inventario lo que `tenants_global.yml` ya trae: `postgres_maintenance_db: postgres`, `acd_log_level: info`, `kamailio_certs_location`, bloque de RTPengine junto a Kamailio. Si una instancia necesita otro valor, el override va en su `vars.yml`.

Para apuntar a Postgres, S3 o RTPengine externos, declaralo en `vars.yml` (`postgres_host`, `bucket_url`, `rtpengine_host`, `kamailio_pstn_host`). Si no están definidos, el deploy usa el componente que corre en los grupos pod.

Comprobación, con el venv y la password del Vault listos:

```bash
ansible -i instances/<instancia>/inventory.yml all --list-hosts
./deploy.sh --action=install --tenant=<instancia>
```

## **Upgrade desde 2.X.** 

Hay dos maneras de hacerlo:

1) Upgradear dentro del mismo host 2.X. En `vars.yml` de esa instancia: `upgrade_from_2X: true`. El default global es `false`.
2) Desplegar en un nuevo host omnileads 3.0 usando un restore  de la base de datos. Se utiliza ```backup_filename:```.
