# Release Notes - OMniLeads 2.6.0
[2025-10-09]

## Added

* [OMLAPP][WhatsApp] Added support for the Meta WhatsApp Provider.
* [OMLAPP] Added the ability for the agent webphone to place participants on hold.

## Changed

* [DIALER] Implemented WebSocket (WS) auto-reconnection on the websocket_ari component.
* [DIALER] Optimized the Stasis App code (dialer-dialplan). Updated Python and Gearman library versions.
* [DIALER] Implemented campaign priorities setting.
* [ANSIBLE] Modified the systemd restart parameter for the Dialer and WhatsApp components from on-failure to always.

## Fixed

* [ANSIBLE] Fixed missing Restart configuration for the Dialer components: process-contact, event, and campaign.
* [OMLAPP] Restored the command responsible for logging out expired web sessions.
* [ACD] Fixed issues with the activation/deactivation of Asterisk verbosity logs.
* [DIALER] Restricted pending schedules used for campaign finalization to the scope of their own campaign.

## Removed

No removals in this release.

## PostgreSQL Migrations

* 2.6.0 whatsapp_app: 0015
