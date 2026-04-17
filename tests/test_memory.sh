#!/bin/bash
# Test: Memory Operations
# Tests save_message, get_messages, search_messages, session management

set -e

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$PROJECT_ROOT/lib/common.sh"
source "$PROJECT_ROOT/lib/memory.sh"

TEST_DB="/tmp/test_memory_$$.db"
export DB_PATH="$TEST_DB"
export PYHELPER="$PROJECT_ROOT/lib/pyhelper.py"
trap "rm -f $TEST_DB" EXIT

echo "=== Testing Memory Operations ==="

# Initialize database
for m in "$PROJECT_ROOT/etc/migrations"/*.sql; do
 python3 "$PYHELPER" --db "$TEST_DB" db-script "$(cat "$m")" > /dev/null 2>&1
done

# Test 1: save_message (via pyhelper)
echo -n "Test 1: Saving messages... "
RESULT=$(python3 "$PYHELPER" --db "$TEST_DB" save-msg 'test-session' 'user' 'Hello world')
MSG_ID=$(python3 "$PYHELPER" json-get "$RESULT" lastrowid)
if [[ -n "$MSG_ID" && "$MSG_ID" -gt 0 ]]; then
 echo "PASS (id: $MSG_ID)"
else
 echo "FAIL"
 exit 1
fi

# Test 2: Getting messages
echo -n "Test 2: Getting messages... "
python3 "$PYHELPER" --db "$TEST_DB" save-msg 'test-session' 'assistant' 'Hello!' > /dev/null
MSGS=$(python3 "$PYHELPER" --db "$TEST_DB" get-msgs 'test-session' 100)
COUNT=$(echo "$MSGS" | python3 -c "import json,sys; print(len(json.load(sys.stdin)))")
if [[ "$COUNT" == "2" ]]; then
 echo "PASS (count: $COUNT)"
else
 echo "FAIL (expected 2, got $COUNT)"
 exit 1
fi

# Test 3: FTS5 search
echo -n "Test 3: FTS5 search... "
SEARCH_RESULTS=$(python3 "$PYHELPER" --db "$TEST_DB" search 'world' 'test-session' 10)
FOUND=$(echo "$SEARCH_RESULTS" | python3 -c "import json,sys; print(len(json.load(sys.stdin)))")
if [[ "$FOUND" -ge 1 ]]; then
 echo "PASS (found: $FOUND)"
else
 echo "FAIL (no results)"
 exit 1
fi

# Test 4: Session stats
echo -n "Test 4: Session stats... "
STATS=$(python3 "$PYHELPER" --db "$TEST_DB" session-stats 'test-session')
TOTAL=$(echo "$STATS" | python3 -c "import json,sys; data=json.load(sys.stdin); print(data[0]['total_messages'])")
if [[ "$TOTAL" == "2" ]]; then
 echo "PASS"
else
 echo "FAIL (expected 2, got $TOTAL)"
 exit 1
fi

# Test 5: Delete session
echo -n "Test 5: Delete session... "
DEL_RESULT=$(python3 "$PYHELPER" --db "$TEST_DB" delete-session 'test-session')
CHANGES=$(python3 "$PYHELPER" json-get "$DEL_RESULT" changes)
if [[ -n "$CHANGES" ]]; then
 echo "PASS"
else
 echo "FAIL"
 exit 1
fi

echo ""
echo "=== All Memory Tests Passed ==="
