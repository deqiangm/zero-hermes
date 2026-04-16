#!/bin/bash
# Test: Tool Execution
# Tests tool dispatcher, safety checks, and tool implementations

set -e

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$PROJECT_ROOT/lib/common.sh"
source "$PROJECT_ROOT/lib/tools.sh"

# Create temp allowlist
ALLOWLIST_FILE="/tmp/test_allowlist_$$.txt"
trap "rm -f $ALLOWLIST_FILE" EXIT

echo "=== Testing Tool Execution ==="

# Test 1: Dangerous command detection
echo -n "Test 1: Dangerous command detection... "
if check_dangerous "rm -rf /"; then
 echo "PASS (detected)"
else
 echo "FAIL (should detect)"
 exit 1
fi

if check_dangerous "ls -la"; then
 echo "FAIL (false positive)"
 exit 1
else
 echo "PASS (safe command)"
fi

# Test 2: Shell readonly - safe commands
echo -n "Test 2: Shell readonly (safe)... "
echo "*" > "$ALLOWLIST_FILE"
export ALLOWLIST_FILE
OUTPUT=$(tool_shell_readonly "echo hello" 2>&1)
if [[ "$OUTPUT" == "hello" ]]; then
 echo "PASS"
else
 echo "FAIL (got: $OUTPUT)"
fi

# Test 3: Shell readonly - blocked commands
echo -n "Test 3: Shell readonly (blocked)... "
# Use a command that's not in safe list but not dangerous
OUTPUT=$(tool_shell_readonly "python3 -c 'print(1)'" 2>&1 || true)
if echo "$OUTPUT" | grep -qi "not allowed"; then
 echo "PASS"
else
 echo "FAIL (should block non-safe commands, got: $OUTPUT)"
 exit 1
fi

# Test 4: File read
echo -n "Test 4: File read... "
TEST_FILE="/tmp/test_file_$$.txt"
echo "test content" > "$TEST_FILE"
trap "rm -f $TEST_FILE $ALLOWLIST_FILE" EXIT
OUTPUT=$(tool_file_read "$TEST_FILE" 1 10)
if [[ "$OUTPUT" == "test content" ]]; then
 echo "PASS"
else
 echo "FAIL (got: $OUTPUT)"
 exit 1
fi

# Test 5: File write
echo -n "Test 5: File write... "
TEST_WRITE="/tmp/test_write_$$.txt"
trap "rm -f $TEST_FILE $TEST_WRITE $ALLOWLIST_FILE" EXIT
tool_file_write "$TEST_WRITE" "written content" > /dev/null
if [[ -f "$TEST_WRITE" ]] && grep -q "written content" "$TEST_WRITE"; then
 echo "PASS"
else
 echo "FAIL"
 exit 1
fi

# Test 6: Path traversal prevention
echo -n "Test 6: Path traversal prevention... "
OUTPUT=$(tool_file_read "../../../etc/passwd" 2>&1 || true)
if echo "$OUTPUT" | grep -qi "traversal\|not found"; then
 echo "PASS"
else
 echo "FAIL (should block path traversal, got: $OUTPUT)"
 exit 1
fi

# Test 7: Tool schemas
echo -n "Test 7: Tool schemas available... "
SCHEMAS=$(get_tool_schemas)
TOOL_COUNT=$(echo "$SCHEMAS" | python3 -c "import json,sys; print(len(json.load(sys.stdin)))")
if [[ "$TOOL_COUNT" -ge 5 ]]; then
 echo "PASS ($TOOL_COUNT tools)"
else
 echo "FAIL (expected 5+, got $TOOL_COUNT)"
 exit 1
fi

# Cleanup
rm -f "$TEST_FILE" "$TEST_WRITE" "$ALLOWLIST_FILE"

echo ""
echo "=== All Tool Tests Passed ==="
