# claude-monitor

[中文](README_zh.md)

A lightweight tmux-based monitor for Claude Code CLI. It keeps Claude running in a tmux session, watches recent output for disconnect/error prompts, sends `continue` when recovery is needed, and auto-confirms common interactive prompts.

## Features

- Automatically detects disconnected or failed Claude sessions.
- Sends `continue` after repeated recoverable error signals.
- Auto-confirms common proceed/continue prompts.
- Runs in the foreground or as a background daemon.
- Can attach to and monitor an existing tmux session.
- Stores logs and PID files in predictable locations.

## Requirements

- Bash 4+
- tmux
- Claude Code CLI available as `claude`

## Install

```bash
make install
```

By default this installs `claude-monitor` to `~/.local/bin`. Make sure that directory is in your `PATH`.

To install somewhere else:

```bash
make install PREFIX=/usr/local
```

## Usage

Run a monitored Claude session in the foreground:

```bash
claude-monitor
```

Run in the background:

```bash
claude-monitor --daemon
```

Monitor an existing tmux session without creating a new one:

```bash
claude-monitor --attach --session claude
```

Stop a background monitor:

```bash
claude-monitor --kill
```

Check status:

```bash
claude-monitor --status
```

Follow logs:

```bash
claude-monitor --logs
```

## Options

```text
-s, --session NAME       tmux session name to monitor (default: claude)
-i, --interval SECS      check interval in seconds (default: 10)
-r, --restart            restart an existing Claude tmux session
-a, --attach             monitor an existing session only
-d, --daemon             run monitor in the background
-k, --kill               stop background monitor
-l, --logs               follow monitor logs
--status                 show daemon status
-h, --help               show help
```

## Configuration

Runtime files can be overridden with environment variables:

```bash
CLAUDE_MONITOR_LOG=/tmp/claude-monitor.log \
CLAUDE_MONITOR_PID=/tmp/claude-monitor.pid \
claude-monitor --daemon
```

The script starts Claude with:

```bash
bash -l -c 'source ~/.bashrc 2>/dev/null; claude --yolo'
```

Edit `claude-monitor.sh` if you need a different Claude startup command.

## How It Differs From Claude's Built-in Behavior

`claude-monitor` is an external automation wrapper around Claude Code CLI. It is not a replacement for Claude's own session handling; it is meant for unattended recovery when Claude is running inside tmux.

| Area | `claude-monitor` | Claude Code CLI |
| --- | --- | --- |
| Role | External watchdog script | Built-in interactive CLI |
| Runtime | Wraps `claude` in a tmux session | Runs directly in the terminal |
| Disconnection handling | Watches tmux output for recovery keywords | Uses Claude CLI's own session behavior |
| `continue` handling | Sends `continue` automatically after repeated recoverable signals | Usually remains user-driven or CLI-managed |
| Prompt confirmation | Auto-confirms common proceed/continue prompts | Usually waits for user confirmation |
| Background mode | Supports `--daemon` | Primarily foreground interactive use |
| Existing sessions | Can monitor an existing tmux session with `--attach` | Does not manage tmux sessions |
| Reliability model | Simple text matching; easy to inspect, but may miss or misread output | Closer to internal CLI state, but less focused on unattended automation |
| Risk profile | More automated and therefore higher-risk in sensitive environments | More conservative and user-controlled |

Use this project when you want Claude Code to keep running on a remote machine, recover from common terminal-visible failures, or continue long-running work without constantly watching the terminal.

Avoid it when automatic confirmation is not acceptable, when commands are high-risk, or when you need exact knowledge of Claude's internal state instead of terminal-output heuristics.

## Development

Run checks:

```bash
make test
```

Run only the syntax check:

```bash
make check
```

## Safety Notes

This tool can automatically press Enter and send `continue` to a Claude Code session. Use it only in environments where that behavior is acceptable.

The monitor sends `continue` at most once for the same continuous error episode. It will only become eligible to send `continue` again after the monitored output no longer contains the configured recovery keywords.
