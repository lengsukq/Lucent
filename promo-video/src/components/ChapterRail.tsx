import React from 'react';
import { useCurrentFrame } from 'remotion';
import { ACTS, getActiveActIndex, TOTAL_FRAMES } from '../timeline';
import { FONT_MONO, FONT_SANS, getTheme, ThemeMode } from '../design/tokens';
import { clampLerp } from '../design/motion';
import { BrandKeycap3D } from './BrandKeycap3D';

interface ChapterRailProps {
  theme?: ThemeMode;
}

export const ChapterRail: React.FC<ChapterRailProps> = ({ theme = 'prism-pulse' }) => {
  const frame = useCurrentFrame();
  const actIdx = getActiveActIndex(frame);
  const currentAct = ACTS[actIdx];

  // Hide gracefully during opening prologue reveal and final fadeout
  const fadeIn = clampLerp(frame, [900, 960], [0, 1]);
  const fadeOut = clampLerp(frame, [14020, 14090], [1, 0]);
  const opacity = Math.min(fadeIn, fadeOut);
  if (opacity <= 0.01) return null;

  const t = getTheme(theme);
  const progress = Math.min(1, Math.max(0, frame / TOTAL_FRAMES));

  return (
    <>
      {/* Minimal Top-Left Brand Mark */}
      <div
        style={{
          position: 'absolute',
          top: 26,
          left: 38,
          display: 'flex',
          alignItems: 'center',
          gap: 12,
          zIndex: 90,
          opacity,
          fontFamily: FONT_SANS,
        }}
      >
        <BrandKeycap3D size={28} />
        <span
          style={{
            fontSize: 16,
            fontWeight: 700,
            color: t.textPrimary,
            letterSpacing: '-0.01em',
          }}
        >
          流光 Lucent
        </span>
        <span
          style={{
            width: 1,
            height: 14,
            background: t.rimOuter,
          }}
        />
        <span
          style={{
            fontFamily: FONT_MONO,
            fontSize: 12.5,
            fontWeight: 600,
            color: t.accentBadgeText,
            letterSpacing: '0.06em',
          }}
        >
          {currentAct.index} · {currentAct.title}
        </span>
      </div>

      {/* Right Architectural Chapter Timecode Rail */}
      <div
        style={{
          position: 'absolute',
          right: 26,
          top: '50%',
          transform: 'translateY(-50%)',
          display: 'flex',
          flexDirection: 'column',
          alignItems: 'center',
          gap: 10,
          zIndex: 90,
          opacity: opacity * 0.85,
          fontFamily: FONT_MONO,
        }}
      >
        <span style={{ fontSize: 11, fontWeight: 700, color: t.accentCyan }}>
          {currentAct.index}
        </span>
        <div style={{ display: 'flex', flexDirection: 'column', gap: 7 }}>
          {ACTS.map((a, idx) => {
            const isAct = idx === actIdx;
            return (
              <div
                key={a.id}
                style={{
                  width: isAct ? 8 : 5,
                  height: isAct ? 18 : 5,
                  borderRadius: 99,
                  background: isAct ? t.accentCyan : t.rimOuter,
                  boxShadow: isAct ? `0 0 10px ${t.accentCyan}` : 'none',
                }}
              />
            );
          })}
        </div>
        <div
          style={{
            width: 2,
            height: 54,
            borderRadius: 99,
            background: t.rimOuter,
            overflow: 'hidden',
          }}
        >
          <div
            style={{
              width: '100%',
              height: `${(progress * 100).toFixed(1)}%`,
              background: t.accentGradient,
            }}
          />
        </div>
        <span style={{ fontSize: 10.5, color: t.textTertiary }}>07</span>
      </div>
    </>
  );
};
