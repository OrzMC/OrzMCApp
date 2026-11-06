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
#   ./scripts/dev/run-ios-ui-tests.sh --device <UDID> --detach   # 自动进 Terminal 跑并等结果
#   ./scripts/dev/run-ios-ui-tests.sh --real              # 额外跑真实账号/真实服务器用例（+4 分钟）
#   UI_ONLY_TESTING="OrzMCUITests/X/a OrzMCUITests/X/b" …  # 只跑指定用例（空格分隔多个）
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

# `--detach` 要把**原始参数**原样传给 Terminal 里的自己，所以在解析前先存一份。
ORIGINAL_ARGS=("$@")

DETACH=0
# 真实账号/真实服务器用例默认**不跑**：它们要联网、单例最慢 150 秒（额度池反复进出），
# 本地整套会因此多花约 4 分钟，而绝大多数改动跟它们无关。发版/真机验收加 `--real`。
REAL="${UI_TEST_REAL:-0}"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --device) DEVICE="${2:?}"; shift 2 ;;
    --simulator) SIM_NAME="${2:?}"; shift 2 ;;
    --detach) DETACH=1; shift ;;
    --real) REAL=1; shift ;;
    -h|--help) sed -n '2,24p' "${BASH_SOURCE[0]}"; exit 0 ;;
    *) echo "未知参数: $1" >&2; exit 2 ;;
  esac
done

# ── O3：`--detach` 把自己丢进 Terminal.app 跑，并在这里等结果 ──────────────
# 为什么必须 Terminal：真机构建/安装要访问钥匙串私钥，SSH/CI 那种非交互会话会报
# `errSecInternalComponent`。以前只能人肉 `open -a Terminal` + 轮询日志（每轮多 1–2 分钟，
# 且失败时看不到关键行）。现在一条命令拿到退出码 + 末尾日志。
# Codex 等受限 agent 必须在沙箱外执行 --detach：沙箱内 LaunchServices 可能
# 报找不到应用或 kLSNoExecutableErr；这不代表 Terminal 未安装，也与默认终端无关。
if [[ "$DETACH" -eq 1 && "${UI_TESTS_IN_TERMINAL:-0}" != "1" ]]; then
  stamp="$(date +%s)"
  detach_log="${TMPDIR:-/tmp}/orzmc-ui-tests-$stamp.log"
  runner="${TMPDIR:-/tmp}/orzmc-ui-tests-$stamp.command"
  args=""
  for a in "${ORIGINAL_ARGS[@]}"; do args+=" $(printf '%q' "$a")"; done
  self="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"
  cat > "$runner" <<EOF2
#!/bin/bash
cd "$(pwd)" || exit 1
UI_TESTS_IN_TERMINAL=1 "$self"$args >"$detach_log" 2>&1
echo "__UI_TESTS_EXIT__=\$?" >>"$detach_log"
EOF2
  chmod +x "$runner"
  echo "▶ 在 Terminal.app 里执行（日志：${detach_log}）"
  # Agent 沙箱内 LaunchServices 按名称查找可能失败，即使 Terminal 已安装；
  # 显式使用系统路径，也不受用户默认终端设置影响。
  terminal_app="/System/Applications/Utilities/Terminal.app"
  if [[ ! -d "$terminal_app" ]]; then
    echo "✗ 找不到系统 Terminal.app：$terminal_app" >&2
    exit 1
  fi
  if ! /usr/bin/open -a "$terminal_app" "$runner"; then
    echo "✗ 无法启动 Terminal.app；agent 请在沙箱外重试（LaunchServices 的找不到应用/可执行文件错误可能由沙箱导致）。任务：$runner" >&2
    exit 1
  fi
  printf '  等待结果'
  for _ in $(seq 1 900); do
    grep -q "__UI_TESTS_EXIT__=" "$detach_log" 2>/dev/null && break
    printf '.'; sleep 2
  done
  printf '\n'
  if ! grep -q "__UI_TESTS_EXIT__=" "$detach_log" 2>/dev/null; then
    echo "✗ 等待超时（15 分钟）；日志：$detach_log" >&2
    tail -20 "$detach_log" 2>/dev/null >&2
    exit 124
  fi
  code="$(sed -n 's/^__UI_TESTS_EXIT__=//p' "$detach_log" | tail -1)"
  echo
  echo "── 末尾日志 ──"
  grep -aE "Test Case|Test Suite|\*\* TEST|error:|refused channel|automation mode|✗|✓" "$detach_log" 2>/dev/null | tail -25
  echo "──"
  if [[ "$code" == "0" ]]; then
    echo "✓ UI 测试通过（耗时见上）"
  else
    echo "✗ 退出码 ${code}（完整日志：${detach_log}）"
  fi
  exit "${code:-1}"
fi

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
if [[ -n "${ORZMC_UITEST_EXAROTON_TOKEN:-}" && "$REAL" == "1" ]]; then
  export TEST_RUNNER_ORZMC_UITEST_REAL_ACCOUNT=1
elif [[ -n "${ORZMC_UITEST_EXAROTON_TOKEN:-}" ]]; then
  printf '\033[36mℹ 真实账号用例已跳过（约 4 分钟）；需要时加 --real\033[0m\n' >&2
fi
# RCON 用例默认不跑（服务端配置错不该把日常迭代染红），需要时 UI_TEST_RCON=1。
if [[ "${UI_TEST_RCON:-0}" = "1" ]]; then
  export TEST_RUNNER_ORZMC_UITEST_RCON=1
fi
echo "  真实自建服务器：$([[ -n "${ORZMC_UITEST_SELFHOSTED_HOST:-}" ]] && echo 已提供 || echo 未提供)" \
     "· exaroton Token：$([[ -n "${ORZMC_UITEST_EXAROTON_TOKEN:-}" ]] && echo 已提供 || echo 未提供)"

step "启动假 SLP / RCON 服务端"
# 日志留档：起不来时把服务端自己的输出打出来。以前丢进 /dev/null，CI 上只看到
# "✗ 端口 25566 没起来"，完全不知道为什么（2026-11-06 排了一轮）。
SLP_LOG="$(mktemp -t orzmc-slp)"
RCON_LOG="$(mktemp -t orzmc-rcon)"
python3 scripts/test-servers/slp_server.py "$SLP_PORT" >"$SLP_LOG" 2>&1 & PIDS+=("$!")
python3 scripts/test-servers/rcon_server.py "$RCON_PORT" >"$RCON_LOG" 2>&1 & PIDS+=("$!")
for port in "$SLP_PORT" "$RCON_PORT"; do
  for _ in $(seq 1 50); do nc -z 127.0.0.1 "$port" 2>/dev/null && break; sleep 0.1; done
  if ! nc -z 127.0.0.1 "$port" 2>/dev/null; then
    echo "✗ 端口 ${port} 没起来" >&2
    echo "--- slp_server 输出 ---" >&2; cat "$SLP_LOG" >&2 || true
    echo "--- rcon_server 输出 ---" >&2; cat "$RCON_LOG" >&2 || true
    exit 1
  fi
done

# 执行 `test-without-building` 并**核对"确实跑了用例"**。
#
# 2026-11-06 发现：CI 的 `ui-smoke` 用 `-only-testing` 指向一个已被删除的用例，
# xcodebuild 于是跑 0 个用例、**照样退出 0**，绿灯但什么都没测（还白花 13 分钟）。
# 所以在这里把输出落盘、统计实际执行数，为 0 就直接失败并说明原因。
run_ui_tests() { # run_ui_tests <xctestrun> [额外 xcodebuild 参数…]
  local xctestrun="$1"; shift
  local log
  log="$(mktemp -t orzmc-uitest)"
  local rc=0
  # 直接落盘再过滤：管道里套 `|| true` 会把 PIPESTATUS 冲掉（实测），拿不到 xcodebuild 的真实退出码。
  set +e
  xcodebuild test-without-building -xctestrun "$xctestrun" -destination "$DESTINATION" "$@" >"$log" 2>&1
  rc=$?
  set -e
  grep -E "Test Case|Test Suite|\*\* TEST|error:" "$log" | tail -30 || true
  # 只数"结束"行（`passed` / `skipped`），否则 started+结束会被数成两倍。
  local executed skipped
  executed="$(grep -cE "' (passed|skipped) \(" "$log" || true)"
  skipped="$(grep -cE "' skipped \(" "$log" || true)"
  printf '\n  实际执行：%s 个（其中跳过 %s）\n' "$executed" "$skipped"
  rm -f "$log"
  if [[ "$rc" -ne 0 ]]; then
    return "$rc"
  fi
  if [[ "${executed:-0}" -eq 0 ]]; then
    printf '\033[31m✗ 一个用例都没跑\033[0m：`-only-testing` 指向的用例可能已被删除或改名（UI_ONLY_TESTING=%s）\n' "${UI_ONLY_TESTING:-<无>}" >&2
    return 1
  fi
  return 0
}

# 真机预检（**只警告，不阻断**）：
#
# 2026-11-06 复核（推翻 2026-10-26 的"必须插数据线"结论）：
#   · **Wi-Fi 也能跑**：`transportType=localNetwork`、没插线，整套真机 UI 测试
#     `** TEST EXECUTE SUCCEEDED **`（同一天同一台 iPhone SE3 / iOS 27.2）。
#   · 真机 UI 测试的**实际门槛**是设备允许「UI 自动化」
#     （设置 → 开发者 → 启用 UI 自动化），否则报
#     `Timed out while enabling automation mode`；
#     **插线状态下同样会报**（2026-11-06 19:12 实测），所以"插线"不是判据。
#   · 设备保持**解锁亮屏**；OS 比 Xcode SDK 新时只提示（27.2 vs 27.0 当天跑通了）。
#   · 插线的价值：安装/日志更稳、更快，但**不是必需**。
#
# 所以这里只做**信息性提醒**，绝不 exit —— 早期版本误判为"版本不匹配必失败"/"必须插线"，
# 会挡住本来能跑的机器。
preflight_device() {
  local udid="$1" dev_os sdk_ver
  dev_os="$(xcrun devicectl device info details --device "$udid" --json-output - 2>/dev/null \
    | python3 -c 'import json,sys; print(json.load(sys.stdin)["result"]["deviceProperties"]["osVersionNumber"])' 2>/dev/null || true)"
  sdk_ver="$(xcodebuild -showsdks 2>/dev/null | sed -n 's/.*-sdk iphoneos\([0-9.]*\).*/\1/p' | head -1)"
  [[ -n "$dev_os" && -n "$sdk_ver" ]] || return 0
  # 逐段比较：设备版本 > SDK 版本 → 不兼容（只比 major/minor，patch 差异常可容忍，但也提示）
  local newer
  newer="$(python3 - "$dev_os" "$sdk_ver" <<'PY2'
import sys
def parts(v): return [int(x) for x in v.split(".") if x.isdigit()]
d, s = parts(sys.argv[1]), parts(sys.argv[2])
print("yes" if d > s else "no")
PY2
)"
  if [[ "$newer" == "yes" ]]; then
    printf '\n\033[33m⚠ 设备 iOS %s 比本机 Xcode 的 iOS SDK %s 新\033[0m\n' "$dev_os" "$sdk_ver" >&2
    printf '  通常仍能跑，但真机 UI 测试失败时这会是第一个要排除的项（升级 Xcode 或用 --simulator）。\n' >&2
  fi

  # 运输方式：只报信息，不再说"必须插线"。
  # 2026-11-06 实测：`localNetwork`（Wi-Fi、没插线）整套真机 UI 测试通过；
  # 失败时先查「启用 UI 自动化」与设备锁屏，而不是连接方式。
  local transport
  transport="$(xcrun devicectl device info details --device "$udid" 2>/dev/null \
    | sed -n 's/.*Transport Type: *//p' | head -1)"
  if [[ -n "$transport" ]]; then
    printf '\n\033[36mℹ 设备连接方式：%s\033[0m\n' "$transport" >&2
    if [[ "$transport" != "wired" ]]; then
      printf '  Wi-Fi 也能跑真机 UI 测试（2026-11-06 实测）；插线只是安装/日志更稳。\n' >&2
      printf '  失败时先确认：设备解锁亮屏 + 设置→开发者→启用 UI 自动化（否则 Timed out while enabling automation mode）。\n' >&2
    fi
  fi
}

if [[ -n "$DEVICE" ]]; then
  DESTINATION="platform=iOS,id=$DEVICE"
  preflight_device "$DEVICE"
  step "目标：真机 ${DEVICE}（需要开发签名与已解锁的钥匙串）"
else
  UDID="$(xcrun simctl list devices available | grep -F "$SIM_NAME (" | head -1 | sed -E 's/.*\(([0-9A-F-]{36})\).*/\1/')"
  if [[ -z "$UDID" ]]; then
    echo "✗ 找不到模拟器「${SIM_NAME}」，可先创建：xcrun simctl create \"$SIM_NAME\" \\" >&2
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
  # 不要加 `-skipPackageUpdates`：它等于"完全不许联网取依赖"。CI 上 `ui-smoke` 恢复了
  # DerivedData 缓存后，若缓存的 `SourcePackages` 与 `Package.resolved` 略有出入，
  # SwiftPM 会直接 `Couldn't check out revision …` 而**不会补 fetch**（2026-11-06 踩了两次，
  # 两次失败的 SHA 还不一样）。保留 `-onlyUsePackageVersionsFromResolvedFile` 就已经锁版本了。
  -skipPackagePluginValidation
  -skipMacroValidation
)
[[ -n "$DEVICE" ]] || COMMON+=(CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY='')
# 可选：`UI_ONLY_TESTING=OrzMCUITests/RemotePanelsUITests/testFoo` 只跑一个用例
# （排查抖动/复跑单个用例时，省掉整套 6 分钟）。
if [[ -n "${UI_ONLY_TESTING:-}" ]]; then
  for id in $UI_ONLY_TESTING; do COMMON+=(-only-testing:"$id"); done
fi

# 先单独构建 App：Xcode 在 "Products 里没有 OrzMC.app" 时会报
# `bundle identifier for OrzMC couldn't be read`（路径少了 .app），这一步保证产物一定在。
step "构建 App"
if [[ -n "$DEVICE" ]]; then
  xcodebuild build -project OrzMC.xcodeproj -scheme OrzMC -destination "$DESTINATION" \
    -derivedDataPath "$DERIVED_DATA" -onlyUsePackageVersionsFromResolvedFile \
    -skipPackagePluginValidation -skipMacroValidation 2>&1 | tail -4
else
  xcodebuild build -project OrzMC.xcodeproj -scheme OrzMC -destination "$DESTINATION" \
    -derivedDataPath "$DERIVED_DATA" -onlyUsePackageVersionsFromResolvedFile \
    -skipPackagePluginValidation -skipMacroValidation \
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
  # `-only-testing` 在 `test-without-building` 上也生效；用 ${arr[@]+…} 展开成"零个参数"，
  # 否则空数组会变成一个空字符串参数（踩过：`Unknown build action ''`）。
  ONLY_ARGS=()
  for id in ${UI_ONLY_TESTING:-}; do ONLY_ARGS+=(-only-testing:"$id"); done
  export TEST_RUNNER_UITEST_HOST="$LAN_IP"
  run_ui_tests "$XCTESTRUN" "${ONLY_ARGS[@]+"${ONLY_ARGS[@]}"}"
  exit $?
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
ONLY_ARGS=()
for id in ${UI_ONLY_TESTING:-}; do ONLY_ARGS+=(-only-testing:"$id"); done
run_ui_tests "$SIM_XCTESTRUN" "${ONLY_ARGS[@]+"${ONLY_ARGS[@]}"}"
