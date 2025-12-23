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
# Human-Readable Byte Formatting (unused helper kept)
# -----------------------------------------------------------------------------
format_bytes() {
    local bytes=${1//[!0-9]/}
    if (( bytes == 0 )); then
        echo "0B"; return
    fi
    local units=(B KB MB GB TB) i=0
    while (( bytes >= 1024 && i < ${#units[@]}-1 )); do
        bytes=$(awk "BEGIN{printf \"%.1f\", $bytes/1024}")
        ((i++))
    done
    echo "${bytes}${units[i]}"
}

# -----------------------------------------------------------------------------
# Enhanced Health Check
# -----------------------------------------------------------------------------
check_health() {
    info "Checking health of critical services..."
    local critical=(postgresql redis minio django-app nginx acd)
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
# Show Stack Status & Averages
# -----------------------------------------------------------------------------
# -----------------------------------------------------------------------------
# Show Stack Status & Validate Execution (Status + Health)
# -----------------------------------------------------------------------------
show_status() {
    echo
    info "Container Status:"
    docker_compose ps --format table || docker_compose ps

    # --- (Mantengo tu bloque de métricas original para no perder funcionalidad) ---
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

    # -------------------------------------------------------------------------
    # NEW: DEEP HEALTH VALIDATION CHECK
    # -------------------------------------------------------------------------
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
        
        # Truco de experto: Extraemos estado y salud en una sola llamada usando condicionales de Go templates
        # Si no tiene healthcheck, devuelve 'none'
        c_info=$(docker inspect --format '{{.State.Status}}:{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' "$cid")
        
        state=${c_info%:*}   # Todo antes de los dos puntos
        health=${c_info#*:}  # Todo después de los dos puntos

        if [[ "$state" != "running" ]]; then
            stopped_containers+=("$c_name (Status: $state)")
        elif [[ "$health" == "unhealthy" ]]; then
            unhealthy_containers+=("$c_name (Health: $health)")
        elif [[ "$health" == "starting" ]]; then
            # Opcional: Puedes decidir si 'starting' es un error o un warning. 
            # Aquí lo guardamos para informar, pero no romperemos ejecución drásticamente si no quieres.
            starting_containers+=("$c_name")
        fi
    done

    local has_errors=0

    # Reporte de Contenedores Detenidos
    if (( ${#stopped_containers[@]} )); then
        echo
        error "CRITICAL: The following containers are NOT running:"
        for item in "${stopped_containers[@]}"; do echo -e "  ${RED}✖ ${item}${NC}"; done
        has_errors=1
    fi

    # Reporte de Contenedores Unhealthy (Corren, pero fallan internamente)
    if (( ${#unhealthy_containers[@]} )); then
        echo
        error "CRITICAL: The following containers are UNHEALTHY:"
        for item in "${unhealthy_containers[@]}"; do echo -e "  ${RED}✖ ${item}${NC}"; done
        has_errors=1
    fi

    # Advertencia de iniciando (no es error crítico, pero el sistema no está listo 100%)
    if (( ${#starting_containers[@]} )); then
        echo
        warning "The following containers are still STARTING (check again in a few seconds):"
        for item in "${starting_containers[@]}"; do echo -e "  ${YELLOW}⏳ ${item}${NC}"; done
        # Dependiendo de tu criterio, esto podría ser un error. 
        # Si quieres que el script falle si algo está 'starting', descomenta la siguiente línea:
        # has_errors=1 
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
    docker_compose exec -T django-app \
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
    docker_compose exec -T django-app \
        python3 manage.py inicializar_entorno || {
        error "Failed to generate example data"
        exit 1
    }
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
    if ! docker_compose ps -q pbxemulator &>/dev/null; then
        error "PBX Emulator service is not running. Please start it first."
        exit 1
    fi
    docker_compose exec -T pbxemulator sipp -sn uac pbxemulator:5070 -s test -m 1 -r 1 -d 60000 -l 1 || {
        error "Failed to send call"
        exit 1
    }
}

# -----------------------------------------------------------------------------
# Rebuild Services
# -----------------------------------------------------------------------------
rebuild_services() {
    if [[ -n "${1:-}" ]]; then
        log "Rebuilding image for $1..."
        docker_compose build "$1"
        docker_compose up -d "$1"
        success "Service '$1' rebuilt and restarted"
    else
        log "Rebuilding all images cache..."
        docker_compose build
        success "All images rebuilt"
    fi
}

# -----------------------------------------------------------------------------
# Open Interactive Terminal
# -----------------------------------------------------------------------------
open_terminal() {
    local service="${1:-}"

    # 1. Validar que el usuario ingresó un nombre de servicio
    if [[ -z "$service" ]]; then
        error "You must specify a service name."
        info "Usage: ./manage.sh terminal <service_name>"
        echo
        info "Available running services:"
        docker_compose ps --services --filter "status=running"
        return 1
    fi

    # 2. Validar que el servicio esté corriendo realmente
    if ! docker_compose ps -q "$service" &>/dev/null; then
        error "Service '$service' is not running or does not exist."
        return 1
    fi

    log "Opening interactive shell in '$service'..."

    # 3. Intentar BASH, si falla (exit code != 0), intentar SH
    #    El '||' ejecuta el segundo comando solo si el primero falla.
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
      up [ -d ]          Start all services (use -d for detached)
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
      rebuild [svc]      Rebuild one or all service images
      backup             Backup PostgreSQL database
      restore            Restore PostgreSQL database from backup
      env                Display first 20 env vars from .env
      send-call          Send a test call using the PBX-Emulator
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
        up)             shift; log "Starting services..."; docker_compose up "$@" ;;
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
        build-vuejs)    build_vuejs ;;   # CLI mantiene el guion; función interna usa guion_bajo
        health)         check_health ;;
        clean)          clean_system ;;
        clean-all)      clean_all ;;
        send-call)      send_call ;;
        backup)         backup_database ;;
        restore)        restore_database ;;
        terminal)       shift; open_terminal "${1:-}" ;;
        rebuild)        shift; rebuild_services "${1:-}" ;;
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
