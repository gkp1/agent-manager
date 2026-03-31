#!/usr/bin/env bash
# lib/llm_commands.sh - CLI commands for LLM management

cmd_global_set() {
    local provider model api_key
    
    provider=$(select_llm_provider_interactive)
    
    echo
    echo "Provider selected: $provider"
    
    api_key=$(prompt_api_key_choice "$provider" "global")
    
    if [[ "$api_key" == "__CLEAR__" ]]; then
        clear_global_api_key "$provider"
    elif [[ -n "$api_key" ]]; then
        set_global_api_key "$provider" "$api_key"
    fi
    
    model=$(select_model_interactive "$provider" "")
    
    set_global_provider "$provider"
    set_global_model "$model"
    
    echo
    print_success "Global config saved:"
    echo "  Provider: $provider"
    echo "  Model: $model"
    echo
    prompt_restart_all_instances
}

cmd_global_provider() {
    local provider
    provider=$(select_llm_provider_interactive)
    
    local api_key
    api_key=$(prompt_api_key_choice "$provider" "global")
    
    if [[ "$api_key" == "__CLEAR__" ]]; then
        clear_global_api_key "$provider"
    elif [[ -n "$api_key" ]]; then
        set_global_api_key "$provider" "$api_key"
    fi
    
    set_global_provider "$provider"
    
    print_success "Global provider set to: $provider"
    echo
    prompt_restart_all_instances
}

cmd_global_model() {
    local provider
    provider=$(get_global_provider)
    
    if [[ -z "$provider" ]]; then
        print_error "No global provider set. Run: $0 global-provider first"
        return 1
    fi
    
    local current_model
    current_model=$(get_global_model)
    
    local model
    model=$(select_model_interactive "$provider" "$current_model")
    
    set_global_model "$model"
    
    print_success "Global model set to: $model"
    echo
    prompt_restart_all_instances
}

cmd_global_key() {
    local provider
    provider=$(select_llm_provider_interactive)
    
    local api_key
    api_key=$(prompt_api_key_choice "$provider" "global")
    
    if [[ "$api_key" == "__CLEAR__" ]]; then
        clear_global_api_key "$provider"
        print_success "API key cleared for: $provider"
    elif [[ -n "$api_key" ]]; then
        set_global_api_key "$provider" "$api_key"
        print_success "API key set for: $provider"
        echo
        prompt_restart_all_instances
    else
        print_warning "No API key set"
    fi
}

cmd_global_show() {
    show_global_config
}

cmd_global_clear() {
    clear_global_config
    print_success "Global config cleared"
    echo
    prompt_restart_all_instances
}

cmd_instance_show() {
    local instance_name="$1"
    
    if ! instance_exists "$instance_name"; then
        print_error "Instance not found: $instance_name"
        return 1
    fi
    
    show_instance_effective_config "$instance_name"
}

cmd_instance_model() {
    local instance_name="$1"
    
    if ! instance_exists "$instance_name"; then
        print_error "Instance not found: $instance_name"
        return 1
    fi
    
    local current_provider current_model
    current_provider=$(llm_get_effective_provider "$instance_name")
    current_model=$(llm_get_effective_model "$instance_name")
    local source
    source=$(llm_get_effective_source "$instance_name")
    
    echo
    echo -e "Instance: $instance_name"
    echo -e "Current: $current_provider / $current_model"
    echo
    
    if [[ "$source" == "GLOBAL" || "$source" == "DEFAULT" ]]; then
        echo -e "${YELLOW}This instance currently INHERITS global config.${NC}"
        echo "Setting a custom model will override global."
        echo
    fi
    
    local new_model
    new_model=$(select_model_interactive "$current_provider" "$current_model")
    
    llm_instance_set_model "$instance_name" "$new_model"
    
    local key_choice
    key_choice=$(prompt_api_key_choice "$current_provider" "instance")
    
    if [[ "$key_choice" == "__CLEAR__" ]]; then
        llm_instance_clear_api_key "$instance_name" "$current_provider"
        print_success "Instance API key cleared (will use global)"
    elif [[ -n "$key_choice" ]]; then
        llm_instance_set_api_key "$instance_name" "$current_provider" "$key_choice"
        print_success "Instance API key set (override)"
    fi
    
    echo
    print_success "Instance $instance_name model set to: $new_model"
    echo
    prompt_restart_instance "$instance_name"
}

cmd_instance_provider() {
    local instance_name="$1"
    
    if ! instance_exists "$instance_name"; then
        print_error "Instance not found: $instance_name"
        return 1
    fi
    
    local new_provider
    new_provider=$(select_llm_provider_interactive)
    
    local default_model
    default_model=$(get_provider_default_model "$new_provider")
    
    llm_instance_set_provider "$instance_name" "$new_provider"
    llm_instance_set_model "$instance_name" "$default_model"
    
    echo
    echo -e "Provider selected: $new_provider"
    echo -e "Default model: $default_model"
    
    local api_key
    api_key=$(prompt_api_key_choice "$new_provider" "instance")
    
    if [[ "$api_key" == "__CLEAR__" ]]; then
        llm_instance_clear_api_key "$instance_name" "$new_provider"
    elif [[ -n "$api_key" ]]; then
        llm_instance_set_api_key "$instance_name" "$new_provider" "$api_key"
    fi
    
    echo
    print_success "Instance $instance_name provider set to: $new_provider"
    echo
    prompt_restart_instance "$instance_name"
}

cmd_instance_key() {
    local instance_name="$1"
    
    if ! instance_exists "$instance_name"; then
        print_error "Instance not found: $instance_name"
        return 1
    fi
    
    local provider
    provider=$(llm_get_effective_provider "$instance_name")
    
    local current_key=""
    if llm_instance_has_key_override "$instance_name" "$provider"; then
        current_key="(instance override)"
    elif [[ -n "$(get_global_api_key "$provider")" ]]; then
        current_key="(global)"
    fi
    
    echo
    echo -e "Instance: $instance_name"
    echo -e "Current provider: $provider"
    echo -e "Current API key: ${YELLOW}$current_key${NC}"
    echo
    
    local new_key
    new_key=$(prompt_api_key_choice "$provider" "instance")
    
    if [[ "$new_key" == "__CLEAR__" ]]; then
        llm_instance_clear_api_key "$instance_name" "$provider"
        print_success "Instance API key cleared - now using global"
    elif [[ -n "$new_key" ]]; then
        llm_instance_set_api_key "$instance_name" "$provider" "$new_key"
        print_success "Instance API key set (override)"
    fi
    
    echo
    prompt_restart_instance "$instance_name"
}

cmd_instance_key_clear() {
    local instance_name="$1"
    
    if ! instance_exists "$instance_name"; then
        print_error "Instance not found: $instance_name"
        return 1
    fi
    
    local provider
    provider=$(llm_get_effective_provider "$instance_name")
    
    llm_instance_clear_api_key "$instance_name" "$provider"
    
    print_success "Instance $instance_name API key cleared - now using global"
    echo
    prompt_restart_instance "$instance_name"
}

cmd_instance_reset() {
    local instance_name="$1"
    
    if ! instance_exists "$instance_name"; then
        print_error "Instance not found: $instance_name"
        return 1
    fi
    
    local current_provider current_model
    current_provider=$(llm_get_effective_provider "$instance_name")
    current_model=$(llm_get_effective_model "$instance_name")
    
    local global_provider global_model
    global_provider=$(get_global_provider)
    global_model=$(get_global_model)
    
    echo
    echo -e "${YELLOW}Instance: $instance_name${NC}"
    echo "This will remove all custom LLM settings."
    echo "Instance will use global config instead."
    echo
    echo -e "Current:  $current_provider / $current_model"
    echo -e "Global:   ${global_provider:-openrouter} / ${global_model:-x-ai/grok-4.1-fast}"
    echo
    read -p "Confirm reset? (y/n): " confirm
    
    if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
        print_info "Cancelled."
        return
    fi
    
    llm_instance_reset "$instance_name"
    
    print_success "Instance $instance_name reset to global config"
    echo
    prompt_restart_instance "$instance_name"
}

prompt_restart_all_instances() {
    echo
    echo -e "${YELLOW}All instances need to be restarted to apply changes.${NC}"
    local confirm
    read -r -p "Restart all instances now? (y/n): " confirm
    if [[ "$confirm" == "y" || "$confirm" == "Y" ]]; then
        manage_all_instances restart
    fi
}

prompt_restart_instance() {
    local instance_name="$1"
    echo
    echo -e "${YELLOW}Instance $instance_name needs to be restarted to apply changes.${NC}"
    local confirm
    read -r -p "Restart instance now? (y/n): " confirm
    if [[ "$confirm" == "y" || "$confirm" == "Y" ]]; then
        manage_instance restart "$instance_name"
    fi
}
