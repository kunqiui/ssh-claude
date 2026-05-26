# SSH Claude — Apple Watch SSH 客户端

让你在 Apple Watch 上一键进 tmux + claude 会话，随手语音指令，断开还能继续跑。

## 架构

```
[Apple Watch]  <-- WatchConnectivity -->  [iPhone (SSH 客户端)]  <-- SSH -->  [Linux 服务器: tmux + claude]
```

- **iPhone**：保管 SSH 凭据（Keychain），维持 SSH 连接，所有 tmux 命令都从 iPhone 出口
- **Watch**：纯 UI + 系统听写，命令通过 WatchConnectivity 发给 iPhone

## 你需要先做的

### 1. 准备开发环境
- Xcode 16+（约 15GB，App Store 安装）
- Apple ID 登录 Xcode → Settings → Accounts（免费账号即可，证书 7 天有效）

### 2. 打开工程

```bash
open SSHClaude/SSHClaude.xcodeproj
```

依赖：[Citadel](https://github.com/orlandos-nl/Citadel)（Swift SSH 库）通过 SPM 自动拉取。

### 3. 在 Xcode 里设置签名团队
- 选择 `SSHClaude` target → Signing & Capabilities → Team 选你的 Apple ID
- 同样给 `SSHClaude Watch App` target 设置一遍
- Bundle ID 如已被占用，改一个唯一前缀（比如 `com.<你的名字>.SSHClaude`）

### 4. 跑起来
- iPhone 用 USB 连 Mac，开发者模式打开（Settings → Privacy & Security → Developer Mode）
- 顶部选你的 iPhone（不是 Simulator），Run
- 第一次启动会让你信任开发者证书：iPhone → Settings → General → VPN & Device Management
- Watch App 会通过 iPhone 自动安装；如果没自动装，去 Watch App（iPhone 上的）→ My Watch 里找到 SSH Claude，点安装

## 服务器端要求

服务器装 `tmux` 和 `claude` CLI。会话名包含 `claude` 会被 Watch 上识别为「Claude 会话」，并在新建时自动启动 `claude` 命令。如果你的 `ANTHROPIC_API_KEY` 写在 `~/.bashrc`，没关系——新建会话用 `bash -i -c` 启动，会加载交互式 shell 的环境变量。

## 使用流程

1. **iPhone 端**首次添加主机：填 host/port/user + 密码
2. **Watch 端**进入主机 → 看到 tmux 会话列表，紫色高亮的就是 claude 会话
3. 点进去看 pane（手动刷新或拉取）
4. 「说话或输入」按钮 → 系统听写 → 按发送
5. 下方按键：`/clear` / Ctrl-C / ↑ / ↓ / Enter

## 设计取舍

- **不在 Watch 上做真正的 PTY**：屏幕装不下，CPU/电池也撑不住。只显示 `tmux capture-pane` 的纯文本最近 N 行
- **不维持长 SSH channel**：每次操作都是一次性命令，断网/灭屏恢复都干净
- **凭据只在 iPhone**：Watch 永远只发 `hostId`，拿不到密码
- **Watch 端文本过滤**：屏蔽 `___` 分隔线、`tip:` / `? for shortcuts` 等装饰行，只显示有效内容

## 已知 TODO（生产前）

- [ ] `SSHClient.swift` 里 `hostKeyValidator: .acceptAnything()` 换成 known_hosts
- [ ] 私钥认证（目前只支持密码）
- [ ] 加重连指数退避
- [ ] 加 PaneUpdate 增量推送（diff），目前是全量字符串覆盖
- [ ] 加复杂功能页时考虑 watchOS 的 16KB applicationContext 大小限制

## 文件布局

```
ssh-claude/
└── SSHClaude/
    ├── SSHClaude.xcodeproj
    ├── SSHClaude/                        # iOS 主 App
    │   ├── SSHClaudeApp.swift
    │   ├── Models/
    │   │   └── WatchMessages.swift       # iPhone↔Watch 消息协议
    │   ├── Services/
    │   │   ├── SSHClient.swift           # Citadel 封装
    │   │   ├── TmuxManager.swift         # tmux 命令封装
    │   │   ├── KeychainStore.swift
    │   │   ├── ConnectionManager.swift   # 多主机连接池
    │   │   └── WatchBridge.swift         # WCSession 委托
    │   └── Views/
    │       └── HostListView.swift
    └── SSHClaude Watch App Watch App/    # watchOS App
        ├── SSHClaude_Watch_AppApp.swift
        ├── Models/
        │   └── WatchMessages.swift
        ├── Services/
        │   └── WatchClient.swift
        └── Views/
            ├── HostListWatchView.swift
            └── TerminalView.swift        # pane + 输入 + 按键
```
