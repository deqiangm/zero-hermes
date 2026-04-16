#!/bin/bash
# Test: Database Initialization
# Tests that database is properly initialized with migrations

set -e

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$PROJECT_ROOT/lib/common.sh"
source "$PROJECT_ROOT/lib/memory.sh"

TEST_DB="/tmp/test_zero_hermes_$$.db"
trap "rm -f $TEST_DB" EXIT

echo "=== Testing Database Initialization ==="

# Test 1: Run migrations
echo -n "Test 1: Running migrations... "
for m in "$PROJECT_ROOT/etc/migrations"/*.sql; do
 sql_exec "$(cat "$m")" "$TEST_DB" > /dev/null 2>&1
done
echo "PASS"

# Test 2: Check schema version
echo -n "Test 2: Checking schema version... "
VERSION=$(python3 -c "
import sqlite3
conn = sqlite3.connect('$TEST_DB')
cursor = conn.cursor()
cursor.execute('SELECT COALESCE(MAX(version), 0) FROM schema_version')
print(cursor.fetchone()[0])
conn.close()
")
if [[ "$VERSION" == "4" ]]; then
 echo "PASS (version: $VERSION)"
else
 echo "FAIL (expected 4, got $VERSION)"
 exit 1
fi

# Test 3: Check tables exist
echo -n "Test 3: Checking tables exist... "
TABLES=$(python3 -c "
import sqlite3
conn = sqlite3.connect('$TEST_DB')
cursor = conn.cursor()
cursor.execute(\"SELECT name FROM sqlite_master WHERE type='table'\")
print(' '.join([r[0] for r in cursor.fetchall()]))
conn.close()
")
for t in messages messages_fts task_patterns feedback schema_version; do
 if [[ ! "$TABLES" =~ $t ]]; then
  echo "FAIL (missing table: $t)"
  exit 1
 fi
done
echo "PASS"

# Test 4: Check FTS5 trigger exists
echo -n "Test 4: Checking FTS5 triggers... "
TRIGGERS=$(python3 -c "
import sqlite3
conn = sqlite3.connect('$TEST_DB')
cursor = conn.cursor()
cursor.execute(\"SELECT name FROM sqlite_master WHERE type='trigger'\")
print(' '.join([r[0] for r in cursor.fetchall()]))
conn.close()
")
for t in messages_ai messages_ad messages_au; do
 if [[ ! "$TRIGGERS" =~ $t ]]; then
  echo "FAIL (missing trigger: $t)"
  exit 1
 fi
done
echo "PASS"

# Test 5: Check integrity
echo -n "Test 5: Database integrity check... "
INTEGRITY=$(python3 -c "
import sqlite3
conn = sqlite3.connect('$TEST_DB')
cursor = conn.cursor()
cursor.execute('PRAGMA integrity_check')
print(cursor.fetchone()[0])
conn.close()
")
if [[ "$INTEGRITY" == "ok" ]]; then
 echo "PASS"
else
 echo "FAIL (integrity: $INTEGRITY)"
 exit 1
fi

echo ""
echo "=== All Database Tests Passed ==="
