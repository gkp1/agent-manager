#!/usr/bin/env bash
# lib/config.sh - OS detection, config directory initialization, JSON config editing

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

# json_edit FILE CODE [NAME=value...]
# Loads FILE into the dict `c`, runs the Python CODE, then writes `c` back.
# Values are passed as NAME=value arguments and read in CODE as env['NAME'],
# so quotes or backslashes in user input can't break the Python source.
json_edit() {
    local file="$1"
    local code="$2"
    shift 2
    env "$@" JSON_FILE="$file" python3 -c "
import json, os
env = os.environ
with open(env['JSON_FILE'], 'r') as f:
    c = json.load(f)
${code}
with open(env['JSON_FILE'], 'w') as f:
    json.dump(c, f, indent=2)
"
}
