# macOS 发版签名：Developer ID 描述文件（0.1.7 起必需）

> **状态**：生效中｜**最后更新**：2026-11-09
> **适用范围**：`scripts/release-macos.sh` / `.github/workflows/release-app.yml`

## 为什么突然需要

0.1.6 及以前的 `OrzMC/Common/OrzMC.entitlements` 是空的，Developer ID 签名不需要描述文件。

0.1.7 起（存储 P4，PR #151）entitlements 里加了**钥匙串共享**：

```xml
<key>keychain-access-groups</key>
<array>
    <string>$(AppIdentifierPrefix)$(CFBundleIdentifier)</string>
    <string>$(AppIdentifierPrefix)com.joker.OrzMC.shared</string>
</array>
```

`keychain-access-groups` 属于 Apple 的**受限权限**：用 Developer ID 分发时，签名必须带一个包含该权限的
**Developer ID 描述文件**。没有它，`xcodebuild archive` 直接失败：

```
error: "OrzMC" requires a provisioning profile. Select a provisioning profile in the Signing & Capabilities editor.
```

> 本地 `install-dev-app.sh` 用 Apple Development + 自动签名，Xcode 会自动生成 *Mac Team* 描述文件
> （`~/Library/Developer/Xcode/UserData/Provisioning Profiles/*.provisionprofile`），
> 所以**开发和真机验收不受影响**；只有 Developer ID 发版这条路需要额外准备。

## 一次性准备（维护者操作，需要开发者后台权限）

1. 确认 App ID `com.joker.OrzMC` 已开启 **Keychain Sharing**，并包含组
   `2N62934Y28.com.joker.OrzMC.shared`（与 iOS 共用这个组）。
2. Apple Developer → **Certificates, Identifiers & Profiles → Profiles → +**
   - 类型选 **Distribution → Developer ID**
   - App ID 选 `com.joker.OrzMC`
   - 证书选 **Developer ID Application: Zhizhou Wang (2N62934Y28)**（仓库 secret 里那张）
   - 下载 `OrzMC_DeveloperID.provisionprofile`
3. 自检（本地）：

   ```bash
   security cms -D -i OrzMC_DeveloperID.provisionprofile | plutil -extract Name raw -
   security cms -D -i OrzMC_DeveloperID.provisionprofile | plutil -extract Entitlements json -
   # 期望能看到 keychain-access-groups，且包含 2N62934Y28.com.joker.OrzMC.shared
   ```
4. 存进仓库 secret（base64 文本，**不要**把文件提交进 Git）：

   ```bash
   gh secret set MACOS_PROFILE --repo OrzMC/OrzMCApp < <(base64 -i OrzMC_DeveloperID.provisionprofile)
   ```

## 发版脚本怎么用它

- `release-macos.sh` 在 `ARCHIVE_CODE_SIGNING_MODE=manual`（发版默认）时：
  - 解码 `MACOS_PROFILE` → 写入
    `~/Library/Developer/Xcode/UserData/Provisioning Profiles/<UUID>.provisionprofile`
    与 `~/Library/MobileDevice/Provisioning Profiles/`（两个路径都放，兼容不同工具链）；
  - 从描述文件读 `Name`，传 `PROVISIONING_PROFILE_SPECIFIER`，并在 `ExportOptions.plist` 里写
    `provisioningProfiles`（bundle id → profile name）。
- 导出后会先 `codesign -d --entitlements` 取**展开后**的权限（`$(AppIdentifierPrefix)` → `2N62934Y28.`），
  再用它重签；直接用仓库里那份原始 plist 重签会把占位符按字面写进签名。
- `MACOS_PROFILE` 缺失时脚本会**直接失败并打印上面的创建步骤**，不会产出一个"签名看起来对、权限不对"的包。

## 有效期与轮换

- Developer ID 描述文件随证书过期（本团队证书到期前需更新）；到期前后 Apple 会给维护者发邮件。
- 轮换只需重新生成描述文件 → `gh secret set MACOS_PROFILE` 覆盖，然后重跑 `release-app.yml`。
- iOS 的 TestFlight/Ad Hoc 走另一套：`IOS_PROFILE`（见 `scripts/release-ios.sh` 与 `docs/ios-release.md`），
  与本文件无关。

## 验证顺序

```bash
gh workflow run release-app.yml --ref <分支> -f dry_run=true   # 签名/公证/打包/断言，不发布
gh workflow run release-app.yml --ref main                     # 正式发布 + 提交 appcast
```

dry-run 输出里应能看到 `macOS 描述文件：…（UUID）` 与 `Re-sign uses expanded entitlements: …`。
