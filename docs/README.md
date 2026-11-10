# OrzMCApp 文档索引

> **状态**：生效中｜**最后更新**：2026-11-09
> 这里只放**现行**文档。一次性交接 / 复盘 / 截图清单在 PR 合并后删除（历史在 `git log`），
> 相关知识并入下面对应的现行文档。新增文档：头部写「状态 / 最后更新」，并在本表登记。

## 架构与分层

| 文档 | 说明 |
|---|---|
| [`app-launcher-architecture.md`](app-launcher-architecture.md) | macOS 启动器的模型划分与职责（谁持有状态、谁负责 I/O） |
| [`app-platform-split.md`](app-platform-split.md) | macOS / iOS 哪些共用、哪些分开；`Sources/*` 不得 import AppKit/UIKit |
| [`server-storage.md`](server-storage.md) | 服务器资料（含 RCON 密码）的保存方式：本地 / iCloud / Keychain 路由 |

## 界面与设计

| 文档 | 说明 |
|---|---|
| [`app-ui-design.md`](app-ui-design.md) | **UI 主文档**：服务器页合并、卡片/动作/刷新、设计令牌、遗留项 |
| [`ui-server-cards-2026-11-07/`](ui-server-cards-2026-11-07/) | 卡片统一前后的截图（被 UI 主文档引用） |
| [`ui-selfhosted-list-2026-11-07/`](ui-selfhosted-list-2026-11-07/) | 「我的服务器」改卡片列表 + 详情页的截图 |
| [`ui-remote-hosting-2026-11-05/`](ui-remote-hosting-2026-11-05/) | 远程托管跨端骨架重构的截图 |
| [`ui-remote-add-provider-2026-11-06/`](ui-remote-add-provider-2026-11-06/) | 页顶统一「添加服务器」入口的截图 |
| [`ui-sidebar-perf-2026-11-07/`](ui-sidebar-perf-2026-11-07/) | 侧边栏收起/展开卡顿（`.prominentDetail`）的取证截图 |
| [`ui-storage-mode-2026-11-08/`](ui-storage-mode-2026-11-08/) | 设置里的保存方式 / 清除本地数据的截图 |

## 控制台

| 文档 | 说明 |
|---|---|
| [`console-rendering.md`](console-rendering.md) | ANSI / Minecraft 颜色解析与渲染分层（Foundation → DesignSystem → 三处控制台） |
| [`console-acceptance.md`](console-acceptance.md) | 控制台怎么验收（本地 / RCON / exaroton / MCSM，含锚点与用例） |
| [`ui-console-redraw-2026-11-05/`](ui-console-redraw-2026-11-05/) | 重绘修复前后的截图（被 `console-rendering.md` 引用） |

## 远程托管

| 文档 | 说明 |
|---|---|
| [`remote-hosting-providers.md`](remote-hosting-providers.md) | 供应商抽象层：多供应商 / 多账号 / 动作 / 控制台流 / 分组 |
| [`remote-status-source.md`](remote-status-source.md) | 远程状态的唯一来源（WS 优先、HTTP 兜底、新鲜度规则） |

## 流程与工具

| 文档 | 说明 |
|---|---|
| [`iteration-flow.md`](iteration-flow.md) | 迭代流程：本地门禁、CI job、界面验收、真机 UI 测试 |
| [`ios-self-hosted.md`](ios-self-hosted.md) | iOS 自建服务器（RCON）最小闭环 |
| [`ios-release.md`](ios-release.md) | iOS 归档、TestFlight、真机开发签名装包 |
| [`doc-publishing.md`](doc-publishing.md) | DocC → GitHub Pages 的发布流程（根路径直达、为什么不用缓存） |

## 发版

| 文档 | 说明 |
|---|---|
| [`release-signing.md`](release-signing.md) | macOS Developer ID 签名：描述文件、`MACOS_PROFILE`、为什么只作用于 app target |
| [`release-notes/`](release-notes/) | 每个版本的更新说明（`0.1.3` … `0.1.7`） |

## 约定

- **文档过期就改或删**：状态标「完成 / 已收口」的一次性文档不要长期留在 `docs/`。
- **截图**：放 `docs/<主题>-<日期>/`，且**只保留被现行文档引用的**；删文档时一起删。
- **引用脚本/文件路径**：改代码时顺手核对，避免文档里出现不存在的脚本。

## AI 流水线（EasyGithub）

- Issue 打上 `ai` 标签后，流水线会在 `ai/issue-<n>` 分支上自动实现并开 PR。
- 低风险且通过门禁的改动会自动合并；高风险改动会以草稿 PR 形式等待人工确认。
- 需要人工决策时，流水线会在 Issue 里提问并打 `ai-needs-input` 标签。

## 常见问题

- 构建失败先看 `./scripts/dev/check.sh --fast`，它只跑静态检查。
- 发布流程见 `docs/release-*.md`。

## 目录结构

- `Sources/`：跨平台逻辑与 SwiftPM 目标。
- `OrzMC/`：应用层与平台专属代码。
- `OrzMCTests/`、`OrzMCUITests/`：单测与 UI 测试。

## 环境要求

- macOS + Xcode（版本见 `Package.swift`）。
- 首次构建前执行 `swift package resolve`。

## 常见问题

- 构建失败先看 `scripts/check-platform-split.sh`。
- 发布流程见 `docs/releases.md`。

## 贡献方式

- 提交前请先在本机跑一遍 `bash scripts/check-platform-split.sh`。
- PR 请保持单一主题，便于评审。

## 自愈验证 A

- 这一节由流水线自动添加。

## 自愈验证 B

- 这一节同样由流水线自动添加。
