# DigitalOcean — esqueleto Terraform

Crea y destruye las droplets del tenant. No instala OMniLeads: eso sigue en Ansible, cuando SSH ya responde.

| Capa | Dónde |
| --- | --- |
| Imagen Debian 13 | [`packer/digitalocean/`](../../packer/digitalocean/) |
| Droplets, IP públicas, firewall | este directorio |
| Aplicación | `ansible/deploy.sh` |

## Nodos y demás recursos del Cloud Provider

La lista no está en este directorio. Cada tenant la declara en `ansible/instances/<tenant>/terraform.tfvars`, siendo coincidente con los host declarados a nivel de inventory.yml, cada VM allí declarada tiene una relación 1 a 1 con los hosts del inventario. `keep = true` no se destruye cuando `compute_enabled = false`, se maneja el flag "compute_enabled" para diferenciar  los que es computo (PODs: acd, omlapp_server, omlapp_workers, dialer) del resto (PODs: telephony_edge, data_stateless & data_stateful)

## Qué no hace un apply de este directorio

No adopta las droplets que ya están corriendo. Crea droplets nuevas dentro de la VPC nombrada en `vpc_name` y no crea ni destruye esa VPC. `terraform destroy` del stack borra todo. Para borrar en las noches las instancias de cómputo usar `compute_enabled = false`, no `destroy`.

DigitalOcean asigna la IP pública y la privada al crear la droplet. Si se destruye, las dos cambian. Después de cada recreación hay que correr [`sync_inventory.py`](sync_inventory.py) y volver a correr Ansible, incluido `do_edge` (HAProxy y Kamailio arman los backends con la IP privada).

El firewall abre SSH desde `ssh_allowed_cidrs`, todo el tráfico dentro de la VPC, y en el edge 80/443, RTP `20000-30000` y SIP udp/5060 desde `sip_allowed_cidrs`. También admite TCP 5061 desde `74.125.88.128/25` para el retorno SIP TLS de Google Telephony Platform (voicebot).

Los adjuntos que viven solo en el disco de `do_omlapp_*` se pierden al destruir esas droplets. Los estáticos salen de la imagen con `collectstatic`.

## Uso

Al dar de alta un tenant, lo primero es apuntar este directorio al Space de ese tenant. El backend está en `versions.tf`; el bucket no: cada tenant lo declara en `ansible/instances/<tenant>/backend.hcl` (copiado de `backend.hcl.example`). Las credenciales del Space van en el entorno, no en ese archivo.

```bash
cd terraform/digitalocean
export DIGITALOCEAN_TOKEN=...
export AWS_ACCESS_KEY_ID=...
export AWS_SECRET_ACCESS_KEY=...

terraform init -backend-config=../../ansible/instances/<tenant>/backend.hcl
terraform plan -var-file=../../ansible/instances/<tenant>/terraform.tfvars
terraform apply -var-file=../../ansible/instances/<tenant>/terraform.tfvars
```

Si ya hay un state local y hay que subirlo a ese Space, el mismo `init` lleva `-migrate-state`. Para cambiar de tenant hay que repetir `terraform init -reconfigure` con el `backend.hcl` del otro. Cada Space guarda su propio `terraform/digitalocean/terraform.tfstate`. Un `plan` contra el backend del tenant equivocado compara con los recursos de ese otro state.

De noche, con el spool de grabaciones de los ACD ya vacío:

```bash
terraform apply -var-file=../../ansible/instances/<tenant>/terraform.tfvars -var="compute_enabled=false"
```

De mañana, el mismo comando sin ese `-var`. Después, con el `init` de este directorio apuntando al Space de ese tenant:

```bash
./sync_inventory.py <tenant>
```

El script lee `terraform output -json ansible_hosts` y escribe en `ansible/instances/<tenant>/inventory.yml` la IP pública en `ansible_host` y la privada de la VPC en `omni_ip_lan`. Se puede invocar desde cualquier directorio como `terraform/digitalocean/sync_inventory.py <tenant>`. No crea hosts ni grupos: si un nombre del output no está en el inventario, termina con error. También falla si el output está vacío (`compute_enabled=false` o el state es de otro tenant).

Hay que correr Ansible, incluido `do_edge`. El install conviene limitarlo a los grupos de `ansible_limit_when_compute_returns` más `edge`. `deploy.sh` no acepta `--limit`; un `install` del tenant entero también borra los host que alojan los Pods Edge y Data.
