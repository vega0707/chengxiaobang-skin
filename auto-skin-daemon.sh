#!/bin/bash
# 程小帮皮肤守护进程：不修改官方 .app 内的已签名主程序。
# 发现程小帮以普通方式启动后，改用 --remote-debugging-port 重新拉起并注入皮肤。
#
# 拉起必须走 LaunchServices（open -b），不能 nohup/直接 exec 二进制：
# 否则责任进程会变成 bash/launchd 脚本，屏幕录制等 TCC 权限无法正确授予应用本身。
set -u

OFF="${HOME}/.chengxiaobang/cxb-skin-off"
APP="${CXB_APP:-/Applications/程小帮.app}"
BIN="${APP}/Contents/MacOS/程小帮"
BUNDLE_ID="${CXB_BUNDLE_ID:-com.chengxiaobang.desktop}"
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

# LaunchServices 拉起的 app 父进程为 launchd(pid 1)；nohup/spawn 则会挂在 shell 下。
is_system_responsible() {
  local pid="$1" ppid
  ppid="$(ps -p "${pid}" -o ppid= 2>/dev/null | tr -d '[:space:]')"
  [ "${ppid}" = "1" ]
}

quit_app() {
  osascript -e 'tell application "程小帮" to quit' >/dev/null 2>&1 || true
  local i pid
  for i in 1 2 3 4 5 6 7 8 9 10; do
    pid="$(main_pid)"
    [ -z "${pid}" ] && break
    sleep 0.4
  done
  pid="$(main_pid)"
  if [ -n "${pid}" ]; then
    kill "${pid}" 2>/dev/null || true
    sleep 0.8
  fi
  # 等旧实例彻底退出，避免 open 复用到无调试端口的残留进程
  for i in 1 2 3 4 5; do
    [ -z "$(main_pid)" ] && ! cdp_up && return 0
    sleep 0.4
  done
}

# 经 LaunchServices 拉起，保证责任进程是程小帮本身（录屏权限可用）
launch_with_debug_port() {
  open -b "${BUNDLE_ID}" --args --remote-debugging-port="${PORT}" >> "${LOG}" 2>&1
}

relaunch_for_debug() {
  local reason="$1"
  local now
  now="$(date +%s)"
  if [ $((now - last_relaunch)) -lt 12 ]; then
    return 1
  fi
  if [ "${fail_streak}" -ge 4 ]; then
    log "连续重启失败，暂停 60 秒（${reason}）"
    sleep 60
    fail_streak=0
    return 1
  fi

  log "需要带调试端口且责任进程正确的实例（${reason}）pid=${pid:-?}，准备重拉"
  quit_app
  last_relaunch="$(date +%s)"
  fail_streak=$((fail_streak + 1))
  if launch_with_debug_port; then
    log "已用 open -b ${BUNDLE_ID} 拉起（remote-debugging-port=${PORT}）"
  else
    log "open 拉起失败"
  fi
  sleep 2
  return 0
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

  # 先纠正责任进程：即使已有 CDP，挂在 shell 下也会导致录屏权限失效
  if ! is_system_responsible "${pid}"; then
    relaunch_for_debug "责任进程非 launchd(ppid!=1)" || sleep 1
    continue
  fi

  if cdp_up; then
    fail_streak=0
    if [ "${injected_pid}" != "${pid}" ]; then
      log "CDP 就绪且责任进程正确 pid=${pid}，开始注入"
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
    # 已带调试端口、责任进程正确，等 CDP 起来
    sleep 1
    continue
  fi

  relaunch_for_debug "普通启动无调试端口" || sleep 1
done
