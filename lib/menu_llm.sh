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
        echo "  [6] Global Vector Memory Settings"
        echo "  [0] Back"
        echo
        read -p "Choose [0-6]: " choice
        
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
            6)
                menu_global_vector
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
        echo "  [6] Vector Memory Settings"
        echo "  [0] Back"
        echo
        read -p "Choose [0-6]: " choice
        
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
            6)
                menu_instance_vector_config "$instance_name"
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

menu_global_vector() {
    while true; do
        print_header
        echo -e "${YELLOW}━━━ Global Vector Memory Settings ━━━━━━━━━━━━━━━━${NC}"
        echo
        
        show_global_vector_config
        
        echo -e "${GREEN}━━━ Global Vector Memory ━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo "  [1] Enable vector memory (default for all instances)"
        echo "  [2] Disable vector memory"
        echo "  [3] Set default embedding model"
        echo "  [4] Clear global vector memory settings"
        echo "  [0] Back"
        echo
        read -p "Choose [0-4]: " choice
        
        case $choice in
            1)
                set_global_vector_memory "true"
                print_success "Global vector memory enabled"
                ;;
            2)
                set_global_vector_memory "false"
                print_success "Global vector memory disabled"
                ;;
            3)
                echo
                echo "Select provider:"
                echo "  [1] sentence-transformers (default, no container)"
                echo "  [2] ollama (requires container)"
                echo "  [3] openai (remote API)"
                read -p "Choose [1-3]: " prov_choice
                case "$prov_choice" in
                    1) local provider="sentence-transformers" ;;
                    2) local provider="ollama" ;;
                    3) local provider="openai" ;;
                    *) local provider="sentence-transformers" ;;
                esac
                
                local model
                case "$provider" in
                    sentence-transformers)
                        echo "Select model:"
                        echo "  [1] paraphrase-multilingual-mpnet-base-v2 (recommended for PT-BR)"
                        echo "  [2] all-MiniLM-L6-v2 (lightweight)"
                        read -p "Choose [1-2]: " model_choice
                        [[ "$model_choice" == "2" ]] && model="all-MiniLM-L6-v2" || model="paraphrase-multilingual-mpnet-base-v2"
                        ;;
                    ollama)
                        echo "Select model:"
                        echo "  [1] nomic-embed-text (default)"
                        echo "  [2] bge-m3 (best multilingual)"
                        read -p "Choose [1-2]: " model_choice
                        [[ "$model_choice" == "2" ]] && model="bge-m3" || model="nomic-embed-text"
                        ;;
                    openai)
                        model="text-embedding-3-small"
                        ;;
                    *) model="paraphrase-multilingual-mpnet-base-v2" ;;
                esac
                
                set_global_vector_model "$provider" "$model"
                print_success "Global vector model set: $provider / $model"
                ;;
            4)
                rm -f "$GLOBAL_VECTOR_CONFIG_FILE"
                print_success "Global vector config cleared"
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

menu_instance_vector_config() {
    local instance_name="$1"
    
    while true; do
        print_header
        echo -e "${YELLOW}━━━ Vector Memory: $instance_name ━━━━━━━━━━━━━━━━━━━━${NC}"
        echo
        show_instance_vector_config "$instance_name"
        
        echo -e "${GREEN}━━━ Configure $instance_name ━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo "  [1] Enable vector memory"
        echo "  [2] Disable vector memory"
        echo "  [3] Set embedding model"
        echo "  [4] Reset to global vector settings"
        echo "  [0] Back"
        echo
        read -p "Choose [0-4]: " choice
        
        case $choice in
            1)
                instance_set_vector_memory "$instance_name" "true"
                print_success "Vector memory enabled for $instance_name"
                prompt_restart_instance "$instance_name"
                ;;
            2)
                instance_set_vector_memory "$instance_name" "false"
                print_success "Vector memory disabled for $instance_name"
                prompt_restart_instance "$instance_name"
                ;;
            3)
                echo
                echo "Select provider:"
                echo "  [1] sentence-transformers (default, no container)"
                echo "  [2] ollama (requires container)"
                echo "  [3] openai (remote API)"
                read -p "Choose [1-3]: " prov_choice
                case "$prov_choice" in
                    1) local provider="sentence-transformers" ;;
                    2) local provider="ollama" ;;
                    3) local provider="openai" ;;
                    *) local provider="sentence-transformers" ;;
                esac
                
                local model
                case "$provider" in
                    sentence-transformers)
                        echo "Select model:"
                        echo "  [1] paraphrase-multilingual-mpnet-base-v2 (recommended for PT-BR)"
                        echo "  [2] all-MiniLM-L6-v2 (lightweight)"
                        read -p "Choose [1-2]: " model_choice
                        [[ "$model_choice" == "2" ]] && model="all-MiniLM-L6-v2" || model="paraphrase-multilingual-mpnet-base-v2"
                        ;;
                    ollama)
                        echo "Select model:"
                        echo "  [1] nomic-embed-text (default)"
                        echo "  [2] bge-m3 (best multilingual)"
                        read -p "Choose [1-2]: " model_choice
                        [[ "$model_choice" == "2" ]] && model="bge-m3" || model="nomic-embed-text"
                        ;;
                    openai)
                        model="text-embedding-3-small"
                        ;;
                    *) model="paraphrase-multilingual-mpnet-base-v2" ;;
                esac
                
                instance_set_vector_memory_model "$instance_name" "$provider" "$model"
                print_success "Vector model set: $provider / $model"
                prompt_restart_instance "$instance_name"
                ;;
            4)
                instance_reset_vector_config "$instance_name"
                print_success "Reset to global config"
                prompt_restart_instance "$instance_name"
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
