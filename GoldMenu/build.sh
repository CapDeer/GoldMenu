#!/bin/zsh
set -e

cd "$(dirname "$0")"
APP="GoldMenu.app"

echo "==> 清理旧版本"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"

echo "==> 编译 Swift 源码"
swiftc -O \
  -target arm64-apple-macosx13.0 \
  -framework SwiftUI \
  -framework AppKit \
  -framework Foundation \
  GoldMenuApp.swift GoldService.swift \
  -o "$APP/Contents/MacOS/GoldMenu"

echo "==> 安装 Info.plist"
cp Info.plist "$APP/Contents/Info.plist"

echo "==> 完成: $(pwd)/$APP"
echo "    双击即可运行，菜单栏出现 Au 金价图标"
