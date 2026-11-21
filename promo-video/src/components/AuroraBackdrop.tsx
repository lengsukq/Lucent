import React from 'react';
import { AbsoluteFill, useCurrentFrame } from 'remotion';
import { getTheme, ThemeMode } from '../design/tokens';

interface AuroraBackdropProps {
  theme?: ThemeMode;
  intensity?: number;
  showGrid?: boolean;
  seedOffset?: number;
  showParticles?: boolean;
}

// Deterministic floating prism bokeh particles (Apple Studio depth parallax)
const BOKEH_MOTES = [
  { x: 11, y: 18, r: 4.5, sx: 0.45, sy: 0.32, cDark: '#67e8f9', cLight: '#38bdf8', o: 0.55 },
  { x: 24, y: 76, r: 3.2, sx: -0.38, sy: 0.41, cDark: '#c084fc', cLight: '#818cf8', o: 0.48 },
  { x: 37, y: 31, r: 2.8, sx: 0.52, sy: -0.28, cDark: '#f472b6', cLight: '#ec4899', o: 0.42 },
  { x: 48, y: 84, r: 5.0, sx: -0.25, sy: -0.35, cDark: '#38bdf8', cLight: '#0284c7', o: 0.45 },
  { x: 63, y: 22, r: 3.6, sx: 0.33, sy: 0.48, cDark: '#34d399', cLight: '#10b981', o: 0.44 },
  { x: 74, y: 68, r: 4.2, sx: -0.44, sy: -0.26, cDark: '#a78bfa', cLight: '#6366f1', o: 0.52 },
  { x: 86, y: 28, r: 3.0, sx: 0.29, sy: 0.37, cDark: '#67e8f9', cLight: '#0ea5e9', o: 0.48 },
  { x: 91, y: 80, r: 5.2, sx: -0.36, sy: 0.29, cDark: '#f472b6', cLight: '#a855f7', o: 0.44 },
  { x: 16, y: 49, r: 2.6, sx: 0.41, sy: -0.44, cDark: '#ffffff', cLight: '#0066dc', o: 0.38 },
  { x: 56, y: 12, r: 3.4, sx: -0.31, sy: 0.33, cDark: '#e0f2fe', cLight: '#4f46e5', o: 0.42 },
  { x: 79, y: 46, r: 2.8, sx: 0.38, sy: -0.31, cDark: '#67e8f9', cLight: '#06b6d4', o: 0.46 },
  { x: 31, y: 61, r: 3.8, sx: -0.29, sy: 0.36, cDark: '#818cf8', cLight: '#3b82f6', o: 0.36 },
];

export const AuroraBackdrop: React.FC<AuroraBackdropProps> = ({
  theme = 'prism-pulse',
  intensity = 1,
  showGrid = true,
  seedOffset = 0,
  showParticles = true,
}) => {
  const frame = useCurrentFrame();
  const tokens = getTheme(theme);
  const t = (frame + seedOffset) * 0.011;

  const isDark = theme === 'prism-pulse';
  const orb1X = 18 + Math.sin(t * 0.65) * 7;
  const orb1Y = 22 + Math.cos(t * 0.52) * 8;
  const orb2X = 81 + Math.cos(t * 0.58) * 7;
  const orb2Y = 74 + Math.sin(t * 0.45) * 6;
  const orb3X = 50 + Math.sin(t * 0.38 + 1.4) * 10;
  const orb3Y = 14 + Math.cos(t * 0.34) * 6;

  // Volumetric diagonal studio light ray sweeping gently across backdrop
  const rayShift = Math.sin(t * 0.35) * 140;

  return (
    <AbsoluteFill
      style={{
        backgroundColor: tokens.bgCanvas,
        overflow: 'hidden',
      }}
    >
      {/* Layered Studio Ceramic / Deep Sapphire Obsidian Foundation */}
      <AbsoluteFill
        style={{
          background: isDark
            ? 'radial-gradient(ellipse 120% 90% at 50% -10%, #141b42 0%, #070918 55%, #03040a 100%)'
            : 'radial-gradient(ellipse 120% 90% at 50% -10%, #ffffff 0%, #f1f6fd 52%, #e3ecf9 100%)',
        }}
      />

      {/* Volumetric Diagonal Caustic Light Ribbon */}
      <div
        style={{
          position: 'absolute',
          left: '50%',
          top: '45%',
          width: 2400,
          height: 520,
          transform: `translate(calc(-50% + ${rayShift}px), -50%) rotate(-18deg)`,
          background: isDark
            ? 'linear-gradient(180deg, transparent 0%, rgba(56, 189, 248, 0.055) 35%, rgba(168, 85, 247, 0.065) 60%, transparent 100%)'
            : 'linear-gradient(180deg, transparent 0%, rgba(56, 189, 248, 0.09) 35%, rgba(168, 85, 247, 0.075) 62%, transparent 100%)',
          opacity: intensity,
          pointerEvents: 'none',
        }}
      />

      {/* Volumetric Aurora Orb 1 (Cyan / Cobalt) */}
      <div
        style={{
          position: 'absolute',
          left: `${orb1X}%`,
          top: `${orb1Y}%`,
          width: 1280,
          height: 980,
          transform: 'translate(-50%, -50%)',
          background: isDark
            ? 'radial-gradient(circle, rgba(34, 211, 238, 0.27) 0%, rgba(56, 189, 248, 0.11) 36%, transparent 68%)'
            : 'radial-gradient(circle, rgba(56, 189, 248, 0.30) 0%, rgba(0, 102, 220, 0.09) 40%, transparent 68%)',
          opacity: intensity,
        }}
      />

      {/* Volumetric Aurora Orb 2 (Violet / Magenta) */}
      <div
        style={{
          position: 'absolute',
          left: `${orb2X}%`,
          top: `${orb2Y}%`,
          width: 1320,
          height: 1020,
          transform: 'translate(-50%, -50%)',
          background: isDark
            ? 'radial-gradient(circle, rgba(168, 85, 247, 0.26) 0%, rgba(244, 114, 182, 0.13) 38%, transparent 70%)'
            : 'radial-gradient(circle, rgba(168, 85, 247, 0.21) 0%, rgba(236, 72, 153, 0.09) 40%, transparent 70%)',
          opacity: intensity,
        }}
      />

      {/* Volumetric Aurora Orb 3 (Indigo / Mint Horizon) */}
      <div
        style={{
          position: 'absolute',
          left: `${orb3X}%`,
          top: `${orb3Y}%`,
          width: 1060,
          height: 800,
          transform: 'translate(-50%, -50%)',
          background: isDark
            ? 'radial-gradient(circle, rgba(99, 102, 241, 0.24) 0%, rgba(52, 211, 153, 0.08) 42%, transparent 70%)'
            : 'radial-gradient(circle, rgba(16, 185, 129, 0.17) 0%, rgba(14, 165, 233, 0.08) 42%, transparent 70%)',
          opacity: intensity,
        }}
      />

      {/* Precision Architectural Grid with Subtle Intersections */}
      {showGrid && (
        <AbsoluteFill
          style={{
            backgroundImage: `linear-gradient(${tokens.gridColor} 1px, transparent 1px), linear-gradient(90deg, ${tokens.gridColor} 1px, transparent 1px)`,
            backgroundSize: '64px 64px',
            maskImage: 'radial-gradient(ellipse 84% 78% at 50% 48%, rgba(0,0,0,0.88) 18%, transparent 94%)',
            WebkitMaskImage:
              'radial-gradient(ellipse 84% 78% at 50% 48%, rgba(0,0,0,0.88) 18%, transparent 94%)',
          }}
        />
      )}

      {/* Drifting Luminous Prism Bokeh Motes (Parallax Depth) */}
      {showParticles && (
        <AbsoluteFill style={{ pointerEvents: 'none' }}>
          {BOKEH_MOTES.map((m, idx) => {
            const dx = Math.sin(t * 0.9 * m.sx + idx * 1.7) * 34;
            const dy = Math.cos(t * 0.85 * m.sy + idx * 2.1) * 28;
            const pulse = 0.65 + 0.35 * Math.sin(t * 1.6 + idx * 1.3);
            const color = isDark ? m.cDark : m.cLight;
            return (
              <div
                key={idx}
                style={{
                  position: 'absolute',
                  left: `${m.x}%`,
                  top: `${m.y}%`,
                  width: m.r * 2,
                  height: m.r * 2,
                  borderRadius: '50%',
                  background: color,
                  boxShadow: isDark
                    ? `0 0 ${m.r * 3.8}px ${color}`
                    : `0 0 ${m.r * 2.6}px ${color}88`,
                  opacity: m.o * pulse * (isDark ? 0.72 : 0.42) * intensity,
                  transform: `translate(${dx}px, ${dy}px)`,
                }}
              />
            );
          })}
        </AbsoluteFill>
      )}

      {/* Subtle Optical Studio Horizon Arc */}
      <div
        style={{
          position: 'absolute',
          left: '10%',
          right: '10%',
          top: -1,
          height: 2,
          background: isDark
            ? 'linear-gradient(90deg, transparent, rgba(103, 232, 249, 0.35), rgba(192, 132, 252, 0.35), transparent)'
            : 'linear-gradient(90deg, transparent, rgba(0, 102, 220, 0.18), rgba(79, 70, 229, 0.18), transparent)',
          opacity: 0.8,
        }}
      />

      {/* Cinematic Edge Vignette */}
      <AbsoluteFill
        style={{
          background: isDark
            ? 'radial-gradient(ellipse 92% 92% at 50% 50%, transparent 54%, rgba(2, 3, 10, 0.66) 100%)'
            : 'radial-gradient(ellipse 94% 94% at 50% 50%, transparent 62%, rgba(176, 198, 230, 0.30) 100%)',
        }}
      />
    </AbsoluteFill>
  );
};
