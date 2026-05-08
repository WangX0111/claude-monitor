#!/bin/bash

# Claude 会话监控脚本
# 使用 tmux 运行 Claude，自动检测断连并发送 continue

SESSION_NAME="claude"
CHECK_INTERVAL=10  # 检查间隔（秒）
CONTINUE_KEYWORDS=("disconnected" "connection lost" "session ended" "rate limit" "timed out" "error" "failed")
PROMPT_KEYWORDS=("Do you want to proceed?" "Do you want to continue?" "Continue?" "Proceed?")
LOG_FILE="${CLAUDE_MONITOR_LOG:-claude-monitor.log}"
PID_FILE="${CLAUDE_MONITOR_PID:-claude-monitor.pid}"
max_consecutive=3
consecutive_checks=0
ATTACH_ONLY=false

# 颜色输出
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
        log_error "缺少依赖命令: $command_name"
        exit 127
    fi
}

require_runtime_commands() {
    require_command tmux
}

# 启动 Claude 会话
start_claude() {
    if [ "$ATTACH_ONLY" = true ]; then
        log_error "会话 '$SESSION_NAME' 不存在，attach 模式不会创建新会话"
        exit 1
    fi

    require_command claude
    log_info "启动 Claude 会话..."
    # 先 source ~/.bashrc，然后启动 claude
    tmux new-session -d -s "$SESSION_NAME" "bash -l -c 'source ~/.bashrc 2>/dev/null; claude --yolo'"
    sleep 2
    log_info "Claude 已启动"
}

# 发送 continue 命令
send_continue() {
    log_warn "发送 continue 命令..."
    tmux send-keys -t "$SESSION_NAME" "continue" Enter
    sleep 2
}

# 自动回复确认提示（发送回车）
auto_confirm_prompt() {
    local last_lines
    last_lines=$(tmux capture-pane -t "$SESSION_NAME" -p -S -10 2>/dev/null)
    
    for keyword in "${PROMPT_KEYWORDS[@]}"; do
        if echo "$last_lines" | grep -qi "$keyword"; then
            log_warn "检测到确认提示，自动回车确认..."
            tmux send-keys -t "$SESSION_NAME" Enter
            sleep 1
            return 0
        fi
    done
    return 1
}

# 检查会话是否存在
check_session_exists() {
    tmux has-session -t "$SESSION_NAME" 2>/dev/null
    return $?
}

# 检查输出中是否有断连关键词
check_disconnection_keywords() {
    local last_lines
    last_lines=$(tmux capture-pane -t "$SESSION_NAME" -p -S -20 2>/dev/null)
    
    for keyword in "${CONTINUE_KEYWORDS[@]}"; do
        if echo "$last_lines" | grep -qi "$keyword"; then
            log_warn "检测到关键词: $keyword"
            return 0
        fi
    done
    return 1
}

# 检查会话是否活跃（有新的输出）
check_session_active() {
    local current_output
    current_output=$(tmux capture-pane -t "$SESSION_NAME" -p -S -5 2>/dev/null)
    
    # 如果最后几行包含提示符或空行，可能已经停止
    if echo "$current_output" | tail -3 | grep -qE "^\s*$|>\s*$"; then
        return 1  # 不活跃
    fi
    return 0  # 活跃
}

# 主监控循环
main() {
    require_runtime_commands
    log_info "开始监控 Claude 会话 (间隔: ${CHECK_INTERVAL}s)"
    log_info "按 Ctrl+C 停止监控"
    
    # 如果会话不存在，启动它
    if ! check_session_exists; then
        start_claude
    else
        log_info "Claude 会话已存在"
    fi
    
    while true; do
        # 检查会话是否存在
        if ! check_session_exists; then
            if [ "$ATTACH_ONLY" = true ]; then
                log_error "会话 '$SESSION_NAME' 不存在，attach 模式不会创建新会话"
                exit 1
            fi
            log_error "会话已断开，正在重启..."
            start_claude
            consecutive_checks=0
            sleep "$CHECK_INTERVAL"
            continue
        fi
        
        # 检查是否有确认提示，自动回车
        auto_confirm_prompt
        
        # 检查输出中是否有断连关键词
        if check_disconnection_keywords; then
            consecutive_checks=$((consecutive_checks + 1))
            
            if [ "$consecutive_checks" -ge "$max_consecutive" ]; then
                log_warn "连续 ${max_consecutive} 次检测到异常，发送 continue..."
                send_continue
                consecutive_checks=0
            fi
        else
            consecutive_checks=0
        fi
        
        sleep "$CHECK_INTERVAL"
    done
}

# 处理退出信号
cleanup() {
    log_info "停止监控..."
    exit 0
}

trap cleanup SIGINT SIGTERM

# 后台运行
run_daemon() {
    require_runtime_commands
    log_info "启动后台监控进程..."

    if [ "$ATTACH_ONLY" = true ] && ! check_session_exists; then
        log_error "会话 '$SESSION_NAME' 不存在，attach 模式不会创建新会话"
        exit 1
    fi

    if [ "$ATTACH_ONLY" != true ] && ! check_session_exists; then
        require_command claude
    fi
    
    # 检查是否已经在运行
    if [ -f "$PID_FILE" ]; then
        local old_pid
        old_pid=$(cat "$PID_FILE")
        if ps -p "$old_pid" > /dev/null 2>&1; then
            log_error "监控进程已在运行 (PID: $old_pid)"
            exit 1
        else
            log_warn "清理过期的 PID 文件"
            rm -f "$PID_FILE"
        fi
    fi
    
    # 启动后台进程
    local daemon_args=(--daemon-running "$SESSION_NAME" "$CHECK_INTERVAL")
    if [ "$ATTACH_ONLY" = true ]; then
        daemon_args+=(--attach)
    fi

    nohup "$0" "${daemon_args[@]}" > /dev/null 2>&1 &
    local pid=$!
    echo "$pid" > "$PID_FILE"
    log_info "后台监控已启动 (PID: $pid)"
    log_info "日志文件: $LOG_FILE"
    log_info "停止命令: $0 -k"
}

# 后台运行模式（由 run_daemon 调用）
run_daemon_mode() {
    require_runtime_commands
    echo $$ > "$PID_FILE"
    trap 'rm -f "$PID_FILE"; exit 0' SIGTERM SIGINT EXIT
    
    log_info "后台监控进程启动 (PID: $$)"
    
    while true; do
        # 检查会话是否存在
        if ! check_session_exists; then
            if [ "$ATTACH_ONLY" = true ]; then
                log_error "会话 '$SESSION_NAME' 不存在，attach 模式不会创建新会话"
                exit 1
            fi
            log_error "会话已断开，正在重启..."
            start_claude
            consecutive_checks=0
            sleep "$CHECK_INTERVAL"
            continue
        fi
        
        # 检查是否有确认提示，自动回车
        auto_confirm_prompt
        
        # 检查输出中是否有断连关键词
        if check_disconnection_keywords; then
            consecutive_checks=$((consecutive_checks + 1))
            
            if [ "$consecutive_checks" -ge "$max_consecutive" ]; then
                log_warn "连续 ${max_consecutive} 次检测到异常，发送 continue..."
                send_continue
                consecutive_checks=0
            fi
        else
            consecutive_checks=0
        fi
        
        sleep "$CHECK_INTERVAL"
    done
}

# 停止后台进程
stop_daemon() {
    if [ ! -f "$PID_FILE" ]; then
        log_error "未找到运行中的监控进程"
        exit 1
    fi
    
    local pid
    pid=$(cat "$PID_FILE")
    
    if ps -p "$pid" > /dev/null 2>&1; then
        log_info "停止监控进程 (PID: $pid)..."
        kill "$pid"
        sleep 1
        
        # 检查是否已停止
        if ps -p "$pid" > /dev/null 2>&1; then
            log_warn "强制停止..."
            kill -9 "$pid"
        fi
        
        rm -f "$PID_FILE"
        log_info "已停止"
    else
        log_warn "进程不存在 (PID: $pid)，清理 PID 文件"
        rm -f "$PID_FILE"
    fi
}

# 显示状态
show_status() {
    if [ -f "$PID_FILE" ]; then
        local pid
        pid=$(cat "$PID_FILE")
        if ps -p "$pid" > /dev/null 2>&1; then
            log_info "监控进程运行中 (PID: $pid)"
            log_info "日志: tail -f $LOG_FILE"
            return 0
        else
            log_warn "PID 文件存在但进程已停止 (PID: $pid)"
            rm -f "$PID_FILE"
        fi
    fi
    log_info "监控进程未运行"
    return 1
}

# 显示帮助
show_help() {
    echo "用法: $0 [选项]"
    echo ""
    echo "选项:"
    echo "  -s, --session NAME    设置 tmux 会话名称 (默认: claude)"
    echo "  -i, --interval SECS   设置检查间隔 (默认: 10)"
    echo "  -r, --restart         重启已存在的会话"
    echo "  -a, --attach          仅监控已有会话（不创建新会话）"
    echo "  -d, --daemon          后台运行"
    echo "  -k, --kill            停止后台进程"
    echo "  -l, --logs            查看日志"
    echo "  --status              查看运行状态"
    echo "  -h, --help            显示帮助"
    echo ""
    echo "示例:"
    echo "  $0                    # 前台监控（创建新会话）"
    echo "  $0 -a                 # 监控已有会话"
    echo "  $0 -d                 # 后台运行"
    echo "  $0 -d -a              # 后台监控已有会话"
    echo "  $0 -k                 # 停止后台进程"
    echo "  $0 -l                 # 查看日志"
    echo "  $0 --status           # 查看状态"
}

# 解析参数
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
            # 内部使用，由 run_daemon 调用
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
                        log_error "未知内部参数: $1"
                        exit 1
                        ;;
                esac
            done
            
            # 确保会话存在
            if ! check_session_exists; then
                if [ "$ATTACH_ONLY" = true ]; then
                    log_error "会话 '$SESSION_NAME' 不存在，attach 模式不会创建新会话"
                    exit 1
                fi
                log_info "Claude 会话不存在，正在创建..."
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
            log_error "未知参数: $1"
            show_help
            exit 1
            ;;
    esac
done

# 处理操作
if [ "$KILL" = true ]; then
    stop_daemon
    exit 0
fi

if [ "$SHOW_LOGS" = true ]; then
    if [ -f "$LOG_FILE" ]; then
        tail -f "$LOG_FILE"
    else
        log_error "日志文件不存在: $LOG_FILE"
        exit 1
    fi
    exit 0
fi

# 后台运行
if [ "$DAEMON" = true ]; then
    run_daemon
    exit 0
fi

# 如果指定了 attach，只监控不创建
if [ "$ATTACH_ONLY" = true ]; then
    if ! check_session_exists; then
        log_error "会话 '$SESSION_NAME' 不存在"
        exit 1
    fi
    log_info "附加到已有会话 '$SESSION_NAME' 进行监控"
fi

# 如果指定了 restart，先杀掉旧会话
if [ "$RESTART" = true ] && check_session_exists; then
    log_warn "重启会话: $SESSION_NAME"
    tmux kill-session -t "$SESSION_NAME"
    sleep 1
fi

# 运行主循环
main
