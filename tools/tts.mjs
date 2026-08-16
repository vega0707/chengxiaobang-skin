#!/usr/bin/env node
/**
 * tts.mjs — 用微软 Edge TTS（在线中文语音）生成皮肤各状态的一句台词
 *
 * 用法：
 *   cd tools && npm i            # 首次：安装 msedge-tts
 *   node tts.mjs                 # 生成两套语音 assets/voice/<theme>/<state>.mp3
 *   node tts.mjs <theme> <state> <文本> [输出名]   # 只生成一句
 *
 * 两套音色（随主题切换）：
 *   cyber（夜间/赛博）：晓伊 XiaoyiNeural，年轻甜美，语速 +15%、音调 +6Hz（接近官方配音的高音女声）
 *   warm （白天/暖白）：晓晓 XiaoxiaoNeural，温柔知性，语速 +8%、音调 +2Hz
 * 背景：vivideo.ai 的声音只是视频配音资产、无法导出单句语音，
 * 故改用微软 Edge TTS 在线合成（与 vivideo 同类的预置在线声音）。
 * 注：Edge 公共端点已禁用 mstts:express-as 情感风格，勿再使用。
 */
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { MsEdgeTTS, OUTPUT_FORMAT } from "msedge-tts";

const HERE = path.dirname(fileURLToPath(import.meta.url));
const OUT_DIR = path.join(HERE, "..", "assets", "voice");

const THEMES = {
  cyber: { voice: "zh-CN-XiaoyiNeural", rate: "+15%", pitch: "+6Hz" },
  warm:  { voice: "zh-CN-XiaoxiaoNeural", rate: "+8%", pitch: "+2Hz" },
};

const LINES = {
  idle: "嗯，我在呢",
  listening: "好呀，我听着呢",
  thinking: "让我想想哦",
  speaking: "马上就好啦",
  acting: "好嘞，这就去办",
  approval: "这个需要你确认一下哦",
  done: "搞定啦",
};

const args = process.argv.slice(2);
const jobs = args.length >= 3
  ? [[args[0], args[1], args[2], args[3] || `${args[1]}.mp3`]]
  : Object.entries(THEMES).flatMap(([theme]) =>
      Object.entries(LINES).map(([state, text]) => [theme, state, text, `${state}.mp3`]));

fs.mkdirSync(OUT_DIR, { recursive: true });
for (const [theme, state, text, outName] of jobs) {
  const cfg = THEMES[theme];
  const tts = new MsEdgeTTS();
  await tts.setMetadata(cfg.voice, OUTPUT_FORMAT.AUDIO_24KHZ_48KBITRATE_MONO_MP3);
  const { audioStream } = tts.toStream(text, { rate: cfg.rate, pitch: cfg.pitch, volume: "+0%" });
  const chunks = [];
  for await (const c of audioStream) chunks.push(c);
  const out = path.join(OUT_DIR, theme, outName);
  fs.mkdirSync(path.dirname(out), { recursive: true });
  fs.writeFileSync(out, Buffer.concat(chunks));
  console.log(`${theme.padEnd(6)} ${state.padEnd(10)} ${text}  ->  ${path.relative(path.join(HERE, ".."), out)}`);
}
