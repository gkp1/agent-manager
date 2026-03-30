# 🐈 AI Manager

<img width="2750" height="1536" alt="AI Manager" src="https://github.com/user-attachments/assets/34af13a6-e745-462f-a501-a90b7bfbdf95" />

Built on [HKUDS/nanobot](https://github.com/HKUDS/nanobot) — as powerful as OpenClaw, but lighter. Open source. Self-hosted. Actually yours.

AI Manager runs your AI agents in isolated Docker containers. Each agent gets its own sandboxed environment with **no access** to other containers or your host system — only the folders explicitly mounted in each agent's `docker-compose.yml`. Your data, your control.

## 📁 Multi-Agent Folder Structure Example

```
~/aimanager/
├── xnanobot.sh                          # Main script
├── nanobot-instances/                   # All agents live here
│   ├── wa1/                             # Agent 1: WhatsApp
│   │   ├── config.json                  # wa1's LLM + channel config
│   │   ├── docker-compose.yml           # wa1's isolated container
│   │   ├── bridge/                     # wa1's WhatsApp bridge
│   │   │   ├── src/
│   │   │   ├── dist/
│   │   │   └── package.json
│   │   ├── workspace/                   # wa1's memory & files
│   │   │   ├── AGENTS.md
│   │   │   ├── TOOLS.md
│   │   │   ├── USER.md
│   │   │   ├── memory/
│   │   │   │   ├── MEMORY.md
│   │   │   │   └── HISTORY.md
│   │   │   └── heartbeat.json
│   │   └── whatsapp-auth/              # wa1's WhatsApp session
│   │       ├── creds.json
│   │       └── session.json
│   │
│   ├── wa2/                             # Agent 2: WhatsApp (different number)
│   │   ├── config.json                  # Can use DIFFERENT LLM provider!
│   │   ├── docker-compose.yml
│   │   ├── bridge/
│   │   ├── workspace/                    # wa2's SEPARATE memory
│   │   └── whatsapp-auth/               # wa2's SEPARATE session
│   │
│   ├── tg1/                             # Agent 3: Telegram
│   │   ├── config.json                  # Telegram bot config
│   │   ├── docker-compose.yml
│   │   └── workspace/
│   │       ├── AGENTS.md
│   │       ├── TOOLS.md
│   │       └── memory/
│   │
│   └── discord1/                        # Agent 4: Discord
│       ├── config.json
│       ├── docker-compose.yml
│       └── workspace/
│
├── nanobot-source/                      # Nanobot source code
│   ├── bridge/
│   ├── src/
│   └── Dockerfile
└── backups/                             # Instance backups
    └── wa1_20240330_120000/
        ├── config.json
        └── docker-compose.yml
```

**Key Points:**
- Each agent is fully isolated — `wa1` cannot access `wa2`'s data
- Different agents can use different LLM providers/models
- Global LLM settings can be applied to all agents, or each can have its own
- WhatsApp, Telegram, Discord, Feishu, Slack, Matrix, Email — mix and match
- Each workspace has its own memory, history, and state

### Workspace Contents (per agent)

Each agent's `workspace/` folder contains:
```
workspace/
├── AGENTS.md         # Agent personality & instructions
├── TOOLS.md          # Available tools for this agent
├── USER.md           # User context
├── HEARTBEAT.md       # Heartbeat config
├── memory/
│   ├── MEMORY.md     # Long-term memory
│   └── HISTORY.md    # Conversation history
└── heartbeat.json    # Heartbeat state
```

### Global LLM Configuration

You can set a global LLM provider/model that all agents inherit, or override per-agent:

```
~/.nanobot/
└── global-config.json        # Global settings (optional)
    ├── global:
    │   ├── provider: "openrouter"
    │   └── model: "x-ai/grok-4.1-fast"
    └── providers:
        ├── openrouter: { apiKey: "sk-or-v1-..." }
        └── anthropic: { apiKey: "sk-ant-..." }
```

Commands:
```bash
./xnanobot.sh global-set           # Set global provider + model + API key
./xnanobot.sh global-show         # Show global config
./xnanobot.sh instance-model wa1  # Override for specific agent
./xnanobot.sh instance-reset wa1   # Reset wa1 to use global
```

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

## Screenshots


<img width="417" height="583" alt="sscrenshot" src="https://github.com/user-attachments/assets/3380be65-ee7d-4a29-8e9e-4cf262644e2d" />

<img width="417" height="194" alt="screenshot" src="https://github.com/user-attachments/assets/301d16c5-07a8-40b8-a862-147312051c0e" />


## Instance creation example

<img width="421" height="571" alt="Tabby_Kbcecvw6gE" src="https://github.com/user-attachments/assets/c1c64147-e66f-49b2-94a4-c594872f0903" />


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
