#!/bin/bash
# install-auto-skin.sh — 程小帮「赛博女友皮肤」一键安装/还原
#
# 功能：
#   1. 启动 wrapper：自动开调试端口 + 延迟注入皮肤
#   2. 应用图标：替换 Dock/启动台图标为项目 icon
#   3. 悬浮窗图标：替换 asar 内的悬浮球头像
#
# 用法：
#   ./install-auto-skin.sh              安装全部（wrapper + 图标）
#   ./install-auto-skin.sh --remove     还原全部
#   ./install-auto-skin.sh --no-icons   只装 wrapper，不替换图标
#
# 注意：
#   - 程小帮应用升级后 wrapper 和图标会被覆盖，升级后需重新执行本脚本
#   - 临时关闭自动皮肤（保留调试端口）：touch ~/.chengxiaobang/cxb-skin-off
set -euo pipefail
cd "$(dirname "$0")"

APP="${CXB_APP:-/Applications/程小帮.app}"
BIN_DIR="$APP/Contents/MacOS"
RESOURCES="$APP/Contents/Resources"
WRAP="$BIN_DIR/程小帮"
REAL="$BIN_DIR/程小帮.real"
MARKER="# cxbskin-auto-skin-wrapper"
SKIN_JS="${CXB_SKIN_JS:-}"

# 图标相关
ICON_ICNS="$RESOURCES/icon.icns"
ICON_ICNS_BAK="$ICON_ICNS.bak"
ASAR="$RESOURCES/app.asar"
ASAR_BAK="$ASAR.bak"
WORK_DIR="/tmp/cxb-icon-replace"

# 源图标：优先插件安装路径，其次脚本所在目录
SOURCE_PNG="${CXB_ICON_SOURCE:-}"
if [ -z "$SOURCE_PNG" ]; then
  if [ -f "$HOME/.chengxiaobang/plugins/chengxiaobang-skin/.claude-plugin/avatar.png" ]; then
    SOURCE_PNG="$HOME/.chengxiaobang/plugins/chengxiaobang-skin/.claude-plugin/avatar.png"
  else
    SOURCE_PNG="$(cd "$(dirname "$0")" && pwd)/.claude-plugin/avatar.png"
  fi
fi

# 自动探测皮肤注入脚本
if [ -z "$SKIN_JS" ]; then
  if [ -f "$HOME/.chengxiaobang/plugins/chengxiaobang-skin/cxbskin.mjs" ]; then
    SKIN_JS="$HOME/.chengxiaobang/plugins/chengxiaobang-skin/cxbskin.mjs"
  else
    SKIN_JS="$(cd "$(dirname "$0")" && pwd)/cxbskin.mjs"
  fi
fi

LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
NO_ICONS=false

# 解析参数
for arg in "$@"; do
  case "$arg" in
    --remove) REMOVE_MODE=true ;;
    --no-icons) NO_ICONS=true ;;
  esac
done

# 探测 node 绝对路径
NODE_BIN="$(command -v node 2>/dev/null || true)"
if [ -n "$NODE_BIN" ]; then
  NODE_BIN="$(cd "$(dirname "$NODE_BIN")" && pwd)/$(basename "$NODE_BIN")"
fi

refresh_ls() { [ -x "$LSREGISTER" ] && "$LSREGISTER" -f "$APP" >/dev/null 2>&1 || true; }
is_our_wrapper() { [ -f "$1" ] && grep -q "$MARKER" "$1"; }

# ========== 图标替换函数 ==========

make_icns() {
  local src_png="$1"
  local out_icns="$2"
  local iconset_dir
  iconset_dir="$(mktemp -d)/icon.iconset"
  mkdir -p "$iconset_dir"
  
  sips -z 512 512 "$src_png" --out "$iconset_dir/icon_512x512@2x.png" >/dev/null 2>&1
  sips -z 512 512 "$src_png" --out "$iconset_dir/icon_512x512.png" >/dev/null 2>&1
  sips -z 256 256 "$src_png" --out "$iconset_dir/icon_256x256@2x.png" >/dev/null 2>&1
  sips -z 256 256 "$src_png" --out "$iconset_dir/icon_256x256.png" >/dev/null 2>&1
  sips -z 128 128 "$src_png" --out "$iconset_dir/icon_128x128@2x.png" >/dev/null 2>&1
  sips -z 128 128 "$src_png" --out "$iconset_dir/icon_128x128.png" >/dev/null 2>&1
  sips -z 32 32 "$src_png" --out "$iconset_dir/icon_32x32@2x.png" >/dev/null 2>&1
  sips -z 32 32 "$src_png" --out "$iconset_dir/icon_32x32.png" >/dev/null 2>&1
  sips -z 16 16 "$src_png" --out "$iconset_dir/icon_16x16@2x.png" >/dev/null 2>&1
  sips -z 16 16 "$src_png" --out "$iconset_dir/icon_16x16.png" >/dev/null 2>&1
  
  iconutil -c icns "$iconset_dir" -o "$out_icns"
  rm -rf "$(dirname "$iconset_dir")"
}

replace_app_icon() {
  echo "==> 替换应用图标（Dock/启动台）"
  
  if [ -f "$ICON_ICNS_BAK" ]; then
    echo "    备份已存在，跳过"
  else
    [ -f "$ICON_ICNS" ] || { echo "    警告：未找到 $ICON_ICNS，跳过"; return 1; }
    cp "$ICON_ICNS" "$ICON_ICNS_BAK"
    echo "    已备份原图标 -> ${ICON_ICNS_BAK}"
  fi
  
  make_icns "$SOURCE_PNG" "$ICON_ICNS"
  echo "    已替换图标"
  touch "$APP"
}

replace_ball_icon() {
  echo "==> 替换悬浮窗图标"
  
  # 检查 asar 工具
  if ! command -v npx &>/dev/null; then
    echo "    警告：未找到 npx，无法替换悬浮窗图标"
    return 1
  fi
  
  # 查找悬浮窗图标（可能在 asar 外）
  local ball_icon
  ball_icon=$(find "$RESOURCES" -path "*/home-mascot-avatar-ball-*.png" 2>/dev/null | head -1)
  
  if [ -z "$ball_icon" ]; then
    # 图标在 asar 内，需要解包
    echo "    解包 app.asar..."
    rm -rf "$WORK_DIR"
    mkdir -p "$WORK_DIR"
    
    npx asar extract "$ASAR" "$WORK_DIR/asar" 2>/dev/null || {
      echo "    警告：asar 解包失败，跳过悬浮窗图标"
      return 1
    }
    
    ball_icon=$(find "$WORK_DIR/asar" -name "home-mascot-avatar-ball-*.png" 2>/dev/null | head -1)
    [ -n "$ball_icon" ] || { echo "    警告：未找到悬浮窗图标"; return 1; }
    
    # 备份 asar
    if [ ! -f "$ASAR_BAK" ]; then
      cp "$ASAR" "$ASAR_BAK"
      echo "    已备份 app.asar -> ${ASAR_BAK}"
    fi
    
    # 替换图标（生成 96x96）
    sips -z 96 96 "$SOURCE_PNG" --out "$ball_icon" >/dev/null 2>&1
    echo "    已替换悬浮窗图标"
    
    # 重新打包 asar
    echo "    重新打包 app.asar..."
    npx asar pack "$WORK_DIR/asar" "$ASAR" 2>/dev/null
    echo "    已重新打包"
    
    rm -rf "$WORK_DIR"
  else
    # 图标在 asar 外
    if [ ! -f "${ball_icon}.bak" ]; then
      cp "$ball_icon" "${ball_icon}.bak"
    fi
    sips -z 96 96 "$SOURCE_PNG" --out "$ball_icon" >/dev/null 2>&1
    echo "    已替换悬浮窗图标"
  fi
}

remove_icons() {
  echo "==> 还原图标"
  
  if [ -f "$ICON_ICNS_BAK" ]; then
    mv "$ICON_ICNS_BAK" "$ICON_ICNS"
    echo "    已还原应用图标"
  else
    echo "    应用图标备份不存在，跳过"
  fi
  
  if [ -f "$ASAR_BAK" ]; then
    mv "$ASAR_BAK" "$ASAR"
    echo "    已还原 app.asar"
  else
    echo "    app.asar 备份不存在，跳过"
  fi
  
  touch "$APP"
}

# ========== 还原模式 ==========

if [ "${REMOVE_MODE:-false}" = true ]; then
  echo "==> 还原全部"
  
  # 还原 wrapper
  if [ -f "$REAL" ]; then
    rm -f "$WRAP"
    mv "$REAL" "$WRAP"
    echo "    已删除包装器，恢复原二进制"
  else
    echo "    未找到备份 $REAL，跳过"
  fi
  
  # 还原图标
  remove_icons
  
  refresh_ls
  echo "完成。已还原全部。"
  exit 0
fi

# ========== 安装模式 ==========

echo "==> 1/4 检查程小帮应用"
[ -f "$APP/Contents/Resources/app.asar" ] || { echo "错误：未找到 $APP"; exit 1; }
echo "    应用: $APP"
[ -f "$SOURCE_PNG" ] || { echo "错误：未找到源图标 $SOURCE_PNG"; exit 1; }
echo "    源图标: $SOURCE_PNG"

echo "==> 2/4 备份原二进制并写入包装器"
if [ -f "$REAL" ]; then
  echo "    备份已存在: ${REAL}，跳过备份"
  is_our_wrapper "$WRAP" || echo "    警告: ${WRAP} 不是本脚本生成的包装器，将被覆盖"
else
  [ -f "$WRAP" ] || { echo "错误：未找到可执行文件 $WRAP"; exit 1; }
  mv "$WRAP" "$REAL"
  echo "    已备份原二进制 -> $REAL"
fi

cat > "$WRAP" <<'EOF'
#!/bin/bash
# cxbskin-auto-skin-wrapper
# 程小帮启动包装器：自动附加 Chromium 远程调试端口，并延迟自动注入赛博女友皮肤
# 还原：在仓库目录执行 ./install-auto-skin.sh --remove
# 临时关闭自动皮肤（保留调试端口）：touch ~/.chengxiaobang/cxb-skin-off
DIR="$(cd "$(dirname "$0")" && pwd)"
PORT="${CXB_GF_PORT:-9229}"
NODE_BIN="__NODE_BIN__"
SKIN_JS="__SKIN_JS__"
if [ -n "$NODE_BIN" ] && [ -f "$SKIN_JS" ] && [ ! -f "$HOME/.chengxiaobang/cxb-skin-off" ]; then
  nohup bash -c "sleep 6; '$NODE_BIN' '$SKIN_JS' --inject" >> /tmp/cxb-skin-auto.log 2>&1 &
fi
exec "$DIR/程小帮.real" --remote-debugging-port="$PORT" "$@"
EOF
sed -i '' "s|__NODE_BIN__|$NODE_BIN|" "$WRAP"
sed -i '' "s|__SKIN_JS__|$SKIN_JS|" "$WRAP"
chmod +x "$WRAP"
chown "$(stat -f '%u:%g' "$REAL")" "$WRAP"
echo "    包装器已写入: ${WRAP}"

if [ "$NO_ICONS" = true ]; then
  echo "==> 3/4 跳过图标替换（--no-icons）"
else
  echo "==> 3/4 替换图标"
  replace_app_icon || echo "    警告：应用图标替换失败"
  replace_ball_icon || echo "    警告：悬浮窗图标替换失败"
fi

echo "==> 4/4 刷新 LaunchServices"
refresh_ls

echo "完成。重启程小帮后生效："
echo "  - 自动开调试端口并注入皮肤"
echo "  - Dock/启动台显示项目图标"
echo "  - 悬浮窗显示项目头像"
echo ""
echo "临时关闭自动皮肤: touch ~/.chengxiaobang/cxb-skin-off"
echo "一键还原: $(cd "$(dirname "$0")" && pwd)/install-auto-skin.sh --remove"
