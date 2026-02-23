# Release Notes - OMniLeads 2.6.3
[2026-02-20]

## Added

* oml-3166 IVR: Dialer campaigns with Survey as destination.
* oml-3250 Browser Notification alert to desktop in inbound calls .
* oml-3252 Bulk Messages: Excell file support.

## Changed

* oml-3240 Survey reports csv with columns names.
* oml-3263 Automatic transfer to survey on agent hangup.
* oml-3253 Wallboard: Enhanced agents table filtering.

## Fixed

* oml-2795 Fix bug receiving inbound with telephone starting with "+".
* oml-3257 Fix bug "undefined" name for Whatsapp chats.
* oml-3259 Fix bug error dispositioning 'Anonymous' inbound phone calls.
* oml-3260 Fix Bug wombat list names max length.
* oml-3261 Avoid error 500 on Omnidialer service API call failure
* oml-3167 Fix Whatsapp service async calls and exception catching.
* oml-3273 Fixes msg-orchestrator crashes with non supported messages.
* oml-3140 Survey: Fix csv reports missing headers.
* oml-3276 Enterprise: Licence check deactivated for certain cron jobs.
* devops-843: Fix bug backup/restore.
* devops-881: Fix bug click2call via API.
* devops-891: Fix bug CRM interaction type 2.

## Removed
No removals in this release.

## DB Migrations

* 2.6.3 whatsapp_app: 0016