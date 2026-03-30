# AI Manager Roadmap

## Project Status
- **Current**: Single monolithic script (xnanobot.sh - 2412 lines)
- **Goal**: Modular, maintainable structure with enhanced LLM management

---

## Part 1: Refactoring Plan

### Proposed Directory Structure

```
aimanager/
├── xnanobot.sh                 # Main entry point ( dispatcher only )
├── lib/
│   ├── colors.sh              # Color constants and print helpers
│   ├── config.sh              # Directory paths, default values
│   ├── docker.sh              # Docker helper functions
│   ├── instance.sh            # Instance discovery, validation
│   ├── llm.sh                 # LLM provider/model utilities
│   └── channel.sh             # Channel detection/validation
├── scripts/
│   ├── setup/
│   │   ├── prerequisites.sh   # check_prerequisites
│   │   ├── build-image.sh    # build_nanobot_image
│   │   └── init-whatsapp.sh  # whatsapp_login_flow
│   ├── instance/
│   │   ├── create.sh         # create_docker_instance
│   │   ├── create-multi.sh   # create_multi_instances
│   │   ├── list.sh           # list_instances
│   │   ├── delete.sh         # delete_instance
│   │   └── config.sh         # configure_instance_menu
│   ├── control/
│   │   ├── start.sh          # Start instance(s)
│   │   ├── stop.sh           # Stop instance(s)
│   │   ├── restart.sh        # Restart instance(s)
│   │   ├── logs.sh           # View logs
│   │   └── status.sh         # Status/chat
│   ├── whatsapp/
│   │   ├── login.sh          # whatsapp_login_flow
│   │   ├── reconnect.sh      # reconnect_whatsapp
│   │   ├── upgrade-bridge.sh # upgrade_whatsapp_bridge
│   │   └── configure.sh       # configure_whatsapp_instance
│   └── system/
│       ├── rebuild.sh         # rebuild_docker_image
│       └── update.sh          # update_nanobot
└── bin/
    └── xnanobot               # Symlink to xnanobot.sh
```

### Module Responsibilities

| Module | Functions |
|--------|-----------|
| `lib/colors.sh` | `print_header`, `print_info`, `print_success`, `print_warning`, `print_error`, `print_step` |
| `lib/config.sh` | Directory paths, default vars, OS detection |
| `lib/docker.sh` | Docker ps checks, container status helpers |
| `lib/instance.sh` | `get_instance_channel`, instance discovery, validation |
| `lib/llm.sh` | Provider/model lists, API key helpers, global config |
| `lib/channel.sh` | Channel validation, config parsing |
| `scripts/instance/create.sh` | Interactive instance creation |
| `scripts/instance/config.sh` | Full instance configuration menu |
| `scripts/control/*.sh` | Start/stop/restart/logs/status per instance or all |

### Migration Strategy

1. **Phase 1**: Extract `lib/` (colors, config, docker, instance, llm, channel)
2. **Phase 2**: Extract `scripts/` subcommands
3. **Phase 3**: Slim down `xnanobot.sh` to dispatcher only
4. **Phase 4**: Testing - all commands work identically

### Backward Compatibility

- Keep CLI interface identical (`./xnanobot.sh start wa1`, etc.)
- All existing commands must work without changes

---

## Part 2: LLM Provider/Model Management Feature

### Feature: Global + Instance-Level Override with API Keys

**Goal**: Set a default LLM for all instances, but allow any instance to use a different provider/model/API key.

---

### How Override Works

**Core Principle**: Instance config ALWAYS takes precedence over global config. Global is just a default that instances inherit only when they don't have their own settings.

**Resolution Order** (for each instance at runtime):
```
1. Check instance config.json → has provider/model set?
   YES → Use instance-specific provider + model + API key
   NO  → Check global config
         YES → Use global provider + model + API key
         NO  → Use hardcoded defaults
```

**Key Behavior**:
- Global config is a "fallback" - it's used only when instance has NO specific config
- Setting a custom model for ONE instance does NOT affect other instances
- Setting a global config does NOT automatically apply to existing instances (they keep their config)
- API keys can be stored at global level OR per-instance

---

### API Key Configuration Flow

**Key Requirement**: When changing provider or model, always ask about API key:
- Option to keep current API key
- Option to set new API key
- Clear indication where API key is stored (global vs instance)

**Three Storage Scenarios**:

| Scenario | Where API Key Stored | Instance Uses |
|----------|---------------------|---------------|
| 1 | Global only | Global API key |
| 2 | Instance only | Instance API key |
| 3 | Both (different keys) | Instance API key (override) |

---

### Data Model

#### Global Config File: `~/.nanobot/global-config.json`

```json
{
  "global": {
    "provider": "openrouter",
    "model": "x-ai/grok-4.1-fast"
  },
  "providers": {
    "openrouter": { "apiKey": "sk-or-v1-..." },
    "openai": { "apiKey": "sk-..." },
    "anthropic": { "apiKey": "sk-ant-..." },
    "deepseek": { "apiKey": "sk-..." },
    "groq": { "apiKey": "gsk_..." }
  }
}
```

#### Instance Config: `nanobot-instances/{name}/config.json`

```json
{
  "agents": {
    "defaults": {
      "model": "anthropic/claude-sonnet-4-6",
      "provider": "openrouter"
    }
  },
  "providers": {
    "openrouter": { "apiKey": "sk-or-v1-..." }  // Optional: instance-specific key
  },
  "channels": { ... }
}
```

**Instance uses global API key** (no providers section):
```json
{
  "agents": { "defaults": { "model": "...", "provider": "..." } },
  "channels": { "whatsapp": { "enabled": true } }
}
```

**Instance has its own API key** (override):
```json
{
  "agents": { "defaults": { "model": "...", "provider": "..." } },
  "providers": { "openrouter": { "apiKey": "sk-or-v1-instance-specific" } },
  "channels": { ... }
}
```

---

### Key Functions in lib/llm.sh

```bash
# Get effective config for an instance (resolves global → instance)
llm_get_effective_config() {
  local instance_name="$1"
  # Returns: provider model source
  # 1. Check instance config
  # 2. If empty, check global config
  # 3. If empty, return defaults
}

# Get API key for instance (checks instance first, then global)
llm_get_api_key() {
  local instance_name="$1"
  local provider="$2"
  # 1. Check instance config for provider.apiKey
  # 2. If empty, check global config
  # 3. Return key or empty
}

# Check if instance has custom config (vs using global)
llm_instance_has_override() {
  local instance_name="$1"
  # Returns 0 if instance has explicit provider/model
}

# Check if instance has its own API key (vs using global)
llm_instance_has_key_override() {
  local instance_name="$1"
  local provider="$2"
  # Returns 0 if instance has its own API key for provider
}
```

---

### CLI Commands

| Command | Description |
|---------|-------------|
| `./xnanobot.sh global-set` | Set global provider + model + API key (interactive) |
| `./xnanobot.sh global-provider` | Set global provider (then asks for API key) |
| `./xnanobot.sh global-model` | Set global model only |
| `./xnanobot.sh global-key` | Set global API key for a provider |
| `./xnanobot.sh global-show` | Show current global config |
| `./xnanobot.sh global-clear` | Clear global config |
| `./xnanobot.sh instance-model <name>` | Set model for instance (then asks for key) |
| `./xnanobot.sh instance-provider <name>` | Set provider for instance (then asks for key) |
| `./xnanobot.sh instance-key <name>` | Set API key for instance (override global) |
| `./xnanobot.sh instance-key-clear <name>` | Clear instance API key → use global |
| `./xnanobot.sh instance-reset <name>` | Remove instance config → use global |
| `./xnanobot.sh instance-show <name>` | Show effective config + API key source |
| `./xnanobot.sh configure` | Enhanced menu with global/instance options |

---

### Menu Integration

```
[25] Global LLM Settings
    ├─ View global config
    ├─ Set global provider (+ optional new API key)
    ├─ Set global model
    ├─ Set global API key for provider
    └─ Clear global config

[26] Instance LLM Settings
    ├─ wa1: openrouter / grok-4.1-fast [uses global key]
    ├─ wa2: openrouter / grok-4.1-fast [uses global key]
    ├─ wa3: anthropic / claude-sonnet-4-6 [INSTANCE KEY]
    └─ Select instance:
        ├─ Change model (+ optional new key)
        ├─ Change provider (+ optional new key)
        ├─ Set instance API key (override global)
        ├─ Clear instance API key (use global)
        └─ Reset all to global
```

---

### Interactive API Key Flow

**When setting provider or model, always prompt:**

```
$ ./xnanobot.sh instance-provider wa1

Instance: wa1

Select provider:
  1) OpenRouter (current: openrouter)
  2) OpenAI
  3) Anthropic
  4) DeepSeek
  5) Groq

Choose [1]: 3

Provider selected: anthropic

┌─────────────────────────────────────────┐
│ API Key Configuration                   │
├─────────────────────────────────────────┤
│ Current: No API key set for anthropic   │
│                                         │
│ [1] Enter new API key                   │
│ [2] Use global anthropic API key       │
│ [3] Skip (set provider only)            │
└─────────────────────────────────────────┘

Choose [1-3]: 1

Enter Anthropic API key (sk-ant-...): sk-ant-xxx

✓ Instance wa1:
  Provider: anthropic
  Model: (inherited from global)
  API Key: INSTANCE (override)
```

**Same flow for global:**

```
$ ./xnanobot.sh global-provider

Select provider:
  1) OpenRouter
  2) OpenAI
  ...

Choose [1]: 2

┌─────────────────────────────────────────┐
│ API Key Configuration                   │
├─────────────────────────────────────────┤
│ Current OpenAI key: sk-...abcd (set)   │
│                                         │
│ [1] Keep current API key                │
│ [2] Enter new API key                   │
│ [3] Clear API key                       │
└─────────────────────────────────────────┘

Choose [1-3]: 2

Enter OpenAI API key (sk-...): sk-newkey

✓ Global provider: openai
✓ API key updated
```

---

### UI Examples

#### Set Global (one command does all)
```
$ ./xnanobot.sh global-set

Select provider:
  1) OpenRouter (recommended)
  2) OpenAI
  3) Anthropic
  4) DeepSeek
  5) Groq
  6) Custom

Choose [1]: 1

┌─────────────────────────────────────────┐
│ API Key Configuration                   │
├─────────────────────────────────────────┤
│ Current: No API key                     │
│                                         │
│ [1] Enter new API key                    │
│ [2] Skip (set provider only)            │
└─────────────────────────────────────────┘

Choose [1-2]: 1

Enter OpenRouter API key (sk-or-v1-...): sk-or-v1-xxx

Select model:
  1) x-ai/grok-4.1-fast
  2) anthropic/claude-sonnet-4-6
  ...

Choose [1]: 1

✓ Global config saved:
  Provider: openrouter
  Model: x-ai/grok-4.1-fast
  API Key: GLOBAL
```

#### Set Instance Override with API Key
```
$ ./xnanobot.sh instance-model wa1

Instance: wa1
Current: openrouter / grok-4.1-fast [uses global key]

This instance currently INHERITS global config.
Set a custom model to override global.

Select model:
  1) anthropic/claude-sonnet-4-6
  2) anthropic/claude-opus-4-5
  ...

Choose [1]: 2

┌─────────────────────────────────────────┐
│ API Key Configuration for claude-opus   │
├─────────────────────────────────────────┤
│ Global anthropic key: sk-ant-xxx (set) │
│                                         │
│ [1] Use global API key                  │
│ [2] Enter new API key for this instance │
│ [3] Skip (no API key - may fail)       │
└─────────────────────────────────────────┘

Choose [1-3]: 2

Enter instance API key: sk-ant-instance

✓ Instance wa1:
  Model: anthropic/claude-opus-4-5
  API Key: INSTANCE (override)
✓ Run ./xnanobot.sh instance-reset wa1 to revert to global
```

#### Show Effective Config (with key source)
```
$ ./xnanobot.sh instance-show wa1

Instance: wa1
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Source: CUSTOM (override)
Provider: openrouter
Model: anthropic/claude-opus-4-5
API Key: INSTANCE (overrides global)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

#### Clear Instance API Key (revert to global)
```
$ ./xnanobot.sh instance-key-clear wa1

Instance: wa1
Current: anthropic with instance-specific API key

Clear instance API key? Will use global key instead.
Confirm? (y/n): y

✓ Instance wa1 now uses global API key
```

---

## Implementation Phases

| Phase | Task |
|-------|------|
| P1 | Add `lib/llm.sh` with global config read/write |
| P2 | Add API key helper functions (get/set/clear) |
| P3 | Add `global-set` interactive command with key flow |
| P4 | Add instance override commands with key flow |
| P5 | Add `instance-key` and `instance-key-clear` |
| P6 | Add `instance-show` with API key source |
| P7 | Add `instance-reset` |
| P8 | Enhance interactive menu |
| P9 | Modify instance creation to use global defaults |

---

## Priority Order

| Priority | Task |
|----------|------|
| P0 | Fix 401 error (API key issue) |
| P1 | Extract lib/ modules |
| P2 | Add lib/llm.sh with global config |
| P3 | Add global-set command with API key flow |
| P4 | Add instance override commands with API key flow |
| P5 | Add instance-key, instance-key-clear |
| P6 | Add instance-show with key source |
| P7 | Add instance-reset |
| P8 | Extract scripts/ subcommands |
| P9 | Slim down main dispatcher |

---

## Analysis & Fixes

### Issue 1: API Key Not Addressed in Original Plan
**Fix**: Added full API key flow - always prompt when changing provider/model

### Issue 2: No Way to Keep Current Key
**Fix**: Added menu options [1] Keep current, [2] Enter new, [3] Clear

### Issue 3: Instance API Key Override Unclear
**Fix**: Added `instance-key` command to set instance-specific API key
**Fix**: Added `instance-key-clear` to revert to global key

### Issue 4: Unclear Where API Key Comes From
**Fix**: Added `instance-show` to display API key source (GLOBAL vs INSTANCE)

### Issue 5: Missing `instance-provider` Command
**Fix**: Added `instance-provider` alongside `instance-model`

### Issue 6: No Way to Set API Key Without Changing Provider/Model
**Fix**: Added `global-key` and `instance-key` standalone commands

---

## Notes

- **Backward compatible**: Existing configs work unchanged
- **Global is optional**: Can be empty → uses hardcoded defaults
- **Instance wins**: Always check instance config first for provider, model, AND API key
- **API key storage**: Can be global-only, instance-only, or both
- **Reset is safe**: `instance-reset` removes all instance overrides (provider, model, API key)
- **Key-clear**: `instance-key-clear` only removes API key override, keeps provider/model
