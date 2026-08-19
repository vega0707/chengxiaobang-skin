#!/bin/bash
# 程小帮皮肤守护进程：不修改官方 .app 内的已签名主程序。
# 发现程小帮以普通方式启动后，改用 --remote-debugging-port 重新拉起并注入皮肤。
set -u

OFF="${HOME}/.chengxiaobang/cxb-skin-off"
APP="${CXB_APP:-/Applications/程小帮.app}"
BIN="${APP}/Contents/MacOS/程小帮"
PORT="${CXB_GF_PORT:-9229}"
SKIN_JS="${CXB_SKIN_JS:-${HOME}/.chengxiaobang/plugins/chengxiaobang-skin/cxbskin.mjs}"
LOG="${CXB_SKIN_LOG:-/tmp/cxb-skin-auto.log}"
NODE_BIN="${CXB_NODE_BIN:-}"
LOCK="/tmp/cxb-autoskin.daemon.lock"

if [ -z "${NODE_BIN}" ]; then
  if [ -x /opt/homebrew/bin/node ]; then
    NODE_BIN=/opt/homebrew/bin/node
  elif [ -x /usr/local/bin/node ]; then
    NODE_BIN=/usr/local/bin/node
  else
    NODE_BIN="$(command -v node 2>/dev/null || true)"
  fi
fi

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "${LOG}"
}

if ! mkdir "${LOCK}" 2>/dev/null; then
  other="$(cat "${LOCK}/pid" 2>/dev/null || true)"
  if [ -n "${other}" ] && kill -0 "${other}" 2>/dev/null; then
    exit 0
  fi
  rm -rf "${LOCK}"
  mkdir "${LOCK}" 2>/dev/null || exit 0
fi
echo "$$" > "${LOCK}/pid"
trap 'rm -rf "${LOCK}"' EXIT

main_pid() {
  pgrep -f "^${BIN}( |$)" | head -1
}

cdp_up() {
  curl -sf -o /dev/null --max-time 0.4 "http://127.0.0.1:${PORT}/json/version"
}

has_debug_flag() {
  local pid="$1"
  ps -p "${pid}" -o args= 2>/dev/null | grep -q "remote-debugging-port=${PORT}"
}

quit_app() {
  osascript -e 'tell application "程小帮" to quit' >/dev/null 2>&1 || true
  local i pid
  for i in 1 2 3 4 5 6 7 8; do
    pid="$(main_pid)"
    [ -z "${pid}" ] && return 0
    sleep 0.4
  done
  pid="$(main_pid)"
  if [ -n "${pid}" ]; then
    kill "${pid}" 2>/dev/null || true
    sleep 0.8
  fi
}

injected_pid=""
last_relaunch=0
fail_streak=0

log "守护进程已启动 pid=$$"

while true; do
  if [ -f "${OFF}" ]; then
    injected_pid=""
    sleep 3
    continue
  fi
  if [ ! -x "${BIN}" ] || [ ! -f "${SKIN_JS}" ] || [ -z "${NODE_BIN}" ]; then
    sleep 5
    continue
  fi
  if head -n 2 "${BIN}" 2>/dev/null | grep -q "cxbskin-auto-skin-wrapper"; then
    log "检测到会破坏签名的旧包装器，已跳过。请运行 install-auto-skin.sh --remove 后再装本守护进程"
    sleep 15
    continue
  fi

  pid="$(main_pid)"
  if [ -z "${pid}" ]; then
    injected_pid=""
    fail_streak=0
    sleep 2
    continue
  fi

  if cdp_up; then
    fail_streak=0
    if [ "${injected_pid}" != "${pid}" ]; then
      log "CDP 就绪 pid=${pid}，开始注入"
      if "${NODE_BIN}" "${SKIN_JS}" --inject >> "${LOG}" 2>&1; then
        injected_pid="${pid}"
        log "注入成功 pid=${pid}"
      else
        log "注入失败 pid=${pid}，稍后重试"
        sleep 4
      fi
    fi
    sleep 2
    continue
  fi

  if has_debug_flag "${pid}"; then
    sleep 1
    continue
  fi

  now="$(date +%s)"
  if [ $((now - last_relaunch)) -lt 12 ]; then
    sleep 1
    continue
  fi
  if [ "${fail_streak}" -ge 4 ]; then
    log "连续重启失败，暂停 60 秒 pid=${pid}"
    sleep 60
    fail_streak=0
    continue
  fi

  log "普通启动无调试端口 pid=${pid}，改为带 9229 拉起"
  quit_app
  last_relaunch="$(date +%s)"
  fail_streak=$((fail_streak + 1))
  nohup "${BIN}" --remote-debugging-port="${PORT}" >/dev/null 2>&1 &
  disown || true
  log "已用调试端口拉起"
  sleep 2
done
