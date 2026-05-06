#!/usr/bin/env bash
# =============================================================================
# OmniLeads Stack Management Script
# =============================================================================
# Author:      DevOps Expert
# Description: Manage the entire OmniLeads Docker-based stack
# Usage:       ./manage.sh <command> [arguments]
# =============================================================================

set -euo pipefail

# -----------------------------------------------------------------------------
# Color Configuration
# -----------------------------------------------------------------------------
RED=''; GREEN=''; YELLOW=''; BLUE=''; PURPLE=''; CYAN=''; BOLD=''; NC=''

setup_colors() {
    if [[ -t 1 ]] && command -v tput &>/dev/null && [[ "$(tput colors)" -ge 8 ]]; then
        RED="$(tput setaf 1)";   GREEN="$(tput setaf 2)";  YELLOW="$(tput setaf 3)"
        BLUE="$(tput setaf 4)";  PURPLE="$(tput setaf 5)"; CYAN="$(tput setaf 6)"
        BOLD="$(tput bold)";     NC="$(tput sgr0)"
    fi
}

# -----------------------------------------------------------------------------
# Logging Helpers
# -----------------------------------------------------------------------------
log()     { echo -e "${BOLD}[$(date +'%H:%M:%S')]${NC} $1"; }
success() { echo -e "${GREEN}✔ $1${NC}"; }
warning() { echo -e "${YELLOW}⚠ $1${NC}"; }
error()   { echo -e "${RED}✖ $1${NC}"; }
info()    { echo -e "${CYAN}ℹ $1${NC}"; }

# -----------------------------------------------------------------------------
# Global Variables
# -----------------------------------------------------------------------------
COMPOSE_FILE="docker-compose.yml"
ENV_FILE=".env"
PROJECT_NAME=$(basename "$(pwd)")

DC_CMD=()           # Will be either `docker-compose` or `docker compose`
DEPENDENCIES=(docker jq)

# -----------------------------------------------------------------------------
# Dependency and File Checks
# -----------------------------------------------------------------------------
check_dependencies() {
    local missing=()
    for dep in "${DEPENDENCIES[@]}"; do
        if ! command -v "$dep" &>/dev/null; then
            missing+=("$dep")
        fi
    done
    if (( ${#missing[@]} )); then
        error "Missing dependencies: ${missing[*]}"
        exit 1
    fi

    # Choose compose command
    if command -v docker-compose &>/dev/null; then
        DC_CMD=(docker-compose)
    else
        DC_CMD=(docker compose)
    fi
}

check_required_files() {
    [[ -f "$COMPOSE_FILE" ]] || { error "Cannot find $COMPOSE_FILE"; exit 1; }
    [[ -f "$ENV_FILE" ]] || warning "$ENV_FILE not found — some variables may be undefined"
}

docker_compose() {
    "${DC_CMD[@]}" --project-name "$PROJECT_NAME" "$@"
}

# -----------------------------------------------------------------------------
# Enhanced Health Check
# -----------------------------------------------------------------------------
check_health() {
    info "Checking health of critical services..."
    local critical=(postgresql redis minio omlapp nginx acd)
    local unhealthy=()

    for svc in "${critical[@]}"; do
        local cid status health
        cid=$(docker_compose ps -q "$svc" 2>/dev/null || echo "")
        if [[ -n "$cid" ]]; then
            status=$(docker inspect --format '{{.State.Status}}' "$cid")
            health=$(docker inspect --format '{{.State.Health.Status}}' "$cid" 2>/dev/null || echo "none")
            printf "  %-12s " "$svc:"
            case "$status/$health" in
                running/healthy)   echo -e "${GREEN}✔ healthy${NC}" ;;
                running/unhealthy) echo -e "${RED}✖ unhealthy${NC}"; unhealthy+=("$svc") ;;
                running/*)         echo -e "${YELLOW}● running${NC}" ;;
                exited/*)          echo -e "${PURPLE}◯ stopped${NC}"; unhealthy+=("$svc") ;;
                *)                 echo -e "${RED}? $status${NC}"; unhealthy+=("$svc") ;;
            esac
        else
            printf "  %-12s ${RED}✖ not found${NC}\n" "$svc"
            unhealthy+=("$svc")
        fi
    done

    if (( ${#unhealthy[@]} )); then
        error "Issues detected in: ${unhealthy[*]}"
        return 1
    else
        success "All critical services are healthy"
    fi
}

# -----------------------------------------------------------------------------
# Show Stack Status & Validate Execution (Status + Health)
# -----------------------------------------------------------------------------
show_status() {
    echo
    info "Container Status:"
    docker_compose ps --format table || docker_compose ps

    echo
    info "Real-Time Metrics (averages):"
    local tmp_cpu tmp_mem tmp_count
    tmp_cpu=$(mktemp); tmp_mem=$(mktemp); tmp_count=$(mktemp)
    echo 0 > "$tmp_cpu"; echo 0 > "$tmp_mem"; echo 0 > "$tmp_count"

    local containers
    mapfile -t containers < <(
        docker ps --filter "label=com.docker.compose.project=$PROJECT_NAME" --format '{{.Names}}'
    )

    if (( ${#containers[@]} )); then
        docker stats --no-stream --format "{{.Name}}\t{{.CPUPerc}}\t{{.MemPerc}}" "${containers[@]}" \
        | while IFS=$'\t' read -r name cpu mem; do
            cpu=${cpu%%%}; mem=${mem%%%}
            echo "$(awk "BEGIN{printf \"%.2f\", $cpu + $(<"$tmp_cpu")}")" > "$tmp_cpu"
            echo "$(awk "BEGIN{printf \"%.2f\", $mem + $(<"$tmp_mem")}")" > "$tmp_mem"
            echo "$(( $(<"$tmp_count") + 1 ))" > "$tmp_count"
        done

        local total_cpu total_mem count avg_cpu avg_mem
        total_cpu=$(<"$tmp_cpu"); total_mem=$(<"$tmp_mem"); count=$(<"$tmp_count")
        rm -f "$tmp_cpu" "$tmp_mem" "$tmp_count"

        avg_cpu=$(awk "BEGIN{printf \"%.1f\", $total_cpu/$count}")
        avg_mem=$(awk "BEGIN{printf \"%.1f\", $total_mem/$count}")

        printf "  CPU Average    : %s%%\n" "$avg_cpu"
        printf "  Memory Average : %s%%\n" "$avg_mem"
        printf "  Active Services: %d\n" "$count"
    else
        warning "No running containers for project '$PROJECT_NAME'"
    fi

    show_raw_stats

    echo
    info "Validating container health and states..."
    
    local all_cids
    all_cids=$(docker_compose ps -q)

    if [[ -z "$all_cids" ]]; then
        error "SYSTEM DOWN: No containers found defined for project '$PROJECT_NAME'."
        return 1
    fi

    local stopped_containers=()
    local unhealthy_containers=()
    local starting_containers=()

    for cid in $all_cids; do
        local c_name c_info state health
        
        c_name=$(docker inspect --format '{{.Name}}' "$cid" | sed 's/^\///')
        c_info=$(docker inspect --format '{{.State.Status}}:{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' "$cid")
        
        state=${c_info%:*}
        health=${c_info#*:}

        if [[ "$state" != "running" ]]; then
            stopped_containers+=("$c_name (Status: $state)")
        elif [[ "$health" == "unhealthy" ]]; then
            unhealthy_containers+=("$c_name (Health: $health)")
        elif [[ "$health" == "starting" ]]; then
            starting_containers+=("$c_name")
        fi
    done

    local has_errors=0

    if (( ${#stopped_containers[@]} )); then
        echo
        error "CRITICAL: The following containers are NOT running:"
        for item in "${stopped_containers[@]}"; do echo -e "  ${RED}✖ ${item}${NC}"; done
        has_errors=1
    fi

    if (( ${#unhealthy_containers[@]} )); then
        echo
        error "CRITICAL: The following containers are UNHEALTHY:"
        for item in "${unhealthy_containers[@]}"; do echo -e "  ${RED}✖ ${item}${NC}"; done
        has_errors=1
    fi

    if (( ${#starting_containers[@]} )); then
        echo
        warning "The following containers are still STARTING (check again in a few seconds):"
        for item in "${starting_containers[@]}"; do echo -e "  ${YELLOW}⏳ ${item}${NC}"; done
    fi

    if (( has_errors == 1 )); then
        echo
        error "System check FAILED."
        return 1
    else
        echo
        success "SYSTEM INTEGRITY OK: All services are running and healthy."
        return 0
    fi
}

# -----------------------------------------------------------------------------
# Raw Docker Stats Display
# -----------------------------------------------------------------------------
show_raw_stats() {
    echo
    info "Resource Usage:"
    mapfile -t containers < <(
        docker ps --filter "label=com.docker.compose.project=$PROJECT_NAME" --format "{{.Names}}"
    )
    if (( ${#containers[@]} )); then
        docker stats --no-stream --format "table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.NetIO}}" "${containers[@]}"
    else
        warning "No running containers for project '$PROJECT_NAME'"
    fi
}

# -----------------------------------------------------------------------------
# Reset admin Password
# -----------------------------------------------------------------------------
reset_admin_password() {
    docker_compose exec -T omlapp \
        python3 manage.py cambiar_admin_password || {
        error "Failed to reset admin password"
        exit 1
    }
}

# -----------------------------------------------------------------------------
# Backup & Restore
# -----------------------------------------------------------------------------
backup_database() {
    docker run --rm --env-file "$ENV_FILE" backup_restore:latest python backup.py || {
        error "Failed to backup database"
        exit 1
    }
}

restore_database() {
    docker run --rm --env-file "$ENV_FILE" backup_restore:latest python restore.py || {
        error "Failed to restore database"
        exit 1
    }
}

# -----------------------------------------------------------------------------
# Init Environment data example
# -----------------------------------------------------------------------------
generate_data() {
    docker_compose exec -T omlapp \
        python3 manage.py inicializar_entorno || {
        error "Failed to generate example data"
        exit 1
    }
}

# -----------------------------------------------------------------------------
# Run Django Commands (on-demand)
# -----------------------------------------------------------------------------
run_django_commands() {
    log "Ejecutando django-commands (on-demand)..."
    
    # Verificar que los servicios dependientes estén corriendo
    local required_services=(postgresql redis minio)
    local missing_services=()
    
    for svc in "${required_services[@]}"; do
        if ! docker_compose ps -q "$svc" &>/dev/null; then
            missing_services+=("$svc")
        fi
    done
    
    if (( ${#missing_services[@]} )); then
        error "Los siguientes servicios requeridos no están corriendo: ${missing_services[*]}"
        info "Por favor, inicia los servicios primero con: ./oml_manage.sh up -d"
        exit 1
    fi
    
    # Ejecutar django-commands con el perfil activado
    docker_compose --profile django-commands run --rm django-commands || {
        error "Failed to execute django-commands"
        exit 1
    }
    success "django-commands ejecutado exitosamente"
}

# -----------------------------------------------------------------------------
# Wait for services to be healthy (for up + commands flow)
# -----------------------------------------------------------------------------
wait_for_services_healthy() {
    local timeout_sec="${1:-120}"
    shift
    local services=("$@")
    local start_ts end_ts elapsed

    if (( ${#services[@]} == 0 )); then
        services=(postgresql redis minio)
    fi

    log "Esperando que los servicios estén healthy (timeout: ${timeout_sec}s)..."
    start_ts=$(date +%s)

    while true; do
        local all_healthy=1
        end_ts=$(date +%s)
        elapsed=$(( end_ts - start_ts ))
        if (( elapsed >= timeout_sec )); then
            error "Timeout esperando servicios healthy: ${services[*]}"
            return 1
        fi

        for svc in "${services[@]}"; do
            local cid health
            cid=$(docker_compose ps -q "$svc" 2>/dev/null || echo "")
            if [[ -z "$cid" ]]; then
                all_healthy=0
                break
            fi
            health=$(docker inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' "$cid" 2>/dev/null || echo "none")
            if [[ "$health" == "healthy" ]]; then
                continue
            fi
            if [[ "$health" == "none" ]]; then
                local status
                status=$(docker inspect --format '{{.State.Status}}' "$cid" 2>/dev/null || echo "")
                if [[ "$status" != "running" ]]; then
                    all_healthy=0
                    break
                fi
                continue
            fi
            all_healthy=0
            break
        done

        if (( all_healthy == 1 )); then
            success "Servicios listos: ${services[*]}"
            return 0
        fi
        sleep 3
    done
}

# -----------------------------------------------------------------------------
# Build VueJS Assets
# -----------------------------------------------------------------------------
build_vuejs() {
    if ! docker_compose ps -q vue-cli &>/dev/null; then
        error "VueJS CLI service is not running. Please start it first."
        exit 1
    fi
    docker_compose exec -T vue-cli npm install
    docker_compose exec -T vue-cli npm run build
}

# -----------------------------------------------------------------------------
# Cleanup Routines
# -----------------------------------------------------------------------------
clean_system() {
    log "Pruning stopped containers..."; docker container prune -f
    log "Pruning unused images...";     docker image prune -f
    log "Pruning unused volumes...";    docker volume prune -f
    log "Pruning unused networks...";   docker network prune -f
    success "Basic cleanup completed"
}

clean_all() {
    warning "This will remove ALL containers, images, volumes, and networks."
    read -rp "Continue? (y/N): " ans
    if [[ "$ans" =~ ^[Yy]$ ]]; then
        docker system prune -a -f --volumes
        success "Full system cleanup done"
    else
        info "Cleanup canceled"
    fi
}

send_call() {
    local telephone="${1:-}"
    if [[ -z "$telephone" ]]; then
        error "Missing telephone argument."
        info "Usage: ./manage.sh inbound-call <telephone>"
        info "Example: ./manage.sh inbound-call 999"
        exit 1
    fi
    
    if ! docker_compose ps -q pbxemulator &>/dev/null; then
        error "PBX Emulator service is not running. Please start it first."
        exit 1
    fi
    # Nota: Asegurarse de que el argumento se pasa como texto
    docker_compose exec -T pbxemulator sipp -sn uac pbxemulator:5070 -s "999$telephone" -m 1 -r 1 -d 60000 -l 1 || {
        error "Failed to send call"
        exit 1
    }
}

hangup_all_pstn_emulator_calls() {
    if ! docker_compose ps -q pbxemulator &>/dev/null; then
        error "PBX Emulator service is not running. Please start it first."
        exit 1
    fi
    docker_compose exec -T pbxemulator asterisk -rx "channel request hangup all" || {
        error "Failed to send call"
        exit 1
    }
}

trigger_dialer_test() {
    # Lógica de argumentos:
    # $1 = ID Campaña (Obligatorio)
    local id_camp="${1:-}"

    # Validation: Ensure Campaign ID is present
    if [[ -z "$id_camp" ]]; then
        error "Missing Campaign ID argument."
        info "Usage:   ./manage.sh dialer-call <id_camp>"
        info "Example: ./manage.sh dialer-call 5"
        exit 1
    fi

    log "Executing dialer test call..."
    
    # Executing the python script inside dialer-process-campaign
    docker_compose exec -T dialer-process-campaign \
        python3 call_test_dialer.py "$id_camp" || {
        error "Failed to execute call_test_dialer.py"
        exit 1
    }
    success "Dialer call command executed successfully."
}

# -----------------------------------------------------------------------------
# Open sngrep in acd-server (SIP debugging)
# -----------------------------------------------------------------------------
run_sngrep() {
    if ! docker_compose ps -q acd-server &>/dev/null; then
        error "Service 'acd-server' is not running or does not exist."
        exit 1
    fi
    log "Opening sngrep in 'acd-server'..."
    docker_compose exec -it acd-server sngrep
}

# -----------------------------------------------------------------------------
# Open Asterisk CLI in acd-server (interactive console)
# -----------------------------------------------------------------------------
run_asterisk_cli() {
    if ! docker_compose ps -q acd-server &>/dev/null; then
        error "Service 'acd-server' is not running or does not exist."
        exit 1
    fi
    log "Opening Asterisk CLI in 'acd-server'..."
    docker_compose exec -it acd-server asterisk -rvvvvv
}

# -----------------------------------------------------------------------------
# Open PostgreSQL psql prompt (interactive)
# -----------------------------------------------------------------------------
open_psql() {
    local db_user="${1:-}"

    if [[ -z "$db_user" ]]; then
        error "Missing database/user argument."
        info "Usage: ./oml_manage.sh --psql <db_user>"
        exit 1
    fi

    if ! docker_compose ps -q postgresql &>/dev/null; then
        error "Service 'postgresql' is not running or does not exist."
        exit 1
    fi

    log "Opening psql on service 'postgresql' as user '$db_user'..."
    docker_compose exec -it postgresql psql -U "$db_user"
}

# -----------------------------------------------------------------------------
# Trigger Manual Test
# -----------------------------------------------------------------------------
trigger_manual_test() {
    # Lógica de argumentos:
    # $1 = ID Campaña (Obligatorio)
    # $2 = Teléfono (Opcional, defecto: 123456784)
    # $3 = ID Cliente (Opcional, defecto: 1)
    
    local id_camp="${2:-9}"
    local telephone="${1:-123456784}"
    local id_customer="${3:-1}"
    local id_agent="${4:-0}"

    # Validation: Ensure Campaign ID is present
    if [[ -z "$id_camp" ]]; then
        error "Missing Campaign ID argument."
        info "Usage:   ./manage.sh dialer-call <id_camp> [telephone] [id_customer]"
        info "Example: ./manage.sh dialer-call 5"
        info "Defaults used if omitted: Tel=$telephone, Cust=$id_customer"
        exit 1
    fi

    # Check correct container (Updated to dialer-acd-dialplan)
    if ! docker_compose ps -q dialer-acd-dialplan &>/dev/null; then
        error "Service 'dialer-acd-dialplan' is not running. Please start it first."
        exit 1
    fi

    log "Executing dialer test call..."
    info "Parameters -> Phone: $telephone | Camp: $id_camp | Cust: $id_customer"
    
    # Executing the python script inside dialer-acd-dialplan
    # Note: Python script order is: phone camp customer
    docker_compose exec -T dialer-acd-dialplan \
        python3 call_test_dialer.py "$telephone" "$id_camp" "$id_customer" "$id_agent" 1 1 15 15 || {
        error "Failed to execute call_test_dialer.py"
        exit 1
    }
    success "Dialer call command executed successfully."
}

# -----------------------------------------------------------------------------
# Rebuild Services
# -----------------------------------------------------------------------------
rebuild_services() {
    local service_name=""
    local platform=""
    local build_args=()
    
    # Parse arguments
    for arg in "$@"; do
        if [[ "$arg" =~ ^--platform=(.+)$ ]]; then
            platform="${BASH_REMATCH[1]}"
        elif [[ "$arg" != --platform=* ]]; then
            build_args+=("$arg")
            if [[ -z "$service_name" ]]; then
                service_name="$arg"
            fi
        fi
    done
    
    # Set DOCKER_PLATFORM environment variable if platform flag was provided
    if [[ -n "$platform" ]]; then
        export DOCKER_PLATFORM="$platform"
        log "Building for platform: $platform"
    fi
    
    if [[ -n "$service_name" ]]; then
        log "Rebuilding image for $service_name..."
        docker_compose build "${build_args[@]}"
        docker_compose up -d "$service_name"
        success "Service '$service_name' rebuilt and restarted"
    else
        log "Rebuilding all images cache..."
        docker_compose build "${build_args[@]}"
        success "All images rebuilt"
    fi
    
    # Unset DOCKER_PLATFORM if it was set
    if [[ -n "$platform" ]]; then
        unset DOCKER_PLATFORM
    fi
}

# -----------------------------------------------------------------------------
# Open Interactive Terminal
# -----------------------------------------------------------------------------
open_terminal() {
    local service="${1:-}"

    if [[ -z "$service" ]]; then
        error "You must specify a service name."
        info "Usage: ./manage.sh terminal <service_name>"
        echo
        info "Available running services:"
        docker_compose ps --services --filter "status=running"
        return 1
    fi

    if ! docker_compose ps -q "$service" &>/dev/null; then
        error "Service '$service' is not running or does not exist."
        return 1
    fi

    log "Opening interactive shell in '$service'..."
    docker_compose exec "$service" bash 2>/dev/null || {
        warning "'bash' not found inside container. Falling back to 'sh'..."
        docker_compose exec "$service" sh
    }
}

# -----------------------------------------------------------------------------
# Compose Version Helper
# -----------------------------------------------------------------------------
compose_version() {
    if command -v docker-compose &>/dev/null; then
        docker-compose version
    else
        docker compose version
    fi
}

# -----------------------------------------------------------------------------
# Display Help
# -----------------------------------------------------------------------------
show_help() {
    cat <<-EOF

    OmniLeads Stack Management Script

    Usage: ./manage.sh <command> [arguments]

    Commands:
      up [ -d ] [ commands ]  Start all services (use -d for detached). If 'commands'
                              is given, runs django-commands before bringing up the stack.
      down [ -v ]        Stop and remove containers (use -v to remove volumes)
      pull [svc]         Pull images (all or specific service)
      restart [svc]      Restart all or a specific service
      stop    [svc]      Stop all or a specific service
      start   [svc]      Start all or a specific service
      logs    [-f] [svc] Show or follow logs
      status             Show container status + averages + raw stats
      health             Perform health check of critical services
      build-vuejs        Build VueJS assets
      clean              Prune stopped containers, unused images/volumes/networks
      clean-all          Full system prune (including volumes and images)
      reset-pass         Reset admin password as admin admin
      force-recreate     Force-recreate services without cache
      data-generate      Generate example data in the database
      django-commands    Execute django-commands container (on-demand)
      rebuild [svc]      Rebuild one or all service images
      psql <db_user>   Open interactive psql in postgresql container (psql -U <db_user>)
      sngrep            Open sngrep in acd-server container (SIP debugging)
      asterisk_cli      Open Asterisk CLI in acd-server (asterisk -rvvvvv)
      backup             Backup PostgreSQL database
      restore            Restore PostgreSQL database from backup
      env                Display first 20 env vars from .env
      inbound-call       Send a test call using the PBX-Emulator
      dialer-call        Trigger 'call_test_dialer.py' (Usage: tel id_camp id_cust)
      manual-call        Trigger 'call_test_manual.py' (Usage: tel id_camp id_cust)
      hangup-pstn        Hangup all PSTN calls using the PBX-Emulator
      version            Show Docker & Compose versions
      help               Display this help message

EOF
}

# -----------------------------------------------------------------------------
# Main Control Flow
# -----------------------------------------------------------------------------
main() {
    setup_colors
    check_dependencies
    check_required_files

    case "${1:-}" in
        up)
            shift
            run_commands_first=0
            UP_ARGS=()
            for arg in "$@"; do
                if [[ "$arg" == "commands" ]]; then
                    run_commands_first=1
                else
                    UP_ARGS+=("$arg")
                fi
            done
            if (( run_commands_first )); then
                log "Levantando dependencias (postgresql, redis, minio)..."
                docker_compose up -d postgresql redis minio
                wait_for_services_healthy 120 postgresql redis minio || exit 1
                run_django_commands
                log "Levantando el resto del stack..."
                docker_compose up -d "${UP_ARGS[@]}"
            else
                log "Starting services..."; docker_compose up "$@"
            fi
            ;;
        down)           shift; log "Stopping stack..."; docker_compose down "$@" ;;
        pull)           shift; log "Pulling images..."; docker_compose pull "$@" ;;
        restart)        shift; log "Restarting..."; docker_compose restart "$@" ;;
        stop)           shift; log "Stopping..."; docker_compose stop "$@" ;;
        start)          shift; log "Starting..."; docker_compose start "$@" ;;
        force-recreate) shift; log "Force-recreating..."; docker_compose up -d --force-recreate "$@" ;;
        logs)           shift; docker_compose logs "$@" ;;
        status)         show_status ;;
        reset-pass)     reset_admin_password ;;
        data-generate)  generate_data ;;
        django-commands) run_django_commands ;;
        build-vuejs)    build_vuejs ;;
        health)         check_health ;;
        clean)          clean_system ;;
        clean-all)      clean_all ;;
        inbound-call)   shift; send_call "${1:-}" ;;
        dialer-call)    shift; trigger_dialer_test "$@" ;;
        manual-call)    shift; trigger_manual_test "$@" ;;
        hangup-pstn)    hangup_all_pstn_emulator_calls ;;
        backup)         backup_database ;;
        restore)        restore_database ;;
        terminal)       shift; open_terminal "${1:-}" ;;
        rebuild)        shift; rebuild_services "${1:-}" ;;
        psql)           shift; open_psql "${1:-}" ;;
        sngrep)         run_sngrep ;;
        asterisk_cli)   run_asterisk_cli ;;
        env)            if [[ -f "$ENV_FILE" ]]; then grep -h '^[A-Z_]\+=' "$ENV_FILE" | head -20; else warning ".env not found"; fi ;;
        version)        printf "Docker: %s\n" "$(docker --version)"; printf "Compose: %s\n" "$(compose_version)"; ;;
        help|--help|"" ) show_help ;;
        *)              error "Unknown command: $1"; show_help; exit 1 ;;
    esac
}

# -----------------------------------------------------------------------------
# Trap for Interrupt
# -----------------------------------------------------------------------------
trap 'echo; warning "Operation interrupted"; exit 130' INT

# Execute Main
main "$@"