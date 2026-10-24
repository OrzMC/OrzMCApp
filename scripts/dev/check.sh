#!/usr/bin/env bash
# 应用仓库的**唯一本地门禁入口**（不需要父仓库）。
#
# 为什么要有它：以前每次改动都是"改一行 → push → 等 CI 3 分钟 → 看是不是编不过"。
# 这个脚本把 CI 会查的东西在本地先跑一遍，失败就地修。
#
# 用法：
#   scripts/dev/check.sh            # 默认：静态检查 + 包单测 + 应用测试 + macOS 构建（约 2~4 分钟）
#   scripts/dev/check.sh --fast     # 只跑静态检查（秒级；提交前/钩子用）
#   scripts/dev/check.sh --full     # 默认 + iOS 构建 + 真 socket 协议联调（约 6~10 分钟）
#   scripts/dev/check.sh --build    # 只构建 macOS（不跑测试）
#   scripts/dev/check.sh --ios      # 只构建 iOS
#   scripts/dev/check.sh --ui       # iOS UI 自动化验收（XCUITest，需本机起假服务端，约 1~2 分钟）
#
# 相当于 CI 的哪些 job：
#   split → 静态检查（平台分层 / pbxproj 登记 / 本地化）
#   protocol-live → --full 里的真 socket 联调
#   build(macos/ios) → --build / --ios
#   Unit tests → 默认档
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

DERIVED_DATA="${DERIVED_DATA:-$HOME/Library/Developer/Xcode/DerivedData/OrzMC-local}"
DERIVED_DATA_IOS="${DERIVED_DATA_IOS:-$DERIVED_DATA-ios}"
XCODEBUILD_FLAGS=(
  -project OrzMC.xcodeproj
  -scheme OrzMC
  -onlyUsePackageVersionsFromResolvedFile
  -skipPackageUpdates
  -skipPackagePluginValidation
  -skipMacroValidation
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY=''
)

step() { printf '\n\033[1m▶ %s\033[0m\n' "$1"; }
ok()   { printf '\033[32m✓ %s\033[0m\n' "$1"; }

static_checks() {
  step "静态检查"
  ./scripts/check-platform-split.sh
  python3 scripts/dev/check-pbxproj.py
  python3 scripts/dev/check-localization.py
  ok "静态检查通过"
}

swift_tests() {
  step "SwiftPM 单测（Sources/*）"
  swift test
  ok "包单测通过"
}

app_tests() {
  step "应用测试 target（OrzMCTests）"
  xcodebuild test "${XCODEBUILD_FLAGS[@]}" \
    -destination 'platform=macOS' \
    -derivedDataPath "$DERIVED_DATA" \
    -only-testing:OrzMCTests \
    2>&1 | tail -25
  ok "应用测试通过"
}

build_macos() {
  step "构建 macOS"
  xcodebuild build "${XCODEBUILD_FLAGS[@]}" \
    -destination 'platform=macOS' \
    -derivedDataPath "$DERIVED_DATA" 2>&1 | tail -15
  ok "macOS 构建通过"
}

build_ios() {
  step "构建 iOS（模拟器）"
  xcodebuild build "${XCODEBUILD_FLAGS[@]}" \
    -destination 'generic/platform=iOS Simulator' \
    -derivedDataPath "$DERIVED_DATA_IOS" 2>&1 | tail -15
  ok "iOS 构建通过"
}

live_protocol() {
  step "真 socket 协议联调（假 SLP / RCON 服务端）"
  ./scripts/test-servers/run-live-tests.sh 2>&1 | tail -20
  ok "协议联调通过"
}

MODE="${1:-default}"
case "$MODE" in
  --fast)  static_checks ;;
  --build) build_macos ;;
  --ios)   build_ios ;;
  --ui)    step "iOS UI 自动化验收"; ./scripts/dev/run-ios-ui-tests.sh; ok "UI 验收通过" ;;
  --full)  static_checks; swift_tests; app_tests; build_macos; build_ios; live_protocol ;;
  default) static_checks; swift_tests; app_tests; build_macos ;;
  *)
    echo "unknown mode: $MODE（--fast / --build / --ios / --full 或留空）" >&2
    exit 2
    ;;
esac

printf '\n\033[32m全部通过（mode=%s）\033[0m\n' "$MODE"
