#!/usr/bin/env bash
# scripts/control.sh - Instance control functions (start/stop/restart/logs)

manage_instance() {
    local action="$1"
    local instance_name="$2"
    local instance_dir="${NANOBOT_INSTANCES}/${instance_name}"
    
    if [[ ! -d "$instance_dir" ]]; then
        print_error "Instance not found: $instance_name"
        return 1
    fi
    
    cd "$instance_dir"
    
    case $action in
        start)
            print_step "Starting instance $instance_name..."
            docker compose up -d
            ;;
        stop)
            print_step "Stopping instance $instance_name..."
            docker compose down
            ;;
        restart)
            print_step "Restarting instance $instance_name..."
            docker compose restart 2>/dev/null || {
                print_warning "No container running. Starting..."
                docker compose up -d
            }
            ;;
        logs)
            print_step "Instance logs $instance_name..."
            local running
            running=$(docker compose ps --format "{{.Names}}" 2>/dev/null)
            if [[ -z "$running" ]]; then
                print_warning "Instance not running. Starting..."
                docker compose up -d
            fi
            docker compose logs -f --tail 50
            ;;
        status)
            print_step "Instance status $instance_name..."
            docker compose run --rm --entrypoint nanobot nanobot status
            ;;
        login-whatsapp)
            print_step "Connecting WhatsApp for $instance_name..."
            docker compose down 2>/dev/null || true
            whatsapp_login_flow "$(pwd)"
            if [[ -f "$(pwd)/bridge/dist/index.js" ]]; then
                print_step "Starting instance..."
                docker compose up -d
                print_success "Instance started!"
            fi
            ;;
        chat)
            print_step "Starting chat CLI for $instance_name..."
            docker compose run --rm --entrypoint nanobot nanobot agent
            ;;
        update)
            print_step "Updating instance $instance_name..."
            docker compose down
            docker compose up -d
            ;;
        *)
            print_error "Unknown action: $action"
            ;;
    esac
    
    cd - > /dev/null 2>&1
}

manage_all_instances() {
    local action="$1"
    
    print_header
    print_step "Managing all instances..."
    
    if [[ ! -d "$NANOBOT_INSTANCES" ]]; then
        print_warning "Instances directory not found."
        return 1
    fi
    
    for dir in "$NANOBOT_INSTANCES"/*/; do
        if [[ -f "${dir}docker-compose.yml" ]]; then
            local instance_name
            instance_name=$(basename "$dir")
            echo
            print_step "Processing $instance_name..."
            manage_instance "$action" "$instance_name"
        fi
    done
}
