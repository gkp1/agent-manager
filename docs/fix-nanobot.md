# Fix: WhatsApp Docker Setup for Multi-Instance nanobot

## Root Cause

Three bugs in the current Docker approach:

1. **Wrong bridge entrypoint**: `docker-compose.yml` runs `node index.js` but the compiled bridge is at `dist/index.js`
2. **Auth data not persisted**: WhatsApp session auth (`~/.nanobot/whatsapp-auth/`) is never mounted as a volume. Each new container loses the session.
3. **Unnecessary `docker cp` complexity**: Copying the bridge out of a login container is fragile and misses auth data.

## Solution

Mount ALL volumes during login. Use pre-built bridge from Docker image to avoid `shutil.rmtree` on bind mounts. No `docker cp`. Ever.

---

## Step 0: Rebuild Docker Image

The nanobot repo was updated (`git pull`) with a critical litellm security fix. The Docker image must be rebuilt.

```bash
cd /home/brewuser/nanobot
docker build -t nanobot .
```

This rebuilds the image with:
- Updated Python dependencies (litellm fix)
- Pre-built WhatsApp bridge at `/app/bridge/dist/index.js`
- Node.js 20 for the bridge runtime

**Verify** the image has the pre-built bridge:
```bash
docker run --rm --entrypoint ls nanobot /app/bridge/dist/
# Should show: index.js, server.js, whatsapp.js, etc.
```

---

## Step 1: New function `init_whatsapp_bridge`

Copy the pre-built bridge from the Docker image to the host. Only needed once per instance (or after `upgrade-bridge`).

```bash
init_whatsapp_bridge() {
    local instance_dir="$1"
    mkdir -p "$instance_dir/bridge"
    docker run --rm \
        -v "$instance_dir/bridge:/root/.nanobot/bridge" \
        --entrypoint sh \
        nanobot -c "cp -a /app/bridge/. /root/.nanobot/bridge/"
}
```

**What this does**:
- Mounts `./bridge` (empty) at `/root/.nanobot/bridge` in container
- Copies contents of `/app/bridge/` (pre-built: `dist/`, `node_modules/`, `package.json`, etc.) into the mount
- Files appear on host at `./bridge/dist/index.js`, `./bridge/node_modules/`, etc.

**Why this is needed**:
- `_ensure_bridge_setup()` checks `if (user_bridge / "dist" / "index.js").exists()` → returns early if true
- If `dist/index.js` doesn't exist, it tries `shutil.rmtree()` on the bind mount → fails with "Device or resource busy"
- Pre-populating `dist/index.js` makes `_ensure_bridge_setup()` skip the rmtree entirely

---

## Step 2: Simplify `whatsapp_login_flow`

Replace the entire current flow (docker run background + monitoring + docker cp) with:

```bash
whatsapp_login_flow() {
    local instance_dir="$1"
    local container_name="$2"  # unused now, kept for signature compat

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
    echo -e "${YELLOW}  1. QR Code vai aparecer abaixo${NC}"
    echo -e "${YELLOW}  2. Abra WhatsApp → Dispositivos vinculados → Vincular dispositivo${NC}"
    echo -e "${YELLOW}  3. Escaneie o QR Code${NC}"
    echo -e "${YELLOW}  4. Quando ver 'Connected', pressione Ctrl+C${NC}"
    echo
    read -p "  Pressione Enter para começar..."

    # Interactive login — all volumes mounted, no docker cp needed
    docker run -it \
        -v "$(pwd)/config.json:/root/.nanobot/config.json" \
        -v "$(pwd)/bridge:/root/.nanobot/bridge" \
        -v "$(pwd)/workspace:/root/.nanobot/workspace" \
        -v "$(pwd)/whatsapp-auth:/root/.nanobot/whatsapp-auth" \
        --entrypoint nanobot \
        nanobot channels login whatsapp

    cd - > /dev/null 2>&1
}
```

**What happens during login**:
1. `_ensure_bridge_setup()` finds `dist/index.js` → returns early (no rmtree, no rebuild)
2. Sets `AUTH_DIR = /root/.nanobot/whatsapp-auth` (mounted to host)
3. Runs `npm start` = `node dist/index.js` → bridge starts on port 3001
4. Bridge shows QR code in terminal
5. User scans with WhatsApp
6. Bridge connects, stores session in `whatsapp-auth/` volume
7. User presses Ctrl+C → container exits
8. Bridge + auth data persist on host volumes

**No docker cp. No background processes. No monitoring. No traps.**

---

## Step 3: Fix `create_docker_compose` for WhatsApp

```bash
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
```

**Key changes from current version**:
- Added `whatsapp-auth` volume
- Entrypoint runs `node dist/index.js` (NOT `node index.js`)
- Bridge starts in background (`&`), gateway in foreground (`exec`)

---

## Step 4: Fix `reconnect_whatsapp`

```bash
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

    # Clear auth to force fresh QR (new account)
    rm -rf whatsapp-auth
    mkdir -p whatsapp-auth

    # Login — bridge already initialized, auth will be fresh
    cd - > /dev/null 2>&1
    whatsapp_login_flow "$instance_dir" "nanobot-login-${instance_name}"

    # Start instance
    cd "$instance_dir"
    docker compose up -d
    cd - > /dev/null 2>&1

    print_success "WhatsApp reconectado para $instance_name!"
}
```

---

## Step 5: Fix `upgrade_whatsapp_bridge`

```bash
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
    init_whatsapp_bridge "$instance_dir"
    mkdir -p "$instance_dir/whatsapp-auth"

    # Login with fresh bridge
    whatsapp_login_flow "$instance_dir" "nanobot-login-${instance_name}"

    # Start instance
    cd "$instance_dir"
    docker compose up -d
    cd - > /dev/null 2>&1

    print_success "Bridge WhatsApp atualizado e instância reiniciada!"
}
```

---

## Step 6: Fix `login-whatsapp` in `manage_instance`

```bash
login-whatsapp)
    print_step "Conectando WhatsApp para $instance_name..."
    docker compose down 2>/dev/null || true
    whatsapp_login_flow "$(pwd)" "nanobot-login-${instance_name}"
    # Auto-start if bridge was initialized
    if [[ -f "$(pwd)/bridge/dist/index.js" ]]; then
        print_step "Iniciando instância..."
        docker compose up -d
        print_success "Instância iniciada!"
    fi
    ;;
```

---

## Step 7: Fix existing wa1 instance

```bash
# Stop existing instance
cd ~/nanobot-instances/wa1
docker compose down

# Fix docker-compose.yml — add whatsapp-auth volume, fix entrypoint
# (write new docker-compose.yml per Step 3)

# Initialize bridge from image
mkdir -p bridge whatsapp-auth
docker run --rm \
    -v "$(pwd)/bridge:/root/.nanobot/bridge" \
    --entrypoint sh \
    nanobot -c "cp -a /app/bridge/. /root/.nanobot/bridge/"

# Re-login
docker run -it \
    -v "$(pwd)/config.json:/root/.nanobot/config.json" \
    -v "$(pwd)/bridge:/root/.nanobot/bridge" \
    -v "$(pwd)/workspace:/root/.nanobot/workspace" \
    -v "$(pwd)/whatsapp-auth:/root/.nanobot/whatsapp-auth" \
    --entrypoint nanobot \
    nanobot channels login whatsapp

# Start
docker compose up -d
```

---

## What Gets Removed

- All `docker cp` logic
- `docker run -d` background approach
- QR code monitoring/polling loops
- Named containers for login
- `trap '' INT` signal hacks
- `docker-compose.login.yml` overlay (if it exists)

## Why This Is Stable

| Scenario | What happens |
|----------|-------------|
| First login | Bridge volume empty → init copies pre-built → `_ensure_bridge_setup()` finds `dist/index.js` → returns early → `npm start` runs → QR shown → auth stored |
| Second login | `dist/index.js` exists → returns early → just re-connects |
| Gateway start | Bridge from volume (`dist/index.js`) + auth from volume → gateway connects to `ws://localhost:3001` immediately |
| Reconnect | Delete auth → fresh QR → new session stored |
| Upgrade bridge | Delete bridge + auth → re-copy from image → re-login |
| Container restart | Bridge + auth persist on volumes → reconnects automatically |
| Multi-instance | Each has own `bridge/` + `whatsapp-auth/` volumes → no conflicts |

## File Inventory After Setup

```
~/nanobot-instances/wa1/
├── config.json            # nanobot config
├── docker-compose.yml     # container definition
├── bridge/                # pre-built bridge from image
│   ├── dist/
│   │   └── index.js       # compiled entry point
│   ├── node_modules/      # npm dependencies
│   ├── package.json
│   └── src/               # TypeScript source (from image)
├── workspace/             # agent workspace
└── whatsapp-auth/         # WhatsApp session data (Baileys)
    └── (session files)
```
