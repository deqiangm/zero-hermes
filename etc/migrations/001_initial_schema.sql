-- Migration 001: Initial Schema
-- Version: 1
-- Description: Core tables for messages, FTS5 search, and triggers

-- Schema version tracking
CREATE TABLE IF NOT EXISTS schema_version (
 version INTEGER PRIMARY KEY,
 applied_at TEXT DEFAULT CURRENT_TIMESTAMP,
 description TEXT
);

-- Initial schema (version 1)
CREATE TABLE IF NOT EXISTS messages (
 id INTEGER PRIMARY KEY AUTOINCREMENT,
 session_id TEXT NOT NULL,
 role TEXT NOT NULL, -- 'user', 'assistant', 'tool'
 content TEXT NOT NULL,
 timestamp TEXT DEFAULT CURRENT_TIMESTAMP,
 metadata TEXT -- JSON for additional data
);

-- FTS5 full-text search
CREATE VIRTUAL TABLE IF NOT EXISTS messages_fts USING fts5(
 content,
 content='messages',
 content_rowid='id'
);

-- Triggers to keep FTS in sync
CREATE TRIGGER IF NOT EXISTS messages_ai AFTER INSERT ON messages BEGIN
 INSERT INTO messages_fts(rowid, content) VALUES (new.id, new.content);
END;

CREATE TRIGGER IF NOT EXISTS messages_ad AFTER DELETE ON messages BEGIN
 INSERT INTO messages_fts(messages_fts, rowid, content) 
 VALUES('delete', old.id, old.content);
END;

CREATE TRIGGER IF NOT EXISTS messages_au AFTER UPDATE ON messages BEGIN
 INSERT INTO messages_fts(messages_fts, rowid, content) 
 VALUES('delete', old.id, old.content);
 INSERT INTO messages_fts(rowid, content) VALUES (new.id, new.content);
END;

-- Insert schema version record
INSERT INTO schema_version (version, description) VALUES (1, 'Initial schema with messages and FTS5');
