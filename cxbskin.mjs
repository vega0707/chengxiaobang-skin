#!/usr/bin/env node
/**
 * cxbskin.mjs — 程小帮「赛博女友」皮肤注入器
 *
 * 原理（参照 Codex-QQ-Skin / heige-codex-skin-studio）：通过 Chromium DevTools Protocol
 * 往程小帮（Electron）渲染进程注入皮肤 CSS + 角色立绘，零修改应用本体（不动 app.asar/签名）。
 *
 * 用法：
 *   node cxbskin.mjs --launch          以调试端口启动程小帮（若已在运行会提示）
 *   node cxbskin.mjs --inject          连接已启动的程小帮并注入皮肤
 *   node cxbskin.mjs --launch --inject 启动并注入（一步到位）
 *   node cxbskin.mjs --remove          移除皮肤（恢复原生界面）
 *   node cxbskin.mjs --shot <out.png>  截图当前主窗口
 */
import { spawn } from "node:child_process";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const HERE = path.dirname(fileURLToPath(import.meta.url));
const PORT = Number(process.env.CXB_GF_PORT || 9229);
const APP_EXE = process.env.CXB_GF_APP || "/Applications/程小帮.app/Contents/MacOS/程小帮";
const PORTRAIT = path.join(HERE, "assets", "gf-portrait.png");
const SKIN_CSS = path.join(HERE, "assets", "gf-skin.css");

const args = process.argv.slice(2);
const mode = args.includes("--launch") && args.includes("--inject") ? "launch-inject"
  : args.includes("--launch") ? "launch"
  : args.includes("--inject") ? "inject"
  : args.includes("--remove") ? "remove"
  : args.includes("--shot") ? "shot"
  : "help";

const shotOut = args[args.indexOf("--shot") + 1] || path.join(HERE, "shot.png");

/* ---------------- CDP 基础 ---------------- */

async function listPageTargets() {
  const res = await fetch(`http://127.0.0.1:${PORT}/json/list`, { redirect: "error" });
  if (!res.ok) throw new Error(`CDP /json/list HTTP ${res.status}`);
  const list = await res.json();
  return (Array.isArray(list) ? list : []).filter((t) => t.type === "page");
}

async function waitForMainTarget(timeoutMs = 30000) {
  const deadline = Date.now() + timeoutMs;
  let lastErr;
  while (Date.now() < deadline) {
    try {
      const targets = await listPageTargets();
      // 主窗口：index.html（title 程小帮）；优先排除 floating-ball / mini-chat
      const main = targets.find((t) => t.url.includes("index.html")) ||
        targets.find((t) => /程小帮/.test(t.title || "")) || targets[0];
      if (main) return main;
    } catch (e) { lastErr = e; }
    await new Promise((r) => setTimeout(r, 400));
  }
  throw new Error(`未找到程小帮主窗口（${timeoutMs}ms）: ${lastErr?.message || "targets 为空"}`);
}

class Cdp {
  constructor(wsUrl) { this.ws = new WebSocket(wsUrl); this.id = 0; this.pending = new Map(); }
  async open() {
    await new Promise((res, rej) => {
      const t = setTimeout(() => rej(new Error("CDP ws open 超时")), 5000);
      this.ws.addEventListener("open", () => { clearTimeout(t); res(); }, { once: true });
      this.ws.addEventListener("error", () => { clearTimeout(t); rej(new Error("CDP ws 连接失败")); }, { once: true });
    });
    this.ws.addEventListener("message", (ev) => {
      const msg = JSON.parse(String(ev.data));
      const w = this.pending.get(msg.id);
      if (!w) return;
      this.pending.delete(msg.id);
      msg.error ? w.reject(new Error(msg.error.message)) : w.resolve(msg.result);
    });
  }
  send(method, params = {}, timeoutMs = 15000) {
    return new Promise((resolve, reject) => {
      const id = ++this.id;
      const t = setTimeout(() => { this.pending.delete(id); reject(new Error(`CDP 超时: ${method}`)); }, timeoutMs);
      this.pending.set(id, { resolve, reject });
      this.ws.send(JSON.stringify({ id, method, params }));
    });
  }
  async eval(expression) {
    const r = await this.send("Runtime.evaluate", { expression, awaitPromise: true, returnByValue: true });
    if (r.exceptionDetails) throw new Error(r.exceptionDetails.exception?.description || r.exceptionDetails.text);
    return r.result?.value;
  }
  close() { try { this.ws.close(); } catch {} }
}

/* ---------------- 皮肤载荷 ---------------- */

const CYBER_STATES = ["idle", "listening", "thinking", "speaking", "acting", "approval", "done"];
const WARM_REUSE = { idle: "idle", listening: "listening", thinking: "listening", speaking: "speaking", acting: "idle", approval: "idle", done: "idle" };

function readVideo(dir, state) {
  return "data:video/webm;base64," + fs.readFileSync(path.join(dir, state + ".webm")).toString("base64");
}

function readVoice(dir, state) {
  return "data:audio/mpeg;base64," + fs.readFileSync(path.join(dir, state + ".mp3")).toString("base64");
}

function readOfficialSpeaking() {
  return "data:audio/mp4;base64," + fs.readFileSync(path.join(HERE, "assets", "voice", "speaking.mp4")).toString("base64");
}

function buildPayload() {
  const cyberCss = fs.readFileSync(path.join(HERE, "assets", "gf-skin.css"), "utf8");
  const warmCss = fs.readFileSync(path.join(HERE, "assets", "gf-warm.css"), "utf8");

  const cyberDir = path.join(HERE, "assets", "themes", "cyber", "states");
  const warmDir = path.join(HERE, "assets", "themes", "warm-white", "states");
  const cyberVideos = {};
  for (const s of CYBER_STATES) cyberVideos[s] = readVideo(cyberDir, s);
  const warmBase = { idle: readVideo(warmDir, "idle"), listening: readVideo(warmDir, "listening"), speaking: readVideo(warmDir, "speaking") };
  const warmVideos = {};
  for (const s of CYBER_STATES) warmVideos[s] = warmBase[WARM_REUSE[s]];

  // 状态语音：每个主题一套（cyber=晓伊活泼甜美 / warm=晓晓温柔知性），见 tools/tts.mjs
  // speaking 状态统一用官方配音（speaking.mp4），其余状态用各自主题的 TTS 台词
  const voiceDir = path.join(HERE, "assets", "voice");
  const officialSpeaking = readOfficialSpeaking();
  const voiceSets = { cyber: {}, warm: {} };
  for (const t of ["cyber", "warm"]) {
    for (const s of CYBER_STATES) {
      voiceSets[t][s] = s === "speaking" ? officialSpeaking : readVoice(path.join(voiceDir, t), s);
    }
  }

  const payload = `(() => {
    const KEY = "__CXB_GF_SKIN__";
    if (window[KEY]) return "already";
    const THEMES = ${JSON.stringify({ cyber: { css: cyberCss, videos: cyberVideos }, warm: { css: warmCss, videos: warmVideos } })};
    const VOICES = ${JSON.stringify(voiceSets)};

    // 注入样式（随主题切换）
    const style = document.createElement("style");
    style.id = "cxb-gf-style-host";
    (document.head || document.documentElement).appendChild(style);

    // 动态女友视频层（右侧大背景，沉底，随状态切换）
    const video = document.createElement("video");
    video.id = "cxb-gf-live";
    video.muted = true;
    video.loop = false; // 不循环，播完一轮触发 ended，由 advance() 决定重播/切换
    video.autoplay = true;
    video.playsInline = true;
    video.setAttribute("playsinline", "");
    document.body.appendChild(video);

    // 女友上方渐变遮罩（保证左侧 UI 可读）
    const veil = document.createElement("div");
    veil.id = "cxb-gf-veil";
    document.body.appendChild(veil);

    // 状态语音层（隐藏 audio，进入状态时播一句，不循环）
    const voice = document.createElement("audio");
    voice.id = "cxb-gf-voice";
    voice.preload = "auto";
    document.body.appendChild(voice);

    // ---- 语音开关（右下角悬浮圆钮，点击静音/恢复，状态持久化到 localStorage）----
    let voiceMuted = false;
    try { voiceMuted = localStorage.getItem("cxb-gf-voice-muted") === "1"; } catch {}
    const voiceBtn = document.createElement("button");
    voiceBtn.id = "cxb-gf-voice-toggle";
    voiceBtn.title = "女友语音：点击静音 / 恢复";
    voiceBtn.setAttribute("aria-label", "切换女友语音");
    voiceBtn.innerHTML = '<span class="vx-on"><svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><polygon points="11 5 6 9 2 9 2 15 6 15 11 19 11 5"></polygon><path d="M15.54 8.46a5 5 0 0 1 0 7.07"></path></svg></span><span class="vx-off"><svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><polygon points="11 5 6 9 2 9 2 15 6 15 11 19 11 5"></polygon><line x1="23" y1="9" x2="17" y2="15"></line><line x1="17" y1="9" x2="23" y2="15"></line></svg></span>';
    voiceBtn.style.cssText = "position:fixed;right:14px;bottom:14px;z-index:2147483000;width:34px;height:34px;border-radius:50%;border:1px solid rgba(255,255,255,0.25);background:rgba(15,12,10,0.55);backdrop-filter:blur(6px);color:#fff;display:flex;align-items:center;justify-content:center;cursor:pointer;font-size:15px;line-height:1;box-shadow:0 2px 8px rgba(0,0,0,0.35);transition:transform .12s,opacity .12s;";
    const renderVoiceBtn = () => {
      voiceBtn.querySelector(".vx-on").style.display = voiceMuted ? "none" : "inline";
      voiceBtn.querySelector(".vx-off").style.display = voiceMuted ? "inline" : "none";
      voiceBtn.style.opacity = voiceMuted ? "0.55" : "1";
    };
    voiceBtn.addEventListener("mouseenter", () => { voiceBtn.style.transform = "scale(1.08)"; });
    voiceBtn.addEventListener("mouseleave", () => { voiceBtn.style.transform = "scale(1)"; });
    voiceBtn.addEventListener("click", () => {
      voiceMuted = !voiceMuted;
      try { localStorage.setItem("cxb-gf-voice-muted", voiceMuted ? "1" : "0"); } catch {}
      if (voiceMuted) voice.pause(); // 点静音时立刻停掉正在说的句子
      renderVoiceBtn();
    });
    renderVoiceBtn();
    document.body.appendChild(voiceBtn);

    // ---- 语音播放：仅在状态真正切换（switchVideo）时触发一句 ----
    // 核心：一次任务运行（running 期间）内，thinking/speaking/acting/approval 每个状态只说一次，
    // 避免任务中状态来回切换导致同一句反复播；新任务开始才重置计数。
    // idle/listening/done 不在运行会话内，走冷却：idle 2 分钟、listening 1 分钟、done 8 秒。
    const RUN_ONCE = ["thinking", "speaking", "acting", "approval"];
    const VOICE_COOLDOWN = { idle: 120000, listening: 60000, done: 8000 };
    const lastVoiceAt = {};
    let saidInSession = {};
    // 全局语音间隔：队列/多任务连续跑时不会连珠炮；完成与授权提示除外
    const VOICE_GAP = 20000;
    let lastPlayedAt = 0;
    const say = (s) => {
      if (voiceMuted) return;
      // 只给当前激活窗口配音：后台窗口/其他进程的任务不播，避免多个任务一起出声
      if (!document.hasFocus()) return;
      if (s === "idle") return; // 空闲不说话（主题切换提示走 sayForced）
      if (!voice.paused) return; // 当前语音正在播：让它讲完（官方配音 6 秒），不中途打断
      const now = Date.now();
      // speaking（官方配音）是核心反馈，与 done/approval 一样豁免全局间隔
      const isImportant = s === "done" || s === "approval" || s === "speaking";
      if (!isImportant && now - lastPlayedAt < VOICE_GAP) return;
      const vset = VOICES[theme] || VOICES.cyber; // 语音随主题切换：夜间晓伊 / 白天晓晓
      const src = vset[s] || vset.idle;
      if (RUN_ONCE.includes(s)) {
        if (saidInSession[s]) return;
        saidInSession[s] = true;
      } else {
        const cd = VOICE_COOLDOWN[s] || 8000;
        if (now - (lastVoiceAt[s] || 0) < cd) return;
        lastVoiceAt[s] = now;
      }
      lastPlayedAt = now;
      voice.src = src;
      voice.play().catch(() => {});
    };
    // 主题切换提示：绕过冷却/会话去重，强制播一句当前主题语音（静音时除外；正在播的语音不打断）
    // 5 秒冷却：一次主题切换过程（class 可能多次变化）只播一次，避免多个「我在呢」连播
    let lastForcedAt = 0;
    const sayForced = (s) => {
      if (voiceMuted) return;
      if (!voice.paused) return;
      const now = Date.now();
      if (now - lastForcedAt < 5000) return;
      lastForcedAt = now;
      const vset = VOICES[theme] || VOICES.cyber;
      lastPlayedAt = now;
      voice.src = vset[s] || vset.idle;
      voice.play().catch(() => {});
    };

    // ---- 主题管理：跟随程小帮深浅外观 ----
    let theme = "cyber";
    const detectTheme = () => document.documentElement.classList.contains("dark") ? "cyber" : "warm";
    const applyTheme = (t) => {
      const changed = t !== theme;
      theme = t;
      style.textContent = THEMES[t].css;
      switchVideo("idle");
      // 深浅主题切换：强制播一句新主题语音，提示“换主题了”（每次切换都播）
      if (changed) sayForced("idle");
    };
    new MutationObserver(() => {
      const t = detectTheme();
      if (t !== theme) { applyTheme(t); setTarget("idle"); }
    }).observe(document.documentElement, { attributes: true, attributeFilter: ["class"] });

    // ---- 状态机：检测程小帮任务状态，切换视频（视频静音，语音由 say 独立播放） ----
    // 只用结构信号（停止按钮/spinner/流式/输入框），不用全文文字匹配——
    // 全文匹配会把聊天内容里的词（"等待确认""全部完成"）误判成状态。
    // 只用结构信号（停止按钮/spinner/流式/输入框），不用全文文字匹配——
    // 全文匹配会把聊天内容里的词（"等待确认""全部完成"）误判成状态。
    //
    // 切换策略：不硬切。detect 只更新「目标状态」，当前视频**播完一轮(ended)**后才切，
    // 且切换时始终用最新的目标状态（中间变化被跳过，不排队积压）。
    let cur = "idle";
    let target = "idle";
    let lastMsgLen = 0;
    let wasRunning = false;
    let runSince = 0;
    let doneUntil = 0;
    // 完成确认：任务真实运行超过 RUN_MIN_MS 后停止，且连续 DONE_CONFIRM_MS 无新活动，
    // 才算「整个事情做完」才播搞定；瞬时误判（运行不足阈值）不触发完成
    let donePending = false;
    let doneSince = 0;
    const RUN_MIN_MS = 3000;
    const DONE_CONFIRM_MS = 3000;
    const switchVideo = (s) => {
      cur = s;
      video.src = THEMES[theme].videos[s] || THEMES[theme].videos.idle;
      video.muted = true;
      video.play().catch(() => {});
      say(s); // 进入新状态：播一句台词（同状态重播不触发）
    };
    const setTarget = (s) => { target = s; };
    const advance = () => {
      if (target === cur) { video.play().catch(() => {}); return; } // 同状态：重新播（循环）
      switchVideo(target);                                         // 不同状态：切到最新目标
    };
    video.addEventListener("ended", advance);
    // 兜底：万一 ended 不触发（如 data URL 异常），每秒检查一次是否该切
    if (window.__CXB_GF_ADVANCE__) clearInterval(window.__CXB_GF_ADVANCE__);
    window.__CXB_GF_ADVANCE__ = setInterval(() => { if (video.paused) advance(); }, 1000);
    const detect = () => {
      try {
        const ae = document.activeElement;
        const typing = ae && (ae.tagName === "TEXTAREA" || ae.tagName === "INPUT") && (ae.value || "").length > 0;
        const msg = document.querySelector(".chat-scroll-area") || document.querySelector(".latest-main-message");
        const msgLen = msg ? msg.innerText.length : 0;
        // 切换对话（消息区骤减）视为新会话：重置「每状态只播一次」并跳过本轮
        if (msgLen < lastMsgLen - 500) { saidInSession = {}; lastMsgLen = msgLen; return; }
        const streaming = msgLen > lastMsgLen + 2;
        lastMsgLen = msgLen;

        // 结构信号（全部要求可见：隐藏的加载图标/动画不能误判为运行中）
        const vis = (el) => !!el && el.offsetWidth > 0 && el.offsetHeight > 0;
        // 运行信号限定在当前对话的布局作用域（.chat-layout-scope）内：
        // 同窗口其他后台任务/任务面板的信号不触发本对话语音；找不到作用域时回退全局
        const chatScope = [...document.querySelectorAll(".chat-layout-scope")].find(vis);
        const scopeRoot = chatScope || document;
        const hasStop = [...scopeRoot.querySelectorAll('button[aria-label*="停止"],button[aria-label*="中断"],button[aria-label*="stop" i]')].some(vis);
        const hasSpinner = [...scopeRoot.querySelectorAll('[class*="animate-spin"],[class*="spinner"],[data-testid*="think"]')].some(vis);
        // 授权弹窗是模态、只属于当前任务，保持全局检测
        const hasApproval = [...document.querySelectorAll('[role="dialog"] button[aria-label*="允许"], [role="dialog"] button[aria-label*="批准"], [role="dialog"] button[aria-label*="授权"], [class*="approval"], [class*="permission"]')].some(vis);
        // 状态行信号：程小帮思考/执行时的固定 UI 文案（限当前对话作用域内、短文本叶子节点）
        const stateLine = (re) => [...scopeRoot.querySelectorAll("p,span,div")].some((e) => {
          if (!vis(e) || e.children.length > 0) return false;
          const t = (e.textContent || "").trim();
          return t.length > 0 && t.length < 14 && re.test(t);
        });
        const hasThinking = stateLine(/^正在思考|^思考中/);
        const hasRunning = stateLine(/^运行命令中|^正在运行|^执行中|^调用.*中$/);

        const running = hasStop || hasSpinner || streaming || hasThinking || hasRunning;
        if (running) {
          if (!wasRunning) { saidInSession = {}; runSince = Date.now(); } // 新任务会话：重置「每状态只播一次」
          wasRunning = true;
          donePending = false; // 任务还在跑，取消完成确认
          if (hasApproval) return setTarget("approval");
          if (streaming) return setTarget("speaking");
          if (hasThinking || hasSpinner) return setTarget("thinking");
          return setTarget("acting"); // hasStop / hasRunning
        }
        // 运行刚停止：真实运行超过阈值才进入「完成确认」窗口（瞬时误判不算）
        if (wasRunning) {
          wasRunning = false;
          if (Date.now() - runSince > RUN_MIN_MS) {
            donePending = true;
            doneSince = Date.now();
          }
        }
        // 停止后连续 DONE_CONFIRM_MS 无新活动 → 确认整个事情做完，才显示完成并播「搞定啦」
        if (donePending && Date.now() - doneSince > DONE_CONFIRM_MS) {
          donePending = false;
          doneUntil = Date.now() + 4000;
        }
        if (Date.now() < doneUntil) return setTarget("done");
        if (typing) return setTarget("listening");
        return setTarget("idle");
      } catch { /* ignore */ }
    };
    // 激活皮肤类
    document.documentElement.classList.add("cxb-gf-skin");

    // 初始应用主题（须在 fadeVideo 定义后调用）
    applyTheme(detectTheme());

    // 启动状态机（先清旧定时器，防止重复注入导致多路并发念多遍）
    if (window.__CXB_GF_TIMER__) clearInterval(window.__CXB_GF_TIMER__);
    window.__CXB_GF_TIMER__ = setInterval(detect, 800);

    window[KEY] = true;
    return "injected:" + theme;
  })()`;
  return payload;
}

function buildRemoveScript() {
  return `(() => {
    if (window.__CXB_GF_TIMER__) { clearInterval(window.__CXB_GF_TIMER__); window.__CXB_GF_TIMER__ = null; }
    document.getElementById("cxb-gf-style-host")?.remove();
    document.getElementById("cxb-gf-background")?.remove();
    document.getElementById("cxb-gf-live")?.remove();
    document.getElementById("cxb-gf-voice")?.remove();
    document.getElementById("cxb-gf-voice-toggle")?.remove();
    document.getElementById("cxb-gf-veil")?.remove();
    document.documentElement.classList.remove("cxb-gf-skin");
    document.documentElement.style.removeProperty("--gf-portrait");
    delete window.__CXB_GF_SKIN__;
    return "removed";
  })()`;
}

/* ---------------- 主流程 ---------------- */

async function connect() {
  const target = await waitForMainTarget();
  const cdp = new Cdp(target.webSocketDebuggerUrl);
  await cdp.open();
  await cdp.send("Runtime.enable");
  await cdp.send("Page.enable");
  return { cdp, target };
}

async function ensureDebugPort() {
  try { await fetch(`http://127.0.0.1:${PORT}/json/version`, { redirect: "error" }); return true; }
  catch { return false; }
}

async function launchApp() {
  if (await ensureDebugPort()) {
    console.log(`端口 ${PORT} 已有 CDP 服务（程小帮已在调试模式运行）。`);
    return;
  }
  const child = spawn(APP_EXE, [`--remote-debugging-port=${PORT}`], {
    detached: true, stdio: "ignore",
  });
  child.unref();
  console.log(`已启动: ${APP_EXE} --remote-debugging-port=${PORT}`);
  console.log("注意：若程小帮此前已在运行（无调试端口），需要先完全退出再启动本脚本。");
}

async function inject() {
  const { cdp, target } = await connect();
  try {
    const r = await cdp.eval(buildPayload());
    console.log(`注入完成: ${r} (target: ${target.title || target.url})`);
  } finally { cdp.close(); }
}

async function remove() {
  const { cdp, target } = await connect();
  try {
    const r = await cdp.eval(buildRemoveScript());
    console.log(`已恢复: ${r}`);
  } finally { cdp.close(); }
}

async function shot() {
  const { cdp } = await connect();
  try {
    // 先确保皮肤已注入（幂等）
    await cdp.eval(buildPayload()).catch(() => {});
    await new Promise((r) => setTimeout(r, 600));
    const { data } = await cdp.send("Page.captureScreenshot", { format: "png" });
    fs.writeFileSync(shotOut, Buffer.from(data, "base64"));
    console.log(`截图已保存: ${shotOut}`);
  } finally { cdp.close(); }
}

/* ---------------- 入口 ---------------- */

(async () => {
  try {
    switch (mode) {
      case "launch": await launchApp(); break;
      case "inject": await inject(); break;
      case "launch-inject": await launchApp(); await inject(); break;
      case "remove": await remove(); break;
      case "shot": await shot(); break;
      default:
        console.log(`cxbskin — 程小帮赛博女友皮肤注入器
用法:
  node cxbskin.mjs --launch           以调试端口启动程小帮
  node cxbskin.mjs --inject           注入皮肤
  node cxbskin.mjs --launch --inject  启动并注入
  node cxbskin.mjs --remove           移除皮肤
  node cxbskin.mjs --shot out.png     截图主窗口`);
    }
  } catch (e) {
    console.error(`[cxbskin] ${e.message}`);
    process.exitCode = 1;
  }
})();
