#!/bin/bash

ENDSTATE=$1

log_transition() {
    echo "$(date '+%Y-%m-%d %H:%M:%S'): $1, exec oml_cluster_transition.sh" >> /var/log/keepalive_transition.log
}

case $ENDSTATE in
    "BACKUP") # Acción para la transición al estado BACKUP
        log_transition "transition to BACKUP"
        systemctl stop nginx
        systemctl stop ami
        systemctl stop omnileads
        systemctl stop whatsapp
        systemctl stop background_tasks
        systemctl stop omlcron
        systemctl stop asterisk            
        systemctl stop asterisk_retrieve_conf
        ;;
    "FAULT")  # Acción para la transición al estado FAULT
        log_transition "transition to FAULT"
        systemctl stop nginx
        systemctl stop ami
        systemctl stop whatsapp
        systemctl stop background_tasks
        systemctl stop omnileads
        systemctl stop omlcron
        systemctl stop asterisk            
        systemctl stop asterisk_retrieve_conf
        ;;
    "MASTER") # Acción para la transición al estado MASTER
        log_transition "transition to MASTER"
        systemctl start asterisk
        sleep 5
        systemctl start ami
        systemctl start omnileads
        systemctl start whatsapp
        systemctl start background_tasks
        sleep 10
        systemctl start nginx
        sleep 2
        systemctl start asterisk_retrieve_conf
        systemctl start omlcron
        oml_manage --redis_sync
        ;;
    *)      
        log_transition "Unknown state ${ENDSTATE}"
        exit 1
        ;;
esac

exit 0
