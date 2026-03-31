# Vector Memory Implementation Plan

## Overview

Add LanceDB-powered vector memory to nanobot for persistent, brain-like memory that survives container restarts. Each agent instance gets its own isolated vector store in its workspace.

## Embedding Model Options

### Supported Models

| Model | Provider | Dimension | Size | PT-BR Support | Type | Notes |
|-------|----------|-----------|------|---------------|------|-------|
| **paraphrase-multilingual-mpnet-base-v2** | sentence-transformers | 768 | ~420MB | ✅ Excellent | Local | **DEFAULT** - Best for PT-BR |
| **all-MiniLM-L6-v2** | sentence-transformers | 384 | ~67MB | ⚠️ Basic | Local | Lightest, fastest |
| **nomic-embed-text** | Ollama | 768 | ~274MB | ✅ Good | Local | Good multilingual |
| **mxbai-embed-large** | Ollama | 1024 | ~334MB | ✅ Good | Local | Higher quality |
| **bge-m3** | Ollama | 1024 | ~560MB | ✅ Excellent | Local | Best for multilingual |
| **all-minilm** | Ollama | 384 | ~67MB | ⚠️ Basic | Local | Fastest, lightweight |
| **paraphrase-multilingual** | Ollama | 768 | ~420MB | ✅ Excellent | Local | Specialized for 50+ languages |
| **text-embedding-3-small** | OpenAI | 1536 | API | ✅ Good | Remote | Cheap API cost |
| **text-embedding-3-large** | OpenAI | 3072 | API | ✅ Good | Remote | Higher quality, 6x cost |

### Recommended Options by Use Case

1. **Best for Portuguese BR (DEFAULT):** `paraphrase-multilingual-mpnet-base-v2` (sentence-transformers)
   - No extra container needed
   - Excellent multilingual embeddings
   - Loads on-demand, no RAM waste

2. **Best balance (Ollama):** `nomic-embed-text`
   - Good PT-BR support, reasonable size (274MB)
   - Requires Ollama container

3. **Best multilingual (Ollama):** `bge-m3`
   - Best for multilingual (recommended for PT-BR)
   - Larger (560MB), more RAM

4. **Remote (API):** `text-embedding-3-small`
   - No local setup needed
   - Cheap ($0.00002/1K tokens)

### Default Configuration

```python
# Default embedding model config
EMBEDDING_MODELS = {
    "sentence-transformers": {
        "default": "paraphrase-multilingual-mpnet-base-v2",
        "alternatives": ["all-MiniLM-L6-v2"]
    },
    "ollama": {
        "default": "nomic-embed-text",
        "alternatives": ["bge-m3", "mxbai-embed-large", "paraphrase-multilingual", "all-minilm"]
    },
    "openai": {
        "default": "text-embedding-3-small", 
        "alternatives": ["text-embedding-3-large"]
    }
}
```

**Default: sentence-transformers (no extra container needed)**
- Embeddings run inside nanobot Python process
- Model loads on-demand, unloads after use
- No separate container, no networking issues
- Good Portuguese BR support with `paraphrase-multilingual`

### Per-Agent Configuration Example

```json
// wa1 config.json - Portuguese wedding photographer
{
  "agents": {
    "defaults": {
      "vectorMemoryEnabled": true,
      "vectorMemoryProvider": "ollama",
      "vectorMemoryModel": "bge-m3"
    }
  }
}

// wa2 config.json - Portuguese restaurant booking
{
  "agents": {
    "defaults": {
      "vectorMemoryEnabled": true,
      "vectorMemoryProvider": "ollama", 
      "vectorMemoryModel": "nomic-embed-text"
    }
  }
}

// wa3 config.json - Using remote API
{
  "agents": {
    "defaults": {
      "vectorMemoryEnabled": true,
      "vectorMemoryProvider": "openai",
      "vectorMemoryModel": "text-embedding-3-small"
    }
  }
}
```

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                    Nanobot Agent Container                       │
│                                                                  │
│  ┌─────────────┐    ┌──────────────┐    ┌───────────────────┐  │
│  │  Session    │───►│ Vector Memory│◄───│ Entity Extraction │  │
│  │  (current)  │    │  (LanceDB)   │    │  (LLM-based)      │  │
│  └─────────────┘    └──────────────┘    └───────────────────┘  │
│         │                   │                     │              │
│         ▼                   ▼                     ▼              │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │  Memory Consolidation Flow:                               │  │
│  │  1. User message triggers consolidation                   │  │
│  │  2. LLM summarizes conversation                          │  │
│  │  3. Extract entities (customer, booking, payment)        │  │
│  │  4. Embed summary + entities → store in LanceDB           │  │
│  │  5. On new session → query similar context → inject       │  │
│  └──────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼ (persists to)
         ┌─────────────────────────────────────────────┐
         │  ~/.nanobot/agents/{instance}/memory.lodb  │
         │  (per-instance isolated folder)            │
         └─────────────────────────────────────────────┘
```

## Implementation Steps

### Phase 1: Requirements & Patching

#### 1.1 Add Dependencies to pyproject.toml

Add to `nanobot-source/pyproject.toml`:
```toml
[project.optional-dependencies]
vector = ["lancedb>=0.12", "numpy>=1.26", "sentence-transformers>=2.2"]

# For Ollama integration (optional)
vector-ollama = ["ollama>=0.1"]
```

#### 1.2 Create Vector Memory Patch Function

Following the `apply_audio_patch()` pattern in `scripts/setup.sh`:

```bash
apply_vector_memory_patch() {
    local repo_dir="$1"
    local target_file="${repo_dir}/nanobot/agent/memory.py"
    
    # Check if patch already applied
    if grep -q "lancedb" "$target_file"; then
        print_info "Vector memory patch already applied."
        return 0
    fi
    
    # Python script to inject LanceDB integration
    # Insert at appropriate location in memory.py
}
```

#### 1.3 Update build_nanobot_image()

In `scripts/setup.sh`, add:
```bash
build_nanobot_image() {
    # ... existing clone/update ...
    
    # Existing audio patch
    if [[ "$PATCH_WHATSAPP_AUDIO" == "true" ]]; then
        apply_audio_patch "$NANOBOT_SOURCE_DIR"
    fi
    
    # NEW: Vector memory patch
    if [[ "$PATCH_VECTOR_MEMORY" == "true" ]]; then
        apply_vector_memory_patch "$NANOBOT_SOURCE_DIR"
    fi
    
    # ... docker build ...
}
```

#### 1.4 Configuration Variable

In `xnanobot.sh`:
```bash
PATCH_VECTOR_MEMORY=true  # Default enabled
```

---

### Phase 2: Nanobot Source Modifications

#### 2.1 New File: `nanobot/vector_memory.py`

```python
"""LanceDB vector memory for nanobot agents with multi-provider embeddings."""

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
        from lancedb.embeddings.sentence_transformers import SentenceTransformerEmbeddingFunction
        return SentenceTransformerEmbeddingFunction(model_name=model)
    else:
        raise ValueError(f"Unknown embedding provider: {provider}")


class VectorMemory:
    """Vector memory store using LanceDB with configurable embeddings."""
    
    # Default configuration
    DEFAULT_MODELS = {
        "sentence-transformers": "paraphrase-multilingual-mpnet-base-v2",
        "ollama": "nomic-embed-text",
        "openai": "text-embedding-3-small",
    }
    
    DIMENSIONS = {
        # sentence-transformers models
        "paraphrase-multilingual-mpnet-base-v2": 768,
        "all-MiniLM-L6-v2": 384,
        # Ollama models
        "nomic-embed-text": 768,
        "mxbai-embed-large": 1024,
        "bge-m3": 1024,
        "all-minilm": 384,
        "snowflake-arctic-embed": 1024,
        "paraphrase-multilingual": 768,
        # OpenAI models
        "text-embedding-3-small": 1536,
        "text-embedding-3-large": 3072,
    }
    
    def __init__(
        self,
        workspace: Path,
        provider: str = "sentence-transformers",
        model: str = None,
    ):
        self.workspace = workspace
        self.db_path = workspace / "memory.lodb"
        
        # Set defaults
        self.provider = provider
        self.model = model or self.DEFAULT_MODELS.get(provider, "paraphrase-multilingual-mpnet-base-v2")
        self.dimension = self.DIMENSIONS.get(self.model, 768)
        
        # Check if dimension changed - if so, need to rebuild
        self._maybe_rebuild_schema()
        
        # Initialize LanceDB
        self.db = lancedb.connect(str(self.db_path))
        
        # Embedding function
        self.embedding_function = get_embedding_function(self.provider, self.model)
        
        # Initialize collections
        self._init_collections()
    
    def _maybe_rebuild_schema(self):
        """Check if model dimension changed and rebuild if needed."""
        marker_file = self.db_path / ".model_config"
        
        # Read current model config
        current_model = None
        current_dim = None
        if marker_file.exists():
            import json
            with open(marker_file) as f:
                cfg = json.load(f)
                current_model = cfg.get("model")
                current_dim = cfg.get("dimension")
        
        # If model changed, delete old database
        if current_model and current_model != self.model:
            import shutil
            logger.warning(f"Model changed from {current_model} to {self.model}. Rebuilding vector store...")
            if self.db_path.exists():
                shutil.rmtree(self.db_path)
        
        # Save new model config
        import json
        self.db_path.mkdir(parents=True, exist_ok=True)
        with open(marker_file, "w") as f:
            json.dump({"model": self.model, "dimension": self.dimension}, f)
    
    def _init_collections(self):
        """Initialize or open collections."""
        dim = self.dimension
        
        # Sessions collection - stores conversation summaries
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
        
        # Entities collection - stores extracted entities
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
        table.add([
            {
                "id": f"{session_key}_{metadata.get('timestamp')}",
                "session_key": session_key,
                "content": content,
                "metadata": metadata,
            }
        ])
    
    def add_entity(
        self,
        session_key: str,
        entity_type: str,
        value: str,
        metadata: dict[str, Any],
    ):
        """Add an entity to vector store."""
        table = self.db.open_table("entities")
        table.add([
            {
                "id": f"{session_key}_{entity_type}_{metadata.get('timestamp')}",
                "session_key": session_key,
                "entity_type": entity_type,
                "value": value,
                "metadata": metadata,
            }
        ])
    
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


# Global singleton per agent
_vector_memory_instances: dict[str, VectorMemory] = {}


def get_vector_memory(
    workspace: Path,
    provider: str = "ollama",
    model: str = None,
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
```

#### 2.2 Modify `nanobot/agent/memory.py`

Inject vector storage into consolidation:

```python
# At top of file, add:
USE_VECTOR_MEMORY = os.environ.get("NANOBOT_USE_VECTOR_MEMORY", "false").lower() == "true"

def maybe_store_in_vector(session_key: str, summary: str, metadata: dict):
    """Store consolidated memory in vector database."""
    if not USE_VECTOR_MEMORY:
        return
    
    try:
        from nanobot.vector_memory import get_vector_memory
        
        workspace = Path(os.environ.get("NANOBOT_WORKSPACE", "~/.nanobot/workspace"))
        vm = get_vector_memory(workspace)
        vm.add_session_summary(session_key, summary, metadata)
    except Exception as e:
        logger.warning("Failed to store in vector memory: {}", e)
```

#### 2.3 Modify `nanobot/agent/context.py`

Inject retrieved context into prompts:

```python
def maybe_inject_vector_context(session_key: str, history: list) -> list:
    """Inject relevant vector context into messages."""
    if not USE_VECTOR_MEMORY:
        return history
    
    try:
        from nanobot.vector_memory import get_vector_memory
        
        # Get recent user message as query
        user_messages = [m for m in history if m.get("role") == "user"]
        if not user_messages:
            return history
        
        query = user_messages[-1].get("content", "")[-500:]  # Last 500 chars
        
        workspace = Path(os.environ.get("NANOBOT_WORKSPACE", "~/.nanobot/workspace"))
        vm = get_vector_memory(workspace)
        
        # Search similar
        results = vm.search_similar(query, session_key=session_key, limit=3)
        
        if results:
            context_parts = [f"[Relevant past context]\n{r['content']}" for r in results]
            context_text = "\n\n".join(context_parts)
            
            # Insert as system message
            return [
                {"role": "system", "content": context_text},
                *history
            ]
    except Exception as e:
        logger.warning("Failed to inject vector context: {}", e)
    
    return history
```

#### 2.4 Add Config to Schema

In `nanobot/config/schema.py`:

```python
class AgentDefaults(Base):
    # ... existing fields ...
    vector_memory_enabled: bool = False
    vector_memory_provider: str = "sentence-transformers"  # Default: no extra container
    vector_memory_model: str = "paraphrase-multilingual-mpnet-base-v2"
```

**Provider defaults:**
- `sentence-transformers`: No container needed, embeddings run in-process
- `ollama`: Requires Ollama container (optional)
- `openai`: Requires API key (optional)

---

### Phase 3: xnanobot.sh Integration

#### 3.1 Add Instance Config Functions

In `lib/llm.sh`:

```bash
# Set vector memory for instance (enable/disable)
instance_set_vector_memory() {
    local instance_name="$1"
    local enabled="$2"  # "true" or "false"
    local instance_dir
    instance_dir=$(get_instance_dir "$instance_name")
    
    python3 -c "
import json
with open('${instance_dir}/config.json', 'r') as f:
    c = json.load(f)
c.setdefault('agents', {}).setdefault('defaults', {})['vectorMemoryEnabled'] = $enabled
with open('${instance_dir}/config.json', 'w') as f:
    json.dump(c, f, indent=2)
"
}

# Set vector memory provider and model
instance_set_vector_memory_model() {
    local instance_name="$1"
    local provider="$2"  # "ollama", "openai", "sentence-transformers"
    local model="$3"
    local instance_dir
    instance_dir=$(get_instance_dir "$instance_name")
    
    python3 -c "
import json
with open('${instance_dir}/config.json', 'r') as f:
    c = json.load(f)
c.setdefault('agents', {}).setdefault('defaults', {})['vectorMemoryProvider'] = '$provider'
c.setdefault('agents', {}).setdefault('defaults', {})['vectorMemoryModel'] = '$model'
with open('${instance_dir}/config.json', 'w') as f:
    json.dump(c, f, indent=2)
"
}

# Show vector memory status
instance_show_vector_memory() {
    local instance_name="$1"
    local instance_dir
    instance_dir=$(get_instance_dir "$instance_name")
    
    python3 -c "
import json
with open('${instance_dir}/config.json', 'r') as f:
    c = json.load(f)
defaults = c.get('agents', {}).get('defaults', {})
enabled = defaults.get('vectorMemoryEnabled', False)
provider = defaults.get('vectorMemoryProvider', 'ollama')
model = defaults.get('vectorMemoryModel', 'nomic-embed-text')
print(f'Vector Memory: {enabled}')
print(f'Provider: {provider}')
print(f'Model: {model}')
"
}

# Reset instance vector config to use global
instance_reset_vector_config() {
    local instance_name="$1"
    local instance_dir
    instance_dir=$(get_instance_dir "$instance_name")
    
    python3 -c "
import json
with open('${instance_dir}/config.json', 'r') as f:
    c = json.load(f)
# Remove vector memory settings from instance
if 'agents' in c and 'defaults' in c['agents']:
    defaults = c['agents']['defaults']
    defaults.pop('vectorMemoryEnabled', None)
    defaults.pop('vectorMemoryProvider', None)
    defaults.pop('vectorMemoryModel', None)
with open('${instance_dir}/config.json', 'w') as f:
    json.dump(c, f, indent=2)
"
}
```

#### 3.2 Add CLI Commands

In `lib/llm_commands.sh`:

```bash
# Global vector memory commands
cmd_global_vector() {
    local action="$1"  # enable, disable, model, status
    
    case "$action" in
        enable)
            set_global_vector_memory "true"
            ;;
        disable)
            set_global_vector_memory "false"
            ;;
        model)
            local provider="$2"
            local model="$3"
            set_global_vector_model "$provider" "$model"
            ;;
        status)
            show_global_vector_config
            ;;
        *)
            echo "Usage: $0 global-vector [enable|disable|model|status]"
            ;;
    esac
}

cmd_instance_vector() {
    local instance_name="$1"
    local action="$2"  # enable, disable, model, status, reset
    
    case "$action" in
        enable)
            instance_set_vector_memory "$instance_name" "true"
            ;;
        disable)
            instance_set_vector_memory "$instance_name" "false"
            ;;
        model)
            local provider="$3"
            local model="$4"
            instance_set_vector_memory_model "$instance_name" "$provider" "$model"
            ;;
        status)
            instance_show_vector_memory "$instance_name"
            ;;
        reset)
            instance_reset_vector_config "$instance_name"
            ;;
        *)
            echo "Usage: $0 instance-vector <instance> [enable|disable|model|status|reset]"
            ;;
    esac
}
```

CLI commands:
```
# Global settings (default for all new instances)
./xnanobot.sh global-vector enable
./xnanobot.sh global-vector disable
./xnanobot.sh global-vector model ollama bge-m3
./xnanobot.sh global-vector status
./xnanobot.sh global-vector clear

# Per-instance (overrides global)
./xnanobot.sh instance-vector wa1 enable
./xnanobot.sh instance-vector wa1 disable
./xnanobot.sh instance-vector wa1 model ollama bge-m3
./xnanobot.sh instance-vector wa1 status
./xnanobot.sh instance-vector wa1 reset   # Reset to global
```

#### 3.3 Add Interactive Menu Options

In `lib/menu_llm.sh`:

**New Global Menu (menu_global_vector):**
```bash
menu_global_vector() {
    while true; do
        print_header
        echo -e "${YELLOW}━━━ Global Vector Memory Settings ━━━━━━━━━━━━━━━━${NC}"
        echo
        
        show_global_vector_config
        
        echo -e "${GREEN}━━━ Global Vector Memory ━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo "  [1] Enable vector memory (default for all instances)"
        echo "  [2] Disable vector memory"
        echo "  [3] Set default embedding model"
        echo "  [4] Set embedding provider"
        echo "  [5] Clear global vector memory settings"
        echo "  [0] Back"
        echo
        read -p "Choose [0-5]: " choice
        
        case $choice in
            1)
                set_global_vector_memory "true"
                print_success "Global vector memory enabled"
                ;;
            2)
                set_global_vector_memory "false"
                print_success "Global vector memory disabled"
                ;;
            3)
                cmd_global_vector_model
                ;;
            4)
                cmd_global_vector_provider
                ;;
            5)
                clear_global_vector_config
                print_success "Global vector config cleared"
                ;;
            0)
                return
                ;;
            *)
                print_error "Invalid option"
                ;;
        esac
        echo
    done
}
```

**New Instance Menu (menu_instance_vector_config):**
```bash
menu_instance_vector_config() {
    local instance_name="$1"
    
    while true; do
        print_header
        show_instance_vector_config "$instance_name"
        
        echo -e "${GREEN}━━━ Vector Memory: $instance_name ━━━━━━━━━━━━━━━━━━━━${NC}"
        echo "  [1] Enable vector memory"
        echo "  [2] Disable vector memory"
        echo "  [3] Set embedding model"
        echo "  [4] Set embedding provider"
        echo "  [5] Reset to global vector settings"
        echo "  [0] Back"
        echo
        read -p "Choose [0-5]: " choice
        
        case $choice in
            1)
                instance_set_vector_memory "$instance_name" "true"
                print_success "Vector memory enabled for $instance_name"
                prompt_restart_instance "$instance_name"
                ;;
            2)
                instance_set_vector_memory "$instance_name" "false"
                print_success "Vector memory disabled for $instance_name"
                prompt_restart_instance "$instance_name"
                ;;
            3)
                cmd_instance_vector_model "$instance_name"
                ;;
            4)
                cmd_instance_vector_provider "$instance_name"
                ;;
            5)
                instance_reset_vector_config "$instance_name"
                print_success "Reset to global config"
                prompt_restart_instance "$instance_name"
                ;;
            0)
                return
                ;;
            *)
                print_error "Invalid option"
                ;;
        esac
        echo
    done
}
```

**Integration into existing menus:**

In `menu_global_llm()`, add:
```bash
echo "  [6] Global Vector Memory Settings"
```

In `menu_instance_llm_config()`, add:
```bash
echo "  [6] Vector Memory Settings"
```

When choice is 6, call the respective vector menu.

#### 3.4 Interactive Model Selection

Add helper functions in `lib/llm.sh` for interactive model selection:

```bash
# Available embedding models by provider
EMBEDDING_MODELS_OLLAMA=(
    "nomic-embed-text:Best all-around, good PT-BR"
    "bge-m3:Best multilingual (recommended for PT-BR)"
    "mxbai-embed-large:Higher quality, more RAM"
    "all-minilm:Lightweight, fastest"
    "paraphrase-multilingual:Specialized for 50+ languages"
    "snowflake-arctic-embed:Good for code + general"
)

EMBEDDING_MODELS_OPENAI=(
    "text-embedding-3-small:Cheap, good quality (default)"
    "text-embedding-3-large:Higher quality, 6x cost"
)

EMBEDDING_MODELS_ST=(
    "paraphrase-multilingual-mpnet-base-v2:Best for PT-BR, recommended"
    "all-MiniLM-L6-v2:Lightweight, fast"
)

select_embedding_provider_interactive() {
    echo "Select embedding provider:"
    echo "  [1] Ollama (local, no API key needed)"
    echo "  [2] OpenAI (remote, API key needed)"
    echo "  [3] sentence-transformers (local, lightweight)"
    echo
    read -p "Choose [1-3]: " choice
    
    case "$choice" in
        1) echo "ollama" ;;
        2) echo "openai" ;;
        3) echo "sentence-transformers" ;;
        *) echo "ollama" ;;
    esac
}

select_embedding_model_interactive() {
    local provider="$1"
    
    case "$provider" in
        sentence-transformers)
            local i=1
            local models_arr=()
            echo "Select embedding model (sentence-transformers):"
            for model_info in "${EMBEDDING_MODELS_ST[@]}"; do
                local model="${model_info%%:*}"
                local desc="${model_info##*:}"
                echo "  [$i] $model - $desc"
                models_arr+=("$model")
                ((i++))
            done
            echo
            read -p "Choose: " sel
            echo "${models_arr[$((sel-1))]:-paraphrase-multilingual-mpnet-base-v2}"
            ;;
        ollama)
            local i=1
            local models_arr=()
            echo "Select embedding model (Ollama):"
            for model_info in "${EMBEDDING_MODELS_OLLAMA[@]}"; do
                local model="${model_info%%:*}"
                local desc="${model_info##*:}"
                echo "  [$i] $model - $desc"
                models_arr+=("$model")
                ((i++))
            done
            echo
            read -p "Choose: " sel
            echo "${models_arr[$((sel-1))]:-nomic-embed-text}"
            ;;
        openai)
            local i=1
            local models_arr=()
            echo "Select embedding model (OpenAI):"
            for model_info in "${EMBEDDING_MODELS_OPENAI[@]}"; do
                local model="${model_info%%:*}"
                local desc="${model_info##*:}"
                echo "  [$i] $model - $desc"
                models_arr+=("$model")
                ((i++))
            done
            echo
            read -p "Choose: " sel
            echo "${models_arr[$((sel-1))]:-text-embedding-3-small}"
            ;;
        *)
            echo "paraphrase-multilingual-mpnet-base-v2"
            ;;
    esac
}

# Helper to get effective vector config (instance or global fallback)
get_effective_vector_enabled() {
    local instance_name="$1"
    local instance_dir
    instance_dir=$(get_instance_dir "$instance_name")
    
    # Check instance config first
    local instance_enabled
    instance_enabled=$(python3 -c "
import json
try:
    with open('${instance_dir}/config.json', 'r') as f:
        c = json.load(f)
    print(c.get('agents', {}).get('defaults', {}).get('vectorMemoryEnabled', 'inherit'))
except: print('inherit')
")
    
    if [[ "$instance_enabled" != "inherit" ]]; then
        echo "$instance_enabled"
        return
    fi
    
    # Fall back to global
    get_global_vector_enabled
}

get_effective_vector_provider() {
    local instance_name="$1"
    local instance_dir
    instance_dir=$(get_instance_dir "$instance_name")
    
    local instance_provider
    instance_provider=$(python3 -c "
import json
try:
    with open('${instance_dir}/config.json', 'r') as f:
        c = json.load(f)
    print(c.get('agents', {}).get('defaults', {}).get('vectorMemoryProvider', 'inherit'))
except: print('inherit')
")
    
    if [[ "$instance_provider" != "inherit" ]]; then
        echo "$instance_provider"
        return
    fi
    
    get_global_vector_provider
}

get_effective_vector_model() {
    local instance_name="$1"
    local instance_dir
    instance_dir=$(get_instance_dir "$instance_name")
    
    local instance_model
    instance_model=$(python3 -c "
import json
try:
    with open('${instance_dir}/config.json', 'r') as f:
        c = json.load(f)
    print(c.get('agents', {}).get('defaults', {}).get('vectorMemoryModel', 'inherit'))
except: print('inherit')
")
    
    if [[ "$instance_model" != "inherit" ]]; then
        echo "$instance_model"
        return
    fi
    
    get_global_vector_model
}
```

This provides interactive selection with descriptions for each model.

### Menu Flow Summary

**Main Menu Integration:**

```
Main Menu
  ├── [25] Global LLM Settings
  │     └── [6] Global Vector Memory Settings (NEW)
  ├── [26] Instance LLM Settings  
  │     └── Instance Selection → [6] Vector Memory Settings (NEW)
```

**Menu Screens:**

```
━━━ Global Vector Memory Settings ━━━━━━━━━━━━━━━━━━━━━
  Vector Memory:  true
  Provider:        ollama
  Model:           nomic-embed-text

━━━ Global Vector Memory ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  [1] Enable vector memory (default for all instances)
  [2] Disable vector memory
  [3] Set default embedding model
  [4] Set embedding provider
  [5] Clear global vector memory settings
  [0] Back
```

```
━━━ Vector Memory: wa1 ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  Vector Memory:  true (instance)
  Provider:        ollama (global)
  Model:           bge-m3 (instance)

━━━ Vector Memory: wa1 ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  [1] Enable vector memory
  [2] Disable vector memory
  [3] Set embedding model
  [4] Set embedding provider
  [5] Reset to global vector settings
  [0] Back
```

**Model Selection Screen (Interactive):**

```
Select embedding model (Ollama):
  [1] nomic-embed-text - Best all-around, good PT-BR
  [2] bge-m3 - Best multilingual (recommended for PT-BR)
  [3] mxbai-embed-large - Higher quality, more RAM
  [4] all-minilm - Lightweight, fastest
  [5] paraphrase-multilingual - Specialized for 50+ languages
  [6] snowflake-arctic-embed - Good for code + general

Choose: 2
Model selected: bge-m3
```

#### 3.4 Helper Functions for Global Config

In `lib/llm.sh`:

```bash
# Global vector memory config file
GLOBAL_VECTOR_CONFIG_FILE="${CONFIG_DIR}/global-vector.json"

set_global_vector_memory() {
    local enabled="$1"
    python3 -c "
import json
c = {}
try:
    with open('${GLOBAL_VECTOR_CONFIG_FILE}', 'r') as f:
        c = json.load(f)
except: pass
c['enabled'] = $enabled
with open('${GLOBAL_VECTOR_CONFIG_FILE}', 'w') as f:
    json.dump(c, f, indent=2)
"
}

set_global_vector_model() {
    local provider="$1"
    local model="$2"
    python3 -c "
import json
c = {}
try:
    with open('${GLOBAL_VECTOR_CONFIG_FILE}', 'r') as f:
        c = json.load(f)
except: pass
c['provider'] = '$provider'
c['model'] = '$model'
with open('${GLOBAL_VECTOR_CONFIG_FILE}', 'w') as f:
    json.dump(c, f, indent=2)
"
}

get_global_vector_enabled() {
    python3 -c "
import json
try:
    with open('${GLOBAL_VECTOR_CONFIG_FILE}', 'r') as f:
        c = json.load(f)
    print(c.get('enabled', False))
except: print(False)
"
}

get_global_vector_model() {
    python3 -c "
import json
try:
    with open('${GLOBAL_VECTOR_CONFIG_FILE}', 'r') as f:
        c = json.load(f)
    print(c.get('model', 'paraphrase-multilingual-mpnet-base-v2'))
except: print('paraphrase-multilingual-mpnet-base-v2')
"
}

get_global_vector_provider() {
    python3 -c "
import json
try:
    with open('${GLOBAL_VECTOR_CONFIG_FILE}', 'r') as f:
        c = json.load(f)
    print(c.get('provider', 'sentence-transformers'))
except: print('sentence-transformers')
"
}

show_global_vector_config() {
    local enabled provider model
    enabled=$(get_global_vector_enabled)
    provider=$(get_global_vector_provider)
    model=$(get_global_vector_model)
    
    echo -e "  Vector Memory: ${GREEN}$enabled${NC}"
    echo -e "  Provider:      ${GREEN}$provider${NC}"
    echo -e "  Model:         ${GREEN}$model${NC}"
}

show_instance_vector_config() {
    local instance_name="$1"
    local instance_dir
    instance_dir=$(get_instance_dir "$instance_name")
    
    python3 -c "
import json
with open('${instance_dir}/config.json', 'r') as f:
    c = json.load(f)
defaults = c.get('agents', {}).get('defaults', {})
enabled = defaults.get('vectorMemoryEnabled', 'inherit')
provider = defaults.get('vectorMemoryProvider', 'inherit')
model = defaults.get('vectorMemoryModel', 'inherit')
print(f'Vector Memory: {enabled}')
print(f'Provider: {provider}')
print(f'Model: {model}')
"
}
```

---

### Phase 4: Environment Variable Propagation

In instance docker-compose template, propagate to container:

```yaml
environment:
  - NANOBOT_USE_VECTOR_MEMORY=${VECTOR_MEMORY_ENABLED:-false}
  - NANOBOT_VECTOR_PROVIDER=${VECTOR_MEMORY_PROVIDER:-sentence-transformers}
  - NANOBOT_VECTOR_MODEL=${VECTOR_MEMORY_MODEL:-paraphrase-multilingual-mpnet-base-v2}
```

**No extra containers needed for default (sentence-transformers)** - embeddings run inside nanobot process.

Optional: If using Ollama, add to docker-compose:
```yaml
ollama:
  image: ollama/ollama:latest
  volumes:
    - ./ollama-data:/root/.ollama
```

---

## Files to Modify

| File | Action |
|------|--------|
| `nanobot-source/pyproject.toml` | Add lancedb, sentence-transformers dependencies |
| `nanobot-source/nanobot/config/schema.py` | Add vector_memory config fields |
| `nanobot-source/nanobot/agent/memory.py` | Patch to store vectors on consolidation |
| `nanobot-source/nanobot/agent/context.py` | Patch to inject context on session start |
| `nanobot-source/nanobot/agent/loop.py` | Pass config to memory system |
| `scripts/setup.sh` | Add `apply_vector_memory_patch()` function |
| `lib/llm.sh` | Add all vector config functions (global + instance) |
| `lib/llm_commands.sh` | Add CLI commands (global-vector, instance-vector) |
| `lib/menu_llm.sh` | Add global + instance vector memory menus |
| `xnanobot.sh` | Add PATCH_VECTOR_MEMORY, dispatch for new commands |

#### xnanobot.sh Dispatch Integration

Add to the case statement in `xnanobot.sh`:

```bash
# Add new commands to dispatch
global-vector)
    shift
    cmd_global_vector "$@"
    ;;
instance-vector)
    local inst="$2"
    shift 2
    cmd_instance_vector "$inst" "$@"
    ;;
```

**Note:** Menu integration (items [6]) handles interactive users. CLI dispatch handles direct command-line usage.

#### Docker-Compose Template Update

In instance docker-compose template, propagate to container:

```yaml
environment:
  - NANOBOT_USE_VECTOR_MEMORY=${VECTOR_MEMORY_ENABLED:-false}
  - NANOBOT_VECTOR_PROVIDER=${VECTOR_MEMORY_PROVIDER:-sentence-transformers}
  - NANOBOT_VECTOR_MODEL=${VECTOR_MEMORY_MODEL:-paraphrase-multilingual-mpnet-base-v2}
```

**No extra containers needed for default (sentence-transformers)** - embeddings run inside nanobot process.

Optional: If using Ollama, add to docker-compose:
```yaml
ollama:
  image: ollama/ollama:latest
  volumes:
    - ./ollama-data:/root/.ollama
```

## Files to Create

| File | Purpose |
|------|---------|
| `nanobot-source/nanobot/vector_memory.py` | LanceDB vector memory module with multi-provider embeddings |
| `config/global-vector.json` | Global vector memory settings storage |

---

## Patching Workflow

```
User runs: ./xnanobot.sh build
    │
    ▼
build_nanobot_image() in scripts/setup.sh
    │
    ├─► git clone nanobot-source/
    │
    ├─► apply_audio_patch() (if PATCH_WHATSAPP_AUDIO=true)
    │
    └─► apply_vector_memory_patch() (if PATCH_VECTOR_MEMORY=true)
           │
           ├─► Creates nanobot/vector_memory.py
           ├─► Modifies memory.py to import/use vector_memory
           └─► Modifies context.py to inject context
    │
    ▼
docker build -t nanobot .
```

---

## Configuration Flow

### Priority: Instance Override > Global Default

```
┌─────────────────────────────────────────────────────────────────┐
│              Vector Memory Config Resolution                    │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  Instance Config (config.json)                                   │
│  ├── vectorMemoryEnabled: true/false/inherit                   │
│  ├── vectorMemoryProvider: "ollama"/"openai"/inherit           │
│  └── vectorMemoryModel: "bge-m3"/.../inherit                   │
│         │                                                        │
│         ▼ (if "inherit" or missing)                             │
│  Global Config (config/global-vector.json)                     │
│  ├── enabled: true/false (default: false)                       │
│  ├── provider: "ollama" (default)                              │
│  └── model: "nomic-embed-text" (default)                       │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

### Configuration Flow Diagram

```
User: ./xnanobot.sh instance-vector wa1 model ollama bge-m3
    │
    ▼
instance_set_vector_memory_model "wa1" "ollama" "bge-m3"
    │
    ▼
Update nanobot-instances/wa1/config.json:
{
  "agents": {
    "defaults": {
      "vectorMemoryEnabled": true,
      "vectorMemoryProvider": "ollama",
      "vectorMemoryModel": "bge-m3"
    }
  }
}
    │
    ▼
Instance restart
    │
    ▼
Container starts with:
  NANOBOT_USE_VECTOR_MEMORY=true
  NANOBOT_VECTOR_PROVIDER=ollama
  NANOBOT_VECTOR_MODEL=bge-m3
    │
    ▼
VectorMemory initialized with config
```

### Global Config Flow

```
User: ./xnanobot.sh global-vector model ollama bge-m3
    │
    ▼
set_global_vector_model "ollama" "bge-m3"
    │
    ▼
Update config/global-vector.json:
{
  "enabled": true,
  "provider": "ollama",
  "model": "bge-m3"
}
    │
    ▼
New instances will inherit these settings
Existing instances can override or reset to global
```

---

## Usage

### CLI Commands

```bash
# Global settings (default for all new instances)
./xnanobot.sh global-vector enable
./xnanobot.sh global-vector disable
./xnanobot.sh global-vector model ollama bge-m3
./xnanobot.sh global-vector provider openai
./xnanobot.sh global-vector status
./xnanobot.sh global-vector clear

# Per-instance (overrides global)
./xnanobot.sh instance-vector wa1 enable
./xnanobot.sh instance-vector wa1 disable
./xnanobot.sh instance-vector wa1 model ollama bge-m3
./xnanobot.sh instance-vector wa1 provider openai
./xnanobot.sh instance-vector wa1 status
./xnanobot.sh instance-vector wa1 reset   # Reset to global
```

### Interactive Menu Navigation

```
Main Menu
  └── [25] Global LLM Settings
        └── [6] Global Vector Memory Settings
              ├── [1] Enable (for all instances)
              ├── [2] Disable
              ├── [3] Set embedding model (interactive)
              ├── [4] Set embedding provider
              └── [5] Clear global settings

Main Menu
  └── [26] Instance LLM Settings
        └── [Select instance]
              └── [6] Vector Memory Settings
                    ├── [1] Enable
                    ├── [2] Disable
                    ├── [3] Set embedding model
                    ├── [4] Set embedding provider
                    └── [5] Reset to global
```

### Configuration Options Summary

| Command | Example | Description |
|---------|---------|-------------|
| `global-vector enable` | - | Enable global vector memory |
| `global-vector disable` | - | Disable global vector memory |
| `global-vector model <provider> <model>` | ollama bge-m3 | Set default embedding model |
| `global-vector status` | - | Show global config |
| `global-vector clear` | - | Clear global config |
| `instance-vector <instance> enable` | wa1 enable | Enable for instance |
| `instance-vector <instance> disable` | wa1 disable | Disable for instance |
| `instance-vector <instance> model <provider> <model>` | wa1 ollama bge-m3 | Set embedding model |
| `instance-vector <instance> status` | wa1 status | Show instance config |
| `instance-vector <instance> reset` | wa1 reset | Reset to global config |

### Provider/Model Options

**Local (sentence-transformers - DEFAULT, no extra container):**
- `sentence-transformers paraphrase-multilingual-mpnet-base-v2` - Best for PT-BR (recommended)
- `sentence-transformers all-MiniLM-L6-v2` - Lightweight, fastest

**Optional - Local (Ollama - requires separate container):**
- `ollama nomic-embed-text` - Good PT-BR support
- `ollama bge-m3` - Best multilingual
- `ollama mxbai-embed-large` - Higher quality
- `ollama all-minilm` - Lightweight

**Optional - Remote (OpenAI API):**
- `openai text-embedding-3-small` - Cheap, good quality
- `openai text-embedding-3-large` - Higher quality, 6x cost

---

## Considerations

1. **Embedding API Key**: 
   - **sentence-transformers**: No API key needed, runs locally (DEFAULT)
   - **Ollama**: No API key needed, runs locally (requires container)
   - **OpenAI**: Needs `OPENAI_API_KEY` in provider config

2. **RAM Usage**:
   - **sentence-transformers**: Loads only during embedding generation, unloads after
   - **Ollama models**: ~300MB-1GB per model in RAM
   - **OpenAI**: No local RAM needed (API calls)

3. **Cost**:
   - **Local**: No API costs, but RAM/CPU usage
   - **OpenAI**: ~$0.00002/1K tokens (text-embedding-3-small)

4. **Portuguese BR Support**:
   - **Recommended**: `paraphrase-multilingual-mpnet-base-v2` (sentence-transformers) - DEFAULT
   - **Good (Ollama)**: `bge-m3`, `paraphrase-multilingual`
   - **Basic**: `all-MiniLM-L6-v2` or `all-minilm`

5. **Session Isolation**: Each agent container has own LanceDB file - isolated by default.

6. **Existing Memory**: This supplements (not replaces) existing MEMORY.md/HISTORY.md consolidation.

7. **Model Change**: When changing model, vector store is auto-rebuilt (old vectors lost).

8. **No Extra Container Needed**: Default (sentence-transformers) runs inside nanobot container.

---

## Alternative: Qdrant (Not Recommended for Your Case)

Qdrant would require:
- Additional container
- Shared storage or per-instance Qdrant instances
- More complex networking

Only use if you want centralized vector search across agents.
