# 🐈 AI Manager

**Tired of complex AI agent setups?**

Running 100 commands just to configure a simple AI agent? Want 2 isolated agents (or more) but don't want to deal with environment conflicts, dependency hell, and manual configuration for every single one?

**AI Manager fixes that.**

One script. Interactive menu. Done. Create isolated AI agents in seconds - each with its own memory, channels, and LLM provider. WhatsApp, Telegram, Discord - all with a few keystrokes.

## ✨ Features

- **Interactive Menu** - Clean CLI with real-time agent status
- **Multi-Instance** - Run multiple isolated nanobot agents
- **WhatsApp Audio** - Native voice message support (patched bridge)
- **Multi-Provider LLM** - OpenRouter, OpenAI, Anthropic, DeepSeek, Groq, or custom
- **Docker Isolation** - Each instance runs in its own container
- **Git Versioned** - Track your configuration and patches

## 📋 Requirements

- Docker 20.10+
- Docker Compose v2+
- Git
- Python 3.x

## 🚀 Quick Start

```bash
# Clone the repo
git clone https://github.com/youruser/aimanager.git
cd aimanager

# Make script executable
chmod +x xnanobot.sh

# Run interactive menu
./xnanobot.sh
```

### First Time Setup

```
╔══════════════════════════════════════════════════════════════════╗
║    🐈 Nanobot Helper v2.0                                        ║
║    WhatsApp Audio Patch + Multi-Provider LLM                     ║
╚══════════════════════════════════════════════════════════════════╝
  📊 Agents
  [wa1] WhatsApp ✅ Connected

  ⚡ Configuração
    [1] Configurar Tudo  [2] Pré-requisitos  [3] Build Imagem

  📦 Instâncias
    [4] Criar  [5] Criar Múltiplas  [6] Listar
    ...
```

## 📖 Usage

### Interactive Menu

```bash
./xnanobot.sh          # Launch interactive menu
```

### CLI Commands

| Command | Description |
|---------|-------------|
| `./xnanobot.sh create` | Create new instance |
| `./xnanobot.sh list` | List all instances |
| `./xnanobot.sh start <name>` | Start instance |
| `./xnanobot.sh stop <name>` | Stop instance |
| `./xnanobot.sh logs <name>` | View instance logs |
| `./xnanobot.sh status <name>` | Check instance status |
| `./xnanobot.sh login <name>` | WhatsApp QR login |
| `./xnanobot.sh delete <name>` | Delete instance (irreversible) |
| `./xnanobot.sh rebuild` | Rebuild Docker image with patches |

### Creating a WhatsApp Agent

```bash
# 1. Create instance
./xnanobot.sh create
# Enter: name, select WhatsApp, choose provider, enter API key

# 2. Login (scan QR code)
./xnanobot.sh login wa1

# 3. Start
./xnanobot.sh start wa1

# 4. Verify connection
./xnanobot.sh status wa1
```

## 🏗️ Architecture

```
~/aimanager/
├── xnanobot.sh              # Main script
├── nanobot-instances/       # All instances
│   ├── wa1/
│   │   ├── config.json      # Instance config
│   │   ├── docker-compose.yml
│   │   ├── bridge/          # WhatsApp bridge (patched)
│   │   ├── workspace/       # Agent memory
│   │   └── whatsapp-auth/   # Session data
│   └── wa2/
├── nanobot-source/          # Nanobot source (for builds)
└── docs/
```

### How It Works

```
┌─────────────────────────────────────────────────────────────┐
│                        HOST                                 │
│  ┌───────────────────────────────────────────────────────┐  │
│  │              nanobot-instances/wa1                    │  │
│  │  ┌─────────────────────────────────────────────────┐  │  │
│  │  │              Docker Container                   │  │  │
│  │  │                                                 │  │  │
│  │  │   ┌─────────────┐      ┌─────────────────┐    │  │  │
│  │  │   │   Bridge    │◄────►│     Gateway     │    │  │  │
│  │  │   │  (Node.js)  │ ws   │    (Python)     │    │  │  │
│  │  │   │  Port 3001  │      │   Port 18790    │    │  │  │
│  │  │   └──────┬──────┘      └────────┬────────┘    │  │  │
│  │  │          │                       │             │  │  │
│  │  │          ▼                       ▼             │  │  │
│  │  │    ┌─────────┐           ┌────────────┐       │  │  │
│  │  │    │WhatsApp │           │  LLM API   │       │  │  │
│  │  │    │  Cloud  │           │ (OpenRouter)│       │  │  │
│  │  │    └─────────┘           └────────────┘       │  │  │
│  │  └─────────────────────────────────────────────────┘  │  │
│  └───────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────┘
```

## 🤖 Supported LLM Providers

| Provider | Default Model | Notes |
|----------|---------------|-------|
| **OpenRouter** | `x-ai/grok-4.1-fast` | Recommended - access to all models |
| OpenAI | `gpt-4o` | Direct API access |
| Anthropic | `claude-sonnet-4-6` | Native Claude API |
| DeepSeek | `deepseek-chat` | Chinese AI models |
| Groq | `llama-3.3-70b-versatile` | Fast inference |
| Custom | User-defined | OpenAI-compatible endpoints |

### Provider Configuration

When creating an instance, you'll be prompted:
```
Selecione o provedor LLM:
  1) OpenRouter (recomendado) - Acesso global a todos os modelos
  2) OpenAI - API direta OpenAI
  3) Anthropic - API direta Claude
  4) DeepSeek - Modelos chineses
  5) Groq - Inference rápida
  6) Personalizado (OpenAI-compatible) - Endpoints locais/customizados
```

## 📱 WhatsApp Audio Support

This fork includes a patched bridge that automatically downloads voice messages:

```typescript
// Patch adds audio message handling in whatsapp.ts
} else if (unwrapped.audioMessage) {
  fallbackContent = '[Voice Message]';
  const audioMime = unwrapped.audioMessage.mimetype ?? 'audio/ogg; codecs=opus';
  const path = await this.downloadMedia(msg, audioMime);
  if (path) {
    mediaPaths.push(path);
    fallbackContent += ` (${path})`;
  }
}
```

The patch is applied automatically during `./xnanobot.sh build` or `./xnanobot.sh rebuild`.

**Disable patch**: Edit `xnanobot.sh` and set:
```bash
PATCH_WHATSAPP_AUDIO=false
```

## 🔧 Configuration

### Script Variables (xnanobot.sh)

```bash
# Toggle WhatsApp audio patch
PATCH_WHATSAPP_AUDIO=true

# These are auto-detected:
AIMANAGER_DIR="$(cd "$(dirname "$0")" && pwd)"
NANOBOT_INSTANCES="${AIMANAGER_DIR}/nanobot-instances"
NANOBOT_SOURCE_DIR="${AIMANAGER_DIR}/nanobot-source"
BACKUP_DIR="${AIMANAGER_DIR}/backups"
```

### Instance Config (config.json)

Each instance has its own `config.json`:
```json
{
  "providers": {
    "openrouter": {
      "apiKey": "sk-or-v1-..."
    }
  },
  "agents": {
    "defaults": {
      "model": "x-ai/grok-4.1-fast",
      "provider": "openrouter",
      "workspace": "/root/.nanobot/workspace"
    }
  },
  "channels": {
    "whatsapp": {
      "enabled": true,
      "allowFrom": ["*"],
      "groupPolicy": "mention"
    }
  }
}
```

## 📁 Git Structure

```
Repository includes:
├── xnanobot.sh          # Main script (version controlled)
├── docs/                # Documentation
└── .gitignore           # Excludes:
                         # - nanobot-source/
                         # - nanobot-instances/*/whatsapp-auth/
                         # - nanobot-instances/*/bridge/node_modules/
                         # - Any .env or API keys
```

**Note**: Instance configs and workspace files ARE tracked in git. API keys in configs should be managed carefully (consider using `.env` files).

## 🐛 Troubleshooting

### Container won't start
```bash
docker compose -f ~/aimanager/nanobot-instances/wa1/docker-compose.yml logs
```

### WhatsApp not connecting
```bash
./xnanobot.sh reconnect wa1
```

### Bridge issues
```bash
./xnanobot.sh upgrade-bridge wa1
```

### Complete reset
```bash
./xnanobot.sh delete wa1
./xnanobot.sh create
```

## 📝 License

MIT

## 🔗 Links

- [Nanobot GitHub](https://github.com/HKUDS/nanobot)
- [Nanobot Documentation](https://docs.nanobot.ai)
