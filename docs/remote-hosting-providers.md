# 远程托管供应商抽象层（多供应商 / 多实例）

> 状态：生效中（P2-7 第 1–2 步已完成，2026-10-25）· 对应代码 `Sources/OrzMCRemoteHosting/` +
> `OrzMC/Common/ExarotonUI/Model/ExarotonHostingProvider.swift` /
> `OrzMC/Common/ExarotonUI/Model/ExarotonServerModel+StatusCenter.swift`
> 交接入口：[`../../../HANDOFF.md`](../../../HANDOFF.md) §1 · 待办看板：[`backlog-2026-10-25.md`](backlog-2026-10-25.md) P2-7

## 目标

远程托管从「只支持 exaroton、单账号」扩展到**多供应商 + 每供应商多实例（多账号/多面板）**，
并且以后再加一家供应商**不需要动界面和状态中心**。

## 已拍板（维护者 2026-10-25）

1. MCSM 走**独立 OpenAPI 依赖**（`OrzMC/MCSManagerAPI`，与 `ExarotonAPI` 同构：`openapi.yml` +
   generator build plugin + `X-Request-API-Key` 中间件），不把两家接口揉进一个包；
2. 抽象层在 API 依赖**之上**，统一"实例 + 状态 + 动作"；
3. **能下沉的尽量下沉**到 `Sources/*`（可复用、可单测、各端不重复实现）；
4. 多供应商界面**按供应商分组**，不做"provider 过滤"。

## 分层

```
┌─ 界面（OrzMC/Common/*UI）─────────────── 只认 RemoteInstanceSummary / ProviderKind
├─ app 适配器（ExarotonHostingProvider …）─ 知道"怎么调某一家"
├─ 抽象层（Sources/OrzMCRemoteHosting）─── 供应商无关；不 import 任何 SDK
└─ API 客户端（ExarotonAPI / MCSMAPI）──── 各自 OpenAPI 生成，互不相识
```

抽象层不能 `import ExarotonAPI`：否则第二家供应商进来就要改抽象层。
反过来，SDK 也不该知道界面存在。

## 接口（`Sources/OrzMCRemoteHosting/RemoteHostingProvider.swift`）

```swift
public enum ProviderKind: String, CaseIterable, Codable, Sendable, Identifiable {
    case exaroton
    case mcsmanager          // MCSManager 面板：URL + apikey
}

public struct RemoteInstanceID {          // 全局键：供应商 + 该供应商内部的 ID
    let provider: ProviderKind
    let rawValue: String                  // description = "exaroton:ATMiLQGZ43vW2k3W"
}

public struct RemoteInstanceSummary {     // 列表/卡片要用的一切
    let id: RemoteInstanceID
    let name: String
    let address: String?                  // 有多个时给**稳定**那个
    let state: RemoteServerState          // online/offline/starting/stopping/restarting/unknown
    var provider: ProviderKind { id.provider }
}

public protocol RemoteHostingProvider: Sendable {
    var kind: ProviderKind { get }
    func listInstances() async throws -> [RemoteInstanceSummary]
    func perform(_ action: RemoteServerAction, on instance: RemoteInstanceID) async throws
}

public struct ClosureRemoteHostingProvider: RemoteHostingProvider { … }  // 两个闭包就能接入
```

### 不变量（有意为之，改之前先想清楚）

| 不变量 | 为什么 |
|---|---|
| **实例的键是 `RemoteInstanceID`（供应商 + 原始 ID），不是裸字符串** | 两家供应商的 ID 会撞（随机串 / 数字）；状态中心、订阅、Keychain 条目都以它为准 |
| `perform` 收到**别家**的实例时立刻抛 `wrongProvider`，不调底层闭包 | 多账号/多供应商交错时，"拿错模型"必须是显式失败，不能静默操作错服务器 |
| 动作被拒绝 → 抛 `actionFailed`（现有 exaroton 动作返回 `Bool`，适配器负责翻译） | 否则调用方会以为请求提交成功；用户侧提示仍由模型写进 `actionErrors`，适配器不重复弹窗 |
| 分组顺序固定为 `ProviderKind.allCases`，组内保持输入顺序 | 界面不能随网络返回顺序抖动 |
| 分组时**去掉重复实例**（保留第一份） | 多账号把同一实例拉了两遍时 `ForEach` 的 `Identifiable` 会渲染错行 |
| 状态**不在供应商里推**，仍走唯一状态中心 | 见下节 |

## 状态：仍然只有一个来源

供应商只**喂数据**（`listInstances()` / 适配器把 WS 推送写进状态中心），
判"该不该轮询"的逻辑只有一份：`RemoteStatusRefreshPolicy` + 唯一写入口 `publishStatus` +
订阅 `statusEvents()`。详见 [`remote-status-source.md`](remote-status-source.md)。

第 2 步把状态中心下沉成供应商无关的 `RemoteStatusCenter`（`Sources/OrzMCRemoteHosting`）：

```swift
let center = RemoteStatusCenter()                       // 一个账号/面板一份
center.publish(.init(state: .online, rawStatus: 1),     // 唯一写入口（WS / 轮询 / 调试注入）
               for: RemoteInstanceID(provider: .exaroton, rawValue: "srv"),
               source: .webSocket)
for await change in center.events() { /* 只在真变化时收到 */ }
center.noteWebSocketActivity()                          // 推送通道还活着
center.beginRefresh(); center.finishRefresh()
center.shouldRefresh(hasCredentials: true, isAppActive: true, isLoading: false)
```

- 键是 `RemoteInstanceID`（供应商 + 原始 ID），不是裸字符串；
- `RemoteInstanceStatus` 同时保留 `state`（归一化）与 `rawStatus`（供应商状态码），
  细节（LOADING / PREPARING）不丢；
- MCSM 没有 WS：从不记 activity，`shouldRefresh` 自然退化成"按最小间隔轮询"，
  **不需要给 MCSM 另写一套节律**；
- 换账号 `reset()` / 实例消失 `forget()`；订阅者保留，界面不用重订阅。

⚠️ 三条红线（P2-7 全程有效）：
1. **不要**改"WebSocket 是否安静 30 秒"这个轮询判据；
2. 状态徽章只有 `OrzMCStatusBadge` 一个实现；
3. 控制台解析按 Unicode 标量遍历，行尾 `\r` 不能丢整行（[`console-rendering.md`](console-rendering.md)）。

## 分组（`RemoteHostingGrouping`）

```swift
RemoteHostingGrouping.groups(from: instances)
// → [RemoteHostingGroup(.exaroton, [...]) , RemoteHostingGroup(.mcsmanager, [...])]
```

界面按这个结果渲染 section；**没有实例的供应商不出现**（不给空 section）。

## 界面口径（第 4b 步）

- **按供应商分组**：`ExarotonContent` 里 exaroton 列表保持原样，MCSManager 是同一页里
  **独立的一组**（`MCSManagerSection`，每个面板一张卡 → 实例行 + 状态徽章）。
  这样"分组"是真的分组，而不是把两家的卡片混在一串里；exaroton 的既有交互（额度池、控制台）零改动。
- **供应商无关的摘要**：`MCSManagerPanelsModel.instanceSummaries()` / `hostingGroups`
  已经能出 `RemoteInstanceSummary` / `RemoteHostingGroup`（按供应商排序、去重），
  将来做"统一实例列表"时直接用，不必再动模型。
- **状态徽章只有一个实现**：`OrzMCStatusBadge` + `RemoteServerState.localizedTitle/statusStyle`
  （文案复用 exaroton 那套已翻译的键，所以没有新增状态文案）。
- **多面板**：添加/删除面板在界面上就能做（URL + API Key + 可选名称）；
  删面板会同时停掉它的心跳、清掉 Keychain 里的 key —— 不影响其它面板的轮询。

### 界面验收钩子（仅 DEBUG）

- `ORZMC_DEMO_MCSM_FAKE=1`：内存里的假面板（两台实例：一在线一停止），不碰 Keychain、不发网络；
  UI 测试 `testMCSManagerSectionShowsInstancesAndStatus` 用它断言"能看到实例 + 状态徽章"。
- ⚠️ **不要在 SwiftUI 容器上设 `accessibilityIdentifier`**：它会下发给所有子元素并覆盖子元素自己的
  identifier（实测把状态徽章的 identifier 冲掉，UI 测试查不到）。容器只放一个最外层的
  `.accessibilityElement(children: .contain)` + identifier，内部靠 label 断言。

## MCSManager 接入要点（第 3–4 步实测/查证）

| 项 | 事实 |
|---|---|
| 鉴权 | 面板接受 `X-Request-API-Key` 头或 `?apikey=`；**必须在面板设置里打开 API Key 功能**，否则一律 403 |
| 403 的含义 | 面板会说明具体原因（`{"status":403,"data":"密钥不正确"}` / 「API Key功能已关闭」/「权限不足」）。app 现在**转述面板原话**（`MCSManagerModelError.unauthorized(panelMessage:)`），比统一猜一句准 —— 只有响应体读不出来时才用兜底句子 |
| 请求超时 | 20 秒（`MCSMClient.defaultTimeout`）。面板在 Cloudflare Tunnel 后面时首次请求实测要 17 秒；超时太短会误报，太长会一直停在「加载中…」 |
| 实例归属 | 面板 → 节点（daemon）→ 实例：列表要按节点查，所以实例 id 用 `daemonId/instanceUuid` |
| 状态 | 面板给 `-1 busy / 0 stopped / 1 stopping / 2 starting / 3 running`；`busy` 底层状态不明 → 归一化 `.unknown`（禁用动作） |
| 实时性 | **没有 WebSocket**：只能 HTTP 轮询；`RemoteStatusCenter` 在"从未有 WS 消息"时自然按最小间隔轮询，不用另写节律 |
| 内存 | Docker 实例的内存上限在 `config.docker.memory`（MB）；普通实例没有统一字段 |
| 分页 | 实例列表 `page_size` 最多 50，按 `maxPage` 翻页（模型里有 20 页防御上限） |

## 进度

| 步骤 | 内容 | 状态 |
|---|---|---|
| 1 | `RemoteHostingProvider` / `ProviderKind` / `RemoteInstanceSummary` 定稿 + exaroton 适配器（行为不变） | ✅ 2026-10-25 |
| 2 | `ExarotonStatusCenter` → 供应商无关的 `RemoteStatusCenter`（`RemoteStatusRefreshPolicy` 下沉到库） | ✅ 2026-10-25 |
| 3 | `swift/lib/MCSManagerAPI`（新仓库 `OrzMC/MCSManagerAPI`）：节点列表 + 实例列表 + 实例详情 | ✅ 2026-10-25 |
| 4a | app 侧 MCSM **数据层**：`MCSManagerPanel`（地址规范化）+ Keychain 凭据 + `MCSManagerModel`（列实例 / 轮询状态 / 挂 `RemoteHostingProvider`） | ✅ 2026-10-25 |
| 4b | app 侧 MCSM **界面**：远程托管页按供应商分组（exaroton 一组 + MCSManager 一组）、面板配置（URL + apikey）入口、实例卡片 + 状态徽章 | ✅ 2026-10-25 |
| 5 | 动作 / 命令（MCSM 的 start/stop/restart + 控制台） | 待做（多面板增删界面已在 4b 做了） |

验收口径（维护者）：新增一个 MCSM 面板（URL + apikey）后，在同一个「远程托管」页里能看到实例并
实时看到状态变化；切换/删除账号不影响其他账号的轮询。

## 涉及文件

| 文件 | 作用 |
|---|---|
| `swift/lib/MCSManagerAPI`（子模块） | MCSManager 面板 API 客户端（OpenAPI 生成；端点/口径见该仓库 README） |
| `OrzMC/Common/MCSManager/MCSManagerPanel.swift` | 面板身份（地址规范化）+ 凭据存储（面板在 `UserDefaults`、API Key 在 Keychain） |
| `OrzMC/Common/MCSManager/MCSManagerPanelAPI.swift` | app 内部的**只读面板接口**（模型只依赖它 → 单测不碰 OpenAPI 类型） |
| `OrzMC/Common/MCSManager/MCSManagerAPIClient.swift` | 真实实现：`MCSMAPI` 生成类型 → 上面的接口（403 → `unauthorized` 等） |
| `OrzMC/Common/MCSManager/MCSManagerPanelsModel.swift` | 多面板聚合：增删面板、每个面板一份 `MCSManagerModel`（各自状态中心/心跳）、`hostingGroups` |
| `OrzMC/Common/MCSManagerUI/MCSManagerSection.swift` | 远程托管页里的 MCSManager 分组（面板卡 + 实例行 + 添加面板表单） |
| `OrzMC/Common/RemoteHosting/RemoteServerState+Presentation.swift` | 供应商无关状态 → 文案/徽章风格（复用已翻译的键） |
| `OrzMC/Common/MCSManager/MCSManagerModel.swift` | `@MainActor @Observable`：列实例（分页取全）、按 `RemoteStatusRefreshPolicy` 轮询、状态写进 `RemoteStatusCenter`、`MCSManagerHostingProvider`（只读） |
| `OrzMC/Common/MCSManager/MCSManagerErrorText.swift` | 面板错误 → 一句人话（403 的含义与 exaroton 不同：可能是"没开 API Key 功能"） |
| `Sources/OrzMCRemoteHosting/RemoteHostingProvider.swift` | `ProviderKind` / `RemoteInstanceID` / `RemoteInstanceSummary` / 协议 / 分组 / 闭包适配器 |
| `Sources/OrzMCRemoteHosting/RemoteServerState.swift` | 归一化状态、动作、列表策略（搜索 + 动作可用性） |
| `Sources/OrzMCRemoteHosting/RemoteStatusCenter.swift` | 供应商无关的状态中心 + `RemoteStatusRefreshPolicy`（30 秒判据） |
| `OrzMC/Common/ExarotonUI/Model/ExarotonServerModel+StatusCenter.swift` | exaroton 接缝：状态码换算、`publishStatus` / `statusEvents` / `effectiveStatus` / `liveStatuses` |
| `OrzMC/Common/ExarotonUI/Model/ExarotonHostingProvider.swift` | exaroton 适配器：`servers` → 摘要（状态取 `effectiveStatus`）、动作 → 现有 start/stop/restart |
| `Tests/OrzMCRemoteHostingTests/RemoteHostingProviderTests.swift` | 抽象层单测（命名空间、分组、闭包适配器、错误透传） |
| `OrzMCTests/ExarotonHostingProviderTests.swift` | exaroton 适配器单测（映射、静态地址优先、无 id 跳过、拒绝别家实例） |
