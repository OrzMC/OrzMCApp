# 工作流与发布指南

## 工作流列表
- Release App：复用 `scripts/release-macos.sh` 构建、Developer ID 签名、公证、生成 appcast、创建/更新 GitHub Release、上传 ZIP/DMG，并提交 `products/appcast.xml`
- Publish Docs：使用 docc 生成静态文档并发布到 gh-pages（根路径重定向到 /documentation/orzmc/）
- Release iOS：当前仓库未保留对应 workflow 文件；如需恢复，可复用 iOS 签名 Secrets 与 App Store Connect API 配置

## 必备 Secrets
- macOS 发布
  - DEVELOPER_ID_CERT_P12：Developer ID Application（Base64 p12）
  - DEVELOPER_ID_CERT_PASSWORD：证书密码
  - TEAM_ID：Apple 团队 ID
  - APPSTORE_PRIVATE_KEY：App Store Connect API 私钥（Base64 .p8）
  - APPSTORE_KEY_ID：API Key ID
  - APPSTORE_ISSUER_ID：Issuer ID
  - SPARKLE_ED_PRIVATE_KEY：Sparkle EdDSA 私钥（Base64 文件内容，用于 appcast 签名）
  - GITHUB_TOKEN：创建 Release 与上传资源（默认自动注入即可）
- 文档发布
  - GITHUB_TOKEN
- iOS 发布（当前没有启用 workflow）
  - IOS_DIST_CERT_P12、IOS_DIST_CERT_PASSWORD：Apple Distribution 证书（Base64 p12）及密码
  - IOS_PROVISIONING_PROFILE（可选）：描述文件（Base64 .mobileprovision）
  - TEAM_ID：Apple 团队 ID（共用）
  - APPSTORE_PRIVATE_KEY、APPSTORE_KEY_ID、APPSTORE_ISSUER_ID：用于 TestFlight 上传

## 仓库变量
- NOTARY_TIMEOUT_DURATION：macOS 公证等待超时（脚本默认 30m，可在仓库变量中覆盖）
- IOS_BUNDLE_ID：恢复 iOS workflow 后用于与构建产物内 CFBundleIdentifier 匹配校验
- UPLOAD_TESTFLIGHT：恢复 iOS workflow 后，设为 "true" 时在 iOS 导出后上传 TestFlight

## 使用说明
- Release App
  - 在 Actions 运行 "Release App"
  - 要求 Secrets 已配置；workflow 会调用 `scripts/release-macos.sh`
  - 脚本会生成 Sparkle ZIP、签名 DMG、appcast.xml，并创建/复用同版本 tag 的 Release
  - CI 固定使用 `macos-26` 和 Xcode 16.4，会先生成未签名 archive，再在 export 后用 Developer ID + 强化运行时重新签名，复用当前用户系统的严格验签环境
  - 发布脚本会校验 `Info.plist entries=` 与 Developer ID 证书链嵌入情况；发布后仍需下载公开 ZIP/DMG 到本机复验
  - workflow 最后会提交 `products/appcast.xml`，保持现有 Sparkle 更新源地址可用
- Publish Docs
  - 运行 "Publish Docs"，生成 docs 并发布到 gh-pages
  - 访问根路径会自动重定向到 /documentation/orzmc/
- Release iOS
  - 当前 `.github/workflows` 下没有 Release iOS 文件；需要时先恢复 workflow，再接入上述 iOS Secrets

## Sparkle EdDSA 私钥生成
- 构建后找到 generate_keys 工具路径：DerivedData/SourcePackages/artifacts/sparkle/Sparkle/bin/generate_keys
- 生成私钥与公钥：

```bash
# 输出公钥（XML）
/path/to/generate_keys
# 导出私钥到文件
/path/to/generate_keys -x key
# 将私钥导入钥匙串（本地测试可选）
/path/to/generate_keys -f key
# 将私钥文件转 Base64 配置到 SPARKLE_ED_PRIVATE_KEY
base64 -i key | pbcopy
```

- 工作流使用 --ed-key-file 直接从私钥文件签名，不依赖钥匙串；确保 Info.plist 中 SUPublicEDKey 与私钥匹配

## 常见问题与诊断
- 公证 Invalid / Hardened Runtime 未启用
  - 发布脚本在 archive/export 阶段直接使用 Developer ID 签名，并开启强化运行时
  - 失败时优先在 Actions 日志里查看 `xcrun notarytool submit` 输出
- Release 创建失败或资产已存在
  - 脚本使用 `gh release view/create/upload --clobber`，会复用已有 Release 并覆盖同名资产
- generate_appcast not found
  - 工作流传入 `DERIVED_DATA_PATH=DerivedData`；脚本会优先搜索 `SPARKLE_BIN_DIR`，再搜索 Xcode DerivedData
- generate_appcast 缺私钥
  - Actions 使用 `SPARKLE_ED_PRIVATE_KEY` Base64 解码为临时文件；本地可使用 `SPARKLE_ED_KEY_FILE`

## 文档访问
- docc 默认文档首页位于 /documentation/orzmc/
- 项目站点根路径（/<repo>/）已生成 index.html 重定向到文档首页
