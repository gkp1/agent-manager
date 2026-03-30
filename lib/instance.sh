#!/usr/bin/env bash
# lib/instance.sh - Instance discovery, validation

get_instance_dir() {
    local instance_name="$1"
    echo "${NANOBOT_INSTANCES}/${instance_name}"
}

instance_exists() {
    local instance_name="$1"
    local instance_dir
    instance_dir=$(get_instance_dir "$instance_name")
    [[ -d "$instance_dir" ]] && [[ -f "${instance_dir}/docker-compose.yml" ]]
}

get_instance_channel() {
    local instance_dir="$1"
    python3 -c "
import json
valid = ['whatsapp','telegram','discord','feishu','slack','matrix','email']
with open('${instance_dir}/config.json') as f:
    c = json.load(f)
chs = [k for k in valid if c.get('channels',{}).get(k,{}).get('enabled',False)]
print(chs[0] if chs else '?')
" 2>/dev/null || echo "?"
}

get_instance_model() {
    local instance_name="$1"
    local instance_dir
    instance_dir=$(get_instance_dir "$instance_name")
    python3 -c "
import json
with open('${instance_dir}/config.json') as f:
    c = json.load(f)
print(c.get('agents',{}).get('defaults',{}).get('model','?'))
" 2>/dev/null || echo "?"
}

get_instance_provider() {
    local instance_name="$1"
    local instance_dir
    instance_dir=$(get_instance_dir "$instance_name")
    python3 -c "
import json
with open('${instance_dir}/config.json') as f:
    c = json.load(f)
print(c.get('agents',{}).get('defaults',{}).get('provider','auto'))
" 2>/dev/null || echo "?"
}

list_instances() {
    local instances=()
    for dir in "${NANOBOT_INSTANCES}"/*/; do
        if [[ -f "${dir}docker-compose.yml" ]]; then
            instances+=("$(basename "$dir")")
        fi
    done
    echo "${instances[@]}"
}

get_instance_status() {
    local instance_name="$1"
    local container="nanobot-${instance_name}"
    
    if docker_container_running "$container"; then
        local ch
        ch=$(get_instance_channel "$(get_instance_dir "$instance_name")")
        if [[ "$ch" == "whatsapp" ]]; then
            local last
            last=$(docker logs "$container" 2>&1 | grep -E "✅ Connected to WhatsApp|WhatsApp status:" | tail -1)
            if [[ "$last" == *"Connected"* ]]; then
                echo "connected"
            elif [[ "$last" == *"disconnected"* ]]; then
                echo "disconnected"
            else
                echo "running"
            fi
        else
            echo "running"
        fi
    else
        echo "stopped"
    fi
}
