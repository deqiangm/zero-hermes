-- Migration 002: Add Task Patterns
-- Version: 2
-- Description: Track task execution patterns for skill creation

-- Skill execution tracking (for learning loop)
CREATE TABLE IF NOT EXISTS task_patterns (
 id INTEGER PRIMARY KEY AUTOINCREMENT,
 pattern_hash TEXT NOT NULL UNIQUE, -- SHA256 of task signature
 task_description TEXT NOT NULL,
 execution_count INTEGER DEFAULT 1,
 first_seen TEXT DEFAULT CURRENT_TIMESTAMP,
 last_seen TEXT DEFAULT CURRENT_TIMESTAMP,
 skill_created INTEGER DEFAULT 0,
 skill_name TEXT -- Name of skill if created
);

-- Index for fast hash lookups
CREATE INDEX IF NOT EXISTS idx_task_patterns_hash ON task_patterns(pattern_hash);

-- Insert schema version record
INSERT INTO schema_version (version, description) VALUES (2, 'Add task_patterns for learning loop');
