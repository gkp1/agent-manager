#!/usr/bin/env bash
# scripts/whatsapp.sh - WhatsApp bridge and configuration functions

init_whatsapp_bridge() {
    local instance_dir="$1"
    mkdir -p "$instance_dir/bridge"
    docker run --rm \
        -v "$instance_dir/bridge:/root/.nanobot/bridge" \
        --entrypoint sh \
        nanobot -c "cp -a /app/bridge/. /root/.nanobot/bridge/"
}

whatsapp_login_flow() {
    local instance_dir="$1"

    cd "$instance_dir"

    if [[ ! -f bridge/dist/index.js ]]; then
        print_step "Initializing WhatsApp bridge from image..."
        init_whatsapp_bridge "$instance_dir"
    fi

    mkdir -p whatsapp-auth

    echo
    print_step "Starting WhatsApp login..."
    echo
    echo -e "${YELLOW}  1. QR Code will appear below${NC}"
    echo -e "${YELLOW}  2. Open WhatsApp → Linked Devices → Link Device${NC}"
    echo -e "${YELLOW}  3. Scan the QR Code${NC}"
    echo -e "${YELLOW}  4. When you see Connected, press Ctrl+C${NC}"
    echo
    read -p "  Press Enter to start..."

    docker run -it \
        -v "$(pwd)/config.json:/root/.nanobot/config.json" \
        -v "$(pwd)/bridge:/root/.nanobot/bridge" \
        -v "$(pwd)/workspace:/root/.nanobot/workspace" \
        -v "$(pwd)/whatsapp-auth:/root/.nanobot/whatsapp-auth" \
        --entrypoint nanobot \
        nanobot channels login whatsapp || true

    if [[ -d whatsapp-auth ]] && [[ "$(ls -A whatsapp-auth 2>/dev/null)" ]]; then
        print_success "WhatsApp connected! Session saved."
    else
        print_warning "Session not detected in whatsapp-auth/. Login may have failed."
    fi

    cd - > /dev/null 2>&1
}

reconnect_whatsapp() {
    local instance_name="$1"
    local instance_dir="${NANOBOT_INSTANCES}/${instance_name}"
    
    if [[ ! -d "$instance_dir" ]]; then
        print_error "Instance not found: $instance_name"
        return 1
    fi
    
    print_step "Reconnecting WhatsApp for $instance_name..."
    
    cd "$instance_dir"
    docker compose down 2>/dev/null || true

    rm -rf whatsapp-auth
    mkdir -p whatsapp-auth

    cd - > /dev/null 2>&1

    whatsapp_login_flow "$instance_dir"

    cd "$instance_dir"
    docker compose up -d
    cd - > /dev/null 2>&1
    
    print_success "WhatsApp reconnected for $instance_name!"
}

upgrade_whatsapp_bridge() {
    local instance_name="$1"
    local instance_dir="${NANOBOT_INSTANCES}/${instance_name}"

    if [[ ! -d "$instance_dir" ]]; then
        print_error "Instance not found: $instance_name"
        return 1
    fi

    print_step "Updating WhatsApp bridge for $instance_name..."

    cd "$instance_dir"
    docker compose down 2>/dev/null || true
    cd - > /dev/null 2>&1

    rm -rf "$instance_dir/bridge" "$instance_dir/whatsapp-auth"

    print_step "Rebuilding bridge with latest version..."
    whatsapp_login_flow "$instance_dir"

    cd "$instance_dir"
    docker compose up -d
    cd - > /dev/null 2>&1

    print_success "WhatsApp bridge updated and instance restarted!"
}

configure_whatsapp_instance() {
    local instance_name="$1"
    local instance_dir="${NANOBOT_INSTANCES}/${instance_name}"

    if [[ ! -d "$instance_dir" ]]; then
        print_error "Instance not found: $instance_name"
        return 1
    fi

    local config_file="${instance_dir}/config.json"
    if [[ ! -f "$config_file" ]]; then
        print_error "config.json not found in $instance_dir"
        return 1
    fi

    local channel
    channel=$(python3 -c "
import json
with open('$config_file') as f:
    cfg = json.load(f)
channels = cfg.get('channels', {})
print('whatsapp' if 'whatsapp' in channels else (list(channels.keys())[0] if channels else ''))
" 2>/dev/null)

    if [[ "$channel" != "whatsapp" ]]; then
        print_error "Instance $instance_name is not WhatsApp (channel: $channel)"
        return 1
    fi

    print_header
    print_step "Configuring WhatsApp for $instance_name..."
    echo

    local current_allow_from current_group_policy current_enabled
    read current_enabled current_allow_from current_group_policy < <(python3 -c "
import json
with open('$config_file') as f:
    cfg = json.load(f)
wa = cfg.get('channels', {}).get('whatsapp', {})
enabled = str(wa.get('enabled', True)).lower()
af = wa.get('allowFrom', ['*'])
af_str = ','.join(af)
gp = wa.get('groupPolicy', 'mention')
print(f'{enabled} {af_str} {gp}')
")

    echo -e "${CYAN}Current configuration:${NC}"
    echo "  Enabled: $current_enabled"
    echo "  allowFrom: $current_allow_from"
    echo "  groupPolicy: $current_group_policy"
    echo

    echo -e "${GREEN}━━━ Configure WhatsApp ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo "  [1] Allow anyone to access (allowFrom: [\"*\"])"
    echo "  [2] Set specific numbers"
    echo "  [3] Group policy: mention"
    echo "  [4] Group policy: open"
    echo "  [5] Enable / Disable channel"
    echo "  [6] Show current config.json"
    echo "  [7] Edit config.json manually"
    echo "  [0] Back"
    echo

    while true; do
        read -p "Choose [0-7]: " wa_choice
        case ${wa_choice:-0} in
            1)
                python3 -c "
import json
with open('$config_file', 'r') as f:
    cfg = json.load(f)
cfg.setdefault('channels', {}).setdefault('whatsapp', {})['allowFrom'] = ['*']
with open('$config_file', 'w') as f:
    json.dump(cfg, f, indent=2)
"
                print_success "allowFrom configured for [\"*\"]"
                ;;
            2)
                echo "Enter numbers separated by comma:"
                read -p "Numbers: " numbers
                if [[ -n "$numbers" ]]; then
                    python3 -c "
import json
nums = [n.strip() for n in '$numbers'.split(',') if n.strip()]
with open('$config_file', 'r') as f:
    cfg = json.load(f)
cfg.setdefault('channels', {}).setdefault('whatsapp', {})['allowFrom'] = nums
with open('$config_file', 'w') as f:
    json.dump(cfg, f, indent=2)
"
                    print_success "allowFrom updated"
                fi
                ;;
            3)
                python3 -c "
import json
with open('$config_file', 'r') as f:
    cfg = json.load(f)
cfg.setdefault('channels', {}).setdefault('whatsapp', {})['groupPolicy'] = 'mention'
with open('$config_file', 'w') as f:
    json.dump(cfg, f, indent=2)
"
                print_success "groupPolicy = mention"
                ;;
            4)
                python3 -c "
import json
with open('$config_file', 'r') as f:
    cfg = json.load(f)
cfg.setdefault('channels', {}).setdefault('whatsapp', {})['groupPolicy'] = 'open'
with open('$config_file', 'w') as f:
    json.dump(cfg, f, indent=2)
"
                print_success "groupPolicy = open"
                ;;
            5)
                local new_enabled
                new_enabled=$(python3 -c "
import json
with open('$config_file', 'r') as f:
    cfg = json.load(f)
wa = cfg.setdefault('channels', {}).setdefault('whatsapp', {})
current = wa.get('enabled', True)
wa['enabled'] = not current
with open('$config_file', 'w') as f:
    json.dump(cfg, f, indent=2)
print(str(not current).lower())
")
                print_success "Channel enabled = $new_enabled"
                ;;
            6)
                echo
                python3 -m json.tool "$config_file"
                echo
                ;;
            7)
                if command -v nano &> /dev/null; then
                    nano "$config_file"
                elif command -v vim &> /dev/null; then
                    vim "$config_file"
                else
                    print_warning "No editor found."
                fi
                ;;
            0)
                local running
                running=$(docker ps --filter "name=nanobot-${instance_name}" --format "{{.Names}}" 2>/dev/null)
                if [[ -n "$running" ]]; then
                    echo
                    read -p "Restart instance to apply changes? (y/n): " restart_confirm
                    if [[ "$restart_confirm" == "y" || "$restart_confirm" == "Y" ]]; then
                        cd "$instance_dir"
                        docker compose restart
                        cd - > /dev/null 2>&1
                        print_success "Instance restarted!"
                    fi
                fi
                return 0
                ;;
            *)
                print_error "Invalid option."
                ;;
        esac
        echo
    done
}
