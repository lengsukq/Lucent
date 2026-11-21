export type ThemeMode = 'prism-pulse' | 'pure-frost';

export interface ThemeTokens {
  mode: ThemeMode;
  bgCanvas: string;
  bgVoid: string;
  bgPanel: string;
  bgPanelSolid: string;
  bgCard: string;
  bgCardStrong: string;
  bgWell: string;
  bgInput: string;
  bgPill: string;
  bgRowSelected: string;
  textPrimary: string;
  textSecondary: string;
  textTertiary: string;
  accentPrimary: string;
  accentSecondary: string;
  accentCyan: string;
  accentPink: string;
  accentEmerald: string;
  accentAmber: string;
  accentBadgeBg: string;
  accentBadgeBorder: string;
  accentBadgeText: string;
  headlineGradient: string;
  accentGradient: string;
  rimOuter: string;
  rimInnerTop: string;
  rimInnerBottom: string;
  rimSelected: string;
  gridColor: string;
  panelShadow: string;
  cardShadow: string;
  keycapBg: string;
  keycapBorder: string;
  keycapText: string;
  keycapShadow: string;
  studioBg: string;
  studioHead: string;
  studioBorder: string;
  studioText: string;
  studioMuted: string;
  studioKw: string;
  studioStr: string;
  studioKey: string;
}

export const PRISM_PULSE: ThemeTokens = {
  mode: 'prism-pulse',
  bgCanvas: '#060713',
  bgVoid: '#03040a',
  bgPanel: 'rgba(17, 17, 40, 0.84)',
  bgPanelSolid: 'rgba(19, 19, 44, 0.94)',
  bgCard: 'rgba(26, 25, 56, 0.72)',
  bgCardStrong: 'rgba(34, 32, 72, 0.86)',
  bgWell: 'rgba(10, 10, 26, 0.74)',
  bgInput: 'rgba(11, 11, 28, 0.88)',
  bgPill: 'rgba(255, 255, 255, 0.085)',
  bgRowSelected: 'rgba(124, 92, 252, 0.30)',
  textPrimary: '#f8faff',
  textSecondary: 'rgba(218, 226, 250, 0.86)',
  textTertiary: 'rgba(156, 168, 212, 0.74)',
  accentPrimary: '#7c5cfc',
  accentSecondary: '#38bdf8',
  accentCyan: '#22d3ee',
  accentPink: '#f472b6',
  accentEmerald: '#34d399',
  accentAmber: '#fbbf24',
  accentBadgeBg: 'rgba(34, 211, 238, 0.14)',
  accentBadgeBorder: 'rgba(103, 232, 249, 0.34)',
  accentBadgeText: '#67e8f9',
  headlineGradient: 'linear-gradient(120deg, #67e8f9 0%, #a78bfa 46%, #f472b6 100%)',
  accentGradient: 'linear-gradient(135deg, #14ccfa 0%, #7c5cfc 52%, #f45ca2 100%)',
  rimOuter: 'rgba(255, 255, 255, 0.16)',
  rimInnerTop: 'rgba(255, 255, 255, 0.30)',
  rimInnerBottom: 'rgba(255, 255, 255, 0.06)',
  rimSelected: 'rgba(103, 232, 249, 0.62)',
  gridColor: 'rgba(255, 255, 255, 0.042)',
  panelShadow:
    '0 42px 96px -18px rgba(1, 2, 10, 0.88), 0 0 72px -20px rgba(124, 92, 252, 0.30), 0 0 0 1px rgba(255, 255, 255, 0.16), inset 0 1.5px 0 rgba(255, 255, 255, 0.30), inset 0 -1px 0 rgba(255, 255, 255, 0.06)',
  cardShadow:
    '0 20px 44px -14px rgba(2, 2, 14, 0.68), 0 0 0 1px rgba(255, 255, 255, 0.12), inset 0 1px 0 rgba(255, 255, 255, 0.18)',
  keycapBg: 'linear-gradient(180deg, rgba(255, 255, 255, 0.18) 0%, rgba(255, 255, 255, 0.07) 100%)',
  keycapBorder: 'rgba(255, 255, 255, 0.24)',
  keycapText: '#f8fafc',
  keycapShadow: '0 2px 0 rgba(0, 0, 0, 0.55), inset 0 1px 0 rgba(255, 255, 255, 0.24)',
  studioBg: '#0a0b1d',
  studioHead: 'rgba(255, 255, 255, 0.055)',
  studioBorder: 'rgba(255, 255, 255, 0.14)',
  studioText: '#e6edf8',
  studioMuted: '#8b98b8',
  studioKw: '#67e8f9',
  studioStr: '#6ee7b7',
  studioKey: '#c4b5fd',
};

export const PURE_FROST: ThemeTokens = {
  mode: 'pure-frost',
  bgCanvas: '#f1f5fc',
  bgVoid: '#eaf0fa',
  bgPanel: 'rgba(255, 255, 255, 0.90)',
  bgPanelSolid: 'rgba(255, 255, 255, 0.96)',
  bgCard: 'rgba(255, 255, 255, 0.92)',
  bgCardStrong: 'rgba(255, 255, 255, 0.98)',
  bgWell: 'rgba(232, 240, 252, 0.86)',
  bgInput: 'rgba(241, 246, 253, 0.94)',
  bgPill: 'rgba(15, 23, 42, 0.055)',
  bgRowSelected: 'rgba(0, 102, 220, 0.11)',
  textPrimary: '#0a1120',
  textSecondary: '#334155',
  textTertiary: '#5b6b84',
  accentPrimary: '#0066dc',
  accentSecondary: '#4f46e5',
  accentCyan: '#0284c7',
  accentPink: '#db2777',
  accentEmerald: '#059669',
  accentAmber: '#d97706',
  accentBadgeBg: 'rgba(0, 102, 220, 0.095)',
  accentBadgeBorder: 'rgba(0, 102, 220, 0.24)',
  accentBadgeText: '#0052b5',
  headlineGradient: 'linear-gradient(120deg, #0055c4 0%, #4f46e5 48%, #0891b2 100%)',
  accentGradient: 'linear-gradient(135deg, #006be6 0%, #4338ca 54%, #0284c7 100%)',
  rimOuter: 'rgba(15, 23, 42, 0.095)',
  rimInnerTop: '#ffffff',
  rimInnerBottom: 'rgba(15, 23, 42, 0.04)',
  rimSelected: 'rgba(0, 102, 220, 0.44)',
  gridColor: 'rgba(15, 23, 42, 0.04)',
  panelShadow:
    '0 8px 20px rgba(15, 23, 42, 0.04), 0 32px 68px -14px rgba(15, 35, 75, 0.14), 0 0 0 1px rgba(15, 23, 42, 0.09), inset 0 1.5px 0 #ffffff, inset 0 -1px 0 rgba(15, 23, 42, 0.04)',
  cardShadow:
    '0 2px 6px rgba(15, 23, 42, 0.035), 0 14px 32px -10px rgba(15, 23, 42, 0.09), 0 0 0 1px rgba(15, 23, 42, 0.08), inset 0 1px 0 #ffffff',
  keycapBg: 'linear-gradient(180deg, #ffffff 0%, #edf2fa 100%)',
  keycapBorder: 'rgba(15, 23, 42, 0.16)',
  keycapText: '#1e293b',
  keycapShadow: '0 2px 0 rgba(15, 23, 42, 0.12), inset 0 1px 0 #ffffff',
  studioBg: '#f8fafd',
  studioHead: '#edf2fa',
  studioBorder: 'rgba(15, 23, 42, 0.10)',
  studioText: '#0f172a',
  studioMuted: '#5b6b82',
  studioKw: '#005cc5',
  studioStr: '#047857',
  studioKey: '#4338ca',
};

export function getTheme(mode: ThemeMode): ThemeTokens {
  return mode === 'pure-frost' ? PURE_FROST : PRISM_PULSE;
}

export const RADII = {
  panel: 28,
  window: 24,
  bento: 22,
  card: 18,
  row: 14,
  control: 12,
  pill: 999,
} as const;

export const FONT_SANS =
  '-apple-system, BlinkMacSystemFont, "SF Pro Display", "PingFang SC", "Hiragino Sans GB", "Helvetica Neue", sans-serif';
export const FONT_MONO =
  '"SF Mono", ui-monospace, Menlo, Monaco, Consolas, monospace';
