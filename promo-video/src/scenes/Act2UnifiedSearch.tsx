import React from 'react';
import { AbsoluteFill, useCurrentFrame } from 'remotion';
import { AuroraBackdrop } from '../components/AuroraBackdrop';
import {
  IconCalculator,
  IconCheck,
  IconClipboard,
  IconCode,
  IconFolder,
  IconSearch,
  IconShield,
  IconTerminal,
  SquircleBadge,
} from '../components/Icons';
import { KeycapBadge } from '../components/KeycapBadge';
import { BottomCaptionBar, CaptionBeat, SceneHeader } from '../components/KineticCaption';
import { LiquidGlassPanel, ScopeKey } from '../components/LiquidGlassPanel';
import { CameraStage } from '../components/MacChrome';
import { spr, SPRING_GLASS, typewriter } from '../design/motion';
import { FONT_MONO, FONT_SANS, PRISM_PULSE, RADII } from '../design/tokens';

const CAPTIONS: CaptionBeat[] = [
  { start: 30, end: 580, tag: 'LCNTIDX3', text: '免前缀秒搜拼音软件与移动硬盘全盘文件 · 零拷贝 mmap 快照 + FSEvents 实时增量' },
  { start: 600, end: 1140, tag: 'CLIPBOARD', text: '富媒体剪贴板历史：文字、#HEX 色板、图片与文件一触回填，15 步撤回且自动跳过密码器' },
  { start: 1160, end: 1700, tag: 'DEV TOOLKIT', text: '内置算式、10 类中英单位换算与离线开发工具箱：JWT 解析、时间戳、UUID 与二维码' },
  { start: 1720, end: 2260, tag: 'QUICK SCRIPTS', text: '输入 ! 秒跑单文件快捷脚本库，支持 Zsh / Swift / AppleScript 与任意自定义 Shebang 及专属 SVG 图标' },
];

type DemoMode = 'files' | 'clipboard' | 'dev' | 'scripts';

export const Act2UnifiedSearch: React.FC = () => {
  const frame = useCurrentFrame();

  const demo: DemoMode =
    frame < 600 ? 'files' : frame < 1160 ? 'clipboard' : frame < 1720 ? 'dev' : 'scripts';

  const scope: ScopeKey = demo === 'files' ? 'files' : demo === 'clipboard' ? 'clip' : 'all';

  const query =
    demo === 'files'
      ? typewriter('Q4 财报 移动硬盘', frame, 120, 14)
      : demo === 'clipboard'
      ? typewriter('#7C5CFC', frame, 680, 16)
      : demo === 'dev'
      ? typewriter('128GB to MiB  ·  qr lucent', frame, 1200, 22)
      : typewriter('!clean-port 3000', frame, 1760, 20);

  const scriptRan = frame >= 2000;
  const enter = spr(frame, 8, SPRING_GLASS);

  const modes: { id: DemoMode; label: string; hint: string; icon: React.ReactNode }[] = [
    { id: 'files', label: '全盘与外置盘秒搜', hint: '0ms mmap', icon: <IconFolder size={17} /> },
    { id: 'clipboard', label: '富媒体剪贴板历史', hint: '15步撤回', icon: <IconClipboard size={17} /> },
    { id: 'dev', label: '算账换算 & 离线开发', hint: '10类单位', icon: <IconCalculator size={17} /> },
    { id: 'scripts', label: '! 单文件快捷脚本库', hint: 'SVG图标', icon: <IconTerminal size={17} /> },
  ];

  const rows =
    demo === 'files'
      ? [
          { title: '2026_Q4_核心财报定稿.pdf', sub: '/Volumes/SSD-Work/Finance · 4.8 MB', tag: '外置固态', grad: 'linear-gradient(135deg,#0ea5e9,#2563eb)', icon: <IconFolder size={17} /> },
          { title: 'Q4_营收拆解模型.xlsx', sub: '/Volumes/Samsung-T7/Reports · 1.2 MB', tag: 'NTFS只读', grad: 'linear-gradient(135deg,#10b981,#059669)', icon: <IconFolder size={17} /> },
          { title: 'Lucent_产品演示大纲.md', sub: '~/Documents/Lucent · 42 KB', tag: 'Markdown', grad: 'linear-gradient(135deg,#7c5cfc,#ec4899)', icon: <IconCode size={17} /> },
          { title: 'wx · 微信 (WeChat)', sub: '/Applications · 中文双音字拼音命中', tag: 'App', grad: 'linear-gradient(135deg,#22c55e,#16a34a)', icon: <IconSearch size={17} /> },
        ]
      : demo === 'clipboard'
      ? [
          { title: '#7C5CFC · Prism Pulse 品牌主紫', sub: 'RGB(124, 92, 252) · 刚刚复制', tag: '色值卡片', grad: 'linear-gradient(135deg,#7c5cfc,#a855f7)', icon: <IconClipboard size={17} /> },
          { title: '截屏_2026-11-19_高分图.png', sub: '2560 × 1440 · PNG 快照 · ⌘↵ 钉屏', tag: '图片', grad: 'linear-gradient(135deg,#0ea5e9,#06b6d4)', icon: <IconClipboard size={17} /> },
          { title: 'curl -fsSL https://.../resign.sh | bash', sub: '来自 Terminal · 回车直粘原窗口', tag: '文本', grad: 'linear-gradient(135deg,#475569,#1e293b)', icon: <IconTerminal size={17} /> },
          { title: '1Password 敏感凭据已自动过滤', sub: '隐私保护 · 绝不落盘历史', tag: '隐私守护', grad: 'linear-gradient(135deg,#10b981,#047857)', icon: <IconShield size={17} /> },
        ]
      : demo === 'dev'
      ? [
          { title: '= 131,072 MiB  (128 GB × 1024)', sub: '10 类中英自然单位换算 · 回车复制结果', tag: '单位换算', grad: 'linear-gradient(135deg,#38bdf8,#6366f1)', icon: <IconCalculator size={17} /> },
          { title: '离线二维码 · https://lengsukq.github.io/Lucent', sub: '本地矢量生成 · 零网络请求', tag: 'QR Code', grad: 'linear-gradient(135deg,#a855f7,#ec4899)', icon: <IconCode size={17} /> },
          { title: 'JWT Payload · exp: 2026-12-01 08:00', sub: '离线解码验证 · Header + Claims', tag: 'JWT', grad: 'linear-gradient(135deg,#f59e0b,#ea580c)', icon: <IconShield size={17} /> },
          { title: 'UUID v4 · 8f4c12a9-7b3d-4e92-91a0', sub: '毫秒级时间戳 / Base64 / SHA-256', tag: 'DevKit', grad: 'linear-gradient(135deg,#06b6d4,#0284c7)', icon: <IconTerminal size={17} /> },
        ]
      : [
          { title: '!clean-port · 一键释放本地占用端口', sub: '#!/usr/bin/env zsh · Scripts/clean-port.sh 双向同步', tag: 'Zsh · SVG', grad: 'linear-gradient(135deg,#f43f5e,#f97316)', icon: <svg width="19" height="19" viewBox="0 0 24 24" fill="none" stroke="#fff" strokeWidth="2.2"><circle cx="12" cy="12" r="8" /><path d="M12 7v5l3 2" /></svg> },
          { title: '!img-shrink · 无损压缩选中图片体积', sub: '#!/usr/bin/env zsh · 原生 sips 压缩 · @lucent.output toast', tag: 'Zsh', grad: 'linear-gradient(135deg,#10b981,#0ea5e9)', icon: <IconTerminal size={17} /> },
          { title: '!swift-bench · 运行 Swift 6 延迟基准', sub: '#!/usr/bin/swift · Seatbelt 沙箱隔离', tag: 'Swift', grad: 'linear-gradient(135deg,#f97316,#7c3aed)', icon: <IconCode size={17} /> },
          { title: ';sig · 展开动态短语模板（含当前日期）', sub: '快捷短语库 · 全应用即时展开', tag: 'Snippet', grad: 'linear-gradient(135deg,#6366f1,#38bdf8)', icon: <IconClipboard size={17} /> },
        ];

  return (
    <AbsoluteFill style={{ fontFamily: FONT_SANS }}>
      <AuroraBackdrop theme="prism-pulse" seedOffset={3240} />

      <div
        style={{
          position: 'absolute',
          inset: '74px 92px 104px',
          display: 'flex',
          flexDirection: 'column',
          alignItems: 'center',
          justifyContent: 'space-between',
        }}
      >
        {/* Top Centered Title + 4-Step Mode Indicator */}
        <div style={{ width: '100%', display: 'flex', alignItems: 'flex-end', justifyContent: 'space-between' }}>
          <SceneHeader
            eyebrow="02 / 07 · UNIFIED SEARCH & DAILY HUB"
            title="一个搜索框，"
            highlight="接管全部高频日常。"
            theme="prism-pulse"
            frame={frame}
            maxWidth={780}
          />

          <div style={{ display: 'flex', gap: 10, paddingBottom: 6 }}>
            {modes.map((m) => {
              const active = m.id === demo;
              return (
                <div
                  key={m.id}
                  style={{
                    padding: '10px 15px',
                    borderRadius: 15,
                    background: active ? PRISM_PULSE.accentGradient : PRISM_PULSE.bgCard,
                    border: `1px solid ${active ? 'rgba(255,255,255,0.45)' : PRISM_PULSE.rimOuter}`,
                    display: 'flex',
                    alignItems: 'center',
                    gap: 9,
                    color: active ? '#fff' : PRISM_PULSE.textSecondary,
                    boxShadow: active ? '0 10px 26px -6px rgba(124,92,252,0.55)' : PRISM_PULSE.cardShadow,
                  }}
                >
                  {m.icon}
                  <div>
                    <div style={{ fontSize: 13.5, fontWeight: 700 }}>{m.label}</div>
                    <div style={{ fontSize: 11, fontFamily: FONT_MONO, opacity: 0.8 }}>{m.hint}</div>
                  </div>
                </div>
              );
            })}
          </div>
        </div>

        {/* Center Locked 880x544 Panel with Dimension Lock Bracket & Living 3D Camera */}
        <CameraStage enterFrame={6} breathScale={0.008} tiltDeg={1.1} style={{ height: 'auto' }}>
        <div
          style={{
            position: 'relative',
            transform: `scale(${0.98 + enter * 0.10}) translateY(${(1 - enter) * 18 - 12}px)`,
            opacity: enter,
          }}
        >
          {/* Left Vertical Dimension Lock Callout */}
          <div
            style={{
              position: 'absolute',
              left: -178,
              top: 32,
              bottom: 32,
              width: 146,
              display: 'flex',
              flexDirection: 'column',
              alignItems: 'flex-end',
              justifyContent: 'center',
              gap: 10,
              paddingRight: 16,
              borderRight: '1.5px dashed rgba(103, 232, 249, 0.35)',
            }}
          >
            <span style={{ fontFamily: FONT_MONO, fontSize: 13, fontWeight: 700, color: '#67e8f9' }}>
              880 × 544
            </span>
            <span style={{ fontSize: 13, color: PRISM_PULSE.textTertiary, textAlign: 'right', lineHeight: 1.45 }}>
              恒定零跳动视窗
              <br />
              稳稳的肌肉记忆
            </span>
            <KeycapBadge keys={['⌘1', '⌘9']} size="sm" />
          </div>

          <LiquidGlassPanel
            theme="prism-pulse"
            width={880}
            height={544}
            query={query}
            activeScope={scope}
            dimensionTag="880 × 544 · 0ms Zero-Jitter"
            toastText={scriptRan ? '✓ 已清理 3000 端口 (PID 48219) · 耗时 18ms' : undefined}
          >
            <div style={{ display: 'grid', gridTemplateColumns: '1.22fr 0.78fr', gap: 14, flex: 1, minHeight: 0 }}>
              {/* Left Candidate List */}
              <div style={{ display: 'flex', flexDirection: 'column', gap: 8 }}>
                {rows.map((r, idx) => {
                  const selected = idx === 0;
                  return (
                    <div
                      key={r.title}
                      style={{
                        padding: '11px 13px',
                        borderRadius: RADII.row,
                        background: selected ? PRISM_PULSE.bgRowSelected : 'rgba(255,255,255,0.025)',
                        border: `1px solid ${selected ? PRISM_PULSE.rimSelected : 'transparent'}`,
                        display: 'flex',
                        alignItems: 'center',
                        gap: 12,
                      }}
                    >
                      <SquircleBadge gradient={r.grad} size={38}>
                        {r.icon}
                      </SquircleBadge>
                      <div style={{ flex: 1, minWidth: 0 }}>
                        <div style={{ fontSize: 14.5, fontWeight: 700, color: '#fff', whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>
                          {r.title}
                        </div>
                        <div style={{ fontSize: 12, color: PRISM_PULSE.textTertiary, marginTop: 2, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>
                          {r.sub}
                        </div>
                      </div>
                      <span
                        style={{
                          padding: '3px 8px',
                          borderRadius: 8,
                          background: 'rgba(255,255,255,0.08)',
                          fontFamily: FONT_MONO,
                          fontSize: 11,
                          color: PRISM_PULSE.textSecondary,
                          flexShrink: 0,
                        }}
                      >
                        ⌘{idx + 1}
                      </span>
                    </div>
                  );
                })}
              </div>

              {/* Right Contextual Side Preview Lens */}
              <div
                style={{
                  borderRadius: RADII.card,
                  background: PRISM_PULSE.bgWell,
                  border: `1px solid ${PRISM_PULSE.rimOuter}`,
                  padding: 18,
                  display: 'flex',
                  flexDirection: 'column',
                  justifyContent: 'space-between',
                }}
              >
                {demo === 'files' && (
                  <>
                    <div style={{ display: 'flex', flexDirection: 'column', gap: 10 }}>
                      <div style={{ fontFamily: FONT_MONO, fontSize: 11.5, color: '#67e8f9' }}>
                        LCNTIDX3 · ZERO-COPY MMAP
                      </div>
                      <div style={{ fontSize: 17, fontWeight: 700, color: '#fff' }}>2026_Q4_核心财报定稿.pdf</div>
                      <div
                        style={{
                          padding: 14,
                          borderRadius: 12,
                          background: 'rgba(255,255,255,0.04)',
                          border: `1px solid ${PRISM_PULSE.rimOuter}`,
                          display: 'flex',
                          flexDirection: 'column',
                          gap: 9,
                          fontFamily: FONT_MONO,
                          fontSize: 12,
                          color: PRISM_PULSE.textSecondary,
                        }}
                      >
                        <div style={{ display: 'flex', justifyContent: 'space-between' }}>
                          <span>索引节点</span>
                          <span style={{ color: '#fff', fontWeight: 700 }}>482,910 项</span>
                        </div>
                        <div style={{ display: 'flex', justifyContent: 'space-between' }}>
                          <span>检索耗时</span>
                          <span style={{ color: '#34d399', fontWeight: 700 }}>0.38 ms</span>
                        </div>
                        <div style={{ height: 5, borderRadius: 99, background: 'rgba(255,255,255,0.08)', overflow: 'hidden' }}>
                          <div style={{ width: '96%', height: '100%', background: 'linear-gradient(90deg,#22d3ee,#34d399)' }} />
                        </div>
                        <div style={{ display: 'flex', justifyContent: 'space-between' }}>
                          <span>增量同步</span>
                          <span style={{ color: '#67e8f9' }}>FSEvents + SHA-256 ✓</span>
                        </div>
                      </div>
                    </div>
                    <div style={{ fontSize: 12.5, color: '#34d399', display: 'flex', alignItems: 'center', gap: 6 }}>
                      <IconCheck size={15} color="#34d399" /> 移动硬盘即插即搜 · 零后台常驻扫盘
                    </div>
                  </>
                )}

                {demo === 'clipboard' && (
                  <>
                    <div style={{ display: 'flex', flexDirection: 'column', gap: 12 }}>
                      <div style={{ fontFamily: FONT_MONO, fontSize: 11.5, color: '#c4b5fd' }}>
                        COLOR & PRIVACY LENS
                      </div>
                      <div
                        style={{
                          height: 118,
                          borderRadius: 16,
                          background: 'linear-gradient(135deg, #7c5cfc 0%, #38bdf8 100%)',
                          boxShadow: '0 14px 32px -8px rgba(124,92,252,0.55), inset 0 1px 0 rgba(255,255,255,0.45)',
                          display: 'flex',
                          alignItems: 'flex-end',
                          padding: 14,
                          fontFamily: FONT_MONO,
                          fontWeight: 700,
                          color: '#fff',
                          fontSize: 18,
                        }}
                      >
                        #7C5CFC
                      </div>
                      <div style={{ display: 'flex', gap: 8 }}>
                        {['#7C5CFC', '#38BDF8', '#F472B6', '#34D399'].map((hex) => (
                          <div
                            key={hex}
                            style={{
                              flex: 1,
                              height: 22,
                              borderRadius: 7,
                              background: hex,
                              border: '1px solid rgba(255,255,255,0.32)',
                            }}
                          />
                        ))}
                      </div>
                      <div style={{ fontFamily: FONT_MONO, fontSize: 12, color: PRISM_PULSE.textSecondary, lineHeight: 1.65 }}>
                        HSL(252°, 96%, 67%) · RGB(124, 92, 252)
                        <br />
                        误删支持 15 步撤回 · 自动屏蔽密码器
                      </div>
                    </div>
                    <div style={{ fontSize: 12.5, color: '#67e8f9', display: 'flex', alignItems: 'center', gap: 6 }}>
                      <IconShield size={15} color="#67e8f9" /> 0600 本地加密收藏 · 回车直粘原窗口
                    </div>
                  </>
                )}

                {demo === 'dev' && (
                  <>
                    <div style={{ display: 'flex', flexDirection: 'column', gap: 10 }}>
                      <div style={{ fontFamily: FONT_MONO, fontSize: 11.5, color: '#67e8f9' }}>
                        OFFLINE DEV TOOLKIT
                      </div>
                      <div style={{ fontSize: 28, fontWeight: 800, fontFamily: FONT_MONO, color: '#38bdf8' }}>
                        131,072 MiB
                      </div>
                      {/* Crisp Offline SVG QR Mockup */}
                      <div style={{ display: 'flex', alignItems: 'center', gap: 14, marginTop: 4 }}>
                        <div
                          style={{
                            width: 92,
                            height: 92,
                            borderRadius: 12,
                            background: '#ffffff',
                            padding: 9,
                            display: 'grid',
                            gridTemplateColumns: 'repeat(7, 1fr)',
                            gap: 2,
                          }}
                        >
                          {[
                            1,1,1,0,1,1,1,
                            1,0,1,1,1,0,1,
                            1,1,1,0,1,1,1,
                            0,1,0,1,0,1,0,
                            1,1,1,1,0,1,1,
                            1,0,1,0,1,0,1,
                            1,1,1,0,1,1,0,
                          ].map((bit, bi) => (
                            <div key={bi} style={{ background: bit ? '#090f1d' : 'transparent', borderRadius: 1 }} />
                          ))}
                        </div>
                        <div style={{ fontSize: 12.5, color: PRISM_PULSE.textSecondary, lineHeight: 1.6 }}>
                          离线矢量二维码
                          <br />
                          支持算式 / 进制 / JWT
                          <br />
                          UUID / 哈希 / 色值
                        </div>
                      </div>
                    </div>
                    <div style={{ fontSize: 12, fontFamily: FONT_MONO, color: '#34d399' }}>
                      100% 本地离线计算 · 零外部依赖
                    </div>
                  </>
                )}

                {demo === 'scripts' && (
                  <>
                    <div style={{ display: 'flex', flexDirection: 'column', gap: 10 }}>
                      <div style={{ fontFamily: FONT_MONO, fontSize: 11.5, color: '#f472b6' }}>
                        QUICK SCRIPTS · 双向同步
                      </div>
                      <div
                        style={{
                          padding: 12,
                          borderRadius: 12,
                          background: PRISM_PULSE.studioBg,
                          border: `1px solid ${PRISM_PULSE.studioBorder}`,
                          fontFamily: FONT_MONO,
                          fontSize: 11.5,
                          lineHeight: 1.65,
                          color: PRISM_PULSE.studioText,
                        }}
                      >
                        <div style={{ color: PRISM_PULSE.studioMuted }}>#!/usr/bin/env zsh</div>
                        <div style={{ color: PRISM_PULSE.studioKw }}># @lucent.title 清理本地端口</div>
                        <div style={{ color: PRISM_PULSE.studioKey }}># @lucent.icon clean-port.svg</div>
                        <div style={{ color: PRISM_PULSE.studioStr }}>lsof -ti :&quot;$1&quot; | xargs kill -9</div>
                      </div>
                      <div
                        style={{
                          padding: '9px 12px',
                          borderRadius: 10,
                          background: scriptRan ? 'rgba(52, 211, 153, 0.16)' : 'rgba(255,255,255,0.05)',
                          border: `1px solid ${scriptRan ? 'rgba(52,211,153,0.45)' : PRISM_PULSE.rimOuter}`,
                          fontFamily: FONT_MONO,
                          fontSize: 12,
                          color: scriptRan ? '#6ee7b7' : PRISM_PULSE.textSecondary,
                        }}
                      >
                        {scriptRan ? '✓ Seatbelt 沙箱执行成功 · PID 48219 已释放' : '▶ 按回车经 Seatbelt 沙箱瞬时运行...'}
                      </div>
                    </div>
                    <div style={{ fontSize: 12, color: PRISM_PULSE.textTertiary, display: 'flex', alignItems: 'center', gap: 6 }}>
                      <IconCode size={14} color="#67e8f9" /> 支持 Zsh / Swift / AppleScript 及任意 #! Shebang
                    </div>
                  </>
                )}
              </div>
            </div>
          </LiquidGlassPanel>
        </div>
        </CameraStage>
      </div>

      <BottomCaptionBar beats={CAPTIONS} frame={frame} theme="prism-pulse" />
    </AbsoluteFill>
  );
};
