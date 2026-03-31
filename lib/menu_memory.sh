#!/usr/bin/env bash
# lib/menu_memory.sh - Memory configuration menus

menu_memory() {
    while true; do
        print_header
        echo -e "${YELLOW}━━━ Memory Settings ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo
        echo -e "${GREEN}━━━ Current Global Settings ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        show_global_vector_config
        
        echo
        echo "  [1] Global Vector Memory Settings"
        echo "  [2] Instance Memory Settings"
        echo "  [0] Back"
        echo
        read -p "Choose [0-2]: " choice
        
        case $choice in
            1) menu_global_vector_memory ;;
            2) menu_instance_memory_select ;;
            0) return ;;
        esac
    done
}

menu_global_vector_memory() {
    while true; do
        print_header
        echo -e "${YELLOW}━━━ Global Vector Memory ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo
        
        show_global_vector_config
        
        echo
        echo "  [1] Enable vector memory"
        echo "  [2] Disable vector memory"
        echo "  [3] Set embedding model"
        echo "  [4] Show current config"
        echo "  [5] Clear global settings"
        echo "  [0] Back"
        echo
        read -p "Choose [0-5]: " choice
        
        case $choice in
            1)
                set_global_vector_memory "true"
                print_success "Vector memory enabled"
                ;;
            2)
                set_global_vector_memory "false"
                print_success "Vector memory disabled"
                ;;
            3)
                select_vector_model_interactive
                ;;
            4)
                echo
                show_global_vector_config
                echo
                read -p "Press Enter to continue..."
                ;;
            5)
                rm -f "$GLOBAL_VECTOR_CONFIG_FILE"
                print_success "Global vector config cleared"
                ;;
            0) return ;;
        esac
    done
}

select_vector_model_interactive() {
    echo
    echo "Select embedding provider:"
    echo "  [1] sentence-transformers (default, no container)"
    echo "  [2] ollama (requires container)"
    echo "  [3] openai (remote API)"
    read -p "Choose [1-3]: " prov_choice
    
    local provider
    case "$prov_choice" in
        1) provider="sentence-transformers" ;;
        2) provider="ollama" ;;
        3) provider="openai" ;;
        *) provider="sentence-transformers" ;;
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
    print_success "Vector model set: $provider / $model"
}

menu_instance_memory_select() {
    local instances=()
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
        echo -e "${YELLOW}━━━ Instance Memory Settings ━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo
        
        local i=1
        declare -A instance_display
        for inst in "${instances[@]}"; do
            echo -e "  ${YELLOW}[$i]${NC} $inst"
            instance_display[$i]="$inst"
            ((i++))
        done
        
        echo
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
                menu_instance_memory_config "$selected"
            else
                print_error "Invalid selection"
            fi
        elif [[ -n "${instance_display[$choice]:-}" ]]; then
            menu_instance_memory_config "${instance_display[$choice]}"
        else
            print_error "Invalid option"
        fi
        echo
    done
}

menu_instance_memory_config() {
    local instance_name="$1"
    
    while true; do
        print_header
        echo -e "${YELLOW}━━━ Memory: $instance_name ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo
        show_instance_vector_config "$instance_name"
        
        echo
        echo "  [1] Enable vector memory"
        echo "  [2] Disable vector memory"
        echo "  [3] Set embedding model"
        echo "  [4] Reset to global settings"
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
                select_instance_vector_model "$instance_name"
                ;;
            4)
                instance_reset_vector_config "$instance_name"
                print_success "Reset to global config"
                prompt_restart_instance "$instance_name"
                ;;
            0) return ;;
        esac
    done
}

select_instance_vector_model() {
    local instance_name="$1"
    
    echo
    echo "Select embedding provider:"
    echo "  [1] sentence-transformers (default, no container)"
    echo "  [2] ollama (requires container)"
    echo "  [3] openai (remote API)"
    read -p "Choose [1-3]: " prov_choice
    
    local provider
    case "$prov_choice" in
        1) provider="sentence-transformers" ;;
        2) provider="ollama" ;;
        3) provider="openai" ;;
        *) provider="sentence-transformers" ;;
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
}