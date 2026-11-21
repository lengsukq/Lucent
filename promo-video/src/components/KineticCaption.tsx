import React from 'react';
import { FONT_MONO, FONT_SANS, getTheme, RADII, ThemeMode } from '../design/tokens';
import { clampLerp, spr, SPRING_GLASS } from '../design/motion';

interface SceneHeaderProps {
  eyebrow: string;
  title: string;
  highlight?: string;
  subtitle?: string;
  theme?: ThemeMode;
  frame: number;
  align?: 'left' | 'center';
  delay?: number;
  maxWidth?: number;
  fontSize?: number;
}

export const SceneHeader: React.FC<SceneHeaderProps> = ({
  eyebrow,
  title,
  highlight,
  subtitle,
  theme = 'prism-pulse',
  frame,
  align = 'left',
  delay = 4,
  maxWidth = 1080,
  fontSize = 48,
}) => {
  const t = getTheme(theme);
  const p0 = spr(frame, delay, SPRING_GLASS);
  const p1 = spr(frame, delay + 7, SPRING_GLASS);
  const p2 = spr(frame, delay + 14, SPRING_GLASS);

  return (
    <div
      style={{
        display: 'flex',
        flexDirection: 'column',
        alignItems: align === 'center' ? 'center' : 'flex-start',
        textAlign: align,
        maxWidth,
        fontFamily: FONT_SANS,
      }}
    >
      <div
        style={{
          display: 'inline-flex',
          alignItems: 'center',
          gap: 10,
          padding: '6px 14px',
          borderRadius: RADII.pill,
          background: t.accentBadgeBg,
          border: `1px solid ${t.accentBadgeBorder}`,
          color: t.accentBadgeText,
          fontFamily: FONT_MONO,
          fontSize: 13.5,
          fontWeight: 600,
          letterSpacing: '0.09em',
          textTransform: 'uppercase',
          opacity: p0,
          transform: `translateY(${(1 - p0) * 14}px)`,
        }}
      >
        <span
          style={{
            width: 7,
            height: 7,
            borderRadius: '50%',
            background: t.accentCyan,
            boxShadow: `0 0 10px ${t.accentCyan}`,
          }}
        />
        {eyebrow}
      </div>

      <h2
        style={{
          margin: '14px 0 0',
          fontSize,
          lineHeight: 1.16,
          fontWeight: 700,
          letterSpacing: '-0.025em',
          color: t.textPrimary,
          opacity: p1,
          transform: `translateY(${(1 - p1) * 20}px)`,
        }}
      >
        {title}
        {highlight && (
          <span
            style={{
              backgroundImage: t.headlineGradient,
              WebkitBackgroundClip: 'text',
              WebkitTextFillColor: 'transparent',
            }}
          >
            {highlight}
          </span>
        )}
      </h2>

      {subtitle && (
        <p
          style={{
            margin: '12px 0 0',
            fontSize: 22,
            lineHeight: 1.5,
            fontWeight: 400,
            color: t.textSecondary,
            opacity: p2,
            transform: `translateY(${(1 - p2) * 16}px)`,
          }}
        >
          {subtitle}
        </p>
      )}
    </div>
  );
};

export interface CaptionBeat {
  start: number;
  end: number;
  tag?: string;
  text: string;
}

interface BottomCaptionBarProps {
  beats: CaptionBeat[];
  frame: number;
  theme?: ThemeMode;
}

export const BottomCaptionBar: React.FC<BottomCaptionBarProps> = ({
  beats,
  frame,
  theme = 'prism-pulse',
}) => {
  const t = getTheme(theme);
  const active = beats.find((b) => frame >= b.start && frame <= b.end);
  if (!active) return null;

  const enter = clampLerp(frame, [active.start, active.start + 16], [0, 1]);
  const exit = clampLerp(frame, [active.end - 16, active.end], [1, 0]);
  const opacity = Math.min(enter, exit);
  const translateY = (1 - enter) * 14 - (1 - exit) * 8;
  const beatProgress = Math.max(0, Math.min(1, (frame - active.start) / Math.max(1, active.end - active.start)));

  return (
    <div
      style={{
        position: 'absolute',
        left: 0,
        right: 0,
        bottom: 30,
        display: 'flex',
        justifyContent: 'center',
        pointerEvents: 'none',
        zIndex: 80,
      }}
    >
      <div
        style={{
          position: 'relative',
          overflow: 'hidden',
          display: 'inline-flex',
          alignItems: 'center',
          gap: 14,
          padding: '13px 28px 15px',
          borderRadius: RADII.pill,
          background:
            theme === 'prism-pulse'
              ? 'rgba(9, 11, 26, 0.84)'
              : 'rgba(255, 255, 255, 0.90)',
          border: `1px solid ${t.rimOuter}`,
          boxShadow:
            theme === 'prism-pulse'
              ? '0 22px 48px -12px rgba(0,0,0,0.72), inset 0 1px 0 rgba(255,255,255,0.20)'
              : '0 16px 40px -10px rgba(15,23,42,0.12), inset 0 1px 0 #ffffff',
          opacity,
          transform: `translateY(${translateY}px)`,
          maxWidth: 1480,
          fontFamily: FONT_SANS,
        }}
      >
        {active.tag && (
          <span
            style={{
              padding: '4px 11px',
              borderRadius: RADII.pill,
              background: t.accentBadgeBg,
              border: `1px solid ${t.accentBadgeBorder}`,
              color: t.accentBadgeText,
              fontFamily: FONT_MONO,
              fontSize: 13,
              fontWeight: 700,
              letterSpacing: '0.05em',
              whiteSpace: 'nowrap',
            }}
          >
            {active.tag}
          </span>
        )}
        <span
          style={{
            fontSize: 21.5,
            lineHeight: 1.35,
            fontWeight: 500,
            color: t.textPrimary,
            letterSpacing: '0.012em',
            whiteSpace: 'nowrap',
          }}
        >
          {active.text}
        </span>

        {/* Ultra-fine optical progress hairline */}
        <div
          style={{
            position: 'absolute',
            left: 26,
            right: 26,
            bottom: 0,
            height: 2,
            background: theme === 'prism-pulse' ? 'rgba(255,255,255,0.06)' : 'rgba(15,23,42,0.05)',
          }}
        >
          <div
            style={{
              width: `${(beatProgress * 100).toFixed(1)}%`,
              height: '100%',
              background: t.accentGradient,
              opacity: 0.85,
            }}
          />
        </div>
      </div>
    </div>
  );
};
