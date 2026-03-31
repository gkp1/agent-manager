#!/usr/bin/env bash
# xnanobot.sh - AI Manager: Main dispatcher
# Usage: ./xnanobot.sh [command] [options]

set -euo pipefail

SCRIPT_NAME="$(basename "$0")"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AIMANAGER_DIR="$SCRIPT_DIR"
NANOBOT_HOME="${HOME}/.nanobot"
NANOBOT_INSTANCES="${AIMANAGER_DIR}/nanobot-instances"
NANOBOT_REPO="https://github.com/HKUDS/nanobot.git"
NANOBOT_SOURCE_DIR="${AIMANAGER_DIR}/nanobot-source"
BACKUP_DIR="${AIMANAGER_DIR}/backups"
GLOBAL_CONFIG="${NANOBOT_HOME}/global-config.json"
PATCH_WHATSAPP_AUDIO=true
PATCH_VECTOR_MEMORY=true

export AIMANAGER_DIR NANOBOT_HOME NANOBOT_INSTANCES BACKUP_DIR GLOBAL_CONFIG

LIB_DIR="${SCRIPT_DIR}/lib"
SCRIPTS_DIR="${SCRIPT_DIR}/scripts"

source "${LIB_DIR}/colors.sh"
source "${LIB_DIR}/config.sh"
source "${LIB_DIR}/docker.sh"
source "${LIB_DIR}/instance.sh"
source "${LIB_DIR}/channel.sh"
source "${LIB_DIR}/llm.sh"
source "${LIB_DIR}/llm_commands.sh"
source "${LIB_DIR}/menu_llm.sh"
source "${LIB_DIR}/menu_memory.sh"

source "${SCRIPTS_DIR}/setup.sh"
source "${SCRIPTS_DIR}/instance.sh"
source "${SCRIPTS_DIR}/control.sh"
source "${SCRIPTS_DIR}/whatsapp.sh"
source "${SCRIPTS_DIR}/system.sh"
source "${SCRIPTS_DIR}/menu.sh"

detect_os
init_config_dirs

main() {
    local command="${1:-}"
    
    case "$command" in
        install) install_nanobot ;;
        setup) setup_initial ;;
        setup-wizard) setup_initial --wizard ;;
        setup-guide) setup_guide_flow ;;
        build) build_nanobot_image ;;
        create) create_docker_instance ;;
        create-multi) create_multi_instances ;;
        list) list_instances ;;
        start)
            [[ -z "${2:-}" ]] && { print_error "Specify instance name"; exit 1; }
            manage_instance start "$2"
            ;;
        stop)
            [[ -z "${2:-}" ]] && { print_error "Specify instance name"; exit 1; }
            manage_instance stop "$2"
            ;;
        restart)
            [[ -z "${2:-}" ]] && { print_error "Specify instance name"; exit 1; }
            manage_instance restart "$2"
            ;;
        logs)
            [[ -z "${2:-}" ]] && { print_error "Specify instance name"; exit 1; }
            manage_instance logs "$2"
            ;;
        status)
            [[ -z "${2:-}" ]] && { print_error "Specify instance name"; exit 1; }
            manage_instance status "$2"
            ;;
        chat)
            [[ -z "${2:-}" ]] && { print_error "Specify instance name"; exit 1; }
            manage_instance chat "$2"
            ;;
        login)
            [[ -z "${2:-}" ]] && { print_error "Specify instance name"; exit 1; }
            manage_instance login-whatsapp "$2"
            ;;
        reconnect)
            [[ -z "${2:-}" ]] && { print_error "Specify instance name"; exit 1; }
            reconnect_whatsapp "$2"
            ;;
        upgrade-bridge)
            [[ -z "${2:-}" ]] && { print_error "Specify instance name"; exit 1; }
            upgrade_whatsapp_bridge "$2"
            ;;
        configure-wa)
            [[ -z "${2:-}" ]] && { print_error "Specify instance name"; exit 1; }
            configure_whatsapp_instance "$2"
            ;;
        delete|remove|rm) delete_instance "${2:-}" ;;
        start-all) manage_all_instances start ;;
        stop-all) manage_all_instances stop ;;
        restart-all) manage_all_instances restart ;;
        update-all) manage_all_instances update ;;
        update) update_nanobot ;;
        rebuild) rebuild_docker_image ;;
        check) check_prerequisites ;;
        configure) configure_instance_menu ;;
        global-set) cmd_global_set ;;
        global-provider) cmd_global_provider ;;
        global-model) cmd_global_model ;;
        global-key) cmd_global_key ;;
        global-show) cmd_global_show ;;
        global-clear) cmd_global_clear ;;
        instance-show)
            [[ -z "${2:-}" ]] && { print_error "Specify instance name"; exit 1; }
            cmd_instance_show "$2"
            ;;
        instance-model)
            [[ -z "${2:-}" ]] && { print_error "Specify instance name"; exit 1; }
            cmd_instance_model "$2"
            ;;
        instance-provider)
            [[ -z "${2:-}" ]] && { print_error "Specify instance name"; exit 1; }
            cmd_instance_provider "$2"
            ;;
        instance-key)
            [[ -z "${2:-}" ]] && { print_error "Specify instance name"; exit 1; }
            cmd_instance_key "$2"
            ;;
        instance-key-clear)
            [[ -z "${2:-}" ]] && { print_error "Specify instance name"; exit 1; }
            cmd_instance_key_clear "$2"
            ;;
        instance-reset)
            [[ -z "${2:-}" ]] && { print_error "Specify instance name"; exit 1; }
            cmd_instance_reset "$2"
            ;;
        global-vector)
            shift
            cmd_global_vector "${1:-}"
            ;;
        instance-vector)
            [[ -z "${2:-}" ]] && { print_error "Specify instance name"; exit 1; }
            local inst="$2"
            shift 2
            cmd_instance_vector "$inst" "${1:-}"
            ;;
        interactive|"") interactive_menu ;;
        help|--help|-h) show_help ;;
        *) print_error "Unknown command: $command"; show_help; exit 1 ;;
    esac
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    if [[ $# -eq 0 ]]; then
        interactive_menu
    else
        main "$@"
    fi
fi
