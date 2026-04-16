# ZeroHermes Optimization - Checklist

## Status Legend
- [ ] Pending
- [~] In Progress
- [x] Completed
- [!] Blocked

---

## Phase 1: Create Python Helper Module

### 1.1 Core Structure
- [ ] Create lib/pyhelper.py base structure
- [ ] Implement database connection with lazy init
- [ ] Implement db_exec() function
- [ ] Implement JSON utilities

### 1.2 Message Operations
- [ ] Implement save_message()
- [ ] Implement get_messages()
- [ ] Implement search_messages()
- [ ] Implement get_context()

### 1.3 LLM Support
- [ ] Implement build_messages()
- [ ] Implement parse_response()
- [ ] Implement extract_tool_call()

### 1.4 CLI Entry Point
- [ ] Add argparse CLI
- [ ] Add error handling
- [ ] Test CLI interface

---

## Phase 2: Refactor Shell Libraries

### 2.1 common.sh
- [ ] Remove sql_exec() embedded Python
- [ ] Remove sql_exec_json() embedded Python
- [ ] Remove _json_parse() embedded Python
- [ ] Add pyhelper wrapper functions

### 2.2 memory.sh
- [ ] Refactor save_message()
- [ ] Refactor get_messages()
- [ ] Refactor get_context()
- [ ] Refactor search_messages()
- [ ] Refactor list_sessions()
- [ ] Refactor get_session_stats()
- [ ] Refactor delete_session()
- [ ] Refactor get_schema_version()
- [ ] Refactor check_database()

### 2.3 llm.sh
- [ ] Refactor build_messages()
- [ ] Refactor call_llm() response parsing
- [ ] Remove embedded Python blocks

### 2.4 tools.sh
- [ ] Refactor execute_tool() JSON parsing
- [ ] Remove embedded Python blocks

---

## Phase 3: Refactor Agent Loop

### 3.1 agent_loop.sh
- [ ] Refactor message array building
- [ ] Refactor context processing loop
- [ ] Refactor tool response handling
- [ ] Test agent loop

---

## Phase 4: Testing

### 4.1 Python Tests
- [ ] Create tests/test_pyhelper.py
- [ ] Test database functions
- [ ] Test JSON functions
- [ ] Test message functions

### 4.2 Shell Tests
- [ ] Update tests/test_database.sh
- [ ] Update tests/test_memory.sh
- [ ] Run all tests
- [ ] Fix failures

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
