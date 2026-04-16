#!/usr/bin/env python3
"""
ZeroHermes Python Helper
A single-file module for core operations: database, JSON, messages.

Usage:
 python3 pyhelper.py [--db PATH] <command> [args...]

Options:
 --db PATH Override database path (default: $DB_PATH or $DATA_DIR/state.db)

Commands:
 db-exec <sql> [params_json] - Execute SQL, return JSON results
 save-msg <session> <role> <content> [metadata] - Save message
 get-msgs <session> [limit] - Get messages for session
 search <query> [session] [limit] - Search messages (FTS5)
 json-get <json> <path> - Extract value from JSON
 json-build <key=value> ... - Build JSON object
 build-msgs <system> <user> [history_json] - Build messages array
 parse-response <response> - Parse LLM API response
 extract-tool <response> - Extract tool call from response
"""

import sqlite3
import json
import sys
import os
from pathlib import Path
from typing import Optional, Any, List, Dict

# ============================================================================
# Configuration
# ============================================================================

PROJECT_ROOT = os.environ.get('PROJECT_ROOT', str(Path(__file__).parent.parent))
DATA_DIR = os.environ.get('DATA_DIR', f'{PROJECT_ROOT}/var')
DEFAULT_DB_PATH = os.environ.get('DB_PATH', f'{DATA_DIR}/state.db')

# ============================================================================
# Database Connection (Lazy Init)
# ============================================================================

_db_conn: Optional[sqlite3.Connection] = None
_db_path_override: Optional[str] = None

def set_db_path(path: str):
    """Override database path."""
    global _db_path_override
    _db_path_override = path

def get_db_path() -> str:
    """Get current database path."""
    return _db_path_override if _db_path_override else DEFAULT_DB_PATH

def get_db() -> sqlite3.Connection:
    """Get database connection (lazy initialization, reused)."""
    global _db_conn
    db_path = get_db_path()
    if _db_conn is None or _db_path_override:
        # Ensure directory exists
        Path(db_path).parent.mkdir(parents=True, exist_ok=True)
        _db_conn = sqlite3.connect(db_path)
        _db_conn.row_factory = sqlite3.Row
    return _db_conn

def close_db():
    """Close database connection."""
    global _db_conn
    if _db_conn:
        _db_conn.close()
        _db_conn = None

# ============================================================================
# Database Operations
# ============================================================================

def db_exec(sql: str, params: tuple = (), fetch: bool = True) -> str:
    """Execute SQL and return results as JSON."""
    conn = get_db()
    cur = conn.cursor()
    
    try:
        cur.execute(sql, params)
        
        if fetch and cur.description:
            rows = [dict(r) for r in cur.fetchall()]
            return json.dumps(rows)
        else:
            conn.commit()
            return json.dumps({
                'lastrowid': cur.lastrowid,
                'changes': conn.total_changes
            })
    except Exception as e:
        return json.dumps({'error': str(e)})

def db_exec_script(sql: str) -> str:
    """Execute multiple SQL statements."""
    conn = get_db()
    cur = conn.cursor()
    try:
        cur.executescript(sql)
        conn.commit()
        return json.dumps({'success': True, 'changes': conn.total_changes})
    except Exception as e:
        return json.dumps({'error': str(e)})

# ============================================================================
# JSON Utilities
# ============================================================================

def json_get(data: str, path: str) -> str:
    """Extract value from JSON using simple dot path (e.g., 'user.name')."""
    try:
        obj = json.loads(data) if isinstance(data, str) else data
        for key in path.split('.'):
            if not key:
                continue
            if key.isdigit():
                obj = obj[int(key)]
            elif isinstance(obj, dict):
                obj = obj.get(key, '')
            elif isinstance(obj, list) and int(key) < len(obj):
                obj = obj[int(key)]
            else:
                return ''
        return obj if isinstance(obj, str) else json.dumps(obj)
    except Exception:
        return ''

def json_build(**kwargs) -> str:
    """Build JSON object from key-value pairs."""
    return json.dumps(kwargs)

def json_merge(base: str, new: str) -> str:
    """Merge two JSON objects."""
    obj = json.loads(base) if base else {}
    obj.update(json.loads(new) if new else {})
    return json.dumps(obj)

# ============================================================================
# Message Operations
# ============================================================================

def save_message(session: str, role: str, content: str, metadata: str = '') -> str:
    """Save a message to the database."""
    return db_exec(
        'INSERT INTO messages (session_id, role, content, metadata) VALUES (?, ?, ?, ?)',
        (session, role, content, metadata),
        fetch=False
    )

def get_messages(session: str, limit: int = 100) -> str:
    """Get messages for a session."""
    return db_exec(
        'SELECT id, role, content, timestamp, metadata FROM messages WHERE session_id = ? ORDER BY timestamp ASC LIMIT ?',
        (session, limit)
    )

def get_context(session: str, limit: int = 10) -> str:
    """Get recent context (role: content format)."""
    rows = json.loads(db_exec(
        'SELECT role, content FROM messages WHERE session_id = ? ORDER BY timestamp DESC LIMIT ?',
        (session, limit)
    ))
    # Return in reverse order (oldest first)
    result = []
    for row in reversed(rows):
        result.append(f"{row['role']}: {row['content']}")
    return '\n'.join(result)

def search_messages(query: str, session: str = '', limit: int = 20) -> str:
    """Search messages using FTS5."""
    sql = '''
    SELECT m.id, m.session_id, m.role, m.content, m.timestamp
    FROM messages m
    JOIN messages_fts fts ON m.id = fts.rowid
    WHERE messages_fts MATCH ?
    '''
    params = [query]
    
    if session:
        sql += ' AND m.session_id = ?'
        params.append(session)
    
    sql += ' ORDER BY m.timestamp DESC LIMIT ?'
    params.append(limit)
    
    return db_exec(sql, tuple(params))

def list_sessions() -> str:
    """List all sessions with stats."""
    return db_exec('''
    SELECT 
    session_id,
    COUNT(*) as message_count,
    MIN(timestamp) as first_message,
    MAX(timestamp) as last_message
    FROM messages
    GROUP BY session_id
    ORDER BY last_message DESC
    ''')

def get_session_stats(session: str) -> str:
    """Get statistics for a session."""
    return db_exec('''
    SELECT
    COUNT(*) as total_messages,
    SUM(CASE WHEN role = 'user' THEN 1 ELSE 0 END) as user_messages,
    SUM(CASE WHEN role = 'assistant' THEN 1 ELSE 0 END) as assistant_messages,
    MIN(timestamp) as first_message,
    MAX(timestamp) as last_message
    FROM messages
    WHERE session_id = ?
    ''', (session,))

def delete_session(session: str) -> str:
    """Delete all messages in a session."""
    return db_exec('DELETE FROM messages WHERE session_id = ?', (session,), fetch=False)

# ============================================================================
# LLM Support
# ============================================================================

def build_messages(system: str, user: str, history: str = '') -> str:
    """Build messages array for LLM API."""
    messages = []
    
    if system:
        messages.append({'role': 'system', 'content': system})
    
    if history:
        try:
            for line in history.strip().split('\n'):
                if ': ' in line:
                    role, content = line.split(': ', 1)
                    messages.append({'role': role, 'content': content})
        except Exception:
            pass
    
    messages.append({'role': 'user', 'content': user})
    return json.dumps(messages)

def parse_response(response: str) -> str:
    """Parse LLM API response to extract content."""
    try:
        data = json.loads(response)
        
        # OpenAI/OpenRouter format
        if 'choices' in data:
            return data['choices'][0]['message']['content']
        
        # Anthropic format
        if 'content' in data:
            for item in data['content']:
                if item.get('type') == 'text':
                    return item.get('text', '')
        
        return ''
    except Exception:
        return response

def extract_tool_call(response: str) -> str:
    """Extract tool call from response if present."""
    try:
        # Check if response contains tool call JSON
        data = json.loads(response)
        if 'tool' in data or 'function' in data:
            return json.dumps(data)
        return ''
    except Exception:
        return ''

# ============================================================================
# Database Utilities
# ============================================================================

def get_schema_version() -> int:
    """Get current database schema version."""
    result = db_exec('SELECT COALESCE(MAX(version), 0) as version FROM schema_version')
    rows = json.loads(result)
    return rows[0]['version'] if rows else 0

def check_database() -> bool:
    """Check database integrity."""
    result = db_exec('PRAGMA integrity_check')
    rows = json.loads(result)
    return rows[0].get('integrity_check', 'error') == 'ok'

# ============================================================================
# CLI Entry Point
# ============================================================================

def print_usage():
    print(__doc__)

def main():
    if len(sys.argv) < 2:
        print_usage()
        sys.exit(1)
    
    # Parse --db option if present
    args = sys.argv[1:]
    if args and args[0] == '--db':
        if len(args) < 2:
            print("Error: --db requires a path argument", file=sys.stderr)
            sys.exit(1)
        set_db_path(args[1])
        args = args[2:]
    
    if not args:
        print_usage()
        sys.exit(1)
    
    cmd = args[0]
    args = args[1:]
    
    try:
        result = ''
        
        if cmd == 'db-exec':
            sql = args[0]
            params = json.loads(args[1]) if len(args) > 1 else ()
            result = db_exec(sql, tuple(params))
        
        elif cmd == 'db-script':
            sql = args[0]
            result = db_exec_script(sql)
        
        elif cmd == 'save-msg':
            session, role, content = args[0], args[1], args[2]
            metadata = args[3] if len(args) > 3 else ''
            result = save_message(session, role, content, metadata)
        
        elif cmd == 'get-msgs':
            session = args[0]
            limit = int(args[1]) if len(args) > 1 else 100
            result = get_messages(session, limit)
        
        elif cmd == 'get-context':
            session = args[0]
            limit = int(args[1]) if len(args) > 1 else 10
            result = get_context(session, limit)
        
        elif cmd == 'search':
            query = args[0]
            session = args[1] if len(args) > 1 else ''
            limit = int(args[2]) if len(args) > 2 else 20
            result = search_messages(query, session, limit)
        
        elif cmd == 'list-sessions':
            result = list_sessions()
        
        elif cmd == 'session-stats':
            session = args[0]
            result = get_session_stats(session)
        
        elif cmd == 'delete-session':
            session = args[0]
            result = delete_session(session)
        
        elif cmd == 'json-get':
            data, path = args[0], args[1]
            result = json_get(data, path)
        
        elif cmd == 'json-build':
            kwargs = {}
            for arg in args:
                if '=' in arg:
                    k, v = arg.split('=', 1)
                    kwargs[k] = v
            result = json_build(**kwargs)
        
        elif cmd == 'build-msgs':
            system = args[0] if args else ''
            user = args[1] if len(args) > 1 else ''
            history = args[2] if len(args) > 2 else ''
            result = build_messages(system, user, history)
        
        elif cmd == 'parse-response':
            response = args[0]
            result = parse_response(response)
        
        elif cmd == 'extract-tool':
            response = args[0]
            result = extract_tool_call(response)
        
        elif cmd == 'schema-version':
            result = str(get_schema_version())
        
        elif cmd == 'check-db':
            result = 'ok' if check_database() else 'error'
        
        else:
            print(f"Unknown command: {cmd}", file=sys.stderr)
            print_usage()
            sys.exit(1)
        
        if result:
            print(result)
        
    except Exception as e:
        print(json.dumps({'error': str(e)}), file=sys.stderr)
        sys.exit(1)

if __name__ == '__main__':
    main()
