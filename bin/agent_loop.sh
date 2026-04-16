#!/bin/bash
# ZeroHermes V2 Agent Loop
# Version: 0.3.0

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
 local memory=$(read_persistent_memory)
 cat << EOF
You are ZeroHermes V2, a minimal AI agent.

## Tools
- shell_readonly: Execute safe shell commands
- file_read/write: File operations
- file_search: Find files
- memory_recall: Search memory

## Memory
$memory

## Instructions
Be helpful and concise. Use tools when needed.
Respond normally or use JSON for tool calls: {"tool": "name", "arguments": {...}}
EOF
}

# Process message
process_message() {
 local msg="$1"
 local session="${2:-$SESSION_ID}"
 
 log_info "Processing: $session"
 save_message "$session" "user" "$msg"
 
 local system=$(get_system_prompt)
 local context=$(get_context "$session" 10)
 
 # Build messages
 local messages='[]'
 messages=$(python3 << EOF
import json
msgs = []
msgs.append({"role": "system", "content": """$system"""})
EOF
)
 
 # Add context
 while IFS= read -r line; do
 [[ -z "$line" ]] && continue
 local role=$(echo "$line" | cut -d: -f1)
 local content=$(echo "$line" | cut -d' ' -f2-)
 messages=$(python3 << EOF
import json
m = json.loads('''$messages''')
m.append({"role": "$role", "content": """$content"""})
print(json.dumps(m))
EOF
)
 done <<< "$context"
 
 # Add current message
 messages=$(python3 << EOF
import json
m = json.loads('''$messages''')
m.append({"role": "user", "content": """$msg"""})
print(json.dumps(m))
EOF
)
 
 local iteration=0
 local response=""
 
 while [[ $iteration -lt $MAX_ITERATIONS ]]; do
 log_debug "Iteration $iteration"
 
 response=$(call_llm_with_retry "$messages")
 
 # Check for tool call
 if echo "$response" | grep -q '"tool"'; then
 local tool=$(echo "$response" | python3 -c "import json,sys; print(json.load(sys.stdin).get('tool',''))" 2>/dev/null)
 local args=$(echo "$response" | python3 -c "import json,sys; d=json.load(sys.stdin); print(json.dumps(d.get('arguments',{})))" 2>/dev/null)
 
 if [[ -n "$tool" ]]; then
 log_info "Tool: $tool"
 local result=$(execute_tool "$tool" "$args")
 
 messages=$(python3 << EOF
import json
m = json.loads('''$messages''')
m.append({"role": "tool", "content": """$result"""})
print(json.dumps(m))
EOF
)
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
