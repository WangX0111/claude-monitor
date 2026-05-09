#!/bin/bash

# Claude session monitor script
# Runs Claude in tmux, auto-detects disconnections and sends continue

SESSION_NAME="claude"
CHECK_INTERVAL=10  # check interval (seconds)
CONTINUE_KEYWORDS=("disconnected" "connection lost" "session ended" "rate limit" "timed out" "error" "failed")
PROMPT_KEYWORDS=("Do you want to proceed?" "Do you want to continue?" "Continue?" "Proceed?")
LOG_FILE="${CLAUDE_MONITOR_LOG:-claude-monitor.log}"
PID_FILE="${CLAUDE_MONITOR_PID:-claude-monitor.pid}"
max_consecutive=3
consecutive_checks=0
continue_sent=false
ATTACH_ONLY=false

# color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() {
    local msg="[$(date '+%Y-%m-%d %H:%M:%S')] $1"
    echo -e "${GREEN}${msg}${NC}"
    echo "$msg" >> "$LOG_FILE"
}

log_warn() {
    local msg="[$(date '+%Y-%m-%d %H:%M:%S')] $1"
    echo -e "${YELLOW}${msg}${NC}"
    echo "$msg" >> "$LOG_FILE"
}

log_error() {
    local msg="[$(date '+%Y-%m-%d %H:%M:%S')] $1"
    echo -e "${RED}${msg}${NC}"
    echo "$msg" >> "$LOG_FILE"
}

require_command() {
    local command_name="$1"
    if ! command -v "$command_name" >/dev/null 2>&1; then
        log_error "Missing required command: $command_name"
        exit 127
    fi
}

require_runtime_commands() {
    require_command tmux
}

# Start Claude session
start_claude() {
    if [ "$ATTACH_ONLY" = true ]; then
        log_error "Session '$SESSION_NAME' does not exist, attach mode will not create a new session"
        exit 1
    fi

    require_command claude
    log_info "Starting Claude session..."
    # Source ~/.bashrc first, then start claude
    tmux new-session -d -s "$SESSION_NAME" "bash -l -c 'source ~/.bashrc 2>/dev/null; claude --yolo'"
    sleep 2
    log_info "Claude started"
}

# Send continue command
send_continue() {
    log_warn "Sending continue command..."
    tmux send-keys -t "$SESSION_NAME" "continue" Enter
    sleep 2
}

# Auto-confirm prompts (send Enter)
auto_confirm_prompt() {
    local last_lines
    last_lines=$(tmux capture-pane -t "$SESSION_NAME" -p -S -10 2>/dev/null)

    for keyword in "${PROMPT_KEYWORDS[@]}"; do
        if echo "$last_lines" | grep -qi "$keyword"; then
            log_warn "Detected confirmation prompt, auto-confirming..."
            tmux send-keys -t "$SESSION_NAME" Enter
            sleep 1
            return 0
        fi
    done
    return 1
}

# Check if session exists
check_session_exists() {
    tmux has-session -t "$SESSION_NAME" 2>/dev/null
    return $?
}

# Check output for disconnection keywords
check_disconnection_keywords() {
    local last_lines
    last_lines=$(tmux capture-pane -t "$SESSION_NAME" -p -S -20 2>/dev/null)

    for keyword in "${CONTINUE_KEYWORDS[@]}"; do
        if echo "$last_lines" | grep -qi "$keyword"; then
            log_warn "Detected keyword: $keyword"
            return 0
        fi
    done
    return 1
}

# Check if session is active (has new output)
check_session_active() {
    local current_output
    current_output=$(tmux capture-pane -t "$SESSION_NAME" -p -S -5 2>/dev/null)

    # If the last few lines contain a prompt or blank lines, it may have stopped
    if echo "$current_output" | tail -3 | grep -qE "^\s*$|>\s*$"; then
        return 1  # inactive
    fi
    return 0  # active
}

handle_disconnection_keywords() {
    if check_disconnection_keywords; then
        consecutive_checks=$((consecutive_checks + 1))

        if [ "$continue_sent" = true ]; then
            log_warn "Anomaly already handled with continue, waiting for output to recover..."
            return 0
        fi

        if [ "$consecutive_checks" -ge "$max_consecutive" ]; then
            log_warn "Detected anomalies ${max_consecutive} consecutive times, sending continue..."
            send_continue
            continue_sent=true
            consecutive_checks=0
        fi
    else
        consecutive_checks=0
        continue_sent=false
    fi
}

# Main monitor loop
main() {
    require_runtime_commands
    log_info "Started monitoring Claude session (interval: ${CHECK_INTERVAL}s)"
    log_info "Press Ctrl+C to stop monitoring"

    # If session does not exist, start it
    if ! check_session_exists; then
        start_claude
    else
        log_info "Claude session already exists"
    fi

    while true; do
        # Check if session exists
        if ! check_session_exists; then
            if [ "$ATTACH_ONLY" = true ]; then
                log_error "Session '$SESSION_NAME' does not exist, attach mode will not create a new session"
                exit 1
            fi
            log_error "Session disconnected, restarting..."
            start_claude
            consecutive_checks=0
            continue_sent=false
            sleep "$CHECK_INTERVAL"
            continue
        fi

        # Check for confirmation prompts and auto-confirm
        auto_confirm_prompt

        # Check output for disconnection keywords
        handle_disconnection_keywords

        sleep "$CHECK_INTERVAL"
    done
}

# Handle exit signals
cleanup() {
    log_info "Stopping monitor..."
    exit 0
}

trap cleanup SIGINT SIGTERM

# Run as daemon
run_daemon() {
    require_runtime_commands
    log_info "Starting background monitor process..."

    if [ "$ATTACH_ONLY" = true ] && ! check_session_exists; then
        log_error "Session '$SESSION_NAME' does not exist, attach mode will not create a new session"
        exit 1
    fi

    if [ "$ATTACH_ONLY" != true ] && ! check_session_exists; then
        require_command claude
    fi

    # Check if already running
    if [ -f "$PID_FILE" ]; then
        local old_pid
        old_pid=$(cat "$PID_FILE")
        if ps -p "$old_pid" > /dev/null 2>&1; then
            log_error "Monitor process already running (PID: $old_pid)"
            exit 1
        else
            log_warn "Cleaning up stale PID file"
            rm -f "$PID_FILE"
        fi
    fi

    # Start background process
    local daemon_args=(--daemon-running "$SESSION_NAME" "$CHECK_INTERVAL")
    if [ "$ATTACH_ONLY" = true ]; then
        daemon_args+=(--attach)
    fi

    nohup "$0" "${daemon_args[@]}" > /dev/null 2>&1 &
    local pid=$!
    echo "$pid" > "$PID_FILE"
    log_info "Background monitor started (PID: $pid)"
    log_info "Log file: $LOG_FILE"
    log_info "Stop command: $0 -k"
}

# Daemon mode (called by run_daemon)
run_daemon_mode() {
    require_runtime_commands
    echo $$ > "$PID_FILE"
    trap 'rm -f "$PID_FILE"; exit 0' SIGTERM SIGINT EXIT

    log_info "Background monitor process started (PID: $$)"

    while true; do
        # Check if session exists
        if ! check_session_exists; then
            if [ "$ATTACH_ONLY" = true ]; then
                log_error "Session '$SESSION_NAME' does not exist, attach mode will not create a new session"
                exit 1
            fi
            log_error "Session disconnected, restarting..."
            start_claude
            consecutive_checks=0
            continue_sent=false
            sleep "$CHECK_INTERVAL"
            continue
        fi

        # Check for confirmation prompts and auto-confirm
        auto_confirm_prompt

        # Check output for disconnection keywords
        handle_disconnection_keywords

        sleep "$CHECK_INTERVAL"
    done
}

# Stop daemon process
stop_daemon() {
    if [ ! -f "$PID_FILE" ]; then
        log_error "No running monitor process found"
        exit 1
    fi

    local pid
    pid=$(cat "$PID_FILE")

    if ps -p "$pid" > /dev/null 2>&1; then
        log_info "Stopping monitor process (PID: $pid)..."
        kill "$pid"
        sleep 1

        # Check if stopped
        if ps -p "$pid" > /dev/null 2>&1; then
            log_warn "Force stopping..."
            kill -9 "$pid"
        fi

        rm -f "$PID_FILE"
        log_info "Stopped"
    else
        log_warn "Process does not exist (PID: $pid), cleaning up PID file"
        rm -f "$PID_FILE"
    fi
}

# Show status
show_status() {
    if [ -f "$PID_FILE" ]; then
        local pid
        pid=$(cat "$PID_FILE")
        if ps -p "$pid" > /dev/null 2>&1; then
            log_info "Monitor process running (PID: $pid)"
            log_info "Log: tail -f $LOG_FILE"
            return 0
        else
            log_warn "PID file exists but process has stopped (PID: $pid)"
            rm -f "$PID_FILE"
        fi
    fi
    log_info "Monitor process is not running"
    return 1
}

# Show help
show_help() {
    echo "Usage: $0 [options]"
    echo ""
    echo "Options:"
    echo "  -s, --session NAME    Set tmux session name (default: claude)"
    echo "  -i, --interval SECS   Set check interval in seconds (default: 10)"
    echo "  -r, --restart         Restart an existing session"
    echo "  -a, --attach          Monitor an existing session only (no new session)"
    echo "  -d, --daemon          Run in the background"
    echo "  -k, --kill            Stop the background process"
    echo "  -l, --logs            Follow logs"
    echo "  --status              Show running status"
    echo "  -h, --help            Show help"
    echo ""
    echo "Examples:"
    echo "  $0                    # Foreground monitor (creates new session)"
    echo "  $0 -a                 # Monitor existing session"
    echo "  $0 -d                 # Run in background"
    echo "  $0 -d -a              # Background monitor for existing session"
    echo "  $0 -k                 # Stop background process"
    echo "  $0 -l                 # Follow logs"
    echo "  $0 --status           # Show status"
}

# Parse arguments
RESTART=false
DAEMON=false
KILL=false
SHOW_LOGS=false
while [[ $# -gt 0 ]]; do
    case $1 in
        -s|--session)
            SESSION_NAME="$2"
            shift 2
            ;;
        -i|--interval)
            CHECK_INTERVAL="$2"
            shift 2
            ;;
        -r|--restart)
            RESTART=true
            shift
            ;;
        -a|--attach)
            ATTACH_ONLY=true
            shift
            ;;
        -d|--daemon)
            DAEMON=true
            shift
            ;;
        -k|--kill)
            KILL=true
            shift
            ;;
        -l|--logs)
            SHOW_LOGS=true
            shift
            ;;
        --status)
            show_status
            exit $?
            ;;
        --daemon-running)
            # Internal use, called by run_daemon
            SESSION_NAME="$2"
            CHECK_INTERVAL="$3"
            shift 3
            while [[ $# -gt 0 ]]; do
                case $1 in
                    -a|--attach)
                        ATTACH_ONLY=true
                        shift
                        ;;
                    *)
                        log_error "Unknown internal argument: $1"
                        exit 1
                        ;;
                esac
            done

            # Ensure session exists
            if ! check_session_exists; then
                if [ "$ATTACH_ONLY" = true ]; then
                    log_error "Session '$SESSION_NAME' does not exist, attach mode will not create a new session"
                    exit 1
                fi
                log_info "Claude session does not exist, creating..."
                start_claude
            fi

            run_daemon_mode
            exit 0
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        *)
            log_error "Unknown argument: $1"
            show_help
            exit 1
            ;;
    esac
done

# Handle actions
if [ "$KILL" = true ]; then
    stop_daemon
    exit 0
fi

if [ "$SHOW_LOGS" = true ]; then
    if [ -f "$LOG_FILE" ]; then
        tail -f "$LOG_FILE"
    else
        log_error "Log file does not exist: $LOG_FILE"
        exit 1
    fi
    exit 0
fi

# Run as daemon
if [ "$DAEMON" = true ]; then
    run_daemon
    exit 0
fi

# If attach is specified, monitor only without creating
if [ "$ATTACH_ONLY" = true ]; then
    if ! check_session_exists; then
        log_error "Session '$SESSION_NAME' does not exist"
        exit 1
    fi
    log_info "Attaching to existing session '$SESSION_NAME' for monitoring"
fi

# If restart is specified, kill the old session first
if [ "$RESTART" = true ] && check_session_exists; then
    log_warn "Restarting session: $SESSION_NAME"
    tmux kill-session -t "$SESSION_NAME"
    sleep 1
fi

# Run main loop
main
