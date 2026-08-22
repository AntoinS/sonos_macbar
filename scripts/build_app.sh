#!/usr/bin/env bash
set -euo pipefail

APP_NAME="Sonos Macbar"
EXECUTABLE_NAME="sonos_macbar"
BUNDLE_EXECUTABLE_NAME="SonosMacbar"
BUNDLE_ID="${SONOS_MACBAR_BUNDLE_ID:-de.alania-bonn.sonos-macbar}"
VERSION="0.1.0"
BUILD_DIR=".build/release"
SCRATCH_DIR="${TMPDIR:-/tmp}/sonos_macbar-swiftpm-build"
DIST_DIR="${SONOS_MACBAR_DIST_DIR:-dist}"
APP_DIR="${DIST_DIR}/${APP_NAME}.app"
CONTENTS_DIR="${APP_DIR}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
RESOURCES_DIR="${CONTENTS_DIR}/Resources"
APP_ICON="AppIcon.icns"

cd "$(dirname "$0")/.."

export CLANG_MODULE_CACHE_PATH="${CLANG_MODULE_CACHE_PATH:-${TMPDIR:-/tmp}/sonos_macbar-clang-cache}"
export SWIFT_MODULE_CACHE_PATH="${SWIFT_MODULE_CACHE_PATH:-${TMPDIR:-/tmp}/sonos_macbar-swift-cache}"

if [[ ! -f "Resources/${APP_ICON}" ]]; then
    swift scripts/generate_app_icon.swift
fi

swift build -c release --disable-sandbox --scratch-path "$SCRATCH_DIR"

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

cp "${SCRATCH_DIR}/release/${EXECUTABLE_NAME}" "${MACOS_DIR}/${BUNDLE_EXECUTABLE_NAME}"
chmod +x "${MACOS_DIR}/${BUNDLE_EXECUTABLE_NAME}"
cp "Resources/${APP_ICON}" "${RESOURCES_DIR}/${APP_ICON}"

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
    <string>1</string>
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
</dict>
</plist>
PLIST

printf "APPL????" > "${CONTENTS_DIR}/PkgInfo"

if command -v codesign >/dev/null 2>&1; then
    codesign --force --sign - "$APP_DIR" >/dev/null
fi

echo "Built ${APP_DIR}"
echo
echo "Install it with:"
echo "  cp -R '${APP_DIR}' /Applications/"
