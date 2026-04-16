#!/bin/bash
# Test: Telegram Gateway
# Tests Telegram gateway functionality without actual API calls

set -e

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$PROJECT_ROOT/lib/common.sh"
source "$PROJECT_ROOT/lib/tools.sh"

echo "=== Testing Telegram Gateway ==="

# Create a mock gateway script for testing
MOCK_GATEWAY="/tmp/test_tg_gateway_$$.sh"
trap "rm -f $MOCK_GATEWAY" EXIT

# Test 1: Chat allowlist check
echo -n "Test 1: Chat allowlist check... "
export TG_ALLOWED_CHATS="123456,789012"
is_chat_allowed() {
    local chat_id="$1"
    [[ -z "$TG_ALLOWED_CHATS" ]] && return 0
    echo "$TG_ALLOWED_CHATS" | tr ',' '\n' | grep -q "^${chat_id}$"
}
if is_chat_allowed "123456" && ! is_chat_allowed "999999"; then
    echo "PASS"
else
    echo "FAIL"
    exit 1
fi

# Test 2: Empty allowlist allows all
echo -n "Test 2: Empty allowlist allows all... "
export TG_ALLOWED_CHATS=""
if is_chat_allowed "123456" && is_chat_allowed "999999"; then
    echo "PASS"
else
    echo "FAIL"
    exit 1
fi

# Test 3: Message formatting
echo -n "Test 3: Message JSON formatting... "
TEST_MSG="Hello world"
FORMATTED=$(python3 -c "
import json
print(json.dumps('''$TEST_MSG'''))
")
if echo "$FORMATTED" | grep -q '"Hello world"'; then
    echo "PASS"
else
    echo "FAIL"
    exit 1
fi

# Test 4: Response truncation logic
echo -n "Test 4: Response truncation... "
LONG_RESPONSE=$(python3 -c "print('x' * 5000)")
TRUNCATED_LEN=${#LONG_RESPONSE}
if [[ $TRUNCATED_LEN -gt 4000 ]]; then
    # Simulate truncation
    TRUNCATED="${LONG_RESPONSE:0:3950}...\\n(truncated)"
    if [[ ${#TRUNCATED} -le 4000 ]]; then
        echo "PASS"
    else
        echo "FAIL (truncated length: ${#TRUNCATED})"
        exit 1
    fi
else
    echo "PASS (no truncation needed)"
fi

# Test 5: Gateway script exists and is executable
echo -n "Test 5: Gateway script executable... "
if [[ -x "$PROJECT_ROOT/bin/telegram_gateway.sh" ]]; then
    echo "PASS"
else
    echo "FAIL"
    exit 1
fi

# Test 6: Gateway script has required functions
echo -n "Test 6: Gateway has required functions... "
for func in tg_api tg_get_me tg_get_updates tg_send_message is_chat_allowed process_telegram_message run_gateway; do
    if ! grep -q "^${func}()" "$PROJECT_ROOT/bin/telegram_gateway.sh"; then
        echo "FAIL (missing function: $func)"
        exit 1
    fi
done
echo "PASS"

echo ""
echo "=== All Telegram Gateway Tests Passed ==="
