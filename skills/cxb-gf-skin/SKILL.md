---
name: cxb-gf-skin
description: 应用、移除或验证程小帮「赛博女友」沉浸式皮肤（CDP 注入，双主题 CSS + 状态视频，零修改应用本体）。用户提到女友皮肤、赛博女友、注入皮肤、换皮肤、恢复原生界面、皮肤截图时使用。皮肤脚本与资产都打包在本插件内，用 ${CLAUDE_PLUGIN_ROOT} 定位，不要到别处找。
---

# 程小帮赛博女友皮肤

通过 Chromium DevTools Protocol 往程小帮（Electron）渲染进程注入皮肤 CSS + 角色视频，不改动 app.asar 与签名。

## 前提

- Node.js（运行注入器）
- 程小帮桌面端已安装（默认路径 `/Applications/程小帮.app`）
- 注入器脚本：`${CLAUDE_PLUGIN_ROOT}/cxbskin.mjs`，资产在同目录 `assets/` 下，脚本用自身相对路径解析，无需额外配置

## 应用皮肤（推荐流程）

程小帮必须**以调试端口启动**才能注入。若用户当前正常打开着程小帮（无调试端口），先完全退出再走启动流程：

```bash
# 1. 退出当前程小帮（macOS；其他平台手动退出）
osascript -e 'tell application "程小帮" to quit' 2>/dev/null || true
pkill -f "/Applications/程小帮.app/Contents/MacOS/程小帮" 2>/dev/null || true
sleep 2

# 2. 以调试端口 9229 启动并注入皮肤（一步到位）
node "${CLAUDE_PLUGIN_ROOT}/cxbskin.mjs" --launch --inject
```

若程小帮已在调试模式运行（端口 9229 有 CDP 服务），直接注入：

```bash
node "${CLAUDE_PLUGIN_ROOT}/cxbskin.mjs" --inject
```

注入器是幂等的（重复注入返回 already，不会重复叠加）。

## 恢复原生界面

```bash
node "${CLAUDE_PLUGIN_ROOT}/cxbskin.mjs" --remove
```

## 截图验证

```bash
node "${CLAUDE_PLUGIN_ROOT}/cxbskin.mjs" --shot /tmp/cxb-skin-shot.png
```

## 注意事项

- **首次使用**：注入后让用户在程小帮里点一下或打个字（浏览器自动播放限制），视频才开始播放。
- 皮肤状态机用 DOM 结构信号推断（停止按钮/spinner/流式输出/输入框），**不要**按聊天内容文字匹配去判断或修改检测逻辑。
- 主题跟随程小帮深浅外观自动切换：深色=赛博，浅色=暖白。
- 想换视频：替换 `${CLAUDE_PLUGIN_ROOT}/assets/themes/cyber/states/*.webm`（或改 `cxbskin.mjs` 的 `CYBER_STATES` / `WARM_REUSE` 映射）。
- 注入失败时先确认程小帮确实以 `--remote-debugging-port=9229` 启动（`curl http://127.0.0.1:9229/json/version` 有响应），不要反复硬试。
