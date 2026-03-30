#!/usr/bin/env bash
# xnanobot.sh - AI Manager: Script for setup and management of nanobot instances
# Author: Created by opencode to help manage nanobot
# Usage: ./xnanobot.sh [commands [options]]

set -euo pipefail

# Script name (for dynamic display)
SCRIPT_NAME="$(basename "$0")"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# ============================================================
# PATCH CONFIGURATION
# ============================================================
PATCH_WHATSAPP_AUDIO=true  # true = apply WhatsApp audio patch on build

# Diretório base do aimanager (deve vir primeiro)
# Use readlink to resolve symlinks correctly
SCRIPT_PATH="$(readlink -f "$0" 2>/dev/null || echo "$0")"
AIMANAGER_DIR="$(cd "$(dirname "$SCRIPT_PATH")" && pwd)"

# Default directories
NANOBOT_HOME="${HOME}/.nanobot"
NANOBOT_INSTANCES="${AIMANAGER_DIR}/nanobot-instances"
NANOBOT_REPO="https://github.com/HKUDS/nanobot.git"
NANOBOT_SOURCE_DIR="${AIMANAGER_DIR}/nanobot-source"  # Fonte do nanobot
BACKUP_DIR="${AIMANAGER_DIR}/backups"  # Backups de instances

# Funções auxiliares (devem vir antes de check_os)
print_header() {
    echo -e "${PURPLE}════════════════════════════════════════════${NC}"
    echo -e "${PURPLE}   🐈 Nanobot Helper Script${NC}"
    echo -e "${PURPLE}════════════════════════════════════════════${NC}"
    echo
}

print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_step() {
    echo -e "${CYAN}[STEP]${NC} $1"
}

# Agent status cache
AGENT_STATUS_CACHE=""
AGENT_STATUS_CACHE_TIME=0

# Get channel of an instance
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

# Get agent status (with 30s cache)
get_agents_status() {
    local current_time=$(date +%s)
    local cache_age=$((current_time - AGENT_STATUS_CACHE_TIME))
    
    # Return cache if < 30s
    if [[ -n "$AGENT_STATUS_CACHE" && $cache_age -lt 30 ]]; then
        echo -e "$AGENT_STATUS_CACHE"
        return
    fi
    
    local output=""
    
    for dir in "$NANOBOT_INSTANCES"/*/; do
        [[ -f "${dir}docker-compose.yml" ]] || continue
        local name=$(basename "$dir")
        local container="nanobot-${name}"
        
        if docker ps --format "{{.Names}}" 2>/dev/null | grep -q "^${container}$"; then
            local ch=$(get_instance_channel "$dir")
            if [[ "$ch" == "whatsapp" ]]; then
                local last=$(docker logs "$container" 2>&1 | grep -E "✅ Connected to WhatsApp|WhatsApp status: (connected|disconnected)" 2>/dev/null | tail -1)
                if [[ "$last" == *"Connected"* ]] || [[ "$last" == *"connected"* ]]; then
                    output+="  [${name}] WhatsApp ${GREEN}✅ Connected${NC}\n"
                elif [[ "$last" == *"disconnected"* ]]; then
                    output+="  [${name}] WhatsApp ${YELLOW}⚠️ Disconnected${NC}\n"
                else
                    output+="  [${name}] WhatsApp ${BLUE}❓ Unknown${NC}\n"
                fi
            else
                output+="  [${name}] ${ch} ${GREEN}● Running${NC}\n"
            fi
        else
            output+="  [${name}] ⚫ Offline\n"
        fi
    done
    
    if [[ -z "$output" ]]; then
        output="  No agents\n"
    fi
    
    AGENT_STATUS_CACHE="$output"
    AGENT_STATUS_CACHE_TIME=$current_time
    echo -e "$output"
}

# Detect operating system
check_os() {
    case "$(uname -s)" in
        Linux*)     OS=Linux ;;
        Darwin*)    OS=Mac ;;
        CYGWIN*)    OS=Cygwin ;;
        MINGW*)     OS=MinGw ;;
        MSYS*)      OS=MSys ;;
        *)          OS="UNKNOWN:$(uname -s)"
    esac
    
    if [[ "$OS" == "UNKNOWN"* ]]; then
        print_error "Unsupported operating system: $(uname -s)"
        print_info "This script requires Linux, macOS, or Windows with WSL."
        exit 1
    fi
    
    print_info "Operating system detected: $OS"
}

check_os

check_command() {
    if ! command -v "$1" &> /dev/null; then
        return 1
    fi
}

check_dependencies() {
    print_step "Checking dependencies..."
    local missing=()
    
    # Docker
    if ! check_command docker; then
        missing+=("docker")
        print_warning "Docker not found. Docker is required for Docker instances."
    fi
    
    # Docker Compose (v2+)
    if ! docker compose version &> /dev/null; then
        missing+=("docker-compose")
        print_warning "Docker Compose (v2+) not found."
    fi
    
    # Check if Docker is running
    if command -v docker &> /dev/null; then
        if ! docker info &> /dev/null; then
            print_warning "Docker is not running. Please start the Docker service."
        fi
    fi
    
    # Git
    if ! check_command git; then
        missing+=("git")
        print_warning "Git not found."
    fi
    
    # Python
    if ! check_command python3 && ! check_command python; then
        missing+=("python3")
        print_warning "Python not found."
    fi
    
    # Pip
    if ! check_command pip3 && ! check_command pip; then
        missing+=("pip")
        print_warning "Pip not found."
    fi
    
    if [ ${#missing[@]} -gt 0 ]; then
        print_warning "Missing dependencies: ${missing[*]}"
        echo "Install required dependencies before continuing."
        return 1
    fi
    
    print_success "All dependencies found!"
    return 0
}

# ============================================================
# Docker Multi-Tenant Guide Functions
# ============================================================

check_prerequisites() {
    print_step "Checking prerequisites (as per guide)..."
    
    # Docker version (20.10+)
    local docker_version
    if command -v docker &> /dev/null; then
        docker_version=$(docker --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+')
        print_info "Docker version: $docker_version"
    else
        print_error "Docker not found."
        return 1
    fi
    
    # Docker Compose version (2.0+)
    local compose_version
    if docker compose version &> /dev/null; then
        compose_version=$(docker compose version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+')
        print_info "Docker Compose version: $compose_version"
    else
        print_error "Docker Compose not found."
        return 1
    fi
    
    print_success "Prerequisites OK: Docker $docker_version, Docker Compose $compose_version"
    return 0
}

# ============================================================
# PATCH: WhatsApp Audio Download
# ============================================================

apply_audio_patch() {
    local repo_dir="$1"
    local whatsapp_file="${repo_dir}/bridge/src/whatsapp.ts"
    
    if [[ ! -f "$whatsapp_file" ]]; then
        print_error "whatsapp.ts file not found: $whatsapp_file"
        return 1
    fi
    
    # Verificar se patch já foi aplicado
    if grep -q "unwrapped.audioMessage" "$whatsapp_file"; then
        print_info "Audio patch already applied."
        return 0
    fi
    
    print_step "Applying audio patch WhatsApp..."
    
    # Use environment variable to pass filepath, heredoc with single quotes to prevent bash expansion
    WHATSAPP_FILE="$whatsapp_file" python3 << 'PYEOF'
import sys, os

filepath = os.environ.get('WHATSAPP_FILE', '')
if not filepath:
    print('ERROR: WHATSAPP_FILE not set.')
    sys.exit(1)

with open(filepath, 'r') as f:
    content = f.read()

if 'unwrapped.audioMessage' in content:
    print('Patch already applied.')
    sys.exit(0)

# Build the audio block (without leading } else if since we replace the closing })
BT = '`'
audio_block = (
    "        } else if (unwrapped.audioMessage) {\n"
    "          fallbackContent = '[Voice Message]';\n"
    "          const audioMime = unwrapped.audioMessage.mimetype ?? 'audio/ogg; codecs=opus';\n"
    "          const path = await this.downloadMedia(msg, audioMime);\n"
    "          if (path) {\n"
    "            mediaPaths.push(path);\n"
    f"            fallbackContent += {BT} (${{path}}){BT};\n"
    "          }\n"
    "        }"
)

# Find the closing } of videoMessage block and replace it with audio block
# The pattern is: after "if (path) mediaPaths.push(path);" comes a line with just "        }"
lines = content.split('\n')
new_lines = []
replaced = False

for i, line in enumerate(lines):
    if not replaced and line.strip() == '}' and i > 0:
        # Check if previous line contains mediaPaths.push
        if i > 0 and 'mediaPaths.push(path)' in lines[i-1]:
            # Replace this closing } with the audio block
            new_lines.append(audio_block)
            replaced = True
            continue
    new_lines.append(line)

if replaced:
    with open(filepath, 'w') as f:
        f.write('\n'.join(new_lines))
    print('Patch applied successfully.')
else:
    print('ERROR: Could not find insertion point.')
    sys.exit(1)
PYEOF
    
    if [[ $? -eq 0 ]]; then
        print_success "Audio patch applied!"
        return 0
    else
        print_error "Failed to apply audio patch."
        return 1
    fi
}

build_nanobot_image() {
    print_step "Building Docker image for nanobot (as per guide)..."
    
    # Clone or update repository
    if [[ ! -d "$NANOBOT_SOURCE_DIR" ]]; then
        print_step "Cloning nanobot repository..."
        git clone "$NANOBOT_REPO" "$NANOBOT_SOURCE_DIR"
    else
        print_step "Updating repository..."
        cd "$NANOBOT_SOURCE_DIR" && git pull && cd -
    fi
    
    # Apply audio patch if enabled
    if [[ "$PATCH_WHATSAPP_AUDIO" == "true" ]]; then
        apply_audio_patch "$NANOBOT_SOURCE_DIR"
    fi
    
    # Build image
    print_step "Executing: docker build -t nanobot ."
    cd "$NANOBOT_SOURCE_DIR"
    docker build -t nanobot .
    cd - > /dev/null 2>&1
    
    print_success "Docker image built successfully!"
    return 0
}

setup_guide_flow() {
    print_header
    print_step "Setup complete following Docker Multi-Tenant guide..."
    echo
    echo "This command runs the full guide workflow:"
    echo "1. Check prerequisites - Docker 20.10+, Docker Compose 2.0+"
    echo "2. Build Docker image do nanobot"
    echo "3. Create isolated Docker instance"
    echo
    read -p "Continue? (y/n): " confirm
    
    if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
        print_info "Setup cancelled."
        return 0
    fi
    
    # 1. Check prerequisites
    if ! check_prerequisites; then
        print_error "Prerequisites not met. Install Docker and Docker Compose."
        return 1
    fi
    
    # 2. Build Docker image
    if ! build_nanobot_image; then
        print_error "Failed to build Docker image."
        return 1
    fi
    
    # 3. Create instance
    echo
    print_step "Now let us create your first Docker instance..."
    create_docker_instance
}

# ============================================================
# Installation functions (DEPRECATED - Docker-only setup)
# ============================================================
# NOTE: This is a Docker-only setup. All nanobot instances run in Docker containers.
# The Docker image is built via build_nanobot_image() using nanobot-source/.
# These functions are kept for reference but are not used.

install_nanobot() {
    print_header
    print_warning "This is a Docker-only setup!"
    echo
    echo "All nanobot agents run in isolated Docker containers."
    echo "No host-side installation needed."
    echo
    echo "To build the Docker image, use:"
    echo "  $SCRIPT_NAME build"
    echo
    read -p "Press Enter to continue..."
}

# ============================================================
# Configuration functions
# ============================================================

setup_initial() {
    print_header
    print_step "Initial nanobot setup..."
    
    # Check if nanobot is installed
    if ! check_command nanobot; then
        print_warning "nanobot not found. Installing..."
        install_nanobot_pip
    fi
    
    print_step "Running onboarding..."
    if [[ "$1" == "--wizard" ]]; then
        nanobot onboard --wizard
    else
        nanobot onboard
    fi
    
    print_success "Initial setup completed!"
    print_info "Edit ~/.nanobot/config.json to add your API keys."
}

configure_channel() {
    local channel="$1"
    local instance_name="$2"
    
    print_step "Configuring channel: $channel"
    
    case $channel in
        whatsapp)
            echo "To configure WhatsApp:"
            echo "1. Make sure nanobot is running - nanobot gateway"
            echo "2. Execute: nanobot channels login whatsapp"
            echo "3. Scan the QR Code with your WhatsApp"
            echo "4. Configure em config.json da instance:"
            echo '   "channels": {'
            echo '     "whatsapp": {'
            echo '       "enabled": true,'
            echo '       "allowFrom": ["+5511999999999"],   # ou ["*"] para qualquer pessoa'
            echo '       "groupPolicy": "mention"            # mention|open'
            echo '     }'
            echo '   }'
            echo
            echo "Configuration options:"
            echo "  allowFrom:"
            echo '    ["+5511999999999"]  - Apenas números específicos'
            echo '    ["*"]              - Anyone can use'
            echo "  groupPolicy:"
            echo '    "mention"  - Only replies when @mentioned in groups - default'
            echo '    "open"     - Responds to all group messages'
            echo
            echo "Dip: Use '$SCRIPT_NAME configure-wa <instance>' to configure interactively"
            echo
            echo "Important: After updating nanobot, recreate the session:"
            echo "   $SCRIPT_NAME upgrade-bridge <instance>"
            ;;
        telegram)
            echo "To configure Telegram:"
            echo "1. Open Telegram, search for @BotFather"
            echo "2. Send /newbot and follow instructions"
            echo "3. Copy the bot token"
            echo "4. Configure in ~/.nanobot/config.json:"
            echo '   "channels": { "telegram": { "enabled": true, "token": "YOUR_TOKEN", "allowFrom": ["YOUR_USER_ID"] } }'
            echo
            echo "Tip: Your User ID appears in Telegram settings as @yourUserId"
            echo "Copy the value WITHOUT the @ symbol"
            ;;
        discord)
            echo "To configure Discord:"
            echo "1. Access https://discord.com/developers/applications"
            echo "2. Create an application → Bot → Add Bot"
            echo "3. Copy the bot token"
            echo "4. Enable MESSAGE CONTENT INTENT in Bot settings"
            echo "5. Configure in ~/.nanobot/config.json:"
            echo '   "channels": { "discord": { "enabled": true, "token": "YOUR_TOKEN", "allowFrom": ["YOUR_USER_ID"], "groupPolicy": "mention" } }'
            echo
            echo "To get your User ID:"
            echo "  - Discord Settings → Advanced → Enable Developer Mode"
            echo "  - Right-click on your avatar → Copy User ID"
            ;;
        feishu)
            echo "To configure Feishu:"
            echo "1. Access https://open.feishu.cn/app"
            echo "2. Create a new app → Enable Bot capability"
            echo "3. Permissions: im:message and im:message.p2p_msg:readonly"
            echo "4. Events: im.message.receive_v1 (Long Connection Mode)"
            echo "5. Get App ID and App Secret"
            echo "6. Configure in ~/.nanobot/config.json:"
            echo '   "channels": { "feishu": { "enabled": true, "appId": "cli_xxx", "appSecret": "xxx", "allowFrom": ["or_YOUR_OPEN_ID"], "groupPolicy": "mention" } }'
            ;;
        slack)
            echo "To configure Slack:"
            echo "1. Access https://api.slack.com/apps"
            echo "2. Create new app → From scratch"
            echo "3. Enable Socket Mode - Generate App-Level Token (connections:write)"
            echo "4. OAuth & Permissions: add chat:write, reactions:write, app_mentions:read"
            echo "5. Event Subscriptions: enable message.im, message.channels, app_mention"
            echo "6. Configure in ~/.nanobot/config.json:"
            echo '   "channels": { "slack": { "enabled": true, "botToken": "xoxb-...", "appToken": "xapp-...", "allowFrom": ["YOUR_USER_ID"], "groupPolicy": "mention" } }'
            ;;
        matrix)
            echo "To configure Matrix:"
            echo "1. Install dependencies: pip install nanobot-ai[matrix]"
            echo "2. Create or use a Matrix account (ex: @nanobot:matrix.org)"
            echo "3. Get accessToken and deviceId"
            echo "4. Configure in ~/.nanobot/config.json:"
            echo '   "channels": { "matrix": { "enabled": true, "homeserver": "https://matrix.org", "userId": "@nanobot:matrix.org", "accessToken": "syt_xxx", "deviceId": "NANOBOT01", "allowFrom": ["@user:matrix.org"] } }'
            ;;
        email)
            echo "To configure Email:"
            echo "1. Create a dedicated email account (ex: my-nanobot@gmail.com)"
            echo "2. Enable 2-Step Verification → Create App Password"
            echo "3. Configure in ~/.nanobot/config.json:"
            echo '   "channels": { "email": { "enabled": true, "consentGranted": true, "imapHost": "imap.gmail.com", "imapPort": 993, "imapUsername": "my-nanobot@gmail.com", "imapPassword": "app-password", "smtpHost": "smtp.gmail.com", "smtpPort": 587, "smtpUsername": "my-nanobot@gmail.com", "smtpPassword": "app-password", "allowFrom": ["user@example.com"] } }'
            ;;
        *)
            print_error "Channel not supported: $channel"
            echo "Supported channels: whatsapp, telegram, discord, feishu, slack, matrix, email"
            ;;
    esac
}

# ============================================================
# LLM Provider Functions
# ============================================================

select_llm_provider() {
    echo >&2
    print_step "Select LLM provider:" >&2
    echo >&2
    echo -e "  ${GREEN}1) OpenRouter${NC} (recommended) - global access to all models" >&2
    echo -e "  2) OpenAI - Direct OpenAI API" >&2
    echo -e "  3) Anthropic - Direct Claude API" >&2
    echo -e "  4) DeepSeek - Chinese models" >&2
    echo -e "  5) Groq - Fast inference" >&2
    echo -e "  6) Custom - OpenAI-compatible - Local/custom endpoints" >&2
    echo >&2
    read -p "Choose provider [1]: " provider_choice

    local provider="openrouter"
    case ${provider_choice:-1} in
        1) provider="openrouter" ;;
        2) provider="openai" ;;
        3) provider="anthropic" ;;
        4) provider="deepseek" ;;
        5) provider="groq" ;;
        6) provider="custom" ;;
        *) provider="openrouter" ;;
    esac
    
    echo "$provider"
}

get_provider_default_model() {
    local provider="$1"
    case $provider in
        openrouter)
            echo "x-ai/grok-4.1-fast"
            ;;
        openai)
            echo "gpt-4o"
            ;;
        anthropic)
            echo "claude-sonnet-4-6"
            ;;
        deepseek)
            echo "deepseek-chat"
            ;;
        groq)
            echo "llama-3.3-70b-versatile"
            ;;
        custom)
            echo "default"
            ;;
        *)
            echo "x-ai/grok-4.1-fast"
            ;;
    esac
}

get_provider_env_key() {
    local provider="$1"
    case $provider in
        openrouter)
            echo "OPENROUTER_API_KEY"
            ;;
        openai)
            echo "OPENAI_API_KEY"
            ;;
        anthropic)
            echo "ANTHROPIC_API_KEY"
            ;;
        deepseek)
            echo "DEEPSEEK_API_KEY"
            ;;
        groq)
            echo "GROQ_API_KEY"
            ;;
        custom)
            echo "OPENAI_API_KEY"
            ;;
        *)
            echo "OPENROUTER_API_KEY"
            ;;
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

select_provider_model() {
    local provider="$1"
    local default_model="$2"
    
    echo >&2
    echo -e "Models for $provider:" >&2
    local models=()
    local i=1
    while IFS= read -r model; do
        models+=("$model")
        if [[ "$model" == "$default_model" ]]; then
            echo -e "  ${GREEN}$i) $model (default)${NC}" >&2
        else
            echo -e "  $i) $model" >&2
        fi
        ((i++))
    done < <(get_provider_models_list "$provider")
    echo -e "  $i) Other model" >&2
    echo >&2
    read -p "Choose model [1]: " model_choice

    local selected_model="$default_model"
    local choice_num=${model_choice:-1}
    
    if [[ "$choice_num" -eq $i ]]; then
        read -p "Custom model: " selected_model
    elif [[ "$choice_num" -ge 1 && "$choice_num" -lt $i ]]; then
        selected_model="${models[$((choice_num-1))]}"
    fi
    
    echo "$selected_model"
}

# ============================================================
# Docker Instance Functions
# ============================================================

create_docker_instance() {
    print_header
    print_step "Creating new Docker instance (as per guide)..."
    
    read -p "Instance name (ex: wa1, wa2, telegram1): " instance_name

    echo
    echo "Available channels:"
    echo "  1) whatsapp"
    echo "  2) telegram"
    echo "  3) discord"
    echo "  4) feishu"
    echo "  5) slack"
    echo "  6) matrix"
    echo "  7) email"
    read -p "Choose channel [1 - whatsapp]: " channel_choice
    case ${channel_choice:-1} in
        1) channel="whatsapp" ;;
        2) channel="telegram" ;;
        3) channel="discord" ;;
        4) channel="feishu" ;;
        5) channel="slack" ;;
        6) channel="matrix" ;;
        7) channel="email" ;;
        *) channel="whatsapp" ;;
    esac

    # Select LLM provider
    local provider
    provider=$(select_llm_provider)
    
    # Request appropriate API key for provider
    local env_key
    env_key=$(get_provider_env_key "$provider")
    local api_key
    local api_base=""
    
    case $provider in
        openrouter)
            read -p "OpenRouter API key (sk-or-v1-...): " api_key
            ;;
        openai)
            read -p "OpenAI API key (sk-...): " api_key
            ;;
        anthropic)
            read -p "Anthropic API key (sk-ant-...): " api_key
            ;;
        deepseek)
            read -p "DeepSeek API key (sk-...): " api_key
            ;;
        groq)
            read -p "GroQ API key (gsk_...): " api_key
            ;;
        custom)
            read -p "API key: " api_key
            read -p "API base URL (ex: http://localhost:8000/v1): " api_base
            ;;
    esac

    # Select model
    local default_model
    default_model=$(get_provider_default_model "$provider")
    local model
    model=$(select_provider_model "$provider" "$default_model")

    read -p "External port (ex: 18791, 18792): " port
    read -p "User ID for allowFrom: " user_id
    
    local instance_dir="${NANOBOT_INSTANCES}/${instance_name}"
    
    # Create instance directory
    mkdir -p "$instance_dir"
    
    # Criar config.json (as per guide)
    create_config_json "$instance_dir" "$channel" "$api_key" "$user_id" "$model" "$provider" "$api_base"
    
    # Criar docker-compose.yml (as per guide)
    create_docker_compose "$instance_dir" "$instance_name" "$port" "$channel"
    
    print_success "Instance $instance_name created in $instance_dir!"
    print_info "Configuration:"
    echo "  - Provider: $provider"
    echo "  - Model: $model"
    echo "  - Channel: $channel"
    echo "  - Port: $port"
    echo
    print_info "Structure created:"
    echo "  - config.json"
    echo "  - docker-compose.yml"
    
    if [[ "$channel" == "whatsapp" ]]; then
        echo "  - bridge/ (will be created after login)"
    fi
    
    echo "  - workspace/ (will be created automatically)"
    echo
    print_info "Next steps (as per guide):"
    echo "1. cd $instance_dir"
    
    if [[ "$channel" == "whatsapp" ]]; then
        echo "2. $SCRIPT_NAME login $instance_name"
        echo "   (Scan the QR Code with your WhatsApp)"
        echo "3. $SCRIPT_NAME start $instance_name"
    else
        echo "2. docker compose up -d"
    fi
    echo
    print_info "To change provider/model later:"
    echo "  $SCRIPT_NAME configure"
    echo "  $SCRIPT_NAME start $instance_name  # Start"
}

create_config_json() {
    local dir="$1"
    local channel="$2"
    local api_key="$3"
    local user_id="$4"
    local model="${5:-x-ai/grok-4.1-fast}"
    local provider="${6:-openrouter}"
    local api_base="${7:-}"

    # Build providers section based on provider type
    local providers_section=""
    local extra_headers=""
    
    case $provider in
        openrouter)
            providers_section="\"openrouter\": {
      \"apiKey\": \"${api_key}\"
    }"
            ;;
        openai)
            providers_section="\"openai\": {
      \"apiKey\": \"${api_key}\"
    }"
            ;;
        anthropic)
            providers_section="\"anthropic\": {
      \"apiKey\": \"${api_key}\"
    }"
            ;;
        deepseek)
            providers_section="\"deepseek\": {
      \"apiKey\": \"${api_key}\"
    }"
            ;;
        groq)
            providers_section="\"groq\": {
      \"apiKey\": \"${api_key}\"
    }"
            ;;
        custom)
            if [[ -n "$api_base" ]]; then
                providers_section="\"openai\": {
      \"apiKey\": \"${api_key}\",
      \"apiBase\": \"${api_base}\"
    }"
            else
                providers_section="\"openai\": {
      \"apiKey\": \"${api_key}\"
    }"
            fi
            # For custom endpoints, use "auto" provider to use the openai_compat backend
            provider="auto"
            ;;
    esac

    cat > "${dir}/config.json" << EOF
{
  "providers": {
    ${providers_section}
  },
  "agents": {
    "defaults": {
      "model": "${model}",
      "provider": "${provider}",
      "workspace": "/root/.nanobot/workspace"
    }
  },
  "channels": {
    "${channel}": {
      "enabled": true,
      "allowFrom": ["${user_id}"]
    }
  }
}
EOF
}

create_docker_compose() {
    local dir="$1"
    local name="$2"
    local port="$3"
    local channel="$4"
    
    if [[ "$channel" == "whatsapp" ]]; then
        cat > "${dir}/docker-compose.yml" << EOF
services:
  nanobot:
    image: nanobot
    container_name: nanobot-${name}
    restart: unless-stopped
    volumes:
      - ./config.json:/root/.nanobot/config.json
      - ./bridge:/root/.nanobot/bridge
      - ./workspace:/root/.nanobot/workspace
      - ./whatsapp-auth:/root/.nanobot/whatsapp-auth
    ports:
      - "${port}:18790"
    entrypoint: ["/bin/bash", "-c"]
    command:
      - |
        cd /root/.nanobot/bridge && node dist/index.js &
        exec nanobot gateway
EOF
    else
        cat > "${dir}/docker-compose.yml" << EOF
services:
  nanobot:
    image: nanobot
    container_name: nanobot-${name}
    restart: unless-stopped
    volumes:
      - ./config.json:/root/.nanobot/config.json
      - ./workspace:/root/.nanobot/workspace
    ports:
      - "${port}:18790"
    command: ["gateway"]
EOF
    fi
}

create_multi_instances() {
    print_header
    print_step "Multi-instance creator (as per guide)..."
    
    read -p "How many instances to create? " num_instances
    read -p "Name prefix (ex: wa, tg): " prefix

    echo
    echo "Available channels:"
    echo "  1) whatsapp"
    echo "  2) telegram"
    echo "  3) discord"
    echo "  4) feishu"
    echo "  5) slack"
    echo "  6) matrix"
    echo "  7) email"
    read -p "Choose channel [1 - whatsapp]: " channel_choice
    case ${channel_choice:-1} in
        1) channel="whatsapp" ;;
        2) channel="telegram" ;;
        3) channel="discord" ;;
        4) channel="feishu" ;;
        5) channel="slack" ;;
        6) channel="matrix" ;;
        7) channel="email" ;;
        *) channel="whatsapp" ;;
    esac

    read -p "Initial port (ex: 18791): " start_port
    
    # Select LLM provider
    local provider
    provider=$(select_llm_provider)
    
    # Request appropriate API key
    local api_key api_base=""
    case $provider in
        openrouter)
            read -p "OpenRouter API key (sk-or-v1-...): " api_key
            ;;
        openai)
            read -p "OpenAI API key (sk-...): " api_key
            ;;
        anthropic)
            read -p "Anthropic API key (sk-ant-...): " api_key
            ;;
        deepseek)
            read -p "DeepSeek API key (sk-...): " api_key
            ;;
        groq)
            read -p "GroQ API key (gsk_...): " api_key
            ;;
        custom)
            read -p "API key: " api_key
            read -p "API base URL (ex: http://localhost:8000/v1): " api_base
            ;;
    esac

    # Select model
    local default_model
    default_model=$(get_provider_default_model "$provider")
    local model
    model=$(select_provider_model "$provider" "$default_model")
    
    for ((i=1; i<=num_instances; i++)); do
        local instance_name="${prefix}${i}"
        local port=$((start_port + i - 1))
        local user_id="YOUR_USER_ID_${i}"
        
        echo
        print_step "Creating instance $instance_name (port: $port, provider: $provider, model: $model)..."
        create_docker_instance_single "$instance_name" "$channel" "$port" "$api_key" "$user_id" "$model" "$provider" "$api_base"
    done
    
    print_success "All instances created!"
    print_info "Configuration:"
    echo "  - Provider: $provider"
    echo "  - Model: $model"
    echo "  - Channel: $channel"
    echo
    print_info "Next steps:"
    echo "1. For each WhatsApp instance, execute:"
    echo "   $SCRIPT_NAME login ${prefix}1"
    echo "2. Start all:"
    echo "   $SCRIPT_NAME start-all"
    echo "3. To change provider/model:"
    echo "   $SCRIPT_NAME configure"
}

create_docker_instance_single() {
    local instance_name="$1"
    local channel="$2"
    local port="$3"
    local api_key="$4"
    local user_id="$5"
    local model="${6:-x-ai/grok-4.1-fast}"
    local provider="${7:-openrouter}"
    local api_base="${8:-}"
    
    local instance_dir="${NANOBOT_INSTANCES}/${instance_name}"
    
    mkdir -p "$instance_dir"
    create_config_json "$instance_dir" "$channel" "$api_key" "$user_id" "$model" "$provider" "$api_base"
    create_docker_compose "$instance_dir" "$instance_name" "$port" "$channel"
}

# ============================================================
# Instance management functions
# ============================================================

list_instances() {
    print_header
    print_step "Listing Docker instances..."
    
    if [[ ! -d "$NANOBOT_INSTANCES" ]]; then
        print_warning "Instances directory not found: $NANOBOT_INSTANCES"
        return 1
    fi
    
    local instances=()
    for dir in "$NANOBOT_INSTANCES"/*/; do
        if [[ -f "${dir}docker-compose.yml" ]]; then
            instances+=("$(basename "$dir")")
        fi
    done
    
    if [[ ${#instances[@]} -eq 0 ]]; then
        print_warning "No instances found."
        return 0
    fi
    
    echo "Instances found:"
    for instance in "${instances[@]}"; do
        echo "  - $instance"
    done
}

manage_instance() {
    local action="$1"
    local instance_name="$2"
    local instance_dir="${NANOBOT_INSTANCES}/${instance_name}"
    
    if [[ ! -d "$instance_dir" ]]; then
        print_error "Instance not found: $instance_name"
        return 1
    fi
    
    cd "$instance_dir"
    
    case $action in
        start)
            print_step "Starting instance $instance_name..."
            docker compose up -d
            ;;
        stop)
            print_step "Stopping instance $instance_name..."
            docker compose down
            ;;
        restart)
            print_step "Restarting instance $instance_name..."
            docker compose restart 2>/dev/null || {
                print_warning "No container running. Starting..."
                docker compose up -d
            }
            ;;
        logs)
            print_step "Instance logs $instance_name..."
            local running
            running=$(docker compose ps --format "{{.Names}}" 2>/dev/null)
            if [[ -z "$running" ]]; then
                print_warning "Instance not running. Starting..."
                docker compose up -d
            fi
            docker compose logs -f --tail 50
            ;;
        status)
            print_step "Instance status $instance_name..."
            docker compose run --rm --entrypoint nanobot nanobot status
            ;;
        login-whatsapp)
            print_step "Connecting WhatsApp for $instance_name..."
            docker compose down 2>/dev/null || true
            whatsapp_login_flow "$(pwd)"
            if [[ -f "$(pwd)/bridge/dist/index.js" ]]; then
                print_step "Starting instance..."
                docker compose up -d
                print_success "Instance started!"
            fi
            ;;
        chat)
            print_step "Starting chat CLI for $instance_name..."
            docker compose run --rm --entrypoint nanobot nanobot agent
            ;;
        update)
            print_step "Updating instance $instance_name..."
            docker compose down
            docker compose up -d
            ;;
        *)
            print_error "Unknown action: $action"
            ;;
    esac
    
    cd - > /dev/null 2>&1
}

manage_all_instances() {
    local action="$1"
    
    print_header
    print_step "Managing all instances..."
    
    if [[ ! -d "$NANOBOT_INSTANCES" ]]; then
        print_warning "Instances directory not found."
        return 1
    fi
    
    for dir in "$NANOBOT_INSTANCES"/*/; do
        if [[ -f "${dir}docker-compose.yml" ]]; then
            local instance_name
            instance_name=$(basename "$dir")
            echo
            print_step "Processing $instance_name..."
            manage_instance "$action" "$instance_name"
        fi
    done
}

delete_instance() {
    local instance_name="${1:-}"
    
    print_header
    echo -e "${RED}⚠️  DELETE INSTANCE${NC}"
    echo
    
    # List instances if no name provided
    if [[ -z "$instance_name" ]]; then
        if [[ ! -d "$NANOBOT_INSTANCES" ]]; then
            print_warning "No instances found."
            return 1
        fi
        
        local instances=()
        local i=1
        for dir in "$NANOBOT_INSTANCES"/*/; do
            if [[ -f "${dir}docker-compose.yml" ]]; then
                local name
                name=$(basename "$dir")
                local ch
                ch=$(python3 -c "
import json
valid_channels = ['whatsapp', 'telegram', 'discord', 'feishu', 'slack', 'matrix', 'email']
with open('${dir}config.json') as f:
    c = json.load(f)
chs = [k for k in valid_channels if c.get('channels', {}).get(k, {}).get('enabled', False)]
print(chs[0] if chs else '?')
" 2>/dev/null || echo "?")
                instances+=("$name")
                echo -e "  ${YELLOW}[$i]${NC} $name ${CYAN}($ch)${NC}"
                ((i++))
            fi
        done
        
        if [[ ${#instances[@]} -eq 0 ]]; then
            print_warning "No instances found."
            return 1
        fi
        
        echo
        read -p "Select instance number to delete: " sel
        if [[ -z "${instances[$((sel-1))]:-}" ]]; then
            print_error "Invalid selection."
            return 1
        fi
        instance_name="${instances[$((sel-1))]}"
    fi
    
    local instance_dir="${NANOBOT_INSTANCES}/${instance_name}"
    
    # Check if instance exists
    if [[ ! -d "$instance_dir" ]]; then
        print_error "Instance not found: $instance_name"
        return 1
    fi
    
    # Show instance details
    local ch
    ch=$(python3 -c "
import json
valid_channels = ['whatsapp', 'telegram', 'discord', 'feishu', 'slack', 'matrix', 'email']
with open('${instance_dir}/config.json') as f:
    c = json.load(f)
chs = [k for k in valid_channels if c.get('channels', {}).get(k, {}).get('enabled', False)]
print(chs[0] if chs else '?')
" 2>/dev/null || echo "?")
    
    local model
    model=$(python3 -c "
import json
with open('${instance_dir}/config.json') as f:
    c = json.load(f)
print(c.get('agents',{}).get('defaults',{}).get('model','?'))
" 2>/dev/null || echo "?")
    
    echo
    echo -e "${YELLOW}━━━ Instance to delete ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "  Name:     ${CYAN}$instance_name${NC}"
    echo -e "  Channel:  $ch"
    echo -e "  Model:    $model"
    echo -e "  Folder:   $instance_dir"
    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo
    echo -e "${RED}This action is IRREVERSIBLE!${NC}"
    echo -e "${RED}Will be removed:${NC}"
    echo "  - Docker Container - nanobot-$instance_name"
    echo "  - All instance folders"
    echo "  - WhatsApp session data if any"
    echo
    
    # Offer backup
    read -p "Backup config.json? (y/n) [y]: " do_backup
    if [[ "${do_backup:-y}" == "y" || "${do_backup:-y}" == "Y" ]]; then
        local backup_dir="${BACKUP_DIR}"
        local backup_name="${instance_name}_$(date +%Y%m%d_%H%M%S)"
        mkdir -p "$backup_dir/$backup_name"
        cp "$instance_dir/config.json" "$backup_dir/$backup_name/"
        cp "$instance_dir/docker-compose.yml" "$backup_dir/$backup_name/" 2>/dev/null || true
        print_success "Backup saved to: $backup_dir/$backup_name/"
        echo
    fi
    
    # Double confirmation - type instance name
    echo -e "${RED}To confirm, type the instance name: ${NC}"
    read -p "> " confirm_name
    
    if [[ "$confirm_name" != "$instance_name" ]]; then
        print_error "Name does not match. Operation cancelled."
        return 1
    fi
    
    echo
    print_step "Deleting instance $instance_name..."
    
    # Stop and remove container
    if docker ps -a --format "{{.Names}}" | grep -q "^nanobot-${instance_name}$"; then
        print_step "Removing container..."
        cd "$instance_dir"
        docker compose down 2>/dev/null || true
        docker rm -f "nanobot-$instance_name" 2>/dev/null || true
        cd - > /dev/null 2>&1
    fi
    
    # Remove directory
    print_step "Removing files..."
    sudo rm -rf "$instance_dir"
    
    # Clean up any orphaned volumes (optional)
    docker volume prune -f 2>/dev/null || true
    
    echo
    print_success "Instance $instance_name deleted successfully!"
}

# ============================================================
# Update functions (Docker-only)
# ============================================================

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
    print_step "Rebuilding Docker image for nanobot (as per guide)..."
    
    # Clone or update repository
    if [[ ! -d "$NANOBOT_SOURCE_DIR" ]]; then
        print_step "Cloning repository..."
        git clone "$NANOBOT_REPO" "$NANOBOT_SOURCE_DIR"
    else
        print_step "Updating repository..."
        cd "$NANOBOT_SOURCE_DIR" && git pull && cd -
    fi
    
    # Apply audio patch if enabled
    if [[ "$PATCH_WHATSAPP_AUDIO" == "true" ]]; then
        apply_audio_patch "$NANOBOT_SOURCE_DIR"
    fi

    cd "$NANOBOT_SOURCE_DIR"
    docker build -t nanobot .
    cd - > /dev/null 2>&1
    
    print_success "Docker image rebuilt!"
    print_info "To update instances, execute: $SCRIPT_NAME update-all"
}

init_whatsapp_bridge() {
    # $1 = instance_dir
    # Copy pre-built bridge from Docker image to host
    local instance_dir="$1"
    mkdir -p "$instance_dir/bridge"
    docker run --rm \
        -v "$instance_dir/bridge:/root/.nanobot/bridge" \
        --entrypoint sh \
        nanobot -c "cp -a /app/bridge/. /root/.nanobot/bridge/"
}

whatsapp_login_flow() {
    local instance_dir="$1"

    cd "$instance_dir"

    # Initialize bridge from image if not done
    if [[ ! -f bridge/dist/index.js ]]; then
        print_step "Initializing WhatsApp bridge from image..."
        init_whatsapp_bridge "$instance_dir"
    fi

    # Create auth directory
    mkdir -p whatsapp-auth

    echo
    print_step "Starting WhatsApp login..."
    echo
    echo -e "${YELLOW}  1. QR Code will appear below${NC}"
    echo -e "${YELLOW}  2. Open WhatsApp → Linked Devices → Link Device${NC}"
    echo -e "${YELLOW}  3. Scan the QR Code${NC}"
    echo -e "${YELLOW}  4. When you see Connected, press Ctrl+C${NC}"
    echo
    read -p "  Press Enter to start..."

    # Interactive login — all volumes mounted, no docker cp
    # || true needed: Ctrl+C makes docker run exit 130, which kills the script with set -e
    docker run -it \
        -v "$(pwd)/config.json:/root/.nanobot/config.json" \
        -v "$(pwd)/bridge:/root/.nanobot/bridge" \
        -v "$(pwd)/workspace:/root/.nanobot/workspace" \
        -v "$(pwd)/whatsapp-auth:/root/.nanobot/whatsapp-auth" \
        --entrypoint nanobot \
        nanobot channels login whatsapp || true

    # Check if login was successful
    if [[ -d whatsapp-auth ]] && [[ "$(ls -A whatsapp-auth 2>/dev/null)" ]]; then
        print_success "WhatsApp connected! Session saved."
    else
        print_warning "Session not detected in whatsapp-auth/. Login may have failed."
    fi

    cd - > /dev/null 2>&1
}

reconnect_whatsapp() {
    local instance_name="$1"
    local instance_dir="${NANOBOT_INSTANCES}/${instance_name}"
    
    if [[ ! -d "$instance_dir" ]]; then
        print_error "Instance not found: $instance_name"
        return 1
    fi
    
    print_step "Reconnecting WhatsApp for $instance_name..."
    
    cd "$instance_dir"
    docker compose down 2>/dev/null || true

    # Clear auth to force fresh QR
    rm -rf whatsapp-auth
    mkdir -p whatsapp-auth

    cd - > /dev/null 2>&1

    whatsapp_login_flow "$instance_dir"

    # Start instance
    cd "$instance_dir"
    docker compose up -d
    cd - > /dev/null 2>&1
    
    print_success "WhatsApp reconnected for $instance_name!"
}

upgrade_whatsapp_bridge() {
    local instance_name="$1"
    local instance_dir="${NANOBOT_INSTANCES}/${instance_name}"

    if [[ ! -d "$instance_dir" ]]; then
        print_error "Instance not found: $instance_name"
        return 1
    fi

    print_step "Updating WhatsApp bridge for $instance_name..."

    cd "$instance_dir"
    docker compose down 2>/dev/null || true
    cd - > /dev/null 2>&1

    # Clear bridge and auth — full rebuild
    rm -rf "$instance_dir/bridge" "$instance_dir/whatsapp-auth"

    print_step "Rebuilding bridge with latest version..."
    whatsapp_login_flow "$instance_dir"

    # Start instance
    cd "$instance_dir"
    docker compose up -d
    cd - > /dev/null 2>&1

    print_success "WhatsApp bridge updated and instance restarted!"
}

configure_whatsapp_instance() {
    local instance_name="$1"
    local instance_dir="${NANOBOT_INSTANCES}/${instance_name}"

    if [[ ! -d "$instance_dir" ]]; then
        print_error "Instance not found: $instance_name"
        return 1
    fi

    local config_file="${instance_dir}/config.json"
    if [[ ! -f "$config_file" ]]; then
        print_error "config.json not found em $instance_dir"
        return 1
    fi

    # Verificar se é WhatsApp
    local channel
    channel=$(python3 -c "
import json
with open('$config_file') as f:
    cfg = json.load(f)
channels = cfg.get('channels', {})
print('whatsapp' if 'whatsapp' in channels else (list(channels.keys())[0] if channels else ''))
" 2>/dev/null)

    if [[ "$channel" != "whatsapp" ]]; then
        print_error "Instância $instance_name is not WhatsApp (channel: $channel)"
        return 1
    fi

    print_header
    print_step "Configuring WhatsApp for $instance_name..."
    echo

    # Read current configuration
    local current_allow_from current_group_policy current_enabled
    read current_enabled current_allow_from current_group_policy < <(python3 -c "
import json
with open('$config_file') as f:
    cfg = json.load(f)
wa = cfg.get('channels', {}).get('whatsapp', {})
enabled = str(wa.get('enabled', True)).lower()
af = wa.get('allowFrom', ['*'])
af_str = ','.join(af)
gp = wa.get('groupPolicy', 'mention')
print(f'{enabled} {af_str} {gp}')
")

    echo -e "${CYAN}Current configuration:${NC}"
    echo "  Enabled: $current_enabled"
    echo "  allowFrom: $current_allow_from"
    echo "  groupPolicy: $current_group_policy"
    echo

    echo -e "${GREEN}━━━ Configure WhatsApp ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo "  [1] Allow anyone to access (allowFrom: [\"*\"])"
    echo "  [2] Set specific numbers"
    echo "  [3] Group policy: mention - only when mentioned"
    echo "  [4] Group policy: open - replies to all"
    echo "  [5] Enable / Disable channel"
    echo "  [6] Show current config.json"
    echo "  [7] Edit config.json manually - nano"
    echo "  [0] Back"
    echo

    while true; do
        read -p "Choose [0-7]: " wa_choice
        case ${wa_choice:-0} in
            1)
                python3 -c "
import json
with open('$config_file', 'r') as f:
    cfg = json.load(f)
cfg.setdefault('channels', {}).setdefault('whatsapp', {})['allowFrom'] = ['*']
with open('$config_file', 'w') as f:
    json.dump(cfg, f, indent=2)
"
                print_success "allowFrom configurado para [\"*\"] - anyone can use"
                ;;
            2)
                echo "Enter numbers separated by comma:"
                read -p "Numbers: " numbers
                if [[ -n "$numbers" ]]; then
                    python3 << PYEOF
import json
nums = [n.strip() for n in "$numbers".split(",") if n.strip()]
with open("$config_file", "r") as f:
    cfg = json.load(f)
cfg.setdefault("channels", {}).setdefault("whatsapp", {})["allowFrom"] = nums
with open("$config_file", "w") as f:
    json.dump(cfg, f, indent=2)
PYEOF
                    print_success "allowFrom atualizado"
                fi
                ;;
            3)
                python3 -c "
import json
with open('$config_file', 'r') as f:
    cfg = json.load(f)
cfg.setdefault('channels', {}).setdefault('whatsapp', {})['groupPolicy'] = 'mention'
with open('$config_file', 'w') as f:
    json.dump(cfg, f, indent=2)
"
                print_success "groupPolicy = mention (only replies when @mentioned in groups)"
                ;;
            4)
                python3 -c "
import json
with open('$config_file', 'r') as f:
    cfg = json.load(f)
cfg.setdefault('channels', {}).setdefault('whatsapp', {})['groupPolicy'] = 'open'
with open('$config_file', 'w') as f:
    json.dump(cfg, f, indent=2)
"
                print_success "groupPolicy = open (replies to all group messages)"
                ;;
            5)
                local new_enabled
                new_enabled=$(python3 -c "
import json
with open('$config_file', 'r') as f:
    cfg = json.load(f)
wa = cfg.setdefault('channels', {}).setdefault('whatsapp', {})
current = wa.get('enabled', True)
wa['enabled'] = not current
with open('$config_file', 'w') as f:
    json.dump(cfg, f, indent=2)
print(str(not current).lower())
")
                print_success "Channel enabled = $new_enabled"
                ;;
            6)
                echo
                python3 -m json.tool "$config_file"
                echo
                ;;
            7)
                if command -v nano &> /dev/null; then
                    nano "$config_file"
                elif command -v vim &> /dev/null; then
                    vim "$config_file"
                else
                    print_warning "No editor found. Edit manually: $config_file"
                fi
                ;;
            0)
                # Restart instance if running
                local running
                running=$(docker ps --filter "name=nanobot-${instance_name}" --format "{{.Names}}" 2>/dev/null)
                if [[ -n "$running" ]]; then
                    echo
                    read -p "Restart instance to apply changes? (y/n): " restart_confirm
                    if [[ "$restart_confirm" == "y" || "$restart_confirm" == "Y" ]]; then
                        cd "$instance_dir"
                        docker compose restart
                        cd - > /dev/null 2>&1
                        print_success "Instance restarted!"
                    fi
                fi
                return 0
                ;;
            *)
                print_error "Invalid option."
                ;;
        esac
        echo
    done
}

configure_instance_menu() {
    local instances=()

    if [[ ! -d "$NANOBOT_INSTANCES" ]]; then
        print_error "No instances found."
        return 1
    fi

    for dir in "$NANOBOT_INSTANCES"/*/; do
        if [[ -f "${dir}config.json" ]]; then
            instances+=("$(basename "$dir")")
        fi
    done

    if [[ ${#instances[@]} -eq 0 ]]; then
        print_error "No instances found."
        return 1
    fi

    print_header
    print_step "Configure instance..."
    echo

    local i=1
    declare -A cfg_map
    for instance in "${instances[@]}"; do
        local cfg="${NANOBOT_INSTANCES}/${instance}/config.json"
        local ch
        ch=$(python3 -c "
import json
valid_channels = ['whatsapp', 'telegram', 'discord', 'feishu', 'slack', 'matrix', 'email']
with open('$cfg') as f:
    c = json.load(f)
chs = [k for k in valid_channels if c.get('channels', {}).get(k, {}).get('enabled', False)]
print(chs[0] if chs else 'unknown')
" 2>/dev/null)
        local model
        model=$(python3 -c "
import json
with open('$cfg') as f:
    c = json.load(f)
print(c.get('agents',{}).get('defaults',{}).get('model','?'))
" 2>/dev/null)
        echo -e "  ${YELLOW}[$i]${NC} $instance  (${ch} / ${model})"
        cfg_map[$i]="$instance"
        ((i++))
    done

    echo
    read -p "Select instance number: " sel

    if [[ -z "${cfg_map[$sel]:-}" ]]; then
        print_error "Invalid selection."
        return 1
    fi

    local selected="${cfg_map[$sel]}"
    local cfg="${NANOBOT_INSTANCES}/${selected}/config.json"

    local channel
    channel=$(python3 -c "
import json
valid_channels = ['whatsapp', 'telegram', 'discord', 'feishu', 'slack', 'matrix', 'email']
with open('$cfg') as f:
    c = json.load(f)
chs = [k for k in valid_channels if c.get('channels', {}).get(k, {}).get('enabled', False)]
print(chs[0] if chs else '')
" 2>/dev/null)

    if [[ "$channel" == "whatsapp" ]]; then
        configure_whatsapp_instance "$selected"
        return
    fi

    # Generic configuration for other channels
    echo
    print_step "Configuring $selected (channel: $channel)..."
    echo

    local allow_from_str group_policy
    allow_from_str=$(python3 -c "
import json
with open('$cfg') as f:
    c = json.load(f)
af = c.get('channels',{}).get('$channel',{}).get('allowFrom',[])
print(','.join(af))
" 2>/dev/null)
    group_policy=$(python3 -c "
import json
with open('$cfg') as f:
    c = json.load(f)
print(c.get('channels',{}).get('$channel',{}).get('groupPolicy','mention'))
" 2>/dev/null)

    echo -e "${CYAN}Channel: $channel${NC}"
    echo "  allowFrom: $allow_from_str"
    echo "  groupPolicy: $group_policy"
    
    # Get current provider and model
    local model_now provider_now
    model_now=$(python3 -c "
import json
with open('$cfg') as f:
    c = json.load(f)
print(c.get('agents',{}).get('defaults',{}).get('model','?'))
" 2>/dev/null)
    provider_now=$(python3 -c "
import json
with open('$cfg') as f:
    c = json.load(f)
print(c.get('agents',{}).get('defaults',{}).get('provider','auto'))
" 2>/dev/null)
    
    echo "  provider: $provider_now"
    echo "  model: $model_now"
    echo

    echo -e "${GREEN}━━━ Configure $channel ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo "  [1] allowFrom: allow anyone"
    echo "  [2] allowFrom: set specific IDs/numbers"
    echo "  [3] groupPolicy: mention - only when mentioned"
    echo "  [4] groupPolicy: open - reply all"
    echo "  [5] Change LLM model"
    echo "  [6] Change API key"
    echo "  [7] Change LLM provider"
    echo "  [8] Show full config.json"
    echo "  [9] Edit manually - nano"
    echo "  [0] Back"
    echo

    while true; do
        read -p "Choose [0-9]: " cfg_choice
        case ${cfg_choice:-0} in
            1)
                python3 << PYEOF
import json
with open("$cfg", "r") as f:
    c = json.load(f)
c["channels"]["$channel"]["allowFrom"] = ["*"]
with open("$cfg", "w") as f:
    json.dump(c, f, indent=2)
PYEOF
                print_success "allowFrom = [\"*\"]"
                ;;
            2)
                read -p "IDs/numbers (separated by comma): " ids
                if [[ -n "$ids" ]]; then
                    python3 << PYEOF
import json
with open("$cfg", "r") as f:
    c = json.load(f)
nums = [n.strip() for n in "$ids".split(",") if n.strip()]
c["channels"]["$channel"]["allowFrom"] = nums
with open("$cfg", "w") as f:
    json.dump(c, f, indent=2)
PYEOF
                    print_success "allowFrom updated"
                fi
                ;;
            3)
                python3 << PYEOF
import json
with open("$cfg", "r") as f:
    c = json.load(f)
c["channels"]["$channel"]["groupPolicy"] = "mention"
with open("$cfg", "w") as f:
    json.dump(c, f, indent=2)
PYEOF
                print_success "groupPolicy = mention"
                ;;
            4)
                python3 << PYEOF
import json
with open("$cfg", "r") as f:
    c = json.load(f)
c["channels"]["$channel"]["groupPolicy"] = "open"
with open("$cfg", "w") as f:
    json.dump(c, f, indent=2)
PYEOF
                print_success "groupPolicy = open"
                ;;
            5)
                # Get current model to highlight
                local current_model
                current_model=$(python3 -c "
import json
with open('$cfg') as f:
    c = json.load(f)
print(c.get('agents',{}).get('defaults',{}).get('model',''))
" 2>/dev/null)
                
                echo "Models for $provider_now:"
                local models=()
                local i=1
                while IFS= read -r model; do
                    models+=("$model")
                    if [[ "$model" == "$current_model" ]]; then
                        echo "  ${GREEN}$i) $model (current)${NC}"
                    else
                        echo "  $i) $model"
                    fi
                    ((i++))
                done < <(get_provider_models_list "$provider_now")
                echo "  $i) Other model"
                read -p "Choose [1-$i]: " mc
                local new_model="$current_model"
                local choice_num=${mc:-1}
                
                if [[ "$choice_num" -eq $i ]]; then
                    read -p "Custom model: " new_model
                elif [[ "$choice_num" -ge 1 && "$choice_num" -lt $i ]]; then
                    new_model="${models[$((choice_num-1))]}"
                fi
                
                if [[ -n "$new_model" ]]; then
                    python3 << PYEOF
import json
with open("$cfg", "r") as f:
    c = json.load(f)
c.setdefault("agents",{}).setdefault("defaults",{})["model"] = "$new_model"
with open("$cfg", "w") as f:
    json.dump(c, f, indent=2)
PYEOF
                    print_success "Model changed to $new_model"
                fi
                ;;
            6)
                local env_key
                env_key=$(get_provider_env_key "$provider_now")
                echo "Current provider: $provider_now"
                echo "Environment variable: $env_key"
                read -p "New API key: " new_key
                if [[ -n "$new_key" ]]; then
                    # Determine which provider section to update
                    local provider_key="$provider_now"
                    if [[ "$provider_now" == "auto" ]]; then
                        provider_key="openai"  # Custom endpoints use openai compat
                    fi
                    
                    python3 << PYEOF
import json
with open("$cfg", "r") as f:
    c = json.load(f)
c.setdefault("providers",{}).setdefault("$provider_key",{})["apiKey"] = "$new_key"
with open("$cfg", "w") as f:
    json.dump(c, f, indent=2)
PYEOF
                    print_success "API key updated"
                fi
                ;;
            7)
                # Change LLM provider
                echo
                print_step "Changing LLM provider..."
                local new_provider
                new_provider=$(select_llm_provider)
                
                # Request new API key
                local new_api_key new_api_base=""
                case $new_provider in
                    openrouter)
                        read -p "OpenRouter API key (sk-or-v1-...): " new_api_key
                        ;;
                    openai)
                        read -p "OpenAI API key (sk-...): " new_api_key
                        ;;
                    anthropic)
                        read -p "Anthropic API key (sk-ant-...): " new_api_key
                        ;;
                    deepseek)
                        read -p "DeepSeek API key (sk-...): " new_api_key
                        ;;
                    groq)
                        read -p "GroQ API key (gsk_...): " new_api_key
                        ;;
                    custom)
                        read -p "API key: " new_api_key
                        read -p "API base URL (ex: http://localhost:8000/v1): " new_api_base
                        ;;
                esac
                
                # Select new model
                local default_model new_model
                default_model=$(get_provider_default_model "$new_provider")
                new_model=$(select_provider_model "$new_provider" "$default_model")
                
                # Update config.json
                python3 << PYEOF
import json
with open("$cfg", "r") as f:
    c = json.load(f)

# Clear old providers and add new one
providers = {}
provider_key = "$new_provider"
if provider_key == "custom":
    provider_key = "openai"
    if "$new_api_base":
        providers["openai"] = {"apiKey": "$new_api_key", "apiBase": "$new_api_base"}
    else:
        providers["openai"] = {"apiKey": "$new_api_key"}
else:
    providers[provider_key] = {"apiKey": "$new_api_key"}

c["providers"] = providers

# Update agent defaults
provider_value = "$new_provider"
if provider_value == "custom":
    provider_value = "auto"
    
c.setdefault("agents",{}).setdefault("defaults",{})["provider"] = provider_value
c["agents"]["defaults"]["model"] = "$new_model"

with open("$cfg", "w") as f:
    json.dump(c, f, indent=2)
PYEOF
                print_success "Provider changed to $new_provider with model $new_model"
                ;;
            8)
                echo
                python3 -m json.tool "$cfg"
                echo
                ;;
            9)
                if command -v nano &> /dev/null; then
                    nano "$cfg"
                elif command -v vim &> /dev/null; then
                    vim "$cfg"
                else
                    print_warning "Edit manually: $cfg"
                fi
                ;;
            0)
                # Ask to restart
                local running
                running=$(docker ps --filter "name=nanobot-${selected}" --format "{{.Names}}" 2>/dev/null)
                if [[ -n "$running" ]]; then
                    read -p "Restart to apply? (y/n): " rc
                    if [[ "$rc" == "y" || "$rc" == "Y" ]]; then
                        cd "${NANOBOT_INSTANCES}/${selected}"
                        docker compose restart
                        cd - > /dev/null 2>&1
                        print_success "Instance restarted!"
                    fi
                fi
                return 0
                ;;
            *)
                print_error "Invalid option."
                ;;
        esac
        echo
    done
}

# ============================================================
# Menu Principal
# ============================================================

show_menu() {
    clear
    
    # Get agent status
    local agent_status
    agent_status=$(get_agents_status)
    
    # Header - top/bottom borders only
    echo -e "${CYAN}══════════════════════════════════════════════════════════════════${NC}"
    echo -e "${PURPLE} 🐈 Nanobot Helper v2.0${NC}"
    echo -e "${BLUE}  WhatsApp Audio Patch + Multi-Provider LLM${NC}"
    echo -e "${CYAN}══════════════════════════════════════════════════════════════════${NC}"
    
    # Agent status (simple list)
    echo -e "  ${PURPLE}📊 Agents${NC}"
    echo -e "${agent_status}"
    
    echo
    echo -e "  ${PURPLE}⚡ Configuration${NC}"
    echo -e "    ${YELLOW}[1]${NC} Setup All  ${YELLOW}[2]${NC} Prerequisites  ${YELLOW}[3]${NC} Build Image"
    echo
    echo -e "  ${CYAN}📦 Instances${NC}"
    echo -e "    ${CYAN}[4]${NC} Create  ${CYAN}[5]${NC} Create Multiple  ${CYAN}[6]${NC} List"
    echo
    echo -e "  ${GREEN}🎮 Control${NC}"
    echo -e "    ${GREEN}[7]${NC} Start  ${RED}[8]${NC} Stop  ${BLUE}[9]${NC} Restart"
    echo -e "    ${PURPLE}[10]${NC} Status  ${CYAN}[11]${NC} Logs  ${CYAN}[12]${NC} Chat"
    echo
    echo -e "  ${GREEN}📱 WhatsApp${NC}"
    echo -e "    ${GREEN}[13]${NC} Login  ${YELLOW}[14]${NC} Reconnect  ${YELLOW}[15]${NC} Update Bridge"
    echo -e "    ${CYAN}[16]${NC} Configure"
    echo
    echo -e "  ${BLUE}🔄 Batch${NC}"
    echo -e "    ${GREEN}[17]${NC} Start All  ${RED}[18]${NC} Stop All"
    echo -e "    ${BLUE}[19]${NC} Restart All  ${YELLOW}[20]${NC} Update All"
    echo
    echo -e "  ${PURPLE}🔧 System${NC}"
    echo -e "    ${PURPLE}[21]${NC} Rebuild Image  ${CYAN}[22]${NC} Config Instance"
    echo -e "    ${CYAN}[23]${NC} Help"
    echo
    echo -e "  ${RED}⚠️  Danger${NC}"
    echo -e "    ${RED}[24]${NC} Delete Instance (IRREVERSIBLE)"
    echo
    echo
    echo -e "    ${RED}[0]${NC} Exit"
    echo
}

select_instance() {
    local action="$1"
    local instances=()
    
    # List available instances
    if [[ ! -d "$NANOBOT_INSTANCES" ]]; then
        print_error "No instances found. Create an instance first."
        return 1
    fi
    
    for dir in "$NANOBOT_INSTANCES"/*/; do
        if [[ -f "${dir}docker-compose.yml" ]]; then
            instances+=("$(basename "$dir")")
        fi
    done
    
    if [[ ${#instances[@]} -eq 0 ]]; then
        print_error "No instances found. Create an instance first."
        return 1
    fi
    
    echo
    echo -e "${CYAN}Available instances:${NC}"
    echo
    
    local i=1
    for instance in "${instances[@]}"; do
        echo -e "  ${YELLOW}[$i]${NC} $instance"
        instance_map[$i]="$instance"
        ((i++))
    done
    
    echo
    read -p "Select instance number: " selection
    
    if [[ -z "${instance_map[$selection]:-}" ]]; then
        print_error "Invalid selection."
        return 1
    fi
    
    selected_instance="${instance_map[$selection]}"
    
    case $action in
        start) manage_instance start "$selected_instance" ;;
        stop) manage_instance stop "$selected_instance" ;;
        restart) manage_instance restart "$selected_instance" ;;
        logs) manage_instance logs "$selected_instance" ;;
        status) manage_instance status "$selected_instance" ;;
        chat) manage_instance chat "$selected_instance" ;;
        login) manage_instance login-whatsapp "$selected_instance" ;;
        reconnect) reconnect_whatsapp "$selected_instance" ;;
        upgrade-bridge) upgrade_whatsapp_bridge "$selected_instance" ;;
        configure-wa) configure_whatsapp_instance "$selected_instance" ;;
    esac
}

interactive_menu() {
    declare -A instance_map
    
    # Welcome message
    clear
    echo -e "${PURPLE}══════════════════════════════════════════════════════════════════${NC}"
    echo -e "${PURPLE}        Nanobot Helper v2.0 - AI Manager for Nanobot${NC}"
    echo -e "${PURPLE}══════════════════════════════════════════════════════════════════${NC}"
    echo
    echo -e "${GREEN}Welcome to AI Manager!${NC}"
    echo
    echo -e "${CYAN}This script helps create and manage isolated Docker instances"
    echo -e "of Nanobot agents using Docker Multi-Tenant.${NC}"
    echo
    echo -e "${YELLOW}Recommendation: Use option [1] Setup All to start!${NC}"
    echo
    read -p "Press Enter to continue..."
    
    while true; do
        show_menu
        read -p "Choose an option [0-24]: " choice
        
        case $choice in
            1)
                setup_guide_flow
                ;;
            2)
                check_prerequisites
                ;;
            3)
                build_nanobot_image
                ;;
            4)
                create_docker_instance
                ;;
            5)
                create_multi_instances
                ;;
            6)
                list_instances
                ;;
            7)
                select_instance "start"
                ;;
            8)
                select_instance "stop"
                ;;
            9)
                select_instance "restart"
                ;;
            10)
                select_instance "status"
                ;;
            11)
                select_instance "logs"
                ;;
            12)
                select_instance "chat"
                ;;
            13)
                select_instance "login"
                ;;
            14)
                select_instance "reconnect"
                ;;
            15)
                select_instance "upgrade-bridge"
                ;;
            16)
                select_instance "configure-wa"
                ;;
            17)
                manage_all_instances start
                ;;
            18)
                manage_all_instances stop
                ;;
            19)
                manage_all_instances restart
                ;;
            20)
                manage_all_instances update
                ;;
            21)
                rebuild_docker_image
                ;;
            22)
                configure_instance_menu
                ;;
            23)
                show_help
                ;;
            24)
                delete_instance
                ;;
            0)
                echo
                print_info "Exiting Nanobot Helper. Goodbye! 🐈"
                exit 0
                ;;
            *)
                print_error "Invalid option. Choose a number from 0 to 24."
                ;;
        esac
        
        echo
        read -p "Press Enter to continue..."
    done
}

# ============================================================
# Modo Linha de Comando
# ============================================================

show_help() {
    print_header
    echo "Usage: ./xnanobot.sh [command] [options]"
    echo "AI Manager - Multi-Tenant Docker for nanobot agents"
    echo
    echo "Setup as per guide:"
    echo "  setup-guide      - Setup complete - prerequisites, build, instance"
    echo "  check            - Check prerequisites - Docker 20.10+, Compose 2.0+"
    echo "  build            - Build Docker image - git clone and docker build"
    echo
    echo "Docker Instances - Isolated:"
    echo "  create           - Create new isolated Docker instance"
    echo "  create-multi     - Create multiple instances"
    echo "  list             - List instances"
    echo
    echo "Instance Management:"
    echo "  start <name>     - Start instance"
    echo "  stop <name>      - Stop instance"
    echo "  restart <name>   - Restart instance"
    echo "  logs <name>      - Ver logs"
    echo "  status <name>    - Ver status"
    echo "  chat <name>      - Chat CLI"
    echo "  login <name>     - Connect WhatsApp - QR Code"
    echo "  reconnect <name> - Reconnect WhatsApp - change account"
    echo "  delete <name>    - Delete instance - IRREVERSIBLE"
    echo
    echo "WhatsApp:"
    echo "  upgrade-bridge <name> - Update WhatsApp bridge - rebuild with latest lib"
    echo "  configure-wa <name>   - Configure WhatsApp - allowFrom, groupPolicy, etc"
    echo
    echo "Batch Management:"
    echo "  start-all        - Start all instances"
    echo "  stop-all         - Stop all instances"
    echo "  restart-all      - Restart all instances"
    echo "  update-all       - Update all instances"
    echo
    echo "Update:"
    echo "  update           - Update nanobot - pip or uv"
    echo "  rebuild          - Reconstruir imagem Docker"
    echo
    echo "Utilities:"
    echo "  install          - Install nanobot - pip, uv, or source"
    echo "  setup            - Initial setup - onboard"
    echo "  configure        - Configure instance - select and edit"
    echo "  interactive      - Interactive mode"
    echo "  help             - Show help"
    echo
    echo "Supported LLM Providers:"
    echo "  - OpenRouter - default - Global access, any model"
    echo "  - OpenAI - API direct OpenAI"
    echo "  - Anthropic - API direct Claude"
    echo "  - DeepSeek - Chinese models"
    echo "  - Groq - Fast inference"
    echo "  - Personalizado - Endpoints OpenAI-compatible"
    echo
    echo "Examples - as per guide:"
    echo "  $0 setup-guide               # Setup complete"
    echo "  $0 create                    # Create instance with provider selection"
    echo "  $0 configure                 # Change provider/model of existing instance"
    echo "  $0 login wa1                 # Connect WhatsApp"
    echo "  $0 start wa1                 # Start instance"
    echo "  $0 logs wa1                  # View logs"
    echo "  $0 reconnect wa1             # Reconnect WhatsApp"
    echo "  $0 upgrade-bridge wa1        # Update WhatsApp bridge"
    echo "  $0 configure-wa wa1          # Configure WhatsApp (allowFrom, groups)"
    echo "  $0 delete wa1                # Delete instance (with confirmation)"
    echo
}

# ============================================================
# Main
# ============================================================

main() {
    local command="${1:-}"
    
    case "$command" in
        install)
            install_nanobot
            ;;
        setup)
            setup_initial
            ;;
        setup-wizard)
            setup_initial --wizard
            ;;
        setup-guide)
            setup_guide_flow
            ;;
        build)
            build_nanobot_image
            ;;
        create)
            create_docker_instance
            ;;
        create-multi)
            create_multi_instances
            ;;
        list)
            list_instances
            ;;
        start)
            if [[ -z "${2:-}" ]]; then
                print_error "Specify the instance name"
                exit 1
            fi
            manage_instance start "$2"
            ;;
        stop)
            if [[ -z "${2:-}" ]]; then
                print_error "Specify the instance name"
                exit 1
            fi
            manage_instance stop "$2"
            ;;
        restart)
            if [[ -z "${2:-}" ]]; then
                print_error "Specify the instance name"
                exit 1
            fi
            manage_instance restart "$2"
            ;;
        logs)
            if [[ -z "${2:-}" ]]; then
                print_error "Specify the instance name"
                exit 1
            fi
            manage_instance logs "$2"
            ;;
        status)
            if [[ -z "${2:-}" ]]; then
                print_error "Specify the instance name"
                exit 1
            fi
            manage_instance status "$2"
            ;;
        chat)
            if [[ -z "${2:-}" ]]; then
                print_error "Specify the instance name"
                exit 1
            fi
            manage_instance chat "$2"
            ;;
        login)
            if [[ -z "${2:-}" ]]; then
                print_error "Specify the instance name"
                exit 1
            fi
            manage_instance login-whatsapp "$2"
            ;;
        reconnect)
            if [[ -z "${2:-}" ]]; then
                print_error "Specify the instance name"
                exit 1
            fi
            reconnect_whatsapp "$2"
            ;;
        upgrade-bridge)
            if [[ -z "${2:-}" ]]; then
                print_error "Specify the instance name"
                exit 1
            fi
            upgrade_whatsapp_bridge "$2"
            ;;
        configure-wa)
            if [[ -z "${2:-}" ]]; then
                print_error "Specify the instance name"
                exit 1
            fi
            configure_whatsapp_instance "$2"
            ;;
        delete|remove|rm)
            delete_instance "${2:-}"
            ;;
        start-all)
            manage_all_instances start
            ;;
        stop-all)
            manage_all_instances stop
            ;;
        restart-all)
            manage_all_instances restart
            ;;
        update-all)
            manage_all_instances update
            ;;
        update)
            update_nanobot
            ;;
        rebuild)
            rebuild_docker_image
            ;;
        check)
            check_prerequisites
            ;;
        configure)
            configure_instance_menu
            ;;
        interactive|"")
            interactive_menu
            ;;
        help|--help|-h)
            show_help
            ;;
        *)
            print_error "Unknown command: $command"
            show_help
            exit 1
            ;;
    esac
}

# Execute main if script is called directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    # If no arguments, start interactive menu
    if [[ $# -eq 0 ]]; then
        interactive_menu
    else
        main "$@"
    fi
fi
