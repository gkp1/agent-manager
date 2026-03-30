#!/usr/bin/env bash
# scripts/system.sh - System functions (update, rebuild)

update_nanobot() {
    print_header
    print_warning "This is a Docker-only setup!"
    echo
    echo "To update nanobot in Docker containers:"
    echo "  1. Rebuild the Docker image: $SCRIPT_NAME rebuild"
    echo "  2. Restart instances: $SCRIPT_NAME restart-all"
    echo
    echo "The nanobot-source/ directory contains the source code."
    echo "Use '$SCRIPT_NAME rebuild' to rebuild the Docker image."
    echo
    read -p "Press Enter to continue..."
}

rebuild_docker_image() {
    print_header
    print_step "Rebuilding Docker image for nanobot..."
    
    if [[ ! -d "$NANOBOT_SOURCE_DIR" ]]; then
        print_step "Cloning repository..."
        git clone "$NANOBOT_REPO" "$NANOBOT_SOURCE_DIR"
    else
        print_step "Updating repository..."
        cd "$NANOBOT_SOURCE_DIR" && git pull && cd - > /dev/null 2>&1
    fi
    
    if [[ "$PATCH_WHATSAPP_AUDIO" == "true" ]]; then
        apply_audio_patch "$NANOBOT_SOURCE_DIR"
    fi

    cd "$NANOBOT_SOURCE_DIR"
    docker build -t nanobot .
    cd - > /dev/null 2>&1
    
    print_success "Docker image rebuilt!"
    print_info "To update instances, execute: $SCRIPT_NAME update-all"
}
