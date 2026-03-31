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

apply_vector_memory_patch() {
    local repo_dir="$1"
    local vector_file="${repo_dir}/nanobot/vector_memory.py"
    local pyproject="${repo_dir}/pyproject.toml"
    local memory_file="${repo_dir}/nanobot/agent/memory.py"
    local context_file="${repo_dir}/nanobot/agent/context.py"
    local schema_file="${repo_dir}/nanobot/config/schema.py"
    
    print_step "Updating nanobot repository..."
    cd "$repo_dir"
    
    # Pin to a specific working commit to avoid breaking changes
    local PINNED_COMMIT="63d646f"
    
    # Check if we need to reset to pinned commit
    local current_commit
    current_commit=$(git rev-parse HEAD 2>/dev/null)
    
    if [[ "$current_commit" != "$PINNED_COMMIT" ]]; then
        print_info "Resetting to pinned commit $PINNED_COMMIT..."
        git fetch origin "$PINNED_COMMIT" 2>/dev/null || true
        git checkout "$PINNED_COMMIT" 2>/dev/null || print_warning "Could not checkout pinned commit"
    fi
    
    # Always re-apply patches after any checkout
    print_info "Patches will be applied after checkout..."
    
    cd - > /dev/null 2>&1
    
    print_step "Creating vector_memory.py module..."
    
    VECTOR_FILE="$vector_file" python3 << 'PYEOF'
import os

vector_content = '''"""LanceDB vector memory for nanobot agents with multi-provider embeddings."""

import json
import os
from pathlib import Path
from typing import Any

import lancedb
from loguru import logger


def get_embedding_function(provider: str, model: str):
    """Get embedding function based on provider."""
    if provider == "ollama":
        from lancedb.embeddings.ollama import OllamaEmbeddingFunction

        return OllamaEmbeddingFunction(model_name=model)
    elif provider == "openai":
        from lancedb.embeddings.openai import OpenAIEmbeddingFunction

        return OpenAIEmbeddingFunction(model=model)
    elif provider == "sentence-transformers":
        from lancedb.embeddings.sentence_transformers import (
            SentenceTransformerEmbeddingFunction,
        )

        return SentenceTransformerEmbeddingFunction(model_name=model)
    else:
        raise ValueError(f"Unknown embedding provider: {provider}")


class VectorMemory:
    """Vector memory store using LanceDB with configurable embeddings."""

    DEFAULT_MODELS = {
        "sentence-transformers": "paraphrase-multilingual-mpnet-base-v2",
        "ollama": "nomic-embed-text",
        "openai": "text-embedding-3-small",
    }

    DIMENSIONS = {
        "paraphrase-multilingual-mpnet-base-v2": 768,
        "all-MiniLM-L6-v2": 384,
        "nomic-embed-text": 768,
        "mxbai-embed-large": 1024,
        "bge-m3": 1024,
        "all-minilm": 384,
        "snowflake-arctic-embed": 1024,
        "paraphrase-multilingual": 768,
        "text-embedding-3-small": 1536,
        "text-embedding-3-large": 3072,
    }

    def __init__(
        self,
        workspace: Path,
        provider: str = "sentence-transformers",
        model: str | None = None,
    ):
        self.workspace = workspace
        self.db_path = workspace / "memory.lodb"

        self.provider = provider
        self.model = model or self.DEFAULT_MODELS.get(
            provider, "paraphrase-multilingual-mpnet-base-v2"
        )
        self.dimension = self.DIMENSIONS.get(self.model, 768)

        self._maybe_rebuild_schema()

        self.db = lancedb.connect(str(self.db_path))

        self.embedding_function = get_embedding_function(self.provider, self.model)

        self._init_collections()

    def _maybe_rebuild_schema(self):
        """Check if model dimension changed and rebuild if needed."""
        marker_file = self.db_path / ".model_config"

        current_model = None
        current_dim = None
        if marker_file.exists():
            with open(marker_file) as f:
                cfg = json.load(f)
                current_model = cfg.get("model")
                current_dim = cfg.get("dimension")

        if current_model and current_model != self.model:
            import shutil

            logger.warning(
                f"Model changed from {current_model} to {self.model}. Rebuilding vector store..."
            )
            if self.db_path.exists():
                shutil.rmtree(self.db_path)

        self.db_path.mkdir(parents=True, exist_ok=True)
        with open(marker_file, "w") as f:
            json.dump({"model": self.model, "dimension": self.dimension}, f)

    def _init_collections(self):
        """Initialize or open collections."""
        dim = self.dimension

        if "sessions" not in self.db.table_names():
            self.db.create_table(
                "sessions",
                schema={
                    "id": "string",
                    "session_key": "string",
                    "content": "string",
                    "metadata": "json",
                    "vector": f"vector({dim})",
                },
                embedding_function=self.embedding_function,
            )

        if "entities" not in self.db.table_names():
            self.db.create_table(
                "entities",
                schema={
                    "id": "string",
                    "session_key": "string",
                    "entity_type": "string",
                    "value": "string",
                    "metadata": "json",
                    "vector": f"vector({dim})",
                },
                embedding_function=self.embedding_function,
            )

    def add_session_summary(
        self,
        session_key: str,
        content: str,
        metadata: dict[str, Any],
    ):
        """Add a session summary to vector store."""
        table = self.db.open_table("sessions")
        table.add(
            [
                {
                    "id": f"{session_key}_{metadata.get('timestamp')}",
                    "session_key": session_key,
                    "content": content,
                    "metadata": metadata,
                }
            ]
        )

    def add_entity(
        self,
        session_key: str,
        entity_type: str,
        value: str,
        metadata: dict[str, Any],
    ):
        """Add an entity to vector store."""
        table = self.db.open_table("entities")
        table.add(
            [
                {
                    "id": f"{session_key}_{entity_type}_{metadata.get('timestamp')}",
                    "session_key": session_key,
                    "entity_type": entity_type,
                    "value": value,
                    "metadata": metadata,
                }
            ]
        )

    def search_similar(
        self,
        query: str,
        session_key: str | None = None,
        limit: int = 5,
    ) -> list[dict[str, Any]]:
        """Search for similar context."""
        table = self.db.open_table("sessions")

        where_clause = None
        if session_key:
            where_clause = f"session_key = '{session_key}'"

        results = table.search(query, filter=where_clause).limit(limit).to_list()
        return results

    def get_session_entities(
        self,
        session_key: str,
    ) -> list[dict[str, Any]]:
        """Get all entities for a session."""
        table = self.db.open_table("entities")
        return table.to_list()


_vector_memory_instances: dict[str, VectorMemory] = {}


def get_vector_memory(
    workspace: Path,
    provider: str = "sentence-transformers",
    model: str | None = None,
) -> VectorMemory:
    """Get or create vector memory instance."""
    key = f"{workspace}:{provider}:{model}"
    if key not in _vector_memory_instances:
        _vector_memory_instances[key] = VectorMemory(
            workspace=workspace,
            provider=provider,
            model=model,
        )
    return _vector_memory_instances[key]
'''

filepath = os.environ.get('VECTOR_FILE', '')
if not filepath:
    print('ERROR: VECTOR_FILE not set.')
    exit(1)

os.makedirs(os.path.dirname(filepath), exist_ok=True)
with open(filepath, 'w') as f:
    f.write(vector_content)
print('Vector memory module created successfully.')
PYEOF

    # Always inject integration code into memory.py and context.py
    print_step "Injecting vector memory integration into nanobot..."
    
    # Inject into memory.py - after consolidation
    if ! grep -q "NANOBOT_USE_VECTOR_MEMORY" "$memory_file"; then
        python3 << 'PYINJECT'
import sys
filepath = sys.argv[1]
with open(filepath, 'r') as f:
    content = f.read()

# Find the line with "Memory consolidation done" and add vector storage after it
injection = '''
            try:
                import os
                from pathlib import Path
                if os.environ.get("NANOBOT_USE_VECTOR_MEMORY", "false").lower() == "true":
                    from nanobot.vector_memory import get_vector_memory
                    workspace = Path(os.environ.get("NANOBOT_WORKSPACE", "~/.nanobot/workspace")).expanduser()
                    vm = get_vector_memory(workspace)
                    vm.add_session_summary(
                        session.key, 
                        entry, 
                        {"timestamp": datetime.now().isoformat(), "message_count": len(messages)}
                    )
            except Exception as e:
                logger.warning("Failed to store in vector memory: {}", e)'''

# Find the line and inject after it
lines = content.split('\n')
new_lines = []
found = False
for line in lines:
    new_lines.append(line)
    if 'logger.info("Memory consolidation done for {} messages"' in line and not found:
        new_lines.append(injection)
        found = True

with open(filepath, 'w') as f:
    f.write('\n'.join(new_lines))
print('memory.py updated')
PYINJECT
        "$memory_file"
    else
        print_info "Vector storage already in memory.py"
    fi
    
    # Inject into context.py - before building messages
    if ! grep -q "NANOBOT_USE_VECTOR_MEMORY" "$context_file"; then
        python3 << 'PYINJECT2'
import sys
filepath = sys.argv[1]
with open(filepath, 'r') as f:
    content = f.read()

# Find the return statement in build_messages and inject vector context before it
injection = '''
        # Inject vector memory context if enabled
        try:
            import os
            if os.environ.get("NANOBOT_USE_VECTOR_MEMORY", "false").lower() == "true" and channel and chat_id:
                from pathlib import Path
                from nanobot.vector_memory import get_vector_memory
                workspace = Path(os.environ.get("NANOBOT_WORKSPACE", "~/.nanobot/workspace")).expanduser()
                vm = get_vector_memory(workspace)
                user_msgs = [m for m in history if m.get("role") == "user"]
                if user_msgs:
                    query = user_msgs[-1].get("content", "")[-500:] if user_msgs else ""
                    if query:
                        results = vm.search_similar(query, session_key=f"{channel}:{chat_id}", limit=3)
                        if results:
                            ctx_parts = [f"[Past context]\\n{r['content']}" for r in results]
                            ctx_text = "\\n\\n".join(ctx_parts)
                            messages.insert(1, {"role": "system", "content": ctx_text})
        except Exception as e:
            from loguru import logger
            logger.warning("Vector context injection failed: {}", e)'''

# Find the return line and inject before it
lines = content.split('\n')
new_lines = []
for line in lines:
    if line.strip() == 'return [' and not '<!-- inject point -->' in content:
        new_lines.append(injection)
    new_lines.append(line)

with open(filepath, 'w') as f:
    f.write('\n'.join(new_lines))
print('context.py updated')
PYINJECT2
        "$context_file"
    else
        print_info "Vector context already in context.py"
    fi
    
    [[ $? -eq 0 ]]
}

build_nanobot_image() {
    print_step "Building Docker image for nanobot..."
    
    if [[ ! -d "$NANOBOT_SOURCE_DIR" ]]; then
        print_step "Cloning nanobot repository..."
        git clone "$NANOBOT_REPO" "$NANOBOT_SOURCE_DIR"
    fi
    
    if [[ "$PATCH_WHATSAPP_AUDIO" == "true" ]]; then
        apply_audio_patch "$NANOBOT_SOURCE_DIR"
    fi
    
    if [[ "$PATCH_VECTOR_MEMORY" == "true" ]]; then
        apply_vector_memory_patch "$NANOBOT_SOURCE_DIR"
    fi
    
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

setup_initial() {
    print_header
    print_step "Initial nanobot setup..."
    
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
            echo "4. Configure in instance config.json:"
            echo '   "channels": {'
            echo '     "whatsapp": {'
            echo '       "enabled": true,'
            echo '       "allowFrom": ["+5511999999999"],'
            echo '       "groupPolicy": "mention"'
            echo '     }'
            echo '   }'
            ;;
        telegram)
            echo "To configure Telegram:"
            echo "1. Open Telegram, search for @BotFather"
            echo "2. Send /newbot and follow instructions"
            echo "3. Copy the bot token"
            echo "4. Configure in ~/.nanobot/config.json"
            ;;
        discord)
            echo "To configure Discord:"
            echo "1. Access https://discord.com/developers/applications"
            echo "2. Create an application → Bot → Add Bot"
            echo "3. Copy the bot token"
            echo "4. Enable MESSAGE CONTENT INTENT"
            ;;
        *)
            print_error "Channel not supported: $channel"
            ;;
    esac
}
