#!/bin/bash
# ZeroHermes V2 Agent Loop
# Version: 0.5.0

set -e

PROJECT_ROOT="${PROJECT_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
LIB_DIR="$PROJECT_ROOT/lib"
ETC_DIR="$PROJECT_ROOT/etc"

# Load .env BEFORE sourcing libraries (so LLM defaults are set correctly)
load_env() {
 local env_file="$PROJECT_ROOT/.env"
 if [[ -f "$env_file" ]]; then
 while IFS='=' read -r key value || [[ -n "$key" ]]; do
 [[ "$key" =~ ^[[:space:]]*# ]] && continue
 [[ -z "$key" ]] && continue
 value="${value#\"}"
 value="${value%\"}"
 value="${value#\'}"
 value="${value%\'}"
 export "$key=$value"
 done < "$env_file"
 fi
}
load_env

source "$LIB_DIR/common.sh"
source "$LIB_DIR/memory.sh"
source "$LIB_DIR/llm.sh"
source "$LIB_DIR/tools.sh"

# Configuration
MAX_ITERATIONS="${MAX_ITERATIONS:-20}"
SESSION_ID="${SESSION_ID:-default}"
DEBUG="${DEBUG:-false}"

# Ctrl+C handling
INTERRUPT_COUNT=0
INTERRUPT_TIME=0
INTERRUPT_THRESHOLD=2  # seconds

# Handle Ctrl+C
handle_interrupt() {
 local now=$(date +%s)
 local elapsed=$((now - INTERRUPT_TIME))
 
 if [[ $elapsed -lt $INTERRUPT_THRESHOLD ]]; then
 # Second Ctrl+C within threshold - exit
 echo ""
 log_info "Bye!"
 exit 0
 else
 # First Ctrl+C - just interrupt current input
 INTERRUPT_COUNT=$((INTERRUPT_COUNT + 1))
 INTERRUPT_TIME=$now
 echo ""
 echo "(Ctrl+C again within ${INTERRUPT_THRESHOLD}s to exit)"
 fi
}

# System prompt
get_system_prompt() {
 local memory=$(read_persistent_memory)
 cat << 'SYSTEMEOF'
You are ZeroHermes V2, a minimal AI agent.

## Tools
- shell_readonly: Execute safe shell commands
- file_read/write: File operations
- file_search: Find files
- memory_recall: Search memory

## Instructions
Be helpful and concise. Use tools when needed.
Respond normally or use JSON for tool calls: {"tool": "name", "arguments": {...}}
SYSTEMEOF
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
 messages=$(append_msg "$messages" "role" "$content")
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

# Process slash commands - returns 0 if handled, 1 if not
handle_slash_command() {
 local cmd="$1"
 
 case "$cmd" in
 /quit|/exit|/q)
 log_info "Bye!"
 exit 0
 ;;
 /help|/?)
 cat << 'HELPMSG'
Commands:
 /quit, /exit, /q - Exit CLI
 /help, /?        - Show this help
 /stats           - Session statistics
 /clear           - Clear session history
 /version         - Show version
 /model           - Show current model

Ctrl+C:
 Press once to interrupt current input
 Press twice within 2 seconds to exit
HELPMSG
 return 0
 ;;
 /stats)
 get_session_stats "$SESSION_ID"
 return 0
 ;;
 /clear)
 delete_session "$SESSION_ID"
 echo "Session cleared"
 return 0
 ;;
 /version)
 echo "ZeroHermes V2 CLI v0.5.0"
 return 0
 ;;
 /model)
 echo "Provider: ${LLM_PROVIDER:-unknown}"
 echo "Model: ${LLM_MODEL:-unknown}"
 return 0
 ;;
 *)
 # Unknown slash command - return 1 to let it be processed by LLM
 return 1
 ;;
 esac
}

# CLI interface
start_cli() {
 # Setup Ctrl+C handler
 trap handle_interrupt INT
 
 log_info "ZeroHermes V2 CLI"
 log_info "Session: $SESSION_ID"
 log_info "Type /help for commands"
 
 HISTFILE="$DATA_DIR/cli_history"
 set -o history
 
 while true; do
 # Reset interrupt state for each new input
 INTERRUPT_COUNT=0
 
 # Read input - will be interrupted by Ctrl+C
 if ! read -e -p "ZeroHermes> " -r input; then
 # EOF or read error
 echo ""
 continue
 fi
 
 [[ -z "$input" ]] && continue

 # Check if it's a slash command
 if [[ "$input" == /* ]]; then
 handle_slash_command "$input" && continue
 fi

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
