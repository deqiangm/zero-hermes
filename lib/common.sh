#!/bin/bash
# ZeroHermes V2 Common Utilities Library
# Version: 0.3.0
# Enhanced with Python fallback for JSON processing

set -o pipefail

# ============================================================================
# Global Configuration
# ============================================================================

PROJECT_ROOT="${PROJECT_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
DATA_DIR="${DATA_DIR:-$PROJECT_ROOT/var}"
ETC_DIR="${ETC_DIR:-$PROJECT_ROOT/etc}"
LIB_DIR="${LIB_DIR:-$PROJECT_ROOT/lib}"
BIN_DIR="${BIN_DIR:-$PROJECT_ROOT/bin}"
DB_PATH="${DB_PATH:-$DATA_DIR/state.db}"
LOG_LEVEL="${LOG_LEVEL:-INFO}"
LOG_FILE="${LOG_FILE:-$DATA_DIR/logs/zero-hermes.log}"

# ============================================================================
# JSON Processing (Python fallback)
# ============================================================================

# Use Python for JSON if jq not available
_json_parse() {
 local data="$1"
 local query="$2"
 
 if command -v jq >/dev/null 2>&1; then
 echo "$data" | jq -r "$query"
 else
 python3 -c "
import json, sys
data = json.loads(sys.stdin.read())
query = '$query'
# Simple jq-like query parsing
if query.startswith('.'):
 query = query[1:]
parts = query.split('.')
result = data
for part in parts:
 if not part: continue
 if part.endswith('[]'):
 part = part[:-2]
 result = result.get(part, [])
 elif '[' in part and part.endswith(']'):
 key = part[:part.index('[')]
 idx = int(part[part.index('[')+1:part.index(']')])
 result = result.get(key, [])[idx]
 else:
 result = result.get(part, '') if isinstance(result, dict) else ''
if isinstance(result, list):
 for item in result:
 print(item if isinstance(item, str) else json.dumps(item))
else:
 print(result if isinstance(result, str) else json.dumps(result))
" <<< "$data" 2>/dev/null
 fi
}

# Quick JSON field extraction
json_get() {
 local data="$1"
 local field="$2"
 _json_parse "$data" ".$field"
}

# ============================================================================
# Logging Functions
# ============================================================================

export RED='\033[0;31m'
export GREEN='\033[0;32m'
export YELLOW='\033[0;33m'
export BLUE='\033[0;34m'
export NC='\033[0m'

declare -A LOG_LEVELS=([DEBUG]=0 [INFO]=1 [WARN]=2 [ERROR]=3)

_log() {
 local level="$1"; shift
 local message="$*"
 local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
 
 if [[ ${LOG_LEVELS[$level]} -ge ${LOG_LEVELS[$LOG_LEVEL]} ]]; then
 case "$level" in
 DEBUG) echo -e "${BLUE}[$timestamp] DEBUG: $message${NC}" ;;
 INFO) echo -e "${GREEN}[$timestamp] INFO: $message${NC}" ;;
 WARN) echo -e "${YELLOW}[$timestamp] WARN: $message${NC}" ;;
 ERROR) echo -e "${RED}[$timestamp] ERROR: $message${NC}" ;;
 esac >&2
 
 if [[ -d "$(dirname "$LOG_FILE")" ]]; then
 echo "[$timestamp] $level: $message" >> "$LOG_FILE"
 fi
 fi
}

log_debug() { _log DEBUG "$*"; }
log_info() { _log INFO "$*"; }
log_warn() { _log WARN "$*"; }
log_error() { _log ERROR "$*"; }

# ============================================================================
# SQLite Alternative (Python-based)
# ============================================================================

# Execute SQL using Python sqlite3
sql_exec() {
 local sql="$1"
 local db="${2:-$DB_PATH}"
 
 python3 << EOF
import sqlite3
import sys

db_path = "$db"
sql = """$sql"""

try:
 conn = sqlite3.connect(db_path)
 cursor = conn.cursor()
 cursor.executescript(sql)
 conn.commit()
 
 # If it's a SELECT, return results
 if sql.strip().upper().startswith('SELECT'):
 cursor.execute(sql)
 rows = cursor.fetchall()
 if rows:
 for row in rows:
 print('|'.join(str(c) if c else '' for c in row))
 else:
 print("Changes:", conn.total_changes)
 
 conn.close()
except Exception as e:
 print(f"ERROR: {e}", file=sys.stderr)
 sys.exit(1)
EOF
}

# Execute SQL and return JSON
sql_exec_json() {
 local sql="$1"
 local db="${2:-$DB_PATH}"
 
 python3 << EOF
import sqlite3
import json

db_path = "$db"
sql = """$sql"""

conn = sqlite3.connect(db_path)
cursor = conn.cursor()

# Get column names
cursor.execute(sql)
columns = [desc[0] for desc in cursor.description] if cursor.description else []
rows = cursor.fetchall()

results = [dict(zip(columns, row)) for row in rows]
print(json.dumps(results))
conn.close()
EOF
}

# ============================================================================
# Utility Functions
# ============================================================================

command_exists() { command -v "$1" >/dev/null 2>&1; }

check_dependencies() {
 local missing=()
 for cmd in curl python3; do
 if ! command_exists "$cmd"; then
 missing+=("$cmd")
 fi
 done
 
 if [[ ${#missing[@]} -gt 0 ]]; then
 log_error "Missing dependencies: ${missing[*]}"
 return 1
 fi
 return 0
}

ensure_data_dir() { mkdir -p "$DATA_DIR/logs" "$DATA_DIR/sessions"; }

sql_escape() {
 local str="$1"
 echo "${str//\'/\'\'}"
}

generate_id() { date +%s%N | md5sum | head -c 16; }
get_timestamp() { date -u +"%Y-%m-%dT%H:%M:%SZ"; }

# ============================================================================
# Initialization
# ============================================================================

init_project() {
 log_info "Initializing ZeroHermes V2..."
 
 if ! check_dependencies; then return 1; fi
 ensure_data_dir
 
 if [[ ! -f "$DB_PATH" ]]; then
 log_info "Database not found, initializing..."
 init_database
 fi
 
 log_info "ZeroHermes V2 initialized successfully"
 return 0
}

init_database() {
 log_info "Running database migrations..."
 for migration in "$ETC_DIR/migrations"/*.sql; do
 if [[ -f "$migration" ]]; then
 log_debug "Applying migration: $(basename "$migration")"
 sql_exec "$(cat "$migration")"
 fi
 done
 log_info "Database initialized at $DB_PATH"
}

# ============================================================================
# Cleanup
# ============================================================================

cleanup() {
 local exit_code=$?
 log_info "Shutting down (exit code: $exit_code)..."
 jobs -p | xargs -r kill 2>/dev/null
 rm -f /tmp/zero-hermes-$$*
 exit $exit_code
}

setup_signal_handlers() { trap cleanup EXIT INT TERM; }

# ============================================================================
# Main
# ============================================================================

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
 echo "ZeroHermes V2 Common Library"
 echo "Usage: source lib/common.sh"
 echo ""
 echo "Features:"
 echo " - Python-based JSON processing (jq fallback)"
 echo " - Python-based SQLite execution"
 echo " - Logging with colors"
fi
