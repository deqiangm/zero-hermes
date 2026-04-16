#!/bin/bash
# ZeroHermes V2 Memory System Library
# Version: 0.3.0
# Python-based SQLite operations

source "${BASH_SOURCE[0]%/*}/common.sh"

# ============================================================================
# Message Operations (Python SQLite)
# ============================================================================

save_message() {
 local session_id="$1"
 local role="$2"
 local content="$3"
 local metadata="${4:-}"
 
 # Use pyhelper for message saving
 local result
 result=$(python3 "$PYHELPER" save-msg "$session_id" "$role" "$content" "$metadata" 2>/dev/null)
 
 # Extract lastrowid from JSON result
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
 
 python3 << EOF
import sqlite3

conn = sqlite3.connect("$DB_PATH")
cursor = conn.cursor()
cursor.execute("""
 SELECT role, content
 FROM messages
 WHERE session_id = ?
 ORDER BY timestamp DESC
 LIMIT ?
""", ("$session_id", $limit))

for row in reversed(cursor.fetchall()):
 print(f"{row[0]}: {row[1]}")
conn.close()
EOF
}

search_messages() {
 local query="$1"
 local session_id="${2:-}"
 local limit="${3:-20}"
 
 python3 << EOF
import sqlite3
import json

conn = sqlite3.connect("$DB_PATH")
cursor = conn.cursor()

sql = """
 SELECT m.id, m.session_id, m.role, m.content, m.timestamp
 FROM messages m
 JOIN messages_fts fts ON m.id = fts.rowid
 WHERE messages_fts MATCH ?
"""

params = ["$query"]
if "$session_id":
 sql += " AND m.session_id = ?"
 params.append("$session_id")

sql += " ORDER BY m.timestamp DESC LIMIT ?"
params.append($limit)

cursor.execute(sql, params)
columns = [desc[0] for desc in cursor.description]
rows = cursor.fetchall()
results = [dict(zip(columns, row)) for row in rows]
print(json.dumps(results))
conn.close()
EOF
}

# ============================================================================
# Session Management
# ============================================================================

list_sessions() {
 python3 << EOF
import sqlite3
import json

conn = sqlite3.connect("$DB_PATH")
cursor = conn.cursor()
cursor.execute("""
 SELECT 
 session_id,
 COUNT(*) as message_count,
 MIN(timestamp) as first_message,
 MAX(timestamp) as last_message
 FROM messages
 GROUP BY session_id
 ORDER BY last_message DESC
""")

columns = [desc[0] for desc in cursor.description]
rows = cursor.fetchall()
results = [dict(zip(columns, row)) for row in rows]
print(json.dumps(results))
conn.close()
EOF
}

get_session_stats() {
 local session_id="$1"
 
 python3 << EOF
import sqlite3
import json

conn = sqlite3.connect("$DB_PATH")
cursor = conn.cursor()
cursor.execute("""
 SELECT
 COUNT(*) as total_messages,
 SUM(CASE WHEN role = 'user' THEN 1 ELSE 0 END) as user_messages,
 SUM(CASE WHEN role = 'assistant' THEN 1 ELSE 0 END) as assistant_messages,
 MIN(timestamp) as first_message,
 MAX(timestamp) as last_message
 FROM messages
 WHERE session_id = ?
""", ("$session_id"))

columns = [desc[0] for desc in cursor.description]
rows = cursor.fetchall()
print(json.dumps(dict(zip(columns, rows[0]))))
conn.close()
EOF
}

delete_session() {
 local session_id="$1"
 
 python3 << EOF
import sqlite3

conn = sqlite3.connect("$DB_PATH")
cursor = conn.cursor()
cursor.execute("DELETE FROM messages WHERE session_id = ?", ("$session_id",))
deleted = cursor.rowcount
conn.commit()
conn.close()
print(deleted)
EOF
}

# ============================================================================
# Persistent Memory (USER.md)
# ============================================================================

USER_MEMORY="${USER_MEMORY:-$PROJECT_ROOT/memory/USER.md}"
FACTS_MEMORY="${FACTS_MEMORY:-$PROJECT_ROOT/memory/FACTS.md}"

init_persistent_memory() {
 mkdir -p "$(dirname "$USER_MEMORY")"
 
 [[ ! -f "$USER_MEMORY" ]] && cat > "$USER_MEMORY" << 'EOF'
# User Profile

## Preferences
- Language: English
- Communication: Concise

## Background

## Interests

## Notes
EOF
 
 [[ ! -f "$FACTS_MEMORY" ]] && cat > "$FACTS_MEMORY" << 'EOF'
# Persistent Facts

## Important Facts

## Lessons Learned

## Technical Notes
EOF
 
 log_info "Persistent memory initialized"
}

read_user_profile() { [[ -f "$USER_MEMORY" ]] && cat "$USER_MEMORY" || echo ""; }
read_persistent_memory() {
 local user=$([[ -f "$USER_MEMORY" ]] && cat "$USER_MEMORY" || echo "")
 local facts=$([[ -f "$FACTS_MEMORY" ]] && cat "$FACTS_MEMORY" || echo "")
 echo -e "$user\n\n---\n\n$facts"
}

add_fact() {
 local fact="$1"
 local category="${2:-Important Facts}"
 [[ ! -f "$FACTS_MEMORY" ]] && init_persistent_memory
 sed -i "/## $category/a - $fact" "$FACTS_MEMORY"
 log_info "Added fact: $fact"
}

# ============================================================================
# Skills
# ============================================================================

list_skills() {
 local skills_dir="${SKILLS_DIR:-$PROJECT_ROOT/skills}"
 [[ ! -d "$skills_dir" ]] && return 1
 find "$skills_dir" -name "SKILL.md" -type f 2>/dev/null | while read f; do
 local name=$(basename "$(dirname "$f")")
 local desc=$(grep -m1 "^# " "$f" 2>/dev/null | sed 's/^# //')
 echo "$name: $desc"
 done
}

# ============================================================================
# Database Operations
# ============================================================================

get_schema_version() {
 python3 << EOF
import sqlite3
conn = sqlite3.connect("$DB_PATH")
cursor = conn.cursor()
cursor.execute("SELECT COALESCE(MAX(version), 0) FROM schema_version")
print(cursor.fetchone()[0])
conn.close()
EOF
}

check_database() {
 local result=$(python3 << EOF
import sqlite3
conn = sqlite3.connect("$DB_PATH")
cursor = conn.cursor()
cursor.execute("PRAGMA integrity_check")
print(cursor.fetchone()[0])
conn.close()
EOF
)
 [[ "$result" == "ok" ]] && return 0 || return 1
}

# ============================================================================
# Main
# ============================================================================

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
 echo "ZeroHermes V2 Memory Library"
 echo "Usage: source lib/memory.sh"
fi
