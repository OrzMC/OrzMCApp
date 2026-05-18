# macOS 发布流程

本项目的完整 macOS 启动器不通过 Mac App Store 分发，而是使用
Developer ID 签名、Apple 公证和 Sparkle 自动更新。

## 发布前准备

- 钥匙串中已安装 `Developer ID Application` 证书。
- 已创建 Apple `notarytool` 钥匙串配置。
- 已准备 Sparkle EdDSA 私钥，可以存放在钥匙串或文件中。
- 可选：GitHub CLI 已登录，用于上传 Release 资产。

首次创建 `notarytool` 配置：

```bash
xcrun notarytool store-credentials "orzmc-notary" \
  --apple-id "APPLE_ID_EMAIL" \
  --team-id "2N62934Y28" \
  --password "APP_SPECIFIC_PASSWORD"
```

## 一条命令发布

```bash
NOTARY_KEYCHAIN_PROFILE=orzmc-notary \
./scripts/release-macos.sh
```

脚本会从 `OrzMC/Configuration/Config.xcconfig` 读取
`MARKETING_VERSION` 和 `CURRENT_PROJECT_VERSION`，然后生成：

- `dist/macos/<version>-<build>/...zip`：用于 Sparkle 更新。
- `dist/macos/<version>-<build>/...dmg`：用于直接下载。
- `products/appcast.xml`：用于 Sparkle 更新源。

## 运行要求

当前公开 macOS 版本要求：

- macOS 14.0 Sonoma 或更新版本。
- Apple Silicon 或 Intel Mac。
- 首次获取版本清单、下载资源和 Sparkle 更新需要网络连接。
- 启动所选 Minecraft Java Edition 版本需要兼容的 JDK。应用会检测已安装 JDK 的主版本，并可在需要时下载匹配版本。

维护时需要保持以下位置一致：

- `OrzMC.xcodeproj/project.pbxproj` 中的 `MACOSX_DEPLOYMENT_TARGET = 14.0`
- `products/appcast.xml` 中的 `sparkle:minimumSystemVersion`
- `README.md` 中面向用户的安装要求说明

## 常用选项

```bash
DEVELOPER_ID_APPLICATION="Developer ID Application: Your Name (TEAMID)"
APPLE_TEAM_ID=TEAMID
NOTARY_KEYCHAIN_PROFILE=orzmc-notary
SPARKLE_ED_KEY_FILE=/path/to/sparkle_private_key
RELEASE_NOTES_FILE=/path/to/release-notes.md
PUBLISH_GITHUB=1
DERIVED_DATA_PATH=DerivedData
```

仅做本地打包验证、不进行公证：

```bash
SKIP_NOTARIZE=1 ./scripts/release-macos.sh
```

`SKIP_NOTARIZE=1` 只用于本地验证。公开下载的构建必须完成公证并装订公证票据。

## GitHub Release 上传

默认情况下，脚本只准备本地产物并更新 appcast。要上传 Release 资产：

```bash
PUBLISH_GITHUB=1 \
NOTARY_KEYCHAIN_PROFILE=orzmc-notary \
./scripts/release-macos.sh
```

默认仓库是 `OrzGeeker/OrzMCApp`，默认发布标签是 `MARKETING_VERSION`，与现有 appcast URL 保持一致。

## GitHub Actions

`.github/workflows/release-app.yml` 会调用与本地相同的发布脚本。工作流会导入 Developer ID 证书，复用 DerivedData 和 SwiftPM 缓存，并设置：

```bash
APPLE_TEAM_ID
APPSTORE_PRIVATE_KEY
APPSTORE_KEY_ID
APPSTORE_ISSUER_ID
SPARKLE_ED_PRIVATE_KEY
GH_TOKEN
DERIVED_DATA_PATH=DerivedData
RESIGN_EXPORTED_APP=1
PUBLISH_GITHUB=1
```

CI 公证使用的 `APPSTORE_PRIVATE_KEY` 和 `SPARKLE_ED_PRIVATE_KEY` 都是 Base64 编码后的文件内容。本地发布可以继续使用 `NOTARY_KEYCHAIN_PROFILE` 和 `SPARKLE_ED_KEY_FILE`。

脚本上传 Release 资产后，工作流会把 `products/appcast.xml` 提交回仓库，保持现有 Sparkle 更新源地址可用。

Actions 先使用 Xcode 的 Developer ID archive/export 路径完成导出，然后默认做一次脚本侧二次签名。二次签名会先签内部 dylib、framework、XPC 和子 app，最后对最外层 `.app` 做一次不带 `--deep` 的 bundle 签名，避免导出产物保留无效的空 entitlements blob 或未被当前系统接受的嵌套框架签名。本地排障时可设置 `RESIGN_EXPORTED_APP=0` 临时跳过二次签名。

Release workflow 固定使用原生 Apple Silicon `macos-26` runner，并显式选择 `/Applications/Xcode_26.4.1.app`，让 CI 的签名工具链与当前本机复验环境保持一致。缓存 key 包含 `runner.arch`，避免 Intel 与 Apple Silicon 的 DerivedData、SPM artifact 混用。GitHub 的 `macos-15`、`macos-26-intel` 或较旧默认 Xcode 可能放过会被 macOS 26.4.1 判定为无效的 universal arm64 签名结果。Intel 兼容性不依赖 runner 架构，而必须在发布验证中确认产物本身保持 `x86_64 arm64` universal binary。

## 更新源托管

应用当前读取的 Sparkle 更新源：

```text
https://raw.githubusercontent.com/OrzGeeker/OrzMCApp/main/products/appcast.xml
```

这个地址可用，但 GitHub Pages 或 CDN 更适合作为发布基础设施。如果后续迁移更新源 URL，需要更新 `OrzMC/Common/Info.plist` 中的 `SUFeedURL`，并在大多数用户完成升级前保持旧更新源可访问。

## 发布验证

发布脚本会执行：

```bash
codesign --verify --deep --strict --all-architectures
xcrun stapler validate
hdiutil verify
spctl --assess --type execute
```

脚本会校验导出的 app、解包后的 Sparkle ZIP，以及挂载后的 DMG 内部 app，并要求 `codesign -dv --verbose=4` 输出包含 `Info.plist entries=`，拒绝 `codesign -d --entitlements :-` 报告的 `invalid entitlements blob`，同时要求 Developer ID 签名中能提取到嵌入的证书链。公开构建还需要下载 ZIP/DMG 到本机复验；如果没有通过这些检查，不要发布。

主应用当前没有启用 App Sandbox，也没有需要声明的签名权限，因此 Xcode target 不应配置空的 entitlements 文件。空 entitlements blob 在较新的 macOS 26.4.1 验签环境中会被报告为无效签名。
