# Vultr — Terraform

Crea y destruye las instancias del tenant. No instala OMniLeads: eso sigue en Ansible, cuando SSH ya responde como `omladmin`.

| Capa | Donde |
| --- | --- |
| Imagen Debian 13 | [`packer/vultr/`](../../packer/vultr/) |
| Instancias, firewall | este directorio |
| Aplicacion | `ansible/deploy.sh` |

## Nodos

La lista no esta en este directorio. Cada tenant la declara en `ansible/instances/<tenant>/terraform.tfvars`, con la misma forma que su inventario: una instancia y los grupos Ansible que corre (`roles`). `size` es el plan de Vultr (`vc2-1c-2gb`, `vc2-2c-4gb`). `keep = true` no se destruye cuando `compute_enabled = false`.

El hostname en Vultr pasa a minusculas y guiones (`do_edge` queda `do-edge`). El inventario sigue con el nombre original.

## Firewall

Los CIDR no van en este directorio. `ssh_allowed_cidrs` y `edge_inbound` se leen del tfvars del tenant, y `*.tfvars` esta en `.gitignore`.

Una instancia acepta un solo firewall group. Las que tienen el rol `edge` reciben el group de edge (SSH mas `edge_inbound`). El resto recibe solo SSH. Vultr filtra la entrada publica. El trafico de la VPC y la salida no pasan por el firewall.

`edge_inbound` vacio deja el edge sin 80, 443, SIP ni RTP publicos. Un rango se escribe `20000-30000`; la API lo recibe como `20000:30000`.

Para Google Telephony Platform (voicebot), agregar entrada TCP `5061` desde `74.125.88.128/25` (señalización SIP TLS de vuelta a Kamailio). La salida TCP/UDP ya no se filtra en Vultr. El audio de Google va a `74.125.39.0/24` puertos 16384–32767.

## Que no hace un apply de este directorio

No adopta instancias que ya estan corriendo. Crea instancias nuevas dentro de la VPC cuya `description` es `vpc_description`, y no crea ni destruye esa VPC. La description tiene que identificar una sola VPC, en la misma region que `region`.

`terraform destroy` borra tambien las instancias con `keep = true`. Para la noche usar `compute_enabled = false`, no `destroy`.

Vultr asigna la IP publica (`main_ip`) y la privada (`internal_ip`) al crear la instancia. Si se destruye, las dos cambian. Despues de cada recreacion hay que correr `sync_inventory.py` y Ansible, incluido el edge.

No hay IP reservada. cloud-init corre solo en el primer boot (`user_data` esta en `ignore_changes`). Un cambio de `cloud_init_vultr.yml` no entra en una instancia ya creada: hay que reemplazarla.

## Uso

La IP de esta maquina tiene que estar en la ACL de la API key.

```bash
cd terraform/vultr
export VULTR_API_KEY=...
export AWS_ACCESS_KEY_ID=...
export AWS_SECRET_ACCESS_KEY=...

terraform init -backend-config=../../ansible/instances/<tenant>/backend.hcl
terraform plan -var-file=../../ansible/instances/<tenant>/terraform.tfvars
terraform apply -var-file=../../ansible/instances/<tenant>/terraform.tfvars
```

El `backend.hcl` es el del Space de ese tenant (parti de `backend.hcl.example`). Puede ser el mismo archivo que usa `terraform/digitalocean`: la key del state es `terraform/vultr/terraform.tfstate`, distinta de la de DigitalOcean. `VULTR_API_KEY` habla con la API de Vultr. `AWS_ACCESS_KEY_ID` y `AWS_SECRET_ACCESS_KEY` son las keys del Space, las mismas que `vault_digital_ocean_bucket_access_key` y `vault_digital_ocean_bucket_secret_key`.

Para cambiar de tenant: `terraform init -reconfigure` con el `backend.hcl` del otro. Un plan contra el backend equivocado compara con las instancias de ese otro state.

De noche, con el spool de grabaciones de los ACD ya vacio:

```bash
terraform apply -var-file=../../ansible/instances/<tenant>/terraform.tfvars -var="compute_enabled=false"
```

De manana, el mismo comando sin ese `-var`. Despues:

```bash
./sync_inventory.py <tenant>
```

`terraform output ansible_hosts` muestra la IP publica y la privada. `ansible_limit_when_compute_returns` lista los grupos de las instancias con `keep = false`. El cron tiene que correr en una maquina que no se destruya.

Para instalar un snapshot de Packer en lugar de Debian 13 de catalogo, agregar `snapshot_id` al tfvars (misma region que la VPC) y dejar de usar `os_name`.
