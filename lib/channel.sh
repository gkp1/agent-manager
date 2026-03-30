#!/usr/bin/env bash
# lib/channel.sh - Channel validation, config parsing

VALID_CHANNELS=("whatsapp" "telegram" "discord" "feishu" "slack" "matrix" "email")

is_valid_channel() {
    local channel="$1"
    for valid in "${VALID_CHANNELS[@]}"; do
        [[ "$channel" == "$valid" ]] && return 0
    done
    return 1
}

channel_from_number() {
    local num="$1"
    case $num in
        1) echo "whatsapp" ;;
        2) echo "telegram" ;;
        3) echo "discord" ;;
        4) echo "feishu" ;;
        5) echo "slack" ;;
        6) echo "matrix" ;;
        7) echo "email" ;;
        *) echo "whatsapp" ;;
    esac
}

get_channel_name() {
    local channel="$1"
    echo "$channel"
}

print_channel_info() {
    local channel="$1"
    
    case $channel in
        whatsapp)
            echo "WhatsApp - Multi-device support via Baileys"
            ;;
        telegram)
            echo "Telegram - Bot API"
            ;;
        discord)
            echo "Discord - Bot with intents"
            ;;
        feishu)
            echo "Feishu/Lark - Chinese collaboration platform"
            ;;
        slack)
            echo "Slack - Bot with events API"
            ;;
        matrix)
            echo "Matrix - Decentralized chat protocol"
            ;;
        email)
            echo "Email - IMAP/SMTP"
            ;;
        *)
            echo "Unknown channel"
            ;;
    esac
}
