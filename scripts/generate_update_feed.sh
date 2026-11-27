#!/usr/bin/env bash
set -euo pipefail

VERSION="${SONOS_MACBAR_VERSION:-0.2.4}"
DIST_DIR="${SONOS_MACBAR_DIST_DIR:-dist}"
SCRATCH_DIR="${TMPDIR:-/tmp}/sonos_macbar-swiftpm-build"
TOOLS_DIR="${SCRATCH_DIR}/artifacts/sparkle/Sparkle/bin"
DOWNLOAD_PREFIX="${SONOS_MACBAR_UPDATE_DOWNLOAD_PREFIX:-https://github.com/AntoinS/sonos_macbar/releases/download/v${VERSION}/}"

cd "$(dirname "$0")/.."

: "${SONOS_MACBAR_SPARKLE_PRIVATE_KEY:?Set the Sparkle private signing key in the release environment.}"
archive="Sonos-Macbar-${VERSION}.zip"
feed_dir="$(mktemp -d "${TMPDIR:-/tmp}/sonos-macbar-feed.XXXXXX")"
trap 'rm -rf "$feed_dir"' EXIT
cp "${DIST_DIR}/${archive}" "$feed_dir/"
printf '%s\n' "$SONOS_MACBAR_SPARKLE_PRIVATE_KEY" |
    "${TOOLS_DIR}/generate_appcast" --ed-key-file - \
        --download-url-prefix "$DOWNLOAD_PREFIX" --maximum-deltas 0 "$feed_dir"

if [[ "$(xmllint --xpath 'count(/rss/channel/item/enclosure/@*[local-name() = "edSignature"])' "$feed_dir/appcast.xml")" != 1 ]]; then
    echo "The update archive has no EdDSA signature. Check that the signing keys match." >&2
    exit 1
fi
printf '%s\n' "$SONOS_MACBAR_SPARKLE_PRIVATE_KEY" |
    "${TOOLS_DIR}/sign_update" --verify --ed-key-file - "$feed_dir/appcast.xml"

cp "${feed_dir}/appcast.xml" "${DIST_DIR}/appcast.xml"
