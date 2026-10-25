# iOS 归档、TestFlight 与真机装包

> **状态**：生效中（2026-10-25）｜**脚本**：`scripts/release-ios.sh`、`scripts/dev/install-ios-device.sh`
> ｜**CI**：`.github/workflows/release-ios.yml`（`Release iOS`）
>
> macOS 的发版是另一套：`scripts/release-macos.sh`（Developer ID + notarize + Sparkle），
> 见 `release-app.yml`。**iOS 不 notarize**，走 App Store Connect 的签名与 TestFlight。

## 三条路径

| 想做什么 | 命令 |
|---|---|
| 归档 + 导出可安装的 ipa（开发签名） | `./scripts/release-ios.sh` |
| 归档 + 导出 App Store 包（TestFlight 用） | `./scripts/release-ios.sh --export app-store-connect` |
| 归档 + 导出 + 上传 TestFlight | `APPSTORE_*` 就绪后 `./scripts/release-ios.sh --export app-store-connect --upload` |
| 归档 + 直接装到已连接的 iPhone | `./scripts/release-ios.sh --install` |
| 只装包（Debug / Release / 现成 ipa） | `./scripts/dev/install-ios-device.sh [--release] [--ipa <path>]` |

产物都落在 `dist/ios/`（`DIST_DIR` 可覆盖）：

```
dist/ios/
  OrzMC_0.1.4_56_20261025_120000.xcarchive/          # 归档（含 dSYM）
  OrzMC_0.1.4_56_20261025_120000_debugging/OrzMC.ipa # 导出的 ipa
  ExportOptions-debugging.plist                      # 导出配置（可复查）
```

## 签名：本地钥匙串 vs 云签名

| 场景 | 怎么签 | 前置 |
|---|---|---|
| 本机（维护者 Mac） | `CODE_SIGN_STYLE=Automatic` + `-allowProvisioningUpdates` | 钥匙串里有 **Apple Development**（真机安装）/**Apple Distribution**（TestFlight），Xcode 已登录 Apple ID |
| CI / 无本地证书 | **云签名**：`-authenticationKeyPath/-authenticationKeyID/-authenticationKeyIssuerID` | `APPSTORE_PRIVATE_KEY`（base64 的 `.p8`）、`APPSTORE_KEY_ID`、`APPSTORE_ISSUER_ID`，key 需要 Admin/App Manager 权限 |

`release-ios.sh` 检测到这三个变量就自动走云签名；`.p8` 只落在临时目录（`chmod 600`），退出即删。

## 导出方式（`--export`）

| 值 | 适用 | 说明 |
|---|---|---|
| `debugging`（默认） | 装自己和团队注册过的设备 | 老的 `development` 名字会自动映射 |
| `release-testing` | Ad hoc 分发 | 老的 `ad-hoc` |
| `app-store-connect` | App Store / TestFlight | 老的 `app-store` |
| `developer-id` | iOS 基本不用 | — |

导出的 ipa 会**当场校验**：`CFBundleIdentifier`（iOS 是 `com.joker.OrzMC.iOS`）、
`CFBundleShortVersionString`/`CFBundleVersion` 是否与 `Config.xcconfig` 一致、签名身份、
`CFBundleIcons` 是否有图标。版本不一致会打 WARNING（说明归档是旧的）。

## 上传 TestFlight

```bash
export APPSTORE_PRIVATE_KEY="$(base64 -i ~/.appstoreconnect/private_keys/AuthKey_XXX.p8)"
export APPSTORE_KEY_ID=XXX
export APPSTORE_ISSUER_ID=xxxx-xxxx-xxxx
./scripts/release-ios.sh --export app-store-connect --upload
```

- 上传用 `xcrun altool --upload-app -t ios --api-key … --api-issuer …`，`.p8` 通过
  `API_PRIVATE_KEYS_DIR` 指向临时目录；`--wait`（或 `WAIT_FOR_PROCESSING=1`）等处理完成。
- **同一版本号不能重复上传**：再传要先提升 `CURRENT_PROJECT_VERSION`（脚本里
  `manageAppVersionAndBuildNumber=false`，避免 Xcode 偷偷改 build 号）。
- 上传成功 ≠ 出现在 TestFlight：App Store Connect 还要处理几分钟；首次还要补合规信息。

## CI：`Release iOS`

`.github/workflows/release-ios.yml`，参数：

| 输入 | 默认 | 说明 |
|---|---|---|
| `export` | `app-store-connect` | `debugging` / `release-testing` / `app-store-connect` |
| `upload` | `false` | **`true` 会真的产生 TestFlight 构建并通知测试员** |

```bash
gh workflow run release-ios.yml --ref main \
  -f export=app-store-connect -f upload=false      # 只归档导出，产物在 workflow artifacts
```

CI 里不导入任何 iOS 证书，全靠上面三个 API key 走云签名；Xcode 固定 **26.3**（与 macOS 发版一致）。
产物：`ios-release-artifacts`（ipa + ExportOptions.plist）。

## CI 现状（2026-10-25 实测）

| 组合 | 结果 | 说明 |
|---|---|---|
| `export=debugging, upload=false` | ✅ **可用** | 云签名拿到 `Apple Development: Created via API` + Team 描述文件，导出真 ipa |
| `export=app-store-connect, upload=false` | ❌ 被权限挡住 | `Cloud signing permission error` / `No signing certificate "iOS Distribution" found` / `No profiles for 'com.joker.OrzMC.iOS' were found` |

已验证的 CI 产物（`release-ios.yml` #40163544468 的 `ios-release-artifacts`）：

```
OrzMC_0.1.4_56_20261025_045514_debugging/OrzMC.ipa
  CFBundleIdentifier = com.joker.OrzMC.iOS
  CFBundleShortVersionString/CFBundleVersion = 0.1.4 / 56
  签名 = Apple Development: Created via API (9X6A7DZKZF)
  描述文件有效期 = 2027-10-25
  包内 AppIcon60x60@2x.png / AppIcon76x76@2x~ipad.png + CFBundleIcons 齐全
```

**分发（TestFlight）为什么不行**：App Store Connect API key 云签名建不了 **Apple Distribution**
证书与 App Store 描述文件 —— 这是密钥角色（权限）问题，不是脚本问题。三条出路（按推荐顺序）：

1. **本机导出 + 上传**（今天就能用）：维护者 Mac 的钥匙串里已经有
   `Apple Distribution: Zhizhou Wang (2N62934Y28)`，在 Terminal.app 里跑
   `./scripts/release-ios.sh --export app-store-connect --upload`。
2. **把 API key 的角色提到 Admin**（App Store Connect → 用户与访问 → 集成），云签名才能自动建证书。
3. **在 CI 里塞分发证书 + 描述文件**（manual signing）：需要在 workflow 里额外导入
   `.p12` 与 `.mobileprovision` 并把 ExportOptions 改成 `signingStyle=manual` + `provisioningProfiles`；
   脚本目前只实现了 automatic，要用这条路得先补这个能力。

> 换句话说：**归档/导出/装真机今天就能用**（本机全通、CI 的开发签名也通）；
> **CI 直传 TestFlight** 还差权限或证书，按上面三条任选其一。

## 真机装开发签名包

```bash
./scripts/dev/install-ios-device.sh              # Debug 构建 + 安装 + 启动
./scripts/dev/install-ios-device.sh --release    # Release 构建（验证发布配置）
./scripts/dev/install-ios-device.sh --ipa dist/ios/OrzMC_0.1.4_56_*_debugging/OrzMC.ipa
./scripts/dev/install-ios-device.sh --device 00008110-0001712226A0401E --no-launch
```

⚠️ **必须在 Terminal.app / iTerm 里跑**：`codesign` 要访问登录钥匙串里的私钥，
锁着的钥匙串会报 `errSecInternalComponent`（后台/agent 会话、ssh 都算"没有图形会话"）。
钥匙串锁了就先 `security unlock-keychain ~/Library/Keychains/login.keychain-db`。

其它前置与常见失败：

| 现象 | 原因 / 处理 |
|---|---|
| `errSecInternalComponent` | 钥匙串锁了 / 不在图形会话里 → Terminal.app + 解锁钥匙串 |
| 安装失败、设备没在描述文件里 | `-allowProvisioningUpdates` 会自动注册，需要 Xcode 登录 Apple ID |
| 装上了但打不开 | iPhone「设置 → 通用 → VPN与设备管理」信任开发者证书 |
| 找不到设备 | 数据线连上、手机上「信任此电脑」；`xcrun devicectl list devices` 确认 |

## 已知限制

- **dSYM 只在 `.xcarchive` 里**：要归档崩溃符号，保留 `dist/ios/*.xcarchive`（CI 的 artifact 只带 ipa）。
- iOS 的 bundle id 与 macOS 不同（`com.joker.OrzMC.iOS` vs `com.joker.OrzMC`），两端的 App Store /
  签名配置互不影响。
- 版本号唯一来源是 `OrzMC/Configuration/Config.xcconfig`；发版前改版本 + 写
  `docs/release-notes/<版本>.md`（iOS 与 macOS 共用这一份说明）。
