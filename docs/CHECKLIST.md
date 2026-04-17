# ZeroHermes Optimization - Checklist

## Status Legend
- [ ] Pending
- [~] In Progress
- [x] Completed
- [!] Blocked

---

## Phase 1: Create Python Helper Module

### 1.1 Core Structure
- [x] Create lib/pyhelper.py base structure
- [x] Implement database connection with lazy init
- [x] Implement db_exec() function
- [x] Implement JSON utilities

### 1.2 Message Operations
- [x] Implement save_message()
- [x] Implement get_messages()
- [x] Implement search_messages()
- [x] Implement get_context()

### 1.3 LLM Support
- [x] Implement build_messages()
- [x] Implement parse_response()
- [x] Implement extract_tool_call()

### 1.4 CLI Entry Point
- [x] Add argparse CLI
- [x] Add error handling
- [x] Test CLI interface

---

## Phase 2: Refactor Shell Libraries

### 2.1 common.sh
- [x] Remove sql_exec() embedded Python
- [x] Remove sql_exec_json() embedded Python
- [x] Remove _json_parse() embedded Python
- [x] Add pyhelper wrapper functions

### 2.2 memory.sh
- [x] Refactor save_message()
- [x] Refactor get_messages()
- [x] Refactor get_context()
- [x] Refactor search_messages()
- [x] Refactor list_sessions()
- [x] Refactor get_session_stats()
- [x] Refactor delete_session()
- [x] Refactor get_schema_version()
- [x] Refactor check_database()

### 2.3 llm.sh
- [x] Refactor build_messages()
- [x] Refactor call_llm() response parsing
- [x] Remove embedded Python blocks

### 2.4 tools.sh
- [x] Refactor execute_tool() JSON parsing
- [x] Remove embedded Python blocks

---

## Phase 3: Refactor Agent Loop

### 3.1 agent_loop.sh
- [x] Refactor message array building
- [x] Refactor context processing loop
- [x] Refactor tool response handling
- [x] Test agent loop

---

## Phase 4: Testing

### 4.1 Python Tests
- [x] Create tests/test_pyhelper.py
- [x] Test database functions
- [x] Test JSON functions
- [x] Test message functions

### 4.2 Shell Tests
- [x] Update tests/test_database.sh
- [x] Update tests/test_memory.sh
- [x] Run all tests
- [x] Fix failures

---

## Phase 5: Documentation & Cleanup

### 5.1 Documentation
- [ ] Update README.md
- [ ] Update CRON_PROMPT.md (if exists)
- [ ] Add pyhelper API docs

### 5.2 Final Verification
- [ ] Count lines: Shell should be ~500
- [ ] Count lines: Python should be ~300-400
- [ ] Verify no embedded Python remains
- [ ] Commit and push

---

**Last Updated**: 2026-04-16
