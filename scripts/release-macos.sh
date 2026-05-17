#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG_FILE="$ROOT_DIR/OrzMC/Configuration/Config.xcconfig"
SCHEME="${SCHEME:-OrzMC}"
CONFIGURATION="${CONFIGURATION:-Release}"
APP_NAME="${APP_NAME:-OrzMC}"
GITHUB_REPOSITORY="${GITHUB_REPOSITORY:-OrzGeeker/OrzMCApp}"
NOTARY_KEY_FILE=""
SPARKLE_TEMP_KEY_FILE=""
NOTARYTOOL_ARGS=()

log() {
    printf "\n==> %s\n" "$*"
}

warn() {
    printf "\nwarning: %s\n" "$*" >&2
}

fail() {
    printf "\nerror: %s\n" "$*" >&2
    exit 1
}

require_command() {
    command -v "$1" >/dev/null 2>&1 || fail "Missing required command: $1"
}

decode_base64_to_file() {
    local value="$1"
    local output="$2"

    if printf "%s" "$value" | base64 --decode > "$output" 2>/dev/null; then
        return 0
    fi
    if printf "%s" "$value" | base64 -d > "$output" 2>/dev/null; then
        return 0
    fi
    printf "%s" "$value" | base64 -D > "$output"
}

xcconfig_value() {
    local key="$1"
    awk -F '=' -v key="$key" '
        $0 !~ /^[[:space:]]*\/\// {
            gsub(/[[:space:]]/, "", $1)
            if ($1 == key) {
                value = $2
                sub(/[[:space:]]*\/\/.*/, "", value)
                gsub(/^[[:space:]]+|[[:space:]]+$/, "", value)
                print value
                exit
            }
        }
    ' "$CONFIG_FILE"
}

auto_developer_id_application() {
    security find-identity -v -p codesigning 2>/dev/null |
        sed -n 's/.*"\(Developer ID Application:.*\)"/\1/p' |
        head -n 1
}

team_id_from_identity() {
    printf "%s" "$1" | sed -n 's/.*(\([A-Z0-9][A-Z0-9]*\)).*/\1/p'
}

find_sparkle_tool() {
    local tool="$1"
    if [ -n "${SPARKLE_BIN_DIR:-}" ] && [ -x "$SPARKLE_BIN_DIR/$tool" ]; then
        printf "%s/%s" "$SPARKLE_BIN_DIR" "$tool"
        return 0
    fi

    local found
    found="$(find "$HOME/Library/Developer/Xcode/DerivedData" -path "*/SourcePackages/artifacts/sparkle/Sparkle/bin/$tool" -type f -perm -111 2>/dev/null | head -n 1 || true)"
    if [ -n "$found" ]; then
        printf "%s" "$found"
        return 0
    fi

    found="$(find "$HOME/Library/Developer/Xcode/DerivedData" -path "*/SourcePackages/checkouts/Sparkle/$tool" -type f -perm -111 2>/dev/null | head -n 1 || true)"
    if [ -n "$found" ]; then
        printf "%s" "$found"
        return 0
    fi

    return 1
}

cleanup_sensitive_files() {
    if [ -n "$NOTARY_KEY_FILE" ]; then
        rm -f "$NOTARY_KEY_FILE"
    fi
    if [ -n "$SPARKLE_TEMP_KEY_FILE" ]; then
        rm -f "$SPARKLE_TEMP_KEY_FILE"
    fi
}

trap cleanup_sensitive_files EXIT

prepare_notarytool_args() {
    if [ -n "${NOTARY_KEYCHAIN_PROFILE:-}" ]; then
        NOTARYTOOL_ARGS=(--keychain-profile "$NOTARY_KEYCHAIN_PROFILE")
        return 0
    fi

    if [ -n "${APPSTORE_PRIVATE_KEY:-}" ] && [ -n "${APPSTORE_KEY_ID:-}" ] && [ -n "${APPSTORE_ISSUER_ID:-}" ]; then
        NOTARY_KEY_FILE="$DIST_DIR/AuthKey_${APPSTORE_KEY_ID}.p8"
        decode_base64_to_file "$APPSTORE_PRIVATE_KEY" "$NOTARY_KEY_FILE"
        chmod 600 "$NOTARY_KEY_FILE"
        NOTARYTOOL_ARGS=(--key "$NOTARY_KEY_FILE" --key-id "$APPSTORE_KEY_ID" --issuer "$APPSTORE_ISSUER_ID")
        return 0
    fi

    fail "Set NOTARY_KEYCHAIN_PROFILE, or APPSTORE_PRIVATE_KEY/APPSTORE_KEY_ID/APPSTORE_ISSUER_ID. Use SKIP_NOTARIZE=1 for local packaging only."
}

notarize_and_staple() {
    local artifact="$1"
    local staple_target="$2"

    if [ "${SKIP_NOTARIZE:-0}" = "1" ]; then
        warn "Skipping notarization for $artifact"
        return 0
    fi

    prepare_notarytool_args

    log "Submitting $artifact to Apple notary service"
    xcrun notarytool submit "$artifact" "${NOTARYTOOL_ARGS[@]}" --wait --timeout "${NOTARY_TIMEOUT_DURATION:-30m}"

    log "Stapling notarization ticket to $staple_target"
    local attempts="${STAPLER_ATTEMPTS:-10}"
    local sleep_seconds="${STAPLER_SLEEP_SECONDS:-30}"
    local attempt=1
    until xcrun stapler staple "$staple_target"; do
        if [ "$attempt" -ge "$attempts" ]; then
            fail "Stapling failed for $staple_target after $attempts attempts."
        fi
        warn "Staple attempt $attempt failed; retrying in ${sleep_seconds}s."
        sleep "$sleep_seconds"
        attempt=$((attempt + 1))
    done
    xcrun stapler validate "$staple_target"
}

write_export_options() {
    local path="$1"
    cat > "$path" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>developer-id</string>
    <key>signingStyle</key>
    <string>manual</string>
    <key>signingCertificate</key>
    <string>Developer ID Application</string>
    <key>teamID</key>
    <string>$APPLE_TEAM_ID</string>
    <key>stripSwiftSymbols</key>
    <true/>
</dict>
</plist>
PLIST
}

make_zip() {
    local app_path="$1"
    local zip_path="$2"
    rm -f "$zip_path"
    ditto -c -k --keepParent "$app_path" "$zip_path"
}

make_dmg() {
    local app_path="$1"
    local dmg_path="$2"
    local staging
    staging="$(mktemp -d)"

    cp -R "$app_path" "$staging/$APP_NAME.app"
    ln -s /Applications "$staging/Applications"
    rm -f "$dmg_path"
    hdiutil create -volname "$APP_NAME" -srcfolder "$staging" -ov -format UDZO "$dmg_path"
    rm -rf "$staging"
    codesign --force --sign "$DEVELOPER_ID_APPLICATION" "$dmg_path"
}

update_appcast() {
    local archives_dir="$1"
    local update_zip="$2"
    local release_notes="${3:-}"
    local generate_appcast="$4"

    mkdir -p "$archives_dir"
    if [ -f "$ROOT_DIR/products/appcast.xml" ]; then
        cp "$ROOT_DIR/products/appcast.xml" "$archives_dir/appcast.xml"
    fi
    cp "$update_zip" "$archives_dir/"

    if [ -n "$release_notes" ] && [ -f "$release_notes" ]; then
        cp "$release_notes" "$archives_dir/$(basename "${update_zip%.*}").md"
    fi

    local args=(
        "--download-url-prefix" "$RELEASE_DOWNLOAD_URL_PREFIX"
        "--maximum-versions" "${SPARKLE_MAXIMUM_VERSIONS:-3}"
        "--versions" "$BUILD_VERSION"
    )

    if [ -n "${SPARKLE_ED_KEY_FILE:-}" ]; then
        args+=("--ed-key-file" "$SPARKLE_ED_KEY_FILE")
    elif [ -n "${SPARKLE_ED_PRIVATE_KEY:-}" ]; then
        SPARKLE_TEMP_KEY_FILE="$DIST_DIR/sparkle_ed_private_key"
        decode_base64_to_file "$SPARKLE_ED_PRIVATE_KEY" "$SPARKLE_TEMP_KEY_FILE"
        chmod 600 "$SPARKLE_TEMP_KEY_FILE"
        args+=("--ed-key-file" "$SPARKLE_TEMP_KEY_FILE")
    fi

    log "Generating Sparkle appcast"
    "$generate_appcast" "${args[@]}" "$archives_dir"
    mkdir -p "$ROOT_DIR/products"
    cp "$archives_dir/appcast.xml" "$ROOT_DIR/products/appcast.xml"
}

publish_github_release() {
    [ "${PUBLISH_GITHUB:-0}" = "1" ] || return 0
    require_command gh

    local notes_args=()
    if [ -n "${RELEASE_NOTES_FILE:-}" ] && [ -f "$RELEASE_NOTES_FILE" ]; then
        notes_args=(--notes-file "$RELEASE_NOTES_FILE")
    else
        notes_args=(--notes "Release $MARKETING_VERSION ($BUILD_VERSION)")
    fi

    log "Publishing GitHub release $RELEASE_TAG"
    if gh release view "$RELEASE_TAG" --repo "$GITHUB_REPOSITORY" >/dev/null 2>&1; then
        gh release upload "$RELEASE_TAG" "$UPDATE_ZIP" "$DMG_PATH" "$ROOT_DIR/products/appcast.xml" --repo "$GITHUB_REPOSITORY" --clobber
    else
        gh release create "$RELEASE_TAG" "$UPDATE_ZIP" "$DMG_PATH" "$ROOT_DIR/products/appcast.xml" \
            --repo "$GITHUB_REPOSITORY" \
            --title "$RELEASE_TAG" \
            "${notes_args[@]}"
    fi
}

require_command xcodebuild
require_command xcrun
require_command ditto
require_command hdiutil
require_command codesign
require_command spctl
require_command security

[ -f "$CONFIG_FILE" ] || fail "Missing config file: $CONFIG_FILE"

MARKETING_VERSION="${MARKETING_VERSION:-$(xcconfig_value MARKETING_VERSION)}"
BUILD_VERSION="${CURRENT_PROJECT_VERSION:-$(xcconfig_value CURRENT_PROJECT_VERSION)}"
[ -n "$MARKETING_VERSION" ] || fail "MARKETING_VERSION is empty."
[ -n "$BUILD_VERSION" ] || fail "CURRENT_PROJECT_VERSION is empty."

DEVELOPER_ID_APPLICATION="${DEVELOPER_ID_APPLICATION:-$(auto_developer_id_application)}"
[ -n "$DEVELOPER_ID_APPLICATION" ] || fail "Set DEVELOPER_ID_APPLICATION to your Developer ID Application certificate common name."

APPLE_TEAM_ID="${APPLE_TEAM_ID:-$(team_id_from_identity "$DEVELOPER_ID_APPLICATION")}"
[ -n "$APPLE_TEAM_ID" ] || fail "Set APPLE_TEAM_ID, or use a Developer ID identity that includes the team id."

GENERATE_APPCAST="${GENERATE_APPCAST:-$(find_sparkle_tool generate_appcast || true)}"
[ -x "$GENERATE_APPCAST" ] || fail "Unable to find Sparkle generate_appcast. Set SPARKLE_BIN_DIR or GENERATE_APPCAST."

RELEASE_TAG="${RELEASE_TAG:-$MARKETING_VERSION}"
RELEASE_DOWNLOAD_URL_PREFIX="${RELEASE_DOWNLOAD_URL_PREFIX:-https://github.com/$GITHUB_REPOSITORY/releases/download/$RELEASE_TAG/}"
TIMESTAMP="${RELEASE_TIMESTAMP:-$(date +%Y%m%d_%H%M%S)}"
DIST_DIR="${DIST_DIR:-$ROOT_DIR/dist/macos/$MARKETING_VERSION-$BUILD_VERSION}"
ARCHIVE_PATH="$DIST_DIR/archive/$APP_NAME.xcarchive"
EXPORT_PATH="$DIST_DIR/export"
APP_PATH="$EXPORT_PATH/$APP_NAME.app"
EXPORT_OPTIONS_PLIST="$DIST_DIR/ExportOptions.plist"
NOTARY_ZIP="$DIST_DIR/${APP_NAME}_${MARKETING_VERSION}_${BUILD_VERSION}_${TIMESTAMP}_notary.zip"
UPDATE_ZIP="$DIST_DIR/${APP_NAME}_${MARKETING_VERSION}_${BUILD_VERSION}_${TIMESTAMP}.zip"
DMG_PATH="$DIST_DIR/${APP_NAME}_${MARKETING_VERSION}_${BUILD_VERSION}_${TIMESTAMP}.dmg"
APPCAST_WORK_DIR="$DIST_DIR/appcast"
ARCHIVE_DERIVED_DATA_ARGS=()
if [ -n "${DERIVED_DATA_PATH:-}" ]; then
    ARCHIVE_DERIVED_DATA_ARGS=(-derivedDataPath "$DERIVED_DATA_PATH")
fi

rm -rf "$DIST_DIR"
mkdir -p "$DIST_DIR" "$EXPORT_PATH"
write_export_options "$EXPORT_OPTIONS_PLIST"

log "Archiving $APP_NAME $MARKETING_VERSION ($BUILD_VERSION)"
xcodebuild archive \
    -scheme "$SCHEME" \
    -configuration "$CONFIGURATION" \
    -destination "generic/platform=macOS" \
    -archivePath "$ARCHIVE_PATH" \
    "${ARCHIVE_DERIVED_DATA_ARGS[@]}" \
    -skipPackagePluginValidation \
    -skipMacroValidation \
    COMPILER_INDEX_STORE_ENABLE=NO \
    SWIFT_SERIALIZE_DEBUGGING_OPTIONS=NO \
    -jobs "$(sysctl -n hw.ncpu)" \
    DEVELOPMENT_TEAM="$APPLE_TEAM_ID" \
    CODE_SIGN_STYLE=Manual \
    CODE_SIGN_IDENTITY="$DEVELOPER_ID_APPLICATION" \
    "CODE_SIGN_IDENTITY[sdk=macosx*]=$DEVELOPER_ID_APPLICATION" \
    SKIP_INSTALL=NO \
    ONLY_ACTIVE_ARCH=NO

log "Exporting Developer ID app"
xcodebuild -exportArchive \
    -archivePath "$ARCHIVE_PATH" \
    -exportPath "$EXPORT_PATH" \
    -exportOptionsPlist "$EXPORT_OPTIONS_PLIST"

[ -d "$APP_PATH" ] || fail "Exported app not found at $APP_PATH"

log "Verifying exported app signature"
codesign --verify --deep --strict --verbose=2 "$APP_PATH"

log "Creating notarization upload zip"
make_zip "$APP_PATH" "$NOTARY_ZIP"
notarize_and_staple "$NOTARY_ZIP" "$APP_PATH"

log "Creating Sparkle update zip"
make_zip "$APP_PATH" "$UPDATE_ZIP"

log "Creating signed DMG"
make_dmg "$APP_PATH" "$DMG_PATH"
notarize_and_staple "$DMG_PATH" "$DMG_PATH"

log "Assessing app with Gatekeeper"
if ! spctl --assess --type execute --verbose=4 "$APP_PATH"; then
    warn "Gatekeeper assessment failed. If this was a SKIP_NOTARIZE=1 run, this is expected."
fi

update_appcast "$APPCAST_WORK_DIR" "$UPDATE_ZIP" "${RELEASE_NOTES_FILE:-}" "$GENERATE_APPCAST"
publish_github_release

log "Release artifacts"
printf "App:     %s\n" "$APP_PATH"
printf "ZIP:     %s\n" "$UPDATE_ZIP"
printf "DMG:     %s\n" "$DMG_PATH"
printf "Appcast: %s\n" "$ROOT_DIR/products/appcast.xml"
