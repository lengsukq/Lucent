import React from 'react';
import { FONT_MONO, getTheme, ThemeMode } from '../design/tokens';

interface KeycapBadgeProps {
  keys: string[];
  theme?: ThemeMode;
  size?: 'sm' | 'md' | 'lg';
  active?: boolean;
  style?: React.CSSProperties;
}

export const KeycapBadge: React.FC<KeycapBadgeProps> = ({
  keys,
  theme = 'prism-pulse',
  size = 'md',
  active = false,
  style,
}) => {
  const t = getTheme(theme);
  const pad = size === 'lg' ? '7px 14px' : size === 'sm' ? '2px 7px' : '4px 10px';
  const fontSize = size === 'lg' ? 19 : size === 'sm' ? 12 : 14;
  const radius = size === 'lg' ? 10 : size === 'sm' ? 6 : 8;

  return (
    <span
      style={{
        display: 'inline-flex',
        alignItems: 'center',
        gap: size === 'lg' ? 7 : 4,
        ...style,
      }}
    >
      {keys.map((k, idx) => (
        <span
          key={`${k}-${idx}`}
          style={{
            display: 'inline-flex',
            alignItems: 'center',
            justifyContent: 'center',
            padding: pad,
            fontSize,
            lineHeight: 1.15,
            fontWeight: 600,
            fontFamily: FONT_MONO,
            borderRadius: radius,
            color: active ? '#ffffff' : t.keycapText,
            background: active ? t.accentGradient : t.keycapBg,
            border: `1px solid ${active ? 'rgba(255,255,255,0.45)' : t.keycapBorder}`,
            boxShadow: active
              ? '0 0 22px rgba(56, 189, 248, 0.55), inset 0 1px 0 rgba(255,255,255,0.45)'
              : t.keycapShadow,
            transform: active ? 'translateY(1.5px) scale(0.97)' : 'translateY(0)',
          }}
        >
          {k}
        </span>
      ))}
    </span>
  );
};
