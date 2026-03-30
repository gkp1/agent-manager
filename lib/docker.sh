#!/usr/bin/env bash
# lib/docker.sh - Docker helper functions

docker_is_running() {
    docker info &> /dev/null
}

docker_ps_names() {
    docker ps --format "{{.Names}}" 2>/dev/null
}

docker_container_exists() {
    local container="$1"
    docker ps -a --format "{{.Names}}" 2>/dev/null | grep -q "^${container}$"
}

docker_container_running() {
    local container="$1"
    docker ps --format "{{.Names}}" 2>/dev/null | grep -q "^${container}$"
}

docker_instance_running() {
    local instance_name="$1"
    local container="nanobot-${instance_name}"
    docker_container_running "$container"
}

docker_start_instance() {
    local instance_dir="$1"
    cd "$instance_dir" && docker compose up -d && cd - > /dev/null 2>&1
}

docker_stop_instance() {
    local instance_dir="$1"
    cd "$instance_dir" && docker compose down && cd - > /dev/null 2>&1
}

docker_restart_instance() {
    local instance_dir="$1"
    cd "$instance_dir" && docker compose restart && cd - > /dev/null 2>&1
}

docker_logs_instance() {
    local instance_dir="$1"
    local lines="${2:-50}"
    cd "$instance_dir" && docker compose logs -f --tail "$lines"
}
