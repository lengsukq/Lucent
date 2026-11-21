import React from 'react';
import { AbsoluteFill, Easing, useCurrentFrame } from 'remotion';
import { AuroraBackdrop } from '../components/AuroraBackdrop';
import { BrandKeycap3D } from '../components/BrandKeycap3D';
import { KeycapBadge } from '../components/KeycapBadge';
import { clampLerp, spr, SPRING_GENTLE, SPRING_GLASS } from '../design/motion';
import { FONT_MONO, FONT_SANS, PRISM_PULSE, RADII } from '../design/tokens';

const BADGES = [
  { k: 'Swift 6', v: 'Apple Silicon arm64' },
  { k: '~10 MB', v: '0 第三方依赖' },
  { k: 'Plugin v3.7', v: '7 款原生官方插件' },
  { k: '20 MCP', v: '一句话 AI 共创' },
  { k: 'MIT License', v: '永久免费开源' },
];

export const Act7Finale: React.FC = () => {
  const frame = useCurrentFrame();

  const iconEnter = spr(frame, 18, SPRING_GENTLE);
  const titleEnter = spr(frame, 75, SPRING_GLASS);
  const subEnter = spr(frame, 120, SPRING_GLASS);
  const badgesEnter = spr(frame, 170, SPRING_GLASS);
  const urlEnter = spr(frame, 230, SPRING_GLASS);

  // Subtle closing fade to obsidian stillness at the very end (frames 875..955)
  const endFade = clampLerp(frame, [875, 955], [1, 0], Easing.in(Easing.cubic));
  const shimmerPos = clampLerp(frame, [130, 380], [-80, 180], Easing.inOut(Easing.quad));
  const orbitAngle = -0.68 + frame * 0.018;

  // Converging light motes returning into the crystal keycap
  const converge = clampLerp(frame, [0, 180], [1, 0], Easing.out(Easing.cubic));

  return (
    <AbsoluteFill style={{ fontFamily: FONT_SANS, backgroundColor: '#03040a' }}>
      <AbsoluteFill style={{ opacity: endFade }}>
        <AuroraBackdrop theme="prism-pulse" intensity={0.98} seedOffset={14040} />

        {/* Slow-Rotating Celestial Prism Astrolabe Rings Behind Finale Keycap */}
        <AbsoluteFill style={{ alignItems: 'center', justifyContent: 'center', pointerEvents: 'none', opacity: iconEnter * 0.52 }}>
          <svg width="860" height="860" viewBox="0 0 860 860" style={{ transform: `translateY(-130px) rotate(${frame * 0.12}deg)` }}>
            <circle cx="430" cy="430" r="210" fill="none" stroke="rgba(103, 232, 249, 0.22)" strokeWidth="1.2" strokeDasharray="5 9" />
            <circle cx="430" cy="430" r="295" fill="none" stroke="rgba(167, 139, 250, 0.16)" strokeWidth="1" strokeDasharray="3 12" />
            <circle cx="430" cy="430" r="380" fill="none" stroke="rgba(244, 114, 182, 0.11)" strokeWidth="1" />
            <circle cx="430" cy="220" r="4" fill="#67e8f9" />
            <circle cx="725" cy="430" r="3.5" fill="#f472b6" />
          </svg>
        </AbsoluteFill>

        {/* Converging Starlight Motes */}
        {converge > 0.01 && (
          <AbsoluteFill style={{ alignItems: 'center', justifyContent: 'center', pointerEvents: 'none' }}>
            {Array.from({ length: 12 }).map((_, i) => {
              const angle = (i / 12) * Math.PI * 2 + frame * 0.008;
              const radius = 120 + converge * 460;
              const x = Math.cos(angle) * radius;
              const y = -110 + Math.sin(angle) * radius * 0.62;
              const colors = ['#22d3ee', '#a78bfa', '#f472b6', '#34d399'];
              const c = colors[i % colors.length];
              return (
                <div
                  key={i}
                  style={{
                    position: 'absolute',
                    width: 6,
                    height: 6,
                    borderRadius: '50%',
                    background: c,
                    boxShadow: `0 0 14px ${c}`,
                    transform: `translate(${x}px, ${y}px)`,
                    opacity: converge * 0.9,
                  }}
                />
              );
            })}
          </AbsoluteFill>
        )}

        <AbsoluteFill
          style={{
            alignItems: 'center',
            justifyContent: 'center',
            padding: '0 100px',
          }}
        >
          <div style={{ display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 26 }}>
            {/* Hero 3D Crystal Keycap */}
            <div
              style={{
                transform: `scale(${0.76 + iconEnter * 0.24}) translateY(${(1 - iconEnter) * 28}px)`,
                opacity: iconEnter,
              }}
            >
              <BrandKeycap3D size={196} orbitAngleRad={orbitAngle} gemGlow={1.25} showHalo />
            </div>

            {/* Brand Name & Poetic Slogan */}
            <div
              style={{
                display: 'flex',
                flexDirection: 'column',
                alignItems: 'center',
                gap: 12,
                opacity: titleEnter,
                transform: `translateY(${(1 - titleEnter) * 24}px)`,
              }}
            >
              <div
                style={{
                  fontFamily: FONT_MONO,
                  fontSize: 16,
                  letterSpacing: '0.32em',
                  color: '#67e8f9',
                  fontWeight: 700,
                }}
              >
                LUCENT · 流光
              </div>
              <h1
                style={{
                  margin: 0,
                  fontSize: 74,
                  fontWeight: 800,
                  letterSpacing: '-0.025em',
                  backgroundImage: `linear-gradient(110deg, #f8faff 15%, #67e8f9 ${shimmerPos}%, #c084fc ${shimmerPos + 20}%, #f8faff 88%)`,
                  WebkitBackgroundClip: 'text',
                  WebkitTextFillColor: 'transparent',
                }}
              >
                让每一次按键，如流光掠影。
              </h1>
            </div>

            <div
              style={{
                fontSize: 23,
                color: PRISM_PULSE.textSecondary,
                opacity: subEnter,
                transform: `translateY(${(1 - subEnter) * 16}px)`,
                display: 'flex',
                alignItems: 'center',
                gap: 12,
              }}
            >
              <span>一触流光，用完即焚</span>
              <span style={{ opacity: 0.35 }}>·</span>
              <KeycapBadge keys={['⌥', 'Space']} size="md" />
              <span>立即开启轻盈顺手的 macOS 效率新体验</span>
            </div>

            {/* 5 Core Specification Badges */}
            <div
              style={{
                display: 'flex',
                gap: 14,
                marginTop: 10,
                opacity: badgesEnter,
                transform: `translateY(${(1 - badgesEnter) * 18}px)`,
              }}
            >
              {BADGES.map((b) => (
                <div
                  key={b.k}
                  style={{
                    padding: '13px 20px',
                    borderRadius: 18,
                    background: 'rgba(18, 20, 44, 0.80)',
                    border: `1px solid ${PRISM_PULSE.rimOuter}`,
                    boxShadow: PRISM_PULSE.cardShadow,
                    textAlign: 'center',
                    minWidth: 176,
                  }}
                >
                  <div style={{ fontFamily: FONT_MONO, fontSize: 19, fontWeight: 800, color: '#67e8f9' }}>{b.k}</div>
                  <div style={{ fontSize: 13, color: PRISM_PULSE.textSecondary, marginTop: 4 }}>{b.v}</div>
                </div>
              ))}
            </div>

            {/* Download & Open Source Links Strip */}
            <div
              style={{
                marginTop: 14,
                padding: '14px 30px',
                borderRadius: RADII.pill,
                background: 'rgba(255, 255, 255, 0.06)',
                border: `1px solid ${PRISM_PULSE.rimSelected}`,
                display: 'flex',
                alignItems: 'center',
                gap: 28,
                fontFamily: FONT_MONO,
                fontSize: 16,
                color: '#f8faff',
                opacity: urlEnter,
                transform: `translateY(${(1 - urlEnter) * 14}px)`,
              }}
            >
              <span>GitHub · github.com/lengsukq/Lucent</span>
              <span style={{ width: 1, height: 18, background: 'rgba(255,255,255,0.22)' }} />
              <span style={{ color: '#67e8f9' }}>官网体验 · lengsukq.github.io/Lucent</span>
            </div>
          </div>
        </AbsoluteFill>
      </AbsoluteFill>
    </AbsoluteFill>
  );
};
