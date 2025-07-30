# Release Notes - OMniLeads 2.5.0
[2025-07-24]

## Added

* oml-2679 Automatic outbound dialer module.
* oml-2923 Order and filtering adding agents in Campaigns Wizard.
* oml-2893 Massive download and deletion of agendas.
* oml-2886 Allow contact database structure definition on campaign wizard.
* oml-2921 Allow configuring Agents as IVR destinations.
* oml-772 New service for call transcriptions.

## Changed

* oml-3040 Asterisk & Kamailio Webrtc SIP Register was optimized.
* oml-708 Migrate callrec postcall actions from RabbitMQ to gearman job server.

## Fixed

* oml-2931 Fix "enmodoselect" Incidence rule.
* oml-2997 Fix "easyaudits" logs ip field.

##  New Environment Variables (docker-compose .env & Ansible inventory.yml)

Release 2.5 introduces OMniLeads' native Automatic Dialer, which means new containers and, consequently, new variables. Therefore, for deployments using docker-compose or Ansible, these new variables must be added to their respective files.

To do this, we recommend regenerating both files and then adjusting your previously set variables step-by-step.
