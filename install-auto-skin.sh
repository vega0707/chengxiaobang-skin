#!/bin/bash
# install-auto-skin.sh — 程小帮「赛博女友皮肤」一键安装/还原
#
# 功能：
#   1. LaunchAgent 守护进程：发现普通启动后，用官方二进制加 --remote-debugging-port=9229 拉起并注入皮肤
#      （不再替换 Contents/MacOS/程小帮，避免 AMFI 因签名无效 SIGKILL）
#   2. 应用图标：替换 Dock/启动台图标为项目 icon
#   3. 悬浮窗图标：替换 asar 内的悬浮球头像
#
# 用法：
#   ./install-auto-skin.sh              安装全部（守护进程 + 图标）
#   ./install-auto-skin.sh --remove     卸载守护进程并还原图标/旧包装器
#   ./install-auto-skin.sh --no-icons   只装守护进程，不替换图标
#
# 临时关闭自动皮肤：touch ~/.chengxiaobang/cxb-skin-off
set -euo pipefail
cd "$(dirname "$0")"

APP="${CXB_APP:-/Applications/程小帮.app}"
BIN_DIR="${APP}/Contents/MacOS"
RESOURCES="${APP}/Contents/Resources"
WRAP="${BIN_DIR}/程小帮"
REAL="${BIN_DIR}/程小帮.real"
MARKER="# cxbskin-auto-skin-wrapper"
DAEMON="$(pwd)/auto-skin-daemon.sh"
SKIN_JS_FILE="$(pwd)/cxbskin.mjs"
LABEL="com.chengxiaobang.autoskin"
PLIST="${HOME}/Library/LaunchAgents/${LABEL}.plist"
UID_NUM="$(id -u)"
DOMAIN="gui/${UID_NUM}"

ICON_ICNS="${RESOURCES}/icon.icns"
ICON_ICNS_BAK="${ICON_ICNS}.bak"
ASAR="${RESOURCES}/app.asar"
ASAR_BAK="${ASAR}.bak"
WORK_DIR="/tmp/cxb-icon-replace"

SOURCE_PNG="${CXB_ICON_SOURCE:-}"
if [ -z "${SOURCE_PNG}" ]; then
  if [ -f "${HOME}/.chengxiaobang/plugins/chengxiaobang-skin/.claude-plugin/avatar.png" ]; then
    SOURCE_PNG="${HOME}/.chengxiaobang/plugins/chengxiaobang-skin/.claude-plugin/avatar.png"
  else
    SOURCE_PNG="$(pwd)/.claude-plugin/avatar.png"
  fi
fi

LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
NO_ICONS=false
REMOVE_MODE=false

for arg in "$@"; do
  case "$arg" in
    --remove) REMOVE_MODE=true ;;
    --no-icons) NO_ICONS=true ;;
  esac
done

NODE_BIN="$(command -v node 2>/dev/null || true)"
if [ -n "${NODE_BIN}" ]; then
  NODE_BIN="$(cd "$(dirname "${NODE_BIN}")" && pwd)/$(basename "${NODE_BIN}")"
elif [ -x /opt/homebrew/bin/node ]; then
  NODE_BIN=/opt/homebrew/bin/node
fi

refresh_ls() { [ -x "${LSREGISTER}" ] && "${LSREGISTER}" -f "${APP}" >/dev/null 2>&1 || true; }
is_our_wrapper() { [ -f "$1" ] && grep -q "${MARKER}" "$1"; }

unload_agent() {
  launchctl bootout "${DOMAIN}/${LABEL}" >/dev/null 2>&1 || true
  launchctl bootout "${DOMAIN}" "${PLIST}" >/dev/null 2>&1 || true
  launchctl unload "${PLIST}" >/dev/null 2>&1 || true
}

restore_legacy_wrapper() {
  if [ -f "${REAL}" ]; then
    echo "==> 还原遗留的签名包装器（旧方案会破坏代码签名）"
    rm -f "${WRAP}"
    mv "${REAL}" "${WRAP}"
    chmod +x "${WRAP}"
    echo "    已恢复官方主程序: ${WRAP}"
  elif is_our_wrapper "${WRAP}"; then
    echo "错误：发现包装器但没有 ${REAL} 备份，请重新安装程小帮。"
    exit 1
  fi
}

make_icns() {
  local src_png="$1"
  local out_icns="$2"
  local iconset_dir
  iconset_dir="$(mktemp -d)/icon.iconset"
  mkdir -p "${iconset_dir}"

  sips -z 512 512 "${src_png}" --out "${iconset_dir}/icon_512x512@2x.png" >/dev/null 2>&1
  sips -z 512 512 "${src_png}" --out "${iconset_dir}/icon_512x512.png" >/dev/null 2>&1
  sips -z 256 256 "${src_png}" --out "${iconset_dir}/icon_256x256@2x.png" >/dev/null 2>&1
  sips -z 256 256 "${src_png}" --out "${iconset_dir}/icon_256x256.png" >/dev/null 2>&1
  sips -z 128 128 "${src_png}" --out "${iconset_dir}/icon_128x128@2x.png" >/dev/null 2>&1
  sips -z 128 128 "${src_png}" --out "${iconset_dir}/icon_128x128.png" >/dev/null 2>&1
  sips -z 32 32 "${src_png}" --out "${iconset_dir}/icon_32x32@2x.png" >/dev/null 2>&1
  sips -z 32 32 "${src_png}" --out "${iconset_dir}/icon_32x32.png" >/dev/null 2>&1
  sips -z 16 16 "${src_png}" --out "${iconset_dir}/icon_16x16@2x.png" >/dev/null 2>&1
  sips -z 16 16 "${src_png}" --out "${iconset_dir}/icon_16x16.png" >/dev/null 2>&1

  iconutil -c icns "${iconset_dir}" -o "${out_icns}"
  rm -rf "$(dirname "${iconset_dir}")"
}

replace_app_icon() {
  echo "==> 替换应用图标（Dock/启动台）"
  if [ -f "${ICON_ICNS_BAK}" ]; then
    echo "    备份已存在，跳过备份"
  else
    [ -f "${ICON_ICNS}" ] || { echo "    警告：未找到 ${ICON_ICNS}，跳过"; return 1; }
    cp "${ICON_ICNS}" "${ICON_ICNS_BAK}"
    echo "    已备份原图标 -> ${ICON_ICNS_BAK}"
  fi
  make_icns "${SOURCE_PNG}" "${ICON_ICNS}"
  echo "    已替换图标"
  touch "${APP}"
}

replace_ball_icon() {
  echo "==> 替换悬浮窗图标"
  if ! command -v npx &>/dev/null; then
    echo "    警告：未找到 npx，无法替换悬浮窗图标"
    return 1
  fi

  local ball_icon
  ball_icon=$(find "${RESOURCES}" -path "*/home-mascot-avatar-ball-*.png" 2>/dev/null | head -1)

  if [ -z "${ball_icon}" ]; then
    echo "    解包 app.asar..."
    rm -rf "${WORK_DIR}"
    mkdir -p "${WORK_DIR}"
    npx asar extract "${ASAR}" "${WORK_DIR}/asar" 2>/dev/null || {
      echo "    警告：asar 解包失败，跳过悬浮窗图标"
      return 1
    }
    ball_icon=$(find "${WORK_DIR}/asar" -name "home-mascot-avatar-ball-*.png" 2>/dev/null | head -1)
    [ -n "${ball_icon}" ] || { echo "    警告：未找到悬浮窗图标"; return 1; }
    if [ ! -f "${ASAR_BAK}" ]; then
      cp "${ASAR}" "${ASAR_BAK}"
      echo "    已备份 app.asar -> ${ASAR_BAK}"
    fi
    sips -z 96 96 "${SOURCE_PNG}" --out "${ball_icon}" >/dev/null 2>&1
    echo "    已替换悬浮窗图标"
    echo "    重新打包 app.asar..."
    npx asar pack "${WORK_DIR}/asar" "${ASAR}" 2>/dev/null
    echo "    已重新打包"
    rm -rf "${WORK_DIR}"
  else
    if [ ! -f "${ball_icon}.bak" ]; then
      cp "${ball_icon}" "${ball_icon}.bak"
    fi
    sips -z 96 96 "${SOURCE_PNG}" --out "${ball_icon}" >/dev/null 2>&1
    echo "    已替换悬浮窗图标"
  fi
}

remove_icons() {
  echo "==> 还原图标"
  if [ -f "${ICON_ICNS_BAK}" ]; then
    mv "${ICON_ICNS_BAK}" "${ICON_ICNS}"
    echo "    已还原应用图标"
  else
    echo "    应用图标备份不存在，跳过"
  fi
  if [ -f "${ASAR_BAK}" ]; then
    mv "${ASAR_BAK}" "${ASAR}"
    echo "    已还原 app.asar"
  else
    echo "    app.asar 备份不存在，跳过"
  fi
  touch "${APP}"
}

install_agent() {
  [ -x "${DAEMON}" ] || chmod +x "${DAEMON}"
  [ -n "${NODE_BIN}" ] || { echo "错误：未找到 node"; exit 1; }
  mkdir -p "${HOME}/Library/LaunchAgents"
  cat > "${PLIST}" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>${LABEL}</string>
  <key>ProgramArguments</key>
  <array>
    <string>/bin/bash</string>
    <string>${DAEMON}</string>
  </array>
  <key>EnvironmentVariables</key>
  <dict>
    <key>CXB_APP</key>
    <string>${APP}</string>
    <key>CXB_SKIN_JS</key>
    <string>${SKIN_JS_FILE}</string>
    <key>CXB_NODE_BIN</key>
    <string>${NODE_BIN}</string>
    <key>PATH</key>
    <string>/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin</string>
  </dict>
  <key>RunAtLoad</key>
  <true/>
  <key>KeepAlive</key>
  <true/>
  <key>Nice</key>
  <integer>5</integer>
  <key>StandardOutPath</key>
  <string>/tmp/cxb-skin-auto.log</string>
  <key>StandardErrorPath</key>
  <string>/tmp/cxb-skin-auto.log</string>
</dict>
</plist>
EOF
  unload_agent
  if ! launchctl bootstrap "${DOMAIN}" "${PLIST}"; then
    launchctl load "${PLIST}"
  fi
}

if [ "${REMOVE_MODE}" = true ]; then
  echo "==> 卸载自动皮肤守护进程"
  unload_agent
  rm -f "${PLIST}"
  restore_legacy_wrapper
  remove_icons
  refresh_ls
  echo "完成。已卸载守护进程并还原遗留包装器/图标。"
  exit 0
fi

echo "==> 1/4 检查程小帮应用"
[ -f "${APP}/Contents/Resources/app.asar" ] || { echo "错误：未找到 ${APP}"; exit 1; }
[ -f "${SKIN_JS_FILE}" ] || { echo "错误：未找到 ${SKIN_JS_FILE}"; exit 1; }
echo "    应用: ${APP}"
echo "    守护进程: ${DAEMON}"
echo "    node: ${NODE_BIN:-未找到}"

echo "==> 2/4 还原旧包装器并安装 LaunchAgent"
restore_legacy_wrapper || true
if is_our_wrapper "${WRAP}"; then
  echo "错误：主程序仍是包装脚本，拒绝安装。请先修复 ${WRAP}"
  exit 1
fi
install_agent
echo "    已加载: ${DOMAIN}/${LABEL}"

if [ "${NO_ICONS}" = true ]; then
  echo "==> 3/4 跳过图标替换（--no-icons）"
else
  echo "==> 3/4 替换图标"
  [ -f "${SOURCE_PNG}" ] || { echo "错误：未找到源图标 ${SOURCE_PNG}"; exit 1; }
  echo "    源图标: ${SOURCE_PNG}"
  replace_app_icon || echo "    警告：应用图标替换失败"
  replace_ball_icon || echo "    警告：悬浮窗图标替换失败"
fi

echo "==> 4/4 刷新 LaunchServices"
refresh_ls

echo "完成。从 Dock / 访达启动程小帮会自动带调试端口并注入皮肤。"
echo "首次普通启动会快速重启一次（约 1–2 秒）以附上调试端口。"
echo "临时关闭: touch ~/.chengxiaobang/cxb-skin-off"
echo "卸载: $(pwd)/install-auto-skin.sh --remove"
