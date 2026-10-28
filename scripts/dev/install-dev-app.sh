#!/usr/bin/env bash
# 开发包安装验收：把**本地开发签名构建**的 OrzMC.app 直接装进 /Applications 跑验收。
#
# 为什么需要它（2026-10-27）：
#   以前验收走"打正式包"那条路 —— 构建 Release → 签名 → notarize → dmg/zip → 装 dmg → 断言，
#   一轮 10~15 分钟，其中 9 分钟是在等 Apple 公证。**验收要验的是"装好之后能不能用"**，
#   跟"有没有公证"没关系（公证是发版门禁，不是功能验收）。
#   所以：验收用开发签名构建（Debug 默认 / `--release` 用优化构建），直接覆盖安装，
#   10~20 秒就能在**真实安装位置**上验证（LaunchServices / 资源 / 权限 / 钥匙串 / 更新器都走真路径）。
#
# 和正式包的区别（别拿它当发版）：
#   · 不公证、不打包 dmg、不写 appcast；`spctl` 一定说 rejected（正常，别拿这个判失败）；
#   · 签名是 Apple Development，不是 Developer ID；
#   · Release 开发构建和发布包仍有差别：没有 strip 后的同一份优化产物也可能不同，
#     **发版前的 dry-run 依旧要跑**（`scripts/dev/release.sh` 会打印命令）。
#
# 用法（在 Terminal.app 里跑；ssh/agent 会话拿不到 GUI 钥匙串）：
#   ./scripts/dev/install-dev-app.sh                  # Debug 构建（已有产物则秒装）+ 覆盖安装 + 启动
#   ./scripts/dev/install-dev-app.sh --release        # 用 Release 配置构建（更接近发布包）
#   ./scripts/dev/install-dev-app.sh --no-build       # 不构建，直接装 DerivedData 里现成的产物
#   ./scripts/dev/install-dev-app.sh --no-launch      # 只装不启动
#   ./scripts/dev/install-dev-app.sh --target ~/Applications/OrzMC.app   # 装到别处（不动 /Applications）
#   ./scripts/dev/install-dev-app.sh --accept         # 装完跑无界面自检（MCSM 面板 + 实时流）
#   ./scripts/dev/install-dev-app.sh --restore        # 还原装之前备份的正式版
#
# 验收记录：脚本会打印版本号 / 架构 / minos / 签名主体 / 安装路径，方便贴进 PR 或 HANDOFF。
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

TEAM_ID="${TEAM_ID:-2N62934Y28}"
DERIVED_DATA="${DERIVED_DATA_SIGNED:-$HOME/Library/Developer/Xcode/DerivedData/OrzMC-local}"
BACKUP_DIR="${BACKUP_DIR:-$HOME/Library/Caches/orzmc-app-backup}"
# 默认装到系统位置：验收要覆盖 LaunchServices / 权限 / 钥匙串 ACL 的真实路径。
DEST="${TARGET_APP:-/Applications/OrzMC.app}"

CONFIG="Debug"
DO_BUILD=1
DO_LAUNCH=1
DO_ACCEPT=0
DO_RESTORE=0
KEEP_BACKUP=1

while [[ $# -gt 0 ]]; do
  case "$1" in
    --release) CONFIG="Release" ;;
    --debug) CONFIG="Debug" ;;
    --no-build) DO_BUILD=0 ;;
    --no-launch) DO_LAUNCH=0 ;;
    --accept) DO_ACCEPT=1 ;;
    --restore) DO_RESTORE=1 ;;
    --no-backup) KEEP_BACKUP=0 ;;
    --target) DEST="${2:?--target 需要路径}"; shift ;;
    --backup-dir) BACKUP_DIR="${2:?--backup-dir 需要路径}"; shift ;;
    -h|--help) sed -n '2,30p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "✗ 未知参数: $1（--help 看用法）" >&2; exit 2 ;;
  esac
  shift
done

say() { printf '%s\n' "$*"; }

# ── 还原：把上次备份的正式版放回去 ────────────────────────────────────────────
if [[ "$DO_RESTORE" == "1" ]]; then
  latest="$(ls -1dt "$BACKUP_DIR"/*.app 2>/dev/null | head -1 || true)"
  [[ -n "$latest" ]] || { echo "✗ $BACKUP_DIR 里没有备份" >&2; exit 1; }
  say "▶ 还原 $latest → $DEST"
  osascript -e 'quit app "OrzMC"' >/dev/null 2>&1 || true
  pkill -f "$DEST/Contents/MacOS/OrzMC" >/dev/null 2>&1 || true
  sleep 1
  rm -rf "$DEST"
  /usr/bin/ditto "$latest" "$DEST"
  codesign --verify --deep --strict "$DEST" 2>/dev/null && say "✓ 已还原并校验签名"
  exit 0
fi

# ── 钥匙串必须可用（否则装完也读不到 Token，白验）────────────────────────────
if ! security show-keychain-info "$HOME/Library/Keychains/login.keychain-db" >/dev/null 2>&1; then
  echo "✗ 登录钥匙串不可用（请在 Terminal.app 里运行，或先 security unlock-keychain）" >&2
  exit 1
fi

# ── 构建（复用共享 DerivedData：`check.sh` / `run-macos-signed.sh` 用的是同一个）──
if [[ "$DO_BUILD" == "1" ]]; then
  say "▶ 构建（${CONFIG}，开发签名，复用 ${DERIVED_DATA}）"
  xcodebuild build \
    -project OrzMC.xcodeproj \
    -scheme OrzMC \
    -configuration "$CONFIG" \
    -destination 'platform=macOS' \
    -derivedDataPath "$DERIVED_DATA" \
    -allowProvisioningUpdates \
    -onlyUsePackageVersionsFromResolvedFile \
    -skipPackageUpdates \
    -skipPackagePluginValidation \
    -skipMacroValidation \
    DEVELOPMENT_TEAM="$TEAM_ID" \
    CODE_SIGN_STYLE=Automatic \
    -quiet 2>&1 | tail -20
  say "✓ 构建完成"
fi

APP="$DERIVED_DATA/Build/Products/$CONFIG/OrzMC.app"
[[ -d "$APP" ]] || { echo "✗ 没找到产物: ${APP}（先不加 --no-build 跑一次）" >&2; exit 1; }

# ── 产物体检：版本 / 架构 / 部署目标 / 签名主体 ──────────────────────────────
plist="$APP/Contents/Info.plist"
version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$plist" 2>/dev/null || echo '?')"
build_number="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$plist" 2>/dev/null || echo '?')"
bin="$APP/Contents/MacOS/OrzMC"
archs="$(lipo -archs "$bin" 2>/dev/null || echo '?')"
# 注意：awk 里**不要** `exit` —— 提前退出会让 vtool 吃 SIGPIPE，
# 在 `set -o pipefail` 下整个命令返回 141，脚本会莫名死在半路（踩过）。
minos="$(vtool -show-build "$bin" 2>/dev/null | awk '/minos/{if (!seen) {print $2; seen = 1}}')"
authority="$(codesign -dv --verbose=2 "$APP" 2>&1 | awk -F'=' '/^Authority/ && !seen {print $2; seen = 1}')"

say ""
say "  版本      $version ($build_number)"
say "  配置      $CONFIG"
say "  架构      $archs"
say "  minos     ${minos:-?}"
say "  签名      ${authority:-未签名}"
say "  产物      $APP"

case "${authority:-}" in
  "Apple Development"*) : ;;
  *) say "  ⚠️ 不是开发证书签名 —— 钥匙串里的 Token/密码很可能读不到（验收会假失败）" ;;
esac

# ── 备份现有安装 → 覆盖安装 ─────────────────────────────────────────────────
osascript -e 'quit app "OrzMC"' >/dev/null 2>&1 || true
pkill -f "$DEST/Contents/MacOS/OrzMC" >/dev/null 2>&1 || true
sleep 1

if [[ -d "$DEST" && "$KEEP_BACKUP" == "1" && "$DEST" != "$APP" ]]; then
  mkdir -p "$BACKUP_DIR"
  old_version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$DEST/Contents/Info.plist" 2>/dev/null || echo '0')"
  old_build="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$DEST/Contents/Info.plist" 2>/dev/null || echo '0')"
  backup="$BACKUP_DIR/OrzMC-$old_version-$old_build-$(date +%Y%m%d-%H%M%S).app"
  say "▶ 备份现有安装（$old_version ($old_build)）→ $backup"
  /usr/bin/ditto "$DEST" "$backup"
fi

say "▶ 安装 → $DEST"
rm -rf "$DEST"
mkdir -p "$(dirname "$DEST")"
/usr/bin/ditto "$APP" "$DEST"
codesign --verify --deep --strict "$DEST" || { echo "✗ 安装后签名校验失败" >&2; exit 1; }
say "✓ 已安装并校验签名（开发签名 → spctl 必报 rejected，属正常）"

# ── 启动（走 LaunchServices 的真实路径，不是直接跑二进制）────────────────────
if [[ "$DO_LAUNCH" == "1" && "$DO_ACCEPT" == "0" ]]; then
  say "▶ 启动（首次可能弹钥匙串授权，点「始终允许」）"
  open -a "$DEST" || { echo "✗ 启动失败" >&2; exit 1; }
  sleep 4
  if pgrep -f "$DEST/Contents/MacOS/OrzMC" >/dev/null 2>&1; then
    say "✓ 已启动（$version ($build_number)）"
  else
    echo "✗ 进程没起来（看 Console.app 或直接跑 $DEST/Contents/MacOS/OrzMC 看输出）" >&2
    exit 1
  fi
fi

# ── 可选：无界面自检（MCSM 面板 + 实时流），不需要看界面 ─────────────────────
if [[ "$DO_ACCEPT" == "1" ]]; then
  cache="$HOME/Library/Caches"
  rm -f "$cache"/orzmc-mcsm-*.json
  say "▶ 无界面自检（MCSM_DIAGNOSE + STREAM_PROBE，最多 120 秒）"
  ORZMC_DEMO_MCSM_DIAGNOSE=1 ORZMC_DEMO_MCSM_STREAM_PROBE=1 \
    timeout 120 "$DEST/Contents/MacOS/OrzMC" >/dev/null 2>&1 || true
  python3 - "$cache" <<'PY'
import glob, json, os, sys
files = sorted(glob.glob(os.path.join(sys.argv[1], "orzmc-mcsm-*.json")))
if not files:
    print("  ✗ 没有诊断文件 —— 自检没跑起来（面板没配置？）")
    raise SystemExit(1)
for path in files:
    data = json.load(open(path))
    print(f"  面板 {data.get('panel')}: 错误={data.get('error')}")
    for inst in data.get("instances", []):
        print(f"    实例 {inst.get('nickname')}: {inst.get('state')}")
    for probe in data.get("stream", []) or []:
        state = "LIVE" if probe.get("ready") else "回退"
        print(f"    实时流 {probe.get('nickname')}: {state} {probe.get('fallback', '')}".rstrip())
        if probe.get("error"):
            print(f"      错误 {probe['error']}")
PY
fi

say ""
say "验收提示："
say "  · 装的是开发包：不公证、不打包 dmg —— 发版前仍要跑 scripts/dev/release.sh 的 dry-run；"
say "  · 想拿回正式版：./scripts/dev/install-dev-app.sh --restore（备份在 ${BACKUP_DIR}）。"
