# ZeroHermes

A minimal AI agent with Python-based SQLite and JSON processing.

## Features

- **Python helper module** - Centralized pyhelper.py for all database/JSON operations
- **Multi-provider LLM support** - OpenRouter, OpenAI, Anthropic, Z.ai
- **Sandboxed tool execution** - Safe command execution with allowlists
- **Persistent memory** - Session memory with FTS5 full-text search
- **Multiple gateways** - CLI and Telegram support
- **No embedded Python** - Clean shell scripts, all Python centralized

## Quick Start

### One-Line Install (Recommended)

```bash
# Linux and macOS
curl -fsSL https://raw.githubusercontent.com/deqiangm/zero-hermes/main/install.sh | bash
```

This will:
- Detect your platform (Linux/macOS, Intel/ARM)
- Install to `~/.zerohermes`
- Initialize the database
- Add `zero-hermes` to your PATH
- Create a `.env` template for your API keys

After installation:
```bash
# 1. Add your API key
nano ~/.zerohermes/.env

# 2. Reload shell
source ~/.bashrc  # or ~/.zshrc

# 3. Run
zero-hermes
```

### Manual Install

```bash
# Clone
git clone https://github.com/deqiangm/zero-hermes.git
cd zero-hermes

# Configure
cp .env.example .env
# Edit .env with your API key

# Initialize database
./bin/init_db.sh

# Run CLI
./bin/zero-hermes
```

### Custom Install Location

```bash
# Install to custom directory
ZEROTHERMES_HOME=~/my-agent curl -fsSL https://raw.githubusercontent.com/deqiangm/zero-hermes/main/install.sh | bash
```

## Architecture

```
lib/
├── pyhelper.py    - Central Python helper (460 lines)
├── common.sh      - Shell wrappers for pyhelper (244 lines)
├── memory.sh      - Session & persistent memory (155 lines)
├── llm.sh         - Multi-provider LLM interface (135 lines)
└── tools.sh       - Sandboxed tools (129 lines)

bin/
├── zero-hermes    - CLI entry point
├── agent_loop.sh  - Main agent loop (145 lines)
├── init_db.sh     - Database setup
└── telegram_gateway.sh - Telegram bot (273 lines)

Total: ~1096 lines shell, ~460 lines Python
```

## pyhelper API

The `lib/pyhelper.py` module provides all database and JSON operations via a CLI interface:

### Database Operations

```bash
# Execute SQL query (returns JSON)
python3 lib/pyhelper.py --db /path/to/db.db db-exec "SELECT * FROM messages"

# Check database integrity
python3 lib/pyhelper.py --db /path/to/db.db check-db

# Get schema version
python3 lib/pyhelper.py --db /path/to/db.db schema-version
```

### Message Operations

```bash
# Save message
python3 lib/pyhelper.py --db /path/to/db.db save-msg "session-1" "user" "Hello world"

# Get messages (last N)
python3 lib/pyhelper.py --db /path/to/db.db get-msgs "session-1" 100

# Search messages (FTS5)
python3 lib/pyhelper.py --db /path/to/db.db search "query" "session-1" 10

# Get context window for LLM
python3 lib/pyhelper.py --db /path/to/db.db get-context "session-1" 4000 "system prompt"

# Session management
python3 lib/pyhelper.py --db /path/to/db.db session-stats "session-1"
python3 lib/pyhelper.py --db /path/to/db.db delete-session "session-1"
python3 lib/pyhelper.py --db /path/to/db.db list-sessions
```

### LLM Support

```bash
# Build OpenAI-compatible message array
python3 lib/pyhelper.py build-msgs "system prompt" "user message" '[{"role":"user","content":"history"}]'

# Parse LLM response
python3 lib/pyhelper.py parse-response '{"choices":[{"message":{"content":"Hello"}}]}'

# Extract tool call from response
python3 lib/pyhelper.py extract-tool '{"choices":[{"message":{"tool_calls":[{"function":{"name":"shell","arguments":"{\"cmd\":\"ls\"}"}}]}}]}'

# Build API request
python3 lib/pyhelper.py build-request '[{"role":"user","content":"Hi"}]' "gpt-4" 0.7 4096

# Append message to array
python3 lib/pyhelper.py append-message '[{"role":"user","content":"Hi"}]' "assistant" "Hello!"

# Get messages as JSON array
python3 lib/pyhelper.py get-messages-array "session-1" 100
```

### JSON Utilities

```bash
# Extract value from JSON
python3 lib/pyhelper.py json-get '{"path":"/file.txt"}' "path"
# Output: /file.txt

# JSON validation and formatting
python3 lib/pyhelper.py json-parse '{"key":"value"}'
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
export TG_BOT_TOKEN="***"

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

# Python unit tests
python3 tests/test_pyhelper.py
```

## Shell Library API

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

# Session management
list_sessions
get_session_stats "session-1"
delete_session "session-1"
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

### JSON Utilities

```bash
source lib/common.sh

# Extract JSON value
json_get '{"path":"/file.txt"}' "path"
# Output: /file.txt

# Execute SQL
sql_exec "SELECT * FROM messages LIMIT 10"

# Execute SQL with JSON output
sql_exec_json "SELECT * FROM messages LIMIT 10"
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

## Code Statistics

| Component | Lines |
|-----------|-------|
| Shell libraries (lib/*.sh) | 663 |
| Shell binaries (bin/*.sh) | 433 |
| **Total Shell** | **1096** |
| Python helper (lib/pyhelper.py) | 460 |
| **Total Python** | **460** |

## License

MIT
