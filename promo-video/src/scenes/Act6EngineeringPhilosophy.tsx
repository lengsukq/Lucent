import React from 'react';
import { AbsoluteFill, Easing, useCurrentFrame } from 'remotion';
import { AuroraBackdrop } from '../components/AuroraBackdrop';
import { IconCheck, IconLayers, IconLock, IconShield, IconZap } from '../components/Icons';
import { BottomCaptionBar, CaptionBeat, SceneHeader } from '../components/KineticCaption';
import { CameraStage } from '../components/MacChrome';
import { clampLerp, spr, SPRING_GLASS } from '../design/motion';
import { FONT_MONO, FONT_SANS, getTheme, RADII, ThemeMode } from '../design/tokens';

const CAPTIONS: CaptionBeat[] = [
  { start: 30, end: 560, tag: 'SWIFT 6 DAG', text: '9 大单向无环模块分层 · 0 第三方依赖 · 每次构建强门禁严查单 .swift 文件 ≤ 300 行' },
  { start: 580, end: 1050, tag: 'ZERO-TRUST', text: 'Seatbelt 内核沙箱 + LCNTVLT2 256-bit AES-GCM 密钥箱 + 21 项 TCC 审计与 WebDAV 加密备份' },
  { start: 1070, end: 1550, tag: 'EPHEMERAL', text: '克制的「用完即焚」哲学：收起 30s 毁视图、空闲 90s 卸索引，默认 0 常驻桌面挂件打扰' },
];

export const Act6EngineeringPhilosophy: React.FC = () => {
  const frame = useCurrentFrame();

  const phase: 'dag' | 'security' | 'memory' =
    frame < 570 ? 'dag' : frame < 1060 ? 'security' : 'memory';

  const theme: ThemeMode = phase === 'memory' ? 'pure-frost' : 'prism-pulse';
  const t = getTheme(theme);

  // Memory self-cleaning curve drawing progress (frame 1080..1460)
  const curveDraw = clampLerp(frame, [1095, 1380], [0, 1], Easing.out(Easing.cubic));

  return (
    <AbsoluteFill style={{ fontFamily: FONT_SANS }}>
      <AuroraBackdrop theme={theme} seedOffset={12480} />

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
            eyebrow="06 / 07 · ENGINEERING CRAFT & RESTRAINT"
            title="极客级纯净架构，"
            highlight="与克制的「用完即焚」。"
            theme={theme}
            frame={frame}
            maxWidth={1060}
            fontSize={44}
          />

          <div style={{ display: 'flex', gap: 10, paddingBottom: 6 }}>
            {[
              { id: 'dag', label: '9 模块 Swift 6 DAG' },
              { id: 'security', label: '纵深安全与加密备份' },
              { id: 'memory', label: '30s / 90s 内存自洁' },
            ].map((p) => {
              const act = p.id === phase;
              return (
                <div
                  key={p.id}
                  style={{
                    padding: '9px 16px',
                    borderRadius: RADII.pill,
                    background: act ? t.accentGradient : t.bgCard,
                    border: `1px solid ${act ? 'rgba(255,255,255,0.45)' : t.rimOuter}`,
                    color: act ? '#fff' : t.textSecondary,
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
          {/* PHASE 1: 9-MODULE ACYCLIC SWIFT 6 DAG */}
          {phase === 'dag' && (
            <div style={{ width: '100%', display: 'grid', gridTemplateColumns: '1.25fr 0.75fr', gap: 32, alignItems: 'center' }}>
              {/* Visual 4-Tier DAG Topology */}
              <div
                style={{
                  padding: 30,
                  borderRadius: 26,
                  background: t.bgCard,
                  border: `1px solid ${t.rimOuter}`,
                  boxShadow: t.panelShadow,
                  display: 'flex',
                  flexDirection: 'column',
                  gap: 22,
                }}
              >
                {[
                  {
                    tier: 'LAYER 4 · ENTRY & VERIFICATION',
                    delay: 260,
                    nodes: [
                      { name: 'Lucent', sub: 'SwiftUI + AppKit 主程序', c: '#38bdf8' },
                      { name: 'lucent-mcp', sub: '20 工具 AI 协议桥', c: '#f472b6' },
                      { name: 'LucentTests / Check', sub: '单测与集成自检', c: '#34d399' },
                    ],
                  },
                  {
                    tier: 'LAYER 3 · ORCHESTRATION & SANDBOX',
                    delay: 185,
                    nodes: [
                      { name: 'LucentCore', sub: '统一搜索 · 主页布局 · 插件与脚本运行时 · WebDAV 备份', c: '#a78bfa' },
                    ],
                  },
                  {
                    tier: 'LAYER 2 · DOMAIN ENGINES',
                    delay: 110,
                    nodes: [
                      { name: 'LucentSearch', sub: 'LCNTIDX3 mmap + FSEvents', c: '#22d3ee' },
                      { name: 'LucentMedia', sub: '多屏 DPI · Vision · HEVC', c: '#c084fc' },
                      { name: 'LucentSystem', sub: '120Hz 鼠标 · 功耗 · 网速', c: '#fbbf24' },
                    ],
                  },
                  {
                    tier: 'LAYER 1 · FOUNDATION',
                    delay: 35,
                    nodes: [
                      { name: 'LucentFoundation', sub: '零上层依赖 · 品牌渲染真源 · LCNTVLT2 密钥箱 · 子进程监管', c: '#67e8f9' },
                    ],
                  },
                ].map((layer, layerIdx) => {
                  const lp = spr(frame, layer.delay, SPRING_GLASS);
                  return (
                    <React.Fragment key={layer.tier}>
                    <div
                      style={{
                        opacity: lp,
                        transform: `translateY(${(1 - lp) * 18}px)`,
                        display: 'flex',
                        flexDirection: 'column',
                        gap: 8,
                      }}
                    >
                      <div style={{ fontFamily: FONT_MONO, fontSize: 11, color: t.textTertiary, letterSpacing: '0.1em' }}>
                        {layer.tier}
                      </div>
                      <div style={{ display: 'grid', gridTemplateColumns: `repeat(${layer.nodes.length}, 1fr)`, gap: 12 }}>
                        {layer.nodes.map((node) => (
                          <div
                            key={node.name}
                            style={{
                              padding: '13px 16px',
                              borderRadius: 14,
                              background: t.bgWell,
                              border: `1px solid ${node.c}55`,
                              boxShadow: `inset 0 1px 0 ${node.c}44`,
                            }}
                          >
                            <div style={{ fontFamily: FONT_MONO, fontSize: 15.5, fontWeight: 800, color: node.c }}>
                              {node.name}
                            </div>
                            <div style={{ fontSize: 12, color: t.textSecondary, marginTop: 3 }}>{node.sub}</div>
                          </div>
                        ))}
                      </div>
                    </div>
                    {layerIdx < 3 && (
                      <div
                        style={{
                          position: 'relative',
                          height: 22,
                          margin: '-12px 0',
                          display: 'flex',
                          alignItems: 'center',
                          justifyContent: 'center',
                          opacity: lp,
                        }}
                      >
                        <svg width="780" height="22" viewBox="0 0 780 22" style={{ overflow: 'visible' }}>
                          {[155, 625].map((cx, ci) => {
                            const pulseY = 20 - (((frame * 0.65 + ci * 9 + layerIdx * 5) % 20));
                            return (
                              <g key={cx}>
                                <line x1={cx} y1="2" x2={cx} y2="20" stroke="rgba(103, 232, 249, 0.35)" strokeWidth="1.6" />
                                <polygon points={`${cx},1 ${cx - 4},7 ${cx + 4},7`} fill="#67e8f9" />
                                <circle cx={cx} cy={pulseY} r="3" fill="#ffffff" />
                              </g>
                            );
                          })}
                        </svg>
                        <span
                          style={{
                            position: 'absolute',
                            padding: '1px 10px',
                            borderRadius: 99,
                            background: 'rgba(10, 12, 30, 0.88)',
                            border: '1px solid rgba(103, 232, 249, 0.28)',
                            fontFamily: FONT_MONO,
                            fontSize: 10,
                            color: '#67e8f9',
                            letterSpacing: '0.06em',
                          }}
                        >
                          ACYCLIC DAG ↑
                        </span>
                      </div>
                    )}
                    </React.Fragment>
                  );
                })}
              </div>

              {/* Right Hard Engineering Specs */}
              <div style={{ display: 'flex', flexDirection: 'column', gap: 16 }}>
                {[
                  { num: '0 Deps', title: '零第三方外部包依赖', desc: '100% 直连 ScreenCaptureKit / Vision / AVKit / Mach / CGEventTap' },
                  { num: '≤ 300 行', title: '单文件 Clean Code 硬上限', desc: 'verify-macos.sh 每次构建自动拦截越界导入与超长源文件' },
                  { num: '~10 MB', title: '极致轻盈 arm64 安装包', desc: '告别数百 MB Electron 网页套壳，原生丝滑冷启动' },
                ].map((m, i) => {
                  const mp = spr(frame, 80 + i * 24, SPRING_GLASS);
                  return (
                    <div
                      key={m.num}
                      style={{
                        padding: 22,
                        borderRadius: 22,
                        background: t.bgCard,
                        border: `1px solid ${t.rimOuter}`,
                        boxShadow: t.cardShadow,
                        opacity: mp,
                        transform: `translateX(${(1 - mp) * 24}px)`,
                      }}
                    >
                      <div style={{ fontFamily: FONT_MONO, fontSize: 30, fontWeight: 800, color: '#67e8f9' }}>{m.num}</div>
                      <div style={{ fontSize: 18, fontWeight: 700, color: '#fff', marginTop: 4 }}>{m.title}</div>
                      <div style={{ fontSize: 14, color: t.textSecondary, marginTop: 6, lineHeight: 1.5 }}>{m.desc}</div>
                    </div>
                  );
                })}
              </div>
            </div>
          )}

          {/* PHASE 2: DEFENSE-IN-DEPTH SECURITY & BACKUP */}
          {phase === 'security' && (
            <div style={{ width: '100%', display: 'grid', gridTemplateColumns: 'repeat(3, 1fr)', gap: 24 }}>
              {[
                {
                  icon: <IconShield size={26} color="#34d399" />,
                  tag: 'KERNEL SANDBOX',
                  title: 'Apple Seatbelt 内核级沙箱',
                  points: [
                    '/usr/bin/sandbox-exec 动态生成隔离策略',
                    '默认阻断未声明网络请求与未授权子进程',
                    '硬性拉黑系统钥匙串与宿主密钥保险箱',
                    '0700 临时目录一次性 48-bit 桥接令牌',
                  ],
                  accent: '#34d399',
                },
                {
                  icon: <IconLock size={26} color="#67e8f9" />,
                  tag: 'LCNTVLT2 VAULT',
                  title: '256-bit AES-GCM 密钥保险箱',
                  points: [
                    '敏感 API Token 与插件凭据双轨加密落盘',
                    '宿主统一代申系统 TCC 权限并纳入 21 项审计矩阵',
                    '剪贴板自动跳过密码管理器敏感标记与私钥',
                    '本机自签名脚本升级延续权限，零云端上传',
                  ],
                  accent: '#67e8f9',
                },
                {
                  icon: <IconLayers size={26} color="#c4b5fd" />,
                  tag: 'BACKUP & SYNC',
                  title: '整机配置备份与 WebDAV 漫游',
                  points: [
                    '一键打包主页、菜单栏、热键、自制插件与脚本',
                    'LZFSE 高效压缩 + SHA-256 完整性校验',
                    '支持可选口令加密迁移敏感密钥至新 Mac',
                    '直连坚果云 / 自建 NAS 自动轮转云同步',
                  ],
                  accent: '#c4b5fd',
                },
              ].map((card, i) => {
                const sp = spr(frame, 595 + i * 18, SPRING_GLASS);
                return (
                  <div
                    key={card.title}
                    style={{
                      padding: 28,
                      borderRadius: 26,
                      background: t.bgCard,
                      border: `1.5px solid ${card.accent}44`,
                      boxShadow: t.panelShadow,
                      opacity: sp,
                      transform: `translateY(${(1 - sp) * 28}px)`,
                      display: 'flex',
                      flexDirection: 'column',
                      gap: 16,
                    }}
                  >
                    <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between' }}>
                      <div style={{ width: 52, height: 52, borderRadius: 16, background: `${card.accent}1c`, display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
                        {card.icon}
                      </div>
                      <span style={{ fontFamily: FONT_MONO, fontSize: 12, fontWeight: 700, color: card.accent }}>{card.tag}</span>
                    </div>
                    <div style={{ fontSize: 22, fontWeight: 800, color: '#fff' }}>{card.title}</div>
                    <div style={{ display: 'flex', flexDirection: 'column', gap: 11 }}>
                      {card.points.map((pt) => (
                        <div key={pt} style={{ display: 'flex', alignItems: 'flex-start', gap: 9, fontSize: 14.5, color: t.textSecondary, lineHeight: 1.5 }}>
                          <IconCheck size={16} color={card.accent} style={{ marginTop: 3, flexShrink: 0 }} />
                          <span>{pt}</span>
                        </div>
                      ))}
                    </div>
                  </div>
                );
              })}
            </div>
          )}

          {/* PHASE 3: EPHEMERAL SELF-CLEANING MEMORY TIMELINE (Pure Frost Light Clarity) */}
          {phase === 'memory' && (
            <CameraStage enterFrame={1060} breathScale={0.007} tiltDeg={0.5}>
            <div style={{ width: '100%', display: 'grid', gridTemplateColumns: '1.3fr 0.7fr', gap: 30, alignItems: 'center' }}>
              <div
                style={{
                  padding: 32,
                  borderRadius: 28,
                  background: 'rgba(255,255,255,0.95)',
                  border: `1px solid ${t.rimOuter}`,
                  boxShadow: t.panelShadow,
                  display: 'flex',
                  flexDirection: 'column',
                  gap: 18,
                }}
              >
                <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
                  <div>
                    <div style={{ fontFamily: FONT_MONO, fontSize: 12.5, color: '#0066dc', fontWeight: 700 }}>
                      SELF-CLEANING MEMORY LIFECYCLE
                    </div>
                    <div style={{ fontSize: 26, fontWeight: 800, color: '#0a1120', marginTop: 4 }}>
                      「用完即焚」内存自洁时间轴
                    </div>
                  </div>
                  <div style={{ display: 'flex', alignItems: 'center', gap: 10 }}>
                    <span
                      style={{
                        padding: '6px 14px',
                        borderRadius: 99,
                        background: curveDraw > 0.78 ? 'rgba(5,150,105,0.14)' : 'rgba(0,102,220,0.11)',
                        color: curveDraw > 0.78 ? '#047857' : '#0066dc',
                        fontFamily: FONT_MONO,
                        fontSize: 13,
                        fontWeight: 800,
                      }}
                    >
                      {curveDraw < 0.35
                        ? 'ACTIVE · 68 MB'
                        : curveDraw < 0.72
                        ? '+30s VIEW FREED · 16 MB'
                        : '+90s IDLE · ~0 MB CACHE'}
                    </span>
                    <span style={{ padding: '6px 14px', borderRadius: 99, background: 'rgba(5,150,105,0.12)', color: '#047857', fontFamily: FONT_MONO, fontSize: 12.5, fontWeight: 700 }}>
                      默认常驻悬浮窗 = 0
                    </span>
                  </div>
                </div>

                {/* Animated SVG Memory Decay Curve */}
                <svg width="100%" height="230" viewBox="0 0 920 230" style={{ overflow: 'visible' }}>
                  <defs>
                    <linearGradient id="memFill" x1="0" y1="0" x2="0" y2="1">
                      <stop offset="0%" stopColor="#0066dc" stopOpacity="0.28" />
                      <stop offset="100%" stopColor="#0066dc" stopOpacity="0.01" />
                    </linearGradient>
                  </defs>
                  {/* Baseline & Guidelines */}
                  <line x1="30" y1="190" x2="890" y2="190" stroke="#cbd5e1" strokeWidth="1.5" />
                  <line x1="340" y1="25" x2="340" y2="190" stroke="#94a3b8" strokeDasharray="5 5" />
                  <line x1="650" y1="25" x2="650" y2="190" stroke="#059669" strokeDasharray="5 5" />

                  {/* Curve Area & Stroke */}
                  <path
                    d="M 30 182 C 90 180, 110 46, 170 46 L 285 46 C 320 46, 332 122, 375 122 L 605 122 C 638 122, 650 180, 710 182 L 890 182 L 890 190 L 30 190 Z"
                    fill="url(#memFill)"
                    opacity={curveDraw}
                  />
                  <path
                    d="M 30 182 C 90 180, 110 46, 170 46 L 285 46 C 320 46, 332 122, 375 122 L 605 122 C 638 122, 650 180, 710 182 L 890 182"
                    fill="none"
                    stroke="#0066dc"
                    strokeWidth="4.5"
                    strokeLinecap="round"
                    strokeDasharray="1100"
                    strokeDashoffset={1100 * (1 - curveDraw)}
                  />

                  {/* Milestone Callouts — placed cleanly in open space above plateaus */}
                  <circle cx="170" cy="46" r="7" fill="#0066dc" opacity={curveDraw} />
                  <text x="170" y="26" textAnchor="middle" fill="#0a1120" fontSize="14.5" fontWeight="700">
                    ⌥Space 瞬时工作
                  </text>

                  <circle cx="375" cy="122" r="7" fill="#4f46e5" opacity={curveDraw} />
                  <text x="492" y="102" textAnchor="middle" fill="#4f46e5" fontSize="14.5" fontWeight="700">
                    收起 30s · 自动销毁视图树
                  </text>

                  <circle cx="710" cy="182" r="7" fill="#059669" opacity={curveDraw} />
                  <circle cx="710" cy="182" r={7 + Math.sin(frame * 0.14) * 5 + 5} fill="rgba(5, 150, 105, 0.22)" opacity={curveDraw} />
                  <text x="792" y="160" textAnchor="middle" fill="#047857" fontSize="14.5" fontWeight="700">
                    空闲 90s · 卸载索引堆页
                  </text>

                  <text x="30" y="216" fill="#64748b" fontSize="12.5" fontFamily={FONT_MONO}>0s</text>
                  <text x="340" y="216" textAnchor="middle" fill="#4f46e5" fontSize="12.5" fontFamily={FONT_MONO}>+30s</text>
                  <text x="650" y="216" textAnchor="middle" fill="#047857" fontSize="12.5" fontFamily={FONT_MONO}>+90s</text>
                  <text x="890" y="216" textAnchor="end" fill="#047857" fontSize="12.5" fontFamily={FONT_MONO}>Quiet Idle</text>
                </svg>
              </div>

              {/* Right: What We Refuse To Do */}
              <div
                style={{
                  padding: 28,
                  borderRadius: 28,
                  background: 'rgba(255,255,255,0.92)',
                  border: `1px solid ${t.rimOuter}`,
                  boxShadow: t.panelShadow,
                  display: 'flex',
                  flexDirection: 'column',
                  gap: 16,
                }}
              >
                <div style={{ fontFamily: FONT_MONO, fontSize: 12.5, color: '#db2777', fontWeight: 700 }}>
                  PRODUCT BOUNDARIES · 我们坚持不做
                </div>
                {[
                  { title: '不做强行开启的全家桶', desc: '所有悬浮窗、实时读数与插件按钮刚安装时全部默认关闭，按需开启' },
                  { title: '不拉起臃肿浏览器内核', desc: '原生渲染 Markdown / 大图 / 4K 视频，二级窗口关窗立即释放堆页' },
                  { title: '不装后台偷跑守护进程', desc: '拒绝 launchd 常驻扫盘，遇脏 NTFS 移动硬盘严格只读护航防丢数' },
                ].map((item) => (
                  <div key={item.title} style={{ padding: 16, borderRadius: 16, background: '#f1f5fc', border: '1px solid rgba(15,23,42,0.06)' }}>
                    <div style={{ fontSize: 16.5, fontWeight: 800, color: '#0a1120', display: 'flex', alignItems: 'center', gap: 8 }}>
                      <IconZap size={16} color="#0066dc" /> {item.title}
                    </div>
                    <div style={{ fontSize: 13.5, color: '#475569', marginTop: 5, lineHeight: 1.55 }}>{item.desc}</div>
                  </div>
                ))}
              </div>
            </div>
            </CameraStage>
          )}
        </div>
      </div>

      <BottomCaptionBar beats={CAPTIONS} frame={frame} theme={theme} />
    </AbsoluteFill>
  );
};
