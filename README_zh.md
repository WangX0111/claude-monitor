# claude-monitor

[English](README.md)

一个基于 tmux 的轻量级 Claude Code CLI 监控工具。它在 tmux 会话中保持 Claude 运行，监控最近的输出以检测断连/错误提示，在需要恢复时发送 `continue`，并自动确认常见的交互式提示。

## 功能特性

- 自动检测 Claude 会话断连或失败。
- 在多次检测到可恢复的错误信号后发送 `continue`。
- 自动确认常见的 proceed/continue 提示。
- 支持前台运行或后台守护进程模式。
- 可以附加到已有的 tmux 会话进行监控。
- 日志和 PID 文件存储在可预测的位置。

## 环境要求

- Bash 4+
- tmux
- Claude Code CLI（命令为 `claude`）

## 安装

```bash
make install
```

默认安装到 `~/.local/bin`，请确保该目录在 `PATH` 中。

自定义安装路径：

```bash
make install PREFIX=/usr/local
```

## 使用方法

前台运行受监控的 Claude 会话：

```bash
claude-monitor
```

后台运行：

```bash
claude-monitor --daemon
```

监控已有的 tmux 会话（不创建新会话）：

```bash
claude-monitor --attach --session claude
```

停止后台监控进程：

```bash
claude-monitor --kill
```

查看状态：

```bash
claude-monitor --status
```

查看日志：

```bash
claude-monitor --logs
```

## 选项

```text
-s, --session 名称       要监控的 tmux 会话名称（默认：claude）
-i, --interval 秒数      检查间隔秒数（默认：10）
-r, --restart            重启已有的 Claude tmux 会话
-a, --attach             仅监控已有会话（不创建新会话）
-d, --daemon             后台运行
-k, --kill               停止后台监控进程
-l, --logs               查看日志
--status                 查看守护进程状态
-h, --help               显示帮助
```

## 配置

运行时文件可通过环境变量覆盖：

```bash
CLAUDE_MONITOR_LOG=/tmp/claude-monitor.log \
CLAUDE_MONITOR_PID=/tmp/claude-monitor.pid \
claude-monitor --daemon
```

脚本使用以下命令启动 Claude：

```bash
bash -l -c 'source ~/.bashrc 2>/dev/null; claude --yolo'
```

如需修改 Claude 启动命令，请编辑 `claude-monitor.sh`。

## 开发

运行测试：

```bash
make test
```

仅运行语法检查：

```bash
make check
```

## 安全提示

本工具会自动按下回车键并向 Claude Code 会话发送 `continue`。请仅在可接受此行为的环境中使用。

此外，可能存在错误发送或多发 `continue` 消息的情况，仍有待优化。如有好的想法，欢迎分享。
