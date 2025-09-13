# Release Notes - OMniLeads 2.5.1
[2025-09-11]

## Added

* oml-3000 Add Agent Group setting to restrict password update.
* oml-3002 User bulk remove.
* oml-3115 Add Campaign setting to allow showing callid in disposition form.
* oml-3116 DTMF input form for agent's softphone (allowing copying long DTMF codes).

## Changed

* oml-2996 Disposition form is always displayed for Inbound calls.
* oml-3136 A fallback routine is now in place to handle scenarios where an audio file for the telephony channel cannot be located.

## Fixed

* oml-2999 Fix phone validation regex.
* oml-3037 Fix recording search tests.
* oml-3028 Fix recording search pagination buttons.
* oml-3048 Fix Respect call autoattend configuration for transfers to campaigns (OOS).
* oml-3135 Eliminated the sending of redundant jobs that activate the process-campaign.
* oml-3132 Management of a Postgres connection pool, a delay configurable between each contact search iteration, implementation of various caches.

## Removed

No removals in this release.

## PostgreSQL Migrations

ominicontacto_app: 0112, 0113
