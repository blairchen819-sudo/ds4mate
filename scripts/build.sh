#!/bin/bash
# DS4Mate 构建脚本
# 用法：./scripts/build.sh

set -e

cd "$(dirname "$0")/.."
PROJECT_DIR="$(pwd)"

echo "=== DS4Mate 构建 ==="
echo "项目目录：$PROJECT_DIR"

# 1. 清理旧的 build 目录
rm -rf build
mkdir -p build/DS4Mate.app/Contents/MacOS
mkdir -p build/DS4Mate.app/Contents/Resources

# 2. 编译主 App
SDK_PATH="$(xcrun --show-sdk-path)"
echo ""
echo "→ 编译主 App（target=arm64-apple-macosx13.0）"
xcrun swiftc \
  -sdk "$SDK_PATH" \
  -target arm64-apple-macosx13.0 \
  -framework SwiftUI -framework AppKit -framework GameController \
  -framework CoreGraphics -framework ApplicationServices -framework Carbon \
  -framework Foundation -framework Combine -framework IOKit -framework IOBluetooth \
  -O \
  -o build/DS4Mate \
  $(find Sources -name "*.swift")

# 3. 编译测试可执行
echo "→ 编译测试可执行"
xcrun swiftc \
  -sdk "$SDK_PATH" \
  -target arm64-apple-macosx13.0 \
  -framework SwiftUI -framework AppKit -framework GameController \
  -framework CoreGraphics -framework ApplicationServices -framework Carbon \
  -framework Foundation -framework Combine \
  -parse-as-library \
  -O \
  -o build/DS4MateTests \
  Sources/DS4Mate/Models/ControllerInput.swift \
  Sources/DS4Mate/Models/Action.swift \
  Sources/DS4Mate/Models/Profile.swift \
  Sources/DS4Mate/Services/BuiltInProfiles.swift \
  Sources/DS4Mate/Services/ProfileStore.swift \
  Tests/RunTests.swift

# 4. 组装 .app bundle
echo "→ 组装 .app bundle"
cp build/DS4Mate build/DS4Mate.app/Contents/MacOS/DS4Mate
cp Sources/DS4Mate/Resources/Info.plist build/DS4Mate.app/Contents/Info.plist
cp Sources/DS4Mate/Resources/default.json build/DS4Mate.app/Contents/Resources/
cp Sources/DS4Mate/Resources/media.json build/DS4Mate.app/Contents/Resources/
cp Sources/DS4Mate/Resources/presentation.json build/DS4Mate.app/Contents/Resources/

# 5. 签名
# 关键：必须用**固定的签名身份**，不能用 ad-hoc（-）。
# ad-hoc 的 designated requirement 是 cdhash，每次重编都变 → TCC 里的
# 「输入监控 / 辅助功能」授权立刻失效，表现为"手柄突然收不到数据"。
# 自签证书的身份认的是 certificate leaf，重建后授权依然有效。
SIGN_ID="DS4Mate Local Signing"
# 证书放在专用钥匙串里。钥匙串密码从环境变量读取，不要硬编码提交到仓库：
#   export DS4_SIGN_KC_PASS="你的钥匙串密码"
# （仅用于本机自签；放登录钥匙串的话每次 codesign 都会弹授权框，无法自动化。）
SIGN_KC="$HOME/Library/Keychains/ds4sign.keychain-db"
SIGN_KC_PASS="${DS4_SIGN_KC_PASS:-}"
if [ -z "$SIGN_KC_PASS" ]; then
  echo "→ 未设置 DS4_SIGN_KC_PASS，尝试登录钥匙串 / ad-hoc"
fi
if [ -n "$SIGN_KC_PASS" ] && [ -f "$SIGN_KC" ] && security find-certificate -c "$SIGN_ID" "$SIGN_KC" >/dev/null 2>&1; then
  security unlock-keychain -p "$SIGN_KC_PASS" "$SIGN_KC" 2>/dev/null
  # 必须进搜索列表，否则 codesign 报 "no identity found"
  security list-keychains -d user -s "$HOME/Library/Keychains/login.keychain-db" "$SIGN_KC" 2>/dev/null
  echo "→ 签名（$SIGN_ID）"
  codesign --force --deep --keychain "$SIGN_KC" --sign "$SIGN_ID" build/DS4Mate.app 2>&1 | sed 's/^/  /'
elif security find-certificate -c "$SIGN_ID" ~/Library/Keychains/login.keychain-db >/dev/null 2>&1; then
  echo "→ 签名（$SIGN_ID，登录钥匙串）"
  codesign --force --deep --sign "$SIGN_ID" build/DS4Mate.app 2>&1 | sed 's/^/  /'
else
  echo "→ 签名（ad-hoc 兜底，注意每次重建都要重新授权）"
  codesign --force --deep --sign - build/DS4Mate.app 2>&1 | sed 's/^/  /'
fi

# 6. 跑测试
echo ""
echo "→ 跑测试"
./build/DS4MateTests 2>&1 | tail -10

# 7. 启动冒烟测试
echo ""
echo "→ 启动冒烟测试（3 秒后退出）"
open build/DS4Mate.app
sleep 3
if pgrep -f "DS4Mate.app/Contents/MacOS" > /dev/null 2>&1; then
  echo "  ✓ App 成功启动"
  PID=$(pgrep -f "DS4Mate.app/Contents/MacOS" | head -1)
  echo "  PID: $PID"
  kill $PID 2>/dev/null
  sleep 1
  pkill -9 -f "DS4Mate.app/Contents/MacOS" 2>/dev/null
  echo "  ✓ 干净退出"
else
  echo "  ⚠ App 启动后立即退出"
fi

echo ""
echo "=== 构建完成 ==="
echo "产物："
echo "  build/DS4Mate            - 独立可执行"
echo "  build/DS4Mate.app        - .app bundle（可双击运行）"
echo "  build/DS4MateTests       - 冒烟测试"
echo ""
echo "启动 App："
echo "  open build/DS4Mate.app"
echo "  或直接：build/DS4Mate.app/Contents/MacOS/DS4Mate"
