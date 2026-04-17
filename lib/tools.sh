#!/bin/bash
# ZeroHermes V2 Tool System
# Version: 0.4.0
# Enhanced with Hermes-style memory and skill tools

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

# ============================================================================
# Tool Implementations
# ============================================================================

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

# ============================================================================
# Memory Tools (Hermes-style)
# ============================================================================

tool_memory() {
	local action="$1"
	local target="$2"
	local content="$3"
	local old_text="$4"
	
	source "$LIB_DIR/memory.sh"
	
	case "$action" in
		add)
			memory_add "$target" "$content"
			;;
		replace)
			memory_replace "$target" "$old_text" "$content"
			;;
		remove)
			memory_remove "$target" "$content"
			;;
		read)
			memory_read "$target"
			;;
		*)
			log_error "Unknown memory action: $action"
			return 1
			;;
	esac
}

tool_memory_recall() {
	local query="$1"
	local session="${2:-default}"
	source "$LIB_DIR/memory.sh"
	search_messages "$query" "$session"
}

# ============================================================================
# Skill Tools (Hermes-style)
# ============================================================================

tool_skill_manage() {
	local action="$1"
	local name="$2"
	local args_json="$3"
	
	source "$LIB_DIR/memory.sh"
	
	case "$action" in
		list)
			skills_list "$name"  # name is actually category here
			;;
		view)
			local file_path=$(json_get "$args_json" "file_path" 2>/dev/null || echo "")
			skill_view "$name" "$file_path"
			;;
		create)
			local description=$(json_get "$args_json" "description")
			local content=$(json_get "$args_json" "content")
			local category=$(json_get "$args_json" "category" 2>/dev/null || echo "")
			skill_create "$name" "$description" "$content" "$category"
			;;
		patch)
			local old_string=$(json_get "$args_json" "old_string")
			local new_string=$(json_get "$args_json" "new_string")
			skill_patch "$name" "$old_string" "$new_string"
			;;
		delete)
			skill_delete "$name"
			;;
		*)
			log_error "Unknown skill action: $action"
			return 1
			;;
	esac
}

# ============================================================================
# Tool Dispatcher
# ============================================================================

# JSON helper (uses pyhelper for reliable parsing)
json_get() {
	local json="$1"
	local key="$2"
	
	# Use Python for JSON parsing (more reliable than regex)
	python3 -c "
import sys, json
try:
    data = json.loads(sys.argv[1])
    print(data.get(sys.argv[2], ''))
except:
    print('')
" "$json" "$key" 2>/dev/null
}

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
		path=$(json_get "$args" "path")
		tool_file_read "$path"
		;;
	file_write)
		path=$(json_get "$args" "path")
		content=$(json_get "$args" "content")
		tool_file_write "$path" "$content"
		;;
	file_search)
		pattern=$(json_get "$args" "pattern")
		tool_file_search "$pattern"
		;;
	memory)
		action=$(json_get "$args" "action")
		target=$(json_get "$args" "target")
		content=$(json_get "$args" "content")
		old_text=$(json_get "$args" "old_text")
		tool_memory "$action" "$target" "$content" "$old_text"
		;;
	memory_recall)
		query=$(json_get "$args" "query")
		tool_memory_recall "$query"
		;;
	skill_manage)
		action=$(json_get "$args" "action")
		name=$(json_get "$args" "name")
		tool_skill_manage "$action" "$name" "$args"
		;;
	*)
		log_error "Unknown tool: $tool"
		return 1
		;;
	esac
}

# ============================================================================
# Tool Schemas for LLM
# ============================================================================

get_tool_schemas() {
	cat << 'EOF'
[
 {"type": "function", "function": {"name": "shell_readonly", "description": "Execute read-only shell command", "parameters": {"type": "object", "properties": {"command": {"type": "string"}}, "required": ["command"]}}},
 {"type": "function", "function": {"name": "file_read", "description": "Read file contents", "parameters": {"type": "object", "properties": {"path": {"type": "string"}}, "required": ["path"]}}},
 {"type": "function", "function": {"name": "file_write", "description": "Write to file", "parameters": {"type": "object", "properties": {"path": {"type": "string"}, "content": {"type": "string"}}, "required": ["path", "content"]}}},
 {"type": "function", "function": {"name": "file_search", "description": "Search for files", "parameters": {"type": "object", "properties": {"pattern": {"type": "string"}}, "required": ["pattern"]}}},
 {"type": "function", "function": {"name": "memory", "description": "Manage persistent memory. Actions: add, replace, remove, read. Targets: memory (agent notes), user (user profile). Use to save facts, preferences, lessons learned. Content is injected into system prompt for future sessions.", "parameters": {"type": "object", "properties": {"action": {"type": "string", "enum": ["add", "replace", "remove", "read"]}, "target": {"type": "string", "enum": ["memory", "user"]}, "content": {"type": "string"}, "old_text": {"type": "string"}}, "required": ["action", "target"]}}},
 {"type": "function", "function": {"name": "memory_recall", "description": "Search conversation history", "parameters": {"type": "object", "properties": {"query": {"type": "string"}}, "required": ["query"]}}},
 {"type": "function", "function": {"name": "skill_manage", "description": "Manage reusable skills. Actions: list, view, create, patch, delete. Skills are procedural memory for recurring tasks. Use to save workflows, best practices, and discovered procedures.", "parameters": {"type": "object", "properties": {"action": {"type": "string", "enum": ["list", "view", "create", "patch", "delete"]}, "name": {"type": "string"}, "description": {"type": "string"}, "content": {"type": "string"}, "file_path": {"type": "string"}, "old_string": {"type": "string"}, "new_string": {"type": "string"}, "category": {"type": "string"}}, "required": ["action"]}}}
]
EOF
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
	echo "ZeroHermes V2 Tools: shell_readonly, file_read, file_write, file_search, memory, memory_recall, skill_manage"
fi
