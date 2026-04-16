-- Migration 004: Optimize FTS and Add Indexes
-- Version: 4
-- Description: Optimize FTS5 and add useful indexes

-- Add indexes for common queries
CREATE INDEX IF NOT EXISTS idx_messages_session ON messages(session_id);
CREATE INDEX IF NOT EXISTS idx_messages_timestamp ON messages(timestamp);
CREATE INDEX IF NOT EXISTS idx_messages_role ON messages(role);

-- Optimize FTS (rebuild)
INSERT INTO messages_fts(messages_fts) VALUES('optimize');

-- Insert schema version record
INSERT INTO schema_version (version, description) VALUES (4, 'Optimize FTS5 and add indexes');
