#!/bin/bash
# Build the native Swift / AppKit OC Theme Studio app bundle.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
APP="$ROOT/OC Theme Studio (Swift).app"
BUILD="$HERE/.build"

echo "==> 编译 Swift 源码"
mkdir -p "$BUILD"
/usr/bin/swiftc \
  -target x86_64-apple-macosx11.0 \
  -O \
  -o "$BUILD/OCThemeStudioSwift" \
  "$HERE"/Sources/*.swift

echo "==> 组装 .app bundle"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BUILD/OCThemeStudioSwift" "$APP/Contents/MacOS/OCThemeStudioSwift"
chmod +x "$APP/Contents/MacOS/OCThemeStudioSwift"
cp "$HERE/Info.plist" "$APP/Contents/Info.plist"

if [ -f "$ROOT/OC Theme Studio.app/Contents/Resources/app.icns" ]; then
  cp "$ROOT/OC Theme Studio.app/Contents/Resources/app.icns" "$APP/Contents/Resources/app.icns"
fi

# Seed the app with three generated sample themes for a fresh install.
mkdir -p "$APP/Contents/Resources/themes"
for d in "$ROOT"/themes/t_d000000*; do
  [ -d "$d" ] && cp -R "$d" "$APP/Contents/Resources/themes/"
done

# Curated icon pool + preset definitions used by "新建主题" and "识别启动项".
if [ -d "$HERE/Presets" ]; then
  rm -rf "$APP/Contents/Resources/Presets"
  cp -R "$HERE/Presets" "$APP/Contents/Resources/Presets"
fi

# Offline theme-store catalog (demo themes so the store works without a server).
if [ -d "$HERE/Store" ]; then
  rm -rf "$APP/Contents/Resources/Store"
  cp -R "$HERE/Store" "$APP/Contents/Resources/Store"
fi

/usr/bin/plutil -lint "$APP/Contents/Info.plist"

if command -v /usr/bin/codesign >/dev/null 2>&1; then
  /usr/bin/codesign --force --deep --sign - "$APP" 2>/dev/null || true
fi

echo "==> 完成：$APP"
/usr/bin/du -sh "$APP"
