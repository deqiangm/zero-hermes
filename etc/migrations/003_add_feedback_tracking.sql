-- Migration 003: Add Feedback Tracking
-- Version: 3
-- Description: Track user feedback for skill improvement

-- User feedback tracking
CREATE TABLE IF NOT EXISTS feedback (
 id INTEGER PRIMARY KEY AUTOINCREMENT,
 session_id TEXT NOT NULL,
 message_id INTEGER NOT NULL,
 feedback_type TEXT NOT NULL, -- 'positive', 'negative', 'correction'
 correction_content TEXT, -- For correction type
 timestamp TEXT DEFAULT CURRENT_TIMESTAMP,
 FOREIGN KEY (message_id) REFERENCES messages(id)
);

-- Index for message lookups
CREATE INDEX IF NOT EXISTS idx_feedback_message ON feedback(message_id);

-- Insert schema version record
INSERT INTO schema_version (version, description) VALUES (3, 'Add feedback tracking for skill improvement');
