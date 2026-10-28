#!/usr/bin/env bash
# scripts/system.sh - System functions (update, rebuild)

update_nanobot() {
    print_header
    print_warning "This is a Docker-only setup!"
    echo
    echo "nanobot is built from nanobot-source/, pinned to commit $NANOBOT_PINNED_COMMIT"
    echo "(NANOBOT_PINNED_COMMIT in $SCRIPT_NAME). The patches target that commit."
    echo
    echo "To rebuild the image and apply it to your agents:"
    echo "  1. Rebuild the Docker image: $SCRIPT_NAME rebuild"
    echo "  2. Recreate the containers:  $SCRIPT_NAME update-all"
    echo
    read -p "Press Enter to continue..."
}

rebuild_docker_image() {
    print_header
    print_step "Rebuilding Docker image for nanobot..."
    
    build_nanobot_image || return 1
    
    print_info "To update instances, execute: $SCRIPT_NAME update-all"
}
