# ZeroHermes V2

A minimal AI agent with Python-based SQLite and JSON processing.

## Features

- **Python-based storage** - No sqlite3 CLI required, uses Python's sqlite3 module
- **Multi-provider LLM support** - OpenRouter, OpenAI, Anthropic, Z.ai
- **Sandboxed tool execution** - Safe command execution with allowlists
- **Persistent memory** - Session memory with FTS5 full-text search
- **Multiple gateways** - CLI and Telegram support

## Quick Start

```bash
# Clone
git clone https://github.com/deqiangm/zero-hermes-v2.git
cd zero-hermes-v2

# Configure
cp .env.example .env
# Edit .env with your API key

# Initialize database
./bin/init_db.sh

# Run CLI
./bin/zero-hermes
```

## Architecture

```
lib/
├── common.sh   - Python-based JSON/SQLite, logging
├── memory.sh   - Session & persistent memory
├── llm.sh      - Multi-provider LLM interface
└── tools.sh    - Sandboxed tools

bin/
├── zero-hermes        - CLI entry point
├── agent_loop.sh      - Main agent loop
├── init_db.sh         - Database setup
└── telegram_gateway.sh - Telegram bot

etc/
├── config.yaml        - Configuration
├── tools.allowlist    - Allowed tools
└── migrations/        - SQL migrations
```

## Usage

### CLI Mode

```bash
# Start interactive CLI
./bin/zero-hermes

# With custom session
./bin/zero-hermes --session my-session

# Debug mode
./bin/zero-hermes --debug
```

CLI Commands:
- `/help` - Show help
- `/stats` - Session statistics
- `/clear` - Clear session memory
- `/exit` - Exit CLI

### Telegram Gateway

```bash
# Set bot token
export TG_BOT_TOKEN="your-bot-token"

# Optional: Restrict to specific chats
export TG_ALLOWED_CHATS="123456,789012"

# Run gateway
./bin/telegram_gateway.sh

# Or with arguments
./bin/telegram_gateway.sh --token "your-token" --allowed "123456"
```

Telegram Commands:
- `/start` - Start bot
- `/help` - Show help
- `/clear` - Clear session
- `/stats` - Session stats

## Configuration

### Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `LLM_PROVIDER` | LLM provider | `openrouter` |
| `LLM_MODEL` | Model name | `anthropic/claude-sonnet-4` |
| `LLM_TIMEOUT` | API timeout (seconds) | `120` |
| `LLM_MAX_RETRIES` | Max retry attempts | `3` |
| `TG_BOT_TOKEN` | Telegram bot token | - |
| `TG_ALLOWED_CHATS` | Allowed chat IDs (comma-separated) | - |

### Tools Allowlist

Edit `etc/tools.allowlist` to control which tools are available:

```
# Allow all tools
*

# Or allow specific tools
shell_readonly
file_read
file_write
file_search
memory_recall
```

## Testing

Run all tests:

```bash
./tests/test_database.sh
./tests/test_memory.sh
./tests/test_llm.sh
./tests/test_tools.sh
./tests/test_telegram_gateway.sh
```

## API

### LLM Interface

```bash
source lib/llm.sh

# Simple chat
chat "What is 2+2?"

# With custom system prompt
chat "Hello" "You are a helpful math tutor."

# Multi-provider
call_llm "$messages" "gpt-4" "openai"
```

### Memory Operations

```bash
source lib/memory.sh

# Save message
save_message "session-1" "user" "Hello"

# Get messages
get_messages "session-1" 100

# Search messages
search_messages "hello" "session-1"
```

### Tool Execution

```bash
source lib/tools.sh

# Execute safe shell command
tool_shell_readonly "ls -la"

# File operations
tool_file_read "/path/to/file" 1 100
tool_file_write "/path/to/file" "content"

# Memory recall
tool_memory_recall "search query"
```

## Database Schema

### Messages Table

```sql
CREATE TABLE messages (
    id INTEGER PRIMARY KEY,
    session_id TEXT NOT NULL,
    role TEXT NOT NULL,
    content TEXT NOT NULL,
    timestamp TEXT DEFAULT CURRENT_TIMESTAMP,
    metadata TEXT
);
```

### FTS5 Full-Text Search

```sql
CREATE VIRTUAL TABLE messages_fts USING fts5(
    content,
    content='messages',
    content_rowid='id'
);
```

## License

MIT
