#!/usr/bin/env bash
set -euo pipefail

APP_NAME="Sonos Macbar"
VERSION="${SONOS_MACBAR_VERSION:-0.2.2}"
DIST_DIR="${SONOS_MACBAR_DIST_DIR:-dist}"
ARCHIVE_NAME="Sonos-Macbar-${VERSION}.zip"
ARCHIVE_PATH="${DIST_DIR}/${ARCHIVE_NAME}"

cd "$(dirname "$0")/.."

bash scripts/build_app.sh

rm -f "$ARCHIVE_PATH"
ditto -c -k --keepParent "${DIST_DIR}/${APP_NAME}.app" "$ARCHIVE_PATH"

echo "Packaged ${ARCHIVE_PATH}"
echo
echo "SHA256:"
shasum -a 256 "$ARCHIVE_PATH" | awk '{ print $1 }'
echo
echo "Upload this file to:"
echo "  https://github.com/AntoinS/sonos_macbar/releases/tag/v${VERSION}"
