import React from 'react';

interface IconProps {
  size?: number;
  color?: string;
  strokeWidth?: number;
  style?: React.CSSProperties;
}

const base = (size: number, color: string, strokeWidth: number, style?: React.CSSProperties) => ({
  width: size,
  height: size,
  viewBox: '0 0 24 24',
  fill: 'none',
  stroke: color,
  strokeWidth,
  strokeLinecap: 'round' as const,
  strokeLinejoin: 'round' as const,
  style,
});

export const IconSearch: React.FC<IconProps> = ({ size = 20, color = 'currentColor', strokeWidth = 2.1, style }) => (
  <svg {...base(size, color, strokeWidth, style)}>
    <circle cx="11" cy="11" r="7.5" />
    <path d="M20 20l-3.8-3.8" />
  </svg>
);

export const IconCrop: React.FC<IconProps> = ({ size = 20, color = 'currentColor', strokeWidth = 2, style }) => (
  <svg {...base(size, color, strokeWidth, style)}>
    <path d="M6 2v14a2 2 0 0 0 2 2h14" />
    <path d="M18 22V8a2 2 0 0 0-2-2H2" />
  </svg>
);

export const IconGif: React.FC<IconProps> = ({ size = 20, color = 'currentColor', strokeWidth = 2, style }) => (
  <svg {...base(size, color, strokeWidth, style)}>
    <rect x="2.5" y="5" width="19" height="14" rx="3" />
    <circle cx="9.5" cy="12" r="2.2" fill={color} stroke="none" />
    <path d="M14.5 9.5l3.5 2.5-3.5 2.5V9.5z" fill={color} stroke="none" />
  </svg>
);

export const IconScanText: React.FC<IconProps> = ({ size = 20, color = 'currentColor', strokeWidth = 2, style }) => (
  <svg {...base(size, color, strokeWidth, style)}>
    <path d="M3 7V5a2 2 0 0 1 2-2h2M17 3h2a2 2 0 0 1 2 2v2M21 17v2a2 2 0 0 1-2 2h-2M7 21H5a2 2 0 0 1-2-2v-2" />
    <path d="M7 9h10M7 12h8M7 15h6" />
  </svg>
);

export const IconMouse: React.FC<IconProps> = ({ size = 20, color = 'currentColor', strokeWidth = 2, style }) => (
  <svg {...base(size, color, strokeWidth, style)}>
    <rect x="6" y="2.5" width="12" height="19" rx="6" />
    <path d="M12 6.5v3.5" />
  </svg>
);

export const IconFolder: React.FC<IconProps> = ({ size = 20, color = 'currentColor', strokeWidth = 2, style }) => (
  <svg {...base(size, color, strokeWidth, style)}>
    <path d="M3 7a2 2 0 0 1 2-2h4.2l2 2.2H19a2 2 0 0 1 2 2V18a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V7z" />
  </svg>
);

export const IconCpu: React.FC<IconProps> = ({ size = 20, color = 'currentColor', strokeWidth = 2, style }) => (
  <svg {...base(size, color, strokeWidth, style)}>
    <rect x="6" y="6" width="12" height="12" rx="2.5" />
    <rect x="9.5" y="9.5" width="5" height="5" rx="1" />
    <path d="M9 2v4M15 2v4M9 18v4M15 18v4M2 9h4M2 15h4M18 9h4M18 15h4" />
  </svg>
);

export const IconNetwork: React.FC<IconProps> = ({ size = 20, color = 'currentColor', strokeWidth = 2, style }) => (
  <svg {...base(size, color, strokeWidth, style)}>
    <path d="M3 16l4-5 4 3 4-7 6 5" />
    <path d="M3 20h18" />
  </svg>
);

export const IconClipboard: React.FC<IconProps> = ({ size = 20, color = 'currentColor', strokeWidth = 2, style }) => (
  <svg {...base(size, color, strokeWidth, style)}>
    <rect x="8" y="2.5" width="8" height="3.5" rx="1.2" />
    <path d="M16 4.5h2a2 2 0 0 1 2 2V19a2 2 0 0 1-2 2H6a2 2 0 0 1-2-2V6.5a2 2 0 0 1 2-2h2" />
    <path d="M8.5 11.5h7M8.5 15.5h5" />
  </svg>
);

export const IconTerminal: React.FC<IconProps> = ({ size = 20, color = 'currentColor', strokeWidth = 2, style }) => (
  <svg {...base(size, color, strokeWidth, style)}>
    <rect x="2.5" y="4" width="19" height="16" rx="3" />
    <path d="M7 9.5l3 2.5-3 2.5M12.5 14.5h4.5" />
  </svg>
);

export const IconSparkles: React.FC<IconProps> = ({ size = 20, color = 'currentColor', strokeWidth = 1.9, style }) => (
  <svg {...base(size, color, strokeWidth, style)}>
    <path d="M12 2.5l2.2 6.8L21 11.5l-6.8 2.2L12 20.5l-2.2-6.8L3 11.5l6.8-2.2L12 2.5z" />
  </svg>
);

export const IconPuzzle: React.FC<IconProps> = ({ size = 20, color = 'currentColor', strokeWidth = 2, style }) => (
  <svg {...base(size, color, strokeWidth, style)}>
    <path d="M19.5 13.5a2 2 0 1 0 0-4H18V6.5a1.5 1.5 0 0 0-1.5-1.5H13.5V3.5a2 2 0 1 0-4 0V5H6.5A1.5 1.5 0 0 0 5 6.5V10h1.5a2 2 0 1 1 0 4H5v3.5A1.5 1.5 0 0 0 6.5 19H10v-1.5a2 2 0 1 1 4 0V19h2.5a1.5 1.5 0 0 0 1.5-1.5V14h1.5z" />
  </svg>
);

export const IconShield: React.FC<IconProps> = ({ size = 20, color = 'currentColor', strokeWidth = 2, style }) => (
  <svg {...base(size, color, strokeWidth, style)}>
    <path d="M12 2.5l7.5 3v6c0 5-3.2 8.6-7.5 10-4.3-1.4-7.5-5-7.5-10v-6l7.5-3z" />
    <path d="M9 12l2.2 2.2L15.5 9.8" />
  </svg>
);

export const IconLock: React.FC<IconProps> = ({ size = 20, color = 'currentColor', strokeWidth = 2, style }) => (
  <svg {...base(size, color, strokeWidth, style)}>
    <rect x="4.5" y="10.5" width="15" height="10" rx="2.5" />
    <path d="M8 10.5V7.5a4 4 0 0 1 8 0v3" />
  </svg>
);

export const IconGlobe: React.FC<IconProps> = ({ size = 20, color = 'currentColor', strokeWidth = 2, style }) => (
  <svg {...base(size, color, strokeWidth, style)}>
    <circle cx="12" cy="12" r="9" />
    <path d="M3.5 12h17M12 3a13.5 13.5 0 0 1 0 18M12 3a13.5 13.5 0 0 0 0 18" />
  </svg>
);

export const IconBell: React.FC<IconProps> = ({ size = 20, color = 'currentColor', strokeWidth = 2, style }) => (
  <svg {...base(size, color, strokeWidth, style)}>
    <path d="M18 9a6 6 0 0 0-12 0c0 6-2.5 7.5-2.5 7.5h17S18 15 18 9z" />
    <path d="M10 20a2.2 2.2 0 0 0 4 0" />
  </svg>
);

export const IconSliders: React.FC<IconProps> = ({ size = 20, color = 'currentColor', strokeWidth = 2, style }) => (
  <svg {...base(size, color, strokeWidth, style)}>
    <path d="M4 6h16M4 12h16M4 18h16" />
    <circle cx="9" cy="6" r="2" fill={color} />
    <circle cx="15" cy="12" r="2" fill={color} />
    <circle cx="11" cy="18" r="2" fill={color} />
  </svg>
);

export const IconBookmark: React.FC<IconProps> = ({ size = 20, color = 'currentColor', strokeWidth = 2, style }) => (
  <svg {...base(size, color, strokeWidth, style)}>
    <path d="M6 4a2 2 0 0 1 2-2h8a2 2 0 0 1 2 2v17l-6-4-6 4V4z" />
  </svg>
);

export const IconPhone: React.FC<IconProps> = ({ size = 20, color = 'currentColor', strokeWidth = 2, style }) => (
  <svg {...base(size, color, strokeWidth, style)}>
    <rect x="6.5" y="2.5" width="11" height="19" rx="2.5" />
    <path d="M11 18h2" />
  </svg>
);

export const IconEyeOff: React.FC<IconProps> = ({ size = 20, color = 'currentColor', strokeWidth = 2, style }) => (
  <svg {...base(size, color, strokeWidth, style)}>
    <path d="M3 3l18 18" />
    <path d="M10.6 10.6a2 2 0 0 0 2.8 2.8" />
    <path d="M9.9 4.3A9.8 9.8 0 0 1 12 4c5 0 8.5 4 9.5 8a12 12 0 0 1-2.8 4.4M6.5 6.5A11.4 11.4 0 0 0 2.5 12c1 4 4.5 8 9.5 8 1.5 0 2.9-.3 4.1-.9" />
  </svg>
);

export const IconPin: React.FC<IconProps> = ({ size = 20, color = 'currentColor', strokeWidth = 2, style }) => (
  <svg {...base(size, color, strokeWidth, style)}>
    <path d="M15 4.5l4.5 4.5-2.5 2.5-1.5-.5-3.5 3.5.5 2.5-2 2-3.5-3.5-4 4m4-4L3.5 12l2-2 2.5.5 3.5-3.5-.5-1.5L15 4.5z" />
  </svg>
);

export const IconCode: React.FC<IconProps> = ({ size = 20, color = 'currentColor', strokeWidth = 2, style }) => (
  <svg {...base(size, color, strokeWidth, style)}>
    <path d="M8 7l-5 5 5 5M16 7l5 5-5 5M14 4l-4 16" />
  </svg>
);

export const IconLayers: React.FC<IconProps> = ({ size = 20, color = 'currentColor', strokeWidth = 2, style }) => (
  <svg {...base(size, color, strokeWidth, style)}>
    <path d="M12 3l9 4.8-9 4.8-9-4.8L12 3z" />
    <path d="M3 12.6l9 4.8 9-4.8" />
    <path d="M3 17.4l9 4.8 9-4.8" />
  </svg>
);

export const IconZap: React.FC<IconProps> = ({ size = 20, color = 'currentColor', strokeWidth = 2, style }) => (
  <svg {...base(size, color, strokeWidth, style)}>
    <path d="M13 2L4.5 13.5H12L11 22l8.5-11.5H12L13 2z" />
  </svg>
);

export const IconCheck: React.FC<IconProps> = ({ size = 20, color = 'currentColor', strokeWidth = 2.4, style }) => (
  <svg {...base(size, color, strokeWidth, style)}>
    <path d="M5 12.5l4.5 4.5L19 7.5" />
  </svg>
);

export const IconPlay: React.FC<IconProps> = ({ size = 20, color = 'currentColor', strokeWidth = 2, style }) => (
  <svg {...base(size, color, strokeWidth, style)}>
    <polygon points="7,4.5 19.5,12 7,19.5" fill={color} stroke="none" />
  </svg>
);

export const IconCalculator: React.FC<IconProps> = ({ size = 20, color = 'currentColor', strokeWidth = 2, style }) => (
  <svg {...base(size, color, strokeWidth, style)}>
    <rect x="4" y="3" width="16" height="18" rx="2.5" />
    <path d="M8 7.5h8M8 12h2M14 12h2M8 16h2M14 16h2" />
  </svg>
);

export const SquircleBadge: React.FC<{
  gradient: string;
  size?: number;
  children: React.ReactNode;
}> = ({ gradient, size = 42, children }) => (
  <div
    style={{
      width: size,
      height: size,
      borderRadius: Math.round(size * 0.27),
      background: gradient,
      display: 'flex',
      alignItems: 'center',
      justifyContent: 'center',
      color: '#ffffff',
      boxShadow:
        '0 8px 18px -6px rgba(0, 0, 0, 0.35), inset 0 1.2px 0 rgba(255, 255, 255, 0.45)',
      flexShrink: 0,
    }}
  >
    {children}
  </div>
);
