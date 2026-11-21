import React from 'react';
import { AbsoluteFill, useCurrentFrame } from 'remotion';
import { AuroraBackdrop } from '../components/AuroraBackdrop';
import {
  IconBell,
  IconBookmark,
  IconCheck,
  IconEyeOff,
  IconGlobe,
  IconLock,
  IconPhone,
  IconPuzzle,
  IconShield,
  IconSliders,
  IconSparkles,
  SquircleBadge,
} from '../components/Icons';
import { KeycapBadge } from '../components/KeycapBadge';
import { BottomCaptionBar, CaptionBeat, SceneHeader } from '../components/KineticCaption';
import { AnimatedCursor, CameraStage, MacStatusBarStrip } from '../components/MacChrome';
import { spr, SPRING_BOUNCY, SPRING_GLASS } from '../design/motion';
import { FONT_MONO, FONT_SANS, PRISM_PULSE, RADII } from '../design/tokens';

const CAPTIONS: CaptionBeat[] = [
  { start: 30, end: 460, tag: 'MENU BAR & HOTKEYS', text: '顶部状态栏三档瘦身排序 + 全链路静默热键与三层冲突检测，不改源码即可覆盖唤醒词' },
  { start: 480, end: 1180, tag: '7 NATIVE PLUGINS', text: '7 款官方精选插件全原生 Swift 6 预编译（开箱即跑无需外部环境）：译站、三端书签、闪电提醒与桌面中控' },
  { start: 1200, end: 1620, tag: 'PLUGIN V3.7', text: '支持无边框透明桌面悬浮挂件：120Hz 自由拖拽、点击穿透与坐标记忆，关窗瞬间归还内存' },
  { start: 1640, end: 2020, tag: 'SMART STORE', text: '单地址框粘贴 GitHub / JSON / ZIP 自动嗅探订阅，强制 64 位 SHA-256 校验与权限升级审阅' },
];

const PLUGINS = [
  {
    id: 'translate-hub',
    name: '流光译站',
    tag: 'tr · 划词 / OCR / 本地 Ollama',
    desc: '跨应用划词即弹工具栏、截图 OCR 翻译、朗读与生词本导出 Anki',
    grad: 'linear-gradient(135deg,#0284c7,#7c3aed)',
    icon: <IconGlobe size={20} />,
  },
  {
    id: 'browser-hub',
    name: '三端书签与历史',
    tag: 'bh · Safari / Chrome / Edge',
    desc: '无锁秒搜多配置档书签与浏览历史，支持指定浏览器打开',
    grad: 'linear-gradient(135deg,#0ea5e9,#06b6d4)',
    icon: <IconBookmark size={20} />,
  },
  {
    id: 'quick-remind',
    name: '闪电提醒',
    tag: 'rem · 10m 喝水',
    desc: '自然语言秒建倒计时与番茄钟，直通系统原生提醒事项零后台常驻',
    grad: 'linear-gradient(135deg,#f59e0b,#ea580c)',
    icon: <IconBell size={20} />,
  },
  {
    id: 'mac-pilot',
    name: '桌面中控台',
    tag: 'mp · 16 项系统设置秒达',
    desc: '音量防休眠、安全退盘、访达原地新建文件一站掌控',
    grad: 'linear-gradient(135deg,#6366f1,#38bdf8)',
    icon: <IconSliders size={20} />,
  },
  {
    id: 'screen-shield',
    name: '状态屏遮罩',
    tag: 'sh · 防误触保护屏',
    desc: '擦键盘清洁黑屏或编译防误碰告示，长按 Esc 2 秒解锁',
    grad: 'linear-gradient(135deg,#ec4899,#8b5cf6)',
    icon: <IconEyeOff size={20} />,
  },
  {
    id: 'lumalink-companion',
    name: 'LumaLink 伴侣',
    tag: 'll · 手机远控伴侣',
    desc: '配对二维码、物理/穿透网卡切换、远控物理防窥黑屏与 HiDPI 切换',
    grad: 'linear-gradient(135deg,#10b981,#0ea5e9)',
    icon: <IconPhone size={20} />,
  },
  {
    id: 'notion-bookmarks',
    name: 'Notion 加密书签箱',
    tag: 'nb · 256-bit 加密托管',
    desc: '一键静默速存剪贴板链接并同步本地秒搜，密钥全托管于保险箱',
    grad: 'linear-gradient(135deg,#475569,#7c5cfc)',
    icon: <IconLock size={20} />,
  },
];

export const Act4PluginEcosystem: React.FC = () => {
  const frame = useCurrentFrame();

  const phase: 'menubar' | 'plugins' | 'widget' | 'store' =
    frame < 470 ? 'menubar' : frame < 1190 ? 'plugins' : frame < 1630 ? 'widget' : 'store';

  // Active highlighted plugin index cycling through all 7
  const activePluginIdx =
    phase === 'plugins'
      ? Math.min(PLUGINS.length - 1, Math.floor((frame - 470) / 100))
      : 0;

  // Floating glass widget smooth 120Hz orbital drift
  const widgetX = Math.sin(frame * 0.035) * 42;
  const widgetY = Math.cos(frame * 0.028) * 18;
  const shaVerified = frame >= 1740;

  return (
    <AbsoluteFill style={{ fontFamily: FONT_SANS }}>
      <AuroraBackdrop theme="prism-pulse" seedOffset={8160} />

      <div
        style={{
          position: 'absolute',
          inset: '72px 88px 104px',
          display: 'flex',
          flexDirection: 'column',
          gap: 24,
        }}
      >
        <div style={{ display: 'flex', alignItems: 'flex-end', justifyContent: 'space-between' }}>
          <SceneHeader
            eyebrow="04 / 07 · DEEP CUSTOMIZATION & PLUGIN V3.7"
            title="从菜单栏到透明挂件，"
            highlight="装上即原生一等公民。"
            theme="prism-pulse"
            frame={frame}
            maxWidth={1060}
            fontSize={44}
          />

          <div style={{ display: 'flex', gap: 10, paddingBottom: 6 }}>
            {[
              { id: 'menubar', label: '菜单栏 & 热键' },
              { id: 'plugins', label: '7 款官方原生插件' },
              { id: 'widget', label: 'v3.7 透明挂件' },
              { id: 'store', label: '智能商店验签' },
            ].map((p) => {
              const act = p.id === phase;
              return (
                <div
                  key={p.id}
                  style={{
                    padding: '9px 15px',
                    borderRadius: RADII.pill,
                    background: act ? PRISM_PULSE.accentGradient : PRISM_PULSE.bgCard,
                    border: `1px solid ${act ? 'rgba(255,255,255,0.45)' : PRISM_PULSE.rimOuter}`,
                    color: act ? '#fff' : PRISM_PULSE.textSecondary,
                    fontSize: 13.5,
                    fontWeight: act ? 700 : 500,
                  }}
                >
                  {p.label}
                </div>
              );
            })}
          </div>
        </div>

        <div style={{ flex: 1, minHeight: 0, display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
          {/* PHASE 1: MENU BAR SLIMMING + SILENT HOTKEYS */}
          {phase === 'menubar' && (
            <CameraStage enterFrame={0} breathScale={0.008} tiltDeg={0.6}>
            <div style={{ width: '100%', display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 30 }}>
              {/* Left: Top macOS Menu Bar Customization */}
              <div
                style={{
                  borderRadius: 24,
                  background: PRISM_PULSE.bgCard,
                  border: `1px solid ${PRISM_PULSE.rimOuter}`,
                  boxShadow: PRISM_PULSE.panelShadow,
                  overflow: 'hidden',
                  display: 'flex',
                  flexDirection: 'column',
                }}
              >
                <MacStatusBarStrip theme="prism-pulse" activeApp="Lucent 状态栏" />
                <div style={{ padding: 26, display: 'flex', flexDirection: 'column', gap: 16 }}>
                <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
                  <span style={{ fontSize: 22, fontWeight: 800, color: '#fff' }}>顶部状态栏菜单瘦身</span>
                  <span style={{ fontFamily: FONT_MONO, fontSize: 12, color: '#67e8f9' }}>3 套预设 · 4 款图标</span>
                </div>
                <div style={{ display: 'flex', gap: 10 }}>
                  {['精简核心', '效率常用', '完整全量'].map((preset, i) => {
                    const sel = (frame < 240 ? 1 : 0) === i;
                    return (
                      <div
                        key={preset}
                        style={{
                          padding: '7px 14px',
                          borderRadius: RADII.pill,
                          background: sel ? PRISM_PULSE.accentGradient : PRISM_PULSE.bgPill,
                          color: '#fff',
                          fontSize: 13,
                          fontWeight: 700,
                        }}
                      >
                        {preset}
                      </div>
                    );
                  })}
                </div>
                <div
                  style={{
                    padding: 16,
                    borderRadius: 16,
                    background: PRISM_PULSE.bgWell,
                    border: `1px solid ${PRISM_PULSE.rimOuter}`,
                    display: 'flex',
                    flexDirection: 'column',
                    gap: 10,
                  }}
                >
                  {[
                    { name: '唤起流光面板', key: '⌥Space', on: true },
                    { name: '高清截图标注 / OCR', key: '⌥A / ⌥O', on: true },
                    { name: '物理鼠标 120Hz 平滑滚轮', key: '✓ 已启用', on: true },
                    { name: '低频维护与诊断项', key: '收纳至二级子菜单 ▸', on: frame < 240 },
                  ].map((item) => (
                    <div
                      key={item.name}
                      style={{
                        display: 'flex',
                        justifyContent: 'space-between',
                        alignItems: 'center',
                        padding: '10px 14px',
                        borderRadius: 12,
                        background: item.on ? 'rgba(255,255,255,0.06)' : 'rgba(255,255,255,0.02)',
                        opacity: item.on ? 1 : 0.48,
                      }}
                    >
                      <span style={{ fontSize: 14.5, color: '#fff', fontWeight: 600 }}>{item.name}</span>
                      <span style={{ fontFamily: FONT_MONO, fontSize: 12, color: '#67e8f9' }}>{item.key}</span>
                    </div>
                  ))}
                </div>
                </div>
              </div>

              {/* Right: Silent Hotkeys & PluginUserOverrides */}
              <div
                style={{
                  padding: 28,
                  borderRadius: 24,
                  background: PRISM_PULSE.bgCard,
                  border: `1px solid ${PRISM_PULSE.rimOuter}`,
                  boxShadow: PRISM_PULSE.panelShadow,
                  display: 'flex',
                  flexDirection: 'column',
                  gap: 18,
                }}
              >
                <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
                  <span style={{ fontSize: 22, fontWeight: 800, color: '#fff' }}>静默热键与不改源码覆写</span>
                  <span style={{ fontFamily: FONT_MONO, fontSize: 12, color: '#34d399' }}>三层冲突检测 ✓</span>
                </div>
                <div style={{ fontSize: 15, color: PRISM_PULSE.textSecondary, lineHeight: 1.6 }}>
                  每一条插件细分动作均可独立录制静默全局热键，按下后在后台瞬时完成，**绝不打断全屏应用焦点**；随时改唤醒词与排序权重，升级插件完整保留个人配置。
                </div>
                <div style={{ display: 'flex', flexDirection: 'column', gap: 10 }}>
                  {[
                    { act: '流光译站 · 划词翻译当前选中文本', keys: ['⌥', 'T'], mode: '静默后台执行' },
                    { act: 'Notion 书签 · 速存剪贴板链接', keys: ['⌥', '⇧', 'B'], mode: '静默后台执行' },
                    { act: '桌面中控台 · 一键防休眠常亮', keys: ['⌥', '⇧', 'C'], mode: '关键词覆写: awake' },
                  ].map((hk) => (
                    <div
                      key={hk.act}
                      style={{
                        padding: '12px 15px',
                        borderRadius: 14,
                        background: PRISM_PULSE.bgWell,
                        border: `1px solid ${PRISM_PULSE.rimOuter}`,
                        display: 'flex',
                        justifyContent: 'space-between',
                        alignItems: 'center',
                      }}
                    >
                      <div>
                        <div style={{ fontSize: 14.5, fontWeight: 700, color: '#fff' }}>{hk.act}</div>
                        <div style={{ fontSize: 12, color: '#a78bfa', marginTop: 2 }}>{hk.mode}</div>
                      </div>
                      <KeycapBadge keys={hk.keys} size="sm" active />
                    </div>
                  ))}
                </div>
              </div>
            </div>
            </CameraStage>
          )}

          {/* PHASE 2: 7 OFFICIAL NATIVE SWIFT 6 PLUGINS SHOWCASE */}
          {phase === 'plugins' && (
            <CameraStage enterFrame={470} breathScale={0.008} tiltDeg={0.6}>
            <div style={{ width: '100%', display: 'flex', flexDirection: 'column', gap: 22 }}>
              <div style={{ display: 'grid', gridTemplateColumns: 'repeat(4, 1fr)', gap: 16 }}>
                {PLUGINS.slice(0, 4).map((p, idx) => {
                  const focused = idx === activePluginIdx;
                  const cp = spr(frame, 485 + idx * 7, SPRING_GLASS);
                  return (
                    <div
                      key={p.id}
                      style={{
                        padding: 20,
                        borderRadius: 22,
                        background: focused ? 'rgba(34, 34, 78, 0.92)' : PRISM_PULSE.bgCard,
                        border: `1.5px solid ${focused ? PRISM_PULSE.rimSelected : PRISM_PULSE.rimOuter}`,
                        boxShadow: focused
                          ? '0 24px 56px -12px rgba(56,189,248,0.34), inset 0 1px 0 rgba(255,255,255,0.35)'
                          : PRISM_PULSE.cardShadow,
                        transform: `translateY(${focused ? -8 : (1 - cp) * 20}px) scale(${focused ? 1.03 : 1})`,
                        opacity: cp,
                        display: 'flex',
                        flexDirection: 'column',
                        gap: 11,
                      }}
                    >
                      <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between' }}>
                        <SquircleBadge gradient={p.grad} size={44}>
                          {p.icon}
                        </SquircleBadge>
                        <span style={{ fontFamily: FONT_MONO, fontSize: 11, color: '#67e8f9', background: 'rgba(34,211,238,0.12)', padding: '3px 8px', borderRadius: 8 }}>
                          原生 arm64 Swift
                        </span>
                      </div>
                      <div style={{ fontSize: 19, fontWeight: 800, color: '#fff' }}>{p.name}</div>
                      <div style={{ fontFamily: FONT_MONO, fontSize: 11.5, color: '#c4b5fd' }}>{p.tag}</div>
                      <div style={{ fontSize: 13.5, color: PRISM_PULSE.textSecondary, lineHeight: 1.5 }}>{p.desc}</div>
                    </div>
                  );
                })}
              </div>

              <div style={{ display: 'grid', gridTemplateColumns: 'repeat(3, 1fr)', gap: 16, padding: '0 110px' }}>
                {PLUGINS.slice(4).map((p, idx) => {
                  const realIdx = idx + 4;
                  const focused = realIdx === activePluginIdx;
                  const cp = spr(frame, 520 + idx * 7, SPRING_GLASS);
                  return (
                    <div
                      key={p.id}
                      style={{
                        padding: 20,
                        borderRadius: 22,
                        background: focused ? 'rgba(34, 34, 78, 0.92)' : PRISM_PULSE.bgCard,
                        border: `1.5px solid ${focused ? PRISM_PULSE.rimSelected : PRISM_PULSE.rimOuter}`,
                        boxShadow: focused
                          ? '0 24px 56px -12px rgba(244,114,182,0.34), inset 0 1px 0 rgba(255,255,255,0.35)'
                          : PRISM_PULSE.cardShadow,
                        transform: `translateY(${focused ? -8 : (1 - cp) * 20}px) scale(${focused ? 1.03 : 1})`,
                        opacity: cp,
                        display: 'flex',
                        flexDirection: 'column',
                        gap: 11,
                      }}
                    >
                      <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between' }}>
                        <SquircleBadge gradient={p.grad} size={44}>
                          {p.icon}
                        </SquircleBadge>
                        <span style={{ fontFamily: FONT_MONO, fontSize: 11, color: '#34d399', background: 'rgba(52,211,153,0.12)', padding: '3px 8px', borderRadius: 8 }}>
                          原生 arm64 Swift
                        </span>
                      </div>
                      <div style={{ fontSize: 19, fontWeight: 800, color: '#fff' }}>{p.name}</div>
                      <div style={{ fontFamily: FONT_MONO, fontSize: 11.5, color: '#f472b6' }}>{p.tag}</div>
                      <div style={{ fontSize: 13.5, color: PRISM_PULSE.textSecondary, lineHeight: 1.5 }}>{p.desc}</div>
                    </div>
                  );
                })}
              </div>
            </div>
            </CameraStage>
          )}

          {/* PHASE 3: PLUGIN V3.7 BORDERLESS TRANSPARENT FLOATING DESKTOP WIDGET */}
          {phase === 'widget' && (
            <CameraStage enterFrame={1190} breathScale={0.008} tiltDeg={0.7}>
            <div style={{ width: '100%', display: 'grid', gridTemplateColumns: '0.95fr 1.05fr', gap: 36, alignItems: 'center' }}>
              <div style={{ display: 'flex', flexDirection: 'column', gap: 18 }}>
                <div style={{ fontFamily: FONT_MONO, fontSize: 13, color: '#67e8f9', letterSpacing: '0.08em' }}>
                  PLUGIN V3.7 · FREE-CANVAS FLOATING WINDOW
                </div>
                <div style={{ fontSize: 38, fontWeight: 800, color: '#fff', lineHeight: 1.2 }}>
                  既能零前端出原生卡片，
                  <br />
                  也能做无边框透明挂件。
                </div>
                <div style={{ fontSize: 16.5, color: PRISM_PULSE.textSecondary, lineHeight: 1.65 }}>
                  普通插件仅需一份 <code style={{ fontFamily: FONT_MONO, color: '#67e8f9' }}>plugin.json</code> 即可自动生成带滑块、密钥框、路径选择器的原生设置页；进阶插件申请 <code style={{ fontFamily: FONT_MONO, color: '#c4b5fd' }}>floatingWindow</code> 后，更可呈现自定义 HTML/CSS/Canvas 透明玻璃桌面挂件。
                </div>
                <div style={{ display: 'flex', gap: 10, flexWrap: 'wrap' }}>
                  {['120Hz 无边框拖拽', '支持点击穿透', '自动记忆屏幕坐标', '关窗即刻销毁零常驻'].map((tag) => (
                    <span
                      key={tag}
                      style={{
                        padding: '7px 14px',
                        borderRadius: RADII.pill,
                        background: PRISM_PULSE.accentBadgeBg,
                        border: `1px solid ${PRISM_PULSE.accentBadgeBorder}`,
                        color: PRISM_PULSE.accentBadgeText,
                        fontSize: 13.5,
                        fontWeight: 600,
                      }}
                    >
                      {tag}
                    </span>
                  ))}
                </div>
              </div>

              {/* Floating Translucent Desktop Glass Widget Demo */}
              <div
                style={{
                  position: 'relative',
                  height: 440,
                  borderRadius: 28,
                  background: 'radial-gradient(circle at 30% 30%, rgba(56,189,248,0.18), rgba(124,92,252,0.14), rgba(10,12,28,0.85))',
                  border: `1px solid ${PRISM_PULSE.rimOuter}`,
                  overflow: 'hidden',
                  display: 'flex',
                  alignItems: 'center',
                  justifyContent: 'center',
                }}
              >
                {/* Simulated Background Code Editor */}
                <div style={{ position: 'absolute', inset: 24, opacity: 0.34, fontFamily: FONT_MONO, fontSize: 13, color: '#94a3b8', lineHeight: 1.8 }}>
                  <div>import LucentCore</div>
                  <div>struct FloatingTelemetryWidget: View {'{'}</div>
                  <div>&nbsp;&nbsp;let refreshInterval: Duration = .seconds(1)</div>
                  <div>&nbsp;&nbsp;// Click-through transparent glass overlay...</div>
                  <div>{'}'}</div>
                </div>

                {/* Translucent Borderless Floating Glass Widget */}
                <div
                  style={{
                    width: 440,
                    padding: 24,
                    borderRadius: 26,
                    background: 'rgba(18, 22, 48, 0.72)',
                    border: '1.5px solid rgba(103, 232, 249, 0.55)',
                    boxShadow: '0 32px 72px rgba(0,0,0,0.65), 0 0 48px rgba(56,189,248,0.22), inset 0 1px 0 rgba(255,255,255,0.35)',
                    transform: `translate(${widgetX}px, ${widgetY}px)`,
                    display: 'flex',
                    flexDirection: 'column',
                    gap: 16,
                  }}
                >
                  <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
                    <div style={{ display: 'flex', alignItems: 'center', gap: 10 }}>
                      <IconSparkles size={18} color="#67e8f9" />
                      <span style={{ fontSize: 16, fontWeight: 700, color: '#fff' }}>番茄专注 · 透明悬浮挂件</span>
                    </div>
                    <span style={{ fontFamily: FONT_MONO, fontSize: 11.5, color: '#34d399' }}>
                      CLICK-THROUGH ON
                    </span>
                  </div>
                  <div style={{ display: 'flex', alignItems: 'baseline', justifyContent: 'space-between' }}>
                    <span style={{ fontFamily: FONT_MONO, fontSize: 48, fontWeight: 800, color: '#fff' }}>24:18</span>
                    <span style={{ fontSize: 14, color: '#c4b5fd' }}>下一项：代码评审 15:00</span>
                  </div>
                  <div style={{ height: 6, borderRadius: 99, background: 'rgba(255,255,255,0.12)', overflow: 'hidden' }}>
                    <div style={{ width: '74%', height: '100%', background: PRISM_PULSE.accentGradient }} />
                  </div>
                </div>

                {/* Live Animated Dragging Cursor Gliding With the 120Hz Transparent Glass Widget */}
                <AnimatedCursor
                  x={435 + widgetX}
                  y={162 + widgetY}
                  clicking
                />
              </div>
            </div>
            </CameraStage>
          )}

          {/* PHASE 4: SINGLE-BOX SMART STORE + SHA-256 VERIFICATION */}
          {phase === 'store' && (
            <CameraStage enterFrame={1630} breathScale={0.008} tiltDeg={0.6}>
            <div style={{ width: '100%', maxWidth: 1160, display: 'flex', flexDirection: 'column', gap: 22 }}>
              <div
                style={{
                  padding: 28,
                  borderRadius: 26,
                  background: PRISM_PULSE.bgPanelSolid,
                  border: `1.5px solid ${shaVerified ? 'rgba(52, 211, 153, 0.55)' : PRISM_PULSE.rimSelected}`,
                  boxShadow: PRISM_PULSE.panelShadow,
                  display: 'flex',
                  flexDirection: 'column',
                  gap: 20,
                }}
              >
                <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
                  <div style={{ display: 'flex', alignItems: 'center', gap: 12 }}>
                    <IconPuzzle size={22} color="#67e8f9" />
                    <span style={{ fontSize: 22, fontWeight: 800, color: '#fff' }}>单地址框智能商店订阅与验签</span>
                  </div>
                  <span style={{ fontFamily: FONT_MONO, fontSize: 12.5, color: '#34d399' }}>
                    GitHub 仓库 · 商店 JSON · .zip 自动嗅探
                  </span>
                </div>

                {/* URL Input Bar */}
                <div
                  style={{
                    padding: '15px 20px',
                    borderRadius: 16,
                    background: PRISM_PULSE.bgInput,
                    border: `1px solid ${PRISM_PULSE.rimSelected}`,
                    fontFamily: FONT_MONO,
                    fontSize: 16,
                    color: '#67e8f9',
                    display: 'flex',
                    justifyContent: 'space-between',
                    alignItems: 'center',
                  }}
                >
                  <span>https://github.com/lengsukq/Lucent/tree/main/plugin-demo</span>
                  <span
                    style={{
                      padding: '6px 14px',
                      borderRadius: RADII.pill,
                      background: shaVerified ? '#059669' : PRISM_PULSE.accentGradient,
                      color: '#fff',
                      fontFamily: FONT_SANS,
                      fontSize: 13.5,
                      fontWeight: 700,
                    }}
                  >
                    {shaVerified ? '✓ SHA-256 校验通过' : '嗅探清单中...'}
                  </span>
                </div>

                {/* Security Audit Strip */}
                <div
                  style={{
                    display: 'grid',
                    gridTemplateColumns: 'repeat(3, 1fr)',
                    gap: 16,
                    opacity: spr(frame, 1730, SPRING_BOUNCY),
                  }}
                >
                  {[
                    { icon: <IconShield size={18} color="#34d399" />, title: '64 位 SHA-256 强校验', desc: '防中间人篡改，校验失败立即拦截' },
                    { icon: <IconLock size={18} color="#67e8f9" />, title: '权限升级差异确认', desc: '新增网络或系统权限必经显式审批' },
                    { icon: <IconCheck size={18} color="#c4b5fd" />, title: '热更新完整保留配置', desc: '升级后自动继承自定义热键与保险箱密钥' },
                  ].map((item) => (
                    <div
                      key={item.title}
                      style={{
                        padding: 18,
                        borderRadius: 16,
                        background: PRISM_PULSE.bgWell,
                        border: `1px solid ${PRISM_PULSE.rimOuter}`,
                        display: 'flex',
                        flexDirection: 'column',
                        gap: 8,
                      }}
                    >
                      <div style={{ display: 'flex', alignItems: 'center', gap: 9, fontSize: 16, fontWeight: 700, color: '#fff' }}>
                        {item.icon} {item.title}
                      </div>
                      <div style={{ fontSize: 13.5, color: PRISM_PULSE.textSecondary }}>{item.desc}</div>
                    </div>
                  ))}
                </div>
              </div>
            </div>
            </CameraStage>
          )}
        </div>
      </div>

      <BottomCaptionBar beats={CAPTIONS} frame={frame} theme="prism-pulse" />
    </AbsoluteFill>
  );
};
