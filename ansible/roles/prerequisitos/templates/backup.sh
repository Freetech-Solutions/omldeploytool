#!/bin/bash

set -x

source /etc/default/backup.env
/usr/bin/podman run --name pgsql_bk_$(date +"%Y%m%d_%H%M") --env-file /etc/default/backup.env -e BACKUP_FILENAME=pgsql-backup-$(date +"%Y%m%d_%H%M").sql --rm {{ BACKUP_RESTORE_IMG }} python backup.py

