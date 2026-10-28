#!/usr/bin/env bash
# lib/menu_llm.sh - Interactive LLM configuration menus

menu_global_llm() {
    while true; do
        print_header
        echo -e "${YELLOW}━━━ Global LLM Settings ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo
        
        show_global_config
        
        echo -e "${GREEN}━━━ Global Settings ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo "  [1] Set global provider (+ API key)"
        echo "  [2] Set global model"
        echo "  [3] Set global API key for a provider"
        echo "  [4] Clear global API key"
        echo "  [5] Clear all global settings"
        echo "  [0] Back"
        echo
        read -p "Choose [0-5]: " choice
        
        case $choice in
            1)
                cmd_global_provider
                ;;
            2)
                cmd_global_model
                ;;
            3)
                cmd_global_key
                ;;
            4)
                echo
                echo "Select provider to clear API key:"
                local i=1
                local providers_arr=()
                for prov in "${LLM_PROVIDERS[@]}"; do
                    echo "  [$i] $prov"
                    providers_arr+=("$prov")
                    ((i++))
                done
                echo
                read -p "Choose: " sel
                if [[ -n "${providers_arr[$((sel-1))]:-}" ]]; then
                    clear_global_api_key "${providers_arr[$((sel-1))]}"
                    print_success "API key cleared for: ${providers_arr[$((sel-1))]}"
                fi
                ;;
            5)
                read -p "Clear all global LLM settings? (y/n): " confirm
                if [[ "$confirm" == "y" || "$confirm" == "Y" ]]; then
                    clear_global_config
                    print_success "Global config cleared"
                fi
                ;;
            0)
                return
                ;;
            *)
                print_error "Invalid option"
                ;;
        esac
        echo
    done
}

menu_instance_llm() {
    local instances=()
    local i=1
    for dir in "${NANOBOT_INSTANCES}"/*/; do
        if [[ -f "${dir}docker-compose.yml" ]]; then
            instances+=("$(basename "$dir")")
        fi
    done
    
    if [[ ${#instances[@]} -eq 0 ]]; then
        print_error "No instances found."
        return 1
    fi
    
    while true; do
        print_header
        echo -e "${YELLOW}━━━ Instance LLM Settings ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo
        
        local i=1
        declare -A instance_display
        for inst in "${instances[@]}"; do
            local provider model source
            provider=$(llm_get_effective_provider "$inst")
            model=$(llm_get_effective_model "$inst")
            source=$(llm_get_effective_source "$inst")
            
            if [[ "$source" == "CUSTOM" ]]; then
                echo -e "  ${YELLOW}[$i]${NC} $inst  ${GREEN}$provider${NC} / ${GREEN}$model${NC} ${CYAN}(custom)${NC}"
            else
                echo -e "  ${YELLOW}[$i]${NC} $inst  ${GREEN}$provider${NC} / ${GREEN}$model${NC} ${YELLOW}(inherits global)${NC}"
            fi
            instance_display[$i]="$inst"
            ((i++))
        done
        
        echo
        echo -e "${GREEN}━━━ Actions ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo "  [S] Select instance to configure"
        echo "  [0] Back"
        echo
        read -p "Choose [0-S]: " choice
        
        if [[ "$choice" == "0" || "$choice" == "" ]]; then
            return
        elif [[ "$choice" == "s" || "$choice" == "S" ]]; then
            echo
            read -p "Select instance number: " sel
            local selected="${instance_display[$sel]:-}"
            if [[ -n "$selected" ]]; then
                menu_instance_llm_config "$selected"
            else
                print_error "Invalid selection"
            fi
        elif [[ -n "${instance_display[$choice]:-}" ]]; then
            menu_instance_llm_config "${instance_display[$choice]}"
        else
            print_error "Invalid option"
        fi
        echo
    done
}

menu_instance_llm_config() {
    local instance_name="$1"
    
    while true; do
        print_header
        show_instance_effective_config "$instance_name"
        
        echo -e "${GREEN}━━━ Configure $instance_name ━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo "  [1] Change model (+ optional new API key)"
        echo "  [2] Change provider (+ optional new API key)"
        echo "  [3] Set instance API key (override global)"
        echo "  [4] Clear instance API key (use global)"
        echo "  [5] Reset to global config"
        echo "  [0] Back"
        echo
        read -p "Choose [0-5]: " choice
        
        case $choice in
            1)
                cmd_instance_model "$instance_name"
                ;;
            2)
                cmd_instance_provider "$instance_name"
                ;;
            3)
                cmd_instance_key "$instance_name"
                ;;
            4)
                cmd_instance_key_clear "$instance_name"
                ;;
            5)
                cmd_instance_reset "$instance_name"
                ;;
            0)
                return
                ;;
            *)
                print_error "Invalid option"
                ;;
        esac
        echo
    done
}
