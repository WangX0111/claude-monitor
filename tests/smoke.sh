#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$ROOT_DIR/claude-monitor.sh"
TMP_DIR="$(mktemp -d)"

cleanup() {
    rm -rf "$TMP_DIR"
}
trap cleanup EXIT

assert_contains() {
    local haystack="$1"
    local needle="$2"

    if [[ "$haystack" != *"$needle"* ]]; then
        printf 'Expected output to contain: %s\n' "$needle" >&2
        printf 'Actual output:\n%s\n' "$haystack" >&2
        exit 1
    fi
}

test_syntax() {
    bash -n "$SCRIPT"
}

test_help_output() {
    local output
    output="$(bash "$SCRIPT" --help)"

    assert_contains "$output" "用法:"
    assert_contains "$output" "--daemon"
    assert_contains "$output" "--attach"
}

test_attach_missing_session_fails() {
    mkdir -p "$TMP_DIR/bin"
    cat > "$TMP_DIR/bin/tmux" <<'TMUX'
#!/usr/bin/env bash
case "$1" in
    has-session)
        exit 1
        ;;
    *)
        printf 'unexpected tmux command: %s\n' "$*" >&2
        exit 2
        ;;
esac
TMUX
    chmod +x "$TMP_DIR/bin/tmux"

    local output
    set +e
    output="$(
        PATH="$TMP_DIR/bin:$PATH" \
        CLAUDE_MONITOR_LOG="$TMP_DIR/monitor.log" \
        CLAUDE_MONITOR_PID="$TMP_DIR/monitor.pid" \
        bash "$SCRIPT" --attach --session missing 2>&1
    )"
    local status=$?
    set -e

    if [[ "$status" -eq 0 ]]; then
        printf 'Expected attach mode to fail for a missing session.\n' >&2
        exit 1
    fi

    assert_contains "$output" "会话 'missing' 不存在"
}

test_daemon_attach_missing_session_fails_before_spawn() {
    mkdir -p "$TMP_DIR/bin"
    cat > "$TMP_DIR/bin/tmux" <<'TMUX'
#!/usr/bin/env bash
case "$1" in
    has-session)
        exit 1
        ;;
    *)
        printf 'unexpected tmux command: %s\n' "$*" >&2
        exit 2
        ;;
esac
TMUX
    chmod +x "$TMP_DIR/bin/tmux"

    local output
    set +e
    output="$(
        PATH="$TMP_DIR/bin:$PATH" \
        CLAUDE_MONITOR_LOG="$TMP_DIR/daemon-monitor.log" \
        CLAUDE_MONITOR_PID="$TMP_DIR/daemon-monitor.pid" \
        bash "$SCRIPT" --daemon --attach --session missing 2>&1
    )"
    local status=$?
    set -e

    if [[ "$status" -eq 0 ]]; then
        printf 'Expected daemon attach mode to fail for a missing session.\n' >&2
        exit 1
    fi

    assert_contains "$output" "attach 模式不会创建新会话"
    if [[ -f "$TMP_DIR/daemon-monitor.pid" ]]; then
        printf 'Expected daemon attach failure not to leave a PID file.\n' >&2
        exit 1
    fi
}

test_syntax
test_help_output
test_attach_missing_session_fails
test_daemon_attach_missing_session_fails_before_spawn

printf 'smoke tests passed\n'
