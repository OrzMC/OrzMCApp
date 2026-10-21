# 服务端控制台：怎么验收

> **状态**：生效中｜**最后更新**：2026-10-21

分两层：**能自动跑的**（模型 + 真进程，CI 覆盖）和**必须人眼看的**（SwiftUI 观感）。

## 1. 自动验收（不需要 GUI）

```bash
scripts/air/run.sh app-test                       # 全部单测
scripts/air/run.sh sh 'cd ~/orzmc-build/app && swift test --filter ServerConsole'
```

覆盖到的东西（`ServerConsoleBufferTests` 9 例 + `ServerConsoleEndToEndTests` 3 例）：

| 关注点 | 怎么验 |
|---|---|
| ANSI 颜色码剥离 | `\u{1B}[32m…\u{1B}[0m` → 纯文本 |
| 字节块切成行 | 半行等齐再出，停止时 `flush` 不丢最后一行 |
| `\r` 进度条覆盖 | 只保留最后状态，不留"半行垃圾" |
| 上限与裁剪 | 2000 行、命令历史 100 条、连续重复不重复记 |
| **命令真送到子进程** | 起 `/bin/sh` 假服务端，`console.send("say hello")` → 断言收到 `[Server] say hello` |
| 退出后拒绝发送 | `stop` → 子进程退出码 0 → `detach` → 再 `send` 返回 false |

> 真实链路与测试只差一个接线点：`ServerInfo.onServerLog` 指向 `console.append`
> （测试里指向同一个方法）。

## 2. 人工验收（要一台能跑 GUI 的机器）

### 前置：**本机（macOS 13 / x86_64）跑不了**

app 的 `MACOSX_DEPLOYMENT_TARGET = 14.0`，本机是 **macOS 13.7.8** → 装回来也起不来。
能跑 GUI 的机器：**air（macOS 27 / arm64）**，或任何 macOS 14+ 的 Mac。

### 在 air 上跑

```bash
scripts/air/run.sh app          # 构建（增量 ~17s）
scripts/air/run.sh app-run      # 在 air 上打开刚构建的 app
```

### 验收步骤（按顺序）

1. 左侧选一个版本 → 模式切到 **Server** → 选核心（Paper/Vanilla/Fabric/Forge）→ **Start Server**；
2. 等日志刷起来（下载/安装阶段的进度在按钮上，运行期日志在控制台里）；
3. 右侧实例列表里，**每个实例那一栏的标题行**都有自己的控制台入口（终端图标，运行中是绿色实心）：
   - 服务端：Paper / Vanilla / Fabric / Forge 各一栏，各自独立；
   - 客户端：`Client` 那一栏也有（`版本#Client`）；
   - 标题是 `Console — 1.21.5 Paper` / `Console — 1.21.5 Client`，左侧绿点 = 该实例进程在跑；
   - 日志**没有** `[32m` 之类的颜色码乱码；可选中复制；新行自动滚到底；
4. 输入 `say hello` 回车 → 控制台里出现强调色的 `say hello` 回显 + 服务端回显 `[Server] hello`；
5. 按 **↑** → 输入框回填 `say hello`；再按 **↓** → 清空；
6. 输入 `op <你的名字>` / `whitelist add <名字>` 验证任意命令都能送；
7. 输入 `stop` → 服务端优雅退出 → 控制台出现 `Server exited (code 0)`，绿点变灰、输入框禁用、
   **日志仍保留**（用于事后排查）；
8. **多实例隔离**：同时起 Paper 与 Vanilla 两个实例 → 两个控制台各自只显示自己的日志，
   `say` 只进对应的那个服务端；删掉某实例的文件后它的控制台一并清空，别的实例不受影响；
9. 点 **Clear**：该实例日志清空、**命令历史还在**（按 ↑ 仍能翻到 `stop`）。

### 详情页的实例栏（布局与安全）

- 左：实例名 + **运行状态**（服务端和客户端都有 Running/Stopped 徽标）；
  客户端状态以"客户端控制台是否挂着进程"为准（游戏退出即变 Stopped）。
- 右：**控制台 / 停止 / 删除** 三个图标按钮（控制台运行时绿色实心、停止橙色、删除红色）。
- **高危操作都要二次确认**：删除（不可恢复，弹窗里带路径与后果）、停止单个服务端（在线玩家会掉线）、
  菜单里的「Stop All Servers」（同理）。
- **防连点**：某实例有操作在进行时，该实例全部按钮禁用并显示小转圈；「停止全部」执行期间也禁用。

### 已知边界

- 截图/自动化点击拿不到（SSH 会话没有"屏幕录制/辅助功能"权限）→ 观感只能人眼看；
- 控制台按实例（`版本#核心`，客户端是 `版本#Client`）隔离：同一实例重复启动会换新的进程句柄，
  但日志延续（便于对照）；
- 客户端与**服务端**走同一套：日志来自 `ClientInfo.onClientLog`，命令同样经 `ManagedProcess.send`
  （Minecraft 客户端本身不接受控制台命令，能发但一般不会有回应——入口仍然有用：能看游戏日志/崩溃输出）。
