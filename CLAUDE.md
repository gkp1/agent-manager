# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A Bash CLI/TUI (`xnanobot.sh`, "Agent Manager") that builds a patched Docker image of [HKUDS/nanobot](https://github.com/HKUDS/nanobot) and runs each AI agent as its own container, one directory per agent under `nanobot-instances/<name>/`. Everything is shell plus inline Python (for JSON). It is published as an unmaintained study prototype, so keep changes small and keep the README's status notice accurate.

## Commands

Requires Docker 20.10+ with Compose v2, git, `python3`, and Bash 4+ (associative arrays). Linux, or macOS with Homebrew Bash.

```bash
./xnanobot.sh                    # interactive menu (no args)
./xnanobot.sh help               # every CLI command
./xnanobot.sh build              # clone nanobot-source/, checkout pinned commit, patch, docker build -t nanobot
./xnanobot.sh create             # interactive new-instance wizard
./xnanobot.sh start|stop|restart|logs|status|chat|login <name>
```

There is no test suite or linter. To syntax-check after editing:

```bash
for f in xnanobot.sh lib/*.sh scripts/*.sh; do bash -n "$f"; done
```

Functions can be exercised without Docker by sourcing `lib/*.sh` then `scripts/*.sh` (the order `xnanobot.sh` uses), with `NANOBOT_HOME`, `NANOBOT_INSTANCES`, `BACKUP_DIR`, `GLOBAL_CONFIG`, `NANOBOT_SOURCE_DIR` and `NANOBOT_PINNED_COMMIT` pointed at a temp dir. Then call e.g. `create_config_json`, `create_docker_compose`, or pipe input into `create_docker_instance`. Sourcing `xnanobot.sh` itself does not run `main`, but it does point at the repo's real `nanobot-instances/`.

## Architecture

**Single-shell dispatcher.** `xnanobot.sh` sets the path globals, `PATCH_WHATSAPP_AUDIO` and `NANOBOT_PINNED_COMMIT` under `set -euo pipefail`. It then `source`s every `lib/*.sh` followed by every `scripts/*.sh` into one shell and dispatches with the `case` in `main()`.
- `lib/` holds helpers and the LLM config logic. `scripts/` holds the user-facing flows.
- A new command needs a `main()` case, a `show_menu` entry and an `interactive_menu` case (both in `scripts/menu.sh`), and a `show_help` line.
- Interactive menu actions go through `run_action` (`scripts/menu.sh`), which runs them in a subshell with `set -e`. A failing action, including any `return 1` for invalid input, returns to the menu instead of killing the program. Outside the menu, a `return 1` exits the CLI.
- Under `set -u`, use `${1:-}`-style defaults. Prompts that loop must use `read ... || return 1` so EOF can't spin forever.

**JSON config.** All reads and writes use inline `python3`, never `jq`. Writers must use `json_edit FILE CODE NAME=value...` (`lib/config.sh`): CODE edits the dict `c` and reads values from `env['NAME']`. Never interpolate user input (keys, models, IDs) into Python source. Readers still interpolate paths and fixed provider names.

**Image build** (`build_nanobot_image` in `scripts/setup.sh`; `rebuild` calls it):
- Clone `nanobot-source/` (gitignored), then `git checkout -f "$NANOBOT_PINNED_COMMIT"`, which resets earlier patches. Then run `apply_audio_patch`, which edits `bridge/src/whatsapp.ts` through a Python heredoc and is idempotent through a grep guard. Then `docker build`.
- Upstream `main` no longer has `bridge/src/whatsapp.ts`, so the pin is load-bearing.

**Instances** (`scripts/instance.sh`):
- `create_config_json` (`json.dump` from env vars) and `create_docker_compose` (unquoted heredocs) write the files.
- `custom` providers are written as `providers.openai` + `apiBase` with provider `auto`.
- Names are checked by `valid_instance_name`, ports by `valid_port` (`lib/instance.sh`).
- The container is `nanobot-<name>`, and the gateway listens on container port 18790.
- A WhatsApp instance runs the Node bridge and the gateway in one container, with `bridge/` (copied out of the image on first login by `init_whatsapp_bridge`) and `whatsapp-auth/` bind-mounted. Editing an instance's `bridge/src` only affects that instance.
- Connection status comes from grepping `docker logs` for "Connected to WhatsApp".

**LLM settings** (`lib/llm.sh`, `lib/llm_commands.sh`, `lib/menu_llm.sh`):
- A container reads only its own `config.json`.
- `~/.nanobot/global-config.json` holds host-side defaults that reach an instance only when copied in: `instance-reset` uses `llm_instance_apply_global`, and `instance-key-clear` copies the global key.
- `llm_get_effective_*` reports what the container actually uses: the instance value, or nanobot's own default (`NANOBOT_DEFAULT_PROVIDER` / `NANOBOT_DEFAULT_MODEL`). They never fall back to the global config.

## Repo conventions

- Do not add Claude/Anthropic attribution (`Co-Authored-By: Claude…`, "Generated with Claude Code") to commits or PRs in this repo.
- `nanobot-instances/` and `backups/` are gitignored and contain live API keys, WhatsApp sessions and chat memory. Never commit them. `examples/` shows the files `create` writes.
- `docs/roadmap.md` is a historical plan. Its note at the top lists where the code has since diverged.
- On Windows checkouts with `core.autocrlf=true`, the working tree is CRLF. Git normalizes to LF on commit, and scripts must stay LF in the repo.
