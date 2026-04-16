#!/usr/bin/env python3
"""
Test suite for pyhelper.py

Run with: python3 tests/test_pyhelper.py
"""

import sys
import os
import json
import tempfile
import unittest

# Add lib to path
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', 'lib'))

from pyhelper import (
    set_db_path, get_db_path, get_db, close_db,
    db_exec, db_exec_script,
    json_get, json_build, json_merge,
    save_message, get_messages, get_context, search_messages,
    list_sessions, get_session_stats, delete_session,
    build_messages, parse_response, extract_tool_call,
    build_request, append_message, get_messages_array,
    get_schema_version, check_database
)


class TestDatabaseConnection(unittest.TestCase):
    """Test database connection and configuration."""

    def setUp(self):
        """Create a temporary database for each test."""
        # Close any existing connection first
        close_db()
        
        self.temp_db = tempfile.NamedTemporaryFile(suffix='.db', delete=False)
        self.temp_db.close()
        set_db_path(self.temp_db.name)
        
        # Create required tables (this triggers connection with new path)
        schema = '''
        CREATE TABLE IF NOT EXISTS messages (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            session_id TEXT NOT NULL,
            role TEXT NOT NULL,
            content TEXT NOT NULL,
            timestamp DATETIME DEFAULT CURRENT_TIMESTAMP,
            metadata TEXT
        );
        CREATE VIRTUAL TABLE IF NOT EXISTS messages_fts USING fts5(
            content, content='messages', content_rowid='id'
        );
        CREATE TABLE IF NOT EXISTS schema_version (
            version INTEGER PRIMARY KEY
        );
        INSERT OR IGNORE INTO schema_version VALUES (1);
        '''
        db_exec_script(schema)

    def tearDown(self):
        """Clean up temporary database."""
        close_db()
        if os.path.exists(self.temp_db.name):
            os.unlink(self.temp_db.name)

    def test_get_db_path(self):
        """Test database path resolution - returns path of active connection."""
        # get_db_path returns the override if set, or default
        # After set_db_path, get_db_path should return that path
        path = get_db_path()
        self.assertEqual(path, self.temp_db.name)

    def test_get_db(self):
        """Test database connection is created."""
        conn = get_db()
        self.assertIsNotNone(conn)

    def test_connection_reuse(self):
        """Test that connection is reused."""
        conn1 = get_db()
        conn2 = get_db()
        self.assertIs(conn1, conn2)


class TestDatabaseExec(unittest.TestCase):
    """Test database execution functions."""

    def setUp(self):
        """Create a temporary database for each test."""
        self.temp_db = tempfile.NamedTemporaryFile(suffix='.db', delete=False)
        self.temp_db.close()
        set_db_path(self.temp_db.name)
        
        schema = '''
        CREATE TABLE test_table (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT,
            value INTEGER
        );
        '''
        db_exec_script(schema)

    def tearDown(self):
        """Clean up temporary database."""
        close_db()
        if os.path.exists(self.temp_db.name):
            os.unlink(self.temp_db.name)

    def test_insert_and_fetch(self):
        """Test insert and fetch operations."""
        # Insert
        result = db_exec(
            'INSERT INTO test_table (name, value) VALUES (?, ?)',
            ('test', 42),
            fetch=False
        )
        self.assertIn('lastrowid', result)
        
        # Fetch
        result = db_exec('SELECT * FROM test_table WHERE name = ?', ('test',))
        rows = json.loads(result)
        self.assertEqual(len(rows), 1)
        self.assertEqual(rows[0]['name'], 'test')
        self.assertEqual(rows[0]['value'], 42)

    def test_error_handling(self):
        """Test error handling for invalid SQL."""
        result = db_exec('SELECT * FROM nonexistent_table')
        data = json.loads(result)
        self.assertIn('error', data)


class TestJSONUtilities(unittest.TestCase):
    """Test JSON utility functions."""

    def test_json_get_simple(self):
        """Test simple key extraction."""
        data = '{"name": "test", "value": 42}'
        self.assertEqual(json_get(data, 'name'), 'test')
        self.assertEqual(json_get(data, 'value'), '42')

    def test_json_get_nested(self):
        """Test nested key extraction."""
        data = '{"user": {"name": "Alice", "age": 30}}'
        self.assertEqual(json_get(data, 'user.name'), 'Alice')
        self.assertEqual(json_get(data, 'user.age'), '30')

    def test_json_get_array(self):
        """Test array index extraction."""
        data = '{"items": ["a", "b", "c"]}'
        self.assertEqual(json_get(data, 'items.0'), 'a')
        self.assertEqual(json_get(data, 'items.2'), 'c')

    def test_json_get_missing_key(self):
        """Test missing key returns empty string."""
        data = '{"name": "test"}'
        self.assertEqual(json_get(data, 'missing'), '')

    def test_json_build(self):
        """Test JSON object building."""
        result = json_build(name='test', value=42)
        data = json.loads(result)
        self.assertEqual(data['name'], 'test')
        self.assertEqual(data['value'], 42)

    def test_json_merge(self):
        """Test JSON merging."""
        base = '{"a": 1, "b": 2}'
        new = '{"b": 3, "c": 4}'
        result = json_merge(base, new)
        data = json.loads(result)
        self.assertEqual(data['a'], 1)
        self.assertEqual(data['b'], 3)
        self.assertEqual(data['c'], 4)


class TestMessageOperations(unittest.TestCase):
    """Test message-related operations."""

    def setUp(self):
        """Create a temporary database for each test."""
        self.temp_db = tempfile.NamedTemporaryFile(suffix='.db', delete=False)
        self.temp_db.close()
        set_db_path(self.temp_db.name)
        
        schema = '''
        CREATE TABLE IF NOT EXISTS messages (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            session_id TEXT NOT NULL,
            role TEXT NOT NULL,
            content TEXT NOT NULL,
            timestamp DATETIME DEFAULT CURRENT_TIMESTAMP,
            metadata TEXT
        );
        CREATE VIRTUAL TABLE IF NOT EXISTS messages_fts USING fts5(
            content, content='messages', content_rowid='id'
        );
        CREATE TABLE IF NOT EXISTS schema_version (
            version INTEGER PRIMARY KEY
        );
        INSERT OR IGNORE INTO schema_version VALUES (1);
        '''
        db_exec_script(schema)

    def tearDown(self):
        """Clean up temporary database."""
        close_db()
        if os.path.exists(self.temp_db.name):
            os.unlink(self.temp_db.name)

    def test_save_message(self):
        """Test saving a message."""
        result = save_message('test-session', 'user', 'Hello, world!')
        data = json.loads(result)
        self.assertIn('lastrowid', data)
        self.assertGreater(data['lastrowid'], 0)

    def test_get_messages(self):
        """Test retrieving messages."""
        # Save multiple messages
        save_message('test-session', 'user', 'Hello')
        save_message('test-session', 'assistant', 'Hi there!')
        
        result = get_messages('test-session')
        messages = json.loads(result)
        self.assertEqual(len(messages), 2)
        self.assertEqual(messages[0]['role'], 'user')
        self.assertEqual(messages[1]['role'], 'assistant')

    def test_get_context(self):
        """Test context retrieval."""
        # Save messages
        save_message('ctx-session', 'user', 'Question 1')
        save_message('ctx-session', 'assistant', 'Answer 1')
        save_message('ctx-session', 'user', 'Question 2')
        
        result = get_context('ctx-session', limit=2)
        lines = result.split('\n')
        self.assertEqual(len(lines), 2)
        # Should be in oldest-first order
        self.assertIn('Question 1', lines[0] + lines[1])

    def test_list_sessions(self):
        """Test listing sessions."""
        save_message('session-a', 'user', 'Message A')
        save_message('session-b', 'user', 'Message B')
        
        result = list_sessions()
        sessions = json.loads(result)
        self.assertEqual(len(sessions), 2)

    def test_get_session_stats(self):
        """Test session statistics."""
        save_message('stats-session', 'user', 'Q1')
        save_message('stats-session', 'assistant', 'A1')
        save_message('stats-session', 'user', 'Q2')
        
        result = get_session_stats('stats-session')
        stats = json.loads(result)[0]
        self.assertEqual(stats['total_messages'], 3)
        self.assertEqual(stats['user_messages'], 2)
        self.assertEqual(stats['assistant_messages'], 1)

    def test_delete_session(self):
        """Test deleting a session."""
        save_message('delete-session', 'user', 'To be deleted')
        
        # Verify it exists
        messages = json.loads(get_messages('delete-session'))
        self.assertEqual(len(messages), 1)
        
        # Delete
        delete_session('delete-session')
        
        # Verify it's gone
        messages = json.loads(get_messages('delete-session'))
        self.assertEqual(len(messages), 0)


class TestLLMSupport(unittest.TestCase):
    """Test LLM support functions."""

    def test_build_messages_basic(self):
        """Test basic message array building."""
        result = build_messages('You are helpful.', 'Hello!')
        messages = json.loads(result)
        self.assertEqual(len(messages), 2)
        self.assertEqual(messages[0]['role'], 'system')
        self.assertEqual(messages[1]['role'], 'user')

    def test_build_messages_with_history(self):
        """Test message array with history."""
        history = "user: Hi\nassistant: Hello!"
        result = build_messages('System', 'New message', history)
        messages = json.loads(result)
        self.assertEqual(len(messages), 4)  # system + 2 history + user

    def test_parse_response_openai(self):
        """Test parsing OpenAI-format response."""
        response = '{"choices": [{"message": {"content": "Hello there!"}}]}'
        result = parse_response(response)
        self.assertEqual(result, 'Hello there!')

    def test_parse_response_anthropic(self):
        """Test parsing Anthropic-format response."""
        response = '{"content": [{"type": "text", "text": "Hi from Claude"}]}'
        result = parse_response(response)
        self.assertEqual(result, 'Hi from Claude')

    def test_parse_response_plain(self):
        """Test parsing plain text response."""
        result = parse_response('plain text')
        self.assertEqual(result, 'plain text')

    def test_extract_tool_call_present(self):
        """Test extracting tool call from response."""
        response = '{"tool": "browser", "function": "click"}'
        result = extract_tool_call(response)
        data = json.loads(result)
        self.assertEqual(data['tool'], 'browser')

    def test_extract_tool_call_absent(self):
        """Test when no tool call present."""
        response = '{"content": "just text"}'
        result = extract_tool_call(response)
        self.assertEqual(result, '')

    def test_build_request(self):
        """Test building API request."""
        messages = '[{"role": "user", "content": "Hi"}]'
        result = build_request(messages, 'gpt-4', temperature=0.5, max_tokens=1000)
        data = json.loads(result)
        self.assertEqual(data['model'], 'gpt-4')
        self.assertEqual(data['temperature'], 0.5)
        self.assertEqual(data['max_tokens'], 1000)

    def test_append_message(self):
        """Test appending message to array."""
        messages = '[{"role": "user", "content": "Hi"}]'
        result = append_message(messages, 'assistant', 'Hello!')
        data = json.loads(result)
        self.assertEqual(len(data), 2)
        self.assertEqual(data[1]['role'], 'assistant')

    def test_get_messages_array(self):
        """Test getting messages as array."""
        # Setup
        self.temp_db = tempfile.NamedTemporaryFile(suffix='.db', delete=False)
        self.temp_db.close()
        set_db_path(self.temp_db.name)
        
        schema = '''
        CREATE TABLE IF NOT EXISTS messages (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            session_id TEXT NOT NULL,
            role TEXT NOT NULL,
            content TEXT NOT NULL,
            timestamp DATETIME DEFAULT CURRENT_TIMESTAMP,
            metadata TEXT
        );
        '''
        db_exec_script(schema)
        
        save_message('array-session', 'user', 'Question')
        save_message('array-session', 'assistant', 'Answer')
        
        result = get_messages_array('array-session')
        messages = json.loads(result)
        self.assertEqual(len(messages), 2)
        self.assertEqual(messages[0]['role'], 'user')
        
        # Cleanup
        close_db()
        os.unlink(self.temp_db.name)


class TestDatabaseUtilities(unittest.TestCase):
    """Test database utility functions."""

    def setUp(self):
        """Create a temporary database for each test."""
        self.temp_db = tempfile.NamedTemporaryFile(suffix='.db', delete=False)
        self.temp_db.close()
        set_db_path(self.temp_db.name)
        
        schema = '''
        CREATE TABLE IF NOT EXISTS schema_version (
            version INTEGER PRIMARY KEY
        );
        INSERT INTO schema_version VALUES (1);
        CREATE TABLE IF NOT EXISTS messages (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            session_id TEXT NOT NULL,
            role TEXT NOT NULL,
            content TEXT NOT NULL,
            timestamp DATETIME DEFAULT CURRENT_TIMESTAMP,
            metadata TEXT
        );
        '''
        db_exec_script(schema)

    def tearDown(self):
        """Clean up temporary database."""
        close_db()
        if os.path.exists(self.temp_db.name):
            os.unlink(self.temp_db.name)

    def test_get_schema_version(self):
        """Test schema version retrieval."""
        version = get_schema_version()
        self.assertEqual(version, 1)

    def test_check_database(self):
        """Test database integrity check."""
        result = check_database()
        self.assertTrue(result)


def run_tests():
    """Run all tests and return results."""
    loader = unittest.TestLoader()
    suite = unittest.TestSuite()
    
    suite.addTests(loader.loadTestsFromTestCase(TestDatabaseConnection))
    suite.addTests(loader.loadTestsFromTestCase(TestDatabaseExec))
    suite.addTests(loader.loadTestsFromTestCase(TestJSONUtilities))
    suite.addTests(loader.loadTestsFromTestCase(TestMessageOperations))
    suite.addTests(loader.loadTestsFromTestCase(TestLLMSupport))
    suite.addTests(loader.loadTestsFromTestCase(TestDatabaseUtilities))
    
    runner = unittest.TextTestRunner(verbosity=2)
    result = runner.run(suite)
    
    return result.wasSuccessful()


if __name__ == '__main__':
    success = run_tests()
    sys.exit(0 if success else 1)
