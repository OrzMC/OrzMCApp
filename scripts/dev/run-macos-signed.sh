#!/usr/bin/env bash
# 以**开发签名**构建并启动 macOS app（本地调试用）。
#
# 为什么需要它：`swift-check.sh app` / `check.sh` 用 `CODE_SIGNING_ALLOWED=NO` 构建（CI 也用这套，
# 快且不需要证书）。但**钥匙串条目是按代码签名做 ACL 的**：未签名/每次 cdhash 都变的构建拿不到
# 之前保存的 Token，表现为「远程托管列表空着」「设置里的 RCON 密码读不到」，还可能弹
# 钥匙串授权框（SecurityAgent）。所以凡是**要验 Keychain / 通知 / 权限相关功能**，用这个脚本。
#
# 首次运行会弹一次「OrzMC 想使用钥匙串中的机密信息」→ 点「始终允许」，之后同一个开发证书签名
# 的构建就不会再问。
#
# 用法（在 Terminal.app 里跑；ssh/agent 会话拿不到 GUI 钥匙串）：
#   ./scripts/dev/run-macos-signed.sh              # 构建 + 启动
#   ./scripts/dev/run-macos-signed.sh --build-only
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

TEAM_ID="${TEAM_ID:-2N62934Y28}"
DERIVED_DATA="${DERIVED_DATA_SIGNED:-$HOME/Library/Developer/Xcode/DerivedData/OrzMC-signed}"

if ! security show-keychain-info "$HOME/Library/Keychains/login.keychain-db" >/dev/null 2>&1; then
  echo "✗ 登录钥匙串不可用（请在 Terminal.app 里运行，或先 security unlock-keychain）" >&2
  exit 1
fi

xcodebuild build \
  -project OrzMC.xcodeproj \
  -scheme OrzMC \
  -configuration Debug \
  -destination 'platform=macOS' \
  -derivedDataPath "$DERIVED_DATA" \
  -allowProvisioningUpdates \
  -onlyUsePackageVersionsFromResolvedFile \
  -skipPackageUpdates \
  -skipPackagePluginValidation \
  -skipMacroValidation \
  DEVELOPMENT_TEAM="$TEAM_ID" \
  CODE_SIGN_STYLE=Automatic \
  2>&1 | tail -12

APP="$DERIVED_DATA/Build/Products/Debug/OrzMC.app"
[[ -d "$APP" ]] || { echo "✗ 没找到产物: $APP" >&2; exit 1; }
echo "产物: $APP"
codesign -dv --verbose=2 "$APP" 2>&1 | grep -E "Authority|TeamIdentifier" | head -3

[[ "${1:-}" == "--build-only" ]] && exit 0

pkill -f "$APP/Contents/MacOS/OrzMC" 2>/dev/null || true
sleep 1
echo "启动…（首次可能弹钥匙串授权，点「始终允许」）"
"$APP/Contents/MacOS/OrzMC" -ApplePersistenceIgnoreState YES >/dev/null 2>&1 &
sleep 3
echo "✓ 已启动"
