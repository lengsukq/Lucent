import React from 'react';
import { AbsoluteFill, Easing, useCurrentFrame } from 'remotion';
import { AuroraBackdrop } from '../components/AuroraBackdrop';
import {
  IconCheck,
  IconCode,
  IconShield,
  IconSparkles,
  IconTerminal,
  IconZap,
  SquircleBadge,
} from '../components/Icons';
import { BottomCaptionBar, CaptionBeat, SceneHeader } from '../components/KineticCaption';
import { LiquidGlassPanel } from '../components/LiquidGlassPanel';
import { clampLerp, spr, SPRING_BOUNCY, SPRING_GLASS, typewriter } from '../design/motion';
import { FONT_MONO, FONT_SANS, PRISM_PULSE, RADII } from '../design/tokens';

const CAPTIONS: CaptionBeat[] = [
  { start: 30, end: 760, tag: 'MCP · 01 造插件', text: '不会写代码也能定制：一句话让 AI 调用 lucent-mcp 生成插件、沙箱实测并 350ms 实时热加载生效' },
  { start: 780, end: 1520, tag: 'MCP · 02 写脚本', text: '一句话创建单文件快捷脚本，并由 AI 自动手绘 64×64 专属矢量 SVG 图标直达 ⌥Space' },
  { start: 1540, end: 2260, tag: 'MCP · 03 排主页', text: '连布局都无需手动拖拽：对 AI 说出你的工作流，lucent_update_home_layout 瞬间热刷新面板' },
];

type ForgeScenario = 'plugin' | 'script' | 'home';

export const Act5McpCoCreation: React.FC = () => {
  const frame = useCurrentFrame();

  const scenario: ForgeScenario =
    frame < 780 ? 'plugin' : frame < 1540 ? 'script' : 'home';

  const localF = scenario === 'plugin' ? frame : scenario === 'script' ? frame - 780 : frame - 1540;

  const promptFull =
    scenario === 'plugin'
      ? '“帮我造个 PR 审查雷达插件：输入 pr 列出待我 Review 的 PR，凭据存入加密保险箱。”'
      : scenario === 'script'
      ? '“写个清理 3000/5173 端口的 Zsh 快捷脚本，顺便画一枚发光清理图标 SVG。”'
      : '“帮我配一套极简开发者启动面板，放好双栏文件台、端口清理脚本与 GitHub 书签架。”';

  const promptTyped = typewriter(promptFull, localF, 35, 32);

  // Optical Energy Conduit Beam firing from Left AI Terminal -> Right Live Lucent Panel
  const beamProgress = clampLerp(localF, [360, 490], [0, 1], Easing.inOut(Easing.cubic));
  const reloaded = localF >= 475;
  const reloadPop = spr(localF, 475, SPRING_BOUNCY);

  const steps =
    scenario === 'plugin'
      ? [
          { tool: 'lucent_scaffold_plugin', note: '生成插件骨架与 manifest', at: 185 },
          { tool: 'lucent_validate_plugin', note: '静态契约与权限边界校验', at: 265 },
          { tool: 'lucent_run_plugin_test', note: 'Seatbelt 沙箱实跑 PASS', at: 345 },
        ]
      : scenario === 'script'
      ? [
          { tool: 'lucent_upsert_script', note: '写入 @lucent.* 单文件脚本', at: 185 },
          { tool: 'svg_icon_sanitize', note: '生成并安检 64×64 专属 SVG', at: 265 },
          { tool: 'lucent_run_script_test', note: '沙箱验证退出码 0 PASS', at: 345 },
        ]
      : [
          { tool: 'lucent_get_home_layout', note: '读取当前 home-layout.json', at: 185 },
          { tool: 'lucent_upsert_home_item', note: '写入双栏台与书签胶囊架', at: 265 },
          { tool: 'lucent_update_home_layout', note: '零轮询热刷新活跃面板', at: 345 },
        ];

  return (
    <AbsoluteFill style={{ fontFamily: FONT_SANS }}>
      <AuroraBackdrop theme="prism-pulse" intensity={1.15} seedOffset={10200} />

      <div
        style={{
          position: 'absolute',
          inset: '68px 72px 104px',
          display: 'flex',
          flexDirection: 'column',
          gap: 22,
        }}
      >
        {/* Top Row: Climax Headline + 3-Scenario Pills */}
        <div style={{ display: 'flex', alignItems: 'flex-end', justifyContent: 'space-between' }}>
          <SceneHeader
            eyebrow="05 / 07 · BUILT-IN LUCENT-MCP (20 TOOLS)"
            title="一句话 AI 十秒共创："
            highlight="造插件、写脚本、排主页。"
            theme="prism-pulse"
            frame={frame}
            maxWidth={1120}
            fontSize={44}
          />

          <div style={{ display: 'flex', gap: 10, paddingBottom: 6 }}>
            {[
              { id: 'plugin', num: '01', label: '一句话造插件' },
              { id: 'script', num: '02', label: '写脚本绘 SVG' },
              { id: 'home', num: '03', label: 'AI 实时排主页' },
            ].map((s) => {
              const act = s.id === scenario;
              return (
                <div
                  key={s.id}
                  style={{
                    padding: '9px 15px',
                    borderRadius: RADII.pill,
                    background: act ? PRISM_PULSE.accentGradient : PRISM_PULSE.bgCard,
                    border: `1px solid ${act ? 'rgba(255,255,255,0.48)' : PRISM_PULSE.rimOuter}`,
                    color: act ? '#fff' : PRISM_PULSE.textSecondary,
                    fontSize: 13.5,
                    fontWeight: act ? 700 : 500,
                    display: 'inline-flex',
                    alignItems: 'center',
                    gap: 8,
                    boxShadow: act ? '0 10px 28px -6px rgba(244,114,182,0.5)' : PRISM_PULSE.cardShadow,
                  }}
                >
                  <span style={{ fontFamily: FONT_MONO, fontSize: 12, opacity: 0.85 }}>{s.num}</span>
                  <span>{s.label}</span>
                </div>
              );
            })}
          </div>
        </div>

        {/* Dual-Stage Forge: Left AI MCP Console ==[Energy Conduit]==> Right Live Lucent Panel */}
        <div
          style={{
            position: 'relative',
            flex: 1,
            minHeight: 0,
            display: 'grid',
            gridTemplateColumns: '770px 100px 880px',
            alignItems: 'center',
            justifyContent: 'center',
          }}
        >
          {/* LEFT: AI Assistant + lucent-mcp Stdio JSON-RPC Console */}
          <div
            style={{
              height: 544,
              borderRadius: 26,
              background: 'rgba(11, 12, 29, 0.92)',
              border: `1.5px solid ${PRISM_PULSE.rimSelected}`,
              boxShadow: PRISM_PULSE.panelShadow,
              display: 'flex',
              flexDirection: 'column',
              overflow: 'hidden',
            }}
          >
            {/* Console Header */}
            <div
              style={{
                padding: '14px 20px',
                background: PRISM_PULSE.studioHead,
                borderBottom: `1px solid ${PRISM_PULSE.studioBorder}`,
                display: 'flex',
                alignItems: 'center',
                justifyContent: 'space-between',
              }}
            >
              <div style={{ display: 'flex', alignItems: 'center', gap: 10 }}>
                <IconTerminal size={18} color="#67e8f9" />
                <span style={{ fontFamily: FONT_MONO, fontSize: 13.5, fontWeight: 700, color: '#fff' }}>
                  Claude Code / Cursor / Codex · lucent-mcp
                </span>
              </div>
              <span
                style={{
                  fontFamily: FONT_MONO,
                  fontSize: 11.5,
                  color: '#34d399',
                  padding: '3px 9px',
                  borderRadius: 99,
                  background: 'rgba(52,211,153,0.14)',
                }}
              >
                20 TOOLS · STDIO ZERO-DEPS
              </span>
            </div>

            <div style={{ padding: 22, display: 'flex', flexDirection: 'column', gap: 16, flex: 1 }}>
              {/* User Natural Language Prompt Bubble */}
              <div
                style={{
                  padding: '15px 18px',
                  borderRadius: 18,
                  background: 'linear-gradient(135deg, rgba(124,92,252,0.24), rgba(56,189,248,0.14))',
                  border: '1px solid rgba(167, 139, 250, 0.42)',
                }}
              >
                <div style={{ fontFamily: FONT_MONO, fontSize: 11.5, color: '#c4b5fd', marginBottom: 6 }}>
                  USER PROMPT · 日常语言描述需求
                </div>
                <div style={{ fontSize: 17, lineHeight: 1.55, color: '#ffffff', fontWeight: 600, minHeight: 54 }}>
                  {promptTyped}
                  {promptTyped.length < promptFull.length && (
                    <span style={{ display: 'inline-block', width: 2.5, height: 18, marginLeft: 3, background: '#67e8f9', verticalAlign: 'middle' }} />
                  )}
                </div>
              </div>

              {/* MCP Tool Call Pipeline Steps */}
              <div style={{ display: 'flex', flexDirection: 'column', gap: 10, flex: 1 }}>
                {steps.map((st, idx) => {
                  const done = localF >= st.at + 55;
                  const active = localF >= st.at;
                  const sp = spr(localF, st.at, SPRING_GLASS);
                  return (
                    <div
                      key={st.tool}
                      style={{
                        padding: '13px 16px',
                        borderRadius: 14,
                        background: done
                          ? 'rgba(52, 211, 153, 0.10)'
                          : active
                          ? 'rgba(56, 189, 248, 0.12)'
                          : 'rgba(255,255,255,0.03)',
                        border: `1px solid ${done ? 'rgba(52,211,153,0.45)' : active ? 'rgba(103,232,249,0.45)' : PRISM_PULSE.rimOuter}`,
                        opacity: active ? sp : 0.35,
                        transform: `translateX(${active ? (1 - sp) * -16 : 0}px)`,
                        display: 'flex',
                        alignItems: 'center',
                        justifyContent: 'space-between',
                      }}
                    >
                      <div style={{ display: 'flex', alignItems: 'center', gap: 12 }}>
                        <span
                          style={{
                            width: 26,
                            height: 26,
                            borderRadius: 8,
                            background: done ? '#059669' : '#0284c7',
                            display: 'flex',
                            alignItems: 'center',
                            justifyContent: 'center',
                            color: '#fff',
                            fontFamily: FONT_MONO,
                            fontSize: 12,
                            fontWeight: 700,
                          }}
                        >
                          {done ? <IconCheck size={14} color="#fff" /> : idx + 1}
                        </span>
                        <div>
                          <div style={{ fontFamily: FONT_MONO, fontSize: 14.5, fontWeight: 700, color: '#67e8f9' }}>
                            {st.tool}()
                          </div>
                          <div style={{ fontSize: 12.5, color: PRISM_PULSE.textSecondary }}>{st.note}</div>
                        </div>
                      </div>
                      <span
                        style={{
                          fontFamily: FONT_MONO,
                          fontSize: 11.5,
                          fontWeight: 700,
                          color: done ? '#34d399' : '#fbbf24',
                        }}
                      >
                        {done ? 'PASS ✓' : active ? 'RUNNING...' : 'PENDING'}
                      </span>
                    </div>
                  );
                })}
              </div>

              {/* Bottom CLI Registration Snippet */}
              <div
                style={{
                  padding: '10px 14px',
                  borderRadius: 12,
                  background: 'rgba(5, 7, 18, 0.85)',
                  border: `1px solid ${PRISM_PULSE.studioBorder}`,
                  fontFamily: FONT_MONO,
                  fontSize: 12,
                  color: '#94a3b8',
                  display: 'flex',
                  justifyContent: 'space-between',
                }}
              >
                <span>$ claude mcp add lucent /Applications/Lucent.app/.../lucent-mcp</span>
                <span style={{ color: '#67e8f9' }}>开箱直连 · 零外部依赖</span>
              </div>
            </div>
          </div>

          {/* CENTER: 3-Strand Luminous SVG Optical Fiber Conduit + Shooting Photon Packets */}
          <div style={{ position: 'relative', height: 260, display: 'flex', flexDirection: 'column', alignItems: 'center', justifyContent: 'center' }}>
            <svg width="100" height="220" viewBox="0 0 100 220" style={{ overflow: 'visible' }}>
              <defs>
                <linearGradient id="fiberGrad" x1="0" y1="0" x2="100" y2="0" gradientUnits="userSpaceOnUse">
                  <stop offset="0%" stopColor="#22d3ee" />
                  <stop offset="50%" stopColor="#a78bfa" />
                  <stop offset="100%" stopColor="#f472b6" />
                </linearGradient>
              </defs>
              {/* 3 Curved Optical Fiber Tracks */}
              <path d="M 0 54 C 40 54, 60 110, 100 110" fill="none" stroke="rgba(255,255,255,0.12)" strokeWidth="2.2" />
              <path d="M 0 110 L 100 110" fill="none" stroke="rgba(255,255,255,0.15)" strokeWidth="2.6" />
              <path d="M 0 166 C 40 166, 60 110, 100 110" fill="none" stroke="rgba(255,255,255,0.12)" strokeWidth="2.2" />

              {/* Energized Glowing Beam Overlays */}
              <path
                d="M 0 54 C 40 54, 60 110, 100 110"
                fill="none"
                stroke="url(#fiberGrad)"
                strokeWidth="2.8"
                strokeDasharray="130"
                strokeDashoffset={130 * (1 - beamProgress)}
              />
              <path
                d="M 0 110 L 100 110"
                fill="none"
                stroke="url(#fiberGrad)"
                strokeWidth="3.4"
                strokeDasharray="100"
                strokeDashoffset={100 * (1 - beamProgress)}
              />
              <path
                d="M 0 166 C 40 166, 60 110, 100 110"
                fill="none"
                stroke="url(#fiberGrad)"
                strokeWidth="2.8"
                strokeDasharray="130"
                strokeDashoffset={130 * (1 - beamProgress)}
              />

              {/* Luminous Photon Data Packets Shooting Across Conduit */}
              {beamProgress > 0.05 && (
                <>
                  <circle cx={beamProgress * 100} cy={110} r="5.5" fill="#ffffff" />
                  <circle cx={beamProgress * 100} cy={110} r="12" fill="rgba(56, 189, 248, 0.42)" />
                </>
              )}
              {reloaded && (
                <circle
                  cx={((localF * 2.4) % 100)}
                  cy={110}
                  r="4"
                  fill="#34d399"
                />
              )}
            </svg>
            <div
              style={{
                position: 'absolute',
                bottom: 24,
                padding: '5px 10px',
                borderRadius: 99,
                background: reloaded ? 'rgba(52, 211, 153, 0.18)' : 'rgba(56, 189, 248, 0.14)',
                border: `1px solid ${reloaded ? 'rgba(52,211,153,0.58)' : 'rgba(103,232,249,0.4)'}`,
                fontFamily: FONT_MONO,
                fontSize: 11,
                fontWeight: 700,
                color: reloaded ? '#6ee7b7' : '#67e8f9',
                whiteSpace: 'nowrap',
                boxShadow: reloaded ? '0 0 18px rgba(52, 211, 153, 0.35)' : 'none',
              }}
            >
              {reloaded ? '350ms ✓' : 'FSEvents'}
            </div>
          </div>

          {/* RIGHT: Live Running Lucent Panel Receiving Instant Hot-Reload + Prism Impact Ring */}
          <div
            style={{
              position: 'relative',
              transform: `scale(${reloaded ? 1 + (1 - reloadPop) * 0.035 : 0.985})`,
            }}
          >
            {reloaded && localF < 550 && (
              <div
                style={{
                  position: 'absolute',
                  inset: -14 * clampLerp(localF, [475, 540], [0, 1]),
                  borderRadius: 36,
                  border: '2.5px solid rgba(52, 211, 153, 0.78)',
                  boxShadow: '0 0 44px rgba(56, 189, 248, 0.42)',
                  opacity: clampLerp(localF, [475, 545], [0.95, 0]),
                  pointerEvents: 'none',
                  zIndex: 40,
                }}
              />
            )}
            <LiquidGlassPanel
              theme="prism-pulse"
              width={880}
              height={544}
              query={scenario === 'plugin' ? 'pr' : scenario === 'script' ? '!clean-port' : ''}
              activeScope={scenario === 'plugin' ? 'plugins' : 'all'}
              dimensionTag={reloaded ? 'HOT RELOADED · 350ms' : 'WATCHING FSEVENTS...'}
              toastText={
                reloaded
                  ? scenario === 'plugin'
                    ? '⚡ 新插件 pr-radar 已实时热加载生效'
                    : scenario === 'script'
                    ? '⚡ 脚本与 64×64 SVG 图标已热同步'
                    : '⚡ 开发者启动面板已实时热刷新'
                  : undefined
              }
            >
              {!reloaded ? (
                <div style={{ flex: 1, display: 'flex', flexDirection: 'column', alignItems: 'center', justifyContent: 'center', gap: 14, color: PRISM_PULSE.textTertiary }}>
                  <IconZap size={38} color="#67e8f9" />
                  <div style={{ fontSize: 18, fontWeight: 600, color: PRISM_PULSE.textSecondary }}>
                    等待 lucent-mcp 完成沙箱校验与热推送...
                  </div>
                  <div style={{ fontFamily: FONT_MONO, fontSize: 12.5 }}>
                    Seatbelt Sandbox · Zero-Restart FSEvents Bridge
                  </div>
                </div>
              ) : scenario === 'plugin' ? (
                <div style={{ display: 'flex', flexDirection: 'column', gap: 10, opacity: reloadPop }}>
                  <div style={{ display: 'flex', justifyContent: 'space-between', fontFamily: FONT_MONO, fontSize: 12, color: '#34d399', padding: '0 4px' }}>
                    <span>PR REVIEW RADAR · AI GENERATED PLUGIN</span>
                    <span>Token Stored in LCNTVLT2 AES-GCM ✓</span>
                  </div>
                  {[
                    { title: '#418 feat(mcp): add live home-layout hot reload', repo: 'lengsukq/Lucent · +420 -88', state: '待我 Review' },
                    { title: '#415 perf(index): zero-copy LCNTIDX3 header probe', repo: 'lengsukq/Lucent · +156 -42', state: 'CI 通过 ✓' },
                    { title: '#412 fix(capture): mixed DPI monitor crop clamp', repo: 'lengsukq/Lucent · +94 -18', state: 'CI 通过 ✓' },
                  ].map((pr, idx) => (
                    <div
                      key={pr.title}
                      style={{
                        padding: '15px 16px',
                        borderRadius: 16,
                        background: idx === 0 ? PRISM_PULSE.bgRowSelected : PRISM_PULSE.bgCard,
                        border: `1px solid ${idx === 0 ? PRISM_PULSE.rimSelected : PRISM_PULSE.rimOuter}`,
                        display: 'flex',
                        alignItems: 'center',
                        justifyContent: 'space-between',
                      }}
                    >
                      <div style={{ display: 'flex', alignItems: 'center', gap: 14 }}>
                        <SquircleBadge gradient="linear-gradient(135deg,#6366f1,#ec4899)" size={40}>
                          <IconCode size={18} />
                        </SquircleBadge>
                        <div>
                          <div style={{ fontSize: 15.5, fontWeight: 700, color: '#fff' }}>{pr.title}</div>
                          <div style={{ fontFamily: FONT_MONO, fontSize: 12, color: PRISM_PULSE.textTertiary, marginTop: 3 }}>{pr.repo}</div>
                        </div>
                      </div>
                      <span style={{ padding: '4px 10px', borderRadius: 99, background: 'rgba(52,211,153,0.16)', color: '#6ee7b7', fontSize: 12, fontWeight: 700 }}>
                        {pr.state}
                      </span>
                    </div>
                  ))}
                </div>
              ) : scenario === 'script' ? (
                <div style={{ display: 'grid', gridTemplateColumns: '0.45fr 0.55fr', gap: 18, flex: 1, opacity: reloadPop }}>
                  {/* AI-Drawn 64x64 Custom SVG Showcase */}
                  <div
                    style={{
                      borderRadius: 20,
                      background: PRISM_PULSE.bgWell,
                      border: `1px solid ${PRISM_PULSE.rimSelected}`,
                      display: 'flex',
                      flexDirection: 'column',
                      alignItems: 'center',
                      justifyContent: 'center',
                      gap: 16,
                      padding: 20,
                    }}
                  >
                    <svg width="118" height="118" viewBox="0 0 64 64" fill="none">
                      <defs>
                        <linearGradient id="aiPortGrad" x1="6" y1="6" x2="58" y2="58" gradientUnits="userSpaceOnUse">
                          <stop offset="0%" stopColor="#22d3ee" />
                          <stop offset="50%" stopColor="#7c5cfc" />
                          <stop offset="100%" stopColor="#f472b6" />
                        </linearGradient>
                      </defs>
                      <rect x="4" y="4" width="56" height="56" rx="16" fill="url(#aiPortGrad)" />
                      <circle cx="32" cy="32" r="15" stroke="#ffffff" strokeWidth="3.5" strokeDasharray="66 18" />
                      <path d="M32 16v14M26 36l6 6 10-12" stroke="#ffffff" strokeWidth="3.5" strokeLinecap="round" strokeLinejoin="round" />
                    </svg>
                    <div style={{ textAlign: 'center' }}>
                      <div style={{ fontFamily: FONT_MONO, fontSize: 13, fontWeight: 700, color: '#67e8f9' }}>64×64 专属 SVG 图标</div>
                      <div style={{ fontSize: 12.5, color: PRISM_PULSE.textTertiary, marginTop: 4 }}>AI 生成 · 自动过滤危险脚本标签</div>
                    </div>
                  </div>

                  {/* Live Script Card */}
                  <div style={{ display: 'flex', flexDirection: 'column', justifyContent: 'space-between', padding: 18, borderRadius: 20, background: PRISM_PULSE.bgCard, border: `1px solid ${PRISM_PULSE.rimOuter}` }}>
                    <div>
                      <div style={{ fontSize: 20, fontWeight: 800, color: '#fff' }}>!clean-port · 端口一键清理</div>
                      <div style={{ fontFamily: FONT_MONO, fontSize: 12, color: '#34d399', marginTop: 4 }}>
                        Scripts/clean-port.sh · 双向实时同步
                      </div>
                      <div style={{ marginTop: 14, padding: 12, borderRadius: 12, background: PRISM_PULSE.studioBg, fontFamily: FONT_MONO, fontSize: 12, color: '#e2e8f0', lineHeight: 1.7 }}>
                        <div>#!/usr/bin/env zsh</div>
                        <div style={{ color: '#67e8f9' }}># @lucent.name 清理 3000/5173 端口</div>
                        <div style={{ color: '#6ee7b7' }}>for p in 3000 5173; do lsof -ti :$p | xargs kill -9; done</div>
                      </div>
                    </div>
                    <div style={{ display: 'flex', alignItems: 'center', gap: 8, fontSize: 13, color: '#c4b5fd' }}>
                      <IconShield size={16} color="#34d399" /> 支持独立热键 · Seatbelt 沙箱隔离运行
                    </div>
                  </div>
                </div>
              ) : (
                <div style={{ display: 'flex', flexDirection: 'column', gap: 12, flex: 1, opacity: reloadPop }}>
                  <div style={{ display: 'grid', gridTemplateColumns: 'repeat(2, 1fr)', gap: 12 }}>
                    <div style={{ padding: 18, borderRadius: 20, background: PRISM_PULSE.bgCard, border: `1px solid ${PRISM_PULSE.rimSelected}` }}>
                      <div style={{ fontFamily: FONT_MONO, fontSize: 11.5, color: '#67e8f9' }}>BENTO TILE · AI PLACED</div>
                      <div style={{ fontSize: 18, fontWeight: 800, color: '#fff', marginTop: 6 }}>双栏文件整理台 ⌥E</div>
                      <div style={{ fontSize: 12.5, color: PRISM_PULSE.textTertiary, marginTop: 3 }}>跨栏拖拽 · NTFS 只读护航</div>
                    </div>
                    <div style={{ padding: 18, borderRadius: 20, background: PRISM_PULSE.bgCard, border: `1px solid ${PRISM_PULSE.rimSelected}` }}>
                      <div style={{ fontFamily: FONT_MONO, fontSize: 11.5, color: '#f472b6' }}>QUICK SCRIPT · AI PLACED</div>
                      <div style={{ fontSize: 18, fontWeight: 800, color: '#fff', marginTop: 6 }}>!clean-port 清理端口</div>
                      <div style={{ fontSize: 12.5, color: PRISM_PULSE.textTertiary, marginTop: 3 }}>3000 / 5173 一键释放</div>
                    </div>
                  </div>
                  <div style={{ padding: 16, borderRadius: 18, background: PRISM_PULSE.bgWell, border: `1px solid ${PRISM_PULSE.rimOuter}` }}>
                    <div style={{ fontFamily: FONT_MONO, fontSize: 11.5, color: '#34d399', marginBottom: 10 }}>
                      GITHUB &amp; DEV SHELF · 由 lucent_update_home_layout 实时编排
                    </div>
                    <div style={{ display: 'flex', gap: 10, flexWrap: 'wrap' }}>
                      {['GitHub PR 审查雷达', 'vscode://Lucent', 'localhost:5173', 'Swift 6 文档', '芯片脉搏 ⌥M', '软件网速 ⌥N'].map((chip) => (
                        <span
                          key={chip}
                          style={{
                            padding: '7px 14px',
                            borderRadius: RADII.pill,
                            background: PRISM_PULSE.accentBadgeBg,
                            border: `1px solid ${PRISM_PULSE.accentBadgeBorder}`,
                            color: '#fff',
                            fontSize: 13,
                            fontWeight: 600,
                          }}
                        >
                          {chip}
                        </span>
                      ))}
                    </div>
                  </div>
                </div>
              )}
            </LiquidGlassPanel>
          </div>
        </div>
      </div>

      <BottomCaptionBar beats={CAPTIONS} frame={frame} theme="prism-pulse" />
    </AbsoluteFill>
  );
};
