#!/bin/bash
# install-auto-skin.sh — 程小帮「默认启动即带皮肤」一键安装/还原
#
# 原理：把程小帮可执行文件替换成包装脚本，包装脚本启动时自动附加
#   --remote-debugging-port=9229（CDP 注入前提），并在后台延迟自动注入赛博女友皮肤。
#   原二进制备份为同目录 程小帮.real，可随时一键还原。
#
# 用法：
#   ./install-auto-skin.sh           安装包装器（备份原二进制 → 写 wrapper → 刷新 LaunchServices）
#   ./install-auto-skin.sh --remove  还原（删 wrapper → 恢复原二进制）
#
# 注意：
#   - 程小帮应用升级后 wrapper 会被覆盖，升级后需重新执行本脚本。
#   - 临时关闭自动皮肤（保留调试端口）：touch ~/.chengxiaobang/cxb-skin-off
set -euo pipefail
cd "$(dirname "$0")"

APP="${CXB_APP:-/Applications/程小帮.app}"
BIN_DIR="$APP/Contents/MacOS"
WRAP="$BIN_DIR/程小帮"
REAL="$BIN_DIR/程小帮.real"
MARKER="# cxbskin-auto-skin-wrapper"
SKIN_JS="${CXB_SKIN_JS:-}"

# 自动探测皮肤注入脚本：优先插件安装路径，其次脚本所在目录
if [ -z "$SKIN_JS" ]; then
  if [ -f "$HOME/.chengxiaobang/plugins/chengxiaobang-skin/cxbskin.mjs" ]; then
    SKIN_JS="$HOME/.chengxiaobang/plugins/chengxiaobang-skin/cxbskin.mjs"
  else
    SKIN_JS="$(cd "$(dirname "$0")" && pwd)/cxbskin.mjs"
  fi
fi

LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

# 探测 node 绝对路径：GUI 启动（Dock/双击）继承 launchd 的 PATH，不含 node，
# 必须把绝对路径写进 wrapper，否则自动注入会报 command not found。
NODE_BIN="$(command -v node 2>/dev/null || true)"
if [ -n "$NODE_BIN" ]; then
  NODE_BIN="$(cd "$(dirname "$NODE_BIN")" && pwd)/$(basename "$NODE_BIN")"
fi

refresh_ls() { [ -x "$LSREGISTER" ] && "$LSREGISTER" -f "$APP" >/dev/null 2>&1 || true; }

is_our_wrapper() { [ -f "$1" ] && grep -q "$MARKER" "$1"; }

if [ "${1:-}" = "--remove" ]; then
  echo "==> 还原原生启动"
  if [ -f "$REAL" ]; then
    rm -f "$WRAP"
    mv "$REAL" "$WRAP"
    echo "    已删除包装器，恢复原二进制"
  else
    echo "    未找到备份 $REAL，跳过"
  fi
  refresh_ls
  echo "完成。已还原：双击启动不再自动带调试端口。"
  exit 0
fi

echo "==> 1/3 检查程小帮应用"
[ -f "$APP/Contents/Resources/app.asar" ] || { echo "错误：未找到 $APP，请确认应用路径（可用 CXB_APP 指定）"; exit 1; }
echo "    应用: $APP"

echo "==> 2/3 备份原二进制并写入包装器"
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
# 临时关闭自动皮肤（保留端口）：touch ~/.chengxiaobang/cxb-skin-off
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
echo "    包装器已写入: ${WRAP}（注入脚本: ${SKIN_JS}）"
if [ -n "$NODE_BIN" ]; then
  echo "    自动注入运行器: ${NODE_BIN}"
else
  echo "    警告：未找到 node，自动注入将跳过（仅开启调试端口）。请安装 Node.js 后重跑本脚本。"
fi

echo "==> 3/3 刷新 LaunchServices"
refresh_ls
echo "完成。之后双击/Dock 启动程小帮即自动开调试端口并注入皮肤。"
echo "临时关闭自动皮肤: touch ~/.chengxiaobang/cxb-skin-off"
echo "一键还原: $(cd "$(dirname "$0")" && pwd)/install-auto-skin.sh --remove"
