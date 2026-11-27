#!/usr/bin/env bash
set -euo pipefail

APP_NAME="Sonos Macbar"
EXECUTABLE_NAME="sonos_macbar"
BUNDLE_EXECUTABLE_NAME="SonosMacbar"
BUNDLE_ID="${SONOS_MACBAR_BUNDLE_ID:-de.alania-bonn.sonos-macbar}"
VERSION="${SONOS_MACBAR_VERSION:-0.2.4}"
SCRATCH_DIR="${TMPDIR:-/tmp}/sonos_macbar-swiftpm-build"
DIST_DIR="${SONOS_MACBAR_DIST_DIR:-dist}"
APP_DIR="${DIST_DIR}/${APP_NAME}.app"
CONTENTS_DIR="${APP_DIR}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
RESOURCES_DIR="${CONTENTS_DIR}/Resources"
FRAMEWORKS_DIR="${CONTENTS_DIR}/Frameworks"
SPARKLE_ARTIFACT="${SCRATCH_DIR}/artifacts/sparkle/Sparkle"
SPARKLE_PUBLIC_KEY="${SONOS_MACBAR_SPARKLE_PUBLIC_KEY:-}"
UPDATE_FEED_URL="${SONOS_MACBAR_UPDATE_FEED_URL:-https://github.com/AntoinS/sonos_macbar/releases/latest/download/appcast.xml}"
SOURCE_ICON="Resources/AppIcon/app-icon.png"
APP_ICON="AppIcon.icns"
GENERATED_APP_ICON="${TMPDIR:-/tmp}/sonos_macbar-${APP_ICON}"
MENU_BAR_ICON_SOURCE="Resources/AppIcon/menu-bar-icon.png"
MENU_BAR_ICON="MenuBarIcon.png"

cd "$(dirname "$0")/.."

export CLANG_MODULE_CACHE_PATH="${CLANG_MODULE_CACHE_PATH:-${TMPDIR:-/tmp}/sonos_macbar-clang-cache}"
export SWIFT_MODULE_CACHE_PATH="${SWIFT_MODULE_CACHE_PATH:-${TMPDIR:-/tmp}/sonos_macbar-swift-cache}"

APP_ICON_SOURCE="Resources/${APP_ICON}"
if [[ ! -f "${APP_ICON_SOURCE}" || "${SOURCE_ICON}" -nt "${APP_ICON_SOURCE}" ]]; then
    SONOS_MACBAR_APP_ICON_OUTPUT="${GENERATED_APP_ICON}" bash scripts/generate_app_icon.sh
    APP_ICON_SOURCE="${GENERATED_APP_ICON}"
fi

swift build -c release --disable-sandbox --scratch-path "$SCRATCH_DIR"

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR" "$FRAMEWORKS_DIR"

cp "${SCRATCH_DIR}/release/${EXECUTABLE_NAME}" "${MACOS_DIR}/${BUNDLE_EXECUTABLE_NAME}"
chmod +x "${MACOS_DIR}/${BUNDLE_EXECUTABLE_NAME}"
cp "${APP_ICON_SOURCE}" "${RESOURCES_DIR}/${APP_ICON}"
cp "${MENU_BAR_ICON_SOURCE}" "${RESOURCES_DIR}/${MENU_BAR_ICON}"
cp "Resources/UPnPCast-LICENSE.txt" "${RESOURCES_DIR}/"
install -m 644 "${SCRATCH_DIR}/checkouts/Sparkle/LICENSE" "${RESOURCES_DIR}/Sparkle-LICENSE.txt"
ditto "${SPARKLE_ARTIFACT}/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework" \
    "${FRAMEWORKS_DIR}/Sparkle.framework"

RPATH='@executable_path/../Frameworks'
if ! otool -l "${MACOS_DIR}/${BUNDLE_EXECUTABLE_NAME}" |
    awk -v rpath="$RPATH" '$1 == "path" && $2 == rpath { found = 1 } END { exit !found }'; then
    install_name_tool -add_rpath "$RPATH" "${MACOS_DIR}/${BUNDLE_EXECUTABLE_NAME}"
fi

cat > "${CONTENTS_DIR}/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleDisplayName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleExecutable</key>
    <string>${BUNDLE_EXECUTABLE_NAME}</string>
    <key>CFBundleIdentifier</key>
    <string>${BUNDLE_ID}</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>${APP_NAME}</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>${VERSION}</string>
    <key>CFBundleVersion</key>
    <string>${VERSION}</string>
    <key>CFBundleURLTypes</key>
    <array>
        <dict>
            <key>CFBundleURLName</key>
            <string>${BUNDLE_ID}.oauth</string>
            <key>CFBundleURLSchemes</key>
            <array>
                <string>sonos-macbar</string>
            </array>
        </dict>
    </array>
    <key>LSApplicationCategoryType</key>
    <string>public.app-category.utilities</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSLocalNetworkUsageDescription</key>
    <string>Sonos Macbar uses your local network to adjust your Sonos equalizer.</string>
    <key>NSBonjourServices</key>
    <array>
        <string>_sonos._tcp</string>
    </array>
    <key>NSAppTransportSecurity</key>
    <dict>
        <key>NSAllowsLocalNetworking</key>
        <true/>
    </dict>
</dict>
</plist>
PLIST

if [[ -n "$SPARKLE_PUBLIC_KEY" ]]; then
    plutil -insert SUPublicEDKey -string "$SPARKLE_PUBLIC_KEY" "${CONTENTS_DIR}/Info.plist"
    plutil -insert SUFeedURL -string "$UPDATE_FEED_URL" "${CONTENTS_DIR}/Info.plist"
    plutil -insert SUEnableAutomaticChecks -bool YES "${CONTENTS_DIR}/Info.plist"
    plutil -insert SUAllowsAutomaticUpdates -bool NO "${CONTENTS_DIR}/Info.plist"
    plutil -insert SUVerifyUpdateBeforeExtraction -bool YES "${CONTENTS_DIR}/Info.plist"
    plutil -insert SURequireSignedFeed -bool YES "${CONTENTS_DIR}/Info.plist"
fi

printf "APPL????" > "${CONTENTS_DIR}/PkgInfo"

if command -v xattr >/dev/null 2>&1; then
    xattr -cr "$APP_DIR"
fi

if command -v codesign >/dev/null 2>&1; then
    codesign --force --sign - "$APP_DIR" >/dev/null
fi

echo "Built ${APP_DIR}"
echo
echo "Install it with:"
echo "  cp -R '${APP_DIR}' /Applications/"
