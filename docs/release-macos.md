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
ARCHIVE_CODE_SIGNING_MODE=disabled
RESIGN_EXPORTED_APP=1
PUBLISH_GITHUB=1
```

CI 公证使用的 `APPSTORE_PRIVATE_KEY` 和 `SPARKLE_ED_PRIVATE_KEY` 都是 Base64 编码后的文件内容。本地发布可以继续使用 `NOTARY_KEYCHAIN_PROFILE` 和 `SPARKLE_ED_KEY_FILE`。

脚本上传 Release 资产后，工作流会把 `products/appcast.xml` 提交回仓库，保持现有 Sparkle 更新源地址可用。

Actions 会先生成未签名 archive，再对导出的 app 使用 Developer ID 和强化运行时重新签名。最终 app 复签会使用 Developer ID 证书 SHA-1 identity，签名参数按 `codesign` 推荐顺序传入，并带 `--deep`，确保主 app、嵌套 Sparkle 组件和资源封口在同一次最终签名中一致。这条路径复用了历史上稳定的 CI 流程，同时保留本地默认的直接 Developer ID archive 签名方式。

Release workflow 固定使用 `macos-15-intel` runner 和 Xcode 16.4。GitHub 的 `macos-15` 标签当前会分配到 arm64 镜像；如果需要 Intel 环境，应使用 `macos-15-intel`。不要直接切换到 arm64 runner 或 Xcode beta：历史构建在这些环境中出现过 `Info.plist=not bound` 或签名证书链未嵌入的结果，CI 端验收可能通过，但下载到本机后会被严格 `codesign` 校验判定为无效。

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

脚本会校验导出的 app、解包后的 Sparkle ZIP，以及挂载后的 DMG 内部 app，并要求 `codesign -dv --verbose=4` 输出包含 `Info.plist entries=`，同时要求 Developer ID 签名中能提取到嵌入的证书链。公开构建还需要下载 ZIP/DMG 到本机复验；如果没有通过这些检查，不要发布。
