---
description: 安装或还原程小帮「默认启动即带皮肤」的 LaunchAgent 守护进程（install-auto-skin.sh）。
argument-hint: "[install | remove | 关闭自动 | 开启自动 | --no-icons]"
skills: cxb-gf-skin
---

处理程小帮自动皮肤守护进程（LaunchAgent，不修改官方主程序签名），脚本在 `${CLAUDE_PLUGIN_ROOT}/install-auto-skin.sh`：

$ARGUMENTS

- **安装**（默认，无参数或 `install`）：运行 `bash "${CLAUDE_PLUGIN_ROOT}/install-auto-skin.sh"`
  - 安装用户级 LaunchAgent，发现程小帮普通启动后改用 `--remote-debugging-port=9229` 拉起并注入皮肤
  - 默认同时替换 Dock/悬浮窗图标；只要守护进程、不要改图标时加 `--no-icons`
  - **禁止**再替换 `/Applications/程小帮.app/Contents/MacOS/程小帮`，那会破坏代码签名导致启动被 AMFI 杀掉
- **卸载**（`remove`）：运行 `bash "${CLAUDE_PLUGIN_ROOT}/install-auto-skin.sh" --remove`
- **临时关闭自动皮肤**：`touch ~/.chengxiaobang/cxb-skin-off`；`开启自动` 则删除该文件
- 装完可提示用户从 Dock 启动验证：9229 端口可访问、皮肤自动出现；日志在 `/tmp/cxb-skin-auto.log`
