#!/usr/bin/env bash
# lib/config.sh - OS detection and config directory initialization

PATCH_WHATSAPP_AUDIO=true

detect_os() {
    case "$(uname -s)" in
        Linux*)     OS=Linux ;;
        Darwin*)    OS=Mac ;;
        CYGWIN*)    OS=Cygwin ;;
        MINGW*)     OS=MinGw ;;
        MSYS*)      OS=Ms ;;
        *)          OS="UNKNOWN:$(uname -s)"
    esac
    
    if [[ "$OS" == "UNKNOWN"* ]]; then
        print_error "Unsupported operating system: $(uname -s)"
        exit 1
    fi
}

check_command() {
    command -v "$1" &> /dev/null
}

init_config_dirs() {
    mkdir -p "$NANOBOT_HOME"
    mkdir -p "$NANOBOT_INSTANCES"
    mkdir -p "$BACKUP_DIR"
}

check_command() {
    command -v "$1" &> /dev/null
}

init_config_dirs() {
    mkdir -p "$NANOBOT_HOME"
    mkdir -p "$NANOBOT_INSTANCES"
    mkdir -p "$BACKUP_DIR"
}
