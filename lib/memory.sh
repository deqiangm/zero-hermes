#!/bin/bash
# ZeroHermes V2 Memory System Library
# Version: 0.4.0
# Enhanced with Hermes-style curated memory capabilities

source "${BASH_SOURCE[0]%/*}/common.sh"

# ============================================================================
# Memory File Paths (Hermes-style)
# ============================================================================

MEMORY_DIR="${MEMORY_DIR:-$PROJECT_ROOT/memory}"
MEMORY_FILE="$MEMORY_DIR/MEMORY.md"
USER_FILE="$MEMORY_DIR/USER.md"

# Character limits (matching Hermes defaults)
MEMORY_CHAR_LIMIT="${MEMORY_CHAR_LIMIT:-2200}"
USER_CHAR_LIMIT="${USER_CHAR_LIMIT:-1375}"

# Entry delimiter (Hermes uses §)
ENTRY_DELIMITER="§"

# ============================================================================
# Hermes-style Curated Memory Operations
# ============================================================================

# Initialize memory directory and files
init_memory() {
	mkdir -p "$MEMORY_DIR"
	
	# Create MEMORY.md (agent's personal notes)
	if [[ ! -f "$MEMORY_FILE" ]]; then
		cat > "$MEMORY_FILE" << 'EOF'
# Agent Memory

## Environment Facts

## Project Conventions

## Tool Quirks

## Lessons Learned
EOF
	fi
	
	# Create USER.md (user profile)
	if [[ ! -f "$USER_FILE" ]]; then
		cat > "$USER_FILE" << 'EOF'
# User Profile

## Preferences

## Communication Style

## Workflow Habits

## Notes
EOF
	fi
	
	log_info "Memory system initialized"
}

# Read memory file content
memory_read() {
	local target="${1:-memory}"  # memory or user
	
	local file
	case "$target" in
		memory) file="$MEMORY_FILE" ;;
		user) file="$USER_FILE" ;;
		*) log_error "Invalid target: $target"; return 1 ;;
	esac
	
	if [[ -f "$file" ]]; then
		cat "$file"
	else
		echo ""
	fi
}

# Add entry to memory
memory_add() {
	local target="$1"      # memory or user
	local content="$2"
	
	local file
	case "$target" in
		memory) file="$MEMORY_FILE" ;;
		user) file="$USER_FILE" ;;
		*) log_error "Invalid target: $target"; return 1 ;;
	esac
	
	# Ensure file exists
	[[ ! -f "$file" ]] && init_memory
	
	# Scan for injection patterns
	if _scan_memory_content "$content"; then
		log_error "Content blocked: contains potential injection pattern"
		return 1
	fi
	
	# Check character limit
	local current_chars=$(wc -c < "$file" 2>/dev/null || echo 0)
	local new_chars=${#content}
	local limit
	case "$target" in
		memory) limit="$MEMORY_CHAR_LIMIT" ;;
		user) limit="$USER_CHAR_LIMIT" ;;
	esac
	
	if (( current_chars + new_chars > limit )); then
		log_warn "Memory limit reached, consider removing old entries"
	fi
	
	# Append entry with delimiter
	{
		echo ""
		echo "$ENTRY_DELIMITER $content"
	} >> "$file"
	
	log_info "Added entry to $target memory"
}

# Replace entry in memory (find by substring)
memory_replace() {
	local target="$1"
	local old_text="$2"
	local new_text="$3"
	
	local file
	case "$target" in
		memory) file="$MEMORY_FILE" ;;
		user) file="$USER_FILE" ;;
		*) log_error "Invalid target: $target"; return 1 ;;
	esac
	
	[[ ! -f "$file" ]] && { log_error "Memory file not found"; return 1; }
	
	# Scan new content
	if _scan_memory_content "$new_text"; then
		log_error "New content blocked: contains potential injection pattern"
		return 1
	fi
	
	# Find and replace (with delimiter)
	local escaped_old=$(printf '%s\n' "$old_text" | sed 's/[][\.*^$()+?{|\\]/\\&/g')
	local escaped_new=$(printf '%s\n' "$new_text" | sed 's/[&/\]/\\&/g')
	
	if grep -q "$escaped_old" "$file"; then
		sed -i "s/$escaped_old/$escaped_new/g" "$file"
		log_info "Replaced entry in $target memory"
	else
		log_error "Entry not found: $old_text"
		return 1
	fi
}

# Remove entry from memory (find by substring)
memory_remove() {
	local target="$1"
	local old_text="$2"
	
	local file
	case "$target" in
		memory) file="$MEMORY_FILE" ;;
		user) file="$USER_FILE" ;;
		*) log_error "Invalid target: $target"; return 1 ;;
	esac
	
	[[ ! -f "$file" ]] && { log_error "Memory file not found"; return 1; }
	
	# Find and remove (including delimiter line)
	local escaped_old=$(printf '%s\n' "$old_text" | sed 's/[][\.*^$()+?{|\\]/\\&/g')
	
	if grep -q "$escaped_old" "$file"; then
		# Remove the line containing the text and its preceding delimiter
		sed -i "/$escaped_old/d" "$file"
		# Clean up orphaned delimiters
		sed -i '/^§$/d' "$file"
		log_info "Removed entry from $target memory"
	else
		log_error "Entry not found: $old_text"
		return 1
	fi
}

# Get memory for system prompt injection (frozen snapshot)
get_memory_snapshot() {
	local memory_content=""
	local user_content=""
	
	if [[ -f "$MEMORY_FILE" ]]; then
		memory_content=$(cat "$MEMORY_FILE")
	fi
	if [[ -f "$USER_FILE" ]]; then
		user_content=$(cat "$USER_FILE")
	fi
	
	# Return formatted for system prompt
	echo "══════════════════════════════════════════════ MEMORY (agent notes) [${#memory_content}/$MEMORY_CHAR_LIMIT chars] ══════════════════════════════════════════════"
	echo "$memory_content"
	echo ""
	echo "══════════════════════════════════════════════ USER PROFILE [${#user_content}/$USER_CHAR_LIMIT chars] ══════════════════════════════════════════════"
	echo "$user_content"
}

# ============================================================================
# Security: Scan for injection patterns
# ============================================================================

_scan_memory_content() {
	local content="$1"
	
	# Check for invisible unicode
	if echo "$content" | grep -qP '[\x{200b}\x{200c}\x{200d}\x{2060}\x{feff}\x{202a}-\x{202e}]'; then
		return 0  # Blocked
	fi
	
	# Check for injection patterns
	local patterns=(
		"ignore.*previous.*instructions"
		"ignore.*all.*instructions"
		"you are now"
		"disregard.*instructions"
		"system prompt override"
		"curl.*\$.*KEY\|curl.*\$.*TOKEN"
		"wget.*\$.*KEY\|wget.*\$.*TOKEN"
	)
	
	for pattern in "${patterns[@]}"; do
		if echo "$content" | grep -qiE "$pattern"; then
			return 0  # Blocked
		fi
	done
	
	return 1  # Not blocked
}

# ============================================================================
# Skills Management (Hermes-style)
# ============================================================================

SKILLS_DIR="${SKILLS_DIR:-$PROJECT_ROOT/skills}"
MAX_SKILL_NAME_LENGTH=64
MAX_SKILL_DESC_LENGTH=1024

# List all skills with metadata
skills_list() {
	local category="${1:-}"
	local search_dir="$SKILLS_DIR"
	
	[[ -n "$category" ]] && search_dir="$SKILLS_DIR/$category"
	[[ ! -d "$search_dir" ]] && { echo "[]"; return 0; }
	
	# Use Python for JSON output (avoid subshell variable scope issues)
	python3 << PYEOF
import json
import os
import re

skills = []
for root, dirs, files in os.walk("$search_dir"):
    if "SKILL.md" in files:
        skill_file = os.path.join(root, "SKILL.md")
        name = os.path.basename(root)
        desc = ""
        with open(skill_file, 'r') as f:
            content = f.read()
            # Try frontmatter
            m = re.search(r'^description:\s*(.+)$', content, re.M)
            if m:
                desc = m.group(1).strip()
            else:
                # Fall back to first heading
                m = re.search(r'^#\s+(.+)$', content, re.M)
                if m:
                    desc = m.group(1).strip()
        skills.append({"name": name, "description": desc})
print(json.dumps(skills))
PYEOF
}

# View skill content
skill_view() {
	local name="$1"
	local file_path="${2:-}"
	
	# Search for skill in all subdirectories
	local skill_file=$(find "$SKILLS_DIR" -path "*/$name/SKILL.md" -type f 2>/dev/null | head -1)
	
	[[ -z "$skill_file" ]] && { log_error "Skill not found: $name"; return 1; }
	
	local skill_dir=$(dirname "$skill_file")
	
	if [[ -n "$file_path" ]]; then
		# View linked file
		local target_file="$skill_dir/$file_path"
		[[ ! -f "$target_file" ]] && { log_error "File not found: $file_path"; return 1; }
		cat "$target_file"
	else
		# View main skill file
		cat "$skill_file"
	fi
}

# Create new skill
skill_create() {
	local name="$1"
	local description="$2"
	local content="${3:-}"
	local category="${4:-}"
	
	# Validate name length
	[[ ${#name} -gt $MAX_SKILL_NAME_LENGTH ]] && { log_error "Skill name too long (max $MAX_SKILL_NAME_LENGTH chars)"; return 1; }
	
	local skill_dir="$SKILLS_DIR/$name"
	[[ -n "$category" ]] && skill_dir="$SKILLS_DIR/$category/$name"
	
	mkdir -p "$skill_dir"
	
	# Create SKILL.md with frontmatter
	cat > "$skill_dir/SKILL.md" << EOF
---
name: $name
description: $description
version: 1.0.0
---

# $name

$description

## Instructions

$content

## Pitfalls

## Verification
EOF
	
	log_info "Created skill: $name"
}

# Patch skill content
skill_patch() {
	local name="$1"
	local old_string="$2"
	local new_string="$3"
	
	local skill_file="$SKILLS_DIR/$name/SKILL.md"
	[[ ! -f "$skill_file" ]] && { log_error "Skill not found: $name"; return 1; }
	
	# Use sed for in-place replacement
	local escaped_old=$(printf '%s\n' "$old_string" | sed 's/[][\.*^$()+?{|\\]/\\&/g')
	local escaped_new=$(printf '%s\n' "$new_text" | sed 's/[&/\]/\\&/g')
	
	sed -i "s/$escaped_old/$escaped_new/g" "$skill_file"
	log_info "Patched skill: $name"
}

# Delete skill
skill_delete() {
	local name="$1"
	
	# Search for skill in all subdirectories
	local skill_file=$(find "$SKILLS_DIR" -path "*/$name/SKILL.md" -type f 2>/dev/null | head -1)
	[[ -z "$skill_file" ]] && { log_error "Skill not found: $name"; return 1; }
	
	local skill_dir=$(dirname "$skill_file")
	rm -rf "$skill_dir"
	log_info "Deleted skill: $name"
}

# Helper: Extract description from SKILL.md
_extract_skill_description() {
	local skill_file="$1"
	
	# Try frontmatter first
	if grep -q "^description:" "$skill_file" 2>/dev/null; then
		grep "^description:" "$skill_file" | head -1 | sed 's/^description: *//'
		return
	fi
	
	# Fall back to first heading
	grep -m1 "^# " "$skill_file" 2>/dev/null | sed 's/^# //'
}

# ============================================================================
# Message Operations (Python SQLite)
# ============================================================================

save_message() {
	local session_id="$1"
	local role="$2"
	local content="$3"
	local metadata="${4:-}"
	
	local result
	result=$(python3 "$PYHELPER" save-msg "$session_id" "$role" "$content" "$metadata" 2>/dev/null)
	
	if [[ -n "$result" ]]; then
		python3 "$PYHELPER" json-get "$result" lastrowid 2>/dev/null
	fi
}

get_messages() {
	local session_id="$1"
	local limit="${2:-100}"
	
	python3 "$PYHELPER" get-msgs "$session_id" "$limit"
}

get_context() {
	local session_id="$1"
	local limit="${2:-10}"
	
	python3 "$PYHELPER" get-context "$session_id" "$limit"
}

search_messages() {
	local query="$1"
	local session_id="${2:-}"
	local limit="${3:-20}"
	
	python3 "$PYHELPER" search "$query" "$session_id" "$limit"
}

# ============================================================================
# Session Management
# ============================================================================

list_sessions() {
	python3 "$PYHELPER" list-sessions
}

get_session_stats() {
	local session_id="$1"
	python3 "$PYHELPER" session-stats "$session_id"
}

delete_session() {
	local session_id="$1"
	python3 "$PYHELPER" delete-session "$session_id"
}

# ============================================================================
# Legacy Support (backward compatibility)
# ============================================================================

USER_MEMORY="$USER_FILE"
FACTS_MEMORY="$MEMORY_FILE"

init_persistent_memory() { init_memory; }
read_user_profile() { memory_read user; }
read_persistent_memory() { get_memory_snapshot; }
add_fact() { memory_add memory "$1"; }

# ============================================================================
# Database Operations
# ============================================================================

get_schema_version() {
	python3 "$PYHELPER" schema-version
}

check_database() {
	local result
	result=$(python3 "$PYHELPER" check-db)
	[[ "$result" == "ok" ]] && return 0 || return 1
}

# ============================================================================
# Main
# ============================================================================

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
	echo "ZeroHermes Memory Library v0.4.0"
	echo "Usage: source lib/memory.sh"
	echo ""
	echo "Memory Commands:"
	echo "  memory_add <target> <content>      - Add entry (target: memory|user)"
	echo "  memory_replace <target> <old> <new>"
	echo "  memory_remove <target> <text>"
	echo "  memory_read <target>               - Read memory file"
	echo "  get_memory_snapshot                - Get formatted snapshot"
	echo ""
	echo "Skill Commands:"
	echo "  skills_list [category]             - List skills"
	echo "  skill_view <name> [file]           - View skill content"
	echo "  skill_create <name> <desc> [content]"
	echo "  skill_delete <name>"
fi
