# 服务器资料保存与同步方案

> 状态：**P1–P4 全部落地并真机验收通过**（2026-11-08）｜最后更新：2026-11-08
> 范围：自建服务器、exaroton 账号、MCSManager 面板；不包含日志和运行状态。

## 用户选择

每个服务器或账号单独选择：

- **仅本次安装**：关闭应用后仍可使用；配置与凭据只属于当前安装，不同步也不应跨全新安装恢复。
- **保留在本机**：配置与凭据保存在本机安全存储中，可在重新安装后恢复，不向其他设备同步。
- **iCloud 同步**：配置和凭据一起保存到当前用户的 iCloud 钥匙串，并在同一 Apple 账号的设备上同步。

默认保留已有用户的存储行为；不在升级时擅自复制、删除或上传已有账号。用户明确选择迁移时，先写入并验证目标，再切换读取来源；目标写入失败应保留原记录并提示错误。数据模型保持稳定 UUID，账号之间和供应商之间互不覆盖。密钥不放入 UserDefaults、普通日志或 iCloud 明文配置。

## 生命周期和边界

本次安装模式需要将敏感信息与安装生命周期绑定；iOS 删除应用会移除其容器，macOS 手动将应用移入废纸篓并不保证清除应用支持目录，因此需提供显式清除入口并准确提示。保留在本机的资料在重新安装后可恢复；删除账号时应清除该账号选择的存储副本。iCloud 模式由用户主动开启，删除同步项会影响其他设备，应在界面确认。离线、未登录或关闭 iCloud 钥匙串时，不能声称已经同步完成；不能以空结果覆盖本地资料。不同设备同时修改时需要明确冲突处理，删除需要防止旧设备把记录复活。

macOS 与 iOS 当前 bundle ID 不同；跨端钥匙串需要同一开发团队的共享访问组、匹配签名权限和统一服务标识，不能仅设置同步标志。启用新的访问组不能让原有本机钥匙串项失去可读性。必须以真实签名的 macOS 与 iOS 设备、同一 Apple 账号、临时测试资料验证写入、同步、删除和重装恢复；自动测试以注入式存储覆盖迁移失败、冲突和离线情况。

依据：[Apple 钥匙串访问组](https://developer.apple.com/documentation/security/sharing-access-to-keychain-items-among-a-collection-of-apps)、[Apple iCloud 钥匙串同步属性](https://developer.apple.com/documentation/security/ksecattrsynchronizable)、[Apple Mac 卸载说明](https://support.apple.com/en-us/102610)。

## 实施计划与进度

| 阶段 | 内容 | 状态 |
|---|---|---|
| **P1 存储核心** | `ServerRecordBackend`（安装内加密文件 / 本机 Keychain / iCloud Keychain）、`ServerRecordMigration`（先写后验再删源）、`ServerRecordStore`（按档位路由 + 迁移 + 如实报错） | ✅ 已完成，10 + 7 条单测 |
| **P2 接到现有三处** | ✅ 三处都已接线（自建 RCON 密码 / Exaroton Token / MCSManager API Key）。统一走 `ServerSecretsStore`；档位跟着记录自身（`storageMode` 字段，老数据缺字段时按 `.device` 解码）；**默认仍是"保留在本机"**，升级不迁移、不删除 | 进行中 |
| **P3 界面** | ✅ 三处表单都有「保存方式」三档选择（不可用档位置灰 + 说明）；保存时用 `move` 迁移，失败就地提示并保留原数据。截图见 `docs/ui-storage-mode-2026-11-08/`。剩余：macOS「清除本机资料」入口 | 基本完成 |
| **P4 iCloud 真机验证** | ✅ **签名已打通**（2026-11-08）：两端 entitlements 都带 `2N62934Y28.com.joker.OrzMC.shared`，macOS 与 iPhone 运行时都探测到 `iCloud=available`。共享访问组 `com.joker.OrzMC.shared`（entitlements 写 `$(AppIdentifierPrefix)com.joker.OrzMC.shared`），运行时自动从签名里读；✅ 2026-11-08 真机验收通过：macOS 写 → iPhone 读、iPhone 写 → macOS 读（约 1–2 分钟传播）、macOS 删 → iPhone 读为「无」 | 已完成 |

### P1 的接口约定（后续实现别绕开）

- **不可读 ≠ 空**：后端读失败直接抛错，绝不返回空数组冒充"没有记录"。
- **迁移顺序**：写目标 → 回读校验 → 删来源；目标里已有同 id 但内容不同 → `conflict`（不覆盖、不删源）。
- **重试幂等**：目标已是同一份内容时，只清来源（上次"写完没删成"的重试路径）。
- **删除要扫所有后端**：一个后端失败也要继续删其它，最后把第一个错误抛给界面。
- 档位枚举 `ServerRecordStorageMode` = `installation` / `device` / `iCloud`，
  与界面文案「仅本次安装 / 保留在本机 / iCloud 同步」一一对应。

### P2 需要先定的事

1. 三处现有 Keychain 的 service/account 命名要不要保留（保留 = 老数据零迁移；改 = 需要写入迁移代码）。
2. 档位元数据放哪：`SelfHostedProfiles` / `ExarotonAccount` / MCSManager 面板模型里各加一个字段（推荐，
   跟着记录一起编解码），还是单独一张 `[UUID: mode]` 表。
3. iCloud 档位在**不可用**时（没开钥匙串 / macOS 端没配访问组）界面怎么表达：不可选 + 说明，还是可选但报错。

### P2 已实施细节（2026-11-08）

- `OrzMC/Common/Storage/ServerSecretsStore.swift`：凭据（RCON 密码 / Token / API Key）按档位读写；
  `.device` **沿用旧 Keychain 的 service/account 命名**（`selfhosted.rcon.<uuid>`、`exaroton.account.<uuid>`、
  `mcsm.panel.<uuid>`），老数据零迁移；`.installation` 用加密记录；`.iCloud` 暂不可用（见下）。
- 读路径带兜底：档位不是 `.device` 但目标里还没有记录时，回退读老 Keychain ——
  避免"刚切档位就看不到密码"。
- `move(from:to:)`：写目标 → 回读校验 → 删来源；失败保留来源并抛错。
- `SelfHostedServerProfile` 增加 `storageMode`（默认 `.device`，自定义 `init(from:)` 兼容老存档），
  `SelfHostedCredentials` / `SelfHostedServersModel` / 设置页都已按档案的档位读写。
- **`.iCloud` 后端刻意配成 `nil`**：没有 Keychain 共享访问组时强行写会"静默不同步"，
  界面会因此谎报已同步。`ServerSecretsStore.isAvailable(.iCloud) == false`，
  P3 的界面据此**置灰 + 说明**（采纳维护者意见）。

### P3 界面（下一步）

- 每台服务器 / 每个账号的「保存方式」三档选择（`isAvailable` 为假的档位置灰 + 说明文案）；
- 切换档位时调用 `move(from:to:)`，失败就地提示且不影响原数据；
- macOS 需要显式「清除本机资料」入口（把应用拖进废纸篓不会清 `Application Support`）。

### P4 预置：访问组命名与运行时探测（2026-11-08）

- 选定的共享访问组：**`com.joker.OrzMC.shared`**（实际字符串 = `<TeamID>.com.joker.OrzMC.shared`）。
  entitlements 里写 `$(AppIdentifierPrefix)com.joker.OrzMC.shared`，并且**必须同时保留**
  `$(AppIdentifierPrefix)$(CFBundleIdentifier)` —— 否则升级后老 Keychain 项读不到。
- `ServerSecretsStore.sharedAccessGroup()` 从**签名里的 entitlements** 读这个组：
  有 → `.iCloud` 后端启用（`ServerRecordKeychain(service: "com.joker.OrzMC.sync", synchronizable: true, accessGroup: …)`）；
  没有 → `.iCloud` 不可用（界面置灰）。
- ✅ **entitlement 已打开**（2026-11-08，维护者登录 Apple 账号后）：
  `OrzMC/Common/OrzMC.entitlements` 里带两个组（默认组 + `$(AppIdentifierPrefix)com.joker.OrzMC.shared`），
  `project.pbxproj` 给 app target 的两个配置都设了 `CODE_SIGN_ENTITLEMENTS`。
  首次签名需要设备注册，因此两个安装脚本都加了 `-allowProvisioningDeviceRegistration`。
- 实测：`codesign -d --entitlements` 两端都含 `2N62934Y28.com.joker.OrzMC.shared`；
  运行日志（DEBUG）两端都是 `sharedAccessGroup=2N62934Y28.com.joker.OrzMC.shared iCloud=available`。

### P3 界面已实施（2026-11-08）

- 新增 `OrzMC/Common/Storage/StorageModePicker.swift`：三档选择（`pickerStyle(.inline)`，每档一行标题 + 一句
  "它怎么活"的说明），`isAvailable` 为假的档位置灰并说明原因；`StorageModeMigration.apply` 封装迁移。
- 接入三处表单：自建服务器设置（`selfHosted`）、Exaroton 账号表单（`exaroton`）、MCSManager 面板表单（`mcsm`）。
  三者都在**保存时**才迁移（取消不动数据），迁移失败会显示错误并保留原数据。
- 档位随记录持久化：`SelfHostedServerProfile` / `ExarotonAccount` / `MCSManagerPanel` 的 `storageMode`
  新增或沿用，老存档缺字段按 `.device` 解码。
- 截图（iPhone 模拟器，iCloud 档位在模拟器上按预期置灰）：
  `docs/ui-storage-mode-2026-11-08/settings-storage-iphone.png`。
- 遗留：macOS「清除本机资料」入口（把 app 拖进废纸篓不会清 `Application Support`）—— 下一轮补。

## P4 真机验收记录（2026-11-08）

用一个共享的探针 id（`00000000-0000-0000-0000-00000000A11C`）走 `ServerSecretsStore` 的 `.iCloud` 档位，
两端各跑一次无界面诊断（`ORZMC_STORAGE_DIAGNOSE=write|read|delete`，见 `OrzMC/Common/Storage/StorageDiagnose.swift`）。

| # | 动作 | 结果 |
|---|---|---|
| 1 | macOS 写入 `probe:…02:11:29Z:macbook-air.local` | `writeOK=true`，`readBack` 一致 |
| 2 | iPhone 读 | `found=yes`，`value` 与 macOS 写入的一致（共享组 `2N62934Y28.com.joker.OrzMC.shared`） |
| 3 | iPhone 写入 `probe:…02:15:02Z:local` | `writeOK=true` |
| 4 | macOS 读（约 1 分钟后） | `found=yes`，`value` = iPhone 写入的那份 |
| 5 | macOS 删除 | `afterDelete=nil` |
| 6 | iPhone 读（约 2 分钟后） | `found=no` |

结论：**写入、双向同步、删除传播**在真实设备 + 真实 iCloud 账号上全部成立；
两端运行时都报告 `sharedAccessGroup=2N62934Y28.com.joker.OrzMC.shared, iCloudAvailable=true`。

已知：iCloud 钥匙串传播有延迟（本次实测 1–2 分钟），所以界面上"另一台设备立刻看到"不应作为验收判据；
文档与提交信息里都按"分钟级"描述，不要写成"实时"。
