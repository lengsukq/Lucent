#!/usr/bin/env node
/**
 * Lucent Promo Video — Gentle Female Mandarin Voiceover (XiaoxiaoNeural)
 * + Restrained Serene Ambient Bed (Zero Drums / Zero Harsh Arps)
 * + Real-Time RMS Sidechain Ducking + Delicate Tactile UI Accents
 *
 * Output:
 *   public/audio/generated/soundtrack-master.wav (48 kHz 16-bit stereo, -16 LUFS mastered)
 */

import { execFileSync } from 'node:child_process';
import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { MsEdgeTTS, OUTPUT_FORMAT } from 'msedge-tts';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const PROJECT_DIR = path.resolve(__dirname, '..');
const TIMELINE = JSON.parse(fs.readFileSync(path.join(PROJECT_DIR, 'src/timeline.json'), 'utf8'));

const SAMPLE_RATE = 48000;
const FPS = TIMELINE.fps;
const DURATION_SEC = TIMELINE.totalFrames / FPS; // 250.00s
const TOTAL_SAMPLES = Math.ceil(DURATION_SEC * SAMPLE_RATE);

const OUT_DIR = path.join(PROJECT_DIR, 'public/audio/generated');
const VO_DIR = path.join(OUT_DIR, 'vo');
fs.mkdirSync(VO_DIR, { recursive: true });

const RAW_MIX_WAV = path.join(OUT_DIR, 'soundtrack-raw.wav');
const MASTER_WAV = path.join(OUT_DIR, 'soundtrack-master.wav');
const FFMPEG_BIN = fs.existsSync('/opt/homebrew/bin/ffmpeg') ? '/opt/homebrew/bin/ffmpeg' : 'ffmpeg';

// =========================================================================
// 1. GENTLE FEMALE MANDARIN VOICEOVER SCRIPT (25 CUES SYNCED TO 8 ACTS)
// =========================================================================
const VOICE_NAME = 'zh-CN-XiaoxiaoNeural';
const VOICE_OPTS = { rate: '+2%', pitch: '-2Hz' };

const NARRATION_CUES = [
  // Act 0 (0..20s)
  { id: 'a0_1', startSec: 2.8, text: '一触流光，用完即焚。专为苹果芯片打造的原生效率中枢，流光 Lucent。' },
  { id: 'a0_2', startSec: 11.2, text: '轻按 Option 空格即可瞬间唤起。全部能力仅约十兆，用完自动释放内存。' },

  // Act 1 (20..54s)
  { id: 'a1_1', startSec: 20.8, text: '启动面板像积木一样自由编排：大磁贴、混合高频坞与书签架，随心开关排序。' },
  { id: 'a1_2', startSec: 32.2, text: '内置四套场景预设一键切换。搜索结果右键就能固定到主页，改乱还能随时撤回。' },
  { id: 'a1_3', startSec: 43.2, text: '霓彩流光与凝霜留白双主题一扫切换，中英双语免重启生效，并自动同步插件。' },

  // Act 2 (54..92s)
  { id: 'a2_1', startSec: 54.8, text: '呼出直接打字。依托内存映射与增量监听，移动硬盘文件与拼音应用瞬间命中。' },
  { id: 'a2_2', startSec: 65.2, text: '富媒体剪贴板随时找回文字、色板与图片，支持十五步撤回并自动避开密码器。' },
  { id: 'a2_3', startSec: 75.2, text: '算账、十类单位换算、二维码与令牌解析，全部本地离线完成。' },
  { id: 'a2_4', startSec: 83.2, text: '输入感叹号秒跑快捷脚本，支持本地目录双向同步与专属矢量图标。' },

  // Act 3 (92..136s)
  { id: 'a3_1', startSec: 92.8, text: '不装插件，五大原生利器开箱顺手。Option A 多屏截图标注、圆角抠窗并置顶贴图。' },
  { id: 'a3_2', startSec: 102.6, text: 'Option G 无需 FFmpeg，灵动岛直录区域动图，自动压缩静止帧。' },
  { id: 'a3_3', startSec: 110.8, text: 'Option O 本地视觉引擎，一秒离线提取中英文与二维码。' },
  { id: 'a3_4', startSec: 117.8, text: '外接普通鼠标享有一百二十赫兹平滑滚轮，同时完整保留触控板原本自然手感。' },
  { id: 'a3_5', startSec: 127.6, text: '双栏文件台、4K 影院、芯片脉搏与网速透视按需呼出，关窗即净。' },

  // Act 4 (136..170s)
  { id: 'a4_1', startSec: 136.8, text: '顶部菜单栏三档瘦身，支持静默全局热键，不改源码即可覆写唤醒词。' },
  { id: 'a4_2', startSec: 145.0, text: '七款官方插件均预编译为原生 Swift 二进制，开箱即跑无需外部环境，涵盖译站、书签、提醒与中控。' },
  { id: 'a4_3', startSec: 156.2, text: '新版引擎支持无边框透明桌面挂件，丝滑拖拽且支持点击穿透。' },
  { id: 'a4_4', startSec: 163.2, text: '单地址框智能订阅商店，强制核验安全哈希，升级保留配置。' },

  // Act 5 (170..208s)
  { id: 'a5_1', startSec: 170.8, text: '不会写代码也能深度定制。内置二十项 AI 协议工具，对助手说一句话，十秒造插件并实时热加载生效。' },
  { id: 'a5_2', startSec: 184.2, text: '让 AI 写一条清理端口的快捷脚本，它会顺手为你画好专属矢量图标。' },
  { id: 'a5_3', startSec: 196.0, text: '甚至连启动面板都不必手动排。说出你的习惯，AI 瞬间为你热刷新主页。' },

  // Act 6 (208..234s)
  { id: 'a6_1', startSec: 208.8, text: '背后是纯净克制的工程底牌：Swift 6 零依赖、九模块无环架构，以及单文件三百行代码门禁。' },
  { id: 'a6_2', startSec: 218.0, text: '插件经苹果内核沙箱隔离，密钥加密落盘，支持整机云端加密备份。' },
  { id: 'a6_3', startSec: 226.2, text: '收起三十秒毁视图，空闲九十秒卸索引，默认零悬浮窗打扰。' },

  // Act 7 (234..250s)
  { id: 'a7_1', startSec: 235.8, text: '让每一次按键，如流光掠影。流光 Lucent，MIT 免费开源，欢迎下载体验。' },
];

async function synthesizeVoiceCue(cue) {
  const hash = crypto
    .createHash('sha1')
    .update(`${VOICE_NAME}|${JSON.stringify(VOICE_OPTS)}|${cue.text}`)
    .digest('hex')
    .slice(0, 10);
  const mp3Path = path.join(VO_DIR, `${cue.id}_${hash}.mp3`);
  const pcmPath = path.join(VO_DIR, `${cue.id}_${hash}.f32`);

  if (!fs.existsSync(mp3Path)) {
    let lastErr;
    for (let attempt = 1; attempt <= 3; attempt++) {
      try {
        const tts = new MsEdgeTTS();
        await tts.setMetadata(VOICE_NAME, OUTPUT_FORMAT.AUDIO_24KHZ_96KBITRATE_MONO_MP3);
        const { audioStream } = tts.toStream(cue.text, VOICE_OPTS);
        const chunks = [];
        for await (const chunk of audioStream) {
          chunks.push(chunk);
        }
        const buf = Buffer.concat(chunks);
        if (buf.length < 1000) throw new Error('Empty TTS audio response');
        fs.writeFileSync(mp3Path, buf);
        lastErr = null;
        break;
      } catch (err) {
        lastErr = err;
        await new Promise((r) => setTimeout(r, 700 * attempt));
      }
    }
    if (lastErr) throw lastErr;
  }

  // Decode + polish voice warmth (highpass 85Hz, warm gentle EQ, soft de-ess, trim leading/trailing silence)
  execFileSync(
    FFMPEG_BIN,
    [
      '-y',
      '-hide_banner',
      '-loglevel',
      'error',
      '-i',
      mp3Path,
      '-af',
      'silenceremove=start_periods=1:start_silence=0.05:start_threshold=-45dB,areverse,silenceremove=start_periods=1:start_silence=0.08:start_threshold=-45dB,areverse,highpass=f=85,equalizer=f=240:t=q:w=1.2:g=1.4,equalizer=f=6800:t=q:w=1.6:g=-2.2',
      '-ar',
      String(SAMPLE_RATE),
      '-ac',
      '1',
      '-f',
      'f32le',
      pcmPath,
    ],
    { stdio: 'inherit' },
  );

  const raw = fs.readFileSync(pcmPath);
  fs.unlinkSync(pcmPath);
  const samples = new Float32Array(raw.buffer, raw.byteOffset, raw.byteLength / 4);
  return new Float32Array(samples);
}

console.log(`==> Synthesizing ${NARRATION_CUES.length} gentle Mandarin female voiceover cues (${VOICE_NAME})...`);
const voMono = new Float32Array(TOTAL_SAMPLES);
let prevEndSec = 0;

for (const cue of NARRATION_CUES) {
  const samples = await synthesizeVoiceCue(cue);
  const durSec = samples.length / SAMPLE_RATE;
  // Auto-guard: ensure at least 0.55s comfortable breathing pause after previous cue
  const actualStartSec = Math.max(cue.startSec, prevEndSec + 0.55);
  const endSec = actualStartSec + durSec;
  if (actualStartSec > cue.startSec + 0.05) {
    console.log(
      `  [adjust] ${cue.id}: shifted ${cue.startSec.toFixed(1)}s -> ${actualStartSec.toFixed(1)}s (dur ${durSec.toFixed(2)}s, ends ${endSec.toFixed(1)}s)`,
    );
  } else {
    console.log(
      `  [VO] ${cue.id}: ${actualStartSec.toFixed(1)}s .. ${endSec.toFixed(1)}s (${durSec.toFixed(2)}s)`,
    );
  }
  prevEndSec = endSec;

  const startIdx = Math.floor(actualStartSec * SAMPLE_RATE);
  const fadeSamples = Math.floor(0.015 * SAMPLE_RATE);
  for (let i = 0; i < samples.length; i++) {
    const idx = startIdx + i;
    if (idx >= TOTAL_SAMPLES) break;
    let env = 1.0;
    if (i < fadeSamples) env = i / fadeSamples;
    else if (i > samples.length - fadeSamples) env = (samples.length - i) / fadeSamples;
    voMono[idx] += samples[i] * env;
  }
}

if (prevEndSec > DURATION_SEC - 0.8) {
  console.warn(`WARNING: Final narration ends at ${prevEndSec.toFixed(2)}s (video is ${DURATION_SEC}s)`);
}

// =========================================================================
// 2. SERENE, ULTRA-QUIET MINIMALIST AMBIENT BED (ZERO DRUMS / ZERO CLUTTER)
//    Whisper-soft warm low-passed velvet chords + sparse gentle felt-piano touches
// =========================================================================
console.log('==> Composing ultra-calm minimalist ambient bed with generous breathing space...');

const bgmL = new Float32Array(TOTAL_SAMPLES);
const bgmR = new Float32Array(TOTAL_SAMPLES);

function addBgm(idx, l, r) {
  if (idx >= 0 && idx < TOTAL_SAMPLES) {
    bgmL[idx] += l;
    bgmR[idx] += r;
  }
}

// Soft low-register warm pads (never bright or buzzy)
const CALM_CHORDS = [
  [130.81, 196.0, 293.66], // Csus2
  [110.0, 164.81, 246.94], // Am9
  [87.31, 174.61, 261.63], // Fadd9
  [98.0, 196.0, 293.66],   // Gsus4
];
const FELT_NOTES = [261.63, 293.66, 329.63, 392.0, 440.0, 523.25];

function addVelvetPad(startSec, durSec, freqs, amp) {
  const start = Math.floor(startSec * SAMPLE_RATE);
  const len = Math.floor(durSec * SAMPLE_RATE);
  const twoPi = 2 * Math.PI;
  for (let i = 0; i < len; i++) {
    const t = i / SAMPLE_RATE;
    const fIn = Math.min(1, t / 2.2);
    const fOut = Math.min(1, (durSec - t) / 2.4);
    const env = 0.5 * (1 - Math.cos(Math.PI * Math.min(fIn, fOut)));
    let l = 0;
    let r = 0;
    for (let v = 0; v < freqs.length; v++) {
      const f = freqs[v];
      // Pure warm fundamental sine only — zero harsh upper harmonics
      const s1 = Math.sin(twoPi * f * t);
      const s2 = Math.sin(twoPi * f * (v % 2 === 0 ? 1.0014 : 0.9986) * t + 0.6);
      l += (s1 * 0.58 + s2 * 0.42);
      r += (s1 * 0.42 + s2 * 0.58);
    }
    const g = (amp * env) / freqs.length;
    addBgm(start + i, l * g, r * g);
  }
}

function addFeltPianoNote(startSec, freq, durSec, amp, pan = 0) {
  const start = Math.floor(startSec * SAMPLE_RATE);
  const len = Math.floor(durSec * SAMPLE_RATE);
  const gL = Math.cos(((pan + 1) * Math.PI) / 4) * amp;
  const gR = Math.sin(((pan + 1) * Math.PI) / 4) * amp;
  const twoPi = 2 * Math.PI;
  for (let i = 0; i < len; i++) {
    const t = i / SAMPLE_RATE;
    const atk = Math.min(1, t / 0.022); // Mellow felt hammer attack
    const env = atk * Math.exp(-t * (2.6 / Math.max(0.6, durSec)));
    // Soft muted felt piano tone (only fundamental + gentle 2nd harmonic)
    const sig = (Math.sin(twoPi * freq * t) * 0.86 + Math.sin(twoPi * freq * 2 * t) * 0.14 * Math.exp(-t * 5.0)) * env;
    addBgm(start + i, sig * gL, sig * gR);
  }
}

// Sparse, whisper-quiet ambient breathing only at chapter openings/transitions — NEVER drones continuously!
let phraseIdx = 0;
for (let t = 0.2; t < DURATION_SEC - 8.0; t += 15.0) {
  const chord = CALM_CHORDS[phraseIdx % CALM_CHORDS.length];
  // 8.0s soft velvet breath followed by 7.0s calm silence/piano tail
  addVelvetPad(t, 8.0, chord, 0.036);

  const n1 = FELT_NOTES[(phraseIdx * 2) % FELT_NOTES.length];
  const n2 = FELT_NOTES[(phraseIdx * 2 + 2) % FELT_NOTES.length];
  addFeltPianoNote(t + 0.5, n1, 3.0, 0.028, -0.28);
  addFeltPianoNote(t + 5.8, n2, 3.2, 0.022, 0.30);
  phraseIdx++;
}

// Gentle warm resolution chord in Finale (234..249.2s)
addVelvetPad(234.0, 14.5, [130.81, 196.0, 261.63, 329.63], 0.048);
addFeltPianoNote(234.8, 523.25, 4.2, 0.030, -0.2);
addFeltPianoNote(244.4, 392.0, 4.0, 0.026, 0.2);
addFeltPianoNote(245.8, 523.25, 3.6, 0.024, 0.0);

// =========================================================================
// 3. ULTRA-DELICATE SIGNATURE MICRO-SFX (FEATHER-SOFT, NEVER JARRING)
// =========================================================================
const sfxL = new Float32Array(TOTAL_SAMPLES);
const sfxR = new Float32Array(TOTAL_SAMPLES);

function addSfx(idx, l, r) {
  if (idx >= 0 && idx < TOTAL_SAMPLES) {
    sfxL[idx] += l;
    sfxR[idx] += r;
  }
}

function addSoftGlassPing(startSec, freq, durSec, amp, pan = 0) {
  const start = Math.floor(startSec * SAMPLE_RATE);
  const len = Math.floor(durSec * SAMPLE_RATE);
  const gL = Math.cos(((pan + 1) * Math.PI) / 4) * amp;
  const gR = Math.sin(((pan + 1) * Math.PI) / 4) * amp;
  const twoPi = 2 * Math.PI;
  for (let i = 0; i < len; i++) {
    const t = i / SAMPLE_RATE;
    const env = Math.min(1, t / 0.012) * Math.exp(-t * (5.2 / Math.max(0.25, durSec)));
    const sig = Math.sin(twoPi * freq * t) * env;
    addSfx(start + i, sig * gL, sig * gR);
  }
}

// Only keep signature milestone accents (keycap press, theme sweep, MCP reload bells, finale shimmer)
const SIGNATURE_SFX = new Set(['keycap_press', 'shockwave_bloom', 'theme_sweep', 'reload_bell', 'verify_lock']);
for (const ev of TIMELINE.sfxEvents) {
  if (!SIGNATURE_SFX.has(ev.type)) continue;
  const t0 = ev.frame / FPS;
  if (ev.type === 'keycap_press') {
    addSoftGlassPing(t0, 523.25, 0.35, 0.055, 0);
  } else if (ev.type === 'shockwave_bloom') {
    addSoftGlassPing(t0, 523.25, 1.4, 0.045, -0.25);
    addSoftGlassPing(t0 + 0.09, 659.25, 1.5, 0.040, 0.25);
  } else if (ev.type === 'theme_sweep') {
    addSoftGlassPing(t0, 587.33, 1.1, 0.045, -0.35);
    addSoftGlassPing(t0 + 0.12, 880.0, 1.2, 0.038, 0.35);
  } else if (ev.type === 'reload_bell' || ev.type === 'verify_lock') {
    addSoftGlassPing(t0, 783.99, 0.85, 0.038, -0.15);
    addSoftGlassPing(t0 + 0.08, 1046.5, 0.95, 0.032, 0.15);
  }
}

// =========================================================================
// 4. REAL-TIME VOICE ENVELOPE FOLLOWER -> AUTOMATIC SIDECHAIN DUCKING
//    When gentle female VO speaks, BGM smoothly ducks by ~-9 dB so VO is effortless & crystal clear
// =========================================================================
console.log('==> Applying smooth sidechain ducking & gentle room ambience...');

const outL = new Float32Array(TOTAL_SAMPLES);
const outR = new Float32Array(TOTAL_SAMPLES);

// Precompute subtle stereo ambient tail on BGM only (keeps voice dry, intimate & ultra-clear)
const dL = Math.floor(0.26 * SAMPLE_RATE);
const dR = Math.floor(0.35 * SAMPLE_RATE);
const bgmWetL = new Float32Array(TOTAL_SAMPLES);
const bgmWetR = new Float32Array(TOTAL_SAMPLES);
for (let i = 0; i < TOTAL_SAMPLES; i++) {
  bgmWetL[i] = (i >= dL ? bgmL[i - dL] + bgmWetR[i - dL] * 0.28 : 0) * 0.26;
  bgmWetR[i] = (i >= dR ? bgmR[i - dR] + bgmWetL[i - dR] * 0.28 : 0) * 0.26;
}

// Very gentle 1-pole lowpass on BGM (~820 Hz) so background music is whisper-soft velvet, never shrill
const lpAlpha = (2 * Math.PI * 820) / (SAMPLE_RATE + 2 * Math.PI * 820);
let lpL = 0;
let lpR = 0;

// Smooth envelope follower on voiceover (attack 40ms, release 720ms)
const atkCoeff = Math.exp(-1 / (0.04 * SAMPLE_RATE));
const relCoeff = Math.exp(-1 / (0.72 * SAMPLE_RATE));
let voEnv = 0;

// Subtle intimate studio air on voice (very low 22ms stereo micro-width)
const voRefL = Math.floor(0.019 * SAMPLE_RATE);
const voRefR = Math.floor(0.027 * SAMPLE_RATE);

const fadeInSamples = Math.floor(1.5 * SAMPLE_RATE);
const fadeOutSamples = Math.floor(3.2 * SAMPLE_RATE);

for (let i = 0; i < TOTAL_SAMPLES; i++) {
  const v = voMono[i];
  const absV = Math.abs(v);
  voEnv = absV > voEnv ? atkCoeff * voEnv + (1 - atkCoeff) * absV : relCoeff * voEnv + (1 - relCoeff) * absV;

  // Map voice activity [0..0.025] -> BGM ducking gain [1.0 -> 0.25] (-12 dB while speaking)
  const duckAmt = Math.min(1, voEnv / 0.024);
  const bgmGain = 1.0 - duckAmt * 0.75;

  // Lowpass velvet BGM
  lpL += lpAlpha * (bgmL[i] + bgmWetL[i] - lpL);
  lpR += lpAlpha * (bgmR[i] + bgmWetR[i] - lpR);

  // Subtle intimate voice presence (centered + tiny stereo air)
  const vAirL = i >= voRefL ? voMono[i - voRefL] * 0.045 : 0;
  const vAirR = i >= voRefR ? voMono[i - voRefR] * 0.045 : 0;
  const voiceL = v * 0.88 + vAirL;
  const voiceR = v * 0.88 + vAirR;

  let masterEnv = 1.0;
  if (i < fadeInSamples) masterEnv = i / fadeInSamples;
  if (i > TOTAL_SAMPLES - fadeOutSamples) {
    masterEnv = Math.max(0, (TOTAL_SAMPLES - i) / fadeOutSamples);
    masterEnv = masterEnv * masterEnv;
  }

  const mixL = (voiceL + lpL * bgmGain + sfxL[i] * (1.0 - duckAmt * 0.45)) * masterEnv;
  const mixR = (voiceR + lpR * bgmGain + sfxR[i] * (1.0 - duckAmt * 0.45)) * masterEnv;

  outL[i] = Math.tanh(mixL * 1.02) * 0.94;
  outR[i] = Math.tanh(mixR * 1.02) * 0.94;
}

function writeWav16(filePath, chL, chR, sampleRate) {
  const numSamples = chL.length;
  const dataBytes = numSamples * 4;
  const buf = Buffer.alloc(44 + dataBytes);

  buf.write('RIFF', 0);
  buf.writeUInt32LE(36 + dataBytes, 4);
  buf.write('WAVE', 8);
  buf.write('fmt ', 12);
  buf.writeUInt32LE(16, 16);
  buf.writeUInt16LE(1, 20);
  buf.writeUInt16LE(2, 22);
  buf.writeUInt32LE(sampleRate, 24);
  buf.writeUInt32LE(sampleRate * 4, 28);
  buf.writeUInt16LE(4, 32);
  buf.writeUInt16LE(16, 34);
  buf.write('data', 36);
  buf.writeUInt32LE(dataBytes, 40);

  let offset = 44;
  for (let i = 0; i < numSamples; i++) {
    const l = Math.max(-1, Math.min(1, chL[i]));
    const r = Math.max(-1, Math.min(1, chR[i]));
    buf.writeInt16LE(Math.round(l * 32767), offset);
    buf.writeInt16LE(Math.round(r * 32767), offset + 2);
    offset += 4;
  }
  fs.writeFileSync(filePath, buf);
}

writeWav16(RAW_MIX_WAV, outL, outR, SAMPLE_RATE);

console.log('==> Mastering final gentle VO + serene ambient track (-16 LUFS)...');
execFileSync(
  FFMPEG_BIN,
  [
    '-y',
    '-hide_banner',
    '-loglevel',
    'error',
    '-i',
    RAW_MIX_WAV,
    '-af',
    'highpass=f=32,loudnorm=I=-16:TP=-1.5:LRA=11',
    '-ar',
    '48000',
    '-ac',
    '2',
    '-c:a',
    'pcm_s16le',
    MASTER_WAV,
  ],
  { stdio: 'inherit' },
);
fs.unlinkSync(RAW_MIX_WAV);

const stat = fs.statSync(MASTER_WAV);
console.log(`==> Gentle VO + Ambient master ready: ${MASTER_WAV} (${(stat.size / 1024 / 1024).toFixed(1)} MB, ${DURATION_SEC.toFixed(2)}s)`);
