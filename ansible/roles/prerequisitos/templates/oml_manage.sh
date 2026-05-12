#!/usr/bin/env bash

{% raw %}
# =============================================================================
# OMniLeads — gestión Podman + systemd (Quadlet)
# Basado en docker-compose/oml_manage.sh; nombres alineados con ContainerName=
# en ansible/roles/*/templates/*.service y *.container
# =============================================================================
set -euo pipefail

# Imagen backup/restore (misma variable que backup.sh del rol prerequisitos)
{% endraw %}
BACKUP_RESTORE_IMG="{{ backup_restore_img | default('') }}"
{% raw %}

# --- Nombres de contenedor (Quadlet ContainerName=) ---
CN_POSTGRES=postgresql-server
CN_REDIS=redis-server
CN_MINIO=minio-server
CN_GEARMAN=gearman-server
CN_OMLAPP=omlapp-uwsgi
CN_DAPHNE=omlapp-daphne
CN_WHATSAPP=omlapp-whatsapp
CN_WEBSOCKET=websocket-server
CN_NGINX=nginx-server
CN_ACD_SERVER=acd-server
CN_ACD_APP=acd-app
CN_ACD_CONF=acd-conf
CN_FASTAGI=acd-fastagi
CN_KAMAILIO_WEBRTC=kamailio-webrtc
CN_KAMAILIO_PSTN=kamailio-pstn-server
CN_RTPENGINE=rtpengine-server
CN_DIALER_API=dialer-api
CN_PSTN_QA=oml-pstn-server

# Servicios críticos para health (nombre lógico -> contenedor)
declare -A CRITICAL_CN=(
  [postgresql]=$CN_POSTGRES
  [redis]=$CN_REDIS
  [minio]=$CN_MINIO
  [omlapp]=$CN_OMLAPP
  [nginx]=$CN_NGINX
  [acd]=$CN_ACD_SERVER
)

# Contenedores conocidos para stats / status ampliado (orden arbitrario)
KNOWN_CONTAINERS=(
  "$CN_POSTGRES" "$CN_REDIS" "$CN_MINIO" "$CN_GEARMAN"
  "$CN_OMLAPP" "$CN_DAPHNE" "$CN_WHATSAPP" "$CN_WEBSOCKET" "$CN_NGINX"
  "$CN_ACD_CONF" "$CN_ACD_SERVER" "$CN_ACD_APP" "$CN_FASTAGI"
  "$CN_KAMAILIO_WEBRTC" "$CN_KAMAILIO_PSTN" "$CN_RTPENGINE" "$CN_DIALER_API"
  omlapp-callrec-worker omlapp-dialer-worker omlapp-supervision-agentes-scheduler
  omlapp-daily-redis-cleanup omlapp-presence-heartbeat-scheduler oml-call-logger
  omlapp-dashboard-agent-scheduler omlapp-supervision-events-listener
  dialer-manage-campaign dialer-incidence-rules dialer-render-template
  dialer-scheduler dialer-send-reports callrec-compressor callrec-transcriptor
)

# Pods Quadlet (membresía en grupos pod del inventario; ver roles/pods/tasks/main.yml).
# Cada nombre genera la unidad systemd "<nombre>-pod.service" desde su .pod.
KNOWN_PODS=(
  acd
  callrec_processor
  data_statefull
  data_stateless
  dialer_workers
  observability
  omlapp_web
  omlapp_workers
  telephony_edge
)

# Unidades systemd típicas (fichero .container en /etc/containers/systemd/)
# stack-up / stack-down recorren esta lista si existen en systemd.
STACK_UNITS_ORDER=(
  omnileads-network.service
  postgresql.service redis.service minio.service gearman.service
  omnileads.service daphne.service whatsapp.service websockets.service
  call_logger.service daily_redis_cleanup.service background_dialer_tasks.service
  background_callrec_tasks.service dashboard_agent_scheduler.service
  supervision_agentes_scheduler.service supervision_events_listener.service
  presence_heartbeat_scheduler.service
  nginx.service
  acd-config.service acd-server.service acd-app.service acd-fastagi.service
  kamailio_webrtc.service kamailio_pstn.service rtpengine.service
  dialer_api.service dialer_incidence_rules.service dialer_manage_campaign.service
  dialer_render_template.service dialer_scheduler.service dialer_send_reports.service
  callrec_compressor.service callrec_transcriber.service
)

DJANGO_ENV=/etc/default/django.env
ACD_ENV=/etc/default/acd.env
BACKUP_ENV=/etc/default/backup.env
MANAGE_PY=/opt/omnileads/ominicontacto/manage.py

RED=''; GREEN=''; YELLOW=''; BLUE=''; PURPLE=''; CYAN=''; BOLD=''; NC=''

setup_colors() {
    if [[ -t 1 ]] && command -v tput &>/dev/null && [[ "$(tput colors 2>/dev/null || echo 0)" -ge 8 ]]; then
        RED="$(tput setaf 1)";   GREEN="$(tput setaf 2)";  YELLOW="$(tput setaf 3)"
        BLUE="$(tput setaf 4)";  PURPLE="$(tput setaf 5)"; CYAN="$(tput setaf 6)"
        BOLD="$(tput bold)";     NC="$(tput sgr0)"
    fi
}

log()     { echo -e "${BOLD}[$(date +'%H:%M:%S')]${NC} $1"; }
success() { echo -e "${GREEN}✔ $1${NC}"; }
warning() { echo -e "${YELLOW}⚠ $1${NC}"; }
error()   { echo -e "${RED}✖ $1${NC}"; }
info()    { echo -e "${CYAN}ℹ $1${NC}"; }

check_podman() {
    command -v podman &>/dev/null || { error "Falta podman"; exit 1; }
}

container_exists() {
    podman container exists "$1" 2>/dev/null || podman inspect "$1" &>/dev/null
}

systemd_unit_exists() {
    local u=$1
    [[ -n "$(systemctl show -p FragmentPath --value "$u" 2>/dev/null || true)" ]]
}

is_known_pod() {
    local p=$1
    local known
    for known in "${KNOWN_PODS[@]}"; do
        [[ "$p" == "$known" ]] && return 0
    done
    return 1
}

container_running() {
    [[ -n "$(podman ps -q --filter "name=^${1}$" --filter "status=running" 2>/dev/null)" ]]
}

require_container_running() {
    local name=$1
    if ! container_running "$name"; then
        error "El contenedor '$name' no está en ejecución."
        return 1
    fi
    return 0
}

# Normaliza comandos legacy (--foo) al estilo nuevo (foo)
normalize_cmd() {
    case "$1" in
        --reset_pass)         echo reset-pass ;;
        --init_env)           echo data-generate ;;
        --regenerar_asterisk) echo regenerar-asterisk ;;
        --redis_sync)         echo redis-sync ;;
        --redis_clean)        echo redis-clean ;;
        --generate_call)      echo inbound-call ;;
        --show_bucket)        echo show-bucket ;;
        --asterisk_cli)       echo asterisk_cli ;;
        --psql)               echo psql ;;
        --psql_reindex)       echo psql-reindex ;;
        --redis_cli)          echo redis-cli ;;
        --asterisk_bash)      echo asterisk-bash ;;
        --kamailio_logs)      echo kamailio-logs ;;
        --django_bash)        echo terminal ;;
        --django_shell)       echo django-shell ;;
        --django_commands)    echo django-commands ;;
        --fastagi_bash)       echo fastagi-bash ;;
        --rtpengine_bash)     echo rtpengine-bash ;;
        --rtpengine_conf)     echo rtpengine-conf ;;
        --websockets_logs)    echo websockets-logs ;;
        --nginx_t)            echo nginx-t ;;
        --pgsql)              echo psql ;;
        --restart_core)       echo restart-core ;;
        --restart)            echo restart-all ;;
        --dialer_sync)        echo dialer-sync ;;
        --clean_redis)        echo clean-redis-volume ;;
        --pod_restart)        echo pod-restart ;;
        --help|help)          echo help ;;
        *)                    echo "$1" ;;
    esac
}

check_health() {
    info "Comprobando servicios críticos (Quadlet)..."
    local unhealthy=()
    for key in "${!CRITICAL_CN[@]}"; do
        local cn=${CRITICAL_CN[$key]}
        printf "  %-12s " "$key:"
        if ! container_exists "$cn"; then
            echo -e "${RED}✖ sin contenedor${NC}"
            unhealthy+=("$key")
            continue
        fi
        local state health
        state=$(podman inspect --format '{{.State.Status}}' "$cn" 2>/dev/null || echo "unknown")
        health=$(podman inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' "$cn" 2>/dev/null || echo "none")
        case "$state/$health" in
            running/healthy)   echo -e "${GREEN}✔ healthy${NC}" ;;
            running/unhealthy) echo -e "${RED}✖ unhealthy${NC}"; unhealthy+=("$key") ;;
            running/*)         echo -e "${YELLOW}● running${NC}" ;;
            exited/*|stopped/*) echo -e "${PURPLE}◯ stopped${NC}"; unhealthy+=("$key") ;;
            *)                 echo -e "${RED}? $state${NC}"; unhealthy+=("$key") ;;
        esac
    done
    if (( ${#unhealthy[@]} )); then
        error "Problemas en: ${unhealthy[*]}"
        return 1
    fi
    success "Servicios críticos OK"
}

show_raw_stats() {
    echo
    info "Uso de recursos (podman stats):"
    local running=()
    local c
    for c in "${KNOWN_CONTAINERS[@]}"; do
        container_running "$c" && running+=("$c")
    done
    if (( ${#running[@]} )); then
        podman stats --no-stream --format "table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.NetIO}}" "${running[@]}"
    else
        warning "Ningún contenedor conocido en ejecución."
    fi
}

show_status() {
    echo
    info "Estado de contenedores (podman ps -a, filtrado por nombres conocidos):"
    podman ps -a --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" 2>/dev/null | head -1
    local c
    for c in "${KNOWN_CONTAINERS[@]}"; do
        podman ps -a --filter "name=^${c}$" --format "{{.Names}}\t{{.Status}}\t{{.Ports}}" 2>/dev/null || true
    done | sort -u

    echo
    info "Métricas medias (contenedores conocidos en ejecución):"
    local tmp_cpu tmp_mem tmp_count
    tmp_cpu=$(mktemp); tmp_mem=$(mktemp); tmp_count=$(mktemp)
    echo 0 > "$tmp_cpu"; echo 0 > "$tmp_mem"; echo 0 > "$tmp_count"
    local any=0
    for c in "${KNOWN_CONTAINERS[@]}"; do
        container_running "$c" || continue
        any=1
        local line cpu mem
        line=$(podman stats --no-stream --format "{{.CPUPerc}}\t{{.MemPerc}}" "$c" 2>/dev/null || true)
        [[ -z "$line" ]] && continue
        cpu=${line%%$'\t'*}; mem=${line##*$'\t'}
        cpu=${cpu%%%}; mem=${mem%%%}
        echo "$(awk "BEGIN{printf \"%.2f\", $cpu + $(<"$tmp_cpu")}")" > "$tmp_cpu"
        echo "$(awk "BEGIN{printf \"%.2f\", $mem + $(<"$tmp_mem")}")" > "$tmp_mem"
        echo "$(( $(<"$tmp_count") + 1 ))" > "$tmp_count"
    done
    if (( any )); then
        local count total_cpu total_mem avg_cpu avg_mem
        count=$(<"$tmp_count")
        if (( count > 0 )); then
            total_cpu=$(<"$tmp_cpu"); total_mem=$(<"$tmp_mem")
            avg_cpu=$(awk "BEGIN{printf \"%.1f\", $total_cpu/$count}")
            avg_mem=$(awk "BEGIN{printf \"%.1f\", $total_mem/$count}")
            printf "  CPU media      : %s%%\n" "$avg_cpu"
            printf "  Memoria media  : %s%%\n" "$avg_mem"
            printf "  Contadores     : %d\n" "$count"
        fi
    else
        warning "Sin contenedores conocidos corriendo."
    fi
    rm -f "$tmp_cpu" "$tmp_mem" "$tmp_count"

    show_raw_stats

    echo
    info "Validación de salud..."
    local stopped=() unhealthy=() starting=()
    for c in "${KNOWN_CONTAINERS[@]}"; do
        container_exists "$c" || continue
        local state health
        state=$(podman inspect --format '{{.State.Status}}' "$c")
        health=$(podman inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' "$c" 2>/dev/null || echo "none")
        if [[ "$state" != "running" ]]; then
            stopped+=("$c ($state)")
        elif [[ "$health" == "unhealthy" ]]; then
            unhealthy+=("$c")
        elif [[ "$health" == "starting" ]]; then
            starting+=("$c")
        fi
    done
    local err=0
    if (( ${#stopped[@]} )); then
        echo; error "Contenedores no en ejecución:"; printf '  %s\n' "${stopped[@]}"; err=1
    fi
    if (( ${#unhealthy[@]} )); then
        echo; error "Contenedores unhealthy:"; printf '  %s\n' "${unhealthy[@]}"; err=1
    fi
    if (( ${#starting[@]} )); then
        echo; warning "Aún arrancando:"; printf '  %s\n' "${starting[@]}"
    fi
    if (( err )); then error "Comprobación del sistema FALLÓ."; return 1; fi
    echo; success "Integridad OK (contenedores conocidos)."
}

wait_for_services_healthy() {
    local timeout_sec="${1:-120}"
    shift
    local services=("$@")
    (( ${#services[@]} )) || services=("$CN_POSTGRES" "$CN_REDIS" "$CN_MINIO")
    log "Esperando contenedores listos (timeout ${timeout_sec}s): ${services[*]}"
    local start_ts elapsed
    start_ts=$(date +%s)
    while true; do
        elapsed=$(( $(date +%s) - start_ts ))
        if (( elapsed >= timeout_sec )); then
            error "Timeout esperando: ${services[*]}"
            return 1
        fi
        local all_ok=1
        local cn
        for cn in "${services[@]}"; do
            if ! container_exists "$cn"; then all_ok=0; break; fi
            local health state
            state=$(podman inspect --format '{{.State.Status}}' "$cn" 2>/dev/null || echo "")
            health=$(podman inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' "$cn" 2>/dev/null || echo "none")
            if [[ "$health" == "healthy" ]]; then continue; fi
            if [[ "$health" == "none" && "$state" == "running" ]]; then continue; fi
            all_ok=0
            break
        done
        if (( all_ok )); then success "Dependencias listas."; return 0; fi
        sleep 3
    done
}

reset_admin_password() {
    require_container_running "$CN_OMLAPP" || exit 1
    podman exec -it "$CN_OMLAPP" python3 "$MANAGE_PY" cambiar_admin_password || {
        error "Fallo al resetear password admin"; exit 1
    }
    success "Password admin actualizado"
}

generate_data() {
    require_container_running "$CN_OMLAPP" || exit 1
    podman exec -it "$CN_OMLAPP" python3 "$MANAGE_PY" inicializar_entorno || {
        error "Fallo inicializar_entorno"; exit 1
    }
}

redis_sync() {
    require_container_running "$CN_OMLAPP" || exit 1
    podman exec -it "$CN_OMLAPP" python3 "$MANAGE_PY" regenerar_asterisk || {
        error "Fallo regenerar_asterisk"; exit 1
    }
}

dialer_sync() {
    require_container_running "$CN_OMLAPP" || exit 1
    podman exec -it "$CN_OMLAPP" python3 "$MANAGE_PY" sincronizar_wombat || {
        error "Fallo sincronizar_wombat"; exit 1
    }
}

backup_database() {
    [[ -f "$BACKUP_ENV" ]] || { error "Falta $BACKUP_ENV (backup no configurado en este nodo)"; exit 1; }
    [[ -n "$BACKUP_RESTORE_IMG" ]] || { error "BACKUP_RESTORE_IMG vacío (definir backup_restore_img en Ansible)"; exit 1; }
    local fn="pgsql-backup-$(date +%Y%m%d_%H%M).sql"
    podman run --rm --network=host --env-file "$BACKUP_ENV" -e "BACKUP_FILENAME=$fn" \
        "$BACKUP_RESTORE_IMG" python backup.py || {
        error "Fallo en backup"; exit 1
    }
    success "Backup solicitado ($fn)"
}

restore_database() {
    [[ -f "$BACKUP_ENV" ]] || { error "Falta $BACKUP_ENV"; exit 1; }
    [[ -n "$BACKUP_RESTORE_IMG" ]] || { error "BACKUP_RESTORE_IMG vacío"; exit 1; }
    podman run --rm --network=host --env-file "$BACKUP_ENV" "$BACKUP_RESTORE_IMG" python restore.py || {
        error "Fallo en restore"; exit 1
    }
    success "Restore ejecutado"
}

run_django_commands() {
    local img="${1:-}"
    if [[ -z "$img" ]]; then
        error "Indica la imagen omlapp: oml_manage django-commands <imagen>"
        info "Ejemplo: oml_manage django-commands docker.io/omnileads/omlapp:231227.01"
        exit 1
    fi
    wait_for_services_healthy 120 "$CN_POSTGRES" "$CN_REDIS" "$CN_MINIO" || exit 1
    podman run --rm --network=host --env-file "$DJANGO_ENV" "$img" /opt/omnileads/bin/django_commands.sh || {
        error "django-commands falló"; exit 1
    }
    success "django-commands OK"
}

send_inbound_call() {
    local telephone="${1:-}"
    [[ -n "$telephone" ]] || { error "Uso: inbound-call <teléfono>"; exit 1; }
    local target="${OML_SIPP_TARGET:-127.0.0.1:5060}"
    if container_running "$CN_PSTN_QA"; then
        require_container_running "$CN_PSTN_QA" || exit 1
        podman exec -T "$CN_PSTN_QA" sipp -sn uac "$target" -s "999$telephone" -m 1 -r 1 -d 60000 -l 1 || {
            error "Fallo sipp"; exit 1
        }
    else
        error "Contenedor $CN_PSTN_QA no está en ejecución (rol qa / pstn.service)."
        exit 1
    fi
}

hangup_pstn() {
    if container_running "$CN_PSTN_QA"; then
        podman exec -T "$CN_PSTN_QA" asterisk -rx "channel request hangup all" || {
            error "Fallo hangup"; exit 1
        }
    else
        error "Contenedor $CN_PSTN_QA no está en ejecución."
        exit 1
    fi
}

dialer_call_test() {
    local id_camp="${1:-}"
    [[ -n "$id_camp" ]] || { error "Uso: dialer-call <id_campaña>"; exit 1; }
    local inst="${DIALER_PC_INSTANCE:-1}"
    local cname="dialer-process-campaign-${inst}"
    require_container_running "$cname" || exit 1
    podman exec -T "$cname" python3 call_test_dialer.py "$id_camp" || {
        error "call_test_dialer.py falló"; exit 1
    }
}

manual_call_test() {
    local telephone="${1:-123456784}"
    local id_camp="${2:-9}"
    local id_customer="${3:-1}"
    local id_agent="${4:-0}"
    local mc="${OML_MANUAL_CALL_CONTAINER:-}"
    if [[ -z "$mc" ]]; then
        error "No hay contenedor Quadlet tipo dialer-acd-dialplan en Ansible."
        info "Exporta OML_MANUAL_CALL_CONTAINER con el nombre del contenedor y reintenta."
        exit 1
    fi
    require_container_running "$mc" || exit 1
    podman exec -T "$mc" python3 call_test_dialer.py "$telephone" "$id_camp" "$id_customer" "$id_agent" 1 1 15 15 || {
        error "manual-call falló"; exit 1
    }
}

run_sngrep() {
    require_container_running "$CN_ACD_SERVER" || exit 1
    podman exec -it "$CN_ACD_SERVER" sngrep
}

run_asterisk_cli() {
    require_container_running "$CN_ACD_SERVER" || exit 1
    podman exec -it "$CN_ACD_SERVER" asterisk -rvvvvv
}

open_psql() {
    local db_user="${1:-}"
    [[ -n "$db_user" ]] || { error "Uso: psql <usuario_db>"; exit 1; }
    require_container_running "$CN_POSTGRES" || exit 1
    podman exec -it "$CN_POSTGRES" psql -U "$db_user"
}

open_terminal() {
    local svc="${1:-}"
    [[ -n "$svc" ]] || {
        error "Uso: terminal <nombre_contenedor>"
        info "Ejemplos: $CN_OMLAPP, $CN_ACD_SERVER, $CN_FASTAGI"
        exit 1
    }
    require_container_running "$svc" || exit 1
    podman exec -it "$svc" bash 2>/dev/null || podman exec -it "$svc" sh
}

stack_start() {
    log "Iniciando unidades systemd (Quadlet) en orden..."
    local u started=0
    for u in "${STACK_UNITS_ORDER[@]}"; do
        systemd_unit_exists "$u" || continue
        systemctl start "$u" && { info "start $u"; ((started++)) || true; } || warning "fallo start $u"
    done
    success "stack-up: procesadas unidades existentes (${started} arranques OK parciales — revisar logs)."
}

stack_stop() {
    log "Deteniendo unidades systemd en orden inverso..."
    local -a rev=()
    local u
    for u in "${STACK_UNITS_ORDER[@]}"; do
        rev=("$u" "${rev[@]}")
    done
    for u in "${rev[@]}"; do
        systemd_unit_exists "$u" || continue
        systemctl stop "$u" && info "stop $u" || warning "fallo stop $u"
    done
    success "stack-down completado (mejor esfuerzo)."
}

# Quadlet .pod → unidad systemd <stem>-pod.service (ver roles/pods/tasks/main.yml)
resolve_pod_systemd_unit() {
    local a="${1:-}"
    [[ -n "$a" ]] || return 1
    local unit
    if [[ "$a" == *-pod.service ]]; then
        unit="$a"
    elif [[ "$a" == omlapp-server ]]; then
        unit="omlapp_web-pod.service"
    else
        local s="$a"
        [[ "$s" == *.pod ]] && s="${s%.pod}"
        [[ "$s" == *-pod ]] && s="${s%-pod}"
        unit="${s}-pod.service"
    fi
    [[ "$unit" == *-pod.service ]] || {
        error "Se espera un pod Quadlet (unidad *-pod.service), obtuve: $unit"
        return 1
    }
    printf '%s\n' "$unit"
}

pod_restart() {
    local arg="${1:-}"
    [[ -n "$arg" ]] || {
        error "Uso: pod-restart <pod|unidad>"
        info "Ejemplo: pod-restart omlapp-server   → omlapp_web-pod.service (pod web)"
        info "También: pod-restart omlapp_web   o   pod-restart omlapp_web-pod.service"
        exit 1
    }
    local unit
    unit=$(resolve_pod_systemd_unit "$arg") || exit 1
    systemd_unit_exists "$unit" || { error "Unidad no encontrada: $unit"; exit 1; }
    log "Reiniciando pod ($unit)..."
    systemctl restart "$unit" && success "restart $unit OK" || {
        error "systemctl restart falló: $unit"
        exit 1
    }
}

systemctl_restart_one() {
    local key=$1
    local base=$key
    [[ "$base" == *.service ]] && base="${base%.service}"
    local unit=""
    case "$base" in
        nginx) unit=nginx.service ;;
        postgresql|postgres) unit=postgresql.service ;;
        redis) unit=redis.service ;;
        minio) unit=minio.service ;;
        gearman) unit=gearman.service ;;
        omnileads|omlapp|uwsgi) unit=omnileads.service ;;
        daphne) unit=daphne.service ;;
        whatsapp) unit=whatsapp.service ;;
        websockets|websocket) unit=websockets.service ;;
        acd-server|asterisk) unit=acd-server.service ;;
        acd-app) unit=acd-app.service ;;
        acd-config|acd-conf) unit=acd-config.service ;;
        fastagi) unit=acd-fastagi.service ;;
        kamailio-webrtc) unit=kamailio_webrtc.service ;;
        kamailio-pstn) unit=kamailio_pstn.service ;;
        rtpengine) unit=rtpengine.service ;;
        dialer-api) unit=dialer_api.service ;;
        *)
            if [[ "$key" == *.service ]]; then unit="$key"; else unit="${key}.service"; fi
            ;;
    esac
    systemd_unit_exists "$unit" || { error "Unidad no encontrada: $unit"; return 1; }
    systemctl restart "$unit" && success "restart $unit"
}

clean_system() {
    log "Limpieza podman (contenedores detenidos, imágenes/volúmenes/redes no usados)..."
    podman container prune -f
    podman image prune -f
    podman volume prune -f
    podman network prune -f
    success "Limpieza básica OK"
}

clean_all() {
    warning "Elimina contenedores, imágenes, volúmenes y redes no usados de forma agresiva (podman system prune -a --volumes)."
    read -rp "¿Continuar? (y/N): " ans
    if [[ "$ans" =~ ^[Yy]$ ]]; then
        podman system prune -a -f --volumes
        success "Limpieza completa"
    else
        info "Cancelado"
    fi
}

show_bucket() {
    require_container_running "$CN_OMLAPP" || exit 1
    podman exec -T "$CN_OMLAPP" bash -c 'aws --endpoint-url "$S3_ENDPOINT" s3 ls --recursive "s3://${S3_BUCKET_NAME}"' || {
        error "show-bucket falló (¿variables S3 en django.env?)"; exit 1
    }
}

redis_cli_launch() {
    local host
    host=$(grep -E '^REDIS' "$DJANGO_ENV" 2>/dev/null | head -1 | cut -d= -f2- || true)
    [[ -n "$host" ]] || { error "No se pudo leer REDIS* de $DJANGO_ENV"; exit 1; }
    podman run --rm -it docker.io/library/redis redis-cli -h "$host"
}

redis_clean_cache() {
    read -rp "¿Flushall en Redis? (y/N): " ans
    [[ "$ans" =~ ^[Yy]$ ]] || { info "Cancelado"; return 0; }
    require_container_running "$CN_REDIS" || exit 1
    podman exec -T "$CN_REDIS" redis-cli flushall
    success "Redis flushall OK"
}

psql_reindex() {
    require_container_running "$CN_OMLAPP" || exit 1
    podman exec -it --env-file "$DJANGO_ENV" "$CN_OMLAPP" bash -c 'psql -c "reindex database ${PGDATABASE};"' || {
        error "reindex falló"; exit 1
    }
}

restart_core() {
    log "Reinicio núcleo (fastagi, acd-server, omnileads, daphne, nginx)..."
    for u in acd-fastagi.service acd-server.service omnileads.service daphne.service nginx.service; do
        systemd_unit_exists "$u" && systemctl restart "$u" && info "restart $u" || true
    done
    success "restart-core completado"
}

restart_all() {
    read -rp "¿Reiniciar todos los componentes conocidos? (yes/no): " confirmacion
    [[ "$confirmacion" == "yes" ]] || { info "Salida"; return 0; }
    local u
    for u in rtpengine.service redis.service acd-fastagi.service acd-server.service \
             kamailio_webrtc.service omnileads.service daphne.service nginx.service \
             websockets.service gearman.service minio.service postgresql.service; do
        systemd_unit_exists "$u" && systemctl restart "$u" && info "restart $u" || true
    done
    success "restart-all (mejor esfuerzo)"
}

clean_redis_volume() {
    warning "Operación destructiva: detiene redis y borra el volumen oml_redis (Quadlet)."
    read -rp "¿Continuar? (yes/no): " confirmacion
    [[ "$confirmacion" == "yes" ]] || { info "Cancelado"; return 0; }
    systemctl stop redis.service 2>/dev/null || true
    podman rm -f "$CN_REDIS" 2>/dev/null || true
    podman volume rm oml_redis 2>/dev/null || true
    systemctl start redis.service 2>/dev/null || true
    sleep 5
    redis_sync
}

up_with_commands() {
    local img="${1:-}"
    log "Arrancando dependencias mínimas (postgresql, redis, minio)..."
    local du
    for du in postgresql.service redis.service minio.service; do
        systemd_unit_exists "$du" && systemctl start "$du" && info "start $du" || true
    done
    wait_for_services_healthy 120 "$CN_POSTGRES" "$CN_REDIS" "$CN_MINIO" || exit 1
    if [[ -n "$img" ]]; then
        run_django_commands "$img"
    else
        warning "Sin imagen: ejecuta django-commands <img> manualmente si necesitas migrate/collectstatic."
    fi
    stack_start
}

show_help() {
    cat <<'EOF'

OMniLeads — oml_manage (Podman / systemd Quadlet)

Uso principal:
  oml_manage <comando> [argumentos]

Comandos (también alias legacy --comando):
  status              Estado, stats y validación de contenedores conocidos
  health              Salud de servicios críticos
  stack-up            systemctl start de unidades Quadlet conocidas (orden)
  stack-down          systemctl stop en orden inverso
  up [commands [img]] Espera postgres/redis/minio; opc. django-commands + stack-up
  start   [unidad]    systemctl start (clave: nginx, redis, omnileads, acd-server, …)
  stop    [unidad]    systemctl stop
  restart [unidad|pod] systemctl restart. Si el argumento coincide con un pod
                       conocido (acd, callrec_processor, data_statefull,
                       data_stateless, dialer_workers, observability, omlapp_web,
                       omlapp_workers, telephony_edge), reinicia <pod>-pod.service.
  logs    [-f] <cnt>  podman logs (nombre de contenedor Quadlet)
  terminal <cnt>      Shell en contenedor
  reset-pass          cambiar_admin_password (omlapp)
  data-generate       inicializar_entorno
  redis-sync          regenerar_asterisk
  dialer-sync         sincronizar_wombat
  redis-clean         flushall en redis-server (confirmación)
  django-commands <img>  podman run one-shot django_commands.sh
  backup / restore    Podman + /etc/default/backup.env + BACKUP_RESTORE_IMG
  psql <usuario>      psql en postgresql-server
  psql-reindex        reindex vía omlapp + django.env
  sngrep / asterisk_cli  en acd-server
  inbound-call <tel>  sipp en oml-pstn-server (OML_SIPP_TARGET, def. 127.0.0.1:5060)
  hangup-pstn         cuelga vía PSTN QA
  dialer-call <id>    call_test_dialer en dialer-process-campaign-${DIALER_PC_INSTANCE:-1}
  manual-call [tel] [camp] [cust] [agent]  requiere OML_MANUAL_CALL_CONTAINER
  env                 Primeras líneas de django.env
  version             podman --version
  clean / clean-all   podman prune
  restart-core / restart-all
  show-bucket         aws s3 ls (variables en contenedor omlapp)
  redis-cli           redis-cli hacia host de django.env
  kamailio-logs       logs kamailio-webrtc
  websockets-logs     logs websocket-server
  nginx-t             nginx -T en oml-nginx-server
  django-shell        manage.py shell
  fastagi-bash / asterisk-bash / rtpengine-bash / rtpengine-conf
  pod-restart <pod>   systemctl restart del Quadlet .pod (ej. omlapp-server → omlapp_web-pod.service)

Variables útiles:
  DIALER_PC_INSTANCE   instancia dialer-process-campaign (default 1)
  OML_SIPP_TARGET      destino sipp para inbound-call
  OML_MANUAL_CALL_CONTAINER  contenedor para manual-call

EOF
}

main() {
    setup_colors
    check_podman

    local raw="${1:-help}"
    local cmd
    cmd=$(normalize_cmd "$raw")
    [[ $# -gt 0 ]] && shift

    case "$cmd" in
        help|--help|-h|"") show_help ;;
        status)            show_status ;;
        health)            check_health ;;

        stack-up)          stack_start ;;
        stack-down)        stack_stop ;;
        up)
            if [[ "${1:-}" == "commands" ]]; then
                shift
                up_with_commands "${1:-}"
            else
                stack_start
            fi
            ;;

        start)
            [[ -n "${1:-}" ]] || { error "Uso: start <unidad|clave>"; exit 1; }
            local su=$1
            [[ "$su" == *.service ]] || su="${su}.service"
            systemd_unit_exists "$su" || { error "Unidad no encontrada: $su"; exit 1; }
            systemctl start "$su" || { error "start falló: $su"; exit 1; }
            ;;
        stop)
            [[ -n "${1:-}" ]] || { error "Uso: stop <unidad|clave>"; exit 1; }
            local su=$1
            [[ "$su" == *.service ]] || su="${su}.service"
            systemd_unit_exists "$su" || { error "Unidad no encontrada: $su"; exit 1; }
            systemctl stop "$su" || { error "stop falló: $su"; exit 1; }
            ;;
        restart)
            [[ -n "${1:-}" ]] || { error "Uso: restart <unidad|clave|pod>"; exit 1; }
            if is_known_pod "$1"; then
                local podunit="${1}-pod.service"
                systemd_unit_exists "$podunit" || { error "Unidad de pod no encontrada: $podunit"; exit 1; }
                log "Reiniciando pod ($podunit)..."
                systemctl restart "$podunit" && success "restart $podunit OK" || {
                    error "systemctl restart falló: $podunit"; exit 1
                }
            else
                systemctl_restart_one "$1"
            fi
            ;;

        logs)
            local follow=()
            [[ "${1:-}" == "-f" ]] && { follow=(-f); shift; }
            [[ -n "${1:-}" ]] || { error "Uso: logs [-f] <contenedor>"; exit 1; }
            podman logs "${follow[@]}" "$1"
            ;;

        reset-pass)        reset_admin_password ;;
        data-generate)     generate_data ;;
        django-commands)   run_django_commands "${1:-}" ;;
        backup)            backup_database ;;
        restore)           restore_database ;;
        psql)              open_psql "${1:-}" ;;
        psql-reindex)      psql_reindex ;;
        sngrep)            run_sngrep ;;
        asterisk_cli)      run_asterisk_cli ;;
        terminal)
            if [[ "$raw" == --django_bash ]]; then
                open_terminal "$CN_OMLAPP"
            else
                open_terminal "${1:-}"
            fi
            ;;
        inbound-call|generate_call) send_inbound_call "${1:-}" ;;
        hangup-pstn)       hangup_pstn ;;
        dialer-call)       dialer_call_test "${1:-}" ;;
        manual-call)       manual_call_test "$@" ;;
        env)
            [[ -f "$DJANGO_ENV" ]] && grep -h '^[A-Z_][A-Z0-9_]*=' "$DJANGO_ENV" | head -20 || warning "No $DJANGO_ENV"
            ;;
        version)           podman version ;;
        clean)             clean_system ;;
        clean-all)         clean_all ;;
        restart-core)      restart_core ;;
        restart-all)       restart_all ;;
        redis-sync|regenerar-asterisk) redis_sync ;;
        dialer-sync)       dialer_sync ;;
        redis-clean)       redis_clean_cache ;;
        show-bucket)       show_bucket ;;
        redis-cli)         redis_cli_launch ;;
        kamailio-logs)     require_container_running "$CN_KAMAILIO_WEBRTC" && podman logs -f "$CN_KAMAILIO_WEBRTC" ;;
        websockets-logs)   require_container_running "$CN_WEBSOCKET" && podman logs -f "$CN_WEBSOCKET" ;;
        nginx-t)           require_container_running "$CN_NGINX" && podman exec -it "$CN_NGINX" nginx -T ;;
        django-shell)      require_container_running "$CN_OMLAPP" && podman exec -it "$CN_OMLAPP" python3 "$MANAGE_PY" shell ;;
        fastagi-bash)      open_terminal "$CN_FASTAGI" ;;
        asterisk-bash)     open_terminal "$CN_ACD_SERVER" ;;
        rtpengine-bash)    open_terminal "$CN_RTPENGINE" ;;
        rtpengine-conf)    require_container_running "$CN_RTPENGINE" && podman exec -it "$CN_RTPENGINE" cat /etc/rtpengine.conf ;;
        clean-redis-volume) clean_redis_volume ;;
        pod-restart|pod_restart) pod_restart "${1:-}" ;;

        *)
            error "Comando desconocido: $raw"
            show_help
            exit 1
            ;;
    esac
}

main "$@"
{% endraw %}
