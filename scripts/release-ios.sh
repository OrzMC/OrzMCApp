#!/usr/bin/env bash
# iOS **归档 + 导出 + （可选）TestFlight 上传 / 装开发签名包** 的唯一入口。
#
# 与 macOS 的 `scripts/release-macos.sh` 对应：那个走 Developer ID + notarize + Sparkle，
# 这个走 iOS 的 archive → ipa（development / release-testing / app-store-connect）。
#
# 用法：
#   ./scripts/release-ios.sh                          # 归档 + 导出 development（可选装到真机）
#   ./scripts/release-ios.sh --export app-store-connect   # 导出 App Store 包（TestFlight 用）
#   ./scripts/release-ios.sh --export app-store-connect --upload   # 再上传 TestFlight
#   ./scripts/release-ios.sh --install                # 归档导出后装到已连接的 iPhone
#   ./scripts/release-ios.sh --install --device <UDID>
#   ./scripts/release-ios.sh --skip-archive --archive dist/ios/x.xcarchive   # 只导出/上传
#
# 导出方式（`--export`，取 Xcode 的新名字；老名字自动映射）：
#   debugging          开发签名，装自己/团队注册过的设备（默认）
#   release-testing    Ad hoc（老的 ad-hoc）
#   app-store-connect  App Store / TestFlight（老的 app-store）
#   developer-id       Developer ID（iOS 一般不用）
#
# 签名：
# * 本机（有 Apple Development / Apple Distribution 证书 + 已登录 Apple ID）：
#   走 `CODE_SIGN_STYLE=Automatic` + `-allowProvisioningUpdates`；
# * CI / 无本地证书：设置 `APPSTORE_PRIVATE_KEY`（base64 的 .p8）、`APPSTORE_KEY_ID`、
#   `APPSTORE_ISSUER_ID`，脚本会把它们传给 xcodebuild 的 `-authenticationKey*`，
#   由 Xcode 云签名拉证书与描述文件（不需要把证书塞进 CI 钥匙串）。
#
# TestFlight 上传（`--upload`）需要上面三个 App Store Connect API key 变量之一套；
# `.p8` 只在临时目录里存在，退出即删。上传成功后 App Store Connect 还要处理几分钟。
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

CONFIG_FILE="$ROOT/OrzMC/Configuration/Config.xcconfig"
APP_NAME="${APP_NAME:-OrzMC}"
SCHEME="${SCHEME:-OrzMC}"
TEAM_ID="${TEAM_ID:-2N62934Y28}"
DIST_DIR="${DIST_DIR:-$ROOT/dist/ios}"
DERIVED_DATA="${DERIVED_DATA:-$HOME/Library/Developer/Xcode/DerivedData/OrzMC-ios-archive}"
EXPORT_METHOD="debugging"
DO_UPLOAD=0
DO_INSTALL=0
WAIT_FOR_PROCESSING="${WAIT_FOR_PROCESSING:-0}"
DEVICE=""
SKIP_ARCHIVE=0
ARCHIVE_PATH=""
AUTH_ARGS=()
KEY_DIR=""

log() { printf "\n\033[1m▶ %s\033[0m\n" "$1"; }
warn() { printf "\nwarning: %s\n" "$*" >&2; }
fail() { printf "\nerror: %s\n" "$*" >&2; exit 1; }

cleanup() {
  if [[ -n "$KEY_DIR" && -d "$KEY_DIR" ]]; then rm -rf "$KEY_DIR"; fi
}
trap cleanup EXIT

usage() { sed -n '2,30p' "${BASH_SOURCE[0]}"; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --export) EXPORT_METHOD="${2:?}"; shift 2 ;;
    --upload) DO_UPLOAD=1; shift ;;
    --install) DO_INSTALL=1; shift ;;
    --wait) WAIT_FOR_PROCESSING=1; shift ;;
    --device) DEVICE="${2:?}"; shift 2 ;;
    --skip-archive) SKIP_ARCHIVE=1; shift ;;
    --archive) ARCHIVE_PATH="${2:?}"; SKIP_ARCHIVE=1; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "未知参数: $1" >&2; usage; exit 2 ;;
  esac
done

# 老名字 → Xcode 15+ 的新名字（`xcodebuild -help` 里注明 deprecated）。
case "$EXPORT_METHOD" in
  development) EXPORT_METHOD="debugging" ;;
  ad-hoc) EXPORT_METHOD="release-testing" ;;
  app-store) EXPORT_METHOD="app-store-connect" ;;
esac

require_command() { command -v "$1" >/dev/null 2>&1 || fail "缺少 $1"; }

xcconfig_value() {
  awk -F '=' -v key="$1" '
    $0 !~ /^[[:space:]]*\/\// {
      gsub(/[[:space:]]/, "", $1)
      if ($1 == key) { value = $2; sub(/[[:space:]]*\/\/.*/, "", value); gsub(/^[[:space:]]+|[[:space:]]+$/, "", value); print value; exit }
    }
  ' "$CONFIG_FILE"
}

decode_base64_to_file() {
  local value="$1" output="$2"
  if printf "%s" "$value" | base64 --decode > "$output" 2>/dev/null; then return 0; fi
  if printf "%s" "$value" | base64 -d > "$output" 2>/dev/null; then return 0; fi
  printf "%s" "$value" | base64 -D > "$output"
}

# 云签名：有 App Store Connect API key 就交给 xcodebuild（CI 不需要本地证书）。
prepare_authentication() {
  if [[ -n "${APPSTORE_PRIVATE_KEY:-}" && -n "${APPSTORE_KEY_ID:-}" && -n "${APPSTORE_ISSUER_ID:-}" ]]; then
    KEY_DIR="$(mktemp -d)"
    local key_path="$KEY_DIR/AuthKey_${APPSTORE_KEY_ID}.p8"
    decode_base64_to_file "$APPSTORE_PRIVATE_KEY" "$key_path"
    chmod 600 "$key_path"
    AUTH_ARGS=(
      -authenticationKeyPath "$key_path"
      -authenticationKeyID "$APPSTORE_KEY_ID"
      -authenticationKeyIssuerID "$APPSTORE_ISSUER_ID"
    )
    echo "签名：App Store Connect API key（云签名，key id ${APPSTORE_KEY_ID}）"
    return 0
  fi
  echo "签名：本机钥匙串（Automatic + -allowProvisioningUpdates）"
}

preflight() {
  log "检查环境"
  require_command xcodebuild
  require_command xcrun
  command -v security >/dev/null 2>&1 || fail "缺少 security"
  if ! security show-keychain-info "$HOME/Library/Keychains/login.keychain-db" >/dev/null 2>&1 \
      && [[ -z "${APPSTORE_PRIVATE_KEY:-}" ]]; then
    cat >&2 <<'MSG'
✗ 登录钥匙串不可用（或当前会话没有图形权限），codesign 会失败（errSecInternalComponent）。
  请在 Terminal.app 里运行；或先 `security unlock-keychain ~/Library/Keychains/login.keychain-db`；
  或提供 APPSTORE_PRIVATE_KEY/KEY_ID/ISSUER_ID 走云签名。
MSG
    exit 1
  fi
  MARKETING_VERSION="$(xcconfig_value MARKETING_VERSION)"
  BUILD_VERSION="$(xcconfig_value CURRENT_PROJECT_VERSION)"
  [[ -n "$MARKETING_VERSION" && -n "$BUILD_VERSION" ]] || fail "读不到版本号（${CONFIG_FILE}）"
  echo "版本：$MARKETING_VERSION ($BUILD_VERSION) · 导出方式：$EXPORT_METHOD"
  echo "产物目录：$DIST_DIR"
  prepare_authentication
}

run_archive() {
  mkdir -p "$DIST_DIR"
  ARCHIVE_PATH="$DIST_DIR/${APP_NAME}_${MARKETING_VERSION}_${BUILD_VERSION}_${TIMESTAMP}.xcarchive"
  log "归档（Release / generic iOS）"
  xcodebuild archive \
    -project OrzMC.xcodeproj \
    -scheme "$SCHEME" \
    -configuration Release \
    -destination 'generic/platform=iOS' \
    -archivePath "$ARCHIVE_PATH" \
    -derivedDataPath "$DERIVED_DATA" \
    -allowProvisioningUpdates \
    ${AUTH_ARGS[@]+"${AUTH_ARGS[@]}"} \
    -onlyUsePackageVersionsFromResolvedFile \
    -skipPackageUpdates \
    -skipPackagePluginValidation \
    -skipMacroValidation \
    DEVELOPMENT_TEAM="$TEAM_ID" \
    CODE_SIGN_STYLE=Automatic \
    2>&1 | tail -30
  [[ -d "$ARCHIVE_PATH" ]] || fail "归档失败：找不到 $ARCHIVE_PATH"
  echo "归档：$ARCHIVE_PATH"
}

write_export_options() {
  EXPORT_OPTIONS="$DIST_DIR/ExportOptions-${EXPORT_METHOD}.plist"
  cat > "$EXPORT_OPTIONS" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>method</key>
	<string>${EXPORT_METHOD}</string>
	<key>signingStyle</key>
	<string>automatic</string>
	<key>teamID</key>
	<string>${TEAM_ID}</string>
	<key>destination</key>
	<string>export</string>
	<key>uploadSymbols</key>
	<true/>
	<key>stripSwiftSymbols</key>
	<true/>
	<key>manageAppVersionAndBuildNumber</key>
	<false/>
</dict>
</plist>
PLIST
  plutil -lint "$EXPORT_OPTIONS" >/dev/null || fail "ExportOptions.plist 格式不对：$EXPORT_OPTIONS"
}

run_export() {
  [[ -d "$ARCHIVE_PATH" ]] || fail "找不到归档：${ARCHIVE_PATH}（先不要加 --skip-archive）"
  EXPORT_DIR="$DIST_DIR/${APP_NAME}_${MARKETING_VERSION}_${BUILD_VERSION}_${TIMESTAMP}_${EXPORT_METHOD}"
  rm -rf "$EXPORT_DIR" && mkdir -p "$EXPORT_DIR"
  write_export_options
  log "导出 ipa（${EXPORT_METHOD}）"
  xcodebuild -exportArchive \
    -archivePath "$ARCHIVE_PATH" \
    -exportPath "$EXPORT_DIR" \
    -exportOptionsPlist "$EXPORT_OPTIONS" \
    -allowProvisioningUpdates \
    ${AUTH_ARGS[@]+"${AUTH_ARGS[@]}"} \
    2>&1 | tail -20
  IPA_PATH="$(find "$EXPORT_DIR" -maxdepth 1 -name '*.ipa' | head -1)"
  if [[ -z "$IPA_PATH" ]]; then
    cat >&2 <<'MSG'
✗ 导出失败（没有 .ipa）。

如果是 `app-store-connect` / `release-testing`，且日志里有
`Cloud signing permission error` / `No signing certificate "iOS Distribution" found`
/ `No profiles for 'com.joker.OrzMC.iOS' were found`：

  分发签名（Apple Distribution + App Store 描述文件）是另一套权限，App Store Connect API key
  的角色不够时云签名**建不了**分发证书/描述文件。三条出路：
    1) 本机导出（推荐，今天就能用）：在 Terminal.app 里跑
         ./scripts/release-ios.sh --export app-store-connect --upload
       本机钥匙串里已有 `Apple Distribution` 证书，用自动签名即可；
    2) 把 App Store Connect API key 的角色提到 Admin，云签名才能自动建证书；
    3) 在 CI 里塞分发证书 + 描述文件（manual signing，脚本目前只支持 automatic）。

`--export debugging`（开发签名）在 CI 里是**验证过可用**的，见 docs/ios-release.md。
MSG
    fail "导出失败：$EXPORT_DIR 里没有 .ipa"
  fi
  echo "ipa：$IPA_PATH"
}

verify_ipa() {
  log "校验 ipa"
  local tmp
  tmp="$(mktemp -d)"
  ditto -x -k "$IPA_PATH" "$tmp"
  local app="$tmp/Payload/${APP_NAME}.app"
  [[ -d "$app" ]] || { rm -rf "$tmp"; fail "ipa 里没有 Payload/${APP_NAME}.app"; }
  local version build bundle
  version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app/Info.plist")"
  build="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$app/Info.plist")"
  bundle="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$app/Info.plist")"
  echo "bundle=$bundle version=$version build=$build"
  [[ "$version" = "$MARKETING_VERSION" && "$build" = "$BUILD_VERSION" ]] \
    || warn "ipa 版本与 Config.xcconfig（$MARKETING_VERSION/${BUILD_VERSION}）不一致，检查归档是不是旧的"
  codesign -dv --verbose=2 "$app" 2>&1 | grep -E "Authority|Identifier|TeamIdentifier" | head -4 || true
  /usr/libexec/PlistBuddy -c 'Print :CFBundleIcons.CFBundlePrimaryIcon.CFBundleIconName' "$app/Info.plist" 2>/dev/null \
    | sed 's/^/AppIcon: /' || warn "ipa 里没有 CFBundleIcons（iOS 图标没进包？）"
  rm -rf "$tmp"
}

upload_to_testflight() {
  [[ -n "${APPSTORE_PRIVATE_KEY:-}" && -n "${APPSTORE_KEY_ID:-}" && -n "${APPSTORE_ISSUER_ID:-}" ]] \
    || fail "上传 TestFlight 需要 APPSTORE_PRIVATE_KEY / APPSTORE_KEY_ID / APPSTORE_ISSUER_ID"
  [[ -n "$KEY_DIR" ]] || fail "内部错误：API key 未准备好"
  log "上传 TestFlight（altool --upload-app）"
  local args=(--upload-app -f "$IPA_PATH" -t ios
              --api-key "$APPSTORE_KEY_ID" --api-issuer "$APPSTORE_ISSUER_ID")
  [[ "$WAIT_FOR_PROCESSING" == "1" ]] && args+=(--wait)
  # altool 在 $API_PRIVATE_KEYS_DIR 里找 AuthKey_<key>.p8。
  API_PRIVATE_KEYS_DIR="$KEY_DIR" xcrun altool "${args[@]}" 2>&1 | tail -20
  echo "已上传。App Store Connect 还要处理几分钟，处理完才会出现在 TestFlight；"
  echo "版本号相同的 build 不能重复上传 —— 再传请先提升 CURRENT_PROJECT_VERSION。"
}

install_on_device() {
  log "装开发签名包到真机"
  local args=(--release)
  [[ -n "$DEVICE" ]] && args+=(--device "$DEVICE")
  "$ROOT/scripts/dev/install-ios-device.sh" "${args[@]}"
}

TIMESTAMP="${TIMESTAMP:-$(date +%Y%m%d_%H%M%S)}"

preflight
if [[ "$SKIP_ARCHIVE" == "0" ]]; then
  run_archive
fi
if [[ "$DO_INSTALL" == "1" ]]; then
  # 真机安装走 `install-ios-device.sh`（它用 destination=设备 直接构建 Release，
  # 自动签名会顺带把设备注册进描述文件；比"导出 development ipa 再装"稳）。
  install_on_device
  if [[ "$DO_UPLOAD" == "0" ]]; then
    printf '\n\033[32m完成\033[0m（归档 + 真机安装）\n'
    exit 0
  fi
fi
run_export
verify_ipa
if [[ "$DO_UPLOAD" == "1" ]]; then
  upload_to_testflight
fi
printf '\n\033[32m完成\033[0m（%s）\n' "$EXPORT_METHOD"
echo "归档：${ARCHIVE_PATH:-（--skip-archive）}"
echo "ipa ：$IPA_PATH"
