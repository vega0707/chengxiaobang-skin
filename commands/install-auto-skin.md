---
description: 安装或还原程小帮「默认启动即带皮肤」的启动包装器（install-auto-skin.sh）。
argument-hint: "[install | remove | 关闭自动 | 开启自动]"
skills: cxb-gf-skin
---

处理程小帮启动包装器（默认启动即自动开调试端口并注入皮肤），脚本在 `${CLAUDE_PLUGIN_ROOT}/install-auto-skin.sh`：

$ARGUMENTS

- **安装包装器**（默认，无参数或 `install`）：运行 `bash "${CLAUDE_PLUGIN_ROOT}/install-auto-skin.sh"`
  - 会把程小帮可执行文件替换为包装脚本，原二进制备份为同目录 `程小帮.real`；之后无论双击/Dock 启动都自动带调试端口，并在 6 秒后后台自动注入皮肤
  - 涉及修改应用可执行文件（代码签名失效风险，应用升级后需重装），执行前必须向用户说明并取得确认
- **还原原生启动**（`remove`）：运行 `bash "${CLAUDE_PLUGIN_ROOT}/install-auto-skin.sh" --remove`
- **临时关闭自动皮肤**（保留调试端口）：`touch ~/.chengxiaobang/cxb-skin-off`；`开启自动` 则删除该文件
- 装完可提示用户重启程小帮验证：9229 端口可访问、皮肤自动出现；注入日志在 `/tmp/cxb-skin-auto.log`
