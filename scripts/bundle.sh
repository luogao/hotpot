#!/usr/bin/env bash
# 打包成可双击运行的 .app（ad-hoc 签名，不需要开发者账号）
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG="${1:-release}"
APP="build/HotPot.app"

swift build -c "$CONFIG"
BIN=".build/$CONFIG/HotPot"
[ -f "$BIN" ] || { echo "构建产物不存在: $BIN"; exit 1; }

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp "$BIN" "$APP/Contents/MacOS/HotPot"
cp Resources/Info.plist "$APP/Contents/Info.plist"
if [ -f Resources/AppIcon.icns ]; then
  cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
fi
# 品牌图标（lobehub/icons 预渲染的 PNG）
if [ -d Resources/Icons ]; then
  cp -R Resources/Icons "$APP/Contents/Resources/Icons"
fi

codesign --force --sign - --timestamp=none "$APP" >/dev/null 2>&1 || true

echo "✓ $APP"
echo "  安装: cp -R \"$APP\" /Applications/ && open /Applications/HotPot.app"
