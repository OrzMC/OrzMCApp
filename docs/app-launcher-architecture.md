# macOS 启动器：模型划分与职责

> **状态**：生效中｜**最后更新**：2026-10-20
> **背景**：`GameModel` 曾是一个 390 行的上帝对象（UI 状态 + 5 个服务 + 进度镜像 + 进程登记），
> 任何改动都要碰它，也测不了。现在按关注点拆成六个模型，逻辑尽量下沉到 `Sources/OrzMCLauncher`。
> 平台分层见 [`app-platform-split.md`](app-platform-split.md)。

## 1. 模型地图

```
AppModel（组合根，只做编排）
├── settings      SettingsModel        设置（UserDefaults 持久化；游戏根目录/内存/客户端类型…）
├── catalog       VersionCatalogModel  版本列表、过滤、选中、装了什么、gameInfo
├── launch        LaunchModel          启动（client/server）+ 进度
├── servers       ServerRegistryModel  自己启动过的服务端：登记/探活/停止
├── java          JavaRuntimeModel     托管 JRE 状态
└── plugins       PluginDownloadModel  Paper 插件批量下载
```

**规则**：`AppModel` 不写业务，只转发（选择变化 → 刷 JRE/进程视图、启动按模式分流、错误收进 `error`）。
跨模型通信走回调/显式调用，模型之间不互相持有。

## 2. 逻辑在哪（可测的部分）

| 逻辑 | 位置 | 测试 |
|---|---|---|
| 版本过滤（搜索/正式版） | `Sources/OrzMCLauncher/VersionListFilter.swift` | `VersionCatalogTests` |
| 装了什么（客户端/服务端目录） | `InstalledVersionScanner` | `InstalledVersionScannerTests` |
| 进度语义与文案 | `LaunchProgressState` | `LaunchProgressStateTests` |
| 进程登记（落盘）+ 探活 | `ManagedServerProcessStore` / `ProcessLivenessProbing` | `ServerProcessStoreTests` |
| JRE 判定 | `JavaRuntimePolicy` | `LauncherPolicyTests` |
| `install.conf` 的 surface/source 语义 | `InstallRecordView` / `InstallSurfacePolicy` | `InstallRecordViewTests` |
| 错误码保留 | `CodedError` / `LauncherError` | `LauncherErrorTests` |

**判据**：能写成"输入→输出"的，一律进 `Sources/`；剩下不可测的只该是"调引擎 + 赋值状态"。

## 3. 几条硬约定（踩过坑）

1. **进度只有一个状态**：`LaunchProgressState`。加了新的进度字段先问"能不能塞进它"，别再散着加。
2. **进程只认自己启动的**：登记落盘在 `~/Library/Application Support/OrzMC/servers.json`，
   探活用 `kill(pid, 0)`。**不要**再用 `ps` 全机搜 `nogui` —— 会把别人的服务端算成自己的，`Stop All` 会误杀。
3. **错误必须带码**：`LauncherError.wrap(_:fallbackCode:)`，UI 显示「人话 (E_XXX)」。
4. **视图不做 IO、不管状态**：装了什么由模型算好传进来（列表滚动时不再逐行 stat）。
5. **参数校验共用引擎规则**：内存走 `MemorySpec`，别在 GUI 重写一份正则。
6. **多实例 = 换游戏根目录**：`settings.rootDir` 会透传到 `ClientInfo`/`ServerInfo`/`GamePlan.*(root:)`/JRE 扫描；
   改根会重算"装了什么"、重置 JRE 与进程视图。
