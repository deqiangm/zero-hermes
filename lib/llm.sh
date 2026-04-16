#!/bin/bash
# ZeroHermes V2 LLM Interface
# Version: 0.3.0

source "${BASH_SOURCE[0]%/*}/common.sh"

DEFAULT_PROVIDER="${LLM_PROVIDER:-openrouter}"
DEFAULT_MODEL="${LLM_MODEL:-anthropic/claude-sonnet-4}"
DEFAULT_TIMEOUT="${LLM_TIMEOUT:-120}"
DEFAULT_MAX_RETRIES="${LLM_MAX_RETRIES:-3}"
DEFAULT_TEMPERATURE="${LLM_TEMPERATURE:-0.7}"

# Provider endpoints
declare -A PROVIDER_ENDPOINTS=(
 [openrouter]="https://openrouter.ai/api/v1/chat/completions"
 [openai]="https://api.openai.com/v1/chat/completions"
 [anthropic]="https://api.anthropic.com/v1/messages"
 [zai]="https://api.z.ai/v1/chat/completions"
)

get_api_key() {
 local provider="$1"
 case "$provider" in
 openrouter) echo "${OPENROUTER_API_KEY:-}" ;;
 openai) echo "${OPENAI_API_KEY:-}" ;;
 anthropic) echo "${ANTHROPIC_API_KEY:-}" ;;
 zai) echo "${ZAI_API_KEY:-}" ;;
 esac
}

is_provider_configured() {
 local provider="$1"
 local api_key=$(get_api_key "$provider")
 [[ -n "$api_key" ]]
}

# Build messages JSON using pyhelper
build_messages() {
 local system="$1"
 local user="$2"
 local history="${3:-}"
 
 python3 "$PYHELPER" build-msgs "$system" "$user" "$history"
}

# Call LLM API
call_llm() {
 local messages="$1"
 local model="${2:-$DEFAULT_MODEL}"
 local provider="${3:-$DEFAULT_PROVIDER}"
 local timeout="${4:-$DEFAULT_TIMEOUT}"
 
 if ! is_provider_configured "$provider"; then
 log_error "Provider $provider not configured"
 return 1
 fi
 
 local api_key=$(get_api_key "$provider")
 local endpoint="${PROVIDER_ENDPOINTS[$provider]}"
 
 log_debug "Calling $provider: $model"
 
 # Build request using pyhelper
 local request=$(python3 "$PYHELPER" build-request "$messages" "$model" "$DEFAULT_TEMPERATURE" 4096)
 
 # Make API call
 local response
 response=$(timeout "$timeout" curl -s -w "\n%{http_code}" \
 -X POST "$endpoint" \
 -H "Authorization: Bearer $api_key" \
 -H "Content-Type: application/json" \
 -d "$request" 2>&1)
 
 local http_code=$(echo "$response" | tail -1)
 local content=$(echo "$response" | head -n -1)
 
 if [[ "$http_code" -lt 200 ]] || [[ "$http_code" -ge 300 ]]; then
 log_error "API failed: HTTP $http_code"
 return 1
 fi
 
 # Extract content using pyhelper
 python3 "$PYHELPER" parse-response "$content"
}

# Call with retry
call_llm_with_retry() {
 local messages="$1"
 local model="${2:-$DEFAULT_MODEL}"
 local provider="${3:-$DEFAULT_PROVIDER}"
 local max_retries="${4:-$DEFAULT_MAX_RETRIES}"
 
 local attempt=1
 local delay=1
 
 while [[ $attempt -le $max_retries ]]; do
 local result
 if result=$(call_llm "$messages" "$model" "$provider"); then
 echo "$result"
 return 0
 fi
 
 delay=$((delay * 2))
 log_warn "Retry $attempt/$max_retries in ${delay}s"
 sleep "$delay"
 ((attempt++))
 done
 
 log_error "Failed after $max_retries attempts"
 return 1
}

# Simple chat
chat() {
 local message="$1"
 local system="${2:-You are a helpful AI assistant.}"
 
 local messages=$(build_messages "$system" "$message")
 call_llm_with_retry "$messages"
}

# Format messages for API
format_messages() {
 local user_message="$1"
 local system_message="${2:-}"
 
 build_messages "$system_message" "$user_message"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
 echo "ZeroHermes V2 LLM Library"
 echo "Providers: openrouter, openai, anthropic, zai"
 echo ""
 echo "Usage: chat <message>"
fi
