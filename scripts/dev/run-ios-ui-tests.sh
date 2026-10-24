#!/usr/bin/env bash
# iOS **UI 自动化验收**：起本机假服务端 → 构建 → 装 App → 跑 XCUITest（真点击 + 断言 + 截图）。
#
# 为什么需要：`devicectl` 没有触摸注入，人（和 AI）都不能"点一下看看"。XCUITest 能真正驱动
# 点击/滑动，既能跑模拟器也能跑真机，把"手工点 + 截图 + 肉眼判断"变成可重复执行的断言。
#
# 用法：
#   ./scripts/dev/run-ios-ui-tests.sh                     # 默认 iPhone SE3 尺寸模拟器
#   ./scripts/dev/run-ios-ui-tests.sh --device <UDID>      # 指定真机（需在 Terminal.app 里跑，开发签名）
#   ./scripts/dev/run-ios-ui-tests.sh --simulator "iPhone 17 Pro"
#
# 测试用到的 DEBUG 钩子（发布构建里不存在）：ORZMC_DEMO_SEED_PROFILE / ORZMC_DEMO_RCON_PASSWORD /
# ORZMC_DEMO_TAB / ORZMC_DEMO_FAKE_SERVER（见 OrzMCUITests/RemotePanelsUITests.swift）。
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

DERIVED_DATA="${DERIVED_DATA_UI:-$HOME/Library/Developer/Xcode/DerivedData/OrzMC-local-ios}"
DEVICE=""
SIM_NAME="${SIM_NAME:-OrzMC-UI}"
SLP_PORT=25566
RCON_PORT=25575
PIDS=()

cleanup() {
  for pid in "${PIDS[@]:-}"; do [[ -n "$pid" ]] && kill "$pid" 2>/dev/null || true; done
}
trap cleanup EXIT

while [[ $# -gt 0 ]]; do
  case "$1" in
    --device) DEVICE="${2:?}"; shift 2 ;;
    --simulator) SIM_NAME="${2:?}"; shift 2 ;;
    -h|--help) sed -n '2,20p' "${BASH_SOURCE[0]}"; exit 0 ;;
    *) echo "未知参数: $1" >&2; exit 2 ;;
  esac
done

step() { printf '\n\033[1m▶ %s\033[0m\n' "$1"; }

step "启动假 SLP / RCON 服务端"
python3 scripts/test-servers/slp_server.py "$SLP_PORT" >/dev/null 2>&1 & PIDS+=("$!")
python3 scripts/test-servers/rcon_server.py "$RCON_PORT" >/dev/null 2>&1 & PIDS+=("$!")
for port in "$SLP_PORT" "$RCON_PORT"; do
  for _ in $(seq 1 50); do nc -z 127.0.0.1 "$port" 2>/dev/null && break; sleep 0.1; done
  nc -z 127.0.0.1 "$port" 2>/dev/null || { echo "✗ 端口 ${port} 没起来" >&2; exit 1; }
done

if [[ -n "$DEVICE" ]]; then
  DESTINATION="platform=iOS,id=$DEVICE"
  step "目标：真机 $DEVICE（需要开发签名与已解锁的钥匙串）"
else
  UDID="$(xcrun simctl list devices available | grep -F "$SIM_NAME (" | head -1 | sed -E 's/.*\(([0-9A-F-]{36})\).*/\1/')"
  if [[ -z "$UDID" ]]; then
    echo "✗ 找不到模拟器「$SIM_NAME」，可先创建：xcrun simctl create \"$SIM_NAME\" \\" >&2
    echo "    com.apple.CoreSimulator.SimDeviceType.iPhone-SE-3rd-generation com.apple.CoreSimulator.SimRuntime.iOS-26-4" >&2
    exit 1
  fi
  xcrun simctl boot "$UDID" 2>/dev/null || true
  sleep 3
  # 必须先装一次 App：某些 Xcode 版本在"没装过 App"时跑 UI 测试会报
  # "bundle identifier for OrzMC couldn't be read"（实测）。
  DESTINATION="platform=iOS Simulator,id=$UDID"
  step "目标：模拟器 ${SIM_NAME}（${UDID}）"
fi

COMMON=(
  -project OrzMC.xcodeproj
  -scheme OrzMCUITests
  -destination "$DESTINATION"
  -derivedDataPath "$DERIVED_DATA"
  -onlyUsePackageVersionsFromResolvedFile
  -skipPackageUpdates
  -skipPackagePluginValidation
  -skipMacroValidation
)
[[ -n "$DEVICE" ]] || COMMON+=(CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY='')

step "构建（build-for-testing）"
xcodebuild build-for-testing "${COMMON[@]}" 2>&1 | tail -8

if [[ -z "$DEVICE" ]]; then
  step "预装 App（规避 Xcode 的 bundle identifier 读取 bug）"
  xcrun simctl uninstall "$UDID" com.joker.OrzMC.iOS 2>/dev/null || true
  xcrun simctl install "$UDID" "$DERIVED_DATA/Build/Products/Debug-iphonesimulator/OrzMC.app"
fi

step "执行 UI 测试"
xcodebuild test-without-building "${COMMON[@]}" 2>&1 | grep -E "Test Case|Test Suite|\*\* TEST" | tail -30
