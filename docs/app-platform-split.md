# 平台分层：macOS / iOS 哪些共用、哪些分开

> **状态**：生效中｜**最后更新**：2026-10-20
> **背景**：iOS target 与 macOS 的功能**不完全相同**。共用部分统一收敛后一次迭代，
> 各自独有的部分单独迭代。本文就是那条分界线，改代码前先按它判断"该放哪里"。

---

## 1. 一图看清

```
swift/app/
├── Package.swift            ← 平台无关的**逻辑**（SwiftPM 目标，可单测，两平台共用）
│   └── Sources/
│       ├── OrzMCFoundation/      基础类型（进程标识等）
│       ├── OrzMCLauncher/        启动器策略：JRE 判定 / 版本过滤 / 进程登记 / 安装记录语义
│       ├── OrzMCProtocol/        **iOS 专用**：服务器状态查询（SLP）/ Query / RCON 协议
│       ├── OrzMCRemoteHosting/   iOS 远控 helper 的托管逻辑
│       └── OrzMCDesignSystem/    共用样式与内容态
└── OrzMC/                   ← 应用本体（**一个多平台 target**，macOS + iOS 各编一遍）
    ├── Common/ExarotonUI/        **两平台共用**的 Exaroton 面板（视图 + 模型）
    ├── Launcher(MacOS)/          **仅 macOS**：客户端/服务端启动、设置页、侧边栏与详情
    └── MobileHelper(iOS)/        **仅 iOS**：远控 helper 的界面与入口
```

Xcode 工程对平台差异用 **`platformFilter`**（文件级）兜住；SwiftPM 侧用 `#if os(...)`。

## 2. 判定树：新代码放哪？

| 代码性质 | 放这里 | 说明 |
|:--|:--|:--|
| 纯逻辑（判定、算法、模型、路径求值），两平台都要 | `Sources/<Target>/` | **首选**：能在 `swift test` 里跑，不用起模拟器 |
| 视图/视图模型，两平台都要 | `OrzMC/Common/` | 用一个多平台 target 编两遍；平台差异写 `#if os(...)` |
| 只有 macOS 有（启动游戏、服务端进程、设置页） | `OrzMC/Launcher(MacOS)/` | 在 Xcode 里打 `platformFilter = macos` |
| 只有 iOS 有（远控 helper） | `OrzMC/MobileHelper(iOS)/` | 打 `platformFilter = ios` |
| 协议/网络编解码（可离线测） | `Sources/<Target>/` | 反例警示：不要塞进 app target（无法测试） |

**硬规则**：`Sources/*` 里**不得** `import AppKit` / `import UIKit`（`SwiftUI` 可以）。
用 `scripts/check-platform-split.sh` 校验，CI 会跑。

## 3. 现状：哪些是真共用

| 能力 | macOS | iOS | 结论 |
|:--|:--|:--|:--|
| `install.conf` 语义（`surface` / `source` / 能否原地升级） | ✅ | — | 逻辑已在 `Sources/OrzMCLauncher/InstallRecordView.swift`（共用目标，iOS 之后可直接用） |
| Exaroton 面板（服务器列表/详情/额度） | ✅ | ✅ | **共用**：`OrzMC/Common/ExarotonUI/` |
| 版本目录 / JRE 判定 / 版本过滤 | ✅ | — | 逻辑在 `Sources/OrzMCLauncher/`（平台无关，iOS 想用可直接引） |
| 客户端启动、服务端四类型、托管 JRE | ✅ | — | 引擎在 `OrzMCKit`（`Game`），GUI 只做编排 |
| **服务器状态查询（SLP / Query / RCON）** | — | ✅ | iOS 专用，`Sources/OrzMCProtocol/` |
| 远控 helper 托管 | — | ✅ | `Sources/OrzMCRemoteHosting/` |

> 也就是说：**"共用"的边界不在 UI，而在逻辑**。iOS 想加 macOS 已有的能力（如版本目录），
> 直接引 `OrzMCLauncher` 目标即可，不要复制实现。

## 4. 迭代顺序建议

1. **共用逻辑先行**（`Sources/`）：改一次、两个平台都受益、还能单测；
2. 共用 UI 其次（`OrzMC/Common/`）：改动必须**两个平台的构建都过**；
3. 平台专属最后：各自独立 PR，互不阻塞。

## 5. 构建与验证

| 目标 | 命令 |
|:--|:--|
| macOS（本地车道，增量 ~17s） | `scripts/air/run.sh app` |
| iOS 模拟器（本地车道） | `scripts/air/run.sh app-ios` |
| 单测（平台无关部分） | `scripts/air/run.sh app-test` |
| 平台分层校验 | `./scripts/check-platform-split.sh` |
| 三条 CI | `.github/workflows/ci.yml`（macOS / iOS / 分层校验） |

> 历史坑：iOS 侧**以前从没被构建过**（CI 只构建 `platform=macOS`），也就是说
> iOS 代码路径可以腐烂很久而没人知道。2026-10-20 起 CI 加 iOS 构建 + 分层校验。
