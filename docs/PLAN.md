# ZeroHermes Optimization Plan

## Goal
Refactor ZeroHermes to use a single Python helper module while keeping lightweight shell-based architecture.

## Background
Current codebase has ~20+ embedded Python code blocks in Shell scripts, causing:
- Repeated Python process spawns
- Code mixing, hard to maintain
- No database connection reuse
- Complex JSON handling

## Solution
Create a single `pyhelper.py` (~300 lines) and simplify Shell wrappers.

---

## Phase 1: Create Python Helper Module

### 1.1 Core Structure
- [ ] Create `lib/pyhelper.py` with core functions
- [ ] Database operations with connection reuse
- [ ] JSON utilities (simple path extraction)
- [ ] Message operations (save/get/search)

### 1.2 LLM Support
- [ ] Message building for API calls
- [ ] Response parsing (OpenAI/Anthropic formats)
- [ ] Provider-agnostic interface

### 1.3 CLI Entry Point
- [ ] Command-line interface for Shell calls
- [ ] Argument parsing
- [ ] Error handling

---

## Phase 2: Refactor Shell Libraries

### 2.1 common.sh
- [ ] Remove embedded Python
- [ ] Keep logging functions
- [ ] Keep utility functions (generate_id, get_timestamp)
- [ ] Add pyhelper wrapper functions

### 2.2 memory.sh
- [ ] Simplify to thin wrappers
- [ ] Remove all embedded Python
- [ ] Keep Markdown memory functions (file-based)

### 2.3 llm.sh
- [ ] Use pyhelper for message building
- [ ] Use pyhelper for response parsing
- [ ] Keep curl API calls in Shell

### 2.4 tools.sh
- [ ] Use pyhelper for JSON argument parsing
- [ ] Keep tool execution in Shell

---

## Phase 3: Refactor Agent Loop

### 3.1 agent_loop.sh
- [ ] Simplify message array building
- [ ] Use pyhelper for JSON operations
- [ ] Keep loop logic in Shell

---

## Phase 4: Testing

### 4.1 Python Tests
- [ ] Create `tests/test_pyhelper.py`
- [ ] Test database operations
- [ ] Test JSON utilities
- [ ] Test message operations

### 4.2 Integration Tests
- [ ] Update existing Shell tests
- [ ] Run all tests
- [ ] Fix any issues

---

## Phase 5: Documentation & Cleanup

### 5.1 Documentation
- [ ] Update README.md
- [ ] Update CRON_PROMPT.md
- [ ] Document pyhelper API

### 5.2 Cleanup
- [ ] Remove unused code
- [ ] Verify line counts reduced
- [ ] Final commit and push

---

## Success Criteria
- Python code: single file < 400 lines
- Shell code: reduced from 1300 to ~500 lines
- All tests pass
- No embedded Python in Shell scripts
