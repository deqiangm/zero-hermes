#!/bin/bash
# Test: Refactored Memory Operations
# Tests list_sessions, get_session_stats, delete_session, get_schema_version, check_database

set -e

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$PROJECT_ROOT/lib/common.sh"
source "$PROJECT_ROOT/lib/memory.sh"

TEST_DB="/tmp/test_memory_refactored_$$.db"
export DB_PATH="$TEST_DB"
trap "rm -f $TEST_DB" EXIT

echo "=== Testing Refactored Memory Operations ==="

# Initialize database
for m in "$PROJECT_ROOT/etc/migrations"/*.sql; do
 sql_exec "$(cat "$m")" "$TEST_DB" > /dev/null 2>&1
done

# Add test data using pyhelper
echo -n "Setup: Adding test messages... "
python3 "$PYHELPER" save-msg "session-1" "user" "Hello from session 1" > /dev/null
python3 "$PYHELPER" save-msg "session-1" "assistant" "Hi there!" > /dev/null
python3 "$PYHELPER" save-msg "session-2" "user" "Hello from session 2" > /dev/null
echo "DONE"

# Test 1: list_sessions
echo -n "Test 1: list_sessions... "
SESSIONS=$(list_sessions)
SESSION_COUNT=$(python3 "$PYHELPER" json-get "$SESSIONS" "length" 2>/dev/null || echo "0")
# Alternative: count by checking if session-1 and session-2 appear
if echo "$SESSIONS" | grep -q "session-1" && echo "$SESSIONS" | grep -q "session-2"; then
 echo "PASS"
else
 echo "FAIL (sessions: $SESSIONS)"
 exit 1
fi

# Test 2: get_session_stats
echo -n "Test 2: get_session_stats... "
STATS=$(get_session_stats "session-1")
if echo "$STATS" | grep -q '"total_messages"'; then
 echo "PASS"
else
 echo "FAIL (stats: $STATS)"
 exit 1
fi

# Test 3: delete_session
echo -n "Test 3: delete_session... "
RESULT=$(delete_session "session-2")
echo "PASS"

# Verify session-2 is gone
echo -n "Test 3b: Verify deletion... "
SESSIONS_AFTER=$(list_sessions)
if echo "$SESSIONS_AFTER" | grep -q "session-2"; then
 echo "FAIL (session-2 still exists)"
 exit 1
else
 echo "PASS"
fi

# Test 4: get_schema_version
echo -n "Test 4: get_schema_version... "
VERSION=$(get_schema_version)
if [[ "$VERSION" =~ ^[0-9]+$ ]]; then
 echo "PASS (version: $VERSION)"
else
 echo "FAIL (version: $VERSION)"
 exit 1
fi

# Test 5: check_database
echo -n "Test 5: check_database... "
if check_database; then
 echo "PASS"
else
 echo "FAIL"
 exit 1
fi

echo ""
echo "=== All Refactored Memory Tests Passed ==="
