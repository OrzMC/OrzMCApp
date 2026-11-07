# 服务器资料保存与同步方案

> 状态：**Phase 1 已落地**（存储核心 + 单测，2026-11-08）｜最后更新：2026-11-08
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
| **P2 接到现有三处** | 自建服务器（RCON 密码）、Exaroton（Token）、MCSManager（API Key）统一走 `ServerRecordStore`；每条记录记住自己的档位（非敏感元数据放 UserDefaults）；**默认仍是"保留在本机"**，升级不迁移、不删除 | 待做 |
| **P3 界面** | 每台服务器 / 每个账号的「保存方式」选择（三档 + 说明）、迁移中的进度与失败提示、显式"清除本机资料"入口（macOS 删应用不会清 `Application Support`） | 待做 |
| **P4 iCloud 真机验证** | 需要同一团队、匹配的 Keychain 访问组与 iCloud 钥匙串能力；用真实签名的 macOS + iOS、同一 Apple 账号验证写入/同步/删除/重装恢复 | 待做（依赖签名配置） |

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
