#!/usr/bin/env bash
# lib/llm.sh - LLM provider/model utilities, global config, API key handling

LLM_PROVIDERS=("openrouter" "openai" "anthropic" "deepseek" "groq" "custom")

get_provider_default_model() {
    local provider="$1"
    case $provider in
        openrouter)  echo "x-ai/grok-4.1-fast" ;;
        openai)      echo "gpt-4o" ;;
        anthropic)   echo "claude-sonnet-4-6" ;;
        deepseek)    echo "deepseek-chat" ;;
        groq)        echo "llama-3.3-70b-versatile" ;;
        custom)      echo "default" ;;
        *)           echo "x-ai/grok-4.1-fast" ;;
    esac
}

get_provider_env_key() {
    local provider="$1"
    case $provider in
        openrouter)  echo "OPENROUTER_API_KEY" ;;
        openai)      echo "OPENAI_API_KEY" ;;
        anthropic)   echo "ANTHROPIC_API_KEY" ;;
        deepseek)    echo "DEEPSEEK_API_KEY" ;;
        groq)        echo "GROQ_API_KEY" ;;
        custom)      echo "OPENAI_API_KEY" ;;
        *)           echo "OPENROUTER_API_KEY" ;;
    esac
}

get_provider_models_list() {
    local provider="$1"
    case $provider in
        openrouter)
            echo "x-ai/grok-4.1-fast"
            echo "anthropic/claude-sonnet-4-6"
            echo "anthropic/claude-opus-4-5"
            echo "google/gemini-2.5-pro-preview"
            echo "meta-llama/llama-4-maverick"
            ;;
        openai)
            echo "gpt-4o"
            echo "gpt-4-turbo"
            echo "gpt-4o-mini"
            echo "o1"
            echo "o3-mini"
            ;;
        anthropic)
            echo "claude-sonnet-4-6"
            echo "claude-opus-4-5"
            echo "claude-haiku-4-6"
            ;;
        deepseek)
            echo "deepseek-chat"
            echo "deepseek-reasoner"
            ;;
        groq)
            echo "llama-3.3-70b-versatile"
            echo "llama-3.1-405b-instruct"
            echo "mixtral-8x7b-32768"
            ;;
        custom)
            echo "default"
            ;;
        *)
            echo "x-ai/grok-4.1-fast"
            ;;
    esac
}

global_config_exists() {
    [[ -f "$GLOBAL_CONFIG" ]]
}

init_global_config() {
    if ! global_config_exists; then
        mkdir -p "$NANOBOT_HOME"
        cat > "$GLOBAL_CONFIG" << 'EOF'
{
  "global": {},
  "providers": {}
}
EOF
    fi
}

get_global_provider() {
    init_global_config
    python3 -c "
import json
with open('$GLOBAL_CONFIG') as f:
    c = json.load(f)
print(c.get('global', {}).get('provider', ''))
" 2>/dev/null
}

get_global_model() {
    init_global_config
    python3 -c "
import json
with open('$GLOBAL_CONFIG') as f:
    c = json.load(f)
print(c.get('global', {}).get('model', ''))
" 2>/dev/null
}

get_global_api_key() {
    local provider="$1"
    init_global_config
    python3 -c "
import json
with open('$GLOBAL_CONFIG') as f:
    c = json.load(f)
print(c.get('providers', {}).get('$provider', {}).get('apiKey', ''))
" 2>/dev/null
}

set_global_provider() {
    local provider="$1"
    init_global_config
    python3 << PYEOF
import json
with open('$GLOBAL_CONFIG', 'r') as f:
    c = json.load(f)
c.setdefault('global', {})['provider'] = '$provider'
with open('$GLOBAL_CONFIG', 'w') as f:
    json.dump(c, f, indent=2)
PYEOF
}

set_global_model() {
    local model="$1"
    init_global_config
    python3 << PYEOF
import json
with open('$GLOBAL_CONFIG', 'r') as f:
    c = json.load(f)
c.setdefault('global', {})['model'] = '$model'
with open('$GLOBAL_CONFIG', 'w') as f:
    json.dump(c, f, indent=2)
PYEOF
}

set_global_api_key() {
    local provider="$1"
    local api_key="$2"
    init_global_config
    python3 << PYEOF
import json
with open('$GLOBAL_CONFIG', 'r') as f:
    c = json.load(f)
c.setdefault('providers', {}).setdefault('$provider', {})['apiKey'] = '$api_key'
with open('$GLOBAL_CONFIG', 'w') as f:
    json.dump(c, f, indent=2)
PYEOF
}

clear_global_api_key() {
    local provider="$1"
    init_global_config
    python3 << PYEOF
import json
with open('$GLOBAL_CONFIG', 'r') as f:
    c = json.load(f)
if 'providers' in c and '$provider' in c['providers']:
    c['providers']['$provider'].pop('apiKey', None)
with open('$GLOBAL_CONFIG', 'w') as f:
    json.dump(c, f, indent=2)
PYEOF
}

clear_global_config() {
    if global_config_exists; then
        cat > "$GLOBAL_CONFIG" << 'EOF'
{
  "global": {},
  "providers": {}
}
EOF
    fi
}

show_global_config() {
    init_global_config
    echo
    echo -e "${CYAN}Global LLM Configuration${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    
    local provider model
    provider=$(get_global_provider)
    model=$(get_global_model)
    
    if [[ -n "$provider" ]]; then
        echo -e "  Provider: ${GREEN}$provider${NC}"
    else
        echo -e "  Provider: ${YELLOW}(not set)${NC}"
    fi
    
    if [[ -n "$model" ]]; then
        echo -e "  Model:    ${GREEN}$model${NC}"
    else
        echo -e "  Model:    ${YELLOW}(not set)${NC}"
    fi
    
    echo
    echo -e "${CYAN}API Keys (Global)${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━${NC}"
    
    for prov in "${LLM_PROVIDERS[@]}"; do
        local key
        key=$(get_global_api_key "$prov")
        if [[ -n "$key" ]]; then
            local masked="${key:0:8}...${key: -4}"
            echo -e "  $prov: ${GREEN}$masked${NC}"
        else
            echo -e "  $prov: ${YELLOW}not set${NC}"
        fi
    done
    echo
}

llm_instance_has_override() {
    local instance_name="$1"
    local instance_dir
    instance_dir=$(get_instance_dir "$instance_name")
    
    [[ ! -f "${instance_dir}/config.json" ]] && return 1
    
    local model provider
    model=$(python3 -c "
import json
with open('${instance_dir}/config.json') as f:
    c = json.load(f)
print(c.get('agents',{}).get('defaults',{}).get('model',''))
" 2>/dev/null)
    
    provider=$(python3 -c "
import json
with open('${instance_dir}/config.json') as f:
    c = json.load(f)
print(c.get('agents',{}).get('defaults',{}).get('provider',''))
" 2>/dev/null)
    
    [[ -n "$model" || -n "$provider" ]] && return 0
    return 1
}

llm_instance_has_key_override() {
    local instance_name="$1"
    local provider="$2"
    local instance_dir
    instance_dir=$(get_instance_dir "$instance_name")
    
    [[ ! -f "${instance_dir}/config.json" ]] && return 1
    
    local key
    key=$(python3 -c "
import json
with open('${instance_dir}/config.json') as f:
    c = json.load(f)
print(c.get('providers',{}).get('$provider',{}).get('apiKey',''))
" 2>/dev/null)
    
    [[ -n "$key" ]] && return 0
    return 1
}

llm_get_effective_provider() {
    local instance_name="$1"
    local instance_dir
    instance_dir=$(get_instance_dir "$instance_name")
    
    local instance_provider
    instance_provider=$(python3 -c "
import json
with open('${instance_dir}/config.json') as f:
    c = json.load(f)
print(c.get('agents',{}).get('defaults',{}).get('provider',''))
" 2>/dev/null)
    
    if [[ -n "$instance_provider" ]]; then
        echo "$instance_provider"
        return
    fi
    
    local global_provider
    global_provider=$(get_global_provider)
    if [[ -n "$global_provider" ]]; then
        echo "$global_provider"
        return
    fi
    
    echo "openrouter"
}

llm_get_effective_model() {
    local instance_name="$1"
    local instance_dir
    instance_dir=$(get_instance_dir "$instance_name")
    
    local instance_model
    instance_model=$(python3 -c "
import json
with open('${instance_dir}/config.json') as f:
    c = json.load(f)
print(c.get('agents',{}).get('defaults',{}).get('model',''))
" 2>/dev/null)
    
    if [[ -n "$instance_model" ]]; then
        echo "$instance_model"
        return
    fi
    
    local global_model
    global_model=$(get_global_model)
    if [[ -n "$global_model" ]]; then
        echo "$global_model"
        return
    fi
    
    echo "x-ai/grok-4.1-fast"
}

llm_get_effective_api_key() {
    local instance_name="$1"
    local provider="$2"
    local instance_dir
    instance_dir=$(get_instance_dir "$instance_name")
    
    local instance_key
    instance_key=$(python3 -c "
import json
with open('${instance_dir}/config.json') as f:
    c = json.load(f)
print(c.get('providers',{}).get('$provider',{}).get('apiKey',''))
" 2>/dev/null)
    
    if [[ -n "$instance_key" ]]; then
        echo "$instance_key"
        return
    fi
    
    local global_key
    global_key=$(get_global_api_key "$provider")
    echo "$global_key"
}

llm_get_effective_source() {
    local instance_name="$1"
    local instance_dir
    instance_dir=$(get_instance_dir "$instance_name")
    
    local instance_model
    instance_model=$(python3 -c "
import json
with open('${instance_dir}/config.json') as f:
    c = json.load(f)
print(c.get('agents',{}).get('defaults',{}).get('model',''))
" 2>/dev/null)
    
    if [[ -n "$instance_model" ]]; then
        echo "CUSTOM"
        return
    fi
    
    local global_provider
    global_provider=$(get_global_provider)
    if [[ -n "$global_provider" ]]; then
        echo "GLOBAL"
        return
    fi
    
    echo "DEFAULT"
}

llm_instance_set_model() {
    local instance_name="$1"
    local model="$2"
    local instance_dir
    instance_dir=$(get_instance_dir "$instance_name")
    
    python3 << PYEOF
import json
with open('${instance_dir}/config.json', 'r') as f:
    c = json.load(f)
c.setdefault('agents', {}).setdefault('defaults', {})['model'] = '$model'
with open('${instance_dir}/config.json', 'w') as f:
    json.dump(c, f, indent=2)
PYEOF
}

llm_instance_set_provider() {
    local instance_name="$1"
    local provider="$2"
    local instance_dir
    instance_dir=$(get_instance_dir "$instance_name")
    
    python3 << PYEOF
import json
with open('${instance_dir}/config.json', 'r') as f:
    c = json.load(f)
c.setdefault('agents', {}).setdefault('defaults', {})['provider'] = '$provider'
with open('${instance_dir}/config.json', 'w') as f:
    json.dump(c, f, indent=2)
PYEOF
}

llm_instance_set_api_key() {
    local instance_name="$1"
    local provider="$2"
    local api_key="$3"
    local instance_dir
    instance_dir=$(get_instance_dir "$instance_name")
    
    python3 << PYEOF
import json
with open('${instance_dir}/config.json', 'r') as f:
    c = json.load(f)
c.setdefault('providers', {}).setdefault('$provider', {})['apiKey'] = '$api_key'
with open('${instance_dir}/config.json', 'w') as f:
    json.dump(c, f, indent=2)
PYEOF
}

llm_instance_clear_api_key() {
    local instance_name="$1"
    local provider="$2"
    local instance_dir
    instance_dir=$(get_instance_dir "$instance_name")
    
    python3 << PYEOF
import json
with open('${instance_dir}/config.json', 'r') as f:
    c = json.load(f)
if 'providers' in c and '$provider' in c['providers']:
    c['providers']['$provider'].pop('apiKey', None)
with open('${instance_dir}/config.json', 'w') as f:
    json.dump(c, f, indent=2)
PYEOF
}

llm_instance_reset() {
    local instance_name="$1"
    local instance_dir
    instance_dir=$(get_instance_dir "$instance_name")
    
    python3 << PYEOF
import json
with open('${instance_dir}/config.json', 'r') as f:
    c = json.load(f)
if 'agents' in c and 'defaults' in c['agents']:
    c['agents'].pop('defaults', None)
if 'providers' in c:
    c.pop('providers', None)
with open('${instance_dir}/config.json', 'w') as f:
    json.dump(c, f, indent=2)
PYEOF
}

llm_instance_apply_global() {
    local instance_name="$1"
    local instance_dir
    instance_dir=$(get_instance_dir "$instance_name")
    
    local global_provider global_model
    global_provider=$(get_global_provider)
    global_model=$(get_global_model)
    
    if [[ -z "$global_provider" && -z "$global_model" ]]; then
        return 1
    fi
    
    python3 << PYEOF
import json
with open('${instance_dir}/config.json', 'r') as f:
    c = json.load(f)
    
if '$global_provider':
    c.setdefault('agents', {}).setdefault('defaults', {})['provider'] = '$global_provider'
if '$global_model':
    c.setdefault('agents', {}).setdefault('defaults', {})['model'] = '$global_model'
    
with open('${instance_dir}/config.json', 'w') as f:
    json.dump(c, f, indent=2)
PYEOF
}

show_instance_effective_config() {
    local instance_name="$1"
    
    local provider model source key_source
    provider=$(llm_get_effective_provider "$instance_name")
    model=$(llm_get_effective_model "$instance_name")
    source=$(llm_get_effective_source "$instance_name")
    
    if llm_instance_has_key_override "$instance_name" "$provider"; then
        key_source="INSTANCE"
    elif [[ -n "$(get_global_api_key "$provider")" ]]; then
        key_source="GLOBAL"
    else
        key_source="NOT SET"
    fi
    
    echo
    echo -e "${CYAN}Instance: $instance_name${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "  Source:     ${GREEN}$source${NC}"
    echo -e "  Provider:   $provider"
    echo -e "  Model:      $model"
    echo -e "  API Key:    $key_source"
    echo
}

prompt_api_key_choice() {
    local provider="$1"
    local scope="$2"
    
    local current_key
    if [[ "$scope" == "global" ]]; then
        current_key=$(get_global_api_key "$provider")
    fi
    
    echo
    echo -e "${CYAN}API Key Configuration for $provider${NC}"
    echo -e "${CYAN}─────────────────────────────────────${NC}"
    
    if [[ -n "$current_key" ]]; then
        local masked="${current_key:0:10}...${current_key: -4}"
        echo -e "  Current: ${GREEN}$masked${NC}"
        echo
        echo -e "  [1] Keep current API key"
        echo -e "  [2] Enter new API key"
        echo -e "  [3] Clear API key"
    else
        echo -e "  Current: ${YELLOW}not set${NC}"
        echo
        echo -e "  [1] Enter new API key"
        echo -e "  [2] Skip (no API key)"
    fi
    echo
    read -p "Choose [1-${current_key:+3}]: " choice
    
    case ${choice:-1} in
        1)
            if [[ -n "$current_key" ]]; then
                echo "$current_key"
            else
                read -p "Enter API key: " new_key
                echo "$new_key"
            fi
            ;;
        2)
            if [[ -n "$current_key" ]]; then
                read -p "Enter new API key: " new_key
            else
                read -p "Enter API key: " new_key
            fi
            echo "$new_key"
            ;;
        3)
            echo "__CLEAR__"
            ;;
        *)
            echo "$current_key"
            ;;
    esac
}

select_llm_provider_interactive() {
    echo
    print_step "Select LLM provider:"
    echo
    echo -e "  ${GREEN}1) OpenRouter${NC} (recommended) - global access to all models"
    echo -e "  2) OpenAI - Direct OpenAI API"
    echo -e "  3) Anthropic - Direct Claude API"
    echo -e "  4) DeepSeek - Chinese models"
    echo -e "  5) Groq - Fast inference"
    echo -e "  6) Custom - OpenAI-compatible"
    echo
    read -p "Choose provider [1]: " provider_choice

    case ${provider_choice:-1} in
        1) echo "openrouter" ;;
        2) echo "openai" ;;
        3) echo "anthropic" ;;
        4) echo "deepseek" ;;
        5) echo "groq" ;;
        6) echo "custom" ;;
        *) echo "openrouter" ;;
    esac
}

select_model_interactive() {
    local provider="$1"
    local current_model="${2:-}"
    
    echo
    echo -e "Models for $provider:"
    local models=()
    local i=1
    while IFS= read -r model; do
        models+=("$model")
        if [[ "$model" == "$current_model" ]]; then
            echo -e "  ${GREEN}$i) $model (current)${NC}"
        else
            echo -e "  $i) $model"
        fi
        ((i++))
    done < <(get_provider_models_list "$provider")
    echo -e "  $i) Other model"
    echo
    read -p "Choose model [1]: " model_choice

    local selected_model="$current_model"
    local choice_num=${model_choice:-1}
    
    if [[ "$choice_num" -eq $i ]]; then
        read -p "Custom model: " selected_model
    elif [[ "$choice_num" -ge 1 && "$choice_num" -lt $i ]]; then
        selected_model="${models[$((choice_num-1))]}"
    fi
    
    [[ -z "$selected_model" ]] && selected_model=$(get_provider_default_model "$provider")
    echo "$selected_model"
}
