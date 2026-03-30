# 🐈 AI Manager

**AI agents, minus the complexity.**

<img width="435" height="195" alt="image" src="https://github.com/user-attachments/assets/4253fa4e-5dec-43f6-93a4-b0c04ed2f20d" />

<img width="417" height="194" alt="image" src="https://github.com/user-attachments/assets/301d16c5-07a8-40b8-a862-147312051c0e" />


Built on [HKUDS/nanobot](https://github.com/HKUDS/nanobot) — as powerful as OpenClaw, but lighter. Open source. Self-hosted. Actually yours.

AI Manager runs your AI agents in isolated Docker containers. Each agent gets its own sandboxed environment with **no access** to other containers or your host system — only the folders explicitly mounted in each agent's `docker-compose.yml`. Your data, your control.

### The Problem

Setting up AI agents is painful. Multiple tools, conflicting dependencies, manual configuration for each instance. Want 2 agents? Double the headaches.

### The Solution

One script. One folder. Everything handled. Install, build, create, manage — all from a single interactive menu or CLI commands. You focus on your agents, not infrastructure.

## ✨ Features

- **Zero Config Overhead** — Script handles installation, Docker builds, and agent management. You just manage agents.

- **True Docker Isolation** — Each agent runs in its own container with isolated workspace, memory, and sessions. No cross-contamination. What each container can access is defined by bind mounts in its `docker-compose.yml` — nothing else.

- **WhatsApp Audio Patch** — We patch the nanobot bridge on build to natively handle voice messages (`.ogg` downloads). This isn't in vanilla nanobot — we add it automatically.

- **Multi-Provider LLM** — OpenRouter, OpenAI, Anthropic, DeepSeek, Groq, or any OpenAI-compatible endpoint. Configure per-agent, switch anytime.

- **Real-time Agent Status** — See all your agents, their channels, and connection status at a glance in the interactive menu.

- **Multi-Instance Management** — Create, start, stop, monitor multiple isolated agents from one place.

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

### Project Structure

```
~/aimanager/
├── xnanobot.sh              # Main script (that's all you need)
├── nanobot-instances/       # All your agents live here
│   ├── wa1/
│   │   ├── config.json      # Agent config (provider, API keys, channels)
│   │   ├── docker-compose.yml
│   │   ├── bridge/          # WhatsApp bridge (patched for audio)
│   │   ├── workspace/       # Agent memory, sessions, files
│   │   └── whatsapp-auth/   # WhatsApp session data
│   └── wa2/                 # Each agent is independent
├── nanobot-source/          # Nanobot source (auto-managed for builds)
└── docs/
```

### Docker Isolation Model

Each agent runs in its own Docker container. What it can access is **strictly defined** by bind mounts in its `docker-compose.yml`:

```yaml
volumes:
  - ./config.json:/root/.nanobot/config.json    # This agent's config
  - ./workspace:/root/.nanobot/workspace        # This agent's memory
  - ./bridge:/root/.nanobot/bridge              # This agent's bridge
  - ./whatsapp-auth:/root/.nanobot/whatsapp-auth  # This agent's session
```

**What this means:**
- Agent `wa1` can **only** access `wa1`'s folders
- Agent `wa2` can **only** access `wa2`'s folders
- No agent can see, modify, or access another agent's data
- No agent can access your host filesystem beyond what's explicitly mounted
- Containers can't talk to each other unless you configure it

### How It Works

```
┌─────────────────────────────────────────────────────────────────┐
│                          HOST                                   │
│                                                                 │
│  ┌────────────────────────────────────────────────────────────┐ │
│  │                   Container: wa1                           │ │
│  │  ┌──────────────┐    WebSocket    ┌──────────────────┐    │ │
│  │  │    Bridge    │◄───────────────►│     Gateway      │    │ │
│  │  │   (Node.js)  │    port 3001    │    (Python)      │    │ │
│  │  │              │                 │   port 18790     │    │ │
│  │  └──────┬───────┘                 └────────┬─────────┘    │ │
│  │         │                                  │              │ │
│  │         ▼                                  ▼              │ │
│  │   ┌──────────┐                    ┌──────────────┐        │ │
│  │   │WhatsApp  │                    │  LLM API     │        │ │
│  │   │  Cloud   │                    │ (OpenRouter) │        │ │
│  │   └──────────┘                    └──────────────┘        │ │
│  │                                                            │ │
│  │   Volumes: ./config.json  ./workspace  ./bridge           │ │
│  └────────────────────────────────────────────────────────────┘ │
│                          ⬆️ separated ⬆️                         │
│  ┌────────────────────────────────────────────────────────────┐ │
│  │                   Container: wa2                           │ │
│  │   (Same structure, completely isolated)                    │ │
│  │   Volumes: ./config.json  ./workspace  ./bridge           │ │
│  └────────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────────┘
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
