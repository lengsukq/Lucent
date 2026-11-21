import React from 'react';
import { useCurrentFrame } from 'remotion';
import { FONT_MONO, FONT_SANS, getTheme, RADII, ThemeMode } from '../design/tokens';
import { BrandKeycap3D } from './BrandKeycap3D';
import { IconSearch } from './Icons';
import { KeycapBadge } from './KeycapBadge';

export type ScopeKey = 'all' | 'plugins' | 'files' | 'clip';

const SCOPES: { key: ScopeKey; label: string; labelEn: string }[] = [
  { key: 'all', label: '全部', labelEn: 'All' },
  { key: 'plugins', label: '插件', labelEn: 'Plugins' },
  { key: 'files', label: '文件', labelEn: 'Files' },
  { key: 'clip', label: '剪贴板', labelEn: 'Clipboard' },
];

interface LiquidGlassPanelProps {
  theme?: ThemeMode;
  query?: string;
  placeholder?: string;
  activeScope?: ScopeKey;
  dimensionTag?: string;
  showCursor?: boolean;
  english?: boolean;
  showFooter?: boolean;
  width?: number;
  height?: number;
  toastText?: string;
  style?: React.CSSProperties;
  children: React.ReactNode;
}

export const LiquidGlassPanel: React.FC<LiquidGlassPanelProps> = ({
  theme = 'prism-pulse',
  query = '',
  placeholder = '输入软件名、全盘与移动硬盘文件、算式换算、!脚本 或插件指令...',
  activeScope = 'all',
  dimensionTag = '880 × 544 · 0ms',
  showCursor = true,
  english = false,
  showFooter = true,
  width = 880,
  height = 544,
  toastText,
  style,
  children,
}) => {
  const frame = useCurrentFrame();
  const t = getTheme(theme);
  const isDark = theme === 'prism-pulse';
  const activeIdx = Math.max(0, SCOPES.findIndex((s) => s.key === activeScope));
  // Subtle continuous optical glass specular glint sweeping across the panel
  const sheenPos = ((frame * 0.42) % 240) - 70;

  return (
    <div
      style={{
        position: 'relative',
        width,
        height,
        borderRadius: RADII.panel,
        background: t.bgPanel,
        boxShadow: t.panelShadow,
        display: 'flex',
        flexDirection: 'column',
        overflow: 'hidden',
        fontFamily: FONT_SANS,
        ...style,
      }}
    >
      {/* Dynamic Optical Specular Glass Sheen */}
      <div
        style={{
          position: 'absolute',
          inset: 0,
          background: isDark
            ? `linear-gradient(115deg, transparent ${sheenPos - 22}%, rgba(125, 211, 252, 0.055) ${sheenPos}%, rgba(255, 255, 255, 0.04) ${sheenPos + 6}%, transparent ${sheenPos + 24}%)`
            : `linear-gradient(115deg, transparent ${sheenPos - 22}%, rgba(255, 255, 255, 0.55) ${sheenPos}%, transparent ${sheenPos + 24}%)`,
          pointerEvents: 'none',
          zIndex: 5,
        }}
      />

      {/* Top Double Specular Highlight Strip */}
      <div
        style={{
          position: 'absolute',
          top: 0,
          left: 28,
          right: 28,
          height: 1.5,
          background: isDark
            ? 'linear-gradient(90deg, transparent, rgba(125, 211, 252, 0.55), rgba(255,255,255,0.65), rgba(244,114,182,0.45), transparent)'
            : 'linear-gradient(90deg, transparent, rgba(255,255,255,0.95), transparent)',
          pointerEvents: 'none',
        }}
      />

      {/* 18pt Top Grabber Chrome */}
      <div
        style={{
          height: 26,
          padding: '0 22px',
          display: 'flex',
          alignItems: 'center',
          justifyContent: 'space-between',
          flexShrink: 0,
        }}
      >
        <div style={{ display: 'flex', alignItems: 'center', gap: 8, minWidth: 160 }}>
          {toastText ? (
            <span
              style={{
                fontFamily: FONT_MONO,
                fontSize: 11,
                fontWeight: 600,
                color: t.accentEmerald,
                background: isDark ? 'rgba(52, 211, 153, 0.14)' : 'rgba(5, 150, 105, 0.11)',
                padding: '2px 9px',
                borderRadius: RADII.pill,
              }}
            >
              {toastText}
            </span>
          ) : (
            <span
              style={{
                fontFamily: FONT_MONO,
                fontSize: 11,
                color: t.textTertiary,
                opacity: 0.78,
              }}
            >
              Lucent · {isDark ? 'Prism Pulse' : 'Pure Frost'}
            </span>
          )}
        </div>

        <div
          style={{
            width: 44,
            height: 4,
            borderRadius: RADII.pill,
            background: isDark ? 'rgba(255,255,255,0.22)' : 'rgba(15,23,42,0.16)',
          }}
        />

        <div
          style={{
            minWidth: 160,
            textAlign: 'right',
            fontFamily: FONT_MONO,
            fontSize: 11,
            color: t.textTertiary,
          }}
        >
          {dimensionTag}
        </div>
      </div>

      {/* Main Search Input Cabin */}
      <div
        style={{
          margin: '2px 18px 12px',
          height: 54,
          padding: '0 14px 0 16px',
          borderRadius: RADII.bento,
          background: t.bgInput,
          border: `1px solid ${t.rimOuter}`,
          boxShadow: isDark
            ? 'inset 0 1px 0 rgba(255,255,255,0.08)'
            : 'inset 0 1px 2px rgba(15,23,42,0.04)',
          display: 'flex',
          alignItems: 'center',
          gap: 12,
          flexShrink: 0,
        }}
      >
        {query ? (
          <IconSearch size={20} color={t.accentSecondary} strokeWidth={2.3} />
        ) : (
          <BrandKeycap3D size={28} />
        )}

        <div
          style={{
            flex: 1,
            fontSize: 17.5,
            fontWeight: query ? 500 : 400,
            color: query ? t.textPrimary : t.textTertiary,
            whiteSpace: 'nowrap',
            overflow: 'hidden',
            display: 'flex',
            alignItems: 'center',
          }}
        >
          <span>{query || placeholder}</span>
          {showCursor && (
            <span
              style={{
                display: 'inline-block',
                width: 2.2,
                height: 21,
                marginLeft: 2,
                borderRadius: 2,
                background: t.accentCyan,
                boxShadow: `0 0 8px ${t.accentCyan}`,
              }}
            />
          )}
        </div>

        {/* 4-State Gliding Scope Capsules */}
        <div
          style={{
            position: 'relative',
            display: 'flex',
            alignItems: 'center',
            padding: 3,
            borderRadius: RADII.pill,
            background: t.bgPill,
            border: `1px solid ${t.rimOuter}`,
          }}
        >
          <div
            style={{
              position: 'absolute',
              top: 3,
              bottom: 3,
              left: 3 + activeIdx * 62,
              width: 62,
              borderRadius: RADII.pill,
              background: isDark
                ? 'rgba(124, 92, 252, 0.36)'
                : 'rgba(255, 255, 255, 0.96)',
              border: `1px solid ${t.rimSelected}`,
              boxShadow: isDark
                ? '0 0 14px rgba(124, 92, 252, 0.35)'
                : '0 2px 6px rgba(15,23,42,0.08)',
            }}
          />
          {SCOPES.map((s) => {
            const isSel = s.key === activeScope;
            return (
              <div
                key={s.key}
                style={{
                  position: 'relative',
                  zIndex: 1,
                  width: 62,
                  textAlign: 'center',
                  fontSize: 12.5,
                  fontWeight: isSel ? 600 : 500,
                  padding: '5px 0',
                  color: isSel ? t.textPrimary : t.textTertiary,
                }}
              >
                {english ? s.labelEn : s.label}
              </div>
            );
          })}
        </div>
      </div>

      {/* Panel Dynamic Body */}
      <div
        style={{
          flex: 1,
          minHeight: 0,
          padding: '0 18px 12px',
          display: 'flex',
          flexDirection: 'column',
          overflow: 'hidden',
        }}
      >
        {children}
      </div>

      {/* Footer Keyboard Flow Hint Strip */}
      {showFooter && (
        <div
          style={{
            height: 38,
            padding: '0 20px',
            borderTop: `1px solid ${t.rimOuter}`,
            background: isDark ? 'rgba(8, 9, 22, 0.56)' : 'rgba(241, 246, 253, 0.72)',
            display: 'flex',
            alignItems: 'center',
            justifyContent: 'space-between',
            fontSize: 12,
            color: t.textTertiary,
            flexShrink: 0,
          }}
        >
          <div style={{ display: 'flex', alignItems: 'center', gap: 16 }}>
            <span style={{ display: 'inline-flex', alignItems: 'center', gap: 6 }}>
              <KeycapBadge keys={['↵']} theme={theme} size="sm" />
              {english ? 'Open' : '打开'}
            </span>
            <span style={{ display: 'inline-flex', alignItems: 'center', gap: 6 }}>
              <KeycapBadge keys={['⌘1-9']} theme={theme} size="sm" />
              {english ? 'Quick Pick' : '快选'}
            </span>
            <span style={{ display: 'inline-flex', alignItems: 'center', gap: 6 }}>
              <KeycapBadge keys={['⌘C']} theme={theme} size="sm" />
              {english ? 'Copy' : '复制'}
            </span>
            <span style={{ display: 'inline-flex', alignItems: 'center', gap: 6 }}>
              <KeycapBadge keys={['⇥']} theme={theme} size="sm" />
              {english ? 'Scope' : '切换分类'}
            </span>
          </div>
          <span style={{ display: 'inline-flex', alignItems: 'center', gap: 6 }}>
            <KeycapBadge keys={['⎋']} theme={theme} size="sm" />
            {english ? 'Dismiss' : '收起即净'}
          </span>
        </div>
      )}
    </div>
  );
};
