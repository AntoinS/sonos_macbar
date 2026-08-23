#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

SOURCE_ICON="Resources/AppIcon/Icon Exports/Icon-iOS-Default-1024x1024@1x.png"
ICONSET_DIR="${TMPDIR:-/tmp}/sonos_macbar-appicon.iconset"
OUTPUT_ICON="Resources/AppIcon.icns"

if [[ ! -f "$SOURCE_ICON" ]]; then
    echo "Missing $SOURCE_ICON" >&2
    exit 1
fi

rm -rf "$ICONSET_DIR"
mkdir -p "$ICONSET_DIR"
trap 'rm -rf "$ICONSET_DIR"' EXIT

sips -z 16 16 "$SOURCE_ICON" --out "$ICONSET_DIR/icon_16x16.png" >/dev/null
sips -z 32 32 "$SOURCE_ICON" --out "$ICONSET_DIR/icon_16x16@2x.png" >/dev/null
sips -z 32 32 "$SOURCE_ICON" --out "$ICONSET_DIR/icon_32x32.png" >/dev/null
sips -z 64 64 "$SOURCE_ICON" --out "$ICONSET_DIR/icon_32x32@2x.png" >/dev/null
sips -z 128 128 "$SOURCE_ICON" --out "$ICONSET_DIR/icon_128x128.png" >/dev/null
sips -z 256 256 "$SOURCE_ICON" --out "$ICONSET_DIR/icon_128x128@2x.png" >/dev/null
sips -z 256 256 "$SOURCE_ICON" --out "$ICONSET_DIR/icon_256x256.png" >/dev/null
sips -z 512 512 "$SOURCE_ICON" --out "$ICONSET_DIR/icon_256x256@2x.png" >/dev/null
sips -z 512 512 "$SOURCE_ICON" --out "$ICONSET_DIR/icon_512x512.png" >/dev/null
sips -z 1024 1024 "$SOURCE_ICON" --out "$ICONSET_DIR/icon_512x512@2x.png" >/dev/null

if ! iconutil -c icns "$ICONSET_DIR" -o "$OUTPUT_ICON" 2>/dev/null; then
    python3 - "$ICONSET_DIR" "$OUTPUT_ICON" <<'PY'
import pathlib
import struct
import sys

iconset_dir = pathlib.Path(sys.argv[1])
output_icon = pathlib.Path(sys.argv[2])
entries = [
    ("icp4", "icon_16x16.png"),
    ("icp5", "icon_32x32.png"),
    ("icp6", "icon_32x32@2x.png"),
    ("ic07", "icon_128x128.png"),
    ("ic08", "icon_256x256.png"),
    ("ic09", "icon_512x512.png"),
    ("ic10", "icon_512x512@2x.png"),
]

chunks = []
for icon_type, filename in entries:
    data = (iconset_dir / filename).read_bytes()
    chunks.append(icon_type.encode("ascii") + struct.pack(">I", len(data) + 8) + data)

payload = b"".join(chunks)
output_icon.write_bytes(b"icns" + struct.pack(">I", len(payload) + 8) + payload)
PY
fi

echo "Generated $OUTPUT_ICON"
