#### This project is part of OMniLeads

![Diagrama deploy tool](./png/omnileads_logo_1.png)

#### 100% Open-Source Contact Center Software
#### [Community Forum](https://forum.omnileads.net/)

---

# Index

* [Bash + Ansible](#bash-ansible)
* [Ansible + Inventory](#ansible-inventory)
* [Bash Script deploy.sh](#bash-script-deploy)
* [Subscriber tracking](#subscriber-traking)
* [Deploy all in one (AIO) instance](#aio-deploy)
* [TLS Certs provisioning](#tls-cert-provisioning)
* [Security](#security)
* [OMniLeads Podman containers](#podman-systemd)
* [Deploy an upgrade from CentOS7](#upgrade_from_centos7)
* [Asterisk Dialplan & other customizations](#asterisk_customizations)
* [Container image & tag customizations](#components_img)
* [Deploy OMniLeads Enterprise](#oml_enterprise)
* [Deploy an upgrade](#upgrades)
* [Deploy a rollback](#rollback)
* [Deploy a backup](#backups)
* [Deploy a restore](#restore)
* [Observability](#observability)
* [Scalability](#scalability)
* [Deploy Cluster all in three (AIT) instance](#ait-deploy)
* [Deploy Onpremise Cluster HA](#cluster-ha-deploy)
* [Cluster HA recovery tools](#cluster_ha_recovery)

# OMniLeads automation your subscribers deploys with Ansible

```
git clone https://gitlab.com/omnileads/omldeploytool.git
cd omldeploytool/ansible
```

In this section, we will find a tool manager for OMniLeads that will allow us to carry out deployments:

* New instances
* Upgrades & rollbacks
* Backup & restore

It is possible to manage hundreds of OMniLeads instances with Ansible inventories.

![Diagrama deploy tool](./png/deploy-tool-ansible-deploy-instances-multiples.png)

Then, for each running instance, a collection of components invoked as systemd services implement OMniLeads functionalities on the Linux instance (or set of instances).

Each OMniLeads instance involves the following collection of components that are run on a container. 
It is possible to group these containers on a single Linux instance or cluster them horizontally in a configuration.

>  Note: If working on a VPS with a public IP address, it is a mandatory requirement that it also has a network interface with the ability to associate a private IP address.

![Diagrama component Pods](./png/oml-pods.png)

## Bash + Ansible 📋 <a name="bash-ansible"></a>

An instance of OMniLeads is launched on a Linux server (using Systemd & Podman) by running a bash script (deploy.sh) along with its input parameters and a set of Ansible files (Playbooks + Templates) that are invoked by the script.

## Bash Script deploy.sh 📄 <a name="bash-script-deploy"></a>

This executable script triggers the deploy actions. It is responsible for receiving the action parameters to execute and the tenant on which to deploy the action.

The script searches for the inventory file of the tenant (or group of them) on which it needs to operate and then launches the root Ansible playbook (matrix.yml) through ansible-playbook with the corresponding tags to respond to the request made. 

```
./deploy.sh --help
```

To run an installation, upgrades, backup or restore deployment, two parameters must be called.

* **--action=**
* **--tenant=**

for example: 

```
./deploy.sh --action=install --tenant=tenants_folder_name
```

## Ansible 🔧 <a name="ansible-inventory"></a>

Ansible allows you to run a number of tasks on a set of hosts specified in your inventory file. Depending on the structure and variables of this file, OMniLeads instances based on podman containers can be launched .

This tool is capable of deploying OMniLeads in three layouts: 

* **OML All in One with Podman & Systemd:**
![Diagrama deploy tool](./png/deploy-tool-tenant-aio.png)

* **OML  Cluster with Podman & Systemd:**
![Diagrama deploy tool](./png/deploy-tool-tenant-ait.png)

* **OML  Cluster HA with Podman & Systemd:**
![Diagrama deploy tool](./png/deploy-tool-tenant-ha.png)

The following is the generic version of inventory.yml file available in this repository.

In the first section of the file you can list the different hosts grouped by tenant and by type of deployment (All in one or Cluster).

AIO instances:

![inventory deploy example header](./png/inventory_aio_section.png)

Cluster instances:

![inventory deploy 2 section](./png/inventory_cluster_section.png)

Cluster HA instances:

![inventory deploy 3 section](./png/inventory_cluster_ha_section.png)

In the second section of the file you can parameterize the runtime variables. By default it affects ALL declared instances, unless the same variable is declared within the host or group specific variables section.

Finally, we have the section where the hosts should be grouped according arq. 
On one side we have the omnileads_aio family, here below you must list the AIO instances you want to deploy.
Then we have *omnileads_data*, *omnileads_voice*, *omnileads_app* where the instances that form clusters should be grouped. 


```
##############################################################################################################
## -- In this section the hosts are grouped based on the type of deployment (AIO, Cluster & Cluster HA).  -- #
## -- here you can control which host the action deployed by the deploy.sh script will be applied to      -- #
## -- The Ansible playbooks are applied on the hosts below declared and classified according to the       -- #
## -- architecture of the instance on which they are deployed.                                            -- #
##############################################################################################################

omnileads_aio:
  hosts:
    #tenant_example_1:
    #tenant_example_2:
    #tenant_example_3:
    #tenant_example_4:
    #tenant_example_5:

################ Active/Pasive HA cluster ######################
################ Active/Pasive HA cluster ######################

    #tenant_example_7_HA_1:
    #tenant_example_7_HA_2:

##################### 3 Host cluster ###########################    
##################### 3 Host cluster ###########################    

omnileads_data:
  hosts:
    #tenant_example_5_data:  
    #tenant_example_6_data:  
    
omnileads_voice:
  hosts:
    #tenant_example_5_voice:
    #tenant_example_6_voice:

omnileads_app:
  hosts:
    #tenant_example_5_app:
    #tenant_example_6_app:
```

# Inventory file :office: <a name="subscriber-traking"></a>

In order to manage multiple instances (or group of them) from this deployment tool, you must create
a folder called **instances** at the root of this directory. The reserved name for this folder is
**instances** since said string is inside the .gitignore of the repository.

```
mkdir instances
```

Then, for each *instance* to be managed, a sub-folder must be created within instances.
For example:

```
mkdir instances/cloud_oml
mkdir instances/onpremise_oml
mkdir instances/company_A_omls
```

Once the tenant folder is generated, there you will need to place a copy of the *inventory.yml* file available
in the root of this repository, in order to customize and tack inside the private GIT repository.

```
cp inventory.yml instances/cloud_oml
cp inventory.yml instances/onpremise_oml
cp inventory.yml instances/company_A_omls
```

Then, once we have adjusted the inventory.yml file inside the tenant's folder, we can trigger its deployment.

```
./deploy.sh --action=install --tenant=cloud_oml
```

# Install on Linux instance 🚀 <a name="aio-deploy"></a>

You must have a generic Linux instance (Redhat or Debian based) with with internet access and your public SSH key available, as Ansible needs to establish an SSH connection using the public key.
The important thing is that the selected distribution has a version of Podman (3.0.0 or higher) available in its repositories. Something that we know Debian, Ubuntu, Rocky, or Alma Linux have.

![Diagrama deploy](./png/deploy-tool-tenant-components-aio.png)

Then you should work on the inventory.yml tenant file.

```
###############################################################################################################
##############################   The complete list of host  ################################################### 
###############################################################################################################
all:
  children:
    # -----------------------------------------
    # -----------------------------------------
    aio_instances:
      hosts:
        algarrobo:
          tenant_id: algarrobo
          ansible_host: 190.19.150.18
          omni_ip_lan: 172.16.101.44
          infra_env: cloud
          fqdn: tenant_name.omnileads.net
          certs: certbot
```

The ***infra_env*** variable can be initialized as "lan", "cloud" or "nat", depending on whether the instance will be accessible via WAN access (IPADDR or FQDN), LAN access (IP or FQDN) or behind a NAT (IPADDRR or FQDN).

The ***nat_ip_addr*** variable. In the case of selecting infra_env: nat, it's optional to uncomment and indicate the address that will perform the NAT (nat_ip_addr: X.X.X.X); otherwise, auto-discovery of the NAT IP address will be performed.

The *bucket_url* and *postgres_host* parameters must be commented out, so that both (PostgreSQL and Object Storage MinIO) are deployed within the AIO instance.

Then in the vars section, we have all the parameters that omnileads expects to work. These variables affect all the hosts that are going to be managed from this inventory.yml. 


```
    # ------------------------------------------------------------------------------------------------ #
    # ------------------------------ Generic OMniLeads runtime variables ----------------------------- #
    # ------------------------------------------------------------------------------------------------ #

    # --- Asterisk & RTPengine scenary for SIP & RTP
    # --- "cloud" instance (access through public IP)
    # --- "lan" instance (access through private IP)
    # --- "nat" instance (access through Public NAT IP)    
    # --- or "all" in order to access through all NICs
    infra_env: cloud
    #nat_ip_addr: X.X.X.X
    # --- If you have an DNS FQDN resolution, you must to uncomment and set this param
    # --- otherwise leave commented to work invoking through an IP address
    #fqdn: fts.sefirot.cloud
    # --- If you want to work with Dialer, then you must install Wombat Dialer on a separate host 
    # --- and indicate the IP address or FQDN of that host here (uncomment and set this param):
    # --- time zone (for example: America/Argentina/Cordoba)
    TZ: America/Argentina/Cordoba
    # --- TLS/SSL Certs configuration (selfsigned, custom or certbot letsencrypt)
    # --- https://gitlab.com/omnileads/omldeploytool/-/blob/develop/ansible/README.md?ref_type=heads#tls-cert-provisioning  
    certs: selfsigned
    # --- PostgreSQL    
    postgres_port: 5432
    postgres_user: omnileads
    postgres_password: HJGKJHGDSAKJHK7856765DASDAS675765JHGJHSAjjhgjhaaa
    postgres_database: omnileads
    ....
    ....
    ....
```

Finally in the last section of the file, we must make sure that our tenant is listed in the omnileads_aio hosts group.

```
#############################################################################################################
# -- In this section the hosts are grouped based on the type of deployment (AIO, Cluster & Cluster HA).     #
#############################################################################################################

omnileads_aio:
  hosts:
    algarrobo:
    #tenant_example_3:
    #tenant_example_4:
    #tenant_example_2:

omnileads_data:
  hosts:
    #tenant_example_5_data:
    #tenant_example_6_data:
    
omnileads_voice:
  hosts:
    #tenant_example_5_voice:
    #tenant_example_6_voice:

omnileads_app:
  hosts:
    #tenant_example_5_app:
    #tenant_example_6_app:
```

Let's run the bash scrip:

```
./deploy.sh --action=install --tenant=tenant_name_folder
```

We can log in:

```
https://tenant_name.omnileads.net
user *admin*
password *admin*. 
```


# TLS/SSL certs provisioning :closed_lock_with_key: <a name="tls-cert-provisioning"></a>

From the inventory variable *certs* you can indicate what to do with the SSL certificates.
The possible options are:

* **selfsigned**: which will display the self-signed certificates (not recommended for production).
* **certbot**: deploy an instance with automatically generated Let's Encrypt SSL certificates.

When working with self-generated certificates in the deployment using Certbot, we must ensure that our instance has DNS resolution based on our FQDN. Additionally, we must ensure that our port 80 is accessible from the certificate authority and set a valid email box in order to recieve TLS renew notifications from Let's & crypt.

```
certs: certbot
fqdn: omlinstance.domain.com
notification_email: your_email@domain.com
```

* **custom**: if the idea is to implement your own certificates. Then you must place them inside instances/tenant_name_folder/ with the names: *cert.pem* for and *key.pem*


Custom certificates should be placed within the folder where we store the inventory file used to manage the instances, i.e., *instances/tenants_folder*.

If we are going to use *certs: custom*, then the certificate and key files should be named *cert.pem* and *key.pem*. Although we can also use different names, in that case, instead of using *certs: custom*, we must change it to:

```
aio_instances:
      hosts:
        algarrobo:
          tenant_id: algarrobo
          ansible_host: 190.19.150.18
          omni_ip_lan: 172.16.101.44
          infra_env: cloud
          fqdn: tenant_name.omnileads.net
          cert_file_name: cert_custom_filename.pem
          key_file_name: key_custom_filename.pem 
```

```
./deploy.sh --action=install --tenant=cloud_oml
```

# Security 🛡️ <a name="security"></a>

OMniLeads is an application that combines Web (https), WebRTC (wss & sRTP) and VoIP (SIP & RTP) technologies. This implies a certain complexity and 
when deploying it in production under an Internet exposure scenario. 

On the Web side of the things the ideal is to implement a Reverse Proxy or Load Balancer ahead of OMnileads, i.e. exposed to the Internet (TCP 443) 
and that it forwards the requests to the Nginx of the OMniLeads stack. On the VoIP side, when connecting to the PSTN via VoIP it is ideal to 
operate behind an SBC (Session Border Controller) exposed to the Internet.

However, we can intelligently use the **Cloud Firewall** technology when operating over VPS exposed to the Internet.

![Diagrama security](./png/security.png)

Below are the Firewall rules to be applied on All In One instance:

* 443/tcp Nginx: This is where Web/WebRTC requests to Nginx are processed. Port 443 can be opened to the entire Internet.

* 20000/30000 UDP WebRTC sRTP RTPengine: this port range can be opened to the entire Internet.

* 5060/UDP Asterisk: This is where SIP requests for incoming calls from the ITSP(s) are processed. This port must be opened by restricting by origin on the IP(s) of the PSTN SIP termination provider(s).

* 40000/50000 UDP: VoIP RTP Asterisk: this port range can be opened to the entire Internet.

* 9090/tcp Prometheus metrics: This is where the connections coming from the monitoring center. This port can be opened by restricting by origin in the IP of the monitoring center.


## Systemd & Podman 🔧 <a name="podman-systemd"></a>

Then, once OMnileads is deployed on the corresponding instance/s, each container on which a component works
can be managed as a systemd service.

```
systemctl start component
systemctl restart component
systemctl stop component
```

Behind every action triggered by the systemctl command, there is actually a Podman container that is launched, stopped, or restarted. This container is the result of the image invoked along with the environment variables.

For example, if we look at the systemd file of the Nginx component.

/etc/systemd/system/nginx.service looks like:

```
[Unit]
Description=Podman container-oml-nginx-server.service
Documentation=man:podman-generate-systemd(1)
Wants=network-online.target
After=network-online.target
RequiresMountsFor=%t/containers

[Service]
Environment=PODMAN_SYSTEMD_UNIT=%n
Restart=on-failure
TimeoutStopSec=70
ExecStartPre=/bin/rm -f %t/%n.ctr-id
ExecStart=/usr/bin/podman run \
  --cidfile=%t/%n.ctr-id \
  --cgroups=no-conmon \
  --sdnotify=conmon \
  --replace \
  --detach \
  --network=host \
  --env-file=/etc/default/nginx.env \
  --name=oml-nginx-server \
  --volume=/etc/omnileads/certs:/etc/omnileads/certs \
  --volume=django_static:/opt/omnileads/static \
  --volume=django_callrec_zip:/opt/omnileads/asterisk/var/spool/asterisk/monitor \
  --rm  \
  docker.io/omnileads/nginx:230215.01
ExecStop=/usr/bin/podman stop --ignore --cidfile=%t/%n.ctr-id
ExecStopPost=/usr/bin/podman rm -f --ignore --cidfile=%t/%n.ctr-id
Type=notify
NotifyAccess=all

[Install]
WantedBy=default.target
```

/etc/default/nginx.env looks like:

```
DJANGO_HOSTNAME=172.16.101.221
DAPHNE_HOSTNAME=172.16.101.221

KAMAILIO_HOSTNAME=127.0.0.1
WEBSOCKETS_HOSTNAME=172.16.101.221
ENV=prodenv

S3_ENDPOINT=http://172.16.101.221:9000
```

This is the standard for all components.


# Upgrade from CentOS-7 OMniLeads instance :arrows_counterclockwise: <a name="upgrade_from_centos7"></a>


You must deploy the new **OMniLeads Community** instance making sure that the inventory.yml variables listed below should be the same as their 
counterparts in the CentOS 7 instance from which you want to migrate. below should be the same as their counterparts in the CentOS 7 instance from which you want to migrate.

* ami_user
* ami_password
* postgres_password
* postgres_database
* postgres_user
* dialer_user
* dialer_password

We must consider that the version of the Postgres image to be deployed with OMniLeads 2.X should be "omnileads/postgres:230624.01". Therefore, you will need to temporarily change the variable groupall/all inherent to Postgres, as follows:

```
#################### containers img tag  ################################

#postgres_img: docker.io/postgres:14.9-bullseye
postgres_img: docker.io/omnileads/postgres:230624.01
```

On the OMniLeads 1.X CentOS-7 instance run the following commands to generate a postgres backup on the one hand 
and then upload to the Bucket Object Storage of the new OMniLeads version the call recordings, telephony audios and the Postgres DB backup.

```
export NOMBRE_BACKUP=some_file_name
pg_dump -h ${PGHOST} -p ${PGPORT} -U ${PGUSER} -Fc -b -v -f /tmp/psql-backup-${NOMBRE_BACKUP}.sql -d ${PGDATABASE} --no-acl
export AWS_ACCESS_KEY_ID=$your_new_instance_bucket_key
export AWS_SECRET_ACCESS_KEY=$your_new_instance_bucket_secret_key
export S3_BUCKET_NAME=$your_new_instance_bucket_name
```

If you are going to use the object storage self-hosted by OMnileads in an AIO instance:
```
export S3_ENDPOINT=http://$YOUR_OML_AIO_IP:9000 
```

If you are going to use the object storage self-hosted by OMnileads in an AIT cluster instance:
```
export S3_ENDPOINT=http://$YOUR_OML_DATA_IP:9000 
```

If you are going to use an external object storage service:
```
export S3_ENDPOINT=https://$object_storage_url
```

Finally, all backups are uploaded to the bucklet of the new OMniLeads instance:
```
aws --endpoint ${S3_ENDPOINT} s3 sync /opt/omnileads/media_root s3://${S3_BUCKET_NAME}/media_root
aws --endpoint ${S3_ENDPOINT} s3 sync /opt/omnileads/asterisk/var/spool/asterisk/monitor/ s3://${S3_BUCKET_NAME}
aws --endpoint ${S3_ENDPOINT} s3 cp /tmp/pgsql-backup-$NOMBRE_BACKUP.sql  s3://${S3_BUCKET_NAME}/backup/
```

Given that all the necessary components for restoring the service on the new infrastructure are available in the same Bucket,
you can proceed with deploying the restoration process.

At the end of the file there is the variable *restore_file_timestamp* which must contain the name used in the previous step to refer to the backups.
previous step to refer to the backups taken.

```
aio_instances:
      hosts:
        algarrobo:
          tenant_id: algarrobo
          ansible_host: 190.19.150.18
          omni_ip_lan: 172.16.101.44
          infra_env: cloud
          fqdn: tenant_name.omnileads.net
          cert_file_name: cert_custom_filename.pem
          key_file_name: key_custom_filename.pem 
          restore_file_timestamp: $NOMBRE_BACKUP
```

Execute the restore deploy on the new instance with OML 2.0:

```
./deploy.sh --action=restore --tenant=$your_inventory_folder_name
```

Now we must revert back to the original Postgres image, which means restoring our group_vars/all file to its previous state:

```
#################### containers img taf  ################################

postgres_img: docker.io/postgres:14.9-bullseye
#postgres_img: omnileads/postgres:230624.01
```

And finally, execute:

```
./deploy.sh --action=upgrade --tenant=$your_inventory_folder_name
```

# Asterisk dialplan and other customizations 🛡️ <a name="asterisk_customizations"></a>

Based on containers, code customizations made within the container are ephemeral. To make permanent modifications to the Asterisk dialplan, scripts, or configurations, it's recommended to use custom images:

An example of how to do this is outlined in this [repo](https://gitlab.com/omnileads/acd-customizations-example/)

# Use your own container registry & images  <a name="components_img"></a>

In the inventory file you can customize the tags of the images to display, as well as the registry from where to download them.

```
    # ------------------------------------------------------------------------------------------------ #
    # ---------------------------- Container IMG TAG customization ----------------------------------- #
    # ------------------------------------------------------------------------------------------------ #
    
    # --- For each OML Deploy Tool release, a versioned stack with the latest stable images of each component is maintained on inventory.yml
    # --- You can combine the versions as you like, also use your own TAGs, using the following TAG version variables
    
    omnileads_img: your_registry/omlapp:231227.01
    asterisk_img: your_registry/asterisk:240102.01
    
    # --- Activate the OMniLeads Enterprise Edition.
    # --- on the contrary you will deploy OMniLeads OSS Edition with GPLV3 licensed. 
    
    enterprise_edition: false
```

## OMniLeads Enterprise :office: <a name="oml_enterprise"></a>

What is OMniLeads Enterprise?

It is an additional layer with complementary modules to OMniLeads Community (GPLV3). It includes functionalities such as advanced reports, wallboards, and automated satisfaction surveys implemented as modules.

This version can be implemented simply by referencing the image for the container that implements the web application.
Therefore, in our "inventory.yml" variable file, we must invoke the enterprise imag e. To do this, we add the string "-enterprise" to the end of the tag that describes the image of the omnileads_img component:

```
omnileads_img: docker.io/your_registry/omlapp:231227.01-enterprise
```

# Perform a Backup :floppy_disk: <a name="backups"></a>


Deploying a backup involves the asterisk custom configuration files /etc/asterisk/custom on the one hand and the database
on the other, using the bucket associated with the instance as a backup log.

To launch a backup, simply call the deploy.sh script:

```
./deploy.sh --action=backup --tenant=tenant_name_folder
```

The backup is deposited in the bucket, being under the backup folder on one side a .sql file with the timestamp and on the other side another directory is generated with the timestamp date and there are the custom and override asterisk files.
another directory is generated with the timestamp date and there inside are the asterisk custom and override files.

![Diagrama deploy backup](./png/deploy-backup.png)

>  Note: the unique numeric identifier forming the filename string of the database backup file is the value we should use when assigning it to the parameter: restore_file_timestamp: *restore_file_timestamp: 1681319391*

# Upgrades :arrows_counterclockwise:  <a name="upgrades"></a>

The OMniLeads project builds images of all its components to be hosted in docker hub: https://hub.docker.com/repositories/omnileads.

Each new release involves an update of code and variables on the **omldeploytool** repository. 
You can verify the image behind the component by inspecting the 'group_vars/all' file.

Therefore a new Release of the application becomes available as an image in the container registry, it will be impacted
the **Releases-Notes.md** file available in the root of this repository, which exposes the mapping between the
versions of the images of each component for each release.



https://gitlab.com/omnileads/omldeploytool/-/blob/main/ansible/group_vars/all?ref_type=heads

```
git pull origin main
git checkout release-2.0.0
```

Then indicate at the inventory.yml level within the corresponding tenant folder, the versions
desired, for example:

```
omnileads_img: docker.io/omnileads/omlapp:240201.01
asterisk_img: docker.io/omnileads/asterisk:240102.01
```

Then the deploy.sh script must be called with the --upgrade parameter.

```
./deploy.sh --action=upgrade --tenant=tenant_name_folder
```

# Rollback  :leftwards_arrow_with_hook: <a name="rollback"></a>


The use of containers when executing the OMniLeads components allows us to easily apply rollbacks towards versions
frozen history and accessible through the "tag".

```
omnileads_img: docker.io/omnileads/omlapp:240117.01
asterisk_img: docker.io/omnileads/asterisk:240102.01
fastagi_img: docker.io/omnileads/fastagi:240104.01
astami_img: docker.io/omnileads/astami:231230.01
nginx_img: docker.io/omnileads/nginx:240105.01
websockets_img: docker.io/omnileads/websockets:231125.01
kamailio_img: docker.io/omnileads/kamailio:231125.01
rtpengine_img: docker.io/omnileads/rtpengine:231125.01
redis_img: docker.io/omnileads/redis:231125.01
```

Then the deploy.sh script must be called with the --upgrade parameter.

```
./deploy.sh --action=upgrade --tenant=tenant_name_folder
```

# Restore :clock9: <a name="restore"></a>


You can proceed with a restore on a fresh installation as well as on a productive instance. 

Apply restore on the new instance: The two final parameters of the inventory.yml must be uncommented. On the one hand to indicate that the bucket does not have trusted certificates and the second one is to indicate the restore that we want to execute.

```
aio_instances:
      hosts:
        algarrobo:
          tenant_id: algarrobo
          ansible_host: 190.19.150.18
          omni_ip_lan: 172.16.101.44
          infra_env: cloud
          fqdn: tenant_name.omnileads.net
          cert_file_name: cert_custom_filename.pem
          key_file_name: key_custom_filename.pem 
          restore_file_timestamp: 458246873642
```

Run restore deploy:

```
./deploy.sh --action=restore --tenant=digitalocean_deb
```

# Observability :mag_right: :bar_chart: <a name="observability"></a>

Inside each subscriber linux instance the deployer put some containers in order to not only be able to 
to observe metrics at the operating system level but also to obtain specific metrics of components such as redis, postgres or asterisk, 
as well as to get the logs of the operating system and the also to get the logs of the operating system and the components and send them to the observability stack.

This allows us to propose a multi-instance observability center. On which it is possible to centralize the monitoring of OS and application metrics
of the OS and the application and its components, as well as centralizing log analysis.

This is possible thanks to the Prometheus approach together with its exporters for metrics monitoring on the one hand, and Loki and Promtail on the other. 
while Loki and Promtail implement the centralization of logs.

* **Loki**: used to storage file logs generated by OMniLeads components like django, nginx, kamailio, etc.
* **Promtail**: used to parse logs file on Linux VM nd send this to Loki DB.

![Diagrama deploy tool zoom](./png/observability_boxes.png)

Finally, you will be able to have an instance of Grafana and Prometheus that invoke this Prometheus deployed on tenat like data-source in order
to them build dashboards, on the other hand Grafana must to invoke the Loki deployed on tenant like data-source for logs analisys.

![Diagrama deploy tool zoom](./png/observability_MT.png).

Centralized observability.

# Scalability settings <a name="#scalability"></a>

* Asterisk:

This is the application server that powers the VoIP part of OMniLeads. You can adjust the following values to achieve better performance on the Asterisk component, aiming to handle more than 200 concurrent calls.

We can use asterisk_mem_limit to limit the amount of memory the process can consume. As for pjsip, stasis, and other settings in .conf files, we recommend referring to this article: https://docs.asterisk.org/Deployment/Performance-Tuning/.

By setting the scale_asterisk value on the inventory.yml host or group, you enable the ability to specify some params.

```
scale_asterisk: True
  asterisk_mem_limit: 1G
  pjsip_threadpool_idle_timeout: 120
  pjsip_threadpool_max_size: 150
```

* UWSGI:

This is the application server that powers the OMniLeads Django application.

By setting the scale_uwsgi value on the host or group, you enable the ability to specify the number of processes and threads it will handle.

```
scale_uwsgi: True
  processes: 8
  threads: 1 
```

## OMniLeads Enterprise

What is OMniLeads Enterprise?

It is an additional layer with complementary modules to OMniLeads Community (GPLV3). It includes functionalities such as advanced reports, wallboards, and automated satisfaction surveys implemented as modules.

This version can be implemented simply by referencing the image for the container that implements the web application.
Therefore, in our "inventory.yml" variable file, we must invoke the enterprise imag e. To do this, we add the string "-enterprise" to the end of the tag that describes the image of the omnileads_img component:

```
omnileads_img: docker.io/your_registry/omlapp:231227.01-enterprise
```

What is OMniLeads Enterprise?

It is an additional layer with complementary modules to OMniLeads Community (GPLV3). It includes functionalities such as advanced reports, wallboards, and automated satisfaction surveys implemented as modules.

This version can be implemented simply by referencing the image for the container that implements the web application.
Therefore, in our "inventory.yml" variable file, we must invoke the enterprise imag e. To do this, we add the string "-enterprise" to the end of the tag that describes the image of the omnileads_img component:

```
omnileads_img: docker.io/your_registry/omlapp:231227.01-enterprise
```

# Install on three (Data, Voice & Web) cluster instances. 🚀 <a name="ait-deploy"></a>

You must have three Linux instances with Internet access and **your public key (ssh) available**, since
Ansible needs to establish an SSH connection to deploy the actions.

![Diagrama deploy cloud services](./png/deploy-tool-tenant-components-ait.png)


Then you should work on the inventory.yml tenant file.

```
# -----------------------------------------
# -----------------------------------------
cluster_instances:
  children:
    tenant_mr_x:
      hosts:
        tenant_mr_x_data:
          ansible_host: 172.16.101.41
          omni_ip_lan: 172.16.101.41
          ansible_ssh_port: 22
        tenant_mr_x_voice:
          ansible_host: 172.16.101.42
          omni_ip_lan: 172.16.101.42
          ansible_ssh_port: 22
        tenant_mr_x_app:
          ansible_host: 172.16.101.43
          omni_ip_lan: 172.16.101.43
          ansible_ssh_port: 22
      vars:
        tenant_id: tenant_mr_x
        data_host: 172.16.101.41
        voice_host: 172.16.101.42
        application_host: 172.16.101.43
        infra_env: lan
```
The parameter ansible_host refers to the IP or FQDN used to establish an SSH connection. The omni_ip_lan parameter refers to the private IP (LAN) that will be used when opening certain ports for components and when they connect with each other.

The infra_env variable can be initialized as "lan" or "cloud", depending on whether the OMniLeads instance will be accessible via WAN access (IPADDR or FQDN) or via LAN access (IP or FQDN).

The *bucket_url* and *postgres_host* parameters must be commented out, so that both (PostgreSQL and Object Storage MinIO) are deployed within the AIO instance.

The rest of the parameters can be customized as desired.

Finally in the last section of the file, we must make sure that our tenant is listed in the omnileads_aio hosts group.

```
omnileads_aio:
  hosts:
    #tenant_example_1:
    #tenant_example_2:
    #tenant_example_3:
    #tenant_example_4:

omnileads_data:
  hosts:
    tenant_mr_x_data:    
    
omnileads_voice:
  hosts:
    tenant_mr_x_voice:

omnileads_app:
  hosts:
    tenant_mr_x_5_app:

```

```
./deploy.sh --action=install --tenant=tenant_name_folder
```

Once the URL is available with the App returning the login view,  we can log in with the user *admin*, password *admin*.

# Install on HA cluster instances. 🚀 <a name="cluster-ha-deploy"></a>

You must have four Linux instances with Internet access and **your public key (ssh) available**, since
Ansible needs to establish an SSH connection to deploy the actions. 

* OMniLeads AIO main Node: Debian 12 Bookworm
* OMniLeads AIO backup Node: Debian 12 Bookworm

![Diagrama deploy cloud services](./png/deploy-tool-tenant-components-ha.png)


Then you should work on the inventory.yml tenant file.

```
# -----------------------------------------
# -----------------------------------------
    ha_instances:
      children:
        tenant_example_7:
          hosts:              
            tenant_example_7_aio_A:
              tenant_id: tenant_example_7_aio_A
              ansible_host: 172.16.101.43
              omni_ip_lan: 172.16.101.43
              ha_role: main
            tenant_example_7_aio_B:
              tenant_id: tenant_example_7_aio_B
              ansible_host: 172.16.101.44
              omni_ip_lan: 172.16.101.44
              ha_role: backup                            
          vars:                        
            omnileads_ha: true
            ha_vip_nic: ens18 
            netaddr: 172.16.101.0/24
            netprefix: 24                        
            aio_1: 172.16.101.43
            aio_2: 172.16.101.44
            omnileads_vip: 172.16.101.205            
            postgres_rw_vip: 172.16.101.206
            postgres_ro_vip: 172.16.101.207   
            infra_env: lan
```

The parameter ansible_host refers to the IP or FQDN used to establish an SSH connection. The omni_ip_lan parameter refers to the private IP (LAN) that will be used when opening certain ports for components and when they connect with each other.

The infra_env variable can be initialized as "lan" or "cloud", depending on whether the OMniLeads instance will be accessible via WAN access (IPADDR or FQDN) or via LAN access (IP or FQDN).

* ha_vip_nic: 

This parameter is used to assign the virtual IP on NIC

In a high availability environment, we need to indicate to each cluster node its initial condition (ha_role), and since the role of the node implies the assignment of a virtual IP address (ha_vip_nic), we also need to indicate the name of the NIC over which the VIP is going to be established.

* omnileads_ha: true

This parameter is used to instruct Ansible to launch certain tasks inherent to the HA configuration.

* netaddr: 172.16.101.0/16
* netprefix: 24

These 2 parameters are used by the cluster. 

* aio_1: 172.16.101.43
* aio_2: 172.16.101.44

These 2 parameters are used by the cluster managers keepalived and rempgr. to indicate the IP of the nodes.

* omnileads_vip: 172.16.101.205

The Virtual IP used to https access.

Finally in the last section of the file, we must make sure that our tenant is listed in the omnileads_aio hosts group.

```
omnileads_aio:
  hosts:
    #tenant_example_1:
    #tenant_example_2:
    #tenant_example_3:
    #tenant_example_4:

    tenant_example_7_aio_A:
    tenant_example_7_aio_B:

################################################    
omnileads_data:
  hosts:
    #tenant_example_5_data:  
    
omnileads_voice:
  hosts:
    #tenant_example_5_voice:

omnileads_app:
  hosts:
    #tenant_example_5_app:
```

it can be seen that at host grouping level, we have the 4 hosts that conform the HA cluster distributed in the groups: ha_omnileads_sql and omnileads_aio instances group.

```
./deploy.sh --action=install --tenant=tenant_name_folder
```

Once the URL is available with the App returning the login view,  we can log in with the user *admin*, password *admin*.

## Postgres Cluster actions :arrows_clockwise: <a name="cluster_ha_recovery"></a>

### **Recovery Postgres main node**

When a Failover from Postgres Main to Postgres Backup occurs, then the Backup node takes the floating IP of the cluster and remains as the only RW/RO node with its corresponding IPs. 
as the only RW/RO node with its corresponding IPs. 

To return Postgres to the initial state two actions must be carried out:

```
./deploy.sh --action=pgsql_node_recovery_main --tenant=tenant_name_folder
```

This command is in charge of rejoining the Postgres Main node to the cluster. But if we only execute this action then 
the Cluster will be inverted, i.e. Postgres B as main and Postgres A as backup.

### **Takeover Postgres main node**


This command implies that a Recovery has been previously executed as described in the previous step.

```
./deploy.sh --action=pgsql_node_takeover_main --tenant=tenant_name_folder
```

After the execution of the takeover we will have the cluster in the initial state, i.e. Postgres A as Main and Postgres B as backup.

### **Recovery Postgres backup node**

When the VM hosting the Postgres Backup node shuts down, the Main node takes the floating RO IP of the cluster and remains as the only RW/RO node with its corresponding IPs. as the only RW/RO node with its corresponding IPs. To rejoin the backup node to the cluster and in this way recover the RO's VIP, it is necessary to run a
the RO VIP, a recovery deploy of the postgres backup node must be executed.

```
./deploy.sh --action=pgsql_node_recovery_backup --tenant=tenant_name_folder
```