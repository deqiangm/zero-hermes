# ZeroHermes V2

A minimal AI agent with Python-based SQLite and JSON processing.

## Features

- Python-based storage (no sqlite3 CLI required)
- Multi-provider LLM support
- Sandboxed tool execution
- Persistent memory

## Quick Start

```bash
# Configure
cp .env.example .env
# Edit .env with API key

# Initialize
./bin/init_db.sh

# Run
./bin/zero-hermes
```

## Architecture

```
lib/
 common.sh - Python-based JSON/SQLite
 memory.sh - Session & persistent memory
 llm.sh - Multi-provider LLM
 tools.sh - Sandboxed tools

bin/
 zero-hermes - Entry point
 agent_loop.sh - Main loop
 init_db.sh - Database setup
```

## License

MIT
