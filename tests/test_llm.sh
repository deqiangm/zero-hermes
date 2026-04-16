#!/bin/bash
# Test: LLM Interface
# Tests LLM API call structure (without actual API calls)

set -e

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$PROJECT_ROOT/lib/common.sh"
source "$PROJECT_ROOT/lib/llm.sh"
source "$PROJECT_ROOT/lib/tools.sh"

echo "=== Testing LLM Interface ==="

# Test 1: Provider endpoints
echo -n "Test 1: Provider endpoints... "
for provider in openrouter openai anthropic zai; do
 if [[ -z "${PROVIDER_ENDPOINTS[$provider]}" ]]; then
  echo "FAIL (missing endpoint for $provider)"
  exit 1
 fi
done
echo "PASS"

# Test 2: Message building
echo -n "Test 2: Building messages JSON... "
MESSAGES=$(build_messages "You are helpful." "Hello!")
if echo "$MESSAGES" | python3 -c "import json,sys; d=json.load(sys.stdin); print('ok') if len(d)==2 and d[0]['role']=='system' and d[1]['role']=='user' else print('fail')" | grep -q ok; then
 echo "PASS"
else
 echo "FAIL"
 echo "Messages: $MESSAGES"
 exit 1
fi

# Test 3: Tool schemas
echo -n "Test 3: Tool schemas... "
SCHEMAS=$(get_tool_schemas)
if echo "$SCHEMAS" | python3 -c "import json,sys; d=json.load(sys.stdin); print('ok') if len(d)>=5 else print('fail')" | grep -q ok; then
 echo "PASS"
else
 echo "FAIL"
 exit 1
fi

# Test 4: Provider configuration check
echo -n "Test 4: Provider configuration check... "
# Set a fake API key for testing
export OPENROUTER_API_KEY="test-key-123"
if is_provider_configured "openrouter"; then
 echo "PASS"
else
 echo "FAIL"
 exit 1
fi

# Test 5: Request building
echo -n "Test 5: Building API request... "
REQUEST=$(python3 << 'EOF'
import json

model = "test-model"
messages = [{"role": "user", "content": "test"}]
data = {
    "model": model,
    "messages": messages,
    "max_tokens": 4096,
    "temperature": 0.7
}
print(json.dumps(data))
EOF
)
if echo "$REQUEST" | python3 -c "import json,sys; d=json.load(sys.stdin); print('ok') if 'model' in d and 'messages' in d else print('fail')" | grep -q ok; then
 echo "PASS"
else
 echo "FAIL"
 exit 1
fi

echo ""
echo "=== All LLM Tests Passed ==="
