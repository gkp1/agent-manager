#!/usr/bin/env bash
# scripts/instance.sh - Instance creation and management functions

create_docker_instance() {
    print_header
    print_step "Creating new Docker instance..."
    
    read -p "Instance name (ex: wa1, wa2, telegram1): " instance_name

    echo
    echo "Available channels:"
    echo "  1) whatsapp"
    echo "  2) telegram"
    echo "  3) discord"
    echo "  4) feishu"
    echo "  5) slack"
    echo "  6) matrix"
    echo "  7) email"
    read -p "Choose channel [1 - whatsapp]: " channel_choice
    channel=$(channel_from_number "${channel_choice:-1}")

    local provider
    provider=$(select_llm_provider_interactive)
    
    local env_key
    env_key=$(get_provider_env_key "$provider")
    local api_key
    local api_base=""
    
    case $provider in
        openrouter)
            read -p "OpenRouter API key (sk-or-v1-...): " api_key
            ;;
        openai)
            read -p "OpenAI API key (sk-...): " api_key
            ;;
        anthropic)
            read -p "Anthropic API key (sk-ant-...): " api_key
            ;;
        deepseek)
            read -p "DeepSeek API key (sk-...): " api_key
            ;;
        groq)
            read -p "GroQ API key (gsk_...): " api_key
            ;;
        custom)
            read -p "API key: " api_key
            read -p "API base URL (ex: http://localhost:8000/v1): " api_base
            ;;
    esac

    local default_model
    default_model=$(get_provider_default_model "$provider")
    local model
    model=$(select_model_interactive "$provider" "$default_model")

    read -p "External port (ex: 18791, 18792): " port
    read -p "User ID for allowFrom: " user_id
    
    local instance_dir="${NANOBOT_INSTANCES}/${instance_name}"
    mkdir -p "$instance_dir"
    
    create_config_json "$instance_dir" "$channel" "$api_key" "$user_id" "$model" "$provider" "$api_base"
    create_docker_compose "$instance_dir" "$instance_name" "$port" "$channel"
    
    print_success "Instance $instance_name created in $instance_dir!"
    echo
    print_info "Next steps:"
    echo "1. cd $instance_dir"
    if [[ "$channel" == "whatsapp" ]]; then
        echo "2. $SCRIPT_NAME login $instance_name"
        echo "3. $SCRIPT_NAME start $instance_name"
    else
        echo "2. docker compose up -d"
    fi
}

create_config_json() {
    local dir="$1"
    local channel="$2"
    local api_key="$3"
    local user_id="$4"
    local model="${5:-moonshotai/kimi-k2.5}"
    local provider="${6:-openrouter}"
    local api_base="${7:-}"

    local providers_section=""
    
    case $provider in
        openrouter)
            providers_section="\"openrouter\": {
      \"apiKey\": \"${api_key}\"
    }"
            ;;
        openai)
            providers_section="\"openai\": {
      \"apiKey\": \"${api_key}\"
    }"
            ;;
        anthropic)
            providers_section="\"anthropic\": {
      \"apiKey\": \"${api_key}\"
    }"
            ;;
        deepseek)
            providers_section="\"deepseek\": {
      \"apiKey\": \"${api_key}\"
    }"
            ;;
        groq)
            providers_section="\"groq\": {
      \"apiKey\": \"${api_key}\"
    }"
            ;;
        custom)
            if [[ -n "$api_base" ]]; then
                providers_section="\"openai\": {
      \"apiKey\": \"${api_key}\",
      \"apiBase\": \"${api_base}\"
    }"
            else
                providers_section="\"openai\": {
      \"apiKey\": \"${api_key}\"
    }"
            fi
            provider="auto"
            ;;
    esac

    cat > "${dir}/config.json" << EOF
{
  "providers": {
    ${providers_section}
  },
  "agents": {
    "defaults": {
      "model": "${model}",
      "provider": "${provider}",
      "workspace": "/root/.nanobot/workspace"
    }
  },
  "channels": {
    "${channel}": {
      "enabled": true,
      "allowFrom": ["${user_id}"]
    }
  }
}
EOF
}

create_docker_compose() {
    local dir="$1"
    local name="$2"
    local port="$3"
    local channel="$4"
    
    if [[ "$channel" == "whatsapp" ]]; then
        cat > "${dir}/docker-compose.yml" << 'EOF'
services:
  nanobot:
    image: nanobot
    container_name: nanobot-{NAME}
    restart: unless-stopped
    volumes:
      - ./config.json:/root/.nanobot/config.json
      - ./bridge:/root/.nanobot/bridge
      - ./workspace:/root/.nanobot/workspace
      - ./whatsapp-auth:/root/.nanobot/whatsapp-auth
    ports:
      - "{PORT}:18790"
    environment:
      - NANOBOT_USE_VECTOR_MEMORY=${NANOBOT_USE_VECTOR_MEMORY:-false}
      - NANOBOT_VECTOR_PROVIDER=${NANOBOT_VECTOR_PROVIDER:-sentence-transformers}
      - NANOBOT_VECTOR_MODEL=${NANOBOT_VECTOR_MODEL:-paraphrase-multilingual-mpnet-base-v2}
    entrypoint: ["/bin/bash", "-c"]
    command:
      - |
        cd /root/.nanobot/bridge && node dist/index.js &
        exec nanobot gateway
EOF
        sed -i "s/{NAME}/$name/g; s/{PORT}/$port/g" "${dir}/docker-compose.yml"
    else
        cat > "${dir}/docker-compose.yml" << EOF
services:
  nanobot:
    image: nanobot
    container_name: nanobot-${name}
    restart: unless-stopped
    volumes:
      - ./config.json:/root/.nanobot/config.json
      - ./workspace:/root/.nanobot/workspace
    ports:
      - "${port}:18790"
    environment:
      - NANOBOT_USE_VECTOR_MEMORY=${NANOBOT_USE_VECTOR_MEMORY:-false}
      - NANOBOT_VECTOR_PROVIDER=${NANOBOT_VECTOR_PROVIDER:-sentence-transformers}
      - NANOBOT_VECTOR_MODEL=${NANOBOT_VECTOR_MODEL:-paraphrase-multilingual-mpnet-base-v2}
    command: ["gateway"]
EOF
    fi
}

create_multi_instances() {
    print_header
    print_step "Multi-instance creator..."
    
    read -p "How many instances to create? " num_instances
    read -p "Name prefix (ex: wa, tg): " prefix

    echo
    echo "Available channels:"
    echo "  1) whatsapp  2) telegram  3) discord  4) feishu  5) slack  6) matrix  7) email"
    read -p "Choose channel [1]: " channel_choice
    channel=$(channel_from_number "${channel_choice:-1}")

    read -p "Initial port (ex: 18791): " start_port
    
    local provider
    provider=$(select_llm_provider_interactive)
    
    local api_key api_base=""
    case $provider in
        openrouter)
            read -p "OpenRouter API key (sk-or-v1-...): " api_key
            ;;
        openai)
            read -p "OpenAI API key (sk-...): " api_key
            ;;
        anthropic)
            read -p "Anthropic API key (sk-ant-...): " api_key
            ;;
        deepseek)
            read -p "DeepSeek API key (sk-...): " api_key
            ;;
        groq)
            read -p "GroQ API key (gsk_...): " api_key
            ;;
        custom)
            read -p "API key: " api_key
            read -p "API base URL: " api_base
            ;;
    esac

    local default_model
    default_model=$(get_provider_default_model "$provider")
    local model
    model=$(select_model_interactive "$provider" "$default_model")
    
    for ((i=1; i<=num_instances; i++)); do
        local instance_name="${prefix}${i}"
        local port=$((start_port + i - 1))
        local user_id="YOUR_USER_ID_${i}"
        
        print_step "Creating instance $instance_name (port: $port)..."
        create_docker_instance_single "$instance_name" "$channel" "$port" "$api_key" "$user_id" "$model" "$provider" "$api_base"
    done
    
    print_success "All instances created!"
}

create_docker_instance_single() {
    local instance_name="$1"
    local channel="$2"
    local port="$3"
    local api_key="$4"
    local user_id="$5"
    local model="${6:-moonshotai/kimi-k2.5}"
    local provider="${7:-openrouter}"
    local api_base="${8:-}"
    
    local instance_dir="${NANOBOT_INSTANCES}/${instance_name}"
    mkdir -p "$instance_dir"
    create_config_json "$instance_dir" "$channel" "$api_key" "$user_id" "$model" "$provider" "$api_base"
    create_docker_compose "$instance_dir" "$instance_name" "$port" "$channel"
}

list_instances() {
    print_header
    print_step "Listing Docker instances..."
    
    if [[ ! -d "$NANOBOT_INSTANCES" ]]; then
        print_warning "Instances directory not found: $NANOBOT_INSTANCES"
        return 1
    fi
    
    local instances=()
    for dir in "$NANOBOT_INSTANCES"/*/; do
        if [[ -f "${dir}docker-compose.yml" ]]; then
            instances+=("$(basename "$dir")")
        fi
    done
    
    if [[ ${#instances[@]} -eq 0 ]]; then
        print_warning "No instances found."
        return 0
    fi
    
    echo "Instances found:"
    for instance in "${instances[@]}"; do
        echo "  - $instance"
    done
}

delete_instance() {
    local instance_name="${1:-}"
    
    print_header
    echo -e "${RED}⚠️  DELETE INSTANCE${NC}"
    echo
    
    if [[ -z "$instance_name" ]]; then
        if [[ ! -d "$NANOBOT_INSTANCES" ]]; then
            print_warning "No instances found."
            return 1
        fi
        
        local instances=()
        local i=1
        for dir in "$NANOBOT_INSTANCES"/*/; do
            if [[ -f "${dir}docker-compose.yml" ]]; then
                local name
                name=$(basename "$dir")
                local ch
                ch=$(get_instance_channel "$dir")
                instances+=("$name")
                echo -e "  ${YELLOW}[$i]${NC} $name ${CYAN}($ch)${NC}"
                ((i++))
            fi
        done
        
        if [[ ${#instances[@]} -eq 0 ]]; then
            print_warning "No instances found."
            return 1
        fi
        
        echo
        read -p "Select instance number to delete: " sel
        if [[ -z "${instances[$((sel-1))]:-}" ]]; then
            print_error "Invalid selection."
            return 1
        fi
        instance_name="${instances[$((sel-1))]}"
    fi
    
    local instance_dir="${NANOBOT_INSTANCES}/${instance_name}"
    
    if [[ ! -d "$instance_dir" ]]; then
        print_error "Instance not found: $instance_name"
        return 1
    fi
    
    local ch
    ch=$(get_instance_channel "$instance_dir")
    
    local model
    model=$(get_instance_model "$instance_name")
    
    echo
    echo -e "${YELLOW}━━━ Instance to delete ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "  Name:     ${CYAN}$instance_name${NC}"
    echo -e "  Channel:  $ch"
    echo -e "  Model:    $model"
    echo -e "  Folder:   $instance_dir"
    echo
    echo -e "${RED}This action is IRREVERSIBLE!${NC}"
    echo
    
    read -p "Backup config.json? (y/n) [y]: " do_backup
    if [[ "${do_backup:-y}" == "y" || "${do_backup:-y}" == "Y" ]]; then
        local backup_dir="${BACKUP_DIR}"
        local backup_name="${instance_name}_$(date +%Y%m%d_%H%M%S)"
        mkdir -p "$backup_dir/$backup_name"
        cp "$instance_dir/config.json" "$backup_dir/$backup_name/" 2>/dev/null || true
        cp "$instance_dir/docker-compose.yml" "$backup_dir/$backup_name/" 2>/dev/null || true
        print_success "Backup saved to: $backup_dir/$backup_name/"
        echo
    fi
    
    echo -e "${RED}To confirm, type the instance name: ${NC}"
    read -p "> " confirm_name
    
    if [[ "$confirm_name" != "$instance_name" ]]; then
        print_error "Name does not match. Operation cancelled."
        return 1
    fi
    
    echo
    print_step "Deleting instance $instance_name..."
    
    if docker ps -a --format "{{.Names}}" | grep -q "^nanobot-${instance_name}$"; then
        print_step "Removing container..."
        cd "$instance_dir"
        docker compose down 2>/dev/null || true
        docker rm -f "nanobot-$instance_name" 2>/dev/null || true
        cd - > /dev/null 2>&1
    fi
    
    print_step "Removing files..."
    rm -rf "$instance_dir"
    
    print_success "Instance $instance_name deleted successfully!"
}

configure_instance_menu() {
    local instances=()

    if [[ ! -d "$NANOBOT_INSTANCES" ]]; then
        print_error "No instances found."
        return 1
    fi

    for dir in "$NANOBOT_INSTANCES"/*/; do
        if [[ -f "${dir}config.json" ]]; then
            instances+=("$(basename "$dir")")
        fi
    done

    if [[ ${#instances[@]} -eq 0 ]]; then
        print_error "No instances found."
        return 1
    fi

    print_header
    print_step "Configure instance..."
    echo

    local i=1
    declare -A cfg_map
    for instance in "${instances[@]}"; do
        local cfg="${NANOBOT_INSTANCES}/${instance}/config.json"
        local ch
        ch=$(get_instance_channel "${NANOBOT_INSTANCES}/${instance}")
        local model
        model=$(get_instance_model "$instance")
        echo -e "  ${YELLOW}[$i]${NC} $instance  (${ch} / ${model})"
        cfg_map[$i]="$instance"
        ((i++))
    done

    echo
    read -p "Select instance number: " sel

    if [[ -z "${cfg_map[$sel]:-}" ]]; then
        print_error "Invalid selection."
        return 1
    fi

    local selected="${cfg_map[$sel]}"
    local cfg="${NANOBOT_INSTANCES}/${selected}/config.json"

    local channel
    channel=$(get_instance_channel "${NANOBOT_INSTANCES}/${selected}")

    if [[ "$channel" == "whatsapp" ]]; then
        configure_whatsapp_instance "$selected"
        return
    fi

    print_step "Configuring $selected (channel: $channel)..."
    echo
    
    local allow_from_str group_policy
    allow_from_str=$(python3 -c "
import json
with open('$cfg') as f:
    c = json.load(f)
af = c.get('channels',{}).get('$channel',{}).get('allowFrom',[])
print(','.join(af))
" 2>/dev/null)
    group_policy=$(python3 -c "
import json
with open('$cfg') as f:
    c = json.load(f)
print(c.get('channels',{}).get('$channel',{}).get('groupPolicy','mention'))
" 2>/dev/null)

    echo -e "${CYAN}Channel: $channel${NC}"
    echo "  allowFrom: $allow_from_str"
    echo "  groupPolicy: $group_policy"
    echo

    echo -e "${GREEN}━━━ Configure ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo "  [1] allowFrom: allow anyone"
    echo "  [2] allowFrom: set specific IDs/numbers"
    echo "  [3] Change LLM model"
    echo "  [4] Change LLM provider"
    echo "  [5] Show full config.json"
    echo "  [0] Back"
    echo

    while true; do
        read -p "Choose [0-5]: " cfg_choice
        case ${cfg_choice:-0} in
            1)
                python3 -c "
import json
with open('$cfg', 'r') as f:
    c = json.load(f)
c['channels']['$channel']['allowFrom'] = ['*']
with open('$cfg', 'w') as f:
    json.dump(c, f, indent=2)
"
                print_success "allowFrom = [\"*\"]"
                ;;
            2)
                read -p "IDs/numbers (separated by comma): " ids
                if [[ -n "$ids" ]]; then
                    python3 -c "
import json
with open('$cfg', 'r') as f:
    c = json.load(f)
nums = [n.strip() for n in '$ids'.split(',') if n.strip()]
c['channels']['$channel']['allowFrom'] = nums
with open('$cfg', 'w') as f:
    json.dump(c, f, indent=2)
"
                    print_success "allowFrom updated"
                fi
                ;;
            3)
                cmd_instance_model "$selected"
                ;;
            4)
                cmd_instance_provider "$selected"
                ;;
            5)
                python3 -m json.tool "$cfg"
                ;;
            0)
                return 0
                ;;
            *)
                print_error "Invalid option."
                ;;
        esac
        echo
    done
}
