#!/usr/bin/env bash
# scripts/menu.sh - Interactive menu functions

AGENT_STATUS_CACHE=""
AGENT_STATUS_CACHE_TIME=0

get_agents_status() {
    local current_time=$(date +%s)
    local cache_age=$((current_time - AGENT_STATUS_CACHE_TIME))
    
    if [[ -n "$AGENT_STATUS_CACHE" && $cache_age -lt 30 ]]; then
        echo -e "$AGENT_STATUS_CACHE"
        return
    fi
    
    local output=""
    
    for dir in "$NANOBOT_INSTANCES"/*/; do
        [[ -f "${dir}docker-compose.yml" ]] || continue
        local name=$(basename "$dir")
        local container="nanobot-${name}"
        
        if docker ps --format "{{.Names}}" 2>/dev/null | grep -q "^${container}$"; then
            local ch=$(get_instance_channel "$dir")
            if [[ "$ch" == "whatsapp" ]]; then
                local last=$(docker logs "$container" 2>&1 | grep -E "✅ Connected to WhatsApp|WhatsApp status:" 2>/dev/null | tail -1)
                local last_lower="${last,,}"
                if [[ "$last_lower" == *"connected"* ]]; then
                    output+="  [${name}] WhatsApp ${GREEN}✅ Connected${NC}\n"
                elif [[ "$last_lower" == *"disconnected"* ]]; then
                    output+="  [${name}] WhatsApp ${YELLOW}⚠️ Disconnected${NC}\n"
                else
                    output+="  [${name}] WhatsApp ${BLUE}❓ Unknown${NC}\n"
                fi
            else
                output+="  [${name}] ${ch} ${GREEN}● Running${NC}\n"
            fi
        else
            output+="  [${name}] ⚫ Offline\n"
        fi
    done
    
    if [[ -z "$output" ]]; then
        output="  No agents\n"
    fi
    
    AGENT_STATUS_CACHE="$output"
    AGENT_STATUS_CACHE_TIME=$current_time
    echo -e "$output"
}

show_menu() {
    clear
    
    local agent_status
    agent_status=$(get_agents_status)
    
    echo -e "${CYAN}══════════════════════════════════════════════════════════════════${NC}"
    echo -e "${PURPLE} 🐈 Agent Manager${NC}"
    echo -e "${BLUE}  WhatsApp Audio Patch + Multi-Provider LLM${NC}"
    echo -e "${CYAN}══════════════════════════════════════════════════════════════════${NC}"
    
    echo -e "  ${PURPLE}📊 Agents${NC}"
    echo -e "${agent_status}"
    
    echo
    echo -e "  ${PURPLE}⚡ Configuration${NC}"
    echo -e "    ${YELLOW}[1]${NC} Setup All  ${YELLOW}[2]${NC} Prerequisites  ${YELLOW}[3]${NC} Build Image"
    echo
    echo -e "  ${CYAN}📦 Instances${NC}"
    echo -e "    ${CYAN}[4]${NC} Create  ${CYAN}[5]${NC} Create Multiple  ${CYAN}[6]${NC} List"
    echo
    echo -e "  ${GREEN}🎮 Control${NC}"
    echo -e "    ${GREEN}[7]${NC} Start  ${RED}[8]${NC} Stop  ${BLUE}[9]${NC} Restart"
    echo -e "    ${PURPLE}[10]${NC} Status  ${CYAN}[11]${NC} Logs  ${CYAN}[12]${NC} Chat"
    echo
    echo -e "  ${GREEN}📱 WhatsApp${NC}"
    echo -e "    ${GREEN}[13]${NC} Login  ${YELLOW}[14]${NC} Reconnect  ${YELLOW}[15]${NC} Update Bridge"
    echo -e "    ${CYAN}[16]${NC} Configure"
    echo
    echo -e "  ${BLUE}🔄 Batch${NC}"
    echo -e "    ${GREEN}[17]${NC} Start All  ${RED}[18]${NC} Stop All"
    echo -e "    ${BLUE}[19]${NC} Restart All  ${YELLOW}[20]${NC} Update All"
    echo
    echo -e "  ${PURPLE}🔧 System${NC}"
    echo -e "    ${PURPLE}[21]${NC} Rebuild Image  ${CYAN}[22]${NC} Config Instance"
    echo -e "    ${CYAN}[23]${NC} Help"
    echo
    echo -e "  ${YELLOW}🤖 AI LLM${NC}"
    echo -e "    ${YELLOW}[25]${NC} Global LLM Settings"
    echo -e "    ${YELLOW}[26]${NC} Instance LLM Settings"
    echo
    echo -e "  ${RED}⚠️  Danger${NC}"
    echo -e "    ${RED}[24]${NC} Delete Instance (IRREVERSIBLE)"
    echo
    echo
    echo -e "    ${RED}[0]${NC} Exit"
    echo
}

select_instance() {
    local action="$1"
    local instances=()
    
    if [[ ! -d "$NANOBOT_INSTANCES" ]]; then
        print_error "No instances found. Create an instance first."
        return 1
    fi
    
    for dir in "$NANOBOT_INSTANCES"/*/; do
        if [[ -f "${dir}docker-compose.yml" ]]; then
            instances+=("$(basename "$dir")")
        fi
    done
    
    if [[ ${#instances[@]} -eq 0 ]]; then
        print_error "No instances found. Create an instance first."
        return 1
    fi
    
    echo
    echo -e "${CYAN}Available instances:${NC}"
    echo
    
    local i=1
    declare -A instance_map
    for instance in "${instances[@]}"; do
        echo -e "  ${YELLOW}[$i]${NC} $instance"
        instance_map[$i]="$instance"
        ((i++))
    done
    
    echo
    read -p "Select instance number: " selection
    
    if [[ -z "${instance_map[$selection]:-}" ]]; then
        print_error "Invalid selection."
        return 1
    fi
    
    local selected_instance="${instance_map[$selection]}"
    
    case $action in
        start) manage_instance start "$selected_instance" ;;
        stop) manage_instance stop "$selected_instance" ;;
        restart) manage_instance restart "$selected_instance" ;;
        logs) manage_instance logs "$selected_instance" ;;
        status) manage_instance status "$selected_instance" ;;
        chat) manage_instance chat "$selected_instance" ;;
        login) manage_instance login-whatsapp "$selected_instance" ;;
        reconnect) reconnect_whatsapp "$selected_instance" ;;
        upgrade-bridge) upgrade_whatsapp_bridge "$selected_instance" ;;
        configure-wa) configure_whatsapp_instance "$selected_instance" ;;
    esac
}

# Run a menu action in a subshell with errexit on, so a failing action (or an
# invalid selection) returns to the menu instead of exiting the whole program
run_action() {
    local rc=0
    set +e
    ( set -e; "$@" )
    rc=$?
    set -e
    if (( rc != 0 )); then
        print_warning "Action failed (exit code $rc)."
    fi
}

interactive_menu() {
    clear
    echo -e "${PURPLE}══════════════════════════════════════════════════════════════════${NC}"
    echo -e "${PURPLE}        🐈 Agent Manager - isolated nanobot agents in Docker${NC}"
    echo -e "${PURPLE}══════════════════════════════════════════════════════════════════${NC}"
    echo
    echo -e "${GREEN}Welcome to Agent Manager!${NC}"
    echo
    echo -e "${CYAN}This script helps create and manage isolated Docker instances"
    echo -e "of nanobot agents, one container per agent.${NC}"
    echo
    echo -e "${YELLOW}Recommendation: Use option [1] Setup All to start!${NC}"
    echo
    read -p "Press Enter to continue..."

    while true; do
        show_menu
        read -p "Choose an option [0-26]: " choice

        case $choice in
            1) run_action setup_guide_flow ;;
            2) run_action check_prerequisites ;;
            3) run_action build_nanobot_image ;;
            4) run_action create_docker_instance ;;
            5) run_action create_multi_instances ;;
            6) run_action list_instances ;;
            7) run_action select_instance "start" ;;
            8) run_action select_instance "stop" ;;
            9) run_action select_instance "restart" ;;
            10) run_action select_instance "status" ;;
            11) run_action select_instance "logs" ;;
            12) run_action select_instance "chat" ;;
            13) run_action select_instance "login" ;;
            14) run_action select_instance "reconnect" ;;
            15) run_action select_instance "upgrade-bridge" ;;
            16) run_action select_instance "configure-wa" ;;
            17) run_action manage_all_instances start ;;
            18) run_action manage_all_instances stop ;;
            19) run_action manage_all_instances restart ;;
            20) run_action manage_all_instances update ;;
            21) run_action rebuild_docker_image ;;
            22) run_action configure_instance_menu ;;
            23) run_action show_help ;;
            24) run_action delete_instance ;;
            25) run_action menu_global_llm ;;
            26) run_action menu_instance_llm ;;
            0)
                echo
                print_info "Exiting Agent Manager. Goodbye! 🐈"
                exit 0
                ;;
            *)
                print_error "Invalid option. Choose a number from 0 to 26."
                ;;
        esac
        
        echo
        read -p "Press Enter to continue..."
    done
}

show_help() {
    print_header
    echo "Usage: ./xnanobot.sh [command] [options]"
    echo "Agent Manager - isolated nanobot agents in Docker"
    echo "Run without a command (or with 'interactive') for the interactive menu."
    echo
    echo "Setup:"
    echo "  setup-guide              - Full setup: check, build, create first instance (alias: setup)"
    echo "  check                    - Check prerequisites (Docker, Compose)"
    echo "  build                    - Build the patched nanobot Docker image"
    echo "  rebuild                  - Rebuild the image (same as build)"
    echo "  update                   - Explain how to update nanobot"
    echo
    echo "Instances:"
    echo "  create                   - Create a new instance"
    echo "  create-multi             - Create several instances at once"
    echo "  list                     - List instances"
    echo "  configure                - Configure an instance (allowFrom, model, provider)"
    echo "  delete [name]            - Delete an instance (aliases: remove, rm)"
    echo
    echo "Control:"
    echo "  start <name>             - Start an instance"
    echo "  stop <name>              - Stop an instance"
    echo "  restart <name>           - Restart an instance"
    echo "  logs <name>              - Follow logs"
    echo "  status <name>            - Show nanobot status"
    echo "  chat <name>              - Chat with the agent in the terminal"
    echo
    echo "WhatsApp:"
    echo "  login <name>             - Link WhatsApp (QR code)"
    echo "  reconnect <name>         - Clear the session and link again"
    echo "  upgrade-bridge <name>    - Refresh the bridge from the image and link again"
    echo "  configure-wa <name>      - Configure allowFrom, group policy, enable/disable"
    echo
    echo "Batch:"
    echo "  start-all | stop-all | restart-all"
    echo "  update-all               - Recreate all containers (after a rebuild)"
    echo
    echo "LLM (global defaults):"
    echo "  global-set               - Set provider, API key and model"
    echo "  global-provider          - Set provider (+ API key)"
    echo "  global-model             - Set model"
    echo "  global-key               - Set API key for a provider"
    echo "  global-show              - Show global config"
    echo "  global-clear             - Clear global config"
    echo
    echo "LLM (per instance, overrides global):"
    echo "  instance-show <name>     - Show effective config and where it comes from"
    echo "  instance-model <name>    - Set model (+ optional API key)"
    echo "  instance-provider <name> - Set provider (+ optional API key)"
    echo "  instance-key <name>      - Set instance API key"
    echo "  instance-key-clear <name> - Clear instance API key (use global)"
    echo "  instance-reset <name>    - Remove instance LLM settings (use global)"
    echo
    echo "  help                     - Show this help"
    echo
}
