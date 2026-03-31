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
    echo -e "${PURPLE} 🐈 Nanobot Helper v2.0${NC}"
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
    echo -e "    ${YELLOW}[27]${NC} Memory Settings"
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

interactive_menu() {
    declare -A instance_map
    
    clear
    echo -e "${PURPLE}══════════════════════════════════════════════════════════════════${NC}"
    echo -e "${PURPLE}        Nanobot Helper v2.0 - AI Manager for Nanobot${NC}"
    echo -e "${PURPLE}══════════════════════════════════════════════════════════════════${NC}"
    echo
    echo -e "${GREEN}Welcome to AI Manager!${NC}"
    echo
    echo -e "${CYAN}This script helps create and manage isolated Docker instances"
    echo -e "of Nanobot agents using Docker Multi-Tenant.${NC}"
    echo
    echo -e "${YELLOW}Recommendation: Use option [1] Setup All to start!${NC}"
    echo
    read -p "Press Enter to continue..."
    
    while true; do
        show_menu
        read -p "Choose an option [0-26]: " choice
        
        case $choice in
            1) setup_guide_flow ;;
            2) check_prerequisites ;;
            3) build_nanobot_image ;;
            4) create_docker_instance ;;
            5) create_multi_instances ;;
            6) list_instances ;;
            7) select_instance "start" ;;
            8) select_instance "stop" ;;
            9) select_instance "restart" ;;
            10) select_instance "status" ;;
            11) select_instance "logs" ;;
            12) select_instance "chat" ;;
            13) select_instance "login" ;;
            14) select_instance "reconnect" ;;
            15) select_instance "upgrade-bridge" ;;
            16) select_instance "configure-wa" ;;
            17) manage_all_instances start ;;
            18) manage_all_instances stop ;;
            19) manage_all_instances restart ;;
            20) manage_all_instances update ;;
            21) rebuild_docker_image ;;
            22) configure_instance_menu ;;
            23) show_help ;;
            24) delete_instance ;;
            25) menu_global_llm ;;
            26) menu_instance_llm ;;
            27) menu_memory ;;
            0)
                echo
                print_info "Exiting Nanobot Helper. Goodbye! 🐈"
                exit 0
                ;;
            *)
                print_error "Invalid option. Choose a number from 0 to 27."
                ;;
        esac
        
        echo
        read -p "Press Enter to continue..."
    done
}

show_help() {
    print_header
    echo "Usage: ./xnanobot.sh [command] [options]"
    echo "AI Manager - Multi-Tenant Docker for nanobot agents"
    echo
    echo "Setup:"
    echo "  setup-guide      - Setup complete"
    echo "  check            - Check prerequisites"
    echo "  build            - Build Docker image"
    echo
    echo "Docker Instances:"
    echo "  create           - Create new instance"
    echo "  create-multi     - Create multiple instances"
    echo "  list             - List instances"
    echo
    echo "Instance Management:"
    echo "  start <name>     - Start instance"
    echo "  stop <name>      - Stop instance"
    echo "  restart <name>   - Restart instance"
    echo "  logs <name>      - View logs"
    echo "  status <name>    - View status"
    echo "  chat <name>     - Chat CLI"
    echo "  login <name>    - Connect WhatsApp"
    echo "  reconnect <name> - Reconnect WhatsApp"
    echo "  delete <name>   - Delete instance"
    echo
    echo "WhatsApp:"
    echo "  upgrade-bridge <name> - Update WhatsApp bridge"
    echo "  configure-wa <name>  - Configure WhatsApp"
    echo
    echo "Batch:"
    echo "  start-all        - Start all"
    echo "  stop-all         - Stop all"
    echo "  restart-all      - Restart all"
    echo "  update-all       - Update all"
    echo
    echo "LLM:"
    echo "  global-set              - Set global LLM"
    echo "  global-show             - Show global config"
    echo "  instance-show <name>    - Show instance config"
    echo "  instance-model <name>   - Set instance model"
    echo "  instance-provider <name> - Set instance provider"
    echo "  instance-reset <name>   - Reset to global"
    echo
    echo "Utilities:"
    echo "  configure        - Configure instance"
    echo "  interactive      - Interactive menu"
    echo "  help             - Show help"
    echo
}
