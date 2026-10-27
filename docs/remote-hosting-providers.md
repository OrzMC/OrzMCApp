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
- MCSM 的**状态**仍然没有 WS：从不记 activity，`shouldRefresh` 自然退化成"按最小间隔轮询"，
  **不需要给 MCSM 另写一套节律**（控制台的实时流只喂日志，不改状态来源，见下节）；
- 换账号 `reset()` / 实例消失 `forget()`；订阅者保留，界面不用重订阅。

⚠️ 三条红线（P2-7 全程有效）：
1. **不要**改"WebSocket 是否安静 30 秒"这个轮询判据；
2. 状态徽章只有 `OrzMCStatusBadge` 一个实现；
3. 控制台解析按 Unicode 标量遍历，行尾 `\r` 不能丢整行（[`console-rendering.md`](console-rendering.md)）。

## 控制台实时流（B1，2026-10-27）

MCSM 控制台原来只能 3 秒轮询 `outputlog`；现在优先走**面板的实时流**，失败才回退轮询。
两条路共用 `ConsoleTextParser` + `ConsoleLineText` 渲染，用户看不出区别（只有顶部一格小字 Live/Polling）。

```
POST /api/protected_instance/stream_channel   → {addr, password, prefix}   （一次性口令）
        ↓
wss://<addr><prefix>/socket.io/?EIO=4&transport=websocket      （Engine.IO v4 / Socket.IO v5）
   emit stream/auth {data:{password:…}}  →  收 {data:true}
   emit stream/detail {}
   收 instance/stdout {data:{text:…}}   ← 节点的原始终端输出
```

分层：

| 层 | 文件 | 职责 |
|---|---|---|
| 协议 | `swift/lib/MCSManagerAPI`（product `MCSMStream`） | 地址解析、帧编解码、连接/心跳/重连、鉴权 |
| 接入 | `OrzMC/Common/MCSManager/MCSManagerPanelAPI.swift` + `MCSManagerAPIClient` | 申请通道（把生成类型抹平成 `MCSMStreamChannel`） |
| 界面 | `MCSManagerConsoleSheet` | 实时流优先；`.fallback` → 轮询；文本进 `ConsoleTextBuffer`（超长按行裁剪） |

必须知道的四件事：

1. **口令一次性**：每次重连都要重新申请通道 → `MCSMStreamClient` 收的是 `makeEndpoint` 闭包；
2. **`addr` 可能是节点视角**（`127.0.0.1:24444`）：回环地址换成本面板主机名，连不上就回退轮询
   （`dataPlane=direct` + 节点在 NAT 后面时这是**正常**路径，不是错误）；
3. **`/socket.io/` 尾部斜杠不能少**（少了 404 / `-1011` 握手失败），**必须回 pong**（否则 20~25 秒被踢）；
4. **状态不走这条流**：`RemoteStatusCenter` 仍是唯一状态来源（红线 1）。
   实时流只往控制台灌日志，`instance/stopped` 之类事件只用来更新时间戳，不改徽章。

自检（不需要看界面）：`ORZMC_DEMO_MCSM_DIAGNOSE=1 ORZMC_DEMO_MCSM_STREAM_PROBE=1`
→ 诊断文件里的 `stream` 字段会写明每台实例 `ready` / 输出片段 / 回退原因。

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
- **多面板**：添加 / **编辑** / 删除面板都在界面上做（URL + API Key + 可选名称）；
  删面板会同时停掉它的心跳、清掉 Keychain 里的 key —— 不影响其它面板的轮询。
- **编辑面板**（2026-10-26）：`⋯ → 编辑面板`。Key 留空 = 不修改（只换地址/名称时不用重新粘 key）；
  编辑不换面板 id（Keychain 里的 key 按 id 存），保存后立刻按新地址重新拉一次。
- **表单（含 macOS）**：地址边输入边校验；「测试连接」用**还没保存**的地址 + key 打一次
  `GET /api/auth`，直接报"连接成功、什么角色、名下几台实例"或**面板自己的错误文案**；
  macOS 上给足窗口尺寸（`minWidth 520 / minHeight 520`），iOS 用 `.large` detent。

### 界面验收钩子（仅 DEBUG）

- `ORZMC_DEMO_MCSM_DIAGNOSE=1`：**无界面**跑一遍所有面板（启动即拉、写文件后退出），
  结果在 `Caches/orzmc-mcsm-<面板 id>.json`：面板名 / 角色 / 实例数 / 每台实例的归一化状态 /
  失败原因 / **分支轨迹**（`currentUser` 的 permission、走的是管理员还是普通用户路径）。
  macOS 上 `screencapture` 要屏幕录制权限、远程托管还在辅助窗口里；iPhone SE 上 MCSM 分组在
  折叠线下 —— 有这个文件就不用靠截图猜。

### 面板 10.18.0 的两个坑（2026-10-26 实测）

| 坑 | 症状 | 处理 |
|---|---|---|
| `GET /api/auth` 的响应被包了一层 `{status, data: {…用户对象…}}` | 只按"裸用户对象"解 → `permission = nil / instances = 0`，普通用户永远看不到实例 | spec 同时声明两套字段，调用方取 `data ?? 顶层` |
| `data.loginTime` / `registerTime` 是字符串（`"2026-10-24 16:26:49"`） | 按 int64 解码 → 整条响应失败，`permission`/`instances` 全拿不到 | 这两个字段我们不用 → 从 schema 删掉（未知字段解码时忽略） |
| 错误响应 `Content-Type: text/plain`（body 是 JSON 文本） | 只声明 `application/json` → 面板的「密钥不正确」被丢掉 | 403/500 同时声明 `application/json` 与 `text/plain` |

- `ORZMC_DEMO_MCSM_FAKE=1`：内存里的假面板（两台实例：一在线一停止），不碰 Keychain、不发网络；
  UI 测试 `testMCSManagerSectionShowsInstancesAndStatus` 用它断言"能看到实例 + 状态徽章"。
- ⚠️ **不要在 SwiftUI 容器上设 `accessibilityIdentifier`**：它会下发给所有子元素并覆盖子元素自己的
  identifier（实测把状态徽章的 identifier 冲掉，UI 测试查不到）。容器只放一个最外层的
  `.accessibilityElement(children: .contain)` + identifier，内部靠 label 断言。

## 动作与控制台（第 5 步）

| 项 | 口径 |
|---|---|
| 端点 | `GET /api/protected_instance/{open,stop,restart}`、`GET /api/protected_instance/command?…&command=`、`GET /api/protected_instance/outputlog`（**纯文本**尾部） |
| 权限 | 中间件先校验"这台实例是不是你的"（`daemonId` + `uuid` 缺一个就 403），**再**看权限等级 → 普通用户的 key 完全够用，不需要管理员 |
| 互斥 | 复用 `RemoteActionGate`：**同一实例同一时刻只允许一个动作**，占用发生在首次 `await` 之前（网络慢时连点也只发一个请求）；命令不占用动作互斥，但同一实例同时只发一条 |
| 过渡态 | 提交后立刻把该实例显示成 `starting / stopping / restarting`（`RemoteServerAction.pendingState`），面板确认前用户能看到反馈；失败则撤回，并把**面板原话**写到实例行下面 |
| 可用性 | 过渡态（含 `busy`/未知）一律不允许动作 —— 与 exaroton 同一套判据（`RemoteServerListPolicy.canPerform`） |
| 错误文案 | 动作失败用 `MCSManagerErrorText.describeAction`：**原样转述面板原话**（「参数不正确或非法访问实例」「节点未连接」）。不能套"API Key 被拒绝"的框架 —— 那是列表接口的 403 语义，动作 403 指向排查方向会错 |
| 控制台 | 轮询 `outputlog`（3 秒，用户正盯着看），渲染走**同一套** `ConsoleTextParser` + `ConsoleLineText`（按 Unicode 标量、`\r` 覆盖不丢行）；命令输入框只在 `online` 时可用，发送失败会把内容还回输入框 |
| 认证细节 | 命令走**查询参数**（面板 `validator` 就这么写的），编码交给生成的客户端（`/say hi & bye` 往返一致） |

## MCSManager 接入要点（第 3–4 步实测/查证）

| 项 | 事实 |
|---|---|
| 鉴权 | 面板接受 `X-Request-API-Key` 头或 `?apikey=`；**必须在面板设置里打开 API Key 功能**，否则一律 403 |
| **权限分级** | **管理员**（`permission = 10`）用 `GET /api/service/remote_services` → `…/remote_service_instances` 列**全部**实例；**普通用户**（`permission = 1`）只能 `GET /api/auth?advanced=true` 列**自己的**实例（管理员端点对普通 key 一律 403，面板文案还可能误导成「密钥不正确」）。模型先取 `/api/auth` 看 `permission` 再选入口；普通用户没有实例时是正常结果（不报错、不去试管理员端点） |
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
| 5 | 动作 / 命令（MCSM 的 start/stop/restart + 控制台） | ✅ 2026-10-26 |

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
