# Release Notes - OMniLeads 2.4.2
[2025-05-27]

## Added

## Changed

* oml-3027 Optimized whatsapp reports
* oml-713 For systemd/ansible deployments, the /dev/shm partition for the PostgreSQL container has been enlarged.
* oml-760 Now allows uploading secret_key and key_id for authentication with AWS Buckets.

## Fixed

* oml-3026 Fix Whatsapp general report dates filter.
* oml-3031 Fix whatsapp messages style.
* oml-766 Resolved an issue with the restore action in All-in-Three deployments using Ansible/Systemd.

## Component changes

### OMLAPP (Django/VueJS)

* Container Img: https://hub.docker.com/layers/omnileads/omlapp/250516.01/images/sha256-9c8c06582777647ab2ff457242fdc3fc9a58afb6f75d824f4465a9a66b9e1c1f
* Gitlab Repo: https://gitlab.com/omnileads/ominicontacto/-/tree/250516.01?ref_type=tags