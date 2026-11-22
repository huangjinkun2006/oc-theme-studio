#!/bin/bash
# Build the drag-to-install DMG for the native Swift / AppKit app.
#
#   bash SwiftApp/dmg/make_dmg.sh
#
# Produces "OC Theme Studio.dmg" in the project root. Everything else lives
# under .cache/dmg and can be deleted safely.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
CACHE="$ROOT/.cache/dmg"
PYLIB="$CACHE/pylib"
STAGE="$CACHE/stage"
OUT="$ROOT/OC Theme Studio.dmg"
APP="$ROOT/OC Theme Studio (Swift).app"
export OCTHEME_ROOT="$ROOT"

mkdir -p "$CACHE" "$CACHE/tmp"
# TMPDIR is set only for the dmgbuild/hdiutil step below; exporting it for the
# whole script made swiftc crash sporadically on this machine.

echo "==> 1/5 检查原生 .app"
if [ ! -x "$APP/Contents/MacOS/OCThemeStudioSwift" ]; then
    bash "$ROOT/SwiftApp/build.sh"
fi
# Guard against a corrupted bundle Info.plist (Swift IR fragments once landed
# here and made the built app fail to launch with "damaged or incomplete").
# Always refresh it from the pristine source and lint before packaging.
cp "$HERE/../Info.plist" "$APP/Contents/Info.plist"
/usr/bin/plutil -lint "$APP/Contents/Info.plist"
/usr/bin/codesign --force --deep --sign - "$APP" 2>/dev/null || true

echo "==> 2/5 生成带箭头的安装背景"
/usr/bin/swiftc "$HERE/make_background.swift" -o "$CACHE/make_bg"
"$CACHE/make_bg" "$HERE/background.png"

echo "==> 3/5 准备卷内容（复制、改名、重新签名）"
/usr/bin/python3 -B - "$APP" "$STAGE" <<'PY'
import os, shutil, sys
src, stage = sys.argv[1], sys.argv[2]
shutil.rmtree(stage, ignore_errors=True)
os.makedirs(stage, exist_ok=True)
dst = os.path.join(stage, "OC Theme Studio.app")
shutil.copytree(src, dst, symlinks=True)
print("staged:", dst)
PY
/usr/bin/codesign --force --deep --sign - "$STAGE/OC Theme Studio.app"

echo "==> 4/5 准备 DMG 构建依赖（仅写入本地缓存）"
if [ ! -d "$PYLIB/dmgbuild" ]; then
    /usr/bin/python3 -m pip install --no-cache-dir --disable-pip-version-check \
        --target "$PYLIB" ds_store mac_alias dmgbuild >/dev/null
fi

echo "==> 5/5 写出 DMG"
/usr/bin/python3 -B - "$OUT" <<'PY'
import os, sys
p = sys.argv[1]
if os.path.exists(p):
    os.remove(p)
PY
# A volume with the same name would collide with hdiutil attach.
/usr/bin/hdiutil detach "/Volumes/OC Theme Studio" -force >/dev/null 2>&1 || true
TMPDIR="$CACHE/tmp" PYTHONPATH="$PYLIB" /usr/bin/python3 -B -m dmgbuild \
    -s "$HERE/settings.py" "OC Theme Studio" "$OUT"

echo "==> 校验"
/usr/bin/hdiutil imageinfo "$OUT" | /usr/bin/grep -E "Format:|Checksum Type:|Class Name:|Total Bytes:" || true
/bin/ls -lh "$OUT"
echo "==> 完成：$OUT"
