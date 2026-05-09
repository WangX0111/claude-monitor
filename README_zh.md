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

## 与 Claude 内置行为的区别

`claude-monitor` 是 Claude Code CLI 外层的自动化包装脚本。它不是用来替代 Claude 自身的会话处理能力，而是用于 Claude 运行在 tmux 中时的无人值守恢复。

| 维度 | `claude-monitor` | Claude Code CLI |
| --- | --- | --- |
| 定位 | 外部看护脚本 | 内置交互式 CLI |
| 运行方式 | 用 tmux 包装 `claude` | 直接在终端中运行 |
| 断连处理 | 监控 tmux 输出中的恢复关键词 | 使用 Claude CLI 自身的会话行为 |
| `continue` 处理 | 多次检测到可恢复信号后自动发送 `continue` | 通常由用户手动操作或由 CLI 自身逻辑处理 |
| 提示确认 | 自动确认常见 proceed/continue 提示 | 通常等待用户确认 |
| 后台运行 | 支持 `--daemon` | 主要面向前台交互使用 |
| 已有会话 | 可通过 `--attach` 监控已有 tmux 会话 | 不负责管理 tmux 会话 |
| 可靠性模型 | 基于简单文本匹配，容易理解，但可能漏判或误判输出 | 更接近 CLI 内部状态，但不是专门为无人值守自动化设计 |
| 风险 | 自动化程度更高，因此在敏感环境中风险也更高 | 更保守，更多由用户控制 |

适合使用本项目的场景：希望 Claude Code 在远程机器上持续运行，从终端可见的常见失败中恢复，或者长任务执行时不想一直盯着终端。

不适合使用的场景：不能接受自动确认提示、正在执行高风险命令，或者需要精确掌握 Claude 内部状态而不是依赖终端输出启发式判断。

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

对于同一段连续异常输出，监控器最多只会发送一次 `continue`。只有当监控输出中不再包含配置的恢复关键词后，后续新的异常才会再次触发 `continue`。
