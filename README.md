# Agent Manager

A Bash CLI and interactive menu for running several [nanobot](https://github.com/HKUDS/nanobot) AI agents side by side, each in its own Docker container with its own config, memory and chat channel.

> [!NOTE]
> **Study prototype, not actively maintained.** It was built and used on Linux with Docker, against nanobot commit [`63d646f`](https://github.com/HKUDS/nanobot/commit/63d646f) (March 2026), which the build pins. It is not being developed further. Use it as a reference or a starting point.

## Screenshots

| Main menu | Status view |
|:---------:|:-----------:|
| <img width="417" height="583" alt="Main menu" src="https://github.com/user-attachments/assets/3380be65-ee7d-4a29-8e9e-4cf262644e2d" /> | <img width="417" height="194" alt="Agent status" src="https://github.com/user-attachments/assets/301d16c5-07a8-40b8-a862-147312051c0e" /> |

**Creating an instance:**

<img width="421" height="571" alt="Instance creation" src="https://github.com/user-attachments/assets/c1c64147-e66f-49b2-94a4-c594872f0903" />

## What it does

- **Builds a patched nanobot image.** It clones nanobot at the pinned commit and patches the WhatsApp bridge so voice messages are downloaded like images and documents. Vanilla nanobot only tags them as `[Voice Message]`. Then it builds one `nanobot` image that every agent uses.
- **Runs one container per agent.** Each agent has a directory under `nanobot-instances/<name>/` and a container named `nanobot-<name>`. The container only sees the files mounted from that directory.
- **Supports these channels:** WhatsApp (with a QR-code login flow), Telegram, Discord, Feishu, Slack, Matrix and Email.
- **Supports these LLM providers:** OpenRouter, OpenAI, Anthropic, DeepSeek, Groq, or any OpenAI-compatible endpoint, configured per agent. You can save global defaults and copy them into agents.
- **Works as an interactive menu or as CLI commands.** Every action is available both ways.

## Requirements

- Linux, or macOS with Bash 4+ (`brew install bash`; macOS ships Bash 3.2). On Windows, use WSL.
- Docker 20.10+ with Docker Compose v2
- Git
- Python 3 (used to read and edit the JSON configs)

## Quick start

```bash
git clone https://github.com/gkp1/agent-manager.git
cd agent-manager
chmod +x xnanobot.sh

./xnanobot.sh          # interactive menu; [1] Setup All runs check → build → create

# or step by step
./xnanobot.sh check    # Docker and Compose versions
./xnanobot.sh build    # clone nanobot into nanobot-source/, patch it, docker build
./xnanobot.sh create   # name, channel, provider, API key, model, port, allowed user

# optional shell alias
echo "alias xnano='bash $(pwd)/xnanobot.sh'" >> ~/.bashrc && source ~/.bashrc
```

### Example: a WhatsApp agent

```bash
./xnanobot.sh create      # name: wa1, channel: whatsapp, port: 18791
./xnanobot.sh login wa1   # scan the QR code: WhatsApp → Linked devices → Link a device
./xnanobot.sh start wa1
./xnanobot.sh logs wa1    # wait for "Connected to WhatsApp"
```

## Commands

Run `./xnanobot.sh help` for the full list.

| Command | Description |
|---|---|
| `setup-guide` | Full setup: check prerequisites, build the image, create the first instance |
| `check` / `build` / `rebuild` | Check Docker, build the patched image (`rebuild` does the same) |
| `create` / `create-multi` | Create one instance, or several with a name prefix and consecutive ports (fill in their `allowFrom` afterwards) |
| `list` / `configure` / `delete [name]` | List instances, edit `allowFrom` / model / provider, delete an instance (offers to back up its config first) |
| `start` / `stop` / `restart` / `logs` / `status` / `chat` `<name>` | Control one instance. `chat` opens a terminal chat with the agent |
| `start-all` / `stop-all` / `restart-all` / `update-all` | The same for every instance. `update-all` recreates containers after a rebuild |
| `login` / `reconnect` / `upgrade-bridge` / `configure-wa` `<name>` | WhatsApp: link with a QR code, re-link, refresh the bridge from the image (also re-links), edit settings |
| `global-set` / `global-provider` / `global-model` / `global-key` / `global-show` / `global-clear` | Global LLM defaults (see below) |
| `instance-show` / `instance-model` / `instance-provider` / `instance-key` `<name>` | Show or change one instance's LLM settings |
| `instance-reset` / `instance-key-clear` `<name>` | Copy the global provider, model and key (or just the key) into an instance |

## How it works

### Layout

```
agent-manager/
├── xnanobot.sh            # entry point: sets paths, sources lib/ and scripts/, dispatches commands
├── lib/                   # helpers: output, Docker, instances, channels, LLM config and menus
├── scripts/               # flows: setup and build, instances, control, WhatsApp, interactive menu
├── examples/              # a config.json and docker-compose.yml as `create` writes them
├── docs/roadmap.md        # original refactoring and LLM-settings plan (historical)
├── nanobot-source/        # created by `build`, ignored by git
├── nanobot-instances/     # one directory per agent, ignored by git
│   └── wa1/
│       ├── config.json          # provider, API key, model, channel settings
│       ├── docker-compose.yml   # this agent's container, port and mounts
│       ├── workspace/           # nanobot's prompt files (AGENTS.md, SOUL.md, USER.md, …) and memory
│       ├── bridge/              # WhatsApp only: Node.js bridge, copied from the image on first login
│       └── whatsapp-auth/       # WhatsApp only: linked-device session
└── backups/               # config copies made when an instance is deleted, ignored by git
```

### Isolation

Each instance is its own Compose project, and its container only sees what its `docker-compose.yml` mounts:

```yaml
volumes:
  - ./config.json:/root/.nanobot/config.json
  - ./workspace:/root/.nanobot/workspace
  - ./bridge:/root/.nanobot/bridge                 # WhatsApp only
  - ./whatsapp-auth:/root/.nanobot/whatsapp-auth   # WhatsApp only
```

One agent can't read another agent's config, memory or WhatsApp session, and none of them see the rest of the host filesystem. Because each instance is a separate Compose project, the containers are also on separate Docker networks.

For WhatsApp, the Node.js bridge and the Python gateway run in the same container:

```
┌──────────────────────── container nanobot-wa1 ────────────────────────┐
│                                                                        │
│   WhatsApp ◄──► Bridge (Node.js, Baileys) ◄─ ws :3001 ─► Gateway ◄──► LLM API
│                                                     (Python, :18790)   │
│                                                                        │
│   mounts: config.json  workspace/  bridge/  whatsapp-auth/             │
└────────────────────────────────────────────────────────────────────────┘
        host port (e.g. 18791) → container port 18790
```

### Build

`build` clones nanobot into `nanobot-source/` and force-checks out the pinned commit, which also discards patches from earlier builds. It then applies the WhatsApp audio patch and runs `docker build -t nanobot .`. Recent upstream nanobot no longer has the bridge layout these scripts rely on, so the pin is required. Change `NANOBOT_PINNED_COMMIT` in `xnanobot.sh` only if you are ready to adapt the patch.

## Configuration

### Instance config

`nanobot-instances/<name>/config.json` is the only LLM and channel config a container reads ([example](examples/config.example.json)):

```json
{
  "providers": { "openrouter": { "apiKey": "sk-or-v1-..." } },
  "agents": {
    "defaults": {
      "model": "moonshotai/kimi-k2.5",
      "provider": "openrouter",
      "workspace": "/root/.nanobot/workspace"
    }
  },
  "channels": {
    "whatsapp": { "enabled": true, "allowFrom": ["+5511999999999"] }
  }
}
```

- `allowFrom` lists who may talk to the agent. An empty list denies everyone, and `["*"]` allows anyone who finds the number or bot. That lets anyone use your API credits, so prefer explicit IDs.
- `groupPolicy` (WhatsApp) is `open` by default, which answers every group message from allowed senders. Set it to `mention` with `configure-wa` to answer only when mentioned.
- Restart the instance after editing `config.json` by hand. The menus offer a restart after they change it.

### Global LLM defaults

`global-set` and the other `global-*` commands save a provider, model and API keys in `~/.nanobot/global-config.json` on the host. Containers never read this file. The defaults reach an instance only when you copy them in:

- `instance-reset <name>` copies the global provider, model and that provider's key into the instance's `config.json`.
- `instance-key-clear <name>` replaces the instance's key with the global one. If no global key is set, it asks before leaving the instance without a key.

### Script settings

At the top of `xnanobot.sh`:

```bash
PATCH_WHATSAPP_AUDIO=true          # apply the voice-message patch during build
NANOBOT_PINNED_COMMIT="63d646f"    # upstream nanobot commit to build
```

## Supported LLM providers

Model lists are as of March 2026. You can always type any model name with "Other model".

| Provider | Default model |
|---|---|
| OpenRouter | `moonshotai/kimi-k2.5` |
| OpenAI | `gpt-4o` |
| Anthropic | `claude-sonnet-4-6` |
| DeepSeek | `deepseek-chat` |
| Groq | `llama-3.3-70b-versatile` |
| Custom (OpenAI-compatible) | your endpoint's model; stored as `providers.openai` with an `apiBase` |

## WhatsApp voice messages

The patch adds an `audioMessage` branch to the bridge's media handling, so voice notes are saved and passed to the agent like other media:

```typescript
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

Transcribing the audio is up to the agent and its tools.

## Known limitations

- **API keys are stored in plain text** in each `config.json` and in `~/.nanobot/global-config.json`. `nanobot-instances/` and `backups/` are git-ignored for this reason.
- **Containers run as root** (the upstream image's default).
- **Linux, or macOS with Bash 4+.** The scripts use Bash 4 features (associative arrays) and an interactive `docker run -it` for the WhatsApp login.
- **No automated tests.** The final cleanup was checked with `bash -n` and by running the config, build and menu functions against throwaway directories with Docker stubbed out. It was not re-run end to end with Docker.
- **Upstream is pinned** to a March 2026 commit, so newer nanobot features aren't available.

## Troubleshooting

```bash
./xnanobot.sh logs wa1             # container logs (starts the instance if it isn't running)
./xnanobot.sh status wa1           # nanobot's own status command
./xnanobot.sh reconnect wa1        # WhatsApp disconnected: clear the session and scan again
./xnanobot.sh upgrade-bridge wa1   # bridge errors after a rebuild: copy the bridge from the new image and re-link
```

If a container won't start, check `docker compose logs` in `nanobot-instances/<name>/`.

## Background

This started as a single ~2,400-line script for running nanobot agents on WhatsApp. It was later split into `lib/` and `scripts/` and gained per-instance LLM settings, as described in [docs/roadmap.md](docs/roadmap.md).

## License

[MIT](LICENSE). nanobot itself is a separate project by [HKUDS](https://github.com/HKUDS/nanobot) under its own license.
