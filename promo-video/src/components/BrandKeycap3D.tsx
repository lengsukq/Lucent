import React, { useId } from 'react';

interface BrandKeycap3DProps {
  size?: number;
  orbitAngleRad?: number;
  gemGlow?: number;
  pressed?: number;
  showHalo?: boolean;
  style?: React.CSSProperties;
}

export const BrandKeycap3D: React.FC<BrandKeycap3DProps> = ({
  size = 180,
  orbitAngleRad = -0.68,
  gemGlow = 1,
  pressed = 0,
  showHalo = false,
  style,
}) => {
  const uid = useId().replace(/:/g, '_');
  const id = (name: string) => `${uid}_${name}`;

  // Compute luminous photon pearl position along tilted (-31.5 deg) orbit ellipse
  const theta = orbitAngleRad;
  const rx = 117;
  const ry = 46.5;
  const ex = Math.cos(theta) * rx;
  const ey = Math.sin(theta) * ry;
  const rot = (-31.5 * Math.PI) / 180;
  const pearlX = 256 + ex * Math.cos(rot) - ey * Math.sin(rot);
  const pearlY = 245 + ex * Math.sin(rot) + ey * Math.cos(rot);

  const keyDrop = pressed * 10;

  return (
    <div
      style={{
        position: 'relative',
        width: size,
        height: size,
        display: 'inline-flex',
        alignItems: 'center',
        justifyContent: 'center',
        ...style,
      }}
    >
      {showHalo && (
        <div
          style={{
            position: 'absolute',
            inset: -size * 0.85,
            borderRadius: '50%',
            background:
              'radial-gradient(circle, rgba(56, 189, 248, 0.34) 0%, rgba(168, 85, 247, 0.16) 28%, rgba(244, 114, 182, 0.05) 45%, transparent 62%)',
            opacity: 0.72 + gemGlow * 0.28,
            pointerEvents: 'none',
          }}
        />
      )}

      <svg
        xmlns="http://www.w3.org/2000/svg"
        viewBox="0 0 512 512"
        width={size}
        height={size}
        fill="none"
        style={{ display: 'block', overflow: 'visible' }}
      >
        <defs>
          <filter id={id('chassisShadow')} x="-12%" y="-10%" width="124%" height="128%">
            <feDropShadow dx="0" dy="14" stdDeviation="16" floodColor="#020512" floodOpacity="0.54" />
          </filter>
          <filter id={id('keywellShadow')} x="-18%" y="-12%" width="136%" height="142%">
            <feDropShadow dx="0" dy="18" stdDeviation="16" floodColor="#01030c" floodOpacity="0.88" />
            <feDropShadow dx="0" dy="8" stdDeviation="14" floodColor="#38bdf8" floodOpacity="0.30" />
          </filter>
          <filter id={id('gemShadow')} x="-24%" y="-20%" width="148%" height="152%">
            <feDropShadow dx="0" dy="10" stdDeviation="8" floodColor="#020514" floodOpacity="0.78" />
          </filter>
          <filter id={id('orbitBloom')} x="-30%" y="-30%" width="160%" height="160%">
            <feGaussianBlur stdDeviation="6.5" result="blur" />
            <feMerge>
              <feMergeNode in="blur" />
              <feMergeNode in="SourceGraphic" />
            </feMerge>
          </filter>

          <linearGradient id={id('chassisBase')} x1="110" y1="44" x2="412" y2="468" gradientUnits="userSpaceOnUse">
            <stop offset="0%" stopColor="#14214E" />
            <stop offset="54%" stopColor="#080D22" />
            <stop offset="100%" stopColor="#150C32" />
          </linearGradient>
          <radialGradient id={id('causticCyan')} cx="122" cy="388" r="268" gradientUnits="userSpaceOnUse">
            <stop offset="0%" stopColor="#0EA5E9" stopOpacity="0.54" />
            <stop offset="48%" stopColor="#38BDF8" stopOpacity="0.16" />
            <stop offset="100%" stopColor="#0EA5E9" stopOpacity="0" />
          </radialGradient>
          <radialGradient id={id('causticViolet')} cx="398" cy="118" r="256" gradientUnits="userSpaceOnUse">
            <stop offset="0%" stopColor="#A855F7" stopOpacity="0.52" />
            <stop offset="46%" stopColor="#F472B6" stopOpacity="0.22" />
            <stop offset="100%" stopColor="#A855F7" stopOpacity="0" />
          </radialGradient>
          <linearGradient id={id('chassisRim')} x1="48" y1="44" x2="464" y2="468" gradientUnits="userSpaceOnUse">
            <stop offset="0%" stopColor="#FFFFFF" stopOpacity="0.86" />
            <stop offset="32%" stopColor="#7DD3FC" stopOpacity="0.52" />
            <stop offset="68%" stopColor="#6366F1" stopOpacity="0.28" />
            <stop offset="100%" stopColor="#F472B6" stopOpacity="0.58" />
          </linearGradient>
          <linearGradient id={id('skirtHoriz')} x1="114" y1="262" x2="398" y2="262" gradientUnits="userSpaceOnUse">
            <stop offset="0%" stopColor="#7DD3FC" />
            <stop offset="20%" stopColor="#2D6CE4" />
            <stop offset="50%" stopColor="#1C245E" />
            <stop offset="80%" stopColor="#6028BA" />
            <stop offset="100%" stopColor="#EC4899" />
          </linearGradient>
          <linearGradient id={id('skirtVert')} x1="256" y1="122" x2="256" y2="402" gradientUnits="userSpaceOnUse">
            <stop offset="0%" stopColor="#FFFFFF" stopOpacity="0.28" />
            <stop offset="45%" stopColor="#0E1436" stopOpacity="0.28" />
            <stop offset="84%" stopColor="#0A0E28" stopOpacity="0.54" />
            <stop offset="100%" stopColor="#818CF8" stopOpacity="0.30" />
          </linearGradient>
          <linearGradient id={id('skirtRim')} x1="114" y1="122" x2="398" y2="402" gradientUnits="userSpaceOnUse">
            <stop offset="0%" stopColor="#E0F2FE" stopOpacity="0.74" />
            <stop offset="52%" stopColor="#6366F1" stopOpacity="0.32" />
            <stop offset="100%" stopColor="#F472B6" stopOpacity="0.58" />
          </linearGradient>
          <linearGradient id={id('dishBase')} x1="133" y1="132" x2="379" y2="362" gradientUnits="userSpaceOnUse">
            <stop offset="0%" stopColor="#284292" />
            <stop offset="52%" stopColor="#101942" />
            <stop offset="100%" stopColor="#281860" />
          </linearGradient>
          <radialGradient id={id('dishWell')} cx="256" cy="238" r="144" gradientUnits="userSpaceOnUse">
            <stop offset="0%" stopColor="#050818" stopOpacity="0.60" />
            <stop offset="64%" stopColor="#111C4A" stopOpacity="0.18" />
            <stop offset="100%" stopColor="#7DD3FC" stopOpacity="0.32" />
          </radialGradient>
          <radialGradient id={id('dishGlow')} cx="256" cy="247" r="128" gradientUnits="userSpaceOnUse">
            <stop offset="0%" stopColor="#38BDF8" stopOpacity={0.36 * gemGlow} />
            <stop offset="52%" stopColor="#A855F7" stopOpacity={0.20 * gemGlow} />
            <stop offset="100%" stopColor="#38BDF8" stopOpacity="0" />
          </radialGradient>
          <linearGradient id={id('dishGloss')} x1="256" y1="132" x2="256" y2="232" gradientUnits="userSpaceOnUse">
            <stop offset="0%" stopColor="#FFFFFF" stopOpacity="0.30" />
            <stop offset="100%" stopColor="#FFFFFF" stopOpacity="0" />
          </linearGradient>
          <linearGradient id={id('dishRim')} x1="133" y1="132" x2="379" y2="362" gradientUnits="userSpaceOnUse">
            <stop offset="0%" stopColor="#FFFFFF" stopOpacity="0.94" />
            <stop offset="35%" stopColor="#7DD3FC" stopOpacity="0.68" />
            <stop offset="72%" stopColor="#818CF8" stopOpacity="0.34" />
            <stop offset="100%" stopColor="#F472B6" stopOpacity="0.65" />
          </linearGradient>
          <linearGradient id={id('orbitGrad')} x1="-124" y1="18" x2="124" y2="-18" gradientUnits="userSpaceOnUse">
            <stop offset="0%" stopColor="#22D3EE" />
            <stop offset="40%" stopColor="#F0F9FF" />
            <stop offset="74%" stopColor="#A78BFA" />
            <stop offset="100%" stopColor="#F472B6" />
          </linearGradient>
          <linearGradient id={id('gemNW')} x1="256" y1="245" x2="164" y2="152" gradientUnits="userSpaceOnUse">
            <stop offset="0%" stopColor="#FFFFFF" />
            <stop offset="100%" stopColor="#E0F2FE" />
          </linearGradient>
          <linearGradient id={id('gemNE')} x1="256" y1="245" x2="348" y2="152" gradientUnits="userSpaceOnUse">
            <stop offset="0%" stopColor="#F0F9FF" />
            <stop offset="100%" stopColor="#38BDF8" />
          </linearGradient>
          <linearGradient id={id('gemSE')} x1="256" y1="245" x2="348" y2="338" gradientUnits="userSpaceOnUse">
            <stop offset="0%" stopColor="#C084FC" />
            <stop offset="100%" stopColor="#EC4899" />
          </linearGradient>
          <linearGradient id={id('gemSW')} x1="256" y1="245" x2="164" y2="338" gradientUnits="userSpaceOnUse">
            <stop offset="0%" stopColor="#7DD3FC" />
            <stop offset="100%" stopColor="#4F46E5" />
          </linearGradient>
          <radialGradient id={id('gemApex')} cx="252" cy="240" r="48" gradientUnits="userSpaceOnUse">
            <stop offset="0%" stopColor="#FFFFFF" stopOpacity="1" />
            <stop offset="36%" stopColor="#E0F2FE" stopOpacity="0.54" />
            <stop offset="100%" stopColor="#FFFFFF" stopOpacity="0" />
          </radialGradient>
          <radialGradient id={id('pearlGlow')} cx={pearlX} cy={pearlY} r="24" gradientUnits="userSpaceOnUse">
            <stop offset="0%" stopColor="#FFFFFF" stopOpacity="1" />
            <stop offset="42%" stopColor="#F472B6" stopOpacity="0.88" />
            <stop offset="100%" stopColor="#F472B6" stopOpacity="0" />
          </radialGradient>

          <clipPath id={id('chassisClip')}>
            <rect x="47" y="42" width="418" height="418" rx="94.5" />
          </clipPath>
          <clipPath id={id('skirtClip')}>
            <rect x="114" y="118" width="284" height="280" rx="74" />
          </clipPath>
          <clipPath id={id('dishClip')}>
            <rect x="133.5" y="128" width="245" height="230" rx="56" />
          </clipPath>
          <clipPath id={id('gemClip')}>
            <path d="M256 147 Q276 225 348 245 Q276 265 256 339 Q236 265 164 245 Q236 225 256 147 Z" />
          </clipPath>
          <clipPath id={id('orbitBackClip')}>
            <polygon points="82,358 434,140 310,-40 -40,180" />
          </clipPath>
          <clipPath id={id('orbitFrontClip')}>
            <polygon points="80,354 432,136 552,312 200,530" />
          </clipPath>
        </defs>

        <g filter={`url(#${id('chassisShadow')})`}>
          <rect x="47" y="42" width="418" height="418" rx="94.5" fill="#070A1C" />
        </g>

        <g clipPath={`url(#${id('chassisClip')})`}>
          <rect x="47" y="42" width="418" height="418" fill={`url(#${id('chassisBase')})`} />
          <circle cx="122" cy="388" r="268" fill={`url(#${id('causticCyan')})`} />
          <circle cx="398" cy="118" r="256" fill={`url(#${id('causticViolet')})`} />
          <rect
            x="50"
            y="45"
            width="412"
            height="412"
            rx="91.5"
            stroke={`url(#${id('chassisRim')})`}
            strokeWidth="5.5"
            opacity="0.45"
          />

          {/* Tactile Keycap Assembly (moves down slightly when pressed) */}
          <g transform={`translate(0, ${keyDrop.toFixed(2)})`}>
            <g filter={`url(#${id('keywellShadow')})`}>
              <rect x="114" y="118" width="284" height="280" rx="74" fill="#0C122E" />
            </g>
            <g clipPath={`url(#${id('skirtClip')})`}>
              <rect x="114" y="118" width="284" height="280" fill={`url(#${id('skirtHoriz')})`} />
              <rect x="114" y="118" width="284" height="280" fill={`url(#${id('skirtVert')})`} />
              <rect x="133.5" y="128" width="245" height="230" rx="56" fill="#141E4C" />
            </g>
            <rect x="114" y="118" width="284" height="280" rx="74" stroke={`url(#${id('skirtRim')})`} strokeWidth="2.6" />

            <g clipPath={`url(#${id('dishClip')})`}>
              <rect x="133.5" y="128" width="245" height="230" fill={`url(#${id('dishBase')})`} />
              <rect x="133.5" y="128" width="245" height="230" fill={`url(#${id('dishWell')})`} />
              <rect x="133.5" y="128" width="245" height="230" fill={`url(#${id('dishGlow')})`} />
              <ellipse cx="256" cy="150" rx="152" ry="74" fill={`url(#${id('dishGloss')})`} />
            </g>
            <rect x="133.5" y="128" width="245" height="230" rx="56" stroke={`url(#${id('dishRim')})`} strokeWidth="4.2" />

            {/* Back half of orbit ring */}
            <g clipPath={`url(#${id('orbitBackClip')})`} filter={`url(#${id('orbitBloom')})`}>
              <g transform="translate(256 245) rotate(-31.5)">
                <path
                  fillRule="evenodd"
                  fill={`url(#${id('orbitGrad')})`}
                  d="M 124,0 A 124,52 0 1,0 -124,0 A 124,52 0 1,0 124,0 Z M 110,-6 A 110,41 0 1,1 -110,-6 A 110,41 0 1,1 110,-6 Z"
                />
              </g>
            </g>

            {/* Crystal 4-facet star gem */}
            <g filter={`url(#${id('gemShadow')})`}>
              <path
                d="M256 147 Q276 225 348 245 Q276 265 256 339 Q236 265 164 245 Q236 225 256 147 Z"
                fill="#FFFFFF"
              />
            </g>
            <g clipPath={`url(#${id('gemClip')})`}>
              <polygon points="256,245 256,142 158,142 158,245" fill={`url(#${id('gemNW')})`} />
              <polygon points="256,245 256,142 354,142 354,245" fill={`url(#${id('gemNE')})`} />
              <polygon points="256,245 354,245 354,344 256,344" fill={`url(#${id('gemSE')})`} />
              <polygon points="256,245 158,245 158,344 256,344" fill={`url(#${id('gemSW')})`} />
              <circle cx="252" cy="240" r="48" fill={`url(#${id('gemApex')})`} />
              <line x1="256" y1="147" x2="256" y2="339" stroke="#FFFFFF" strokeWidth="3.2" strokeLinecap="round" opacity="0.92" />
              <line x1="164" y1="245" x2="348" y2="245" stroke="#FFFFFF" strokeWidth="3.2" strokeLinecap="round" opacity="0.92" />
            </g>
            <path
              d="M256 147 Q276 225 348 245 Q276 265 256 339 Q236 265 164 245 Q236 225 256 147 Z"
              stroke="#FFFFFF"
              strokeWidth="2.4"
              strokeOpacity="0.88"
            />

            {/* Front half of orbit ring */}
            <g clipPath={`url(#${id('orbitFrontClip')})`} filter={`url(#${id('orbitBloom')})`}>
              <g transform="translate(256 245) rotate(-31.5)">
                <path
                  fillRule="evenodd"
                  fill={`url(#${id('orbitGrad')})`}
                  d="M 124,0 A 124,52 0 1,0 -124,0 A 124,52 0 1,0 124,0 Z M 110,-6 A 110,41 0 1,1 -110,-6 A 110,41 0 1,1 110,-6 Z"
                />
              </g>
            </g>

            <circle cx={pearlX} cy={pearlY} r="24" fill={`url(#${id('pearlGlow')})`} />
          </g>
        </g>

        <rect x="47" y="42" width="418" height="418" rx="94.5" stroke={`url(#${id('chassisRim')})`} strokeWidth="3.2" />
      </svg>
    </div>
  );
};
