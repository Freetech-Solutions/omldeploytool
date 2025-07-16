# Release Notes - OMniLeads 2.5.0
[2025-07-11]

## Added

* oml-2679 Automatic outbound dialer module.
* oml-2923 Order and filtering adding agents in Campaigns Wizard.
* oml-2893 Massive download and deletion of agendas.
* oml-2886 Allow contact database structure definition on campaign wizard.
* oml-2921 Allow configuring Agents as IVR destinations.

## Changed

* oml-3040 Asterisk & Kamailio Webrtc SIP Register was optimized.
* oml-708 Migrate callrec postcall actions from RabbitMQ to gearman job server.

## Fixed

* oml-2931 Fix "enmodoselect" Incidence rule.
* oml-2997 Fix "easyaudits" logs ip field.

## Component changes

### OMniDialer (a new component)

* Docker registry (Worker): https://hub.docker.com/layers/omnileads/dialer_worker/20250711-5e7a2efa/images/sha256-d0eb18ab6899a634a34c116648d935210c4bce54c8b0559e2ce155adde587242
* Docker registry (ACD): https://hub.docker.com/layers/omnileads/dialer_asterisk/20250711-5e7a2efa/images/sha256-db601601ac45d5a0713a5e137c08ab5f3b3bec11b8a766cbf6d82a8daf0112d1
* Docker registry (Scheduler): https://hub.docker.com/layers/omnileads/dialer_scheduler/20250711-5e7a2efa/images/sha256-3c9c385ac4ecea48caa478336b5060c374552334bd7cf42a41abcb4f16fd2285 
* Docker registry (Event listener): https://hub.docker.com/layers/omnileads/dialer_listener/20250711-5e7a2efa/images/sha256-61432e304aa33931c9aba3efa88d623eff3f996bb46d23e2f774d059c02da714 
* Docker registry (API): https://hub.docker.com/layers/omnileads/dialer_api/20250711-5e7a2efa/images/sha256-6deefaef415862cc026f94010368042fe483c0ea0749def5a2fa8bb1bd21899f
* Docker registry (Dialplan): https://hub.docker.com/layers/omnileads/dialer_dialplan/20250711-5e7a2efa/images/sha256-175a41ee8f8b66c281b35e5493011da65c76d241c2df5abd6be5ea4667bb408d 
* Git: https://gitlab.com/omnileads/omnidialer

### OMLAPP

* Docker registry: https://hub.docker.com/layers/freetechsolutions/omlapp/20250711-35f57eb1/images/sha256-48a4df14dd7584f3f7e09e4fcfb8a621d143bf38906e8e61e05d0147c78f8f07
* Git: https://gitlab.com/omnileads/ominicontacto/-/tree/pre-release-2.5.0?ref_type=heads

### ACD

* Docker registry: https://hub.docker.com/layers/freetechsolutions/asterisk/20250710-d0c11614/images/sha256-60fcb0287c4de081e3f4a7977477dcdf644049c414b3b13e21a12860f465b2a7
* Git: https://gitlab.com/omnileads/omlacd/-/tree/develop-2.0?ref_type=heads

### Post call actions

* Docker registry: https://hub.docker.com/layers/freetechsolutions/interaction_processor/20250607-79649b40/images/sha256-b5d30e9de29fb4b53b9668c529cb50472e6a84fcd9cc230f9cbdacc513a606f0
* Git: https://gitlab.com/omnileads/oml_interactions_processor/-/tree/develop?ref_type=heads

### WebRTC SIP Bridge

* Docker registry: https://hub.docker.com/layers/freetechsolutions/kamailio/20250711-bd7d2c66/images/sha256-5c961b75f5dbc99637169152df5d55b6143ae339274aa6143df4521b4f8493dd
* Git: https://gitlab.com/omnileads/omlkamailio/-/tree/develop-2.0?ref_type=heads

### Nginx

* Docker registry: https://hub.docker.com/layers/freetechsolutions/nginx/20250711-8d976daf/images/sha256-b221d4a835483f128d5d262991bbcef5349f1856be97dbee7df74fd26b416eb6
* Git: https://gitlab.com/omnileads/omlnginx/-/tree/develop-2.0?ref_type=heads

### FastAGI

* Docker registry: https://hub.docker.com/layers/freetechsolutions/fastagi/20250616-6782cc3c/images/sha256-5b0d3fe89b2bbbe15848406a17e90809bdb88bdba69b0c3ef6a02a9a2a740b86
* Git: https://gitlab.com/omnileads/omlfastagi/-/tree/develop?ref_type=heads

##  New Environment Variables (docker-compose .env & Ansible inventory.yml)

Release 2.5 introduces OMniLeads' native Automatic Dialer, which means new containers and, consequently, new variables. Therefore, for deployments using docker-compose or Ansible, these new variables must be added to their respective files.

To do this, we recommend regenerating both files and then adjusting your previously set variables step-by-step.
