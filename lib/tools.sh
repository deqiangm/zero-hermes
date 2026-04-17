#!/bin/bash
# ZeroHermes V2 Tool System
# Version: 0.3.0

source "${BASH_SOURCE[0]%/*}/common.sh"

ALLOWLIST_FILE="${ALLOWLIST_FILE:-$ETC_DIR/tools.allowlist}"
DEFAULT_TIMEOUT="${TOOL_TIMEOUT:-60}"

# Dangerous patterns
DANGEROUS_PATTERNS=("rm -rf /" "rm -rf *" "dd if=" ":(){:|:&};:" "mkfs" "chmod -R 777 /")

check_dangerous() {
 local cmd="$1"
 for p in "${DANGEROUS_PATTERNS[@]}"; do
 [[ "$cmd" == *"$p"* ]] && return 0
 done
 return 1
}

is_tool_allowed() {
 local tool="$1"
 [[ -f "$ALLOWLIST_FILE" ]] || return 1
 grep -q "^\*$" "$ALLOWLIST_FILE" && return 0
 grep -q "^$tool$" "$ALLOWLIST_FILE"
}

# Tool implementations
tool_shell_readonly() {
 local cmd="$1"
 local timeout="${2:-$DEFAULT_TIMEOUT}"
 
 check_dangerous "$cmd" && { log_error "Dangerous command blocked"; return 1; }
 
 # Allowlist of safe commands (match command at start, optionally with args)
 local safe="ls|cat|head|tail|grep|find|pwd|echo|wc|sort|uniq|awk|sed|tr|cut|date|whoami|uname|df|du|ps"
 echo "$cmd" | grep -qE "^($safe)(\s|$)" || { log_error "Command not allowed"; return 1; }
 
 timeout "$timeout" bash -c "$cmd" 2>&1
}

tool_file_read() {
 local path="$1"
 local offset="${2:-1}"
 local limit="${3:-100}"
 
 [[ "$path" =~ \.\. ]] && { log_error "Path traversal blocked"; return 1; }
 [[ ! -f "$path" ]] && { log_error "File not found"; return 1; }
 
 sed -n "${offset},$((offset+limit-1))p" "$path"
}

tool_file_write() {
 local path="$1"
 local content="$2"
 
 [[ "$path" =~ \.\. ]] && { log_error "Path traversal blocked"; return 1; }
 mkdir -p "$(dirname "$path")"
 echo "$content" > "$path"
 echo "Wrote to $path"
}

tool_file_search() {
 local pattern="$1"
 local path="${2:-.}"
 find "$path" -name "*$pattern*" -type f 2>/dev/null | head -50
}

tool_memory_recall() {
 local query="$1"
 local session="${2:-default}"
 source "$LIB_DIR/memory.sh"
 search_messages "$query" "$session"
}

# Tool dispatcher
execute_tool() {
 local tool="$1"
 local args="$2"
 local timeout="${3:-$DEFAULT_TIMEOUT}"
 
 log_debug "Executing: $tool"
 
 is_tool_allowed "$tool" || { log_error "Tool not allowed"; return 2; }
 
 case "$tool" in
 shell_readonly)
 cmd=$(json_get "$args" "command")
 tool_shell_readonly "$cmd" "$timeout"
 ;;
 file_read)
 local path=$(json_get "$args" "path")
 tool_file_read "$path"
 ;;
 file_write)
 local path=$(json_get "$args" "path")
 local content=$(json_get "$args" "content")
 tool_file_write "$path" "$content"
 ;;
 file_search)
 local pattern=$(json_get "$args" "pattern")
 tool_file_search "$pattern"
 ;;
 memory_recall)
 local query=$(json_get "$args" "query")
 tool_memory_recall "$query"
 ;;
 *)
 log_error "Unknown tool: $tool"
 return 1
 ;;
 esac
}

# Get tool schemas for LLM
get_tool_schemas() {
 cat << 'EOF'
[
 {"type": "function", "function": {"name": "shell_readonly", "description": "Execute read-only shell command", "parameters": {"type": "object", "properties": {"command": {"type": "string"}}, "required": ["command"]}}},
 {"type": "function", "function": {"name": "file_read", "description": "Read file contents", "parameters": {"type": "object", "properties": {"path": {"type": "string"}}, "required": ["path"]}}},
 {"type": "function", "function": {"name": "file_write", "description": "Write to file", "parameters": {"type": "object", "properties": {"path": {"type": "string"}, "content": {"type": "string"}}, "required": ["path", "content"]}}},
 {"type": "function", "function": {"name": "file_search", "description": "Search for files", "parameters": {"type": "object", "properties": {"pattern": {"type": "string"}}, "required": ["pattern"]}}},
 {"type": "function", "function": {"name": "memory_recall", "description": "Search memory", "parameters": {"type": "object", "properties": {"query": {"type": "string"}}, "required": ["query"]}}}
]
EOF
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
 echo "ZeroHermes V2 Tools: shell_readonly, file_read, file_write, file_search, memory_recall"
fi
