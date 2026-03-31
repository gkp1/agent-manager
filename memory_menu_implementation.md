# Memory Settings Menu Implementation Plan

## Overview

Add a new dedicated "Memory" menu section to configure:
1. **Vector Memory** - LanceDB-based persistent memory (already implemented)
2. **Max Messages** - Rolling window for conversation history (from earlier discussion)

Both can be configured globally (default for all instances) or per-instance.

---

## Current State

- Vector memory CLI commands already exist: `global-vector`, `instance-vector`
- Vector memory config functions already exist in `lib/llm.sh`
- No dedicated Memory menu exists - users must use CLI or LLM menu [6]

---

## Implementation Steps

### Phase 1: Add Main Menu Option

In `lib/menu.sh`:

```bash
# Add to main menu
echo "  [27] Memory Settings"
```

```bash
# Add to case statement
27)
    menu_memory
    ;;
```

---

### Phase 2: Create menu_memory() Function

In `lib/menu_memory.sh` (NEW FILE):

```bash
menu_memory() {
    while true; do
        print_header
        echo -e "${YELLOW}━━━ Memory Settings ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo
        echo -e "${GREEN}━━━ Global Memory Settings ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        show_global_vector_config
        
        echo
        echo "  [1] Global Vector Memory Settings"
        echo "  [2] Global Max Messages Settings"  
        echo "  [3] Instance Memory Settings"
        echo "  [0] Back"
        echo
        read -p "Choose [0-3]: " choice
        
        case $choice in
            1) menu_global_vector_memory ;;
            2) menu_global_max_messages ;;
            3) menu_instance_memory_select ;;
            0) return ;;
        esac
    done
}
```

---

### Phase 3: Create menu_global_vector_memory()

```bash
menu_global_vector_memory() {
    while true; do
        print_header
        echo -e "${YELLOW}━━━ Global Vector Memory ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo
        
        show_global_vector_config
        
        echo
        echo "  [1] Enable vector memory"
        echo "  [2] Disable vector memory"
        echo "  [3] Set embedding model"
        echo "  [4] Show current config"
        echo "  [5] Clear global settings"
        echo "  [0] Back"
        echo
        read -p "Choose [0-5]: " choice
        
        case $choice in
            1)
                set_global_vector_memory "true"
                print_success "Enabled"
                ;;
            2)
                set_global_vector_memory "false"
                print_success "Disabled"
                ;;
            3)
                # Interactive model selection
                select_vector_model_interactive
                ;;
            4)
                show_global_vector_config
                echo
                read -p "Press Enter to continue..."
                ;;
            5)
                rm -f "$GLOBAL_VECTOR_CONFIG_FILE"
                print_success "Cleared"
                ;;
            0) return ;;
        esac
    done
}
```

---

### Phase 4: Create menu_global_max_messages()

```bash
# Add to lib/llm.sh
get_global_max_messages() { ... }
set_global_max_messages() { ... }
show_global_max_messages_config() { ... }

menu_global_max_messages() {
    while true; do
        print_header
        echo -e "${YELLOW}━━━ Global Max Messages ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo
        
        show_global_max_messages_config
        
        echo
        echo "  [1] Set max messages (0=unlimited)"
        echo "  [2] Reset to default (0)"
        echo "  [0] Back"
        echo
        read -p "Choose [0-2]: " choice
        
        case $choice in
            1)
                read -p "Max messages (0=unlimited): " max_msg
                set_global_max_messages "$max_msg"
                print_success "Set to $max_msg"
                ;;
            2)
                set_global_max_messages "0"
                print_success "Reset to unlimited"
                ;;
            0) return ;;
        esac
    done
}
```

---

### Phase 5: Instance Memory Selection

```bash
menu_instance_memory_select() {
    # Similar to menu_instance_llm() - list instances
    # Then call menu_instance_memory_config for selected instance
}

menu_instance_memory_config() {
    local instance_name="$1"
    
    while true; do
        print_header
        echo -e "${YELLOW}━━━ Memory: $instance_name ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo
        
        show_instance_vector_config "$instance_name"
        show_instance_max_messages_config "$instance_name"
        
        echo
        echo "  [1] Vector Memory: Enable/Disable"
        echo "  [2] Vector Memory: Set model"
        echo "  [3] Max Messages: Set value"
        echo "  [4] Reset to global settings"
        echo "  [0] Back"
        echo
        read -p "Choose [0-4]: " choice
        
        case $choice in
            1)
                # Toggle enable/disable
                ;;
            2)
                # Set model
                ;;
            3)
                # Set max messages
                ;;
            4)
                instance_reset_memory_config "$instance_name"
                print_success "Reset to global"
                ;;
            0) return ;;
        esac
    done
}
```

---

### Phase 6: Helper Functions

In `lib/llm.sh`, add:

```bash
# Max messages functions
GLOBAL_MAX_MESSAGES_FILE="${NANOBOT_HOME}/global-max-messages.json"

get_global_max_messages() { ... }
set_global_max_messages() { ... }
show_global_max_messages_config() { ... }

instance_set_max_messages() { ... }
instance_get_max_messages() { ... }
instance_show_max_messages() { ... }
instance_reset_memory_config() { ... }

# Interactive model selection
select_vector_model_interactive() {
    # Show provider selection
    # Show model selection based on provider
    # Call set_global_vector_model
}
```

---

### Phase 7: Update Config Schema

In nanobot for max_messages:

```python
# nanobot/config/schema.py
class AgentDefaults(Base):
    # ... existing ...
    max_messages: int = 0  # 0 = unlimited (current behavior)
```

---

## Files to Modify

| File | Action |
|------|--------|
| `lib/menu.sh` | Add [27] Memory Settings option |
| `lib/menu_memory.sh` | NEW - Main memory menu |
| `lib/llm.sh` | Add max_messages functions |
| `lib/llm_commands.sh` | Add max_messages CLI commands |
| `xnanobot.sh` | Add dispatch for new commands |
| `nanobot-source/nanobot/config/schema.py` | Add max_messages field |

---

## Menu Structure

```
Main Menu
  └── [27] Memory Settings
        ├── [1] Global Vector Memory Settings
        │     ├── Enable
        │     ├── Disable
        │     ├── Set model
        │     ├── Show config
        │     └── Clear
        ├── [2] Global Max Messages Settings
        │     ├── Set value (0=unlimited)
        │     └── Reset to default
        └── [3] Instance Memory Settings
              ├── Select instance
              └── [for selected instance]
                    ├── Vector Memory: On/Off
                    ├── Vector Memory: Model
                    ├── Max Messages: value
                    └── Reset to global
```

---

## CLI Commands (Optional)

```bash
# Max messages
./xnanobot.sh global-max-messages 100
./xnanobot.sh global-max-messages 0    # unlimited
./xnanobot.sh instance-max-messages wa1 50
./xnanobot.sh instance-max-messages wa1 reset
```
