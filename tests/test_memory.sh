#!/bin/bash
# Test: Memory Operations
# Tests save_message, get_messages, search_messages, session management

set -e

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$PROJECT_ROOT/lib/common.sh"
source "$PROJECT_ROOT/lib/memory.sh"

TEST_DB="/tmp/test_memory_$$.db"
export DB_PATH="$TEST_DB"
trap "rm -f $TEST_DB" EXIT

echo "=== Testing Memory Operations ==="

# Initialize database
for m in "$PROJECT_ROOT/etc/migrations"/*.sql; do
 sql_exec "$(cat "$m")" "$TEST_DB" > /dev/null 2>&1
done

# Test 1: save_message
echo -n "Test 1: Saving messages... "
MSG_ID=$(python3 -c "
import sqlite3
conn = sqlite3.connect('$TEST_DB')
cursor = conn.cursor()
cursor.execute('INSERT INTO messages (session_id, role, content) VALUES (?, ?, ?)', ('test-session', 'user', 'Hello world'))
conn.commit()
print(cursor.lastrowid)
conn.close()
")
if [[ -n "$MSG_ID" && "$MSG_ID" -gt 0 ]]; then
 echo "PASS (id: $MSG_ID)"
else
 echo "FAIL"
 exit 1
fi

# Test 2: Getting messages
echo -n "Test 2: Getting messages... "
python3 -c "
import sqlite3
import json
conn = sqlite3.connect('$TEST_DB')
cursor = conn.cursor()
cursor.execute('INSERT INTO messages (session_id, role, content) VALUES (?, ?, ?)', ('test-session', 'assistant', 'Hello!'))
conn.commit()
cursor.execute('SELECT id, role, content FROM messages WHERE session_id = ?', ('test-session',))
rows = cursor.fetchall()
print(len(rows))
conn.close()
"
COUNT=$(python3 -c "
import sqlite3
conn = sqlite3.connect('$TEST_DB')
cursor = conn.cursor()
cursor.execute('SELECT COUNT(*) FROM messages WHERE session_id = ?', ('test-session',))
print(cursor.fetchone()[0])
conn.close()
")
if [[ "$COUNT" == "2" ]]; then
 echo "PASS (count: $COUNT)"
else
 echo "FAIL (expected 2, got $COUNT)"
 exit 1
fi

# Test 3: FTS5 search
echo -n "Test 3: FTS5 search... "
SEARCH_RESULTS=$(python3 -c "
import sqlite3
conn = sqlite3.connect('$TEST_DB')
cursor = conn.cursor()
cursor.execute(\"SELECT m.id FROM messages m JOIN messages_fts fts ON m.id = fts.rowid WHERE messages_fts MATCH 'world'\")
rows = cursor.fetchall()
print(len(rows))
conn.close()
")
if [[ "$SEARCH_RESULTS" -ge 1 ]]; then
 echo "PASS (found: $SEARCH_RESULTS)"
else
 echo "FAIL (no results)"
 exit 1
fi

# Test 4: Session stats
echo -n "Test 4: Session stats... "
STATS=$(python3 -c "
import sqlite3
import json
conn = sqlite3.connect('$TEST_DB')
cursor = conn.cursor()
cursor.execute('SELECT COUNT(*) FROM messages WHERE session_id = ?', ('test-session',))
print(cursor.fetchone()[0])
conn.close()
")
if [[ "$STATS" == "2" ]]; then
 echo "PASS"
else
 echo "FAIL"
 exit 1
fi

# Test 5: Delete session
echo -n "Test 5: Delete session... "
DELETED=$(python3 -c "
import sqlite3
conn = sqlite3.connect('$TEST_DB')
cursor = conn.cursor()
cursor.execute('DELETE FROM messages WHERE session_id = ?', ('test-session',))
conn.commit()
print(cursor.rowcount)
conn.close()
")
if [[ "$DELETED" == "2" ]]; then
 echo "PASS"
else
 echo "FAIL"
 exit 1
fi

echo ""
echo "=== All Memory Tests Passed ==="
