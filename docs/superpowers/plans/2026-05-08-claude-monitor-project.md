# Claude Monitor Project Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn the existing tmux Claude monitor script into a small, usable git project.

**Architecture:** Keep a single Bash CLI as the runtime artifact. Add project documentation, ignore rules, license, install/test helpers, and shell smoke tests that exercise stable CLI behavior without requiring a real Claude session.

**Tech Stack:** Bash, tmux, Make, git.

---

### Task 1: Project Metadata

**Files:**
- Create: `README.md`
- Create: `LICENSE`
- Create: `.gitignore`
- Create: `.editorconfig`
- Create: `Makefile`

- [x] Document purpose, features, requirements, install, usage, and safety notes.
- [x] Ignore runtime logs, PID files, temp files, and editor files.
- [x] Add MIT license.
- [x] Add Make targets for syntax check, smoke test, install, and uninstall.

### Task 2: Script Hardening

**Files:**
- Modify: `claude-monitor.sh`

- [x] Keep defaults simple and configurable.
- [x] Preserve foreground monitor, daemon monitor, status, logs, restart, and attach modes.
- [x] Make daemon attach mode fail when the target tmux session is absent instead of creating a new Claude session.
- [x] Validate required command dependencies before starting long-running monitor modes.
- [x] Make runtime files predictable through `CLAUDE_MONITOR_LOG` and `CLAUDE_MONITOR_PID`.

### Task 3: Smoke Tests

**Files:**
- Create: `tests/smoke.sh`

- [x] Verify Bash syntax.
- [x] Verify help output.
- [x] Verify attach mode exits non-zero when a mocked tmux session is missing.

### Task 4: Verification and Git

- [x] Run `bash tests/smoke.sh`.
- [x] Initialize git repository.
- [x] Commit the completed project baseline.
