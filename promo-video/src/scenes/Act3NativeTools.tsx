import React from 'react';
import { AbsoluteFill, Easing, interpolate, useCurrentFrame } from 'remotion';
import { AuroraBackdrop } from '../components/AuroraBackdrop';
import {
  IconCheck,
  IconCpu,
  IconCrop,
  IconFolder,
  IconGif,
  IconMouse,
  IconNetwork,
  IconPin,
  IconPlay,
  IconScanText,
  IconShield,
  SquircleBadge,
} from '../components/Icons';
import { KeycapBadge } from '../components/KeycapBadge';
import { BottomCaptionBar, CaptionBeat, SceneHeader } from '../components/KineticCaption';
import { AnimatedCursor, CameraStage, MacStatusBarStrip } from '../components/MacChrome';
import { clampLerp, spr, SPRING_GLASS } from '../design/motion';
import { FONT_MONO, FONT_SANS, getTheme, RADII, ThemeMode } from '../design/tokens';

const CAPTIONS: CaptionBeat[] = [
  { start: 30, end: 560, tag: '⌥A CAPTURE', text: '多显示器逐屏原画质截图标注：窗口无遮挡圆角抠图、放大镜按 C 取色、1:1 穿透钉屏' },
  { start: 590, end: 1020, tag: '⌥G GIF', text: '零 FFmpeg 原生 SCStream 区域 GIF 录屏：灵动岛悬浮控制 + 静止帧自动压缩，即录即粘' },
  { start: 1050, end: 1460, tag: '⌥O OCR', text: '绑定 Apple Vision 离线引擎，亚秒级识别屏幕中英文与二维码，一键交给翻译或笔记插件' },
  { start: 1490, end: 2040, tag: '120Hz MOUSE', text: '独立识别物理鼠标与触控板：外接鼠标享受 120Hz 平滑滚轮，完全保留触控板原本自然手感' },
  { start: 2070, end: 2620, tag: 'ON-DEMAND', text: '双栏文件整理台（NTFS 只读护航）、4K 置顶小窗、芯片脉搏与网速透视：按需呼出，关窗即净' },
];

type SubStage = 'capture' | 'gif' | 'ocr' | 'mouse' | 'toolbox';

export const Act3NativeTools: React.FC = () => {
  const frame = useCurrentFrame();

  const stage: SubStage =
    frame < 580
      ? 'capture'
      : frame < 1040
      ? 'gif'
      : frame < 1480
      ? 'ocr'
      : frame < 2060
      ? 'mouse'
      : 'toolbox';

  // Alternate Pure Frost (capture, mouse) and Prism Pulse (gif, ocr, toolbox) for cinematic visual rhythm
  const theme: ThemeMode = stage === 'capture' || stage === 'mouse' ? 'pure-frost' : 'prism-pulse';
  const t = getTheme(theme);

  const stageNav: { id: SubStage; key: string; label: string; icon: React.ReactNode }[] = [
    { id: 'capture', key: '⌥A', label: '截图标注钉屏', icon: <IconCrop size={15} /> },
    { id: 'gif', key: '⌥G', label: '原生 GIF', icon: <IconGif size={15} /> },
    { id: 'ocr', key: '⌥O', label: '离线识字', icon: <IconScanText size={15} /> },
    { id: 'mouse', key: '120Hz', label: '鼠标平滑滚轮', icon: <IconMouse size={15} /> },
    { id: 'toolbox', key: '⌥E/M/N', label: '按需工具箱', icon: <IconCpu size={15} /> },
  ];

  // Sub-animations
  const cropDraw = clampLerp(frame, [50, 155], [0, 1], Easing.out(Easing.cubic));
  const arrowDraw = clampLerp(frame, [175, 265], [0, 1], Easing.out(Easing.cubic));
  const pinFloat = clampLerp(frame, [150, 250], [0, 1], Easing.out(Easing.cubic));

  const gifSec = Math.max(0, (frame - 620) / 60);
  const ocrScanY = clampLerp(frame, [1090, 1270], [0, 100], Easing.inOut(Easing.cubic));
  const ocrDone = frame >= 1265;

  // Mouse scroll comparison physics (frame 1480..2060)
  const mouseElapsed = Math.max(0, (frame - 1520) / 60);
  // Raw discrete mouse: harsh 3-step jumps per second
  const steppedOffset = Math.floor(mouseElapsed * 2.4) * 86;
  // Lucent 120Hz smooth curve: continuous silky buttery travel
  const smoothOffset = mouseElapsed * 2.4 * 86;

  return (
    <AbsoluteFill style={{ fontFamily: FONT_SANS }}>
      <AuroraBackdrop theme={theme} seedOffset={5520} />

      <div
        style={{
          position: 'absolute',
          inset: '72px 88px 104px',
          display: 'flex',
          flexDirection: 'column',
          gap: 24,
        }}
      >
        {/* Top Row: Header + 5-Tool Pill Selector */}
        <div style={{ display: 'flex', alignItems: 'flex-end', justifyContent: 'space-between' }}>
          <SceneHeader
            eyebrow="03 / 07 · FIVE EVERYDAY NATIVE TOOLS"
            title="不装插件，"
            highlight="五大原生利器开箱即顺手。"
            theme={theme}
            frame={frame}
            maxWidth={960}
            fontSize={44}
          />

          <div style={{ display: 'flex', gap: 9, paddingBottom: 6 }}>
            {stageNav.map((item) => {
              const active = item.id === stage;
              return (
                <div
                  key={item.id}
                  style={{
                    padding: '9px 14px',
                    borderRadius: RADII.pill,
                    background: active ? t.accentGradient : t.bgCard,
                    border: `1px solid ${active ? 'rgba(255,255,255,0.45)' : t.rimOuter}`,
                    color: active ? '#fff' : t.textSecondary,
                    fontSize: 13.5,
                    fontWeight: active ? 700 : 500,
                    display: 'inline-flex',
                    alignItems: 'center',
                    gap: 7,
                    boxShadow: t.cardShadow,
                  }}
                >
                  {item.icon}
                  <span>{item.label}</span>
                  <span style={{ fontFamily: FONT_MONO, fontSize: 11, opacity: 0.8 }}>{item.key}</span>
                </div>
              );
            })}
          </div>
        </div>

        {/* Main Interactive Stage */}
        <div style={{ flex: 1, minHeight: 0, display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
          {/* 1. SCREENSHOT + ANNOTATION + PIN (⌥A) */}
          {stage === 'capture' && (
            <CameraStage enterFrame={0} breathScale={0.008} tiltDeg={0.7}>
            <div style={{ width: '100%', height: '100%', display: 'grid', gridTemplateColumns: '1.35fr 0.65fr', gap: 28, alignItems: 'center' }}>
              <div
                style={{
                  position: 'relative',
                  height: 536,
                  borderRadius: 26,
                  background: 'linear-gradient(145deg, #d7e5fb, #eef4fd 55%, #e4e9fb)',
                  border: `1px solid ${t.rimOuter}`,
                  boxShadow: t.panelShadow,
                  overflow: 'hidden',
                }}
              >
                <MacStatusBarStrip theme="pure-frost" activeApp="Lucent Capture" />
                <div style={{ padding: '20px 28px 28px', position: 'relative', height: 'calc(100% - 30px)' }}>
                {/* Mock macOS Window Behind Capture */}
                <div
                  style={{
                    width: '86%',
                    height: 360,
                    borderRadius: 18,
                    background: '#ffffff',
                    border: '1px solid rgba(15,23,42,0.09)',
                    boxShadow: '0 22px 48px rgba(15,23,42,0.10)',
                    padding: 22,
                  }}
                >
                  <div style={{ display: 'flex', gap: 7, marginBottom: 18 }}>
                    <span style={{ width: 11, height: 11, borderRadius: '50%', background: '#ff5f57' }} />
                    <span style={{ width: 11, height: 11, borderRadius: '50%', background: '#febc2e' }} />
                    <span style={{ width: 11, height: 11, borderRadius: '50%', background: '#28c840' }} />
                    <span style={{ marginLeft: 10, fontFamily: FONT_MONO, fontSize: 12, color: '#64748b' }}>
                      Studio Display 5K + Pro Display XDR · 逐屏原生 DPI
                    </span>
                  </div>
                  <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 16 }}>
                    <div style={{ height: 120, borderRadius: 14, background: 'linear-gradient(135deg,#0ea5e9,#6366f1)', padding: 16, color: '#fff' }}>
                      <div style={{ fontSize: 12, opacity: 0.8 }}>ScreenCaptureKit</div>
                      <div style={{ fontSize: 22, fontWeight: 800, marginTop: 8 }}>无遮挡圆角抠窗</div>
                      <div style={{ fontSize: 12, marginTop: 6, opacity: 0.85 }}>支持一键去除窗口阴影</div>
                    </div>
                    <div style={{ height: 120, borderRadius: 14, background: '#f1f5f9', padding: 16, color: '#0f172a' }}>
                      <div style={{ fontSize: 13, fontWeight: 700 }}>敏感信息打码区</div>
                      <div
                        style={{
                          marginTop: 12,
                          height: 44,
                          borderRadius: 8,
                          backgroundImage: 'repeating-conic-gradient(#cbd5e1 0% 25%, #94a3b8 0% 50%)',
                          backgroundSize: '12px 12px',
                        }}
                      />
                    </div>
                  </div>
                  <div style={{ marginTop: 18, height: 110, borderRadius: 14, background: '#f8fafc', border: '1px solid #e2e8f0', padding: 16, display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
                    <div>
                      <div style={{ fontSize: 16, fontWeight: 700, color: '#0f172a' }}>实时矢量标注画布</div>
                      <div style={{ fontSize: 13, color: '#64748b', marginTop: 4 }}>矩形 · 箭头 · 荧光笔 · 马赛克 · 聚光灯 · 序号</div>
                    </div>
                    <KeycapBadge keys={['C', '取色']} theme="pure-frost" />
                  </div>
                </div>

                {/* Live Selection Marquee + Vector Arrow + True 9x9 Magnified Pixel Loupe */}
                <div
                  style={{
                    position: 'absolute',
                    left: 44,
                    top: 62,
                    width: 680 * cropDraw,
                    height: 318 * cropDraw,
                    borderRadius: 18,
                    border: '2.5px solid #0066dc',
                    boxShadow: '0 0 0 9999px rgba(15, 23, 42, 0.22)',
                    pointerEvents: 'none',
                  }}
                >
                  {/* Circular 9x9 Pixel-Grid Magnifier Loupe */}
                  <div
                    style={{
                      position: 'absolute',
                      right: -46,
                      top: -42,
                      display: 'flex',
                      flexDirection: 'column',
                      alignItems: 'center',
                      gap: 6,
                    }}
                  >
                    <div
                      style={{
                        position: 'relative',
                        width: 82,
                        height: 82,
                        borderRadius: '50%',
                        border: '3px solid #ffffff',
                        boxShadow: '0 12px 28px rgba(15,23,42,0.42), 0 0 0 1.5px #0066dc',
                        overflow: 'hidden',
                        display: 'grid',
                        gridTemplateColumns: 'repeat(7, 1fr)',
                        gridTemplateRows: 'repeat(7, 1fr)',
                        background: '#0ea5e9',
                      }}
                    >
                      {Array.from({ length: 49 }).map((_, idx) => {
                        const row = Math.floor(idx / 7);
                        const col = idx % 7;
                        const isCenter = row === 3 && col === 3;
                        const palette = ['#0284c7', '#0ea5e9', '#38bdf8', '#7dd3fc', '#6366f1', '#818cf8'];
                        return (
                          <div
                            key={idx}
                            style={{
                              background: isCenter ? '#38bdf8' : palette[(row + col) % palette.length],
                              border: isCenter ? '1.5px solid #ffffff' : '0.5px solid rgba(255,255,255,0.22)',
                            }}
                          />
                        );
                      })}
                    </div>
                    <div
                      style={{
                        padding: '4px 10px',
                        borderRadius: 8,
                        background: '#0f172a',
                        color: '#fff',
                        fontFamily: FONT_MONO,
                        fontSize: 11.5,
                        display: 'flex',
                        alignItems: 'center',
                        gap: 6,
                        boxShadow: '0 8px 18px rgba(0,0,0,0.35)',
                        whiteSpace: 'nowrap',
                      }}
                    >
                      <span style={{ width: 10, height: 10, borderRadius: 3, background: '#38bdf8', border: '1px solid #fff' }} />
                      #38BDF8 · 按 C 复制
                    </div>
                  </div>

                  {/* Animated Annotation Arrow SVG */}
                  {arrowDraw > 0.05 && (
                    <svg width="240" height="110" style={{ position: 'absolute', left: 250, top: 70, overflow: 'visible' }}>
                      <path
                        d="M 10 90 Q 95 20 200 35"
                        fill="none"
                        stroke="#ef4444"
                        strokeWidth="5"
                        strokeLinecap="round"
                        strokeDasharray="260"
                        strokeDashoffset={260 * (1 - arrowDraw)}
                      />
                      <circle cx="14" cy="90" r="14" fill="#ef4444" opacity={arrowDraw} />
                      <text x="14" y="95" textAnchor="middle" fill="#fff" fontSize="13" fontWeight="700" opacity={arrowDraw}>
                        1
                      </text>
                    </svg>
                  )}
                </div>

                {/* Animated Capture Cursor */}
                <AnimatedCursor
                  x={44 + 680 * cropDraw - 10}
                  y={62 + 318 * cropDraw - 10}
                  clicking={frame >= 150 && frame <= 165}
                  opacity={clampLerp(frame, [20, 45], [0, 1]) * clampLerp(frame, [470, 520], [1, 0])}
                />

                {/* Bottom Floating iOS Liquid Glass Capture Toolbar */}
                <div
                  style={{
                    position: 'absolute',
                    left: '50%',
                    bottom: 20,
                    transform: 'translateX(-50%)',
                    padding: '9px 18px',
                    borderRadius: RADII.pill,
                    background: 'rgba(255, 255, 255, 0.94)',
                    border: '1px solid rgba(15, 23, 42, 0.12)',
                    boxShadow: t.panelShadow,
                    display: 'flex',
                    alignItems: 'center',
                    gap: 14,
                    fontSize: 13,
                    fontWeight: 600,
                    color: '#0f172a',
                    whiteSpace: 'nowrap',
                  }}
                >
                  <span>矩形</span>
                  <span style={{ color: '#ef4444' }}>● 箭头</span>
                  <span>马赛克</span>
                  <span>荧光笔</span>
                  <span>序号</span>
                  <span style={{ width: 1, height: 16, background: '#cbd5e1' }} />
                  <span style={{ color: '#0066dc', display: 'inline-flex', alignItems: 'center', gap: 5 }}>
                    <IconPin size={14} color="#0066dc" /> 钉在屏幕最上层
                  </span>
                </div>
                </div>
              </div>

              {/* Right Floating Pinned Card Showcase */}
              <div style={{ display: 'flex', flexDirection: 'column', gap: 20 }}>
                <div
                  style={{
                    padding: 24,
                    borderRadius: 24,
                    background: 'rgba(255,255,255,0.94)',
                    border: '1.5px solid rgba(0, 102, 220, 0.35)',
                    boxShadow: t.panelShadow,
                    transform: `translateY(${(1 - pinFloat) * 10}px)`,
                    opacity: 0.7 + pinFloat * 0.3,
                  }}
                >
                  <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', marginBottom: 14 }}>
                    <span style={{ fontFamily: FONT_MONO, fontSize: 12, fontWeight: 700, color: '#0066dc' }}>
                      PINNED OVERLAY · 1:1 RETINA
                    </span>
                    <KeycapBadge keys={['T', '穿透对照']} theme="pure-frost" size="sm" />
                  </div>
                  <div style={{ fontSize: 22, fontWeight: 800, color: '#0a1120', marginBottom: 8 }}>
                    截图直接钉在屏幕最上层
                  </div>
                  <div style={{ fontSize: 14.5, color: '#475569', lineHeight: 1.65 }}>
                    支持滚轮无级缩放、首击丝滑拖拽、按 <code style={{ fontFamily: FONT_MONO }}>T</code> 开启半透明点击穿透，边对照参考图边写代码或做设计。
                  </div>
                </div>

                <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 14 }}>
                  <div style={{ padding: 18, borderRadius: 18, background: t.bgCard, border: `1px solid ${t.rimOuter}`, boxShadow: t.cardShadow }}>
                    <div style={{ fontFamily: FONT_MONO, fontSize: 22, fontWeight: 800, color: '#0066dc' }}>10 种</div>
                    <div style={{ fontSize: 13.5, color: t.textSecondary, marginTop: 4 }}>实时矢量标注与取色</div>
                  </div>
                  <div style={{ padding: 18, borderRadius: 18, background: t.bgCard, border: `1px solid ${t.rimOuter}`, boxShadow: t.cardShadow }}>
                    <div style={{ fontFamily: FONT_MONO, fontSize: 22, fontWeight: 800, color: '#4f46e5' }}>混合 DPI</div>
                    <div style={{ fontSize: 13.5, color: t.textSecondary, marginTop: 4 }}>跨多屏逐屏无损直裁</div>
                  </div>
                </div>
              </div>
            </div>
            </CameraStage>
          )}

          {/* 2. ZERO-FFMPEG NATIVE GIF RECORDING (⌥G) */}
          {stage === 'gif' && (
            <CameraStage enterFrame={580} breathScale={0.008} tiltDeg={0.6}>
            <div style={{ width: '100%', display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 28 }}>
              {/* Dynamic Island Floating HUD */}
              <div
                style={{
                  padding: '13px 26px',
                  borderRadius: RADII.pill,
                  background: 'rgba(10, 12, 26, 0.94)',
                  border: '1px solid rgba(255,255,255,0.22)',
                  boxShadow: '0 22px 48px rgba(0,0,0,0.65), 0 0 36px rgba(244, 63, 94, 0.28)',
                  display: 'flex',
                  alignItems: 'center',
                  gap: 20,
                  transform: `scale(${spr(frame, 595, SPRING_GLASS)})`,
                }}
              >
                <span
                  style={{
                    width: 12,
                    height: 12,
                    borderRadius: '50%',
                    background: '#f43f5e',
                    boxShadow: `0 0 ${12 + Math.sin(frame * 0.2) * 6}px #f43f5e`,
                  }}
                />
                <span style={{ fontFamily: FONT_MONO, fontSize: 18, fontWeight: 700, color: '#fff' }}>
                  REC 00:0{Math.min(9, Math.floor(gifSec))}.{Math.floor((gifSec % 1) * 10)}
                </span>
                <span style={{ fontFamily: FONT_MONO, fontSize: 13, color: '#67e8f9' }}>
                  SCStream · 15 fps · 静止帧差值压缩
                </span>
                <span
                  style={{
                    padding: '5px 14px',
                    borderRadius: RADII.pill,
                    background: '#f43f5e',
                    color: '#fff',
                    fontSize: 13,
                    fontWeight: 700,
                  }}
                >
                  完成并复制 GIF
                </span>
              </div>

              {/* Dashed Passthrough Recording Frame */}
              <div
                style={{
                  width: 1080,
                  height: 360,
                  borderRadius: 24,
                  border: '2.5px dashed #38bdf8',
                  background: 'rgba(16, 18, 42, 0.62)',
                  padding: 34,
                  display: 'grid',
                  gridTemplateColumns: '1.2fr 0.8fr',
                  gap: 30,
                  alignItems: 'center',
                  boxShadow: '0 0 60px rgba(56, 189, 248, 0.14)',
                }}
              >
                <div>
                  <div style={{ fontFamily: FONT_MONO, fontSize: 12.5, color: '#34d399', marginBottom: 10 }}>
                    ZERO FFMPEG · IMAGEIO STREAMING GIF89A
                  </div>
                  <div style={{ fontSize: 34, fontWeight: 800, color: '#fff', lineHeight: 1.25 }}>
                    无需安装 FFmpeg，
                    <br />
                    灵动岛直录轻巧 GIF 动图。
                  </div>
                  <div style={{ fontSize: 16.5, color: t.textSecondary, marginTop: 14, lineHeight: 1.65 }}>
                    支持窗口自动吸附或跨屏自由框选；录制边界采用 <code style={{ fontFamily: FONT_MONO, color: '#67e8f9' }}>sharingType = .none</code> 绝不入镜，自动压缩静止帧体积，录完直接粘贴发文档与聊天。
                  </div>
                </div>

                {/* Live Frame Compression Visualizer */}
                <div style={{ display: 'flex', flexDirection: 'column', gap: 14 }}>
                  <div style={{ padding: 18, borderRadius: 18, background: t.bgCard, border: `1px solid ${t.rimOuter}` }}>
                    <div style={{ fontFamily: FONT_MONO, fontSize: 12, color: t.textTertiary, marginBottom: 10 }}>
                      STATIC FRAME DELTA COMPRESSION
                    </div>
                    <div style={{ display: 'flex', alignItems: 'flex-end', gap: 6, height: 84 }}>
                      {[42, 76, 68, 22, 18, 18, 82, 74, 24, 20, 64, 52].map((h, i) => {
                        const pulse = Math.sin(frame * 0.12 + i) * 8;
                        return (
                          <div
                            key={i}
                            style={{
                              flex: 1,
                              height: `${Math.max(14, h + pulse)}%`,
                              borderRadius: 6,
                              background: h > 40 ? 'linear-gradient(180deg,#38bdf8,#7c5cfc)' : 'rgba(52,211,153,0.55)',
                            }}
                          />
                        );
                      })}
                    </div>
                    <div style={{ marginTop: 10, display: 'flex', justifyContent: 'space-between', fontFamily: FONT_MONO, fontSize: 12, color: '#34d399' }}>
                      <span>原体积 4.6 MB</span>
                      <span>→ 压后 680 KB</span>
                    </div>
                  </div>
                </div>
              </div>
            </div>
            </CameraStage>
          )}

          {/* 3. OFFLINE VISION OCR (⌥O) */}
          {stage === 'ocr' && (
            <CameraStage enterFrame={1040} breathScale={0.008} tiltDeg={0.7}>
            <div style={{ width: '100%', display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 36, alignItems: 'center' }}>
              {/* Left Source Screen Region with Scanning Beam */}
              <div
                style={{
                  position: 'relative',
                  height: 440,
                  borderRadius: 24,
                  background: t.bgCard,
                  border: `1.5px solid ${t.rimSelected}`,
                  boxShadow: t.panelShadow,
                  padding: 34,
                  overflow: 'hidden',
                }}
              >
                <div style={{ fontFamily: FONT_MONO, fontSize: 12, color: '#67e8f9', marginBottom: 18 }}>
                  SCREEN REGION · APPLE VISION (CPU BOUND)
                </div>
                <div style={{ fontSize: 23, lineHeight: 1.75, color: 'rgba(248,250,255,0.88)', fontWeight: 500 }}>
                  「一触流光，用完即焚」
                  <br />
                  Lucent runs 100% offline Apple Vision OCR for Chinese, English &amp; QR codes in sub-second latency.
                  <br />
                  无需联网上传图片，完整守护屏幕隐私。
                </div>

                {/* Luminous Horizontal Optical Scan Beam */}
                {!ocrDone && (
                  <div
                    style={{
                      position: 'absolute',
                      left: 0,
                      right: 0,
                      top: `${ocrScanY}%`,
                      height: 4,
                      background: 'linear-gradient(90deg, transparent, #22d3ee, #ffffff, #f472b6, transparent)',
                      boxShadow: '0 0 28px 10px rgba(34, 211, 238, 0.55)',
                    }}
                  />
                )}
              </div>

              {/* Right Extracted Editable Result Window */}
              <div
                style={{
                  height: 440,
                  borderRadius: 24,
                  background: t.bgPanelSolid,
                  border: `1px solid ${ocrDone ? 'rgba(52, 211, 153, 0.55)' : t.rimOuter}`,
                  boxShadow: t.panelShadow,
                  padding: 32,
                  display: 'flex',
                  flexDirection: 'column',
                  justifyContent: 'space-between',
                }}
              >
                <div>
                  <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: 16 }}>
                    <span style={{ fontFamily: FONT_MONO, fontSize: 12.5, color: '#34d399', fontWeight: 700 }}>
                      {ocrDone ? '✓ 离线识字完成 · 0.24s' : 'VISION 引擎识别中...'}
                    </span>
                    <KeycapBadge keys={['⌥O']} size="sm" />
                  </div>
                  <div
                    style={{
                      padding: 20,
                      borderRadius: 16,
                      background: t.bgWell,
                      border: `1px solid ${t.rimOuter}`,
                      fontSize: 17.5,
                      lineHeight: 1.7,
                      color: '#fff',
                      opacity: ocrDone ? 1 : 0.35,
                    }}
                  >
                    一触流光，用完即焚 — Lucent runs 100% offline Apple Vision OCR for Chinese, English &amp; QR codes in sub-second latency. 无需联网上传图片，完整守护屏幕隐私。
                  </div>
                </div>

                <div style={{ display: 'flex', gap: 12 }}>
                  {['复制纯文本', '智能合并换行', '一键送往「流光译站」翻译'].map((btn, i) => (
                    <div
                      key={btn}
                      style={{
                        padding: '10px 16px',
                        borderRadius: 12,
                        background: i === 2 ? t.accentGradient : t.bgPill,
                        color: '#fff',
                        fontSize: 13.5,
                        fontWeight: 600,
                      }}
                    >
                      {btn}
                    </div>
                  ))}
                </div>
              </div>
            </div>
            </CameraStage>
          )}

          {/* 4. 120Hz PHYSICAL MOUSE SMOOTH SCROLL SPLIT COMPARISON + LIVE TELEMETRY WAVEFORM */}
          {stage === 'mouse' && (
            <CameraStage enterFrame={1480} breathScale={0.007} tiltDeg={0.5}>
            <div style={{ width: '100%', display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 30, alignItems: 'stretch' }}>
              {[
                {
                  title: 'macOS 原生外接鼠标滚轮',
                  badge: '生硬步进跳格 · 方向与触控板绑死',
                  offset: steppedOffset,
                  smooth: false,
                  accent: '#dc2626',
                },
                {
                  title: 'Lucent 120Hz 物理鼠标平滑引擎',
                  badge: '仅平滑物理鼠标 · 保留触控板自然滚动',
                  offset: smoothOffset,
                  smooth: true,
                  accent: '#0066dc',
                },
              ].map((col) => {
                const wavePhase = (mouseElapsed * 1.4) % 1;
                return (
                <div
                  key={col.title}
                  style={{
                    borderRadius: 26,
                    background: 'rgba(255,255,255,0.94)',
                    border: `1.5px solid ${col.smooth ? 'rgba(0, 102, 220, 0.45)' : 'rgba(15, 23, 42, 0.10)'}`,
                    boxShadow: t.panelShadow,
                    padding: '22px 24px',
                    display: 'flex',
                    flexDirection: 'column',
                    gap: 12,
                  }}
                >
                  <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
                    <div style={{ fontSize: 21, fontWeight: 800, color: '#0a1120' }}>{col.title}</div>
                    <span
                      style={{
                        padding: '5px 12px',
                        borderRadius: RADII.pill,
                        background: col.smooth ? 'rgba(0,102,220,0.10)' : 'rgba(220,38,38,0.09)',
                        color: col.accent,
                        fontSize: 12.5,
                        fontWeight: 700,
                      }}
                    >
                      {col.smooth ? '120Hz 丝滑曲线' : '离散跳变'}
                    </span>
                  </div>
                  <div style={{ fontSize: 14, color: '#475569' }}>{col.badge}</div>

                  {/* Scrolling Viewport */}
                  <div
                    style={{
                      position: 'relative',
                      height: 274,
                      borderRadius: 18,
                      background: '#f1f5fc',
                      border: '1px solid rgba(15,23,42,0.08)',
                      overflow: 'hidden',
                      padding: 16,
                      maskImage: 'linear-gradient(180deg, transparent 0%, black 11%, black 89%, transparent 100%)',
                      WebkitMaskImage:
                        'linear-gradient(180deg, transparent 0%, black 11%, black 89%, transparent 100%)',
                    }}
                  >
                    <div style={{ transform: `translateY(-${col.offset % 420}px)`, display: 'flex', flexDirection: 'column', gap: 12 }}>
                      {Array.from({ length: 12 }).map((_, i) => (
                        <div
                          key={i}
                          style={{
                            height: 58,
                            borderRadius: 14,
                            background: '#ffffff',
                            border: '1px solid rgba(15,23,42,0.07)',
                            padding: '0 18px',
                            display: 'flex',
                            alignItems: 'center',
                            justifyContent: 'space-between',
                          }}
                        >
                          <div style={{ display: 'flex', alignItems: 'center', gap: 12 }}>
                            <span
                              style={{
                                width: 10,
                                height: 10,
                                borderRadius: '50%',
                                background: col.smooth ? '#0066dc' : '#94a3b8',
                              }}
                            />
                            <span style={{ fontSize: 15, fontWeight: 600, color: '#0f172a' }}>
                              文档段落 #{i + 1} · {col.smooth ? '高帧率惯性阻尼插值' : '逐格机械硬跳'}
                            </span>
                          </div>
                          <span style={{ fontFamily: FONT_MONO, fontSize: 12, color: '#64748b' }}>
                            {col.smooth ? '⇧横向 · ⌥加速' : 'step +86px'}
                          </span>
                        </div>
                      ))}
                    </div>
                  </div>

                  {/* Live Telemetry Curve: Discrete Staircase vs 120Hz Smooth Spline */}
                  <div
                    style={{
                      padding: '10px 14px',
                      borderRadius: 14,
                      background: '#f8fafd',
                      border: '1px solid rgba(15,23,42,0.08)',
                      display: 'flex',
                      alignItems: 'center',
                      justifyContent: 'space-between',
                      gap: 14,
                    }}
                  >
                    <span style={{ fontFamily: FONT_MONO, fontSize: 11.5, fontWeight: 700, color: col.accent, whiteSpace: 'nowrap' }}>
                      {col.smooth ? '120Hz SPLINE' : 'DISCRETE STEP'}
                    </span>
                    <svg width="460" height="44" viewBox="0 0 460 44" style={{ flex: 1 }}>
                      <line x1="0" y1="36" x2="460" y2="36" stroke="#e2e8f0" strokeWidth="1" />
                      {col.smooth ? (
                        <>
                          <path
                            d="M 4 36 C 85 36, 110 24, 185 20 C 260 16, 330 8, 456 6"
                            fill="none"
                            stroke="#0066dc"
                            strokeWidth="3"
                            strokeLinecap="round"
                          />
                          <circle cx={4 + wavePhase * 452} cy={36 - wavePhase * 30} r="5.5" fill="#0066dc" />
                        </>
                      ) : (
                        <>
                          <path
                            d="M 4 36 H 96 V 26 H 192 V 16 H 296 V 6 H 456"
                            fill="none"
                            stroke="#dc2626"
                            strokeWidth="2.8"
                            strokeLinejoin="miter"
                          />
                          <circle
                            cx={4 + Math.floor(wavePhase * 4) * 100 + 20}
                            cy={36 - Math.floor(wavePhase * 4) * 10}
                            r="5"
                            fill="#dc2626"
                          />
                        </>
                      )}
                    </svg>
                  </div>
                </div>
                );
              })}
            </div>
            </CameraStage>
          )}

          {/* 5. ON-DEMAND TOOLBOX: FILE WORKBENCH + CINEMA + PULSE + NETWORK */}
          {stage === 'toolbox' && (
            <CameraStage enterFrame={2060} breathScale={0.008} tiltDeg={0.6}>
            <div style={{ width: '100%', display: 'grid', gridTemplateColumns: 'repeat(2, 1fr)', gap: 22 }}>
              {[
                {
                  key: '⌥E',
                  title: '双栏文件整理台',
                  desc: '跨栏拖拽复制移动、液态蓝框选、批量重命名预检；遇脏 NTFS 移动硬盘严格只读护航',
                  badge: 'NTFS 只读护航 · 关窗即净',
                  grad: 'linear-gradient(135deg,#10b981,#06b6d4)',
                  icon: <IconFolder size={20} />,
                  extra: 'SSD-Work  ⇄  Samsung-T7 (NTFS RO)',
                  chart: 'none' as const,
                },
                {
                  key: '⌥M',
                  title: '芯片脉搏悬浮窗',
                  desc: 'Apple Silicon 大小核实时负载、整机功耗（W）与内存压力 Sparkline 曲线，三边贴边隐藏',
                  badge: 'P-Core 18% · 整机 9.4W · 38°C',
                  grad: 'linear-gradient(135deg,#0ea5e9,#6366f1)',
                  icon: <IconCpu size={20} />,
                  extra: '',
                  chart: 'cpu' as const,
                },
                {
                  key: '⌥N',
                  title: '软件网速与去向透视',
                  desc: '免 Root 实时洞察每个 App 当前上下行速度与远程 Socket 去向，顺手安全清理应用缓存',
                  badge: '↓ 28.4 MB/s · ↑ 1.9 MB/s',
                  grad: 'linear-gradient(135deg,#a855f7,#ec4899)',
                  icon: <IconNetwork size={20} />,
                  extra: '',
                  chart: 'net' as const,
                },
                {
                  key: '4K',
                  title: '纯原生阅读与 4K 影院小窗',
                  desc: '零 WKWebView 瞬开 Markdown 大纲与无损大图；支持 4K HEVC 硬解、520×300 置顶小窗与同目录连播',
                  badge: 'HEVC 硬解 · 关窗归还内存',
                  grad: 'linear-gradient(135deg,#f59e0b,#ef4444)',
                  icon: <IconPlay size={18} />,
                  extra: '520×300 Picture-in-Picture · 同目录连播',
                  chart: 'none' as const,
                },
              ].map((card, i) => {
                const cp = spr(frame, 2075 + i * 8, SPRING_GLASS);
                const waveShift = (frame - 2060) * 0.08;
                const buildSpark = (amp: number, base: number, freq: number) =>
                  Array.from({ length: 24 })
                    .map((_, xi) => {
                      const x = (xi / 23) * 420;
                      const y = base - Math.abs(Math.sin(xi * freq + waveShift) * amp + Math.cos(xi * 0.4 - waveShift * 0.6) * (amp * 0.45));
                      return `${xi === 0 ? 'M' : 'L'} ${x.toFixed(1)} ${y.toFixed(1)}`;
                    })
                    .join(' ');
                return (
                  <div
                    key={card.title}
                    style={{
                      padding: 26,
                      borderRadius: 24,
                      background: t.bgCard,
                      border: `1px solid ${t.rimOuter}`,
                      boxShadow: t.cardShadow,
                      opacity: cp,
                      transform: `translateY(${(1 - cp) * 24}px)`,
                      display: 'flex',
                      flexDirection: 'column',
                      justifyContent: 'space-between',
                      gap: 14,
                    }}
                  >
                    <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between' }}>
                      <div style={{ display: 'flex', alignItems: 'center', gap: 14 }}>
                        <SquircleBadge gradient={card.grad} size={46}>
                          {card.icon}
                        </SquircleBadge>
                        <div>
                          <div style={{ fontSize: 21, fontWeight: 800, color: '#fff' }}>{card.title}</div>
                          <div style={{ fontFamily: FONT_MONO, fontSize: 12, color: '#67e8f9', marginTop: 2 }}>
                            {card.badge}
                          </div>
                        </div>
                      </div>
                      <KeycapBadge keys={[card.key]} size="md" />
                    </div>
                    <div style={{ fontSize: 15, color: t.textSecondary, lineHeight: 1.6 }}>{card.desc}</div>
                    <div
                      style={{
                        padding: card.chart === 'none' ? '10px 14px' : '8px 14px',
                        borderRadius: 12,
                        background: t.bgWell,
                        border: `1px solid ${t.rimOuter}`,
                        fontFamily: FONT_MONO,
                        fontSize: 12.5,
                        color: '#34d399',
                        display: 'flex',
                        alignItems: 'center',
                        justifyContent: 'space-between',
                        gap: 8,
                        minHeight: 42,
                      }}
                    >
                      {card.chart === 'none' ? (
                        <span style={{ display: 'inline-flex', alignItems: 'center', gap: 8 }}>
                          <IconCheck size={14} color="#34d399" /> {card.extra}
                        </span>
                      ) : (
                        <svg width="100%" height="32" viewBox="0 0 420 32" preserveAspectRatio="none" style={{ display: 'block' }}>
                          <path
                            d={`${buildSpark(card.chart === 'cpu' ? 14 : 16, 28, card.chart === 'cpu' ? 0.55 : 0.42)} L 420 32 L 0 32 Z`}
                            fill={card.chart === 'cpu' ? 'rgba(56, 189, 248, 0.22)' : 'rgba(236, 72, 153, 0.22)'}
                          />
                          <path
                            d={buildSpark(card.chart === 'cpu' ? 14 : 16, 28, card.chart === 'cpu' ? 0.55 : 0.42)}
                            fill="none"
                            stroke={card.chart === 'cpu' ? '#38bdf8' : '#f472b6'}
                            strokeWidth="2.4"
                            strokeLinecap="round"
                          />
                        </svg>
                      )}
                    </div>
                  </div>
                );
              })}
            </div>
            </CameraStage>
          )}
        </div>
      </div>

      <BottomCaptionBar beats={CAPTIONS} frame={frame} theme={theme} />
    </AbsoluteFill>
  );
};
