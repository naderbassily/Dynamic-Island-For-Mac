#!/bin/bash
# Builds "Dynamic Island.app".
#   ./build.sh            build only          → build/Dynamic Island.app
#   ./build.sh --install  build, copy to /Applications and launch
#   ./build.sh --zip      universal build (Apple silicon + Intel), zipped → build/DynamicIsland.zip
#   ./build.sh --share    universal build + zip + disk image → "Dynamic Island.dmg" (to share or upload)
set -euo pipefail
cd "$(dirname "$0")"

MODE="${1:-}"
ARCH_FLAGS=()
if [[ "$MODE" == "--zip" || "$MODE" == "--share" ]]; then
  ARCH_FLAGS=(--arch arm64 --arch x86_64)   # runs on every Mac
fi

echo "==> Compiling (release)…"
swift build -c release ${ARCH_FLAGS[@]+"${ARCH_FLAGS[@]}"}

BIN="$(swift build -c release ${ARCH_FLAGS[@]+"${ARCH_FLAGS[@]}"} --show-bin-path)/DynamicIsland"
APP="build/Dynamic Island.app"

echo "==> Assembling app bundle…"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/DynamicIsland"
cp Resources/Info.plist "$APP/Contents/Info.plist"

# App icon (Resources/AppIcon.png → AppIcon.icns)
if [[ -f Resources/AppIcon.png ]] && command -v iconutil >/dev/null; then
  ICONSET="build/AppIcon.iconset"
  rm -rf "$ICONSET"; mkdir -p "$ICONSET"
  for s in 16 32 128 256 512; do
    sips -z $s $s Resources/AppIcon.png --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
    sips -z $((s*2)) $((s*2)) Resources/AppIcon.png --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
  done
  iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
  rm -rf "$ICONSET"
fi

echo "==> Signing (ad-hoc)…"
codesign --force --deep --sign - "$APP"
touch "$APP"   # make Finder refresh the icon

echo "Built: $APP"

make_zip() {
  rm -f build/DynamicIsland.zip
  ditto -c -k --sequesterRsrc --keepParent "$APP" build/DynamicIsland.zip
  echo "Zipped: build/DynamicIsland.zip"
}

case "$MODE" in
  --install)
    pkill -x DynamicIsland 2>/dev/null || true
    sleep 0.5
    rm -rf "/Applications/Dynamic Island.app"
    cp -R "$APP" /Applications/
    touch "/Applications/Dynamic Island.app"
    open "/Applications/Dynamic Island.app"
    echo "Installed to /Applications and launched."
    ;;
  --zip)
    make_zip
    ;;
  --share)
    make_zip
    echo "==> Making disk image…"
    STAGE="build/dmg"
    rm -rf "$STAGE"; mkdir -p "$STAGE"
    cp -R "$APP" "$STAGE/"
    ln -s /Applications "$STAGE/Applications"
    rm -f "Dynamic Island.dmg"
    hdiutil create -volname "Dynamic Island" -srcfolder "$STAGE" -ov -format UDZO "Dynamic Island.dmg" >/dev/null
    rm -rf "$STAGE"
    cp build/DynamicIsland.zip "Dynamic Island.zip"
    echo "Ready to share: \"Dynamic Island.dmg\" and \"Dynamic Island.zip\" in $(pwd)"
    ;;
esac
