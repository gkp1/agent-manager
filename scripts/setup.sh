#!/usr/bin/env bash
# scripts/setup.sh - Setup and prerequisites functions

check_dependencies() {
    print_step "Checking dependencies..."
    local missing=()
    
    if ! check_command docker; then
        missing+=("docker")
        print_warning "Docker not found. Docker is required for Docker instances."
    fi
    
    if ! docker compose version &> /dev/null; then
        missing+=("docker-compose")
        print_warning "Docker Compose (v2+) not found."
    fi
    
    if command -v docker &> /dev/null; then
        if ! docker info &> /dev/null; then
            print_warning "Docker is not running. Please start the Docker service."
        fi
    fi
    
    if ! check_command git; then
        missing+=("git")
        print_warning "Git not found."
    fi
    
    if ! check_command python3 && ! check_command python; then
        missing+=("python3")
        print_warning "Python not found."
    fi
    
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

check_prerequisites() {
    print_step "Checking prerequisites..."
    
    local docker_version
    if command -v docker &> /dev/null; then
        docker_version=$(docker --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+')
        print_info "Docker version: $docker_version"
    else
        print_error "Docker not found."
        return 1
    fi
    
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

apply_audio_patch() {
    local repo_dir="$1"
    local whatsapp_file="${repo_dir}/bridge/src/whatsapp.ts"
    
    if [[ ! -f "$whatsapp_file" ]]; then
        print_error "whatsapp.ts file not found: $whatsapp_file"
        return 1
    fi
    
    if grep -q "unwrapped.audioMessage" "$whatsapp_file"; then
        print_info "Audio patch already applied."
        return 0
    fi
    
    print_step "Applying audio patch WhatsApp..."
    
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

lines = content.split('\n')
new_lines = []
replaced = False

for i, line in enumerate(lines):
    if not replaced and line.strip() == '}' and i > 0:
        if i > 0 and 'mediaPaths.push(path)' in lines[i-1]:
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
    
    [[ $? -eq 0 ]]
}

build_nanobot_image() {
    print_step "Building Docker image for nanobot..."
    
    if [[ ! -d "$NANOBOT_SOURCE_DIR" ]]; then
        print_step "Cloning nanobot repository..."
        git clone "$NANOBOT_REPO" "$NANOBOT_SOURCE_DIR"
    fi

    # The patches and the bridge layout target this upstream commit. The forced
    # checkout also resets files patched by a previous build before re-patching.
    print_step "Checking out nanobot $NANOBOT_PINNED_COMMIT (local changes in nanobot-source/ are discarded)..."
    if ! git -C "$NANOBOT_SOURCE_DIR" cat-file -e "${NANOBOT_PINNED_COMMIT}^{commit}" 2>/dev/null; then
        git -C "$NANOBOT_SOURCE_DIR" fetch origin
    fi
    git -C "$NANOBOT_SOURCE_DIR" checkout -q -f "$NANOBOT_PINNED_COMMIT"

    if [[ "$PATCH_WHATSAPP_AUDIO" == "true" ]]; then
        apply_audio_patch "$NANOBOT_SOURCE_DIR"
    fi

    print_step "Executing: docker build -t nanobot ."
    if ! (cd "$NANOBOT_SOURCE_DIR" && docker build -t nanobot .); then
        print_error "Docker build failed."
        return 1
    fi

    print_success "Docker image built successfully!"
    return 0
}

setup_guide_flow() {
    print_header
    print_step "Full setup..."
    echo
    echo "This command runs the full setup:"
    echo "1. Check prerequisites - Docker 20.10+, Docker Compose 2.0+"
    echo "2. Build the nanobot Docker image (pinned to $NANOBOT_PINNED_COMMIT)"
    echo "3. Create isolated Docker instance"
    echo
    read -p "Continue? (y/n): " confirm
    
    if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
        print_info "Setup cancelled."
        return 0
    fi
    
    if ! check_prerequisites; then
        print_error "Prerequisites not met. Install Docker and Docker Compose."
        return 1
    fi
    
    if ! build_nanobot_image; then
        print_error "Failed to build Docker image."
        return 1
    fi
    
    echo
    print_step "Now let us create your first Docker instance..."
    create_docker_instance
}

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
