import React from 'react';
import { Easing, interpolate, useCurrentFrame } from 'remotion';
import { FONT_MONO, FONT_SANS, getTheme, ThemeMode } from '../design/tokens';

/**
 * Smooth cinematic stage camera wrapper — adds gentle living 3D breath & micro-dolly
 * plus silky cross-fade/scale transitions for sub-stages inside each act.
 */
export const CameraStage: React.FC<{
  children: React.ReactNode;
  enterFrame?: number;
  breathScale?: number;
  tiltDeg?: number;
  style?: React.CSSProperties;
}> = ({ children, enterFrame = 0, breathScale = 0.012, tiltDeg = 0.8, style }) => {
  const frame = useCurrentFrame();
  const local = Math.max(0, frame - enterFrame);
  const enter = interpolate(local, [0, 20], [0, 1], {
    extrapolateLeft: 'clamp',
    extrapolateRight: 'clamp',
    easing: Easing.out(Easing.cubic),
  });
  const breath = Math.sin(local * 0.016) * breathScale;
  const ry = Math.sin(local * 0.013) * tiltDeg;

  return (
    <div
      style={{
        width: '100%',
        height: '100%',
        display: 'flex',
        alignItems: 'center',
        justifyContent: 'center',
        opacity: enter,
        transform: `perspective(1400px) translateY(${(1 - enter) * 18}px) scale(${(0.975 + enter * 0.025) + breath}) rotateY(${ry}deg)`,
        ...style,
      }}
    >
      {children}
    </div>
  );
};

/**
 * Realistic macOS translucent pointer cursor with soft drop shadow & optional click ripple.
 */
export const AnimatedCursor: React.FC<{
  x: number;
  y: number;
  clicking?: boolean;
  rippleProgress?: number;
  opacity?: number;
}> = ({ x, y, clicking = false, rippleProgress = 0, opacity = 1 }) => {
  if (opacity <= 0.01) return null;
  return (
    <div
      style={{
        position: 'absolute',
        left: x,
        top: y,
        zIndex: 120,
        pointerEvents: 'none',
        opacity,
        transform: `scale(${clicking ? 0.88 : 1})`,
      }}
    >
      {rippleProgress > 0.01 && rippleProgress < 0.99 && (
        <div
          style={{
            position: 'absolute',
            left: -24 * rippleProgress,
            top: -24 * rippleProgress,
            width: 48 * rippleProgress,
            height: 48 * rippleProgress,
            borderRadius: '50%',
            border: '2px solid rgba(56, 189, 248, 0.85)',
            boxShadow: '0 0 18px rgba(56, 189, 248, 0.55)',
            opacity: 1 - rippleProgress,
          }}
        />
      )}
      <svg
        width="28"
        height="32"
        viewBox="0 0 28 32"
        fill="none"
        style={{ filter: 'drop-shadow(0 4px 8px rgba(0,0,0,0.45))' }}
      >
        <path
          d="M4 3L23 17.5L14.5 18.8L18.5 27.5L14.8 29.2L10.8 20.4L4.8 25.5L4 3Z"
          fill="#0f172a"
          stroke="#ffffff"
          strokeWidth="2.1"
          strokeLinejoin="round"
        />
      </svg>
    </div>
  );
};

/**
 * Bespoke crisp macOS-style vector icons for Omni Dock apps & plugins (replaces plain letter boxes).
 */
export const BespokeDockIcon: React.FC<{
  kind:
    | 'xcode'
    | 'cursor'
    | 'translate'
    | 'remind'
    | 'files'
    | 'github'
    | 'obsidian'
    | 'folder'
    | 'safari'
    | 'terminal'
    | 'figma'
    | 'notion'
    | 'finder'
    | 'bookmarks'
    | 'pilot'
    | 'luma';
  size?: number;
}> = ({ kind, size = 42 }) => {
  const r = Math.round(size * 0.27);
  const iconSz = Math.round(size * 0.52);

  const specs: Record<string, { bg: string; glyph: React.ReactNode }> = {
    xcode: {
      bg: 'linear-gradient(145deg, #38bdf8, #1d4ed8)',
      glyph: (
        <svg width={iconSz} height={iconSz} viewBox="0 0 24 24" fill="none" stroke="#fff" strokeWidth="2.1" strokeLinecap="round">
          <path d="M14.5 4.5l5 5-9.5 9.5-5-5 9.5-9.5z" />
          <path d="M5 19l4-4M13 6l5 5" />
        </svg>
      ),
    },
    cursor: {
      bg: 'linear-gradient(145deg, #1e1b4b, #6d28d9)',
      glyph: (
        <svg width={iconSz} height={iconSz} viewBox="0 0 24 24" fill="none">
          <polygon points="5,4 19,12 12,13.8 10,20" fill="#ffffff" />
          <circle cx="17.5" cy="6.5" r="2.2" fill="#38bdf8" />
        </svg>
      ),
    },
    translate: {
      bg: 'linear-gradient(145deg, #06b6d4, #6366f1)',
      glyph: (
        <svg width={iconSz} height={iconSz} viewBox="0 0 24 24" fill="none" stroke="#fff" strokeWidth="2" strokeLinecap="round">
          <circle cx="12" cy="12" r="8.5" />
          <path d="M4 12h16M12 3.5a12 12 0 0 1 0 17M12 3.5a12 12 0 0 0 0 17" />
        </svg>
      ),
    },
    remind: {
      bg: 'linear-gradient(145deg, #fbbf24, #ea580c)',
      glyph: (
        <svg width={iconSz} height={iconSz} viewBox="0 0 24 24" fill="none" stroke="#fff" strokeWidth="2.1" strokeLinecap="round">
          <path d="M18 9a6 6 0 0 0-12 0c0 5.5-2 7-2 7h16s-2-1.5-2-7z" />
          <path d="M10 19.5a2 2 0 0 0 4 0" />
        </svg>
      ),
    },
    files: {
      bg: 'linear-gradient(145deg, #10b981, #0284c7)',
      glyph: (
        <svg width={iconSz} height={iconSz} viewBox="0 0 24 24" fill="none" stroke="#fff" strokeWidth="2" strokeLinecap="round">
          <rect x="3" y="5" width="8" height="14" rx="2" />
          <rect x="13" y="5" width="8" height="14" rx="2" />
        </svg>
      ),
    },
    github: {
      bg: 'linear-gradient(145deg, #334155, #0f172a)',
      glyph: (
        <svg width={iconSz} height={iconSz} viewBox="0 0 24 24" fill="none" stroke="#fff" strokeWidth="2.1" strokeLinecap="round">
          <circle cx="7" cy="6" r="2.2" />
          <circle cx="17" cy="18" r="2.2" />
          <circle cx="17" cy="6" r="2.2" />
          <path d="M7 8.2V18M17 8.2v7.6M7 13c0-2 3-3 10-3" />
        </svg>
      ),
    },
    obsidian: {
      bg: 'linear-gradient(145deg, #a855f7, #4c1d95)',
      glyph: (
        <svg width={iconSz} height={iconSz} viewBox="0 0 24 24" fill="none">
          <polygon points="12,3 19,10 15,21 7,19 5,11" fill="rgba(255,255,255,0.92)" />
          <polygon points="12,3 19,10 12,13" fill="#c4b5fd" />
        </svg>
      ),
    },
    folder: {
      bg: 'linear-gradient(145deg, #38bdf8, #0284c7)',
      glyph: (
        <svg width={iconSz} height={iconSz} viewBox="0 0 24 24" fill="none" stroke="#fff" strokeWidth="2.1" strokeLinejoin="round">
          <path d="M3 7a2 2 0 0 1 2-2h4.5l2 2.2H19a2 2 0 0 1 2 2V18a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V7z" />
        </svg>
      ),
    },
    safari: {
      bg: 'linear-gradient(145deg, #60a5fa, #1d4ed8)',
      glyph: (
        <svg width={iconSz} height={iconSz} viewBox="0 0 24 24" fill="none" stroke="#fff" strokeWidth="2">
          <circle cx="12" cy="12" r="8.5" />
          <polygon points="15.5,8.5 13.2,13.2 8.5,15.5 10.8,10.8" fill="#fff" stroke="none" />
        </svg>
      ),
    },
    terminal: {
      bg: 'linear-gradient(145deg, #1e293b, #020617)',
      glyph: (
        <svg width={iconSz} height={iconSz} viewBox="0 0 24 24" fill="none" stroke="#34d399" strokeWidth="2.3" strokeLinecap="round" strokeLinejoin="round">
          <path d="M5 8l5 4-5 4M12 16h7" />
        </svg>
      ),
    },
    figma: {
      bg: 'linear-gradient(145deg, #f43f5e, #8b5cf6)',
      glyph: (
        <svg width={iconSz} height={iconSz} viewBox="0 0 24 24" fill="none">
          <circle cx="14.5" cy="12" r="3" fill="#38bdf8" />
          <rect x="6.5" y="4" width="6" height="6" rx="3" fill="#fff" />
          <rect x="12.5" y="4" width="5.5" height="6" rx="2.75" fill="#fb7185" />
          <rect x="6.5" y="10" width="6" height="6" rx="3" fill="#c084fc" />
          <rect x="6.5" y="16" width="6" height="5" rx="2.5" fill="#34d399" />
        </svg>
      ),
    },
    notion: {
      bg: 'linear-gradient(145deg, #475569, #1e293b)',
      glyph: (
        <svg width={iconSz} height={iconSz} viewBox="0 0 24 24" fill="none" stroke="#fff" strokeWidth="2.1" strokeLinecap="round" strokeLinejoin="round">
          <rect x="4.5" y="4" width="15" height="16" rx="2.5" />
          <path d="M9 15.5V8.5l6 7V8.5" />
        </svg>
      ),
    },
    finder: {
      bg: 'linear-gradient(145deg, #38bdf8, #2563eb)',
      glyph: (
        <svg width={iconSz} height={iconSz} viewBox="0 0 24 24" fill="none" stroke="#fff" strokeWidth="2.1" strokeLinecap="round">
          <path d="M8.5 9v1.5M15.5 9v1.5M12 5v8.5h-2M7.5 16c1.5 1.8 7.5 1.8 9 0" />
        </svg>
      ),
    },
    bookmarks: {
      bg: 'linear-gradient(145deg, #0ea5e9, #4f46e5)',
      glyph: (
        <svg width={iconSz} height={iconSz} viewBox="0 0 24 24" fill="none" stroke="#fff" strokeWidth="2.1" strokeLinejoin="round">
          <path d="M6.5 4.5h11v15.5L12 16l-5.5 4V4.5z" />
        </svg>
      ),
    },
    pilot: {
      bg: 'linear-gradient(145deg, #6366f1, #38bdf8)',
      glyph: (
        <svg width={iconSz} height={iconSz} viewBox="0 0 24 24" fill="none" stroke="#fff" strokeWidth="2.1" strokeLinecap="round">
          <path d="M5 7h14M5 12h14M5 17h14" />
          <circle cx="9" cy="7" r="2" fill="#fff" />
          <circle cx="15" cy="12" r="2" fill="#fff" />
          <circle cx="11" cy="17" r="2" fill="#fff" />
        </svg>
      ),
    },
    luma: {
      bg: 'linear-gradient(145deg, #10b981, #06b6d4)',
      glyph: (
        <svg width={iconSz} height={iconSz} viewBox="0 0 24 24" fill="none" stroke="#fff" strokeWidth="2.1" strokeLinecap="round">
          <rect x="7" y="3.5" width="10" height="17" rx="2.5" />
          <path d="M11 17.5h2" />
        </svg>
      ),
    },
  };

  const item = specs[kind] ?? specs.folder;
  return (
    <div
      style={{
        width: size,
        height: size,
        borderRadius: r,
        background: item.bg,
        display: 'flex',
        alignItems: 'center',
        justifyContent: 'center',
        boxShadow:
          '0 8px 18px -6px rgba(2, 6, 23, 0.45), inset 0 1.2px 0 rgba(255, 255, 255, 0.42), inset 0 -1px 0 rgba(0, 0, 0, 0.22)',
        flexShrink: 0,
      }}
    >
      {item.glyph}
    </div>
  );
};

/**
 * Slim authentic macOS menu bar strip for desktop context cards.
 */
export const MacStatusBarStrip: React.FC<{
  theme?: ThemeMode;
  activeApp?: string;
  highlightLucent?: boolean;
}> = ({ theme = 'prism-pulse', activeApp = 'Lucent', highlightLucent = true }) => {
  const t = getTheme(theme);
  const isDark = theme === 'prism-pulse';
  return (
    <div
      style={{
        height: 30,
        padding: '0 16px',
        background: isDark ? 'rgba(10, 12, 26, 0.72)' : 'rgba(255, 255, 255, 0.78)',
        borderBottom: `1px solid ${t.rimOuter}`,
        display: 'flex',
        alignItems: 'center',
        justifyContent: 'space-between',
        fontFamily: FONT_SANS,
        fontSize: 12,
        color: t.textSecondary,
      }}
    >
      <div style={{ display: 'flex', alignItems: 'center', gap: 14 }}>
        <span style={{ fontWeight: 800, color: t.textPrimary }}></span>
        <span style={{ fontWeight: 700, color: t.textPrimary }}>{activeApp}</span>
        <span style={{ opacity: 0.72 }}>文件</span>
        <span style={{ opacity: 0.72 }}>编辑</span>
        <span style={{ opacity: 0.72 }}>窗口</span>
      </div>
      <div style={{ display: 'flex', alignItems: 'center', gap: 12, fontFamily: FONT_MONO, fontSize: 11.5 }}>
        <span
          style={{
            padding: '2px 8px',
            borderRadius: 6,
            background: highlightLucent ? t.accentBadgeBg : 'transparent',
            border: highlightLucent ? `1px solid ${t.accentBadgeBorder}` : 'none',
            color: highlightLucent ? t.accentBadgeText : t.textSecondary,
            fontWeight: 700,
          }}
        >
          ✦ Lucent
        </span>
        <span style={{ opacity: 0.72 }}>Wi-Fi</span>
        <span style={{ opacity: 0.72 }}>100%</span>
        <span style={{ fontWeight: 600, color: t.textPrimary }}>09:41</span>
      </div>
    </div>
  );
};
