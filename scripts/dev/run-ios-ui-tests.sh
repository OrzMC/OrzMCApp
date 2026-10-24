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

# ── 本地凭据（可选）──────────────────────────────────────────────
# 真实服务器 / 真实 exaroton 账号的用例需要凭据。凭据只从**未入库**的
# scripts/dev/uitest-secrets.env 读取（模板见同名 .example.env），
# 这里只做"有没有"，**从不打印值**。
SECRETS_FILE="${UI_TEST_SECRETS:-$ROOT/scripts/dev/uitest-secrets.env}"
if [[ -f "$SECRETS_FILE" ]]; then
  # shellcheck disable=SC1090
  set -a; source "$SECRETS_FILE"; set +a
  step "已加载本地凭据（${SECRETS_FILE#"$ROOT"/}，值不回显）"
else
  step "没有本地凭据文件：真实服务器 / 真实账号的用例会自动跳过"
fi

# 把凭据转成测试进程的环境变量：xcodebuild 会把 `TEST_RUNNER_` 前缀剥掉后传给 runner。
#
# ⚠️ 必须用**环境变量**（`export TEST_RUNNER_X=…`），不能写成 xcodebuild 的命令行参数
# （`xcodebuild … TEST_RUNNER_X=…`）：后者是"构建设置赋值"，不会进 runner 的进程环境，
# 症状就是凭据明明"已提供"，真机/真实账号用例照样 skip。
add_secret() { # add_secret <测试侧变量名> <值>
  # 注意：必须用 if 而不是 `[[ … ]] && …` —— 后者在值为空时返回 1，配合 set -e 会直接终止脚本。
  if [[ -n "${2:-}" ]]; then
    export "TEST_RUNNER_$1=$2"
  fi
}
add_secret ORZMC_UITEST_SELFHOSTED_HOST          "${ORZMC_UITEST_SELFHOSTED_HOST:-}"
add_secret ORZMC_UITEST_SELFHOSTED_PORT          "${ORZMC_UITEST_SELFHOSTED_PORT:-}"
add_secret ORZMC_UITEST_SELFHOSTED_RCON_PORT     "${ORZMC_UITEST_SELFHOSTED_RCON_PORT:-}"
add_secret ORZMC_UITEST_SELFHOSTED_RCON_PASSWORD "${ORZMC_UITEST_SELFHOSTED_RCON_PASSWORD:-}"
add_secret ORZMC_UITEST_SELFHOSTED_NAME          "${ORZMC_UITEST_SELFHOSTED_NAME:-}"
add_secret ORZMC_DEMO_TOKEN                      "${ORZMC_UITEST_EXAROTON_TOKEN:-}"
if [[ -n "${ORZMC_UITEST_EXAROTON_TOKEN:-}" ]]; then
  export TEST_RUNNER_ORZMC_UITEST_REAL_ACCOUNT=1
fi
# RCON 用例默认不跑（服务端配置错不该把日常迭代染红），需要时 UI_TEST_RCON=1。
if [[ "${UI_TEST_RCON:-0}" = "1" ]]; then
  export TEST_RUNNER_ORZMC_UITEST_RCON=1
fi
echo "  真实自建服务器：$([[ -n "${ORZMC_UITEST_SELFHOSTED_HOST:-}" ]] && echo 已提供 || echo 未提供)" \
     "· exaroton Token：$([[ -n "${ORZMC_UITEST_EXAROTON_TOKEN:-}" ]] && echo 已提供 || echo 未提供)"

step "启动假 SLP / RCON 服务端"
python3 scripts/test-servers/slp_server.py "$SLP_PORT" >/dev/null 2>&1 & PIDS+=("$!")
python3 scripts/test-servers/rcon_server.py "$RCON_PORT" >/dev/null 2>&1 & PIDS+=("$!")
for port in "$SLP_PORT" "$RCON_PORT"; do
  for _ in $(seq 1 50); do nc -z 127.0.0.1 "$port" 2>/dev/null && break; sleep 0.1; done
  nc -z 127.0.0.1 "$port" 2>/dev/null || { echo "✗ 端口 ${port} 没起来" >&2; exit 1; }
done

if [[ -n "$DEVICE" ]]; then
  DESTINATION="platform=iOS,id=$DEVICE"
  step "目标：真机 ${DEVICE}（需要开发签名与已解锁的钥匙串）"
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

# 先单独构建 App：Xcode 在 "Products 里没有 OrzMC.app" 时会报
# `bundle identifier for OrzMC couldn't be read`（路径少了 .app），这一步保证产物一定在。
step "构建 App"
if [[ -n "$DEVICE" ]]; then
  xcodebuild build -project OrzMC.xcodeproj -scheme OrzMC -destination "$DESTINATION" \
    -derivedDataPath "$DERIVED_DATA" -onlyUsePackageVersionsFromResolvedFile \
    -skipPackageUpdates -skipPackagePluginValidation -skipMacroValidation 2>&1 | tail -4
else
  xcodebuild build -project OrzMC.xcodeproj -scheme OrzMC -destination "$DESTINATION" \
    -derivedDataPath "$DERIVED_DATA" -onlyUsePackageVersionsFromResolvedFile \
    -skipPackageUpdates -skipPackagePluginValidation -skipMacroValidation \
    CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY='' 2>&1 | tail -4
fi

if [[ -n "$DEVICE" ]]; then
  # 真机流程（实测 iOS 27 / Xcode 27）：
  #   build-for-testing → 修 xctestrun → 装 App → test-without-building -xctestrun
  #
  # 为什么不能直接 `xcodebuild test`：本项目 pbxproj 是手工维护的，Xcode 27 生成的
  # xctestrun 会把 UITargetAppPath 写成 `.../Debug-iphoneos/OrzMC`（少了 `.app`），
  # 于是报 `bundle identifier for OrzMC couldn't be read`，或者 runner 直接起不来
  # （code 74 / testmanagerd 拒绝 dtxproxy 通道）。patch-xctestrun.py 补上真实路径。
  step "构建测试（build-for-testing）"
  xcodebuild build-for-testing "${COMMON[@]}" 2>&1 | tail -4
  XCTESTRUN="$(ls -t "$DERIVED_DATA"/Build/Products/*_iphoneos*.xctestrun | head -1)"
  python3 scripts/dev/patch-xctestrun.py "$XCTESTRUN"

  step "安装 App 到真机"
  xcrun devicectl device install app --device "$DEVICE" \
    "$DERIVED_DATA/Build/Products/Debug-iphoneos/OrzMC.app" 2>&1 | tail -2

  LAN_IP="$(ipconfig getifaddr en0 2>/dev/null || ipconfig getifaddr en1 2>/dev/null || true)"
  step "执行 UI 测试（真机）"
  echo "  假服务端地址：${LAN_IP:-未取到}（真机通过局域网访问 Mac；默认测试用应用内假数据）"
  TEST_RUNNER_UITEST_HOST="$LAN_IP" xcodebuild test-without-building \
    -xctestrun "$XCTESTRUN" -destination "$DESTINATION" 2>&1 \
    | grep -E "Test Case|Test Suite|\*\* TEST|error:" | tail -30
  exit ${PIPESTATUS[0]}
fi

step "构建测试（build-for-testing）"
xcodebuild build-for-testing "${COMMON[@]}" 2>&1 | tail -8

# 同一个坑在模拟器上也存在（Xcode 27 把 UITargetAppPath 写成不带 .app 的路径），
# 所以两条路径都修一遍；修完就不再依赖"预先装 App"这个 workaround。
SIM_XCTESTRUN="$(ls -t "$DERIVED_DATA"/Build/Products/*_iphonesimulator*.xctestrun 2>/dev/null | head -1 || true)"
[[ -n "$SIM_XCTESTRUN" ]] && python3 scripts/dev/patch-xctestrun.py "$SIM_XCTESTRUN"

step "预装 App（双保险：某些 Xcode 版本没装过 App 会读不到 bundle identifier）"
xcrun simctl install "$UDID" "$DERIVED_DATA/Build/Products/Debug-iphonesimulator/OrzMC.app"
# 模拟器里已经装过旧版 test runner 时，xcodebuild 会**沿用旧包**（测试代码改了却不生效，
# 症状是"Executed 0 tests"或跑到已经不存在的用例）。跑之前强制卸掉，让它必须装新的。
xcrun simctl uninstall "$UDID" com.joker.OrzMCUITests.xctrunner 2>/dev/null || true

step "执行 UI 测试（模拟器）"
# 必须显式 -xctestrun：用 -scheme 时 xcodebuild 会自己**重新生成** xctestrun，
# 把我们刚修好的 UITargetAppPath 又覆盖回不带 .app 的版本。
# 空数组要用 ${arr[@]+"${arr[@]}"} 展开成"零个参数"；写成 "${arr[@]:-}" 会变成一个空字符串参数，
# xcodebuild 会报 `Unknown build action ''`。
xcodebuild test-without-building -xctestrun "$SIM_XCTESTRUN" -destination "$DESTINATION" 2>&1 \
  | grep -E "Test Case|Test Suite|\*\* TEST|error:" | tail -30
