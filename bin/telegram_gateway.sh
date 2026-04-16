#!/bin/bash
# ZeroHermes V2 Telegram Gateway
# Version: 0.1.0
# Listens for Telegram messages and processes them through the agent

set -e

PROJECT_ROOT="${PROJECT_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
LIB_DIR="$PROJECT_ROOT/lib"
BIN_DIR="$PROJECT_ROOT/bin"

source "$LIB_DIR/common.sh"
source "$LIB_DIR/memory.sh"
source "$LIB_DIR/llm.sh"
source "$LIB_DIR/tools.sh"

# Telegram configuration
TG_BOT_TOKEN="${TG_BOT_TOKEN:-}"
TG_API_URL="https://api.telegram.org/bot${TG_BOT_TOKEN}"
TG_TIMEOUT="${TG_TIMEOUT:-30}"
TG_OFFSET_FILE="${TG_OFFSET_FILE:-$DATA_DIR/tg_offset}"
TG_ALLOWED_CHATS="${TG_ALLOWED_CHATS:-}"  # Comma-separated chat IDs

# ============================================================================
# Telegram API Functions
# ============================================================================

tg_api() {
    local method="$1"
    local data="${2:-}"
    
    local url="$TG_API_URL/$method"
    local response
    
    if [[ -n "$data" ]]; then
        response=$(timeout "$TG_TIMEOUT" curl -s -X POST "$url" \
            -H "Content-Type: application/json" \
            -d "$data" 2>&1)
    else
        response=$(timeout "$TG_TIMEOUT" curl -s "$url" 2>&1)
    fi
    
    echo "$response"
}

tg_get_me() {
    tg_api "getMe"
}

tg_get_updates() {
    local offset="${1:-}"
    local timeout="${2:-$TG_TIMEOUT}"
    
    local data='{}'
    if [[ -n "$offset" ]]; then
        data='{"offset": '"$offset"', "timeout": '"$timeout"', "allowed_updates": ["message"]}'
    else
        data='{"timeout": '"$timeout"', "allowed_updates": ["message"]}'
    fi
    
    tg_api "getUpdates" "$data"
}

tg_send_message() {
    local chat_id="$1"
    local text="$2"
    local parse_mode="${3:-Markdown}"
    
    # Escape special characters for JSON
    local escaped_text
    escaped_text=$(python3 -c "
import json
print(json.dumps('''$text'''))
")
    
    local data='{"chat_id": '"$chat_id"', "text": '"$escaped_text"', "parse_mode": "'"$parse_mode"'"}'
    tg_api "sendMessage" "$data"
}

# ============================================================================
# Message Processing
# ============================================================================

is_chat_allowed() {
    local chat_id="$1"
    
    # If no restrictions, allow all
    [[ -z "$TG_ALLOWED_CHATS" ]] && return 0
    
    # Check if chat_id is in allowed list
    echo "$TG_ALLOWED_CHATS" | tr ',' '\n' | grep -q "^${chat_id}$"
}

process_telegram_message() {
    local chat_id="$1"
    local user_id="$2"
    local username="$3"
    local text="$4"
    
    log_info "Received from @$username (chat: $chat_id): $text"
    
    # Check if chat is allowed
    if ! is_chat_allowed "$chat_id"; then
        log_warn "Chat $chat_id not allowed"
        tg_send_message "$chat_id" "⚠️ This bot is not authorized for this chat."
        return 1
    fi
    
    # Create session ID from chat_id
    local session_id="tg_${chat_id}"
    
    # Handle commands
    case "$text" in
        /start)
            tg_send_message "$chat_id" "👋 Hello! I'm ZeroHermes V2, a minimal AI agent.\n\nCommands:\n/help - Show help\n/clear - Clear session\n/stats - Session stats"
            return 0
            ;;
        /help)
            tg_send_message "$chat_id" "*ZeroHermes V2 Help*\n\nJust send me a message and I'll process it.\n\n/commands:\n/start - Start bot\n/help - Show this help\n/clear - Clear session memory\n/stats - Show session stats"
            return 0
            ;;
        /clear)
            delete_session "$session_id"
            tg_send_message "$chat_id" "🗑️ Session cleared."
            return 0
            ;;
        /stats)
            local stats
            stats=$(get_session_stats "$session_id")
            tg_send_message "$chat_id" "📊 *Session Stats*\n\n\`$stats\`"
            return 0
            ;;
    esac
    
    # Process through agent
    local response
    response=$(process_message "$text" "$session_id")
    
    # Send response (truncate if too long)
    if [[ ${#response} -gt 4000 ]]; then
        response="${response:0:3950}...\n(truncated)"
    fi
    
    tg_send_message "$chat_id" "$response"
}

# ============================================================================
# Main Loop
# ============================================================================

get_offset() {
    [[ -f "$TG_OFFSET_FILE" ]] && cat "$TG_OFFSET_FILE" || echo "0"
}

save_offset() {
    echo "$1" > "$TG_OFFSET_FILE"
}

run_gateway() {
    log_info "Starting Telegram Gateway..."
    
    # Validate configuration
    if [[ -z "$TG_BOT_TOKEN" ]]; then
        log_error "TG_BOT_TOKEN not set"
        return 1
    fi
    
    # Test connection
    local me
    me=$(tg_get_me)
    if echo "$me" | python3 -c "import json,sys; d=json.load(sys.stdin); sys.exit(0 if d.get('ok') else 1)" 2>/dev/null; then
        local bot_name
        bot_name=$(echo "$me" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d['result'].get('username', 'unknown'))")
        log_info "Connected as @$bot_name"
    else
        log_error "Failed to connect to Telegram API"
        return 1
    fi
    
    # Main polling loop
    local offset=$(get_offset)
    log_info "Starting message polling (offset: $offset)"
    
    while true; do
        local updates
        updates=$(tg_get_updates "$((offset + 1))" "$TG_TIMEOUT")
        
        # Parse updates
        python3 << EOF 2>/dev/null || true
import json
import sys

try:
    data = json.loads('''$updates''')
    if not data.get('ok'):
        print(f"ERROR: {data.get('description', 'Unknown error')}", file=sys.stderr)
        sys.exit(1)
    
    for update in data.get('result', []):
        update_id = update.get('update_id', 0)
        
        message = update.get('message', {})
        if not message:
            continue
        
        chat_id = message.get('chat', {}).get('id', '')
        user_id = message.get('from', {}).get('id', '')
        username = message.get('from', {}).get('username', 'unknown')
        text = message.get('text', '')
        
        if not text:
            continue
        
        # Output as pipe-delimited
        print(f"{update_id}|{chat_id}|{user_id}|{username}|{text}")
        
except Exception as e:
    print(f"ERROR: {e}", file=sys.stderr)
    sys.exit(1)
EOF
        
        # Process each update
        while IFS='|' read -r update_id chat_id user_id username text; do
            [[ -z "$update_id" ]] && continue
            
            log_debug "Processing update: $update_id"
            process_telegram_message "$chat_id" "$user_id" "$username" "$text" || true
            
            # Save offset
            offset="$update_id"
            save_offset "$offset"
        done < <(python3 << EOF 2>/dev/null
import json
try:
    data = json.loads('''$updates''')
    for update in data.get('result', []):
        update_id = update.get('update_id', 0)
        message = update.get('message', {})
        chat_id = message.get('chat', {}).get('id', '')
        user_id = message.get('from', {}).get('id', '')
        username = message.get('from', {}).get('username', 'unknown')
        text = message.get('text', '')
        if text:
            print(f"{update_id}|{chat_id}|{user_id}|{username}|{text}")
except:
    pass
EOF
)
        
        # Brief pause to prevent tight loop
        sleep 1
    done
}

# ============================================================================
# Entry Point
# ============================================================================

while [[ $# -gt 0 ]]; do
    case "$1" in
        --token) TG_BOT_TOKEN="$2"; shift 2 ;;
        --allowed) TG_ALLOWED_CHATS="$2"; shift 2 ;;
        --debug) DEBUG="true"; shift ;;
        *) shift ;;
    esac
done

# Initialize
init_project
ensure_data_dir

# Run gateway
run_gateway
