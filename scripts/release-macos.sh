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
    local line
    line="$(developer_id_identity_line)"
    printf "%s" "$line" | sed -n 's/.*"\(Developer ID Application:.*\)"/\1/p'
}

auto_developer_id_signing_identity() {
    local line
    line="$(developer_id_identity_line)"
    printf "%s" "$line" | awk '{ print $2 }'
}

developer_id_identity_line() {
    local keychain_args=()
    if [ -n "${DEVELOPER_ID_KEYCHAIN:-}" ]; then
        keychain_args=("$DEVELOPER_ID_KEYCHAIN")
    fi

    security find-identity -v -p codesigning "${keychain_args[@]}" 2>/dev/null |
        grep '"Developer ID Application:' |
        head -n 1 || true
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

    if [ -n "${DERIVED_DATA_PATH:-}" ]; then
        local derived_data_root="$DERIVED_DATA_PATH"
        if [ "${derived_data_root#/}" = "$derived_data_root" ]; then
            derived_data_root="$ROOT_DIR/$derived_data_root"
        fi

        local found_in_configured_derived_data
        found_in_configured_derived_data="$(find "$derived_data_root" -path "*/SourcePackages/artifacts/sparkle/Sparkle/bin/$tool" -type f -perm -111 2>/dev/null | head -n 1 || true)"
        if [ -n "$found_in_configured_derived_data" ]; then
            printf "%s" "$found_in_configured_derived_data"
            return 0
        fi
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

entitlements_file() {
    local path="$ROOT_DIR/OrzMC/Common/OrzMC.entitlements"
    if [ -f "$path" ] && /usr/libexec/PlistBuddy -c "Print" "$path" 2>/dev/null | grep -q "="; then
        printf "%s" "$path"
    fi
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
    xcrun stapler validate -v "$staple_target"
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

    ditto "$app_path" "$staging/$APP_NAME.app"
    ln -s /Applications "$staging/Applications"
    rm -f "$dmg_path"
    hdiutil create -volname "$APP_NAME" -srcfolder "$staging" -ov -format UDZO "$dmg_path"
    rm -rf "$staging"
    codesign --force --sign "$DEVELOPER_ID_APPLICATION" "$dmg_path"
}

codesign_distribution_args() {
    local args=(
        --sign "$DEVELOPER_ID_SIGNING_IDENTITY" \
        --force \
        --timestamp \
        --options runtime
    )

    if [ -n "${DEVELOPER_ID_KEYCHAIN:-}" ]; then
        args+=(--keychain "$DEVELOPER_ID_KEYCHAIN")
    fi

    printf '%s\0' "${args[@]}"
}

codesign_app_args() {
    codesign_distribution_args

    local entitlements
    entitlements="$(entitlements_file)"
    if [ -n "$entitlements" ]; then
        printf '%s\0' --entitlements "$entitlements"
    fi
}

sign_path() {
    local path="$1"
    shift
    local args=("$@")

    codesign "${args[@]}" "$path"
}

validate_distribution_signing_identity() {
    local keychain_args=()
    local temp_dir
    local probe
    local signature_info

    if [ -n "${DEVELOPER_ID_KEYCHAIN:-}" ]; then
        keychain_args=("$DEVELOPER_ID_KEYCHAIN")
    fi

    log "Validating Developer ID signing identity"
    security find-identity -v -p codesigning "${keychain_args[@]}"
    security find-certificate -a -c "$DEVELOPER_ID_APPLICATION" -Z "${keychain_args[@]}" >/dev/null ||
        fail "Developer ID certificate was not found in the signing keychain. Re-export DEVELOPER_ID_CERT_P12 from the Keychain Access 'My Certificates' item so the private key and certificate are included together."

    temp_dir="$(mktemp -d)"
    probe="$temp_dir/codesign-probe"
    printf "OrzMC Developer ID signing probe\n" > "$probe"
    if [ -n "${DEVELOPER_ID_KEYCHAIN:-}" ]; then
        codesign --force --sign "$DEVELOPER_ID_SIGNING_IDENTITY" --keychain "$DEVELOPER_ID_KEYCHAIN" "$probe"
    else
        codesign --force --sign "$DEVELOPER_ID_SIGNING_IDENTITY" "$probe"
    fi

    signature_info="$(codesign -dv --verbose=4 "$probe" 2>&1)"
    printf "%s\n" "$signature_info" >&2
    if ! printf "%s\n" "$signature_info" | grep -q "^Authority=Developer ID Application:"; then
        rm -rf "$temp_dir"
        fail "Developer ID signing probe did not embed a usable Developer ID certificate authority."
    fi
    if ! codesign -d --extract-certificates="$temp_dir/cert" "$probe" >/dev/null 2>&1 || [ ! -f "$temp_dir/cert0" ]; then
        rm -rf "$temp_dir"
        fail "Developer ID signing probe did not embed the signing certificate chain."
    fi
    rm -rf "$temp_dir"
}

is_mach_o_file() {
    file "$1" | grep -q "Mach-O"
}

sign_exported_app() {
    local app_path="$1"
    local args=()
    local app_args=()
    local nested_path

    while IFS= read -r -d '' arg; do
        args+=("$arg")
    done < <(codesign_distribution_args)

    while IFS= read -r -d '' arg; do
        app_args+=("$arg")
    done < <(codesign_app_args)

    while IFS= read -r nested_path; do
        if is_mach_o_file "$nested_path"; then
            sign_path "$nested_path" "${args[@]}"
        fi
    done < <(
        find "$app_path/Contents" -type f -perm +111 -print 2>/dev/null |
        grep -v "^$app_path/Contents/MacOS/$APP_NAME$" |
        awk '{ print length($0) " " $0 }' |
        sort -rn |
        cut -d ' ' -f 2-
    )

    while IFS= read -r nested_path; do
        sign_path "$nested_path" "${args[@]}"
    done < <(
        find "$app_path/Contents" \
            \( -name "*.app" -o -name "*.xpc" -o -name "*.appex" -o -name "*.framework" -o -name "*.dylib" \) \
            -print 2>/dev/null |
        awk '{ print length($0) " " $0 }' |
        sort -rn |
        cut -d ' ' -f 2-
    )

    # Sign the outer app bundle last with --deep. macOS 26.4 strict validation
    # rejects the exported bundle if nested Sparkle components are not resealed
    # into the final app signature.
    sign_path "$app_path" "${app_args[@]}" --deep
}

validate_app_bundle() {
    local app_path="$1"
    local signature_info
    local entitlements_info

    [ -d "$app_path" ] || fail "App bundle not found at $app_path"
    if ! codesign --verify --deep --strict --all-architectures --verbose=2 "$app_path"; then
        return 1
    fi
    if ! signature_info="$(codesign -dv --verbose=4 "$app_path" 2>&1)"; then
        return 1
    fi
    printf "%s\n" "$signature_info" >&2
    if ! printf "%s\n" "$signature_info" | grep -q "Info.plist entries="; then
        warn "Code signature does not bind Info.plist."
        return 1
    fi
    if ! printf "%s\n" "$signature_info" | grep -q "^Authority=Developer ID Application:"; then
        warn "Code signature does not contain a usable Developer ID Application authority."
        return 1
    fi
    entitlements_info="$(codesign -d --entitlements :- "$app_path" 2>&1 || true)"
    if printf "%s\n" "$entitlements_info" | grep -q "invalid entitlements blob"; then
        printf "%s\n" "$entitlements_info" >&2
        warn "Code signature contains an invalid entitlements blob."
        return 1
    fi
    if [ "${DEVELOPER_ID_SIGNING_IDENTITY:-}" != "-" ]; then
        validate_certificate_chain_embedded "$app_path"
    fi
}

validate_certificate_chain_embedded() {
    local app_path="$1"
    local temp_dir
    temp_dir="$(mktemp -d)"

    if ! codesign -d --extract-certificates="$temp_dir/cert" "$app_path" >/dev/null 2>&1; then
        rm -rf "$temp_dir"
        return 1
    fi

    if [ ! -f "$temp_dir/cert0" ]; then
        rm -rf "$temp_dir"
        warn "Code signature does not embed the signing certificate chain."
        return 1
    fi

    rm -rf "$temp_dir"
}

validate_zip_artifact() {
    local zip_path="$1"
    local temp_dir
    temp_dir="$(mktemp -d)"

    ditto -x -k "$zip_path" "$temp_dir"
    if ! validate_app_bundle "$temp_dir/$APP_NAME.app"; then
        rm -rf "$temp_dir"
        fail "ZIP artifact validation failed: $zip_path"
    fi
    rm -rf "$temp_dir"
}

validate_dmg_artifact() {
    local dmg_path="$1"
    local mount_dir
    local mounted=0
    mount_dir="$(mktemp -d)"

    hdiutil verify "$dmg_path"
    hdiutil attach "$dmg_path" -nobrowse -readonly -mountpoint "$mount_dir"
    mounted=1
    if ! validate_app_bundle "$mount_dir/$APP_NAME.app"; then
        if [ "$mounted" = "1" ]; then
            hdiutil detach "$mount_dir" || true
        fi
        rmdir "$mount_dir" || true
        fail "DMG artifact validation failed: $dmg_path"
    fi

    if [ "$mounted" = "1" ]; then
        hdiutil detach "$mount_dir"
    fi
    rmdir "$mount_dir"
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
require_command file
require_command hdiutil
require_command codesign
require_command spctl
require_command security

[ -f "$CONFIG_FILE" ] || fail "Missing config file: $CONFIG_FILE"

log "Build host toolchain"
sw_vers
xcodebuild -version

MARKETING_VERSION="${MARKETING_VERSION:-$(xcconfig_value MARKETING_VERSION)}"
BUILD_VERSION="${CURRENT_PROJECT_VERSION:-$(xcconfig_value CURRENT_PROJECT_VERSION)}"
[ -n "$MARKETING_VERSION" ] || fail "MARKETING_VERSION is empty."
[ -n "$BUILD_VERSION" ] || fail "CURRENT_PROJECT_VERSION is empty."

DEVELOPER_ID_APPLICATION="${DEVELOPER_ID_APPLICATION:-$(auto_developer_id_application)}"
[ -n "$DEVELOPER_ID_APPLICATION" ] || fail "Set DEVELOPER_ID_APPLICATION to your Developer ID Application certificate common name."

DEVELOPER_ID_SIGNING_IDENTITY="${DEVELOPER_ID_SIGNING_IDENTITY:-$(auto_developer_id_signing_identity)}"
[ -n "$DEVELOPER_ID_SIGNING_IDENTITY" ] || DEVELOPER_ID_SIGNING_IDENTITY="$DEVELOPER_ID_APPLICATION"
validate_distribution_signing_identity

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
ARCHIVE_OPTIONAL_BUILD_SETTINGS=()
if [ -n "${ARCHIVE_ONLY_ACTIVE_ARCH:-}" ]; then
    ARCHIVE_OPTIONAL_BUILD_SETTINGS+=(ONLY_ACTIVE_ARCH="$ARCHIVE_ONLY_ACTIVE_ARCH")
fi
ARCHIVE_SIGNING_ARGS=()
case "${ARCHIVE_CODE_SIGNING_MODE:-manual}" in
    disabled)
        ARCHIVE_SIGNING_ARGS=(
            CODE_SIGN_IDENTITY=
            CODE_SIGNING_REQUIRED=NO
            CODE_SIGNING_ALLOWED=NO
            DEVELOPMENT_TEAM=
        )
        ;;
    manual)
        ARCHIVE_SIGNING_ARGS=(
            DEVELOPMENT_TEAM="$APPLE_TEAM_ID"
            CODE_SIGN_STYLE=Manual
            CODE_SIGN_IDENTITY="$DEVELOPER_ID_APPLICATION"
        )
        ;;
    *)
        fail "Unsupported ARCHIVE_CODE_SIGNING_MODE: ${ARCHIVE_CODE_SIGNING_MODE:-}"
        ;;
esac

rm -rf "$DIST_DIR"
mkdir -p "$DIST_DIR" "$EXPORT_PATH"
write_export_options "$EXPORT_OPTIONS_PLIST"

log "Archiving $APP_NAME $MARKETING_VERSION ($BUILD_VERSION)"
ARCHIVE_COMMAND=(
    xcodebuild archive
    -scheme "$SCHEME"
    -configuration "$CONFIGURATION"
    -destination "generic/platform=macOS"
    -archivePath "$ARCHIVE_PATH"
    "${ARCHIVE_DERIVED_DATA_ARGS[@]}"
    -skipPackagePluginValidation
    -skipMacroValidation
    COMPILER_INDEX_STORE_ENABLE=NO
    SWIFT_SERIALIZE_DEBUGGING_OPTIONS=NO
    -jobs "$(sysctl -n hw.ncpu)"
    "${ARCHIVE_SIGNING_ARGS[@]}"
)
if [ "${#ARCHIVE_OPTIONAL_BUILD_SETTINGS[@]}" -gt 0 ]; then
    ARCHIVE_COMMAND+=("${ARCHIVE_OPTIONAL_BUILD_SETTINGS[@]}")
fi
"${ARCHIVE_COMMAND[@]}"

log "Exporting Developer ID app"
xcodebuild -exportArchive \
    -archivePath "$ARCHIVE_PATH" \
    -exportPath "$EXPORT_PATH" \
    -exportOptionsPlist "$EXPORT_OPTIONS_PLIST"

[ -d "$APP_PATH" ] || fail "Exported app not found at $APP_PATH"

if [ "${RESIGN_EXPORTED_APP:-1}" != "0" ]; then
    log "Re-signing exported app with hardened runtime"
    sign_exported_app "$APP_PATH"
fi

log "Verifying exported app signature"
validate_app_bundle "$APP_PATH"

log "Creating notarization upload zip"
make_zip "$APP_PATH" "$NOTARY_ZIP"
notarize_and_staple "$NOTARY_ZIP" "$APP_PATH"

log "Creating Sparkle update zip"
make_zip "$APP_PATH" "$UPDATE_ZIP"
validate_zip_artifact "$UPDATE_ZIP"

log "Creating signed DMG"
make_dmg "$APP_PATH" "$DMG_PATH"
notarize_and_staple "$DMG_PATH" "$DMG_PATH"
validate_dmg_artifact "$DMG_PATH"

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
