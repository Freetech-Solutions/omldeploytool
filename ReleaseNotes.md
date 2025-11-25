# Release Notes - OMniLeads 2.6.1
[2025-11-25]

## Added

* oml-3001 Internal agents calls permission.
* oml-3118 Phone rating.
* oml-3165 Bulk Messaging Meta providers Support.

## Changed

* oml-3128 Database Results shows Subdispositions.
* oml-3190 Search Audits now includes non engaged dispositions.
* oml-3206 Allow editing Disconnection time for preview campaigns.
* oml-3105 Visual changes in Contact Disposition form.

## Fixed

* oml-3212 Fix External site interaction double trigger.
* oml-3229 Avoid Error 500 generating Call Reports with bad logs.
* oml-795 Fixed backup/restore tool
* oml-3240 OMniDialer boost factor
* oml-853 Disable SElinux on upgrades
* oml-863 Enable promtail service
* oml-855 Set 644 permission on postgresql.conf binded file

## Removed
No removals in this release.

## DB Migrations

* 2.6.1 ominicontacto_app: 0114, 0115