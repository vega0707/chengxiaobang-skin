# chengxiaobang-skin

程小帮（Chengxiaobang）沉浸式女友皮肤，基于 [CodexGF-Live](https://github.com/zhulin025/CodexGF-Live-Releases) 官方视觉配方移植。

## 特性

- 双主题：赛博（深色）+ 暖白（浅色），跟随程小帮深浅外观自动切换
- 7 个状态视频（idle/listening/thinking/speaking/acting/approval/done），暖白主题复用映射
- 昼夜双声线语音：每个阶段一句短台词，夜间晓伊（甜美）/ 白天晓晓（温柔）随主题切换，不循环、防重复、右下角可静音
- 播完一轮再切，排队只留最新状态（不硬切、不闪烁）
- 官方径向 mask 羽化，女友中心清晰、边缘自然融入
- 输入框强制不透明，其他面板半透明透出女友
- 可选 wrapper：默认启动程小帮即自动开调试端口并注入皮肤（见下文「自动开启」）

## 安装

### 前提
- Node.js（运行注入器）
- 程小帮桌面端已安装（默认路径 `/Applications/程小帮.app`）

### 步骤
```bash
git clone https://github.com/<你的用户名>/Codex-QQ-Skin.git
cd Codex-QQ-Skin/chengxiaobang-skin
node cxbskin.mjs --launch --inject   # 启动程小帮并注入
```

### 恢复原生界面
```bash
node cxbskin.mjs --remove
```

### 首次使用
注入后在程小帮里**点一下或打个字**（浏览器自动播放限制），之后视频正常播放。

## 自动开启（可选，推荐）

默认双击/Dock 启动程小帮**不带调试端口**，CDP 注入连不上。`install-auto-skin.sh` 会把程小帮可执行文件替换成包装脚本（原二进制备份为 `程小帮.real`），之后无论怎么启动都自动：

1. 附加 `--remote-debugging-port=9229`（注入前提）
2. 延迟 6 秒后台自动注入皮肤——**重启后皮肤自动出现，无需手动注入**

```bash
./install-auto-skin.sh            # 安装 wrapper
./install-auto-skin.sh --remove   # 还原原生启动
```

- 临时关闭自动皮肤（保留端口）：`touch ~/.chengxiaobang/cxb-skin-off`；删除该文件恢复
- 注入日志：`/tmp/cxb-skin-auto.log`
- 程小帮**升级应用后 wrapper 会被覆盖**，升级后重新执行 `./install-auto-skin.sh` 即可

## 目录结构

```
chengxiaobang-skin/
├── cxbskin.mjs              # 注入器（CDP 注入 CSS + 视频 + 状态机 + 状态语音）
├── install-auto-skin.sh     # 一键 wrapper：默认启动即带端口 + 自动注入（可 --remove 还原）
├── tools/
│   ├── tts.mjs              # 状态语音生成脚本（Edge TTS，可改台词重新生成）
│   └── package.json
├── assets/
│   ├── gf-skin.css          # 赛博主题 CSS
│   ├── gf-warm.css          # 暖白主题 CSS
│   ├── themes/
│   │   ├── cyber/           # 赛博主题视频（7 个状态）
│   │   │   └── states/*.webm
│   │   └── warm-white/      # 暖白主题视频（3 个 + 复用映射）
│   │       └── states/*.webm
│   └── voice/
│       └── *.mp3            # 7 个状态各一句台词（idle/listening/thinking/speaking/acting/approval/done）
└── README.md
```

## 程小帮适配要点

以下记录程小帮 DOM 的特殊之处，给其他机器安装或二次开发时参考。

### 1. 消息区选择器
程小帮的消息滚动容器是 `.chat-scroll-area`（不是 `.latest-main-message`）。状态检测用这个元素的文字长度变化判断流式输出。

### 2. 状态检测
程小帮渲染层（`window.chengxiaobang`）**没有暴露 agent 状态 getter**，真实状态在后端。注入器用结构信号推断：
- 停止按钮出现 = 运行中（acting/thinking）
- spinner 出现 = 思考（thinking）
- 消息流式增长 = 说话（speaking）
- 输入框有内容 = 倾听（listening）
- 运行→空闲边沿 = 完成（done，持续 4 秒）
- 其余 = 待机（idle）

**不要用全文文字匹配**（会把聊天内容误判成状态）。

### 3. 输入框容器
输入框外层容器是 `.bg-card` + `.bg-popover`（含 textarea），必须强制不透明，否则会被面板半透明规则改透明。用 `:has(textarea)` 精准选中：
```css
html.cxb-gf-skin .bg-card:has(textarea),
html.cxb-gf-skin .bg-popover:has(textarea) {
  background-color: <主题底色> !important;
}
```

### 4. 主题检测
程小帮用 `document.documentElement.classList.contains("dark")` 切换深浅主题。注入器监听这个 class 变化自动切换 CSS。

### 5. 视频切换策略
- `video.loop = false`（不循环，播完触发 `ended`）
- 检测器只更新 `target`（目标状态），不直接切视频
- `ended` 事件触发切换：同状态重播，不同状态切到最新 target
- 兜底：每秒检查 `video.paused`，万一 `ended` 没触发也能推进

### 6. 面板半透明
`.bg-background`、`.bg-card`、`.bg-muted`、`.bg-sidebar`、`.bg-canvas-soft`、`.bg-canvas-soft-2`、`.bg-popover` 设为半透明（深色 `rgba(20,17,13,0.55)` / 暖白 `rgba(247,243,238,0.55)`），让女友透出。

### 7. 状态视频映射
**赛博主题**（7 个独立视频）：
| 状态 | 视频 |
|---|---|
| idle | idle.webm |
| listening | listening.webm |
| thinking | thinking.webm |
| speaking | speaking.webm |
| acting | acting.webm |
| approval | approval.webm |
| done | done.webm |

**暖白主题**（3 个视频 + 复用）：
| 状态 | 视频 |
|---|---|
| idle | idle.webm |
| listening | listening.webm |
| speaking | speaking.webm |
| thinking | → listening |
| acting | → idle |
| approval | → idle |
| done | → idle |

### 8. 状态语音
`assets/voice/<theme>/<state>.mp3` 是两套状态台词（每套 7 句），**语音随主题自动切换**：

| 主题 | 音色 | 参数 | 氛围 |
|---|---|---|---|
| cyber（夜间/深色） | 晓伊 XiaoyiNeural | 语速 +15%、音调 +6Hz | 年轻甜美，接近官方配音 |
| warm（白天/浅色） | 晓晓 XiaoxiaoNeural | 语速 +8%、音调 +2Hz | 温柔知性，更温馨 |

台词（两套相同）：

| 状态 | 台词 |
|---|---|
| idle | （不说话） |
| listening | 好呀，我听着呢 |
| thinking | 让我想想哦 |
| speaking | 官方配音（speaking.mp4，6 秒） |
| acting | 好嘞，这就去办 |
| approval | 这个需要你确认一下哦 |
| done | 搞定啦 |

- 只在**状态切换**（`switchVideo`）时播一句，同状态重播不触发；语音不循环。
- 防重复播报：一次任务运行内 thinking/speaking/acting/approval 每个状态只说一次（新任务才重置）；
  idle 2 分钟、listening 1 分钟、done 8 秒冷却。
- 语音开关：右下角悬浮圆钮（🔊/🔇），点击静音/恢复，状态存 localStorage（重启程小帮仍保持）。
- 视频保持静音，语音由独立 `<audio>` 播放（互不影响）。
- 改台词/音色：`cd tools && node tts.mjs` 重新生成（改 `tools/tts.mjs` 里的 `THEMES`/`LINES`，首次 `npm i`）。

## 换机器安装

```bash
git clone https://github.com/<你的用户名>/Codex-QQ-Skin.git
cd Codex-QQ-Skin/chengxiaobang-skin
node cxbskin.mjs --launch --inject
```

所有资产（视频、CSS、配音）都在仓库里，拉下来就能用。

## 修改视频映射

编辑 `cxbskin.mjs` 第 95-96 行：
```js
const CYBER_STATES = ["idle", "listening", "thinking", "speaking", "acting", "approval", "done"];
const WARM_REUSE = { idle: "idle", listening: "listening", thinking: "listening", speaking: "speaking", acting: "idle", approval: "idle", done: "idle" };
```

或替换 `assets/themes/cyber/states/*.webm` 文件（BuddyLiveGF 解包里有 20 个变体视频可选）。

## 更新日志

- **2026-08-16 · 市场 rev 19（0.5.14）**：修复 wrapper 自动注入失效——启动包装器改用 node 绝对路径（GUI 启动环境 PATH 无 node 导致重启后皮肤不自动加载），install-auto-skin.sh 会探测 node 路径并写入包装器
- **2026-08-16 · 市场 rev 18（0.5.13）**：去掉主题切换提示音——切换深浅主题完全安静，不再播「我在呢」
- **2026-08-16 · 市场 rev 17（0.5.12）**：修复切主题时多个「我在呢」连播——主题切换提示加 5 秒冷却，一次切换过程只播一次
- **2026-08-16 · 市场 rev 16（0.5.11）**：修复空闲误报「搞定啦」——任务必须真实运行超过 3 秒、停止后才算完成；瞬时误判（运行信号一闪而过）不再触发完成语音
- **2026-08-16 · 市场 rev 15（0.5.10）**：语音不中途打断——正在播放的语音（含官方 6 秒配音）讲完才播下一句，状态切换不再截断
- **2026-08-16 · 市场 rev 14（0.5.9）**：空闲（idle）不再说话；speaking 状态改用**官方配音**（speaking.mp4，6 秒），speaking 豁免全局间隔保证每次说话都能听到官方声音
- **2026-08-16 · 市场 rev 13（0.5.8）**：修复思考时说「搞定啦」——程小帮思考/执行阶段没有 spinner/停止按钮，改用界面固定状态行（「正在思考…」「运行命令中」）作为运行信号，思考时正确播「让我想想」
- **2026-08-16 · 市场 rev 12（0.5.7）**：「搞定啦」完成确认从 8 秒缩短到 3 秒——做完几乎立即反馈，同时过滤输出中途停顿不误报
- **2026-08-16 · 市场 rev 11（0.5.6）**：「搞定啦」延迟确认——运行停止后连续 8 秒无新活动，确认整个事情做完才播完成音；任务中途停顿不再误报完成
- **2026-08-16 · 市场 rev 10（0.5.5）**：全局语音间隔 20 秒（完成/授权提示除外）——队列/多任务连续跑时不连珠炮（程小帮 UI 未暴露队列与直接任务的区分信号，无法精确识别队列任务）
- **2026-08-16 · 市场 rev 9（0.5.4）**：切换深浅主题时强制播一句新主题语音（绕过冷却），提示「换主题了」
- **2026-08-16 · 市场 rev 8（0.5.3）**：语音只跟「当前激活」走——非聚焦窗口（后台任务/其他进程）不播语音；运行信号限定在当前对话作用域（.chat-layout-scope）内，同窗口其他后台任务的信号不再误触发
- **2026-08-16 · 市场 rev 7（0.5.2）**：修复语音失效——状态检测误将隐藏的加载动画（`animate-spin`）判为运行中，导致会话去重永不重置、语音只播一次；状态信号全部加可见性过滤，并新增切换对话自动重置会话
- **2026-08-16 · 市场 rev 6（0.5.1）**：语音开关图标改为 lucide 风格白描边喇叭（开：喇叭+声波；关：喇叭+斜线），与程小帮界面图标统一
- **2026-08-16 · 市场 rev 5（0.5.0）**：
  - 语音随主题切换双声线：夜间赛博用晓伊（活泼甜美）、白天暖白用晓晓（温柔知性）
  - 右下角语音开关（🔊/🔇）：点击静音/恢复，状态本地持久化
- **2026-08-16 · 市场 rev 4（0.4.0）**：
  - 7 个状态各配一句短台词（晓伊中文女声，Edge TTS 在线合成，声线参考官方配音），进入阶段播一句、不循环
  - 防重复播报：一次任务运行内每个运行态只说一次（thinking/speaking/acting/approval），新任务才重置；idle 2 分钟、listening 1 分钟冷却
  - 新增 `tools/tts.mjs` 语音生成脚本（可改台词重新生成）
  - 说明：vivideo.ai 的声音只是视频配音资产、无法导出单句语音，故改用微软 Edge TTS
- **2026-08-16 · 市场 rev 3（0.3.0）**：
  - 新增斜杠命令 `/install-auto-skin`：一键安装/还原启动包装器（默认启动即带皮肤）
- **2026-08-16 · 市场 rev 2（0.2.0）**：
  - 新增 `install-auto-skin.sh`：一键安装启动包装器，**默认启动程小帮即自动开调试端口并注入皮肤**（原二进制备份为 `程小帮.real`，`--remove` 可还原；升级应用后需重装）
  - 插件头像更换为紫色 icon
  - 技能说明与本文档补充 wrapper 用法
- **2026-08-16 · 市场 rev 1（0.1.0）**：首个版本——双主题（赛博/暖白）CDP 皮肤注入、7 状态视频、注入器技能、插件化打包与发布

## 参考

- [CodexGF-Live Releases](https://github.com/zhulin025/CodexGF-Live-Releases) — 官方皮肤（含 style-patch.json）
- [zhulin025/BuddyLiveGF](https://github.com/zhulin025/BuddyLiveGF) — WorkBuddy 女友皮肤（状态视频来源）
- [codex.liuwa.xyz](https://codex.liuwa.xyz/) — 官方演示站
