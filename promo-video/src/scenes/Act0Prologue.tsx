import React from 'react';
import { AbsoluteFill, Easing, interpolate, useCurrentFrame } from 'remotion';
import { AuroraBackdrop } from '../components/AuroraBackdrop';
import { BrandKeycap3D } from '../components/BrandKeycap3D';
import { IconCrop, IconGif, IconScanText } from '../components/Icons';
import { KeycapBadge } from '../components/KeycapBadge';
import { BottomCaptionBar, CaptionBeat } from '../components/KineticCaption';
import { LiquidGlassPanel } from '../components/LiquidGlassPanel';
import { BespokeDockIcon } from '../components/MacChrome';
import { clampLerp, spr, SPRING_BOUNCY, SPRING_GENTLE, SPRING_GLASS } from '../design/motion';
import { FONT_MONO, FONT_SANS, PRISM_PULSE, RADII } from '../design/tokens';

const MOTES = [
  { angle: -0.52, dist: 245, size: 8, color: '#22d3ee' },
  { angle: 0.35, dist: 270, size: 7, color: '#f472b6' },
  { angle: 1.18, dist: 215, size: 6.5, color: '#a855f7' },
  { angle: 2.05, dist: 235, size: 7.5, color: '#34d399' },
  { angle: 2.72, dist: 262, size: 7, color: '#38bdf8' },
  { angle: -2.35, dist: 252, size: 8, color: '#818cf8' },
  { angle: -1.42, dist: 210, size: 6.5, color: '#f472b6' },
  { angle: -0.10, dist: 285, size: 6, color: '#67e8f9' },
];

const CAPTIONS: CaptionBeat[] = [
  { start: 230, end: 500, tag: 'APPLE SILICON', text: '专为 Apple Silicon Mac 打造的纯原生快捷效率中枢' },
  { start: 530, end: 840, tag: '⌥ Space', text: '一触唤起 880 × 544 零跳动液态玻璃中枢，用完即焚绝不拖慢电脑' },
  { start: 870, end: 1185, tag: '~10 MB', text: '100% Swift 6 原生直连 · 零第三方依赖 · 从日常到极客全随你定' },
];

export const Act0Prologue: React.FC = () => {
  const frame = useCurrentFrame();

  // Phase 1 (0..180): Keycap descends into obsidian prism aura & ⌥Space presses at frame 165
  const heroEnter = spr(frame, 18, SPRING_GENTLE);
  const pressDown = clampLerp(frame, [154, 170], [0, 1], Easing.in(Easing.cubic));
  const pressRelease = clampLerp(frame, [170, 210], [0, 1], Easing.out(Easing.back(1.8)));
  const pressedAmount = Math.max(0, pressDown - pressRelease);

  // Phase 2 (180..420): Chromatic shockwave rings + 8 glowing prism motes + slogan plaque
  const rippleProgress = clampLerp(frame, [176, 330], [0, 1], Easing.out(Easing.cubic));
  const rippleOpacity =
    frame < 176 ? 0 : clampLerp(frame, [176, 195], [0, 1]) * clampLerp(frame, [260, 355], [1, 0]);

  const titleEnter = spr(frame, 205, SPRING_GLASS);
  const shimmerX = clampLerp(frame, [240, 390], [-120, 220], Easing.inOut(Easing.quad));

  // Phase 3 (420..820): Morph silhouette expands from 340x180 -> 880x544 liquid glass panel
  const morphPhase = clampLerp(frame, [415, 485], [0, 1], Easing.inOut(Easing.cubic));
  const heroStageOut = clampLerp(frame, [405, 465], [1, 0]);
  const panelEnter = spr(frame, 450, SPRING_GLASS);

  // Phase 4 (820..1224): Hero panel settles left/center slightly elevated with 4 crisp stat pillars
  const pillarBase = 780;
  const stats = [
    { value: 'Swift 6', label: '纯原生 arm64 框架直连', accent: '#38bdf8' },
    { value: '~10 MB', label: '极轻安装包 · 0 第三方依赖', accent: '#a78bfa' },
    { value: '880×544', label: '恒定零跳动液态玻璃面板', accent: '#f472b6' },
    { value: '20 MCP', label: '内置 AI 工具一句话定制', accent: '#34d399' },
  ];

  const orbitAngle = -0.68 + frame * 0.022;
  const tiltDeg = (1 - heroEnter) * 22 + pressedAmount * 9;

  const panelYShift = clampLerp(frame, [740, 825], [0, -52], Easing.inOut(Easing.cubic));
  const panelScale = clampLerp(frame, [740, 825], [1.06, 0.90], Easing.inOut(Easing.cubic));

  return (
    <AbsoluteFill style={{ fontFamily: FONT_SANS }}>
      <AuroraBackdrop theme="prism-pulse" intensity={0.78 + rippleProgress * 0.35} />

      {/* Subtle Rotating Optical Astrolabe Rings Behind Opening Hero */}
      {heroStageOut > 0.01 && (
        <AbsoluteFill style={{ alignItems: 'center', justifyContent: 'center', pointerEvents: 'none', opacity: heroStageOut * heroEnter * 0.55 }}>
          <svg width="760" height="760" viewBox="0 0 760 760" style={{ transform: `translateY(-54px) rotate(${frame * 0.14}deg)` }}>
            <circle cx="380" cy="380" r="248" fill="none" stroke="rgba(103, 232, 249, 0.20)" strokeWidth="1.2" strokeDasharray="6 10" />
            <circle cx="380" cy="380" r="326" fill="none" stroke="rgba(167, 139, 250, 0.16)" strokeWidth="1" strokeDasharray="3 14" />
            <circle cx="380" cy="132" r="4" fill="#67e8f9" />
            <circle cx="628" cy="380" r="3.5" fill="#f472b6" />
          </svg>
        </AbsoluteFill>
      )}

      {/* Center Chromatic Shockwave & 8 Prism Motes (faithful to LaunchIntroOverlayView.swift) */}
      {rippleOpacity > 0.01 && (
        <AbsoluteFill style={{ alignItems: 'center', justifyContent: 'center', pointerEvents: 'none' }}>
          <div
            style={{
              position: 'absolute',
              width: 170 + rippleProgress * 720,
              height: 170 + rippleProgress * 460,
              borderRadius: 56 + rippleProgress * 34,
              border: `${Math.max(1, 3.2 * (1 - rippleProgress))}px solid rgba(103, 232, 249, 0.85)`,
              boxShadow: '0 0 42px rgba(124, 92, 252, 0.45), inset 0 0 28px rgba(244, 114, 182, 0.32)',
              opacity: rippleOpacity,
              transform: 'translateY(-48px)',
            }}
          />
          <div
            style={{
              position: 'absolute',
              width: 140 + rippleProgress * 520,
              height: 140 + rippleProgress * 520,
              borderRadius: '50%',
              border: `${Math.max(0.8, 2 * (1 - rippleProgress))}px solid rgba(244, 114, 182, 0.72)`,
              opacity: rippleOpacity * 0.85,
              transform: 'translateY(-48px)',
            }}
          />
          {MOTES.map((m, idx) => {
            const dist = m.dist * (0.28 + rippleProgress * 0.92);
            const mx = Math.cos(m.angle) * dist;
            const my = -48 + Math.sin(m.angle) * dist * 0.68;
            return (
              <div
                key={idx}
                style={{
                  position: 'absolute',
                  width: m.size,
                  height: m.size,
                  borderRadius: '50%',
                  background: m.color,
                  boxShadow: `0 0 14px ${m.color}`,
                  transform: `translate(${mx}px, ${my}px)`,
                  opacity: rippleOpacity * 0.95,
                }}
              />
            );
          })}
        </AbsoluteFill>
      )}

      {/* Morphing Silhouette Outline (340x180 -> 880x544) */}
      {morphPhase > 0.01 && frame < 560 && (
        <AbsoluteFill style={{ alignItems: 'center', justifyContent: 'center', pointerEvents: 'none' }}>
          <div
            style={{
              width: interpolate(morphPhase, [0, 1], [340, 932]),
              height: interpolate(morphPhase, [0, 1], [180, 578]),
              borderRadius: RADII.panel,
              border: '2px solid rgba(103, 232, 249, 0.75)',
              background: 'radial-gradient(circle, rgba(56,189,248,0.14), rgba(168,85,247,0.08), transparent)',
              boxShadow: '0 0 60px rgba(56, 189, 248, 0.25)',
              opacity: clampLerp(frame, [415, 455], [0, 0.95]) * clampLerp(frame, [490, 555], [1, 0]),
            }}
          />
        </AbsoluteFill>
      )}

      {/* Hero Keycap + Slogan Stage (Frames 0..465) */}
      {heroStageOut > 0.01 && (
        <AbsoluteFill
          style={{
            alignItems: 'center',
            justifyContent: 'center',
            opacity: heroStageOut,
            transform: `scale(${1 + (1 - heroStageOut) * 0.08})`,
          }}
        >
          <div
            style={{
              display: 'flex',
              flexDirection: 'column',
              alignItems: 'center',
              gap: 28,
            }}
          >
            {/* 3D Crystal Keycap */}
            <div
              style={{
                transform: `perspective(900px) translateY(${(1 - heroEnter) * 44}px) rotateX(${tiltDeg}deg) scale(${0.66 + heroEnter * 0.34 - pressedAmount * 0.07})`,
                opacity: heroEnter,
              }}
            >
              <BrandKeycap3D
                size={218}
                orbitAngleRad={orbitAngle}
                pressed={pressedAmount}
                gemGlow={1 + rippleOpacity * 0.6}
                showHalo
              />
            </div>

            {/* Tactile ⌥ Space Prompt Pill */}
            <div
              style={{
                display: 'inline-flex',
                alignItems: 'center',
                gap: 12,
                padding: '9px 18px',
                borderRadius: RADII.pill,
                background: 'rgba(18, 20, 44, 0.78)',
                border: `1px solid ${pressedAmount > 0.2 ? 'rgba(103, 232, 249, 0.75)' : PRISM_PULSE.rimOuter}`,
                boxShadow: pressedAmount > 0.2 ? '0 0 32px rgba(56, 189, 248, 0.45)' : PRISM_PULSE.cardShadow,
                opacity: spr(frame, 70, SPRING_GLASS),
              }}
            >
              <KeycapBadge keys={['⌥', 'Space']} size="md" active={pressedAmount > 0.15} />
              <span style={{ fontSize: 15, color: PRISM_PULSE.textSecondary, fontWeight: 500 }}>
                随时一触唤醒
              </span>
            </div>

            {/* Slogan Plaque with Optical Shimmer */}
            <div
              style={{
                display: 'flex',
                flexDirection: 'column',
                alignItems: 'center',
                gap: 14,
                opacity: titleEnter,
                transform: `translateY(${(1 - titleEnter) * 26}px)`,
              }}
            >
              <div
                style={{
                  fontFamily: FONT_MONO,
                  fontSize: 15,
                  letterSpacing: '0.28em',
                  color: '#67e8f9',
                  fontWeight: 600,
                }}
              >
                LUCENT · 流光
              </div>
              <h1
                style={{
                  position: 'relative',
                  margin: 0,
                  fontSize: 78,
                  fontWeight: 800,
                  letterSpacing: '-0.02em',
                  color: '#ffffff',
                  backgroundImage: `linear-gradient(110deg, #f8faff 20%, #67e8f9 ${shimmerX}%, #c084fc ${shimmerX + 18}%, #f8faff 85%)`,
                  WebkitBackgroundClip: 'text',
                  WebkitTextFillColor: 'transparent',
                }}
              >
                一触流光，用完即焚。
              </h1>
              <div
                style={{
                  fontSize: 22,
                  color: PRISM_PULSE.textSecondary,
                  letterSpacing: '0.02em',
                }}
              >
                专为 Apple Silicon Mac 打造的轻巧、可深度定制的原生快捷效率中枢
              </div>
            </div>
          </div>
        </AbsoluteFill>
      )}

      {/* Morph Result: Authentic 880x544 Liquid Glass Hub + 4 Pillar Metrics */}
      {frame >= 445 && (
        <AbsoluteFill style={{ alignItems: 'center', justifyContent: 'center' }}>
          <div
            style={{
              transform: `translateY(${panelYShift}px) scale(${(0.84 + panelEnter * 0.16) * panelScale})`,
              opacity: panelEnter,
            }}
          >
            <LiquidGlassPanel
              theme="prism-pulse"
              dimensionTag="880 × 544 · 0ms Instant Wake"
              placeholder="按一下 ⌥Space，搜软件、全盘文件、剪贴板一步直达..."
            >
              {/* Authentic Default Bento Home Preview Inside Prologue Panel */}
              <div style={{ display: 'flex', flexDirection: 'column', gap: 14, flex: 1 }}>
                <div style={{ display: 'grid', gridTemplateColumns: 'repeat(3, 1fr)', gap: 12 }}>
                  {[
                    { title: '高清截图标注', sub: '⌥A · 多屏原画质 & 钉屏', grad: 'linear-gradient(135deg, #0ea5e9, #6366f1)', icon: <IconCrop size={18} color="#fff" /> },
                    { title: '离线 OCR 识字', sub: '⌥O · Vision 亚秒级识别', grad: 'linear-gradient(135deg, #8b5cf6, #ec4899)', icon: <IconScanText size={18} color="#fff" /> },
                    { title: '区域 GIF 录屏', sub: '⌥G · 零 FFmpeg 灵动岛', grad: 'linear-gradient(135deg, #10b981, #06b6d4)', icon: <IconGif size={18} color="#fff" /> },
                  ].map((tile, i) => {
                    const tp = spr(frame, 475 + i * 7, SPRING_BOUNCY);
                    return (
                      <div
                        key={tile.title}
                        style={{
                          padding: '18px 18px',
                          borderRadius: RADII.bento,
                          background: PRISM_PULSE.bgCard,
                          border: `1px solid ${PRISM_PULSE.rimOuter}`,
                          boxShadow: PRISM_PULSE.cardShadow,
                          transform: `translateY(${(1 - tp) * 18}px) scale(${0.95 + tp * 0.05})`,
                          opacity: tp,
                          display: 'flex',
                          flexDirection: 'column',
                          gap: 8,
                        }}
                      >
                        <div
                          style={{
                            width: 36,
                            height: 36,
                            borderRadius: 11,
                            background: tile.grad,
                            boxShadow: 'inset 0 1px 0 rgba(255,255,255,0.45)',
                            display: 'flex',
                            alignItems: 'center',
                            justifyContent: 'center',
                          }}
                        >
                          {tile.icon}
                        </div>
                        <div style={{ fontSize: 16, fontWeight: 700, color: '#ffffff' }}>{tile.title}</div>
                        <div style={{ fontSize: 12.5, color: PRISM_PULSE.textTertiary }}>{tile.sub}</div>
                      </div>
                    );
                  })}
                </div>

                {/* 8-Slot Omni Dock */}
                <div
                  style={{
                    padding: '14px 16px',
                    borderRadius: RADII.bento,
                    background: PRISM_PULSE.bgWell,
                    border: `1px solid ${PRISM_PULSE.rimOuter}`,
                    display: 'flex',
                    flexDirection: 'column',
                    gap: 10,
                  }}
                >
                  <div
                    style={{
                      display: 'flex',
                      justifyContent: 'space-between',
                      fontSize: 12,
                      color: PRISM_PULSE.textTertiary,
                      fontFamily: FONT_MONO,
                    }}
                  >
                    <span>OMNI DOCK · 混合高频坞</span>
                    <span>App · 插件 · 书签 · 目录</span>
                  </div>
                  <div style={{ display: 'grid', gridTemplateColumns: 'repeat(8, 1fr)', gap: 10 }}>
                    {(
                      [
                        { name: 'Xcode', kind: 'xcode' },
                        { name: 'Cursor', kind: 'cursor' },
                        { name: '流光译站', kind: 'translate' },
                        { name: '闪电提醒', kind: 'remind' },
                        { name: '双栏文件台', kind: 'files' },
                        { name: 'GitHub', kind: 'github' },
                        { name: 'Obsidian', kind: 'obsidian' },
                        { name: '项目目录', kind: 'folder' },
                      ] as const
                    ).map((app, i) => {
                      const ap = spr(frame, 515 + i * 4, SPRING_GLASS);
                      return (
                        <div
                          key={app.name}
                          style={{
                            display: 'flex',
                            flexDirection: 'column',
                            alignItems: 'center',
                            gap: 6,
                            opacity: ap,
                            transform: `translateY(${(1 - ap) * 12}px)`,
                          }}
                        >
                          <BespokeDockIcon kind={app.kind} size={44} />
                          <span style={{ fontSize: 11, color: PRISM_PULSE.textSecondary }}>{app.name}</span>
                        </div>
                      );
                    })}
                  </div>
                </div>

                {/* Named Bookmark Shelf */}
                <div style={{ display: 'flex', alignItems: 'center', gap: 10 }}>
                  <span style={{ fontSize: 12, fontFamily: FONT_MONO, color: PRISM_PULSE.textTertiary }}>
                    常用胶囊架
                  </span>
                  {['Claude Code', 'PR 审查雷达', '!清理 3000 端口', '本地文档库', '芯片脉搏 ⌥M'].map((pill) => (
                    <span
                      key={pill}
                      style={{
                        padding: '6px 13px',
                        borderRadius: RADII.pill,
                        background: PRISM_PULSE.bgPill,
                        border: `1px solid ${PRISM_PULSE.rimOuter}`,
                        fontSize: 12.5,
                        color: PRISM_PULSE.textSecondary,
                      }}
                    >
                      {pill}
                    </span>
                  ))}
                </div>
              </div>
            </LiquidGlassPanel>
          </div>

          {/* 4 Engineering Pillars Emerging Below Panel */}
          {frame >= pillarBase && (
            <div
              style={{
                position: 'absolute',
                bottom: 120,
                display: 'grid',
                gridTemplateColumns: 'repeat(4, 300px)',
                gap: 20,
              }}
            >
              {stats.map((s, idx) => {
                const sp = spr(frame, pillarBase + idx * 8, SPRING_GLASS);
                return (
                  <div
                    key={s.value}
                    style={{
                      padding: '18px 22px',
                      borderRadius: RADII.card,
                      background: 'rgba(15, 16, 36, 0.80)',
                      border: `1px solid ${PRISM_PULSE.rimOuter}`,
                      boxShadow: PRISM_PULSE.cardShadow,
                      opacity: sp,
                      transform: `translateY(${(1 - sp) * 24}px)`,
                      display: 'flex',
                      flexDirection: 'column',
                      gap: 4,
                    }}
                  >
                    <div
                      style={{
                        fontFamily: FONT_MONO,
                        fontSize: 30,
                        fontWeight: 800,
                        color: s.accent,
                      }}
                    >
                      {s.value}
                    </div>
                    <div style={{ fontSize: 14.5, color: PRISM_PULSE.textSecondary }}>{s.label}</div>
                  </div>
                );
              })}
            </div>
          )}
        </AbsoluteFill>
      )}

      <BottomCaptionBar beats={CAPTIONS} frame={frame} theme="prism-pulse" />
    </AbsoluteFill>
  );
};
