#!/usr/bin/env bash
# x2nanobot.sh - AI Manager: Script helper para setup e gerenciamento de instâncias nanobot
# Autor: Criado por opencode para facilitar o uso do nanobot
# Uso: ./x2nanobot.sh [comando] [opções]

set -euo pipefail

# Nome do script (para exibição dinâmica)
SCRIPT_NAME="$(basename "$0")"

# Cores para output
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
PATCH_WHATSAPP_AUDIO=true  # true = aplicar patch de áudio WhatsApp no build

# Diretório base do aimanager (deve vir primeiro)
# Usar readlink para resolver symlinks corretamente
SCRIPT_PATH="$(readlink -f "$0" 2>/dev/null || echo "$0")"
AIMANAGER_DIR="$(cd "$(dirname "$SCRIPT_PATH")" && pwd)"

# Diretórios padrão
NANOBOT_HOME="${HOME}/.nanobot"
NANOBOT_INSTANCES="${AIMANAGER_DIR}/nanobot-instances"
NANOBOT_REPO="https://github.com/HKUDS/nanobot.git"
NANOBOT_SOURCE_DIR="${AIMANAGER_DIR}/nanobot-source"  # Fonte do nanobot
BACKUP_DIR="${AIMANAGER_DIR}/backups"  # Backups de instâncias

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
    echo -e "${GREEN}[SUCESSO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[AVISO]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERRO]${NC} $1"
}

print_step() {
    echo -e "${CYAN}[PASSO]${NC} $1"
}

# Verificar sistema operacional
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
        print_error "Sistema operacional não suportado: $(uname -s)"
        print_info "Este script requer Linux, macOS, ou Windows com WSL."
        exit 1
    fi
    
    print_info "Sistema operacional detectado: $OS"
}

check_os

check_command() {
    if ! command -v "$1" &> /dev/null; then
        return 1
    fi
}

check_dependencies() {
    print_step "Verificando dependências..."
    local missing=()
    
    # Docker
    if ! check_command docker; then
        missing+=("docker")
        print_warning "Docker não encontrado. Será necessário para instâncias Docker."
    fi
    
    # Docker Compose (v2+)
    if ! docker compose version &> /dev/null; then
        missing+=("docker-compose")
        print_warning "Docker Compose (v2+) não encontrado."
    fi
    
    # Verificar se Docker está rodando
    if command -v docker &> /dev/null; then
        if ! docker info &> /dev/null; then
            print_warning "Docker não está rodando. Inicie o serviço Docker."
        fi
    fi
    
    # Git
    if ! check_command git; then
        missing+=("git")
        print_warning "Git não encontrado."
    fi
    
    # Python
    if ! check_command python3 && ! check_command python; then
        missing+=("python3")
        print_warning "Python não encontrado."
    fi
    
    # Pip
    if ! check_command pip3 && ! check_command pip; then
        missing+=("pip")
        print_warning "Pip não encontrado."
    fi
    
    if [ ${#missing[@]} -gt 0 ]; then
        print_warning "Dependências faltando: ${missing[*]}"
        echo "Instale as dependências necessárias antes de continuar."
        return 1
    fi
    
    print_success "Todas as dependências encontradas!"
    return 0
}

# ============================================================
# Funções do Guia Docker Multi-Tenant
# ============================================================

check_prerequisites() {
    print_step "Verificando pré-requisitos (conforme guia)..."
    
    # Docker version (20.10+)
    local docker_version
    if command -v docker &> /dev/null; then
        docker_version=$(docker --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+')
        print_info "Docker version: $docker_version"
    else
        print_error "Docker não encontrado."
        return 1
    fi
    
    # Docker Compose version (2.0+)
    local compose_version
    if docker compose version &> /dev/null; then
        compose_version=$(docker compose version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+')
        print_info "Docker Compose version: $compose_version"
    else
        print_error "Docker Compose não encontrado."
        return 1
    fi
    
    print_success "Pré-requisitos OK: Docker $docker_version, Docker Compose $compose_version"
    return 0
}

# ============================================================
# PATCH: WhatsApp Audio Download
# ============================================================

apply_audio_patch() {
    local repo_dir="$1"
    local whatsapp_file="${repo_dir}/bridge/src/whatsapp.ts"
    
    if [[ ! -f "$whatsapp_file" ]]; then
        print_error "Arquivo whatsapp.ts não encontrado: $whatsapp_file"
        return 1
    fi
    
    # Verificar se patch já foi aplicado
    if grep -q "unwrapped.audioMessage" "$whatsapp_file"; then
        print_info "Patch de áudio já aplicado."
        return 0
    fi
    
    print_step "Aplicando patch de áudio WhatsApp..."
    
    # Use environment variable to pass filepath, heredoc with single quotes to prevent bash expansion
    WHATSAPP_FILE="$whatsapp_file" python3 << 'PYEOF'
import sys, os

filepath = os.environ.get('WHATSAPP_FILE', '')
if not filepath:
    print('ERRO: WHATSAPP_FILE nao definido.')
    sys.exit(1)

with open(filepath, 'r') as f:
    content = f.read()

if 'unwrapped.audioMessage' in content:
    print('Patch ja aplicado.')
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
    print('Patch aplicado com sucesso.')
else:
    print('ERRO: Nao foi possivel encontrar ponto de insercao.')
    sys.exit(1)
PYEOF
    
    if [[ $? -eq 0 ]]; then
        print_success "Patch de áudio aplicado!"
        return 0
    else
        print_error "Falha ao aplicar patch de áudio."
        return 1
    fi
}

build_nanobot_image() {
    print_step "Construindo imagem Docker do nanobot (conforme guia)..."
    
    # Clonar ou atualizar repositório
    if [[ ! -d "$NANOBOT_SOURCE_DIR" ]]; then
        print_step "Clonando repositório nanobot..."
        git clone "$NANOBOT_REPO" "$NANOBOT_SOURCE_DIR"
    else
        print_step "Atualizando repositório..."
        cd "$NANOBOT_SOURCE_DIR" && git pull && cd -
    fi
    
    # Aplicar patch de áudio se habilitado
    if [[ "$PATCH_WHATSAPP_AUDIO" == "true" ]]; then
        apply_audio_patch "$NANOBOT_SOURCE_DIR"
    fi
    
    # Construir imagem
    print_step "Executando: docker build -t nanobot ."
    cd "$NANOBOT_SOURCE_DIR"
    docker build -t nanobot .
    cd - > /dev/null 2>&1
    
    print_success "Imagem Docker construída com sucesso!"
    return 0
}

setup_guide_flow() {
    print_header
    print_step "Configuração completa seguindo o Guia Docker Multi-Tenant..."
    echo
    echo "Este comando executa todo o fluxo do guia:"
    echo "1. Verificar pré-requisitos (Docker 20.10+, Docker Compose 2.0+)"
    echo "2. Construir imagem Docker do nanobot"
    echo "3. Criar instância Docker isolada"
    echo
    read -p "Continuar? (s/n): " confirm
    
    if [[ "$confirm" != "s" && "$confirm" != "S" ]]; then
        print_info "Configuração cancelada."
        return 0
    fi
    
    # 1. Verificar pré-requisitos
    if ! check_prerequisites; then
        print_error "Pré-requisitos não atendidos. Instale Docker e Docker Compose."
        return 1
    fi
    
    # 2. Construir imagem Docker
    if ! build_nanobot_image; then
        print_error "Falha ao construir imagem Docker."
        return 1
    fi
    
    # 3. Criar instância
    echo
    print_step "Agora vamos criar sua primeira instância Docker..."
    create_docker_instance
}

# ============================================================
# Funções de Instalação
# ============================================================

install_nanobot_pip() {
    print_step "Instalando nanobot via pip..."
    pip3 install -U nanobot-ai
    print_success "nanobot instalado via pip!"
}

install_nanobot_uv() {
    print_step "Instalando nanobot via uv..."
    if ! check_command uv; then
        print_warning "uv não encontrado. Instalando uv primeiro..."
        curl -LsSf https://astral.sh/uv/install.sh | sh
        export PATH="$HOME/.local/bin:$PATH"
    fi
    uv tool install nanobot-ai
    print_success "nanobot instalado via uv!"
}

install_nanobot_source() {
    print_step "Instalando nanobot a partir do código fonte..."
    local temp_dir
    temp_dir=$(mktemp -d)
    
    git clone "$NANOBOT_REPO" "$temp_dir/nanobot"
    cd "$temp_dir/nanobot"
    pip3 install -e .
    
    cd - > /dev/null 2>&1
    rm -rf "$temp_dir"
    print_success "nanobot instalado a partir do código fonte!"
}

install_nanobot() {
    print_header
    echo "Escolha o método de instalação:"
    echo "1) pip (recomendado para uso normal)"
    echo "2) uv (estável, rápido)"
    echo "3) Código fonte (últimas funcionalidades, desenvolvimento)"
    echo "4) Voltar"
    echo
    read -p "Opção: " choice
    
    case $choice in
        1) install_nanobot_pip ;;
        2) install_nanobot_uv ;;
        3) install_nanobot_source ;;
        4) return ;;
        *) print_error "Opção inválida!" ;;
    esac
}

# ============================================================
# Funções de Configuração
# ============================================================

setup_initial() {
    print_header
    print_step "Configuração inicial do nanobot..."
    
    # Verificar se nanobot está instalado
    if ! check_command nanobot; then
        print_warning "nanobot não encontrado. Instalando..."
        install_nanobot_pip
    fi
    
    print_step "Executando onboard..."
    if [[ "$1" == "--wizard" ]]; then
        nanobot onboard --wizard
    else
        nanobot onboard
    fi
    
    print_success "Configuração inicial concluída!"
    print_info "Edite ~/.nanobot/config.json para adicionar suas chaves de API."
}

configure_channel() {
    local channel="$1"
    local instance_name="$2"
    
    print_step "Configurando canal: $channel"
    
    case $channel in
        whatsapp)
            echo "Para configurar WhatsApp:"
            echo "1. Certifique-se de que o nanobot está rodando (nanobot gateway)"
            echo "2. Execute: nanobot channels login whatsapp"
            echo "3. Escaneie o QR Code com seu WhatsApp"
            echo "4. Configure em config.json da instância:"
            echo '   "channels": {'
            echo '     "whatsapp": {'
            echo '       "enabled": true,'
            echo '       "allowFrom": ["+5511999999999"],   # ou ["*"] para qualquer pessoa'
            echo '       "groupPolicy": "mention"            # mention|open'
            echo '     }'
            echo '   }'
            echo
            echo "Opções de configuração:"
            echo "  allowFrom:"
            echo '    ["+5511999999999"]  - Apenas números específicos'
            echo '    ["*"]              - Qualquer pessoa pode usar'
            echo "  groupPolicy:"
            echo '    "mention"  - Só responde quando @mencionado em grupos (padrão)'
            echo '    "open"     - Responde a todas as mensagens de grupo'
            echo
            echo "Dica: Use '$SCRIPT_NAME configure-wa <instância>' para configurar interativamente"
            echo
            echo "Importante: Após atualizar nanobot, recrie a sessão:"
            echo "   $SCRIPT_NAME upgrade-bridge <instância>"
            ;;
        telegram)
            echo "Para configurar Telegram:"
            echo "1. Abra Telegram, procure @BotFather"
            echo "2. Envie /newbot e siga as instruções"
            echo "3. Copie o token do bot"
            echo "4. Configure em ~/.nanobot/config.json:"
            echo '   "channels": { "telegram": { "enabled": true, "token": "SEU_TOKEN", "allowFrom": ["SEU_USER_ID"] } }'
            echo
            echo "Dica: Seu User ID aparece nas configurações do Telegram como @seuUserId"
            echo "Copie o valor SEM o símbolo @"
            ;;
        discord)
            echo "Para configurar Discord:"
            echo "1. Acesse https://discord.com/developers/applications"
            echo "2. Crie uma aplicação → Bot → Add Bot"
            echo "3. Copie o token do bot"
            echo "4. Habilite MESSAGE CONTENT INTENT nas configurações do Bot"
            echo "5. Configure em ~/.nanobot/config.json:"
            echo '   "channels": { "discord": { "enabled": true, "token": "SEU_TOKEN", "allowFrom": ["SEU_USER_ID"], "groupPolicy": "mention" } }'
            echo
            echo "Para obter seu User ID:"
            echo "  - Configurações do Discord → Avançado → Habilite Modo Desenvolvedor"
            echo "  - Clique com botão direito no seu avatar → Copiar ID do Usuário"
            ;;
        feishu)
            echo "Para configurar Feishu:"
            echo "1. Acesse https://open.feishu.cn/app"
            echo "2. Crie um novo app → Habilite capacidade Bot"
            echo "3. Permissões: im:message e im:message.p2p_msg:readonly"
            echo "4. Eventos: im.message.receive_v1 (Modo Long Connection)"
            echo "5. Obtenha App ID e App Secret"
            echo "6. Configure em ~/.nanobot/config.json:"
            echo '   "channels": { "feishu": { "enabled": true, "appId": "cli_xxx", "appSecret": "xxx", "allowFrom": ["ou_YOUR_OPEN_ID"], "groupPolicy": "mention" } }'
            ;;
        slack)
            echo "Para configurar Slack:"
            echo "1. Acesse https://api.slack.com/apps"
            echo "2. Crie novo app → From scratch"
            echo "3. Habilite Socket Mode → Gere App-Level Token (connections:write)"
            echo "4. OAuth & Permissions: adicione chat:write, reactions:write, app_mentions:read"
            echo "5. Event Subscriptions: ative message.im, message.channels, app_mention"
            echo "6. Configure em ~/.nanobot/config.json:"
            echo '   "channels": { "slack": { "enabled": true, "botToken": "xoxb-...", "appToken": "xapp-...", "allowFrom": ["SEU_USER_ID"], "groupPolicy": "mention" } }'
            ;;
        matrix)
            echo "Para configurar Matrix:"
            echo "1. Instale dependências: pip install nanobot-ai[matrix]"
            echo "2. Crie/use uma conta Matrix (ex: @nanobot:matrix.org)"
            echo "3. Obtenha accessToken e deviceId"
            echo "4. Configure em ~/.nanobot/config.json:"
            echo '   "channels": { "matrix": { "enabled": true, "homeserver": "https://matrix.org", "userId": "@nanobot:matrix.org", "accessToken": "syt_xxx", "deviceId": "NANOBOT01", "allowFrom": ["@user:matrix.org"] } }'
            ;;
        email)
            echo "Para configurar Email:"
            echo "1. Crie uma conta de email dedicada (ex: my-nanobot@gmail.com)"
            echo "2. Habilite 2-Step Verification → Crie App Password"
            echo "3. Configure em ~/.nanobot/config.json:"
            echo '   "channels": { "email": { "enabled": true, "consentGranted": true, "imapHost": "imap.gmail.com", "imapPort": 993, "imapUsername": "my-nanobot@gmail.com", "imapPassword": "app-password", "smtpHost": "smtp.gmail.com", "smtpPort": 587, "smtpUsername": "my-nanobot@gmail.com", "smtpPassword": "app-password", "allowFrom": ["seu-email@gmail.com"] } }'
            ;;
        *)
            print_error "Canal não suportado: $channel"
            echo "Canais suportados: whatsapp, telegram, discord, feishu, slack, matrix, email"
            ;;
    esac
}

# ============================================================
# Funções de LLM Provider
# ============================================================

select_llm_provider() {
    echo >&2
    print_step "Selecione o provedor LLM:" >&2
    echo >&2
    echo -e "  ${GREEN}1) OpenRouter${NC} (recomendado) - Acesso global a todos os modelos" >&2
    echo -e "  2) OpenAI - API direta OpenAI" >&2
    echo -e "  3) Anthropic - API direta Claude" >&2
    echo -e "  4) DeepSeek - Modelos chineses" >&2
    echo -e "  5) Groq - Inference rápida" >&2
    echo -e "  6) Personalizado (OpenAI-compatible) - Endpoints locais/customizados" >&2
    echo >&2
    read -p "Escolha o provedor [1]: " provider_choice

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
    echo -e "Modelos para $provider:" >&2
    local models=()
    local i=1
    while IFS= read -r model; do
        models+=("$model")
        if [[ "$model" == "$default_model" ]]; then
            echo -e "  ${GREEN}$i) $model (padrão)${NC}" >&2
        else
            echo -e "  $i) $model" >&2
        fi
        ((i++))
    done < <(get_provider_models_list "$provider")
    echo -e "  $i) Outro modelo" >&2
    echo >&2
    read -p "Escolha o modelo [1]: " model_choice

    local selected_model="$default_model"
    local choice_num=${model_choice:-1}
    
    if [[ "$choice_num" -eq $i ]]; then
        read -p "Modelo personalizado: " selected_model
    elif [[ "$choice_num" -ge 1 && "$choice_num" -lt $i ]]; then
        selected_model="${models[$((choice_num-1))]}"
    fi
    
    echo "$selected_model"
}

# ============================================================
# Funções de Instância Docker
# ============================================================

create_docker_instance() {
    print_header
    print_step "Criando nova instância Docker (conforme guia)..."
    
    read -p "Nome da instância (ex: wa1, wa2, telegram1): " instance_name

    echo
    echo "Canais disponíveis:"
    echo "  1) whatsapp"
    echo "  2) telegram"
    echo "  3) discord"
    echo "  4) feishu"
    echo "  5) slack"
    echo "  6) matrix"
    echo "  7) email"
    read -p "Escolha o canal [1 - whatsapp]: " channel_choice
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

    # Selecionar provedor LLM
    local provider
    provider=$(select_llm_provider)
    
    # Solicitar chave API apropriada para o provedor
    local env_key
    env_key=$(get_provider_env_key "$provider")
    local api_key
    local api_base=""
    
    case $provider in
        openrouter)
            read -p "Chave API OpenRouter (sk-or-v1-...): " api_key
            ;;
        openai)
            read -p "Chave API OpenAI (sk-...): " api_key
            ;;
        anthropic)
            read -p "Chave API Anthropic (sk-ant-...): " api_key
            ;;
        deepseek)
            read -p "Chave API DeepSeek (sk-...): " api_key
            ;;
        groq)
            read -p "Chave API Groq (gsk_...): " api_key
            ;;
        custom)
            read -p "Chave API: " api_key
            read -p "URL base da API (ex: http://localhost:8000/v1): " api_base
            ;;
    esac

    # Selecionar modelo
    local default_model
    default_model=$(get_provider_default_model "$provider")
    local model
    model=$(select_provider_model "$provider" "$default_model")

    read -p "Porta externa (ex: 18791, 18792): " port
    read -p "ID do usuário para allowFrom: " user_id
    
    local instance_dir="${NANOBOT_INSTANCES}/${instance_name}"
    
    # Criar diretório da instância
    mkdir -p "$instance_dir"
    
    # Criar config.json (conforme guia)
    create_config_json "$instance_dir" "$channel" "$api_key" "$user_id" "$model" "$provider" "$api_base"
    
    # Criar docker-compose.yml (conforme guia)
    create_docker_compose "$instance_dir" "$instance_name" "$port" "$channel"
    
    print_success "Instância $instance_name criada em $instance_dir!"
    print_info "Configuração:"
    echo "  - Provedor: $provider"
    echo "  - Modelo: $model"
    echo "  - Canal: $channel"
    echo "  - Porta: $port"
    echo
    print_info "Estrutura criada:"
    echo "  - config.json"
    echo "  - docker-compose.yml"
    
    if [[ "$channel" == "whatsapp" ]]; then
        echo "  - bridge/ (será criado após login)"
    fi
    
    echo "  - workspace/ (será criado automaticamente)"
    echo
    print_info "Próximos passos (conforme guia):"
    echo "1. cd $instance_dir"
    
    if [[ "$channel" == "whatsapp" ]]; then
        echo "2. $SCRIPT_NAME login $instance_name"
        echo "   (Escaneie o QR Code com seu WhatsApp)"
        echo "3. $SCRIPT_NAME start $instance_name"
    else
        echo "2. docker compose up -d"
    fi
    echo
    print_info "Para alterar provedor/modelo depois:"
    echo "  $SCRIPT_NAME configure"
    echo "  $SCRIPT_NAME start $instance_name  # Iniciar"
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
    print_step "Criador de múltiplas instâncias (conforme guia)..."
    
    read -p "Quantas instâncias criar? " num_instances
    read -p "Prefixo do nome (ex: wa, tg): " prefix

    echo
    echo "Canais disponíveis:"
    echo "  1) whatsapp"
    echo "  2) telegram"
    echo "  3) discord"
    echo "  4) feishu"
    echo "  5) slack"
    echo "  6) matrix"
    echo "  7) email"
    read -p "Escolha o canal [1 - whatsapp]: " channel_choice
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

    read -p "Porta inicial (ex: 18791): " start_port
    
    # Selecionar provedor LLM
    local provider
    provider=$(select_llm_provider)
    
    # Solicitar chave API apropriada
    local api_key api_base=""
    case $provider in
        openrouter)
            read -p "Chave API OpenRouter (sk-or-v1-...): " api_key
            ;;
        openai)
            read -p "Chave API OpenAI (sk-...): " api_key
            ;;
        anthropic)
            read -p "Chave API Anthropic (sk-ant-...): " api_key
            ;;
        deepseek)
            read -p "Chave API DeepSeek (sk-...): " api_key
            ;;
        groq)
            read -p "Chave API Groq (gsk_...): " api_key
            ;;
        custom)
            read -p "Chave API: " api_key
            read -p "URL base da API (ex: http://localhost:8000/v1): " api_base
            ;;
    esac

    # Selecionar modelo
    local default_model
    default_model=$(get_provider_default_model "$provider")
    local model
    model=$(select_provider_model "$provider" "$default_model")
    
    for ((i=1; i<=num_instances; i++)); do
        local instance_name="${prefix}${i}"
        local port=$((start_port + i - 1))
        local user_id="YOUR_USER_ID_${i}"
        
        echo
        print_step "Criando instância $instance_name (porta: $port, provedor: $provider, modelo: $model)..."
        create_docker_instance_single "$instance_name" "$channel" "$port" "$api_key" "$user_id" "$model" "$provider" "$api_base"
    done
    
    print_success "Todas as $num_instances instâncias criadas!"
    print_info "Configuração:"
    echo "  - Provedor: $provider"
    echo "  - Modelo: $model"
    echo "  - Canal: $channel"
    echo
    print_info "Próximos passos:"
    echo "1. Para cada instância WhatsApp, execute:"
    echo "   $SCRIPT_NAME login ${prefix}1"
    echo "2. Inicie todas:"
    echo "   $SCRIPT_NAME start-all"
    echo "3. Para alterar provedor/modelo:"
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
# Funções de Gerenciamento de Instâncias
# ============================================================

list_instances() {
    print_header
    print_step "Listando instâncias Docker..."
    
    if [[ ! -d "$NANOBOT_INSTANCES" ]]; then
        print_warning "Diretório de instâncias não encontrado: $NANOBOT_INSTANCES"
        return 1
    fi
    
    local instances=()
    for dir in "$NANOBOT_INSTANCES"/*/; do
        if [[ -f "${dir}docker-compose.yml" ]]; then
            instances+=("$(basename "$dir")")
        fi
    done
    
    if [[ ${#instances[@]} -eq 0 ]]; then
        print_warning "Nenhuma instância encontrada."
        return 0
    fi
    
    echo "Instâncias encontradas:"
    for instance in "${instances[@]}"; do
        echo "  - $instance"
    done
}

manage_instance() {
    local action="$1"
    local instance_name="$2"
    local instance_dir="${NANOBOT_INSTANCES}/${instance_name}"
    
    if [[ ! -d "$instance_dir" ]]; then
        print_error "Instância não encontrada: $instance_name"
        return 1
    fi
    
    cd "$instance_dir"
    
    case $action in
        start)
            print_step "Iniciando instância $instance_name..."
            docker compose up -d
            ;;
        stop)
            print_step "Parando instância $instance_name..."
            docker compose down
            ;;
        restart)
            print_step "Reiniciando instância $instance_name..."
            docker compose restart 2>/dev/null || {
                print_warning "Nenhum container rodando. Iniciando..."
                docker compose up -d
            }
            ;;
        logs)
            print_step "Logs da instância $instance_name..."
            local running
            running=$(docker compose ps --format "{{.Names}}" 2>/dev/null)
            if [[ -z "$running" ]]; then
                print_warning "Instância não está rodando. Iniciando..."
                docker compose up -d
            fi
            docker compose logs -f --tail 50
            ;;
        status)
            print_step "Status da instância $instance_name..."
            docker compose run --rm --entrypoint nanobot nanobot status
            ;;
        login-whatsapp)
            print_step "Conectando WhatsApp para $instance_name..."
            docker compose down 2>/dev/null || true
            whatsapp_login_flow "$(pwd)"
            if [[ -f "$(pwd)/bridge/dist/index.js" ]]; then
                print_step "Iniciando instância..."
                docker compose up -d
                print_success "Instância iniciada!"
            fi
            ;;
        chat)
            print_step "Iniciando chat CLI para $instance_name..."
            docker compose run --rm --entrypoint nanobot nanobot agent
            ;;
        update)
            print_step "Atualizando instância $instance_name..."
            docker compose down
            docker compose up -d
            ;;
        *)
            print_error "Ação desconhecida: $action"
            ;;
    esac
    
    cd - > /dev/null 2>&1
}

manage_all_instances() {
    local action="$1"
    
    print_header
    print_step "Gerenciando todas as instâncias..."
    
    if [[ ! -d "$NANOBOT_INSTANCES" ]]; then
        print_warning "Diretório de instâncias não encontrado."
        return 1
    fi
    
    for dir in "$NANOBOT_INSTANCES"/*/; do
        if [[ -f "${dir}docker-compose.yml" ]]; then
            local instance_name
            instance_name=$(basename "$dir")
            echo
            print_step "Processando $instance_name..."
            manage_instance "$action" "$instance_name"
        fi
    done
}

delete_instance() {
    local instance_name="${1:-}"
    
    print_header
    echo -e "${RED}⚠️  DELETAR INSTÂNCIA${NC}"
    echo
    
    # List instances if no name provided
    if [[ -z "$instance_name" ]]; then
        if [[ ! -d "$NANOBOT_INSTANCES" ]]; then
            print_warning "Nenhuma instância encontrada."
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
            print_warning "Nenhuma instância encontrada."
            return 1
        fi
        
        echo
        read -p "Selecione o número da instância a deletar: " sel
        if [[ -z "${instances[$((sel-1))]:-}" ]]; then
            print_error "Seleção inválida."
            return 1
        fi
        instance_name="${instances[$((sel-1))]}"
    fi
    
    local instance_dir="${NANOBOT_INSTANCES}/${instance_name}"
    
    # Check if instance exists
    if [[ ! -d "$instance_dir" ]]; then
        print_error "Instância não encontrada: $instance_name"
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
    echo -e "${YELLOW}━━━ Instância a deletar ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "  Nome:     ${CYAN}$instance_name${NC}"
    echo -e "  Canal:    $ch"
    echo -e "  Modelo:   $model"
    echo -e "  Pasta:    $instance_dir"
    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo
    echo -e "${RED}Esta ação é IRREVERSÍVEL!${NC}"
    echo -e "${RED}Será removido:${NC}"
    echo "  - Container Docker (nanobot-$instance_name)"
    echo "  - Todas as pastas da instância"
    echo "  - Dados de sessão WhatsApp (se houver)"
    echo
    
    # Offer backup
    read -p "Fazer backup do config.json? (s/n) [s]: " do_backup
    if [[ "${do_backup:-s}" == "s" || "${do_backup:-s}" == "S" ]]; then
        local backup_dir="${BACKUP_DIR}"
        local backup_name="${instance_name}_$(date +%Y%m%d_%H%M%S)"
        mkdir -p "$backup_dir/$backup_name"
        cp "$instance_dir/config.json" "$backup_dir/$backup_name/"
        cp "$instance_dir/docker-compose.yml" "$backup_dir/$backup_name/" 2>/dev/null || true
        print_success "Backup salvo em: $backup_dir/$backup_name/"
        echo
    fi
    
    # Double confirmation - type instance name
    echo -e "${RED}Para confirmar, digite o nome da instância: ${NC}"
    read -p "> " confirm_name
    
    if [[ "$confirm_name" != "$instance_name" ]]; then
        print_error "Nome não corresponde. Operação cancelada."
        return 1
    fi
    
    echo
    print_step "Deletando instância $instance_name..."
    
    # Stop and remove container
    if docker ps -a --format "{{.Names}}" | grep -q "^nanobot-${instance_name}$"; then
        print_step "Removendo container..."
        cd "$instance_dir"
        docker compose down 2>/dev/null || true
        docker rm -f "nanobot-$instance_name" 2>/dev/null || true
        cd - > /dev/null 2>&1
    fi
    
    # Remove directory
    print_step "Removendo arquivos..."
    sudo rm -rf "$instance_dir"
    
    # Clean up any orphaned volumes (optional)
    docker volume prune -f 2>/dev/null || true
    
    echo
    print_success "Instância $instance_name deletada com sucesso!"
}

# ============================================================
# Funções de Atualização
# ============================================================

update_nanobot() {
    print_header
    print_step "Atualizando nanobot..."
    
    echo "Como você instalou o nanobot?"
    echo "1) pip"
    echo "2) uv"
    echo "3) Código fonte"
    echo
    read -p "Opção: " choice
    
    case $choice in
        1)
            print_step "Atualizando via pip..."
            pip3 install -U nanobot-ai
            ;;
        2)
            print_step "Atualizando via uv..."
            uv tool upgrade nanobot-ai
            ;;
        3)
            print_step "Atualizando a partir do código fonte..."
            if [[ -d "nanobot" ]]; then
                cd nanobot
                git pull
                pip3 install -e .
                cd - > /dev/null 2>&1
            else
                print_warning "Repositório nanobot não encontrado no diretório atual."
                print_info "Clonando novamente..."
                install_nanobot_source
            fi
            ;;
        *)
            print_error "Opção inválida!"
            ;;
    esac
    
    print_success "nanobot atualizado!"
    nanobot --version
}

rebuild_docker_image() {
    print_header
    print_step "Reconstruindo imagem Docker do nanobot (conforme guia)..."
    
    # Clonar ou atualizar repositório
    if [[ ! -d "$NANOBOT_SOURCE_DIR" ]]; then
        print_step "Clonando repositório..."
        git clone "$NANOBOT_REPO" "$NANOBOT_SOURCE_DIR"
    else
        print_step "Atualizando repositório..."
        cd "$NANOBOT_SOURCE_DIR" && git pull && cd -
    fi
    
    # Aplicar patch de áudio se habilitado
    if [[ "$PATCH_WHATSAPP_AUDIO" == "true" ]]; then
        apply_audio_patch "$NANOBOT_SOURCE_DIR"
    fi
    
    cd "$NANOBOT_SOURCE_DIR"
    docker build -t nanobot .
    cd - > /dev/null 2>&1
    
    print_success "Imagem Docker reconstruída!"
    print_info "Para atualizar as instâncias, execute: $SCRIPT_NAME update-all"
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
        print_step "Inicializando bridge WhatsApp a partir da imagem..."
        init_whatsapp_bridge "$instance_dir"
    fi

    # Create auth directory
    mkdir -p whatsapp-auth

    echo
    print_step "Iniciando login WhatsApp..."
    echo
    echo -e "${YELLOW}  1. QR Code vai aparecer abaixo${NC}"
    echo -e "${YELLOW}  2. Abra WhatsApp → Dispositivos vinculados → Vincular dispositivo${NC}"
    echo -e "${YELLOW}  3. Escaneie o QR Code${NC}"
    echo -e "${YELLOW}  4. Quando ver 'Connected', pressione Ctrl+C${NC}"
    echo
    read -p "  Pressione Enter para começar..."

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
        print_success "WhatsApp conectado! Sessão salva."
    else
        print_warning "Sessão não detectada em whatsapp-auth/. Login pode ter falhado."
    fi

    cd - > /dev/null 2>&1
}

reconnect_whatsapp() {
    local instance_name="$1"
    local instance_dir="${NANOBOT_INSTANCES}/${instance_name}"
    
    if [[ ! -d "$instance_dir" ]]; then
        print_error "Instância não encontrada: $instance_name"
        return 1
    fi
    
    print_step "Reconectando WhatsApp para $instance_name..."
    
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
    
    print_success "WhatsApp reconectado para $instance_name!"
}

upgrade_whatsapp_bridge() {
    local instance_name="$1"
    local instance_dir="${NANOBOT_INSTANCES}/${instance_name}"

    if [[ ! -d "$instance_dir" ]]; then
        print_error "Instância não encontrada: $instance_name"
        return 1
    fi

    print_step "Atualizando WhatsApp bridge para $instance_name..."

    cd "$instance_dir"
    docker compose down 2>/dev/null || true
    cd - > /dev/null 2>&1

    # Clear bridge and auth — full rebuild
    rm -rf "$instance_dir/bridge" "$instance_dir/whatsapp-auth"

    print_step "Recriando bridge com a versão mais recente..."
    whatsapp_login_flow "$instance_dir"

    # Start instance
    cd "$instance_dir"
    docker compose up -d
    cd - > /dev/null 2>&1

    print_success "Bridge WhatsApp atualizado e instância reiniciada!"
}

configure_whatsapp_instance() {
    local instance_name="$1"
    local instance_dir="${NANOBOT_INSTANCES}/${instance_name}"

    if [[ ! -d "$instance_dir" ]]; then
        print_error "Instância não encontrada: $instance_name"
        return 1
    fi

    local config_file="${instance_dir}/config.json"
    if [[ ! -f "$config_file" ]]; then
        print_error "config.json não encontrado em $instance_dir"
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
        print_error "Instância $instance_name não é WhatsApp (canal: $channel)"
        return 1
    fi

    print_header
    print_step "Configurando WhatsApp para $instance_name..."
    echo

    # Ler configuração atual
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

    echo -e "${CYAN}Configuração atual:${NC}"
    echo "  Habilitado: $current_enabled"
    echo "  allowFrom: $current_allow_from"
    echo "  groupPolicy: $current_group_policy"
    echo

    echo -e "${GREEN}━━━ Configurar WhatsApp ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo "  [1] Permitir acesso de qualquer pessoa (allowFrom: [\"*\"])"
    echo "  [2] Definir números específicos (allowFrom)"
    echo "  [3] Política de grupo: mention (só responde quando mencionado)"
    echo "  [4] Política de grupo: open (responde a todas as mensagens)"
    echo "  [5] Habilitar / Desabilitar canal"
    echo "  [6] Mostrar config.json atual"
    echo "  [7] Editar config.json manualmente (nano)"
    echo "  [0] Voltar"
    echo

    while true; do
        read -p "Escolha [0-7]: " wa_choice
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
                print_success "allowFrom configurado para [\"*\"] - qualquer pessoa pode usar"
                ;;
            2)
                echo "Digite os números separados por vírgula (ex: +5511999999999,+5511888888888):"
                read -p "Números: " numbers
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
                print_success "groupPolicy = mention (só responde quando @mencionado em grupos)"
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
                print_success "groupPolicy = open (responde a todas as mensagens de grupo)"
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
                print_success "Canal enabled = $new_enabled"
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
                    print_warning "Nenhum editor encontrado. Edite manualmente: $config_file"
                fi
                ;;
            0)
                # Reiniciar instância se estiver rodando
                local running
                running=$(docker ps --filter "name=nanobot-${instance_name}" --format "{{.Names}}" 2>/dev/null)
                if [[ -n "$running" ]]; then
                    echo
                    read -p "Reiniciar instância para aplicar mudanças? (s/n): " restart_confirm
                    if [[ "$restart_confirm" == "s" || "$restart_confirm" == "S" ]]; then
                        cd "$instance_dir"
                        docker compose restart
                        cd - > /dev/null 2>&1
                        print_success "Instância reiniciada!"
                    fi
                fi
                return 0
                ;;
            *)
                print_error "Opção inválida."
                ;;
        esac
        echo
    done
}

configure_instance_menu() {
    local instances=()

    if [[ ! -d "$NANOBOT_INSTANCES" ]]; then
        print_error "Nenhuma instância encontrada."
        return 1
    fi

    for dir in "$NANOBOT_INSTANCES"/*/; do
        if [[ -f "${dir}config.json" ]]; then
            instances+=("$(basename "$dir")")
        fi
    done

    if [[ ${#instances[@]} -eq 0 ]]; then
        print_error "Nenhuma instância encontrada."
        return 1
    fi

    print_header
    print_step "Configurar instância..."
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
print(chs[0] if chs else 'desconhecido')
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
    read -p "Selecione o número da instância: " sel

    if [[ -z "${cfg_map[$sel]:-}" ]]; then
        print_error "Seleção inválida."
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

    # Configuração genérica para outros canais
    echo
    print_step "Configurando $selected (canal: $channel)..."
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

    echo -e "${CYAN}Canal: $channel${NC}"
    echo "  allowFrom: $allow_from_str"
    echo "  groupPolicy: $group_policy"
    
    # Obter provider e modelo atuais
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

    echo -e "${GREEN}━━━ Configurar $channel ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo "  [1] allowFrom: permitir qualquer pessoa"
    echo "  [2] allowFrom: definir IDs/números específicos"
    echo "  [3] groupPolicy: mention (só quando mencionado)"
    echo "  [4] groupPolicy: open (responde tudo)"
    echo "  [5] Alterar modelo LLM"
    echo "  [6] Alterar chave API"
    echo "  [7] Alterar provedor LLM"
    echo "  [8] Mostrar config.json completo"
    echo "  [9] Editar manualmente (nano)"
    echo "  [0] Voltar"
    echo

    while true; do
        read -p "Escolha [0-9]: " cfg_choice
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
                read -p "IDs/números (separados por vírgula): " ids
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
                    print_success "allowFrom atualizado"
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
                # Obter modelo atual para destacar
                local current_model
                current_model=$(python3 -c "
import json
with open('$cfg') as f:
    c = json.load(f)
print(c.get('agents',{}).get('defaults',{}).get('model',''))
" 2>/dev/null)
                
                echo "Modelos para $provider_now:"
                local models=()
                local i=1
                while IFS= read -r model; do
                    models+=("$model")
                    if [[ "$model" == "$current_model" ]]; then
                        echo "  ${GREEN}$i) $model (atual)${NC}"
                    else
                        echo "  $i) $model"
                    fi
                    ((i++))
                done < <(get_provider_models_list "$provider_now")
                echo "  $i) Outro modelo"
                read -p "Escolha [1-$i]: " mc
                local new_model="$current_model"
                local choice_num=${mc:-1}
                
                if [[ "$choice_num" -eq $i ]]; then
                    read -p "Modelo personalizado: " new_model
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
                    print_success "Modelo alterado para $new_model"
                fi
                ;;
            6)
                local env_key
                env_key=$(get_provider_env_key "$provider_now")
                echo "Provedor atual: $provider_now"
                echo "Variável de ambiente: $env_key"
                read -p "Nova chave API: " new_key
                if [[ -n "$new_key" ]]; then
                    # Determinar qual provider section atualizar
                    local provider_key="$provider_now"
                    if [[ "$provider_now" == "auto" ]]; then
                        provider_key="openai"  # Custom endpoints usam openai compat
                    fi
                    
                    python3 << PYEOF
import json
with open("$cfg", "r") as f:
    c = json.load(f)
c.setdefault("providers",{}).setdefault("$provider_key",{})["apiKey"] = "$new_key"
with open("$cfg", "w") as f:
    json.dump(c, f, indent=2)
PYEOF
                    print_success "Chave API atualizada"
                fi
                ;;
            7)
                # Alterar provedor LLM
                echo
                print_step "Alterando provedor LLM..."
                local new_provider
                new_provider=$(select_llm_provider)
                
                # Solicitar nova chave API
                local new_api_key new_api_base=""
                case $new_provider in
                    openrouter)
                        read -p "Chave API OpenRouter (sk-or-v1-...): " new_api_key
                        ;;
                    openai)
                        read -p "Chave API OpenAI (sk-...): " new_api_key
                        ;;
                    anthropic)
                        read -p "Chave API Anthropic (sk-ant-...): " new_api_key
                        ;;
                    deepseek)
                        read -p "Chave API DeepSeek (sk-...): " new_api_key
                        ;;
                    groq)
                        read -p "Chave API Groq (gsk_...): " new_api_key
                        ;;
                    custom)
                        read -p "Chave API: " new_api_key
                        read -p "URL base da API (ex: http://localhost:8000/v1): " new_api_base
                        ;;
                esac
                
                # Selecionar novo modelo
                local default_model new_model
                default_model=$(get_provider_default_model "$new_provider")
                new_model=$(select_provider_model "$new_provider" "$default_model")
                
                # Atualizar config.json
                python3 << PYEOF
import json
with open("$cfg", "r") as f:
    c = json.load(f)

# Limpar providers antigos e adicionar novo
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

# Atualizar agent defaults
provider_value = "$new_provider"
if provider_value == "custom":
    provider_value = "auto"
    
c.setdefault("agents",{}).setdefault("defaults",{})["provider"] = provider_value
c["agents"]["defaults"]["model"] = "$new_model"

with open("$cfg", "w") as f:
    json.dump(c, f, indent=2)
PYEOF
                print_success "Provedor alterado para $new_provider com modelo $new_model"
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
                    print_warning "Edite manualmente: $cfg"
                fi
                ;;
            0)
                # Perguntar se reinicia
                local running
                running=$(docker ps --filter "name=nanobot-${selected}" --format "{{.Names}}" 2>/dev/null)
                if [[ -n "$running" ]]; then
                    read -p "Reiniciar para aplicar? (s/n): " rc
                    if [[ "$rc" == "s" || "$rc" == "S" ]]; then
                        cd "${NANOBOT_INSTANCES}/${selected}"
                        docker compose restart
                        cd - > /dev/null 2>&1
                        print_success "Instância reiniciada!"
                    fi
                fi
                return 0
                ;;
            *)
                print_error "Opção inválida."
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
    echo -e "${CYAN}╔══════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║${NC}    ${PURPLE}🐈 Nanobot Helper v2.0${NC}                              ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}    ${BLUE}WhatsApp Audio Patch + Multi-Provider LLM${NC}             ${CYAN}║${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════════════════════════════════╝${NC}"
    echo
    echo -e "  ${PURPLE}⚡ Configuração${NC}"
    echo -e "    ${YELLOW}[1]${NC} Configurar Tudo  ${YELLOW}[2]${NC} Pré-requisitos  ${YELLOW}[3]${NC} Build Imagem"
    echo
    echo -e "  ${CYAN}📦 Instâncias${NC}"
    echo -e "    ${CYAN}[4]${NC} Criar  ${CYAN}[5]${NC} Criar Múltiplas  ${CYAN}[6]${NC} Listar"
    echo
    echo -e "  ${GREEN}🎮 Controle${NC}"
    echo -e "    ${GREEN}[7]${NC} Iniciar  ${RED}[8]${NC} Parar  ${BLUE}[9]${NC} Reiniciar"
    echo -e "    ${PURPLE}[10]${NC} Status  ${CYAN}[11]${NC} Logs  ${CYAN}[12]${NC} Chat"
    echo
    echo -e "  ${GREEN}📱 WhatsApp${NC}"
    echo -e "    ${GREEN}[13]${NC} Login  ${YELLOW}[14]${NC} Reconectar  ${YELLOW}[15]${NC} Update Bridge"
    echo -e "    ${CYAN}[16]${NC} Configurar"
    echo
    echo -e "  ${BLUE}🔄 Em Lote${NC}"
    echo -e "    ${GREEN}[17]${NC} Iniciar Todas  ${RED}[18]${NC} Parar Todas"
    echo -e "    ${BLUE}[19]${NC} Reiniciar Todas  ${YELLOW}[20]${NC} Atualizar Todas"
    echo
    echo -e "  ${PURPLE}🔧 Sistema${NC}"
    echo -e "    ${PURPLE}[21]${NC} Atualizar Nanobot  ${PURPLE}[22]${NC} Reconstruir Imagem"
    echo -e "    ${CYAN}[23]${NC} Config Instância  ${CYAN}[24]${NC} Ajuda"
    echo
    echo -e "  ${RED}⚠️  Perigo${NC}"
    echo -e "    ${RED}[25]${NC} Deletar Instância ${RED}(IRREVERSÍVEL)${NC}"
    echo
    echo -e "    ${RED}[0]${NC} Sair"
    echo
}

select_instance() {
    local action="$1"
    local instances=()
    
    # Listar instâncias disponíveis
    if [[ ! -d "$NANOBOT_INSTANCES" ]]; then
        print_error "Nenhuma instância encontrada. Crie uma instância primeiro."
        return 1
    fi
    
    for dir in "$NANOBOT_INSTANCES"/*/; do
        if [[ -f "${dir}docker-compose.yml" ]]; then
            instances+=("$(basename "$dir")")
        fi
    done
    
    if [[ ${#instances[@]} -eq 0 ]]; then
        print_error "Nenhuma instância encontrada. Crie uma instância primeiro."
        return 1
    fi
    
    echo
    echo -e "${CYAN}Instâncias disponíveis:${NC}"
    echo
    
    local i=1
    for instance in "${instances[@]}"; do
        echo -e "  ${YELLOW}[$i]${NC} $instance"
        instance_map[$i]="$instance"
        ((i++))
    done
    
    echo
    read -p "Selecione o número da instância: " selection
    
    if [[ -z "${instance_map[$selection]:-}" ]]; then
        print_error "Seleção inválida."
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
    
    # Mensagem de boas-vindas
    clear
    echo -e "${PURPLE}══════════════════════════════════════════════════════════════════${NC}"
    echo -e "${PURPLE}                    🐈 Nanobot Helper v1.0${NC}"
    echo -e "${PURPLE}══════════════════════════════════════════════════════════════════${NC}"
    echo
    echo -e "${GREEN}Bem-vindo ao Nanobot Helper!${NC}"
    echo
    echo -e "${CYAN}Este script facilita a criação e gerenciamento de instâncias"
    echo -e "isoladas do Nanobot usando Docker (Guia Multi-Tenant).${NC}"
    echo
    echo -e "${YELLOW}Recomendação: Use a opção [1] Configurar Tudo para começar!${NC}"
    echo
    read -p "Pressione Enter para continuar..."
    
    while true; do
        show_menu
        read -p "Escolha uma opção [0-25]: " choice
        
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
                select_instance "logs"
                ;;
            10)
                select_instance "status"
                ;;
            11)
                select_instance "restart"
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
                update_nanobot
                ;;
            22)
                rebuild_docker_image
                ;;
            23)
                configure_instance_menu
                ;;
            24)
                show_help
                ;;
            25)
                delete_instance
                ;;
            0)
                echo
                print_info "Saindo do Nanobot Helper. Até logo! 🐈"
                exit 0
                ;;
            *)
                print_error "Opção inválida. Escolha um número de 0 a 25."
                ;;
        esac
        
        echo
        read -p "Pressione Enter para continuar..."
    done
}

# ============================================================
# Modo Linha de Comando
# ============================================================

show_help() {
    print_header
    echo "Uso: $0 [comando] [opções]"
    echo "Guia Docker Multi-Tenant - Instâncias Docker isoladas"
    echo
    echo "Configuração (Conforme Guia):"
    echo "  setup-guide      - Configuração completa (pré-requisitos + build + instância)"
    echo "  check            - Verificar pré-requisitos (Docker 20.10+, Compose 2.0+)"
    echo "  build            - Construir imagem Docker (git clone + docker build)"
    echo
    echo "Instâncias Docker (Isoladas):"
    echo "  create           - Criar nova instância Docker isolada"
    echo "  create-multi     - Criar múltiplas instâncias"
    echo "  list             - Listar instâncias"
    echo
    echo "Gerenciamento por Instância:"
    echo "  start <name>     - Iniciar instância"
    echo "  stop <name>      - Parar instância"
    echo "  restart <name>   - Reiniciar instância"
    echo "  logs <name>      - Ver logs"
    echo "  status <name>    - Ver status"
    echo "  chat <name>      - Chat CLI"
    echo "  login <name>     - Conectar WhatsApp (QR Code)"
    echo "  reconnect <name> - Reconectar WhatsApp (trocar conta)"
    echo "  delete <name>    - Deletar instância (IRREVERSÍVEL)"
    echo
    echo "WhatsApp:"
    echo "  upgrade-bridge <name> - Atualizar bridge WhatsApp (recriar com lib mais recente)"
    echo "  configure-wa <name>   - Configurar WhatsApp (allowFrom, groupPolicy, etc)"
    echo
    echo "Gerenciamento em Lote:"
    echo "  start-all        - Iniciar todas as instâncias"
    echo "  stop-all         - Parar todas as instâncias"
    echo "  restart-all      - Reiniciar todas as instâncias"
    echo "  update-all       - Atualizar todas as instâncias"
    echo
    echo "Atualização:"
    echo "  update           - Atualizar nanobot (pip/uv)"
    echo "  rebuild          - Reconstruir imagem Docker"
    echo
    echo "Utilidades:"
    echo "  install          - Instalar nanobot (pip/uv/fonte)"
    echo "  setup            - Configuração inicial (onboard)"
    echo "  configure        - Configurar instância (selecionar e editar)"
    echo "  interactive      - Modo interativo"
    echo "  help             - Mostrar ajuda"
    echo
    echo "Provedores LLM Suportados:"
    echo "  - OpenRouter (padrão) - Acesso global, qualquer modelo"
    echo "  - OpenAI - API direta OpenAI"
    echo "  - Anthropic - API direta Claude"
    echo "  - DeepSeek - Modelos chineses"
    echo "  - Groq - Inference rápida"
    echo "  - Personalizado - Endpoints OpenAI-compatible"
    echo
    echo "Exemplos (conforme guia):"
    echo "  $0 setup-guide               # Configuração completa"
    echo "  $0 create                    # Criar instância com seleção de provedor"
    echo "  $0 configure                 # Alterar provedor/modelo de instância existente"
    echo "  $0 login wa1                 # Conectar WhatsApp"
    echo "  $0 start wa1                 # Iniciar instância"
    echo "  $0 logs wa1                  # Ver logs"
    echo "  $0 reconnect wa1             # Reconectar WhatsApp"
    echo "  $0 upgrade-bridge wa1        # Atualizar bridge WhatsApp"
    echo "  $0 configure-wa wa1          # Configurar WhatsApp (allowFrom, grupos)"
    echo "  $0 delete wa1                # Deletar instância (com confirmação)"
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
                print_error "Especifique o nome da instância"
                exit 1
            fi
            manage_instance start "$2"
            ;;
        stop)
            if [[ -z "${2:-}" ]]; then
                print_error "Especifique o nome da instância"
                exit 1
            fi
            manage_instance stop "$2"
            ;;
        restart)
            if [[ -z "${2:-}" ]]; then
                print_error "Especifique o nome da instância"
                exit 1
            fi
            manage_instance restart "$2"
            ;;
        logs)
            if [[ -z "${2:-}" ]]; then
                print_error "Especifique o nome da instância"
                exit 1
            fi
            manage_instance logs "$2"
            ;;
        status)
            if [[ -z "${2:-}" ]]; then
                print_error "Especifique o nome da instância"
                exit 1
            fi
            manage_instance status "$2"
            ;;
        chat)
            if [[ -z "${2:-}" ]]; then
                print_error "Especifique o nome da instância"
                exit 1
            fi
            manage_instance chat "$2"
            ;;
        login)
            if [[ -z "${2:-}" ]]; then
                print_error "Especifique o nome da instância"
                exit 1
            fi
            manage_instance login-whatsapp "$2"
            ;;
        reconnect)
            if [[ -z "${2:-}" ]]; then
                print_error "Especifique o nome da instância"
                exit 1
            fi
            reconnect_whatsapp "$2"
            ;;
        upgrade-bridge)
            if [[ -z "${2:-}" ]]; then
                print_error "Especifique o nome da instância"
                exit 1
            fi
            upgrade_whatsapp_bridge "$2"
            ;;
        configure-wa)
            if [[ -z "${2:-}" ]]; then
                print_error "Especifique o nome da instância"
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
            print_error "Comando desconhecido: $command"
            show_help
            exit 1
            ;;
    esac
}

# Executar main se o script for chamado diretamente
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    # Se sem argumentos, iniciar menu interativo
    if [[ $# -eq 0 ]]; then
        interactive_menu
    else
        main "$@"
    fi
fi
