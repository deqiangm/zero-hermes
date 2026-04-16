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

# Get pyhelper path (used by JSON and SQLite functions)
PYHELPER="${LIB_DIR}/pyhelper.py"

# ============================================================================
# JSON Processing (via pyhelper)
# ============================================================================

# Use Python for JSON (pyhelper-based)
_json_parse() {
 local data="$1"
 local query="$2"
 
 # Convert jq-style path to pyhelper format
 local path="${query#.}"
 path="${path//[]/}"
 
 python3 "$PYHELPER" json-get "$data" "$path" 2>/dev/null
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
# SQLite Operations (via pyhelper)
# ============================================================================

# Execute SQL and return pipe-delimited results (legacy format)
sql_exec() {
 local sql="$1"
 local db="${2:-$DB_PATH}"
 
 # Use pyhelper for SQL execution with --db option for custom path
 local result
 if [[ "$db" == "$DB_PATH" ]]; then
 result=$(python3 "$PYHELPER" db-script "$sql" 2>/dev/null)
 else
 result=$(python3 "$PYHELPER" --db "$db" db-script "$sql" 2>/dev/null)
 fi
 
 # Check for errors
 if echo "$result" | grep -q '"error"'; then
 echo "$result" | python3 "$PYHELPER" json-get "$result" error >&2
 return 1
 fi
 
 # For SELECT queries, re-execute with db-exec to get data
 if echo "$sql" | grep -qi '^[[:space:]]*SELECT'; then
 if [[ "$db" == "$DB_PATH" ]]; then
 result=$(python3 "$PYHELPER" db-exec "$sql")
 else
 result=$(python3 "$PYHELPER" --db "$db" db-exec "$sql")
 fi
 if [[ -n "$result" ]] && [[ "$result" != "[]" ]]; then
 # Convert JSON to pipe-delimited format for legacy compatibility
 local lines
 lines=$(python3 -c "
import json
rows = json.loads('$result')
for row in rows:
 print('|'.join(str(v) if v is not None else '' for v in row.values()))
")
 echo "$lines"
 fi
 else
 # For non-SELECT, show changes
 echo "$result"
 fi
}

# Execute SQL and return JSON
sql_exec_json() {
 local sql="$1"
 local db="${2:-$DB_PATH}"
 
 if [[ "$db" == "$DB_PATH" ]]; then
 python3 "$PYHELPER" db-exec "$sql"
 else
 python3 "$PYHELPER" --db "$db" db-exec "$sql"
 fi
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
