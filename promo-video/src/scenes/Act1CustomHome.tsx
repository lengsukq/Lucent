import React from 'react';
import { AbsoluteFill, Easing, useCurrentFrame } from 'remotion';
import { AuroraBackdrop } from '../components/AuroraBackdrop';
import {
  IconBookmark,
  IconCode,
  IconCrop,
  IconFolder,
  IconGif,
  IconGlobe,
  IconPin,
  IconScanText,
  IconSparkles,
  IconTerminal,
  SquircleBadge,
} from '../components/Icons';
import { BottomCaptionBar, CaptionBeat, SceneHeader } from '../components/KineticCaption';
import { LiquidGlassPanel } from '../components/LiquidGlassPanel';
import { AnimatedCursor, BespokeDockIcon } from '../components/MacChrome';
import { clampLerp, spr, SPRING_BOUNCY, SPRING_GLASS } from '../design/motion';
import { FONT_MONO, FONT_SANS, getTheme, RADII, ThemeMode } from '../design/tokens';

const CAPTIONS: CaptionBeat[] = [
  { start: 30, end: 420, tag: '4 ZONES', text: 'Bento 大磁贴、混合高频坞、6 组命名书签架与探索提示，四大分区随心开关调序' },
  { start: 440, end: 880, tag: 'PROFILES', text: '内置 4 套官方预设，支持「均衡 / 极简 / 开发者工作台」多场景主页一键切换' },
  { start: 900, end: 1320, tag: 'ONE-CLICK PIN', text: '任何搜索结果右键一键钉上主页，自定义标题、图标与强调色，支持撤回修改' },
  { start: 1360, end: 2020, tag: 'DUAL THEME', text: '双生液态玻璃「霓彩流光 ↔ 凝霜留白」与中英双语免重启实时切换，自动同步全部插件' },
];

type LayoutPreset = 'balanced' | 'developer' | 'compact4';

const HomePanelContent: React.FC<{
  theme: ThemeMode;
  preset: LayoutPreset;
  frame: number;
  english: boolean;
  showRightClickPin: boolean;
  pinnedExtra: boolean;
}> = ({ theme, preset, frame, english, showRightClickPin, pinnedExtra }) => {
  const t = getTheme(theme);
  const cols = preset === 'compact4' ? 4 : preset === 'developer' ? 2 : 3;

  const tiles =
    preset === 'developer'
      ? [
          { title: english ? 'Dual File Workbench' : '双栏文件整理台', sub: '⌥E · NTFS 只读护航', grad: 'linear-gradient(135deg,#059669,#06b6d4)', icon: <IconFolder size={18} /> },
          { title: english ? 'Clean Port 3000' : '!清理开发端口', sub: 'Quick Script · Zsh', grad: 'linear-gradient(135deg,#f59e0b,#ef4444)', icon: <IconTerminal size={18} /> },
        ]
      : preset === 'compact4'
      ? [
          { title: english ? 'Capture & Pin' : '截图标注', sub: '⌥A', grad: 'linear-gradient(135deg,#0ea5e9,#6366f1)', icon: <IconCrop size={17} /> },
          { title: english ? 'Offline OCR' : '离线识字', sub: '⌥O', grad: 'linear-gradient(135deg,#8b5cf6,#ec4899)', icon: <IconScanText size={17} /> },
          { title: english ? 'Region GIF' : 'GIF 录屏', sub: '⌥G', grad: 'linear-gradient(135deg,#10b981,#06b6d4)', icon: <IconGif size={17} /> },
          { title: english ? 'Translate Hub' : '流光译站', sub: 'tr', grad: 'linear-gradient(135deg,#0284c7,#7c3aed)', icon: <IconGlobe size={17} /> },
        ]
      : [
          { title: english ? 'Screenshot & Pin' : '多屏截图标注', sub: '⌥A · 窗口抠图与钉屏', grad: 'linear-gradient(135deg,#0ea5e9,#6366f1)', icon: <IconCrop size={18} /> },
          { title: english ? 'Offline Vision OCR' : '一秒离线识字', sub: '⌥O · 中英文与二维码', grad: 'linear-gradient(135deg,#8b5cf6,#ec4899)', icon: <IconScanText size={18} /> },
          { title: english ? 'Region GIF Capture' : '轻巧 GIF 录屏', sub: '⌥G · 零 FFmpeg 灵动岛', grad: 'linear-gradient(135deg,#10b981,#06b6d4)', icon: <IconGif size={18} /> },
        ];

  const dockItems: readonly { name: string; kind: React.ComponentProps<typeof BespokeDockIcon>['kind'] }[] =
    preset === 'compact4'
      ? [
          { name: 'Xcode', kind: 'xcode' },
          { name: 'Cursor', kind: 'cursor' },
          { name: 'Safari', kind: 'safari' },
          { name: 'Terminal', kind: 'terminal' },
          { name: 'Figma', kind: 'figma' },
          { name: 'Obsidian', kind: 'obsidian' },
          { name: 'Notion', kind: 'notion' },
          { name: 'Finder', kind: 'finder' },
          { name: '译站', kind: 'translate' },
          { name: '书签', kind: 'bookmarks' },
          { name: '提醒', kind: 'remind' },
          { name: '中控', kind: 'pilot' },
          { name: 'Luma', kind: 'luma' },
          { name: '双栏', kind: 'files' },
          { name: 'GitHub', kind: 'github' },
          { name: '代码', kind: 'folder' },
        ]
      : [
          { name: 'Xcode', kind: 'xcode' },
          { name: 'Cursor', kind: 'cursor' },
          { name: '流光译站', kind: 'translate' },
          { name: '闪电提醒', kind: 'remind' },
          { name: '双栏文件', kind: 'files' },
          { name: 'GitHub', kind: 'github' },
          { name: 'Obsidian', kind: 'obsidian' },
          { name: '代码目录', kind: 'folder' },
        ];

  const shelves =
    preset === 'developer'
      ? [
          { group: english ? 'DEV LINKS' : '本地与开发', items: ['vscode://lucent', 'localhost:5173', 'GitHub PRs', 'Swift 6 Docs'] },
          { group: english ? 'AI & SCRIPTS' : 'AI 与快捷脚本', items: ['!port-kill', '!img-compress', 'Claude MCP', ...(pinnedExtra ? ['★ PR 审查雷达'] : [])] },
        ]
      : [
          { group: english ? 'AI WORKFLOW' : 'AI 常用', items: ['Claude Code', 'Cursor IDE', 'Gemini CLI', ...(pinnedExtra ? ['★ PR 审查雷达'] : [])] },
          { group: english ? 'DOCS & PROTOCOLS' : '团队与协议', items: ['obsidian://vault', 'notion://wiki', 'Lucent 官网'] },
        ];

  return (
    <div style={{ position: 'relative', display: 'flex', flexDirection: 'column', gap: 12, flex: 1 }}>
      {/* Zone 1: Bento Tiles */}
      <div style={{ display: 'grid', gridTemplateColumns: `repeat(${cols}, 1fr)`, gap: 11 }}>
        {tiles.map((tile) => (
          <div
            key={tile.title}
            style={{
              padding: preset === 'compact4' ? '12px 13px' : '14px 16px',
              borderRadius: RADII.bento,
              background: t.bgCard,
              border: `1px solid ${t.rimOuter}`,
              boxShadow: t.cardShadow,
              display: 'flex',
              alignItems: 'center',
              gap: 12,
            }}
          >
            <SquircleBadge gradient={tile.grad} size={preset === 'compact4' ? 34 : 40}>
              {tile.icon}
            </SquircleBadge>
            <div style={{ minWidth: 0 }}>
              <div style={{ fontSize: preset === 'compact4' ? 14 : 15.5, fontWeight: 700, color: t.textPrimary, whiteSpace: 'nowrap' }}>
                {tile.title}
              </div>
              <div style={{ fontSize: 12, color: t.textTertiary, marginTop: 2 }}>{tile.sub}</div>
            </div>
          </div>
        ))}
      </div>

      {/* Zone 2: Omni Dock (8 or 16 slots) */}
      <div
        style={{
          padding: preset === 'compact4' ? '10px 14px' : '12px 15px',
          borderRadius: RADII.bento,
          background: t.bgWell,
          border: `1px solid ${t.rimOuter}`,
        }}
      >
        <div
          style={{
            display: 'flex',
            justifyContent: 'space-between',
            fontSize: 11,
            fontFamily: FONT_MONO,
            color: t.textTertiary,
            marginBottom: 8,
          }}
        >
          <span>{english ? `OMNI DOCK · ${dockItems.length} SLOTS` : `混合高频坞 · ${dockItems.length} 格混排`}</span>
          <span>{english ? 'Pinned First + Smart Fill' : '手动钉选优先 + 智能高频补位'}</span>
        </div>
        <div style={{ display: 'grid', gridTemplateColumns: 'repeat(8, 1fr)', gap: preset === 'compact4' ? 7 : 10 }}>
          {dockItems.map((item, idx) => (
            <div key={`${item.name}-${idx}`} style={{ display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 4 }}>
              <BespokeDockIcon kind={item.kind} size={preset === 'compact4' ? 34 : 40} />
              <span style={{ fontSize: 10.5, color: t.textSecondary, whiteSpace: 'nowrap' }}>{item.name}</span>
            </div>
          ))}
        </div>
      </div>

      {/* Zone 3: Multi-Group Named Bookmark Shelves */}
      <div style={{ display: 'flex', flexDirection: 'column', gap: 8 }}>
        {shelves.map((shelf) => (
          <div key={shelf.group} style={{ display: 'flex', alignItems: 'center', gap: 9 }}>
            <span
              style={{
                width: 96,
                fontSize: 11.5,
                fontFamily: FONT_MONO,
                fontWeight: 600,
                color: t.textTertiary,
                flexShrink: 0,
              }}
            >
              {shelf.group}
            </span>
            <div style={{ display: 'flex', gap: 8, flexWrap: 'nowrap' }}>
              {shelf.items.map((item) => {
                const isNew = item.startsWith('★');
                return (
                  <span
                    key={item}
                    style={{
                      padding: '5px 12px',
                      borderRadius: RADII.pill,
                      background: isNew ? t.accentBadgeBg : t.bgPill,
                      border: `1px solid ${isNew ? t.rimSelected : t.rimOuter}`,
                      color: isNew ? t.accentBadgeText : t.textSecondary,
                      fontSize: 12,
                      fontWeight: isNew ? 700 : 500,
                      display: 'inline-flex',
                      alignItems: 'center',
                      gap: 5,
                    }}
                  >
                    {isNew ? <IconSparkles size={12} color={t.accentCyan} /> : <IconBookmark size={11} color={t.textTertiary} />}
                    {item}
                  </span>
                );
              })}
            </div>
          </div>
        ))}
      </div>

      {/* Right-Click Context Menu Popover ("一键钉上主页") */}
      {showRightClickPin && (
        <div
          style={{
            position: 'absolute',
            right: 46,
            top: 96,
            width: 248,
            padding: 8,
            borderRadius: 16,
            background: t.bgPanelSolid,
            border: `1px solid ${t.rimSelected}`,
            boxShadow: t.panelShadow,
            transform: `scale(${spr(frame, 930, SPRING_BOUNCY)})`,
            display: 'flex',
            flexDirection: 'column',
            gap: 4,
          }}
        >
          {[
            { label: '钉上 Bento 大磁贴', active: false },
            { label: '钉入混合高频坞', active: false },
            { label: '一键钉入「AI 常用」胶囊架', active: true },
            { label: '自定义标题、图标与强调色...', active: false },
          ].map((opt) => (
            <div
              key={opt.label}
              style={{
                padding: '8px 12px',
                borderRadius: 10,
                background: opt.active ? t.accentGradient : 'transparent',
                color: opt.active ? '#fff' : t.textSecondary,
                fontSize: 12.5,
                fontWeight: opt.active ? 700 : 500,
                display: 'flex',
                alignItems: 'center',
                gap: 8,
              }}
            >
              <IconPin size={13} color={opt.active ? '#fff' : t.textTertiary} />
              {opt.label}
            </div>
          ))}
        </div>
      )}
    </div>
  );
};

export const Act1CustomHome: React.FC = () => {
  const frame = useCurrentFrame();

  // Dynamic Preset Timeline:
  // 0..420: balanced (3-col + 8-dock)
  // 420..760: developer (2-col + dev shelves)
  // 760..1360: compact4 (4-col + 16-dock + right-click pin at 930..1120 -> pinned at 1080+)
  // 1360..2064: Diagonal prism light-blade sweeps across screen -> Pure Frost + live EN toggle (1700..1880) -> back to ZH
  const preset: LayoutPreset =
    frame < 420 ? 'balanced' : frame < 760 ? 'developer' : frame < 1460 ? 'compact4' : 'balanced';

  const showRightClickPin = frame >= 920 && frame < 1100;
  const pinnedExtra = frame >= 1080;

  // Dual Theme Optical Wipe (frames 1380..1490)
  const wipeProgress = clampLerp(frame, [1380, 1480], [0, 1], Easing.inOut(Easing.cubic));
  const english = frame >= 1700 && frame < 1890;

  const activeTheme: ThemeMode = wipeProgress > 0.5 ? 'pure-frost' : 'prism-pulse';
  const enter = spr(frame, 8, SPRING_GLASS);

  const profiles = [
    { id: 'balanced', label: '均衡默认' },
    { id: 'developer', label: '开发者工作台' },
    { id: 'compact4', label: '4列 + 16格坞' },
    { id: 'minimal', label: '极简纯搜' },
  ];

  const renderStage = (mode: ThemeMode) => {
    const t = getTheme(mode);
    return (
      <AbsoluteFill>
        <AuroraBackdrop theme={mode} seedOffset={1200} />

        <div
          style={{
            position: 'absolute',
            inset: '78px 86px 104px',
            display: 'flex',
            alignItems: 'center',
            justifyContent: 'space-between',
            gap: 54,
            fontFamily: FONT_SANS,
          }}
        >
          {/* Left Narrative Column */}
          <div style={{ width: 690, display: 'flex', flexDirection: 'column', gap: 26 }}>
            <SceneHeader
              eyebrow="01 / 07 · CUSTOM LAUNCH PANEL"
              title="像搭积木一样，"
              highlight="布置你的 ⌥Space 主页。"
              subtitle="不把所有人塞进死板界面：分区、列数、混排坞、协议书签与主题语言，全部由你掌控。"
              theme={mode}
              frame={frame}
              maxWidth={680}
            />

            {/* Profile Selector Chips */}
            <div style={{ display: 'flex', flexDirection: 'column', gap: 12 }}>
              <div style={{ fontFamily: FONT_MONO, fontSize: 12.5, color: t.textTertiary, letterSpacing: '0.08em' }}>
                HOME PROFILES · 4 套官方预设 & 多场景切换
              </div>
              <div style={{ display: 'flex', gap: 10, flexWrap: 'wrap' }}>
                {profiles.map((p) => {
                  const isAct = p.id === preset;
                  return (
                    <div
                      key={p.id}
                      style={{
                        padding: '9px 16px',
                        borderRadius: RADII.pill,
                        background: isAct ? t.accentGradient : t.bgCard,
                        border: `1px solid ${isAct ? 'rgba(255,255,255,0.4)' : t.rimOuter}`,
                        color: isAct ? '#fff' : t.textSecondary,
                        fontSize: 14.5,
                        fontWeight: isAct ? 700 : 500,
                        boxShadow: isAct ? '0 10px 26px -6px rgba(56, 189, 248, 0.45)' : t.cardShadow,
                      }}
                    >
                      {p.label}
                    </div>
                  );
                })}
              </div>
            </div>

            {/* Dual Theme & Bilingual Live Switch Indicator */}
            <div
              style={{
                display: 'grid',
                gridTemplateColumns: '1fr 1fr',
                gap: 14,
                opacity: spr(frame, 36, SPRING_GLASS),
              }}
            >
              <div
                style={{
                  padding: '16px 18px',
                  borderRadius: RADII.card,
                  background: t.bgCard,
                  border: `1px solid ${mode === 'pure-frost' ? t.rimSelected : t.rimOuter}`,
                  boxShadow: t.cardShadow,
                }}
              >
                <div style={{ fontSize: 12, fontFamily: FONT_MONO, color: t.accentBadgeText, marginBottom: 4 }}>
                  DUAL LIQUID GLASS
                </div>
                <div style={{ fontSize: 18, fontWeight: 700, color: t.textPrimary }}>
                  {mode === 'prism-pulse' ? '霓彩流光 · Prism Pulse' : '凝霜留白 · Pure Frost'}
                </div>
                <div style={{ fontSize: 13, color: t.textTertiary, marginTop: 4 }}>
                  {mode === 'prism-pulse' ? '深空棱镜高光 · 专注沉浸' : '通透珠光留白 · 明亮清爽'}
                </div>
              </div>

              <div
                style={{
                  padding: '16px 18px',
                  borderRadius: RADII.card,
                  background: t.bgCard,
                  border: `1px solid ${english ? t.rimSelected : t.rimOuter}`,
                  boxShadow: t.cardShadow,
                }}
              >
                <div style={{ fontSize: 12, fontFamily: FONT_MONO, color: t.accentBadgeText, marginBottom: 4 }}>
                  ZERO-RESTART I18N
                </div>
                <div style={{ fontSize: 18, fontWeight: 700, color: t.textPrimary }}>
                  {english ? 'English · Real-Time' : '简体中文 · 免重启秒切'}
                </div>
                <div style={{ fontSize: 13, color: t.textTertiary, marginTop: 4 }}>
                  主题与语言实时广播给全部插件
                </div>
              </div>
            </div>
          </div>

          {/* Right Live 880x544 Panel Showcase with Living 3D Parallax & Animated Right-Click Cursor */}
          <div
            style={{
              position: 'relative',
              transform: `perspective(1200px) rotateY(${-3.5 + Math.sin(frame * 0.015) * 1.4 + (1 - enter) * 10}deg) scale(${0.92 + enter * 0.08})`,
              opacity: enter,
            }}
          >
            <LiquidGlassPanel
              theme={mode}
              english={english}
              dimensionTag={`home-layout.json · ${preset.toUpperCase()}`}
              toastText={pinnedExtra && frame < 1340 ? '✓ 已钉入「AI 常用」胶囊架 · 支持撤回' : undefined}
              placeholder={
                english
                  ? 'Type to launch apps, search files, clipboard, !scripts or plugins...'
                  : '呼出即见专属主页 · 直接打字免前缀全搜...'
              }
            >
              <HomePanelContent
                theme={mode}
                preset={preset}
                frame={frame}
                english={english}
                showRightClickPin={showRightClickPin}
                pinnedExtra={pinnedExtra}
              />
            </LiquidGlassPanel>

            {/* Smooth Animated Cursor demonstrating Right-Click -> One-Click Pin */}
            {frame >= 850 && frame <= 1160 && (
              <AnimatedCursor
                x={clampLerp(frame, [850, 920], [520, 665]) + clampLerp(frame, [950, 1055], [0, 38])}
                y={clampLerp(frame, [850, 920], [280, 185]) + clampLerp(frame, [950, 1055], [0, 118])}
                clicking={(frame >= 918 && frame <= 934) || (frame >= 1068 && frame <= 1085)}
                rippleProgress={
                  frame >= 1068
                    ? clampLerp(frame, [1068, 1110], [0, 1])
                    : clampLerp(frame, [918, 955], [0, 1])
                }
                opacity={clampLerp(frame, [850, 875], [0, 1]) * clampLerp(frame, [1115, 1160], [1, 0])}
              />
            )}
          </div>
        </div>
      </AbsoluteFill>
    );
  };

  // Clip-path diagonal glass sweep from Prism Pulse -> Pure Frost
  const wipePct = wipeProgress * 130;

  return (
    <AbsoluteFill>
      {renderStage('prism-pulse')}

      {wipeProgress > 0.001 && (
        <AbsoluteFill
          style={{
            clipPath: `polygon(0 0, ${wipePct}% 0, ${Math.max(0, wipePct - 24)}% 100%, 0 100%)`,
          }}
        >
          {renderStage('pure-frost')}
        </AbsoluteFill>
      )}

      {/* Optical Prism Sweep Blade — aligned to exact clip-path slope atan(0.24*1920/1080)=23.1deg */}
      {wipeProgress > 0.01 && wipeProgress < 0.99 && (
        <div
          style={{
            position: 'absolute',
            top: -160,
            bottom: -160,
            left: `${wipePct - 12}%`,
            width: 10,
            transform: 'rotate(23.1deg)',
            background: 'linear-gradient(180deg, #38bdf8, #ffffff, #c084fc, #f472b6)',
            boxShadow: '0 0 38px 12px rgba(103, 232, 249, 0.72)',
            zIndex: 70,
            pointerEvents: 'none',
          }}
        />
      )}

      <BottomCaptionBar beats={CAPTIONS} frame={frame} theme={activeTheme} />
    </AbsoluteFill>
  );
};
