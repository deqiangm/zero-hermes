#!/bin/bash
# ZeroHermes V2 Agent Loop
# Version: 0.4.0

set -e

PROJECT_ROOT="${PROJECT_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
LIB_DIR="$PROJECT_ROOT/lib"
ETC_DIR="$PROJECT_ROOT/etc"

source "$LIB_DIR/common.sh"
source "$LIB_DIR/memory.sh"
source "$LIB_DIR/llm.sh"
source "$LIB_DIR/tools.sh"

# Configuration
MAX_ITERATIONS="${MAX_ITERATIONS:-20}"
SESSION_ID="${SESSION_ID:-default}"
DEBUG="${DEBUG:-false}"

# System prompt
get_system_prompt() {
	local memory_snapshot=$(get_memory_snapshot)
	local skills_list=$(execute_tool "skill_manage" '{"action":"list"}')
	
	cat << EOF
You are ZeroHermes V2, a minimal AI agent written in pure Shell.

## Available Tools
- shell_readonly: Execute safe shell commands (ls, cat, grep, etc.)
- file_read/write/search: File operations
- memory: Manage persistent memory (add/replace/remove/read)
- memory_recall: Search conversation history
- skill_manage: Create, view, and manage skills (list/view/create/delete)

## Memory System
You have TWO memory stores that persist across sessions:
1. MEMORY (agent notes) - Environment facts, project conventions, tool quirks, lessons learned
2. USER PROFILE - User preferences, communication style, workflow habits

IMPORTANT: 
- Save durable facts to memory as you discover them
- Use memory to remember user preferences and corrections
- Character limits: MEMORY=2200, USER=1375 chars

## Skills System
Skills are reusable procedures for recurring tasks. Available skills:
$skills_list

When you solve a complex problem or discover a useful workflow, consider saving it as a skill.

## Memory Snapshot
$memory_snapshot

## Instructions
Be helpful and concise. Use tools when needed.
- Save important facts to memory proactively
- Create skills for workflows worth reusing
- Respond normally or use JSON for tool calls: {"tool": "name", "arguments": {...}}
EOF
}

# Process message
process_message() {
    local msg="$1"
    local session="${2:-$SESSION_ID}"
    
    log_info "Processing: $session"
    save_message "$session" "user" "$msg"
    
    local system=$(get_system_prompt)
    
    # Build messages array using pyhelper
    local messages='[]'
    messages=$(append_msg "$messages" "system" "$system")
    
    # Add context from history
    local context=$(get_context "$session" 10)
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        local role=$(echo "$line" | cut -d: -f1)
        local content=$(echo "$line" | cut -d' ' -f2-)
        messages=$(append_msg "$messages" "$role" "$content")
    done <<< "$context"
    
    # Add current message
    messages=$(append_msg "$messages" "user" "$msg")
    
    local iteration=0
    local response=""
    
    while [[ $iteration -lt $MAX_ITERATIONS ]]; do
        log_debug "Iteration $iteration"
        
        response=$(call_llm_with_retry "$messages")
        
        # Check for tool call using pyhelper
        local tool_result=$(python3 "$PYHELPER" extract-tool "$response" 2>/dev/null)
        
        if [[ -n "$tool_result" ]]; then
            local tool=$(json_get "$tool_result" "tool")
            local args=$(echo "$tool_result" | python3 -c "import json,sys; d=json.load(sys.stdin); print(json.dumps(d.get('arguments',{})))" 2>/dev/null)
            
            if [[ -n "$tool" ]]; then
                log_info "Tool: $tool"
                local result=$(execute_tool "$tool" "$args")
                
                # Append tool result to messages
                messages=$(append_msg "$messages" "tool" "$tool: $result")
                save_message "$session" "tool" "$tool: $result"
                ((iteration++))
                continue
            fi
        fi
        
        break
    done
    
    save_message "$session" "assistant" "$response"
    echo "$response"
}

# CLI interface
start_cli() {
    log_info "ZeroHermes V2 CLI"
    log_info "Session: $SESSION_ID"
    log_info "Type /help for commands"
    
    HISTFILE="$DATA_DIR/cli_history"
    set -o history
    
    while true; do
        read -e -p "ZeroHermes> " -r input || break
        [[ -z "$input" ]] && continue
        
        case "$input" in
            /exit) log_info "Bye!"; exit 0 ;;
            /help) cat << 'EOF'
/exit - Exit
/help - Help
/stats - Session stats
/clear - Clear session
EOF
                continue ;;
            /stats) get_session_stats "$SESSION_ID"; continue ;;
            /clear) delete_session "$SESSION_ID"; echo "Cleared"; continue ;;
        esac
        
        local resp=$(process_message "$input")
        echo ""
        echo "$resp"
        echo ""
    done
}

# Main
while [[ $# -gt 0 ]]; do
    case "$1" in
        --session) SESSION_ID="$2"; shift 2 ;;
        --debug) DEBUG="true"; shift ;;
        *) shift ;;
    esac
done

init_project
start_cli
