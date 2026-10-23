#!/usr/bin/env bash
# 把 **debug 包**装到真机 iPhone 上（开发签名，非 TestFlight/App Store）。
#
# ⚠️ 必须在**有图形会话的终端**里跑（Terminal.app / iTerm），不要通过 ssh / agent 会话跑：
#    codesign 需要访问登录钥匙串里的私钥，锁着的钥匙串会报 `errSecInternalComponent`。
#    如果钥匙串是锁的：`security unlock-keychain ~/Library/Keychains/login.keychain-db`
#
# 用法：
#   ./scripts/dev/install-ios-device.sh                 # 自动找第一台物理设备，装完并启动
#   ./scripts/dev/install-ios-device.sh --device iPhoneSE3
#   ./scripts/dev/install-ios-device.sh --no-launch     # 只安装
#
# 首次在设备上装开发包时，还要在 iPhone 上「设置 → 通用 → VPN与设备管理」信任你的开发者证书。
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

TEAM_ID="${TEAM_ID:-2N62934Y28}"
DEVICE=""
LAUNCH=1
DERIVED_DATA="${DERIVED_DATA:-$HOME/Library/Developer/Xcode/DerivedData/OrzMC-device}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --device) DEVICE="${2:?}"; shift 2 ;;
    --no-launch) LAUNCH=0; shift ;;
    -h|--help) sed -n '2,18p' "${BASH_SOURCE[0]}"; exit 0 ;;
    *) echo "未知参数: $1" >&2; exit 2 ;;
  esac
done

step() { printf '\n\033[1m▶ %s\033[0m\n' "$1"; }

step "检查环境"
command -v xcodebuild >/dev/null || { echo "缺少 xcodebuild" >&2; exit 1; }
command -v xcrun >/dev/null || { echo "缺少 xcrun" >&2; exit 1; }

if ! security show-keychain-info "$HOME/Library/Keychains/login.keychain-db" >/dev/null 2>&1; then
  cat >&2 <<'MSG'
✗ 登录钥匙串当前不可用（或本会话没有图形权限），codesign 会失败（errSecInternalComponent）。
  请在 Terminal.app 里运行本脚本；或先执行：
      security unlock-keychain ~/Library/Keychains/login.keychain-db
MSG
  exit 1
fi

# 找物理设备（devicectl 的 JSON 里 reality = physical / available）
if [[ -z "$DEVICE" ]]; then
  DEVICE="$(xcrun devicectl list devices --json-output /tmp/orzmc-devices.json >/dev/null 2>&1 && \
    python3 - <<'PY'
import json
data = json.load(open("/tmp/orzmc-devices.json"))
for device in data.get("result", {}).get("devices", []):
    conn = device.get("connectionProperties", {})
    hw = device.get("hardwareProperties", {})
    props = device.get("deviceProperties", {})
    udid = hw.get("udid")
    # 模拟器 / 本机 = transportType "sameMachine"；真机是 "localNetwork" / "usb" / "wired"。
    if udid and conn.get("transportType") != "sameMachine" and props.get("reality") != "simulated":
        print(udid)
        break
PY
  )"
fi

[[ -n "$DEVICE" ]] || { echo "✗ 没找到已连接的 iPhone；先用数据线连上并在手机上「信任此电脑」" >&2; exit 1; }
echo "设备: $DEVICE"
echo "团队: $TEAM_ID"

step "构建（Debug，开发签名）"
xcodebuild build \
  -project OrzMC.xcodeproj \
  -scheme OrzMC \
  -configuration Debug \
  -destination "platform=iOS,id=$DEVICE" \
  -derivedDataPath "$DERIVED_DATA" \
  -allowProvisioningUpdates \
  -onlyUsePackageVersionsFromResolvedFile \
  -skipPackageUpdates \
  -skipPackagePluginValidation \
  -skipMacroValidation \
  DEVELOPMENT_TEAM="$TEAM_ID" \
  CODE_SIGN_STYLE=Automatic \
  2>&1 | tail -25

APP_PATH="$DERIVED_DATA/Build/Products/Debug-iphoneos/OrzMC.app"
[[ -d "$APP_PATH" ]] || { echo "✗ 没找到构建产物: $APP_PATH" >&2; exit 1; }
BUNDLE_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP_PATH/Info.plist")"
echo "产物: $APP_PATH"
echo "Bundle ID: $BUNDLE_ID"

step "安装到设备"
if ! xcrun devicectl device install app --device "$DEVICE" "$APP_PATH" 2>&1 | tail -5; then
  cat >&2 <<'MSG'
✗ 安装失败。常见原因：
  * iPhone 锁屏 → 解锁后重试；
  * 首次安装需要信任开发者：设置 → 通用 → VPN与设备管理 → 开发者 App；
  * 设备未注册到团队描述文件（-allowProvisioningUpdates 会自动注册，可能需要 Apple ID 登录）。
MSG
  exit 1
fi

if [[ "$LAUNCH" == "1" ]]; then
  step "启动"
  xcrun devicectl device process launch --device "$DEVICE" "$BUNDLE_ID" 2>&1 | tail -3 || true
fi

printf '\n\033[32m完成\033[0m（debug 包已装到 %s）\n' "$DEVICE"
