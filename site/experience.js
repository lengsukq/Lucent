/* ==========================================================================
   Lucent — Six-Morphology Optical Crystal WebGL2 Engine & Tactile UI
   Light Frost (晴霜浅色) & Obsidian Dark (曜石暗色)
   6 Industrial Sculptural Stages · Smooth themeBlend · 11 Swift Plugins · 21 MCP Tools
   ========================================================================== */

(() => {
'use strict';

/* --------------------------------------------------------------------------
   1. Safe Storage, Media Queries & Shared Cross-Page State
   -------------------------------------------------------------------------- */
const THEME_KEY = 'lucent-showcase-theme-v2';
const LANG_KEY = 'lucent-showcase-lang-v2';
const PLUGINS_KEY = 'lucent-enabled-plugins-v1';

function safeGetStorage(key, fallback = null) {
  try {
    const v = window.localStorage.getItem(key);
    return v !== null ? v : fallback;
  } catch (_) {
    return fallback;
  }
}

function safeSetStorage(key, val) {
  try {
    window.localStorage.setItem(key, val);
  } catch (_) {}
}

const colorSchemeQuery = window.matchMedia
  ? window.matchMedia('(prefers-color-scheme: dark)')
  : null;
const reducedMotionQuery = window.matchMedia
  ? window.matchMedia('(prefers-reduced-motion: reduce)')
  : null;

function isReducedMotion() {
  return Boolean(reducedMotionQuery && reducedMotionQuery.matches);
}

function detectSystemTheme() {
  return colorSchemeQuery && colorSchemeQuery.matches ? 'prism-pulse' : 'pure-frost';
}

const GH_HOST = ['https://', 'github.com', '/lengsukq/Lucent'].join('');
const ESM_CANDIDATES = [
  ['https://', 'registry.npmmirror.com', '/three/0.170.0/files/build/three.module.js'].join(''),
  ['https://', 'cdn.jsdelivr.net', '/npm/three@0.170.0/build/three.module.js'].join('')
];
const UMD_CANDIDATES = [
  ['https://', 'registry.npmmirror.com', '/three/0.158.0/files/build/three.min.js'].join(''),
  ['https://', 'cdn.bootcdn.net', '/ajax/libs/three.js/0.158.0/three.min.js'].join(''),
  ['https://', 'cdnjs.cloudflare.com', '/ajax/libs/three.js/0.158.0/three.min.js'].join('')
];
const CDN_RACE_TIMEOUT_MS = 950;

/* 11 Official Native Swift Plugins (Aligned with docs/STATUS.md & plugin-demo/) */
const PLUGINS = [
  { id: 'antigravity-pulse', zh: 'Antigravity 脉搏', en: 'Antigravity Pulse', color: 0x2997ff },
  { id: 'audio-presets', zh: '一键音频组合', en: 'Audio Presets', color: 0x5e7ce2 },
  { id: 'file-shelf', zh: '文件中转站', en: 'File Shelf', color: 0x0071e3 },
  { id: 'gold-monitor', zh: '金价悬浮窗', en: 'Gold Monitor HUD', color: 0xd99b43 },
  { id: 'translate-hub', zh: '流光译站', en: 'Translate Hub', color: 0x3b9eff },
  { id: 'browser-hub', zh: '三端书签', en: 'Browser Hub', color: 0x4f74d6 },
  { id: 'quick-remind', zh: '闪电提醒', en: 'Quick Remind', color: 0xc89548 },
  { id: 'mac-pilot', zh: '桌面中控台', en: 'Mac Pilot', color: 0x2aa9e0 },
  { id: 'screen-shield', zh: '状态屏遮罩', en: 'Screen Shield', color: 0x30d158 },
  { id: 'lumalink-companion', zh: '流光随行', en: 'LumaLink', color: 0x64b5ff },
  { id: 'notion-bookmarks', zh: 'Notion 书签', en: 'Notion Bookmarks', color: 0x43a688 }
];

/* 7 Acyclic Swift 6 DAG Nodes (Zero Neon Pink / Purple) */
const DAG_NODES = [
  { id: 'Lucent.app', zh: 'Lucent.app · 双主题与液态浮窗', en: 'Lucent.app · Dual-Theme Glass UI', pos: [-1.62, 2.28, 0.18], color: 0x2997ff },
  { id: 'lucent-mcp', zh: 'lucent-mcp · 21 项 AI 定制工具', en: 'lucent-mcp · 21 MCP Tools', pos: [1.62, 2.28, 0.18], color: 0x5e7ce2 },
  { id: 'LucentCore', zh: 'LucentCore · ⌘K 抽屉、脚本与插件', en: 'LucentCore · ⌘K Drawer & Plugin v3.7', pos: [0.0, 1.74, 0.36], color: 0x0071e3 },
  { id: 'LucentSearch', zh: 'LucentSearch · LCNTIDX3 秒搜', en: 'LucentSearch · LCNTIDX3 mmap', pos: [-2.26, -0.12, 0.22], color: 0x2aa9e0 },
  { id: 'LucentMedia', zh: 'LucentMedia · 截图标注 & 离线识字', en: 'LucentMedia · Capture, OCR & HEVC', pos: [0.0, -1.68, 0.36], color: 0x94b8e8 },
  { id: 'LucentSystem', zh: 'LucentSystem · 功耗脉搏 & 120Hz 滚轮', en: 'LucentSystem · Mach & 120Hz Wheel', pos: [2.26, -0.12, 0.22], color: 0x30d158 },
  { id: 'LucentFoundation', zh: 'LucentFoundation · 密钥箱 & 自洁进程', en: 'LucentFoundation · AES-GCM Vault', pos: [0.0, -2.42, 0.18], color: 0xd99b43 }
];

const STAGE_LABELS = {
  zh: [
    '00 · 轻巧可定制的快捷中枢',
    '01 · 启动面板定制与 ⌘K',
    '02 · 11 款官方原生插件',
    '03 · 21 项 lucent-mcp 共创',
    '04 · 五大原生利器与架构',
    '05 · 获取与开源共建'
  ],
  en: [
    '00 · CUSTOMIZABLE NATIVE HUB',
    '01 · LAUNCH PANEL & ⌘K DRAWER',
    '02 · 11 NATIVE SWIFT PLUGINS',
    '03 · 21 LUCENT-MCP TOOLS',
    '04 · NATIVE TOOLS & DAG',
    '05 · DOWNLOAD & OPEN SOURCE'
  ]
};

const FORGE_PRESETS = {
  pr: {
    zhQuote: '“帮我做一个磁吸贴边液态玻璃悬浮窗，实时监控代码会话与待审 PR，凭据安全存入加密保险箱。”',
    enQuote: '"Build an edge-dockable Liquid Glass HUD monitoring active sessions & PR reviews, with tokens sealed in the AES-GCM vault."',
    zhMeta: 'scaffold → validate → run_plugin_test · FSEvents 350ms 热重载生效',
    enMeta: 'scaffold → validate → run_plugin_test · FSEvents 350ms Hot-Reload'
  },
  home: {
    zhQuote: '“新建一套『极简开发』启动面板：保留 16 格混合应用坞，挂上 GitHub 与本地 3000 端口书签架，隐藏底部提示。”',
    enQuote: '"Create a Minimal Dev launch profile: keep a 16-slot hybrid dock, add a GitHub & localhost:3000 shelf, and hide tips."',
    zhMeta: 'lucent_get_home_layout → lucent_update_home_layout · 0ms 实时热刷新',
    enMeta: 'lucent_get_home_layout → lucent_update_home_layout · Instant Reload'
  },
  port: {
    zhQuote: '“帮我写个无损压缩图片体积的快捷脚本，起好中英名字并画一枚 64×64 专属 SVG 图标，绑定到 ⌘K 动作抽屉。”',
    enQuote: '"Write an image-compression Quick Script with bilingual names, draw a 64×64 SVG icon, and bind it to the ⌘K Action Drawer."',
    zhMeta: 'lucent_upsert_script (iconSvg) → lucent_run_script_test · 0ms 双向热同步',
    enMeta: 'lucent_upsert_script (iconSvg) → lucent_run_script_test · Live Two-Way Sync'
  }
};

const savedPluginsRaw = safeGetStorage(PLUGINS_KEY);
let initialPlugins = [
  'antigravity-pulse',
  'audio-presets',
  'file-shelf',
  'translate-hub',
  'browser-hub',
  'quick-remind',
  'mac-pilot'
];
if (savedPluginsRaw) {
  try {
    const parsed = JSON.parse(savedPluginsRaw);
    if (Array.isArray(parsed)) {
      const validIds = new Set(PLUGINS.map((p) => p.id));
      const filtered = parsed.filter((id) => validIds.has(id));
      if (filtered.length > 0 || parsed.length === 0) initialPlugins = filtered;
    }
  } catch (_) {}
}

const savedThemeRaw = safeGetStorage(THEME_KEY);
const hasStoredTheme = savedThemeRaw === 'pure-frost' || savedThemeRaw === 'prism-pulse';
const savedLangRaw = safeGetStorage(LANG_KEY);

const state = {
  theme: hasStoredTheme ? savedThemeRaw : detectSystemTheme(),
  hasManualTheme: hasStoredTheme,
  lang: savedLangRaw === 'en' ? 'en' : 'zh',
  enabledPlugins: new Set(initialPlugins),
  forgePreset: 'pr',
  autoPlaying: false,
  autoFinished: false,
  autoLayerShowcase: 0,
  scrollNorm: 0,
  sceneProgress: 0,
  activeScene: 0
};

function persistPlugins() {
  safeSetStorage(PLUGINS_KEY, JSON.stringify([...state.enabledPlugins]));
}

document.querySelectorAll('[data-gh-path]').forEach((el) => {
  const sub = el.getAttribute('data-gh-path') || '';
  el.setAttribute('href', `${GH_HOST}${sub}`);
  el.setAttribute('target', '_blank');
  el.setAttribute('rel', 'noopener noreferrer');
});

/* --------------------------------------------------------------------------
   2. Bilingual Product Copy (Aligned with docs/STATUS.md)
   -------------------------------------------------------------------------- */
const I18N = {
  zh: {
    nav_overview: '2D 图文详解',
    sound_on: '音效',
    sound_off: '静音',
    btn_play: '自动导览',
    btn_playing: '导览中',
    btn_replay: '重新导览',
    theme_dark: '曜石暗色',
    theme_light: '晴霜浅色',
    nav_get: '获取 DMG',
    ch_0: '序章 · 轻巧可定制的快捷中枢',
    ch_1: '启动面板定制、全盘秒搜与 ⌘K',
    ch_2: '11 款官方原生 Swift 插件生态',
    ch_3: '内置 21 项 lucent-mcp AI 共创',
    ch_4: '五大日常原生利器与 Swift 6 架构',
    ch_5: '获取原生 DMG 与开源共建',
    rail_0: '00 · 统一快捷中枢',
    rail_1: '01 · 启动面板与 ⌘K',
    rail_2: '02 · 11 款官方插件',
    rail_3: '03 · 21 项 MCP 共创',
    rail_4: '04 · 五大原生利器',
    rail_5: '05 · 下载与开源',
    s0_eyebrow: 'APPLE SILICON NATIVE · SWIFT 6 · 11 SWIFT PLUGINS · 21 MCP TOOLS',
    s0_title: '一触流光，|用完即焚。',
    s0_desc: '按一下 ⌥Space，找软件、搜文件、翻剪贴板、截屏识字与 ⌘K 上下文动作一步直达；~从启动面板、快捷脚本到 11 款官方原生插件皆可随心定制，松手即净不占后台。',
    s0_trigger: '体验 ⌥Space 瞬间唤醒',
    s0_overview_cta: '打开 2D 交互模拟器',
    s0_scroll: '向下滚动探索五大核心能力 · 支持 ↑ / ↓ 与 1–6 快捷键切换章节',
    s1_eyebrow: '01 / 05 · LAUNCH PANEL, UNIFIED SEARCH & ⌘K DRAWER',
    s1_title: '启动面板随心摆，\n一框秒搜与 ⌘K 动作直达。',
    s1_desc: '呼出瞬间就是你亲手布置的专属主页：大号 Bento 磁贴（2/3/4 列）、混排本机应用与常用目录的 8/16 格高频坞、多组命名书签胶囊架皆可自由编排并切换多套场景。直接打字即可免前缀秒搜拼音应用、外置盘文件、剪贴板历史（15 步撤回）与开发工具；对任意结果按 ⌘K 呼出液态玻璃上下文动作抽屉，纯键盘串联文件中转站、钉屏、离线识字与扩展脚本，880 × 544 视窗绝不乱跳。',
    s1_m1: '任意选中项按 ⌘K 呼出上下文动作抽屉，串联原生动作与匹配插件',
    s1_m2: 'LCNTIDX3 内存映射快照 + FSEvents 实时增量全盘秒搜',
    s1_m3: '收起 30s 释放视图缓存、空闲 90s 卸载索引页，安静省电不赖内存',
    s1_link: '前往 2D 实验台在线体验 ⌘K 动作抽屉与启动面板',
    s2_eyebrow: '02 / 05 · DEEP CUSTOMIZATION & 11 NATIVE SWIFT PLUGINS',
    s2_title: '从菜单栏到悬浮挂件，\n11 款官方扩展即装即原生。',
    s2_desc: '不用的功能零内存、零后台打扰；常用的能力支持精简排序顶部菜单栏、改唤醒词、录不抢焦点的静默快捷键，还能开启 Plugin v3.7 磁吸贴边液态玻璃浮窗、跨应用划词工具栏与双语朗读。粘贴仓库链接即可经 SHA-256 核验订阅 11 款官方原生 Swift 扩展（点击下方芯片实时联动 3D 水晶卫星）：',
    s2_link: '进入模块化拼装台查阅全部 11 款官方原生 Swift 扩展',
    s3_eyebrow: '03 / 05 · BUILT-IN LUCENT-MCP (21 TOOLS)',
    s3_title: '不会写代码也能定制，\n一句话造脚本、插件与主页。',
    s3_desc: '安装包直接内置零依赖 lucent-mcp 服务（21 项标准工具，支持按需授权离线检索本地 LCNTIDX3 文件快照），免配环境一键接入 Claude Code、Cursor、Codex 与 Gemini CLI。无论是写一枚带专属 SVG 图标的快捷脚本、打造透明悬浮插件，还是排好整套启动面板，几秒即可经 Seatbelt 沙箱实测并热重载生效：',
    f_pr: '一句话造插件 · 悬浮监控与 PR 雷达',
    f_home: '一句话排主页 · 极简开发启动面板',
    f_port: '一句话写脚本 · 绘专属 SVG 图标秒跑',
    s3_trigger: '模拟 AI 自动编排与 350ms 热重载',
    s3_trigger_done: '✓ 已通过沙箱校验并实时热刷新至 ⌥Space',
    s3_link: '查阅全部 21 项内置 MCP 工具与安全沙箱闭环',
    s4_eyebrow: '04 / 05 · EVERYDAY NATIVE TOOLS & SWIFT 6 DAG',
    s4_title: '开箱即享五大原生利器，\n零依赖极客级纯粹架构。',
    s4_desc: '没装任何插件前，高频刚需就已一应俱全：跨屏混合 DPI 截图标注、长截图拼接与单击窗口抠图钉屏（⌥A）、轻巧区域 GIF 录屏（⌥G）、一秒离线识字（⌥O）、不改触控板手感的物理鼠标 120Hz 平滑滚轮、双栏文件整理台（⌥E），以及按需查看芯片功耗（⌥M）、软件实时网速（⌥N）与原生 Markdown / 4K 视频阅读窗——全部浓缩在约 10 MB 纯正原生安装包中。',
    s4_m1: '100% 纯原生 Swift 6 直连 Apple Silicon 框架，拒绝网页套壳臃肿',
    s4_m2: '九大单向无环模块分层，构建门禁每次严查单文件 ≤ 300 行',
    s4_m3: 'Seatbelt 内核沙箱、LCNTVLT2 256-bit 密钥箱与 WebDAV 加密备份',
    s4_link: '查阅九大模块架构蓝图与五大原生利器详解',
    s5_eyebrow: 'MACOS 14+ · APPLE SILICON ARM64 · ~10 MB · MIT OPEN SOURCE',
    s5_title: '让每一次按键，|如流光掠影。',
    s5_desc: 'MIT 协议免费开源，内置「晴霜浅色 / 曜石暗色」液态折射双主题默认跟随系统外观，支持中英双语免重启秒切、应用内升级保留本机权限与一键加密备份漫游。立即下载原生 DMG，或进入 2D 实验台亲手定制你的 Lucent。',
    s5_cta_dmg: '下载 macOS 原生 DMG',
    s5_cta_home: '进入 2D 图文详解与定制实验台\u00a0→',
    p_hero: '启动面板与 ⌘K 模拟',
    p_builder: '11 款扩展拼装台',
    p_mcp: '21 项 MCP AI 共创',
    p_bento: '五大日常原生利器',
    p_arch: '极客 DAG 架构蓝图'
  },
  en: {
    nav_overview: '2D Overview',
    sound_on: 'Sound',
    sound_off: 'Muted',
    btn_play: 'Auto Tour',
    btn_playing: 'Touring',
    btn_replay: 'Replay Tour',
    theme_dark: 'Obsidian Dark',
    theme_light: 'Light Frost',
    nav_get: 'Get DMG',
    ch_0: 'Prologue · Customizable Native Hub',
    ch_1: 'Launch Panel, Search & ⌘K Drawer',
    ch_2: '11 Official Native Swift Plugins',
    ch_3: 'Built-In 21 lucent-mcp AI Tools',
    ch_4: '5 Native Tools & Swift 6 DAG',
    ch_5: 'Download DMG & Open Source',
    rail_0: '00 · Native Hub',
    rail_1: '01 · Panel & ⌘K',
    rail_2: '02 · 11 Plugins',
    rail_3: '03 · 21 MCP Tools',
    rail_4: '04 · Native Tools',
    rail_5: '05 · Get DMG',
    s0_eyebrow: 'APPLE SILICON NATIVE · SWIFT 6 · 11 SWIFT PLUGINS · 21 MCP TOOLS',
    s0_title: 'Summon Light. |Leave Zero Trace.',
    s0_desc: 'Press ⌥Space to launch apps, search drives, browse clipboard history, OCR your screen, or open the ⌘K Action Drawer — ~customize Home zones, Quick Scripts & 11 native plugins freely with zero bloat.',
    s0_trigger: 'Experience ⌥Space Instant Wake',
    s0_overview_cta: 'Open 2D Simulator',
    s0_scroll: 'SCROLL TO EXPLORE 5 PILLARS · USE ↑ / ↓ OR 1–6 TO JUMP',
    s1_eyebrow: '01 / 05 · LAUNCH PANEL, UNIFIED SEARCH & ⌘K DRAWER',
    s1_title: 'Shape Your Launch Panel.\nUnified Search & ⌘K Actions.',
    s1_desc: 'Open ⌥Space to a home screen built your way: 2/3/4-column Bento tiles, an 8/16-slot hybrid Omni Dock, and named pill shelves across switchable scene profiles. Type directly to search apps, external drives, clipboard history (15-step undo), and dev tools; press ⌘K on any result to summon the Liquid Glass Action Drawer for File Shelf, pin-to-screen, offline OCR, and scripts inside a zero-jitter 880 × 544 frame.',
    s1_m1: 'Press ⌘K on any candidate for native actions, File Shelf, OCR & matching scripts',
    s1_m2: 'LCNTIDX3 zero-copy mmap snapshot + live FSEvents full-disk search',
    s1_m3: 'Tears down UI cache in 30s and unmaps index heap after 90s idle',
    s1_link: 'Try the ⌘K Action Drawer & Launch Panel Live in 2D',
    s2_eyebrow: '02 / 05 · DEEP CUSTOMIZATION & 11 NATIVE SWIFT PLUGINS',
    s2_title: 'From Menu Bar to Glass HUD.\n11 Official Native Extensions.',
    s2_desc: 'Unused features take zero RAM or background polling. Trim the menu bar, set custom triggers and silent hotkeys, or run Plugin v3.7 edge-retractable Liquid Glass HUDs & Selection Quick Bar. Paste any repo URL for SHA-256 verified installs — toggle all 11 official native Swift plugins below to interact with the 3D crystal satellites:',
    s2_link: 'Explore All 11 Official Swift Plugins in the Workbench',
    s3_eyebrow: '03 / 05 · BUILT-IN LUCENT-MCP (21 TOOLS)',
    s3_title: 'No Coding Required.\nOne Sentence Builds Scripts, Plugins & Home.',
    s3_desc: 'Ships with an embedded zero-dependency lucent-mcp server (21 JSON-RPC 2.0 tools including opt-in offline LCNTIDX3 file search) ready for Claude Code, Cursor, Codex, and Gemini CLI. Ask AI to craft a Quick Script with a custom SVG icon, build a floating HUD plugin, or arrange your Launch Panel — validated inside Seatbelt and hot-reloaded live:',
    f_pr: 'Build Plugin · Glass HUD & PR Radar',
    f_home: 'Arrange Home · Minimal Dev Launch Panel',
    f_port: 'Craft Script · Custom SVG Icon & ⌘K Action',
    s3_trigger: 'Simulate AI Orchestration & Live Reload',
    s3_trigger_done: '✓ Verified in Seatbelt & Hot-Reloaded to ⌥Space',
    s3_link: 'Explore All 21 MCP Tools & Sandbox Security',
    s4_eyebrow: '04 / 05 · EVERYDAY NATIVE TOOLS & SWIFT 6 DAG',
    s4_title: 'Five Everyday Tools Built In.\nPure Zero-Dependency Architecture.',
    s4_desc: 'Before installing a single plugin, everyday essentials are ready: multi-display DPI capture, scrolling stitch & window cutouts (⌥A), lightweight GIF recording (⌥G), 1-second offline Vision OCR (⌥O), 120Hz smooth mouse wheel that leaves Trackpad untouched, dual-pane file workspace (⌥E), plus chip wattage (⌥M), app bandwidth (⌥N), and native Markdown / 4K video viewers in ~10 MB.',
    s4_m1: '100% pure Swift 6 atop Apple Silicon frameworks — zero web-wrapper bloat',
    s4_m2: '9 acyclic Swift targets with automated ≤ 300 LOC per-file build gates',
    s4_m3: 'Kernel Seatbelt sandbox, LCNTVLT2 256-bit vault & WebDAV backup',
    s4_link: 'Inspect 9-Module DAG Blueprint & 5 Native Tools',
    s5_eyebrow: 'MACOS 14+ · APPLE SILICON ARM64 · ~10 MB · MIT OPEN SOURCE',
    s5_title: 'Every Keystroke, |Pure Velocity.',
    s5_desc: 'Free & open source under MIT with Light Frost / Obsidian Dark Liquid Glass dual themes following macOS appearance by default, instant bilingual switching, in-app DMG updates preserving local permissions, and encrypted backup across Macs. Download the native DMG or explore the 2D workbench.',
    s5_cta_dmg: 'Download Native macOS DMG',
    s5_cta_home: 'Open 2D Overview & Customizer\u00a0→',
    p_hero: 'Launch Panel & ⌘K Sim',
    p_builder: '11 Plugins Workbench',
    p_mcp: '21 MCP AI Co-Creation',
    p_bento: '5 Everyday Native Tools',
    p_arch: 'Geek DAG Architecture'
  }
};

/* --------------------------------------------------------------------------
   3. DOM References, Boot Curtain & Bespoke Micro-FX Engine
   -------------------------------------------------------------------------- */
const bootVeil = document.getElementById('bootVeil');
const bootBarFill = document.getElementById('bootBarFill');
const timecodeIndex = document.getElementById('timecodeIndex');
const timecodeFill = document.getElementById('timecodeFill');
const railDroplet = document.getElementById('railDroplet');
const stageMorphBtn = document.getElementById('stageMorphBtn');
const stageMorphTag = document.getElementById('stageMorphTag');
const chapterPopover = document.getElementById('chapterPopover');
const filmPlayBtn = document.getElementById('filmPlayBtn');
const filmPlayLabel = document.getElementById('filmPlayLabel');
const soundToggleBtn = document.getElementById('soundToggleBtn');
const soundToggleLabel = document.getElementById('soundToggleLabel');
const themeToggleBtn = document.getElementById('themeToggleBtn');
const themeToggleLabel = document.getElementById('themeToggleLabel');
const langToggleBtn = document.getElementById('langToggleBtn');
const pluginWhisperList = document.getElementById('pluginWhisperList');
const pluginSummaryLine = document.getElementById('pluginSummaryLine');
const forgeSelector = document.getElementById('forgeSelector');
const forgeIndicator = document.getElementById('forgeIndicator');
const forgePromptQuote = document.getElementById('forgePromptQuote');
const forgePromptMeta = document.getElementById('forgePromptMeta');
const igniteForgeText = document.getElementById('igniteForgeText');
const heroKeycap = document.getElementById('heroKeycap');
const cursorAura = document.getElementById('cursorAura');
const cursorNodeLabel = document.getElementById('cursorNodeLabel');

let bootDismissed = false;
function dismissBootVeilImmediate() {
  if (bootDismissed) return;
  bootDismissed = true;
  if (bootBarFill) bootBarFill.style.width = '100%';
  if (bootVeil) bootVeil.classList.add('ready');
}

function scheduleBootDismissAfterFirstFrame() {
  if (bootDismissed) return;
  if (bootBarFill) bootBarFill.style.width = '100%';
  setTimeout(dismissBootVeilImmediate, isReducedMotion() ? 20 : 350);
}

// Safety ceiling if network/GPU takes longer
setTimeout(dismissBootVeilImmediate, 1750);

/* Tactile Micro-FX Helpers */
function spawnOpticalRipple(el, event, accentMode = false) {
  if (!el || isReducedMotion()) return;
  const rect = el.getBoundingClientRect();
  const hasCoords = event && typeof event.clientX === 'number' && (event.clientX !== 0 || event.clientY !== 0);
  const x = hasCoords ? event.clientX - rect.left : rect.width * 0.5;
  const y = hasCoords ? event.clientY - rect.top : rect.height * 0.5;
  const size = Math.max(rect.width, rect.height) * 0.9;

  const ripple = document.createElement('span');
  ripple.className = accentMode ? 'fx-ripple fx-ripple-accent' : 'fx-ripple';
  ripple.style.width = `${size}px`;
  ripple.style.height = `${size}px`;
  ripple.style.left = `${x}px`;
  ripple.style.top = `${y}px`;
  el.appendChild(ripple);
  const cleanup = () => ripple.remove();
  ripple.addEventListener('animationend', cleanup, { once: true });
  setTimeout(cleanup, 650);
}

function triggerGlintSweep(el) {
  if (!el || isReducedMotion()) return;
  const glint = document.createElement('span');
  glint.className = 'fx-glint-layer';
  el.appendChild(glint);
  const cleanup = () => glint.remove();
  glint.addEventListener('animationend', cleanup, { once: true });
  setTimeout(cleanup, 540);
}

function triggerSpringBounce(el) {
  if (!el || isReducedMotion()) return;
  el.classList.remove('fx-bouncing');
  void el.offsetWidth;
  el.classList.add('fx-bouncing');
  el.addEventListener('animationend', () => el.classList.remove('fx-bouncing'), { once: true });
}

function triggerKeycapPress(el = heroKeycap) {
  if (!el) return;
  el.classList.remove('key-pressed', 'key-halo');
  void el.offsetWidth;
  el.classList.add('key-pressed');
  setTimeout(() => {
    el.classList.remove('key-pressed');
    if (!isReducedMotion()) {
      el.classList.add('key-halo');
      el.addEventListener('animationend', () => el.classList.remove('key-halo'), { once: true });
    }
  }, 130);
}

function bindButtonMicroFx() {
  document.querySelectorAll('[data-fx="primary"]').forEach((el) => {
    el.addEventListener('click', (e) => {
      spawnOpticalRipple(el, e, false);
      triggerGlintSweep(el);
      triggerSpringBounce(el);
    });
  });

  document.querySelectorAll('[data-fx="pill"]').forEach((el) => {
    el.addEventListener('click', (e) => {
      spawnOpticalRipple(el, e, true);
      triggerSpringBounce(el);
    });
  });

  document.querySelectorAll('[data-glass-card]').forEach((card) => {
    card.addEventListener('pointermove', (e) => {
      if (isReducedMotion()) return;
      const rect = card.getBoundingClientRect();
      const px = e.clientX - rect.left;
      const py = e.clientY - rect.top;
      card.style.setProperty('--mx', `${px.toFixed(1)}px`);
      card.style.setProperty('--my', `${py.toFixed(1)}px`);
      card.style.setProperty('--sheen-opacity', '0.88');
    }, { passive: true });

    card.addEventListener('pointerleave', () => {
      card.style.setProperty('--sheen-opacity', '0.52');
      card.style.setProperty('--press-rx', '0deg');
      card.style.setProperty('--press-ry', '0deg');
      card.style.setProperty('--press-ty', '0px');
    });

    card.addEventListener('pointerenter', () => {
      if (isReducedMotion()) return;
      card.classList.remove('card-glinting');
      void card.offsetWidth;
      card.classList.add('card-glinting');
    });

    card.addEventListener('pointerdown', (e) => {
      if (isReducedMotion()) return;
      const rect = card.getBoundingClientRect();
      const nx = ((e.clientX - rect.left) / Math.max(1, rect.width) - 0.5) * 2;
      const ny = ((e.clientY - rect.top) / Math.max(1, rect.height) - 0.5) * 2;
      card.style.setProperty('--press-rx', `${(-ny * 1.15).toFixed(2)}deg`);
      card.style.setProperty('--press-ry', `${(nx * 1.15).toFixed(2)}deg`);
      card.style.setProperty('--press-ty', '1.5px');
      card.classList.remove('card-glinting');
      void card.offsetWidth;
      card.classList.add('card-glinting');
    });

    const releaseTilt = () => {
      card.style.setProperty('--press-rx', '0deg');
      card.style.setProperty('--press-ry', '0deg');
      card.style.setProperty('--press-ty', '0px');
    };
    card.addEventListener('pointerup', releaseTilt);
    card.addEventListener('pointercancel', releaseTilt);
  });
}

bindButtonMicroFx();

/* --------------------------------------------------------------------------
   4. Sound, Header Chapter Popover, Plugin Chips, Forge Indicator & Theme Sync
   -------------------------------------------------------------------------- */
const soundApi = window.LucentSound || null;

let shaderBridge = {
  triggerPulse: () => {},
  triggerForgeCollapse: () => {},
  syncPluginMask: () => {},
  syncTheme: () => {}
};

function syncSoundButtonUi(status = soundApi?.getStatus?.()) {
  if (!soundToggleBtn || !status) return;
  const dict = I18N[state.lang] || I18N.zh;
  soundToggleBtn.classList.toggle('sound-active', Boolean(status.active));
  soundToggleBtn.classList.toggle('sound-muted', !status.enabled);
  soundToggleBtn.setAttribute('aria-pressed', String(Boolean(status.enabled)));
  if (soundToggleLabel) {
    soundToggleLabel.textContent = status.enabled ? dict.sound_on : dict.sound_off;
  }
}

soundApi?.onStateChange?.((status) => {
  syncSoundButtonUi(status);
});

function setChapterPopoverOpen(open) {
  if (!chapterPopover || !stageMorphBtn) return;
  chapterPopover.hidden = !open;
  stageMorphBtn.setAttribute('aria-expanded', String(open));
}

stageMorphBtn?.addEventListener('click', (e) => {
  e.stopPropagation();
  const isOpen = !chapterPopover.hidden;
  setChapterPopoverOpen(!isOpen);
  soundApi?.playUiTick?.('click');
});

document.addEventListener('click', (e) => {
  if (chapterPopover && !chapterPopover.hidden && !e.target?.closest?.('.chapter-pill-wrap')) {
    setChapterPopoverOpen(false);
  }
});

function syncStageMorphLabel() {
  if (stageMorphTag) {
    const list = STAGE_LABELS[state.lang] || STAGE_LABELS.zh;
    stageMorphTag.textContent = list[state.activeScene] || list[0];
  }
  document.querySelectorAll('.chapter-menu-item').forEach((item, idx) => {
    item.classList.toggle('active', idx === state.activeScene);
  });
}

function syncRailDroplet() {
  if (!railDroplet) return;
  const activeDot = document.querySelector('#timecodeDots .tc-dot.active');
  if (!activeDot) return;
  const centerY = activeDot.offsetTop + activeDot.offsetHeight * 0.5;
  railDroplet.style.transform = `translate3d(0, ${centerY.toFixed(1)}px, 0)`;
}

function syncForgeIndicator() {
  if (!forgeIndicator || !forgeSelector) return;
  const activeOpt = forgeSelector.querySelector('.forge-option.active');
  if (!activeOpt) return;
  const top = activeOpt.offsetTop + 8;
  const height = Math.max(18, activeOpt.offsetHeight - 16);
  forgeIndicator.style.transform = `translate3d(0, ${top.toFixed(1)}px, 0)`;
  forgeIndicator.style.height = `${height.toFixed(1)}px`;
}

function renderForgePrompt() {
  const preset = FORGE_PRESETS[state.forgePreset] || FORGE_PRESETS.pr;
  const zh = state.lang === 'zh';
  if (forgePromptQuote) forgePromptQuote.textContent = zh ? preset.zhQuote : preset.enQuote;
  if (forgePromptMeta) forgePromptMeta.textContent = zh ? preset.zhMeta : preset.enMeta;
}

function renderPluginWhispers(justMountedId = null) {
  if (!pluginWhisperList) return;
  const zh = state.lang === 'zh';
  pluginWhisperList.innerHTML = PLUGINS.map((p, idx) => {
    const mounted = state.enabledPlugins.has(p.id);
    const popClass = justMountedId === p.id && mounted ? ' chip-just-mounted' : '';
    return `
      <button type="button" class="plugin-whisper-chip ${mounted ? 'mounted' : ''}${popClass}" data-pid="${p.id}" data-pidx="${idx}" aria-pressed="${mounted}">
        <span class="chip-dot" aria-hidden="true"></span>
        <span>${zh ? p.zh : p.en}</span>
      </button>
    `;
  }).join('');

  if (pluginSummaryLine) {
    const n = state.enabledPlugins.size;
    pluginSummaryLine.textContent = zh
      ? `已按需启用 ${n} / ${PLUGINS.length} 款官方扩展  ·  常驻守护进程：0  ·  Seatbelt 沙箱隔离`
      : `ACTIVE OFFICIAL PLUGINS: ${n} / ${PLUGINS.length}  ·  RESIDENT DAEMONS: 0  ·  SEATBELT ISOLATED`;
  }

  pluginWhisperList.querySelectorAll('[data-pid]').forEach((btn) => {
    btn.addEventListener('click', (e) => {
      const id = btn.getAttribute('data-pid');
      togglePluginById(id, e);
    });
  });
}

function togglePluginById(id, event = null) {
  const willEnable = !state.enabledPlugins.has(id);
  if (willEnable) state.enabledPlugins.add(id);
  else state.enabledPlugins.delete(id);
  persistPlugins();
  renderPluginWhispers(willEnable ? id : null);

  if (pluginWhisperList) {
    const updatedBtn = pluginWhisperList.querySelector(`[data-pid="${id}"]`);
    if (updatedBtn) {
      spawnOpticalRipple(updatedBtn, event, true);
      triggerSpringBounce(updatedBtn);
    }
  }

  shaderBridge.syncPluginMask();
  shaderBridge.triggerPulse(0.75, false);
  soundApi?.playPluginToggle?.(willEnable);
}

function applyTheme(themeId, { persist = true } = {}) {
  const valid = themeId === 'pure-frost' ? 'pure-frost' : 'prism-pulse';
  state.theme = valid;
  document.documentElement.setAttribute('data-theme', valid);
  if (persist) {
    state.hasManualTheme = true;
    safeSetStorage(THEME_KEY, valid);
  }
  const dict = I18N[state.lang] || I18N.zh;
  if (themeToggleLabel) {
    themeToggleLabel.textContent = valid === 'pure-frost' ? dict.theme_light : dict.theme_dark;
  }
  if (themeToggleBtn) {
    themeToggleBtn.setAttribute(
      'aria-label',
      state.lang === 'zh'
        ? `当前主题：${valid === 'pure-frost' ? dict.theme_light : dict.theme_dark}，点击切换`
        : `Current theme: ${valid === 'pure-frost' ? dict.theme_light : dict.theme_dark}, click to switch`
    );
  }
  shaderBridge.syncTheme(valid);
}

function toggleThemeWithTransition(event) {
  const nextTheme = state.theme === 'pure-frost' ? 'prism-pulse' : 'pure-frost';
  soundApi?.playUiTick?.('theme');

  if (!document.startViewTransition || isReducedMotion()) {
    applyTheme(nextTheme, { persist: true });
    return;
  }

  let x = window.innerWidth * 0.82;
  let y = 32;
  if (event && typeof event.clientX === 'number' && (event.clientX !== 0 || event.clientY !== 0)) {
    x = event.clientX;
    y = event.clientY;
  } else if (themeToggleBtn) {
    const r = themeToggleBtn.getBoundingClientRect();
    x = r.left + r.width * 0.5;
    y = r.top + r.height * 0.5;
  }
  const maxR = Math.hypot(
    Math.max(x, window.innerWidth - x),
    Math.max(y, window.innerHeight - y)
  ) + 96;

  const rootStyle = document.documentElement.style;
  rootStyle.setProperty('--vt-x', `${x.toFixed(1)}px`);
  rootStyle.setProperty('--vt-y', `${y.toFixed(1)}px`);
  rootStyle.setProperty('--vt-max-r', `${Math.ceil(maxR)}px`);

  try {
    document.startViewTransition(() => {
      applyTheme(nextTheme, { persist: true });
    });
  } catch (_) {
    applyTheme(nextTheme, { persist: true });
  }
}

colorSchemeQuery?.addEventListener?.('change', (e) => {
  if (!state.hasManualTheme) {
    applyTheme(e.matches ? 'prism-pulse' : 'pure-frost', { persist: false });
  }
});

window.addEventListener('storage', (e) => {
  if (e.key === THEME_KEY && (e.newValue === 'pure-frost' || e.newValue === 'prism-pulse')) {
    applyTheme(e.newValue, { persist: false });
    state.hasManualTheme = true;
  } else if (e.key === LANG_KEY && (e.newValue === 'zh' || e.newValue === 'en')) {
    applyLanguage(e.newValue, { persist: false });
  }
});

function applyLanguage(lang, { persist = true } = {}) {
  state.lang = lang === 'en' ? 'en' : 'zh';
  document.documentElement.lang = state.lang === 'zh' ? 'zh-CN' : 'en';
  if (persist) safeSetStorage(LANG_KEY, state.lang);
  const dict = I18N[state.lang];

  document.querySelectorAll('[data-i18n]').forEach((el) => {
    const key = el.getAttribute('data-i18n');
    const val = dict[key];
    if (val === undefined) return;
    if (val.includes('|')) {
      el.innerHTML = val
        .split('|')
        .map((s) => {
          const trail = /\s$/.test(s) ? ' ' : '';
          return `<span class="title-clause">${s.trim()}</span>${trail}`;
        })
        .join('');
    } else if (val.includes('~')) {
      el.innerHTML = val
        .split('~')
        .map((s) => {
          const trail = /\s$/.test(s) ? ' ' : '';
          return `<span class="prose-clause">${s.trim()}</span>${trail}`;
        })
        .join('');
    } else if (val.includes('\n')) {
      el.innerHTML = val.split('\n').join('<br/>');
    } else {
      el.textContent = val;
    }
  });

  if (langToggleBtn) langToggleBtn.textContent = state.lang === 'zh' ? 'EN' : '中文';
  if (themeToggleLabel) {
    themeToggleLabel.textContent = state.theme === 'pure-frost' ? dict.theme_light : dict.theme_dark;
  }
  syncPlayButtonUi();
  syncSoundButtonUi();

  const tcTitles = STAGE_LABELS[state.lang] || STAGE_LABELS.zh;
  document.querySelectorAll('#timecodeDots .tc-dot').forEach((dot, idx) => {
    if (tcTitles[idx]) dot.setAttribute('aria-label', tcTitles[idx]);
  });
  const rail = document.querySelector('.timecode-rail');
  if (rail) rail.setAttribute('aria-label', state.lang === 'zh' ? '产品章节导航' : 'Product chapter navigation');
  if (pluginWhisperList) {
    pluginWhisperList.setAttribute('aria-label', state.lang === 'zh' ? '11 款官方插件按需挂载切换' : 'Toggle 11 official Swift plugins');
  }
  document.title = state.lang === 'zh'
    ? '流光 Lucent — 一触流光，用完即焚 (可深度定制的 Apple Silicon 原生效率中枢)'
    : 'Lucent — Summon Light, Leave Zero Trace (Customizable Apple Silicon Native Hub)';

  syncStageMorphLabel();
  renderForgePrompt();
  renderPluginWhispers();
  requestAnimationFrame(() => {
    refreshLayoutMetrics();
    syncForgeIndicator();
    syncRailDroplet();
  });
}

/* --------------------------------------------------------------------------
   5. Auto-Director Tour, Chapter Jumps & Keyboard Navigation
   -------------------------------------------------------------------------- */
const SCENE_DWELL_SECONDS = [1.15, 3.6, 3.6, 3.6, 3.6, 0];
let autoPhase = 'hold';
let autoPhaseTime = 0;
let autoCurrentHoldDur = 0.32;
let autoSceneIdx = 0;
let autoGlideFromY = 0;
let autoGlideToY = 0;
let autoStageTriggered = false;

let cachedVh = Math.max(1, window.innerHeight);
let cachedMaxScroll = 1;
let cachedStops = [0, 1];
let cachedCenters = [0];

function refreshLayoutMetrics() {
  cachedVh = Math.max(1, window.innerHeight);
  cachedMaxScroll = Math.max(1, document.documentElement.scrollHeight - cachedVh);
  const secs = Array.from(document.querySelectorAll('.film-scene'));
  if (secs.length === 0) {
    cachedStops = [0, cachedMaxScroll];
    cachedCenters = [cachedVh * 0.5];
    return;
  }
  cachedCenters = secs.map((sec) => sec.offsetTop + sec.offsetHeight * 0.5);
  cachedStops = secs.map((_, idx) => {
    if (idx === 0) return 0;
    if (idx === secs.length - 1) return cachedMaxScroll;
    return Math.max(0, Math.min(cachedMaxScroll, cachedCenters[idx] - cachedVh * 0.5));
  });
}

function easeInOutCubic(t) {
  return t < 0.5 ? 4 * t * t * t : 1 - Math.pow(-2 * t + 2, 3) / 2;
}

function syncPlayButtonUi() {
  const dict = I18N[state.lang] || I18N.zh;
  filmPlayBtn?.classList.toggle('playing', state.autoPlaying);
  filmPlayBtn?.setAttribute('aria-pressed', String(state.autoPlaying));
  if (filmPlayLabel) {
    if (state.autoPlaying) filmPlayLabel.textContent = dict.btn_playing;
    else if (state.autoFinished) filmPlayLabel.textContent = dict.btn_replay;
    else filmPlayLabel.textContent = dict.btn_play;
  }
}

function stopAutoPlay(finishedAtEnd = false) {
  state.autoPlaying = false;
  state.autoFinished = finishedAtEnd;
  state.autoLayerShowcase = 0;
  syncPlayButtonUi();
}

function jumpToScene(idx) {
  const clamped = Math.max(0, Math.min(5, idx));
  stopAutoPlay(false);
  setChapterPopoverOpen(false);
  document.getElementById(`sec-${clamped}`)?.scrollIntoView({
    behavior: isReducedMotion() ? 'auto' : 'smooth',
    block: 'center'
  });
  soundApi?.playUiTick?.('click');
}

function startAutoPlayFromCurrent() {
  const stops = cachedStops;
  const maxScroll = stops[stops.length - 1] || 1;
  let curY = window.scrollY;
  let rewoundFromBottom = false;

  if (curY >= maxScroll - 24) {
    curY = 0;
    rewoundFromBottom = true;
    window.scrollTo(0, 0);
  }

  let matchedIdx = -1;
  for (let i = 0; i < stops.length; i++) {
    if (Math.abs(curY - stops[i]) <= 32) {
      matchedIdx = i;
      break;
    }
  }

  state.autoPlaying = true;
  state.autoFinished = false;
  autoPhaseTime = 0;
  autoStageTriggered = false;
  shaderBridge.triggerPulse(0.75, false);

  if (matchedIdx >= 0 && matchedIdx < stops.length - 1) {
    window.scrollTo(0, stops[matchedIdx]);
    autoPhase = 'hold';
    autoSceneIdx = matchedIdx;
    autoCurrentHoldDur = rewoundFromBottom ? SCENE_DWELL_SECONDS[0] : 0.32;
    autoStageTriggered = true;
  } else {
    let nextIdx = stops.findIndex((sy) => sy > curY + 32);
    if (nextIdx < 0) nextIdx = stops.length - 1;
    autoPhase = 'glide';
    autoSceneIdx = nextIdx;
    autoGlideFromY = curY;
    autoGlideToY = stops[nextIdx];
  }
  syncPlayButtonUi();
}

function triggerSceneHoldShowcase(idx) {
  if (idx === 0 || idx === 2) shaderBridge.triggerPulse(0.85);
  else if (idx === 3) shaderBridge.triggerForgeCollapse();
  else if (idx === 4) shaderBridge.triggerPulse(0.95);
}

function stepAutoPlay(dt) {
  if (!state.autoPlaying) return;
  const stops = cachedStops;
  const lastIdx = stops.length - 1;
  autoPhaseTime += dt;

  if (autoPhase === 'hold') {
    const holdDur = autoCurrentHoldDur;
    if (!autoStageTriggered && autoPhaseTime >= 0.55) {
      autoStageTriggered = true;
      triggerSceneHoldShowcase(autoSceneIdx);
    }
    if (autoSceneIdx === 1 && holdDur > 1.0) {
      const bell = Math.sin(Math.min(1, autoPhaseTime / holdDur) * Math.PI);
      state.autoLayerShowcase = Math.max(0, bell * 0.92);
    } else {
      state.autoLayerShowcase = 0;
    }

    if (autoPhaseTime >= holdDur) {
      state.autoLayerShowcase = 0;
      const nextIdx = autoSceneIdx + 1;
      if (nextIdx > lastIdx) {
        stopAutoPlay(true);
        return;
      }
      autoPhase = 'glide';
      autoPhaseTime = 0;
      autoStageTriggered = false;
      autoGlideFromY = window.scrollY;
      autoGlideToY = stops[nextIdx];
      autoSceneIdx = nextIdx;
    }
  } else {
    const distance = Math.abs(autoGlideToY - autoGlideFromY);
    const dur = Math.max(0.85, Math.min(2.10, (distance / Math.max(1, window.innerHeight)) * 1.50));
    const t = Math.min(1, autoPhaseTime / dur);
    const eased = easeInOutCubic(t);
    const targetY = autoGlideFromY + (autoGlideToY - autoGlideFromY) * eased;
    window.scrollTo(0, targetY);

    if (t >= 1) {
      window.scrollTo(0, autoGlideToY);
      if (autoSceneIdx >= lastIdx) {
        stopAutoPlay(true);
        shaderBridge.triggerPulse(1.15);
        return;
      }
      autoPhase = 'hold';
      autoPhaseTime = 0;
      autoCurrentHoldDur = SCENE_DWELL_SECONDS[autoSceneIdx] ?? 3.6;
      autoStageTriggered = false;
    }
  }
}

soundToggleBtn?.addEventListener('click', () => {
  soundApi?.toggleEnabled?.();
});

themeToggleBtn?.addEventListener('click', (e) => {
  toggleThemeWithTransition(e);
});

langToggleBtn?.addEventListener('click', () => {
  applyLanguage(state.lang === 'zh' ? 'en' : 'zh', { persist: true });
  soundApi?.playUiTick?.('lang');
});

filmPlayBtn?.addEventListener('click', () => {
  if (state.autoPlaying) {
    stopAutoPlay(false);
    soundApi?.playUiTick?.('click');
  } else {
    startAutoPlayFromCurrent();
    soundApi?.playUiTick?.('play');
  }
});

window.addEventListener('wheel', () => {
  if (state.autoPlaying) stopAutoPlay(false);
}, { passive: true });

window.addEventListener('touchstart', () => {
  if (state.autoPlaying) stopAutoPlay(false);
}, { passive: true });

document.getElementById('brandTopLink')?.addEventListener('click', (e) => {
  e.preventDefault();
  stopAutoPlay(false);
  setChapterPopoverOpen(false);
  window.scrollTo({ top: 0, behavior: isReducedMotion() ? 'auto' : 'smooth' });
});

document.querySelectorAll('[data-jump]').forEach((el) => {
  el.addEventListener('click', () => {
    const idx = Number(el.getAttribute('data-jump'));
    jumpToScene(idx);
  });
});

document.getElementById('heroPulseBtn')?.addEventListener('click', () => {
  triggerKeycapPress(heroKeycap);
  shaderBridge.triggerPulse(1.25);
});

let forgeStatusTimer = null;
function flashForgeSuccess() {
  const dict = I18N[state.lang] || I18N.zh;
  if (!igniteForgeText) return;
  igniteForgeText.textContent = dict.s3_trigger_done;
  if (forgeStatusTimer) clearTimeout(forgeStatusTimer);
  forgeStatusTimer = setTimeout(() => {
    const d = I18N[state.lang] || I18N.zh;
    if (igniteForgeText) igniteForgeText.textContent = d.s3_trigger;
  }, 2200);
}

document.querySelectorAll('[data-forge]').forEach((btn) => {
  btn.addEventListener('click', (e) => {
    state.forgePreset = btn.getAttribute('data-forge');
    document.querySelectorAll('[data-forge]').forEach((b) => {
      const active = b === btn;
      b.classList.toggle('active', active);
      b.setAttribute('aria-checked', String(active));
    });
    spawnOpticalRipple(btn, e, true);
    triggerSpringBounce(btn);
    syncForgeIndicator();
    renderForgePrompt();
    shaderBridge.triggerForgeCollapse();
    flashForgeSuccess();
  });
});

document.getElementById('igniteForgeBtn')?.addEventListener('click', () => {
  const kbd = document.querySelector('#igniteForgeBtn .kbd-whisper');
  triggerKeycapPress(kbd);
  shaderBridge.triggerForgeCollapse();
  flashForgeSuccess();
});

let lastArrowJumpAt = 0;
window.addEventListener('keydown', (e) => {
  if (e.target && /^(INPUT|TEXTAREA|SELECT)$/.test(e.target.tagName)) return;

  if (e.key === 'Escape') {
    setChapterPopoverOpen(false);
    return;
  }

  if ((e.altKey && e.code === 'Space') || e.key === '/') {
    e.preventDefault();
    triggerKeycapPress(heroKeycap);
    shaderBridge.triggerPulse(1.3);
  } else if (e.key >= '1' && e.key <= '6' && !e.metaKey && !e.ctrlKey && !e.altKey) {
    e.preventDefault();
    jumpToScene(Number(e.key) - 1);
  } else if ((e.key === 'ArrowDown' || e.key === 'ArrowUp') && !e.metaKey && !e.ctrlKey && !e.altKey) {
    const now = performance.now();
    if (now - lastArrowJumpAt < 260) {
      e.preventDefault();
      return;
    }
    lastArrowJumpAt = now;
    e.preventDefault();
    const delta = e.key === 'ArrowDown' ? 1 : -1;
    jumpToScene(state.activeScene + delta);
  }
});

applyTheme(state.theme, { persist: false });
applyLanguage(state.lang, { persist: false });

/* Deep-Link Jump (?scene=plugins | mcp | dag | engines) */
const sceneQuery = new URLSearchParams(window.location.search).get('scene') || '';
const SCENE_TO_SEC = {
  hero: 'sec-1', launcher: 'sec-1',
  plugins: 'sec-2', builder: 'sec-2',
  mcp: 'sec-3', theatre: 'sec-3',
  engines: 'sec-4', capabilities: 'sec-4',
  dag: 'sec-4', architecture: 'sec-4'
};
if (SCENE_TO_SEC[sceneQuery]) {
  requestAnimationFrame(() => {
    document.getElementById(SCENE_TO_SEC[sceneQuery])?.scrollIntoView({ behavior: 'auto' });
  });
}

/* --------------------------------------------------------------------------
   6. Scroll-Scrubbed Optical Depth-of-Field Kinetic Typography Engine
   -------------------------------------------------------------------------- */
const sceneSections = Array.from(document.querySelectorAll('.film-scene'));
const timecodeDotEls = Array.from(document.querySelectorAll('#timecodeDots .tc-dot'));
const kineticBlocks = sceneSections.map((sec) => ({
  sec,
  copy: sec.querySelector('[data-kinetic]')
}));

function plateauBlend(f) {
  const lo = 0.16, hi = 0.84;
  if (f <= lo) return 0;
  if (f >= hi) return 1;
  const u = (f - lo) / (hi - lo);
  return u * u * (3 - 2 * u);
}

function updateScrollAndKineticDOM() {
  const vh = cachedVh;
  const maxScroll = cachedMaxScroll;
  const y = window.scrollY;
  state.scrollNorm = Math.max(0, Math.min(1, y / maxScroll));

  const stops = cachedStops;
  let sp = 0;
  if (y <= stops[0]) {
    sp = 0;
  } else if (y >= stops[stops.length - 1]) {
    sp = stops.length - 1;
  } else {
    for (let i = 0; i < stops.length - 1; i++) {
      if (y >= stops[i] && y <= stops[i + 1]) {
        const span = Math.max(1, stops[i + 1] - stops[i]);
        sp = i + plateauBlend((y - stops[i]) / span);
        break;
      }
    }
  }
  state.sceneProgress = sp;

  if (timecodeFill) {
    timecodeFill.style.transform = `scaleY(${Math.max(0.05, state.scrollNorm).toFixed(4)})`;
  }

  const reduced = isReducedMotion();
  let closestIdx = 0;
  let closestDist = Infinity;

  kineticBlocks.forEach(({ copy }, idx) => {
    const secCenterViewport = (cachedCenters[idx] ?? vh * 0.5) - y;
    const normOffset = (secCenterViewport - vh * 0.5) / (vh * 0.78);
    const absOff = Math.abs(normOffset);

    if (absOff < closestDist) {
      closestDist = absOff;
      closestIdx = idx;
    }

    if (copy) {
      if (reduced) {
        copy.style.opacity = '1';
        copy.style.transform = 'none';
      } else {
        const fadeDist = Math.max(0, (absOff - 0.42) / 0.68);
        const alpha = Math.max(0, Math.min(1, 1 - Math.pow(fadeDist, 1.45)));
        const scale = 1 - Math.min(0.032, fadeDist * 0.032);
        const driftY = absOff <= 0.42
          ? normOffset * -6
          : Math.sign(normOffset) * (-2.52 - (absOff - 0.42) * 24);
        copy.style.opacity = alpha.toFixed(3);
        copy.style.transform = `translate3d(0, ${driftY.toFixed(1)}px, 0) scale(${scale.toFixed(4)})`;
      }
    }
  });

  if (closestIdx !== state.activeScene) {
    state.activeScene = closestIdx;
    if (timecodeIndex) {
      timecodeIndex.textContent = String(closestIdx).padStart(2, '0');
    }
    timecodeDotEls.forEach((d, i) => {
      const isActive = i === closestIdx;
      d.classList.toggle('active', isActive);
      if (isActive) d.setAttribute('aria-current', 'step');
      else d.removeAttribute('aria-current');
    });
    syncStageMorphLabel();
    syncRailDroplet();
  }
}

refreshLayoutMetrics();
window.addEventListener('scroll', updateScrollAndKineticDOM, { passive: true });
window.addEventListener('resize', () => {
  refreshLayoutMetrics();
  updateScrollAndKineticDOM();
  syncForgeIndicator();
  syncRailDroplet();
});
window.addEventListener('load', () => {
  refreshLayoutMetrics();
  updateScrollAndKineticDOM();
  syncForgeIndicator();
  syncRailDroplet();
});
updateScrollAndKineticDOM();
requestAnimationFrame(() => {
  syncForgeIndicator();
  syncRailDroplet();
});

/* --------------------------------------------------------------------------
   7. Six-Stage Mathematical 3D Point-Cloud Sculptures (11-Plugin Astrolabe)
   -------------------------------------------------------------------------- */
function generateSixMorphForms(count) {
  const form0 = new Float32Array(count * 3);
  const form1 = new Float32Array(count * 3);
  const form2 = new Float32Array(count * 3);
  const form3 = new Float32Array(count * 3);
  const form4 = new Float32Array(count * 3);
  const form5 = new Float32Array(count * 3);
  const seeds = new Float32Array(count * 4);

  const pluginCount = PLUGINS.length; // 11 official plugins
  const goldenAngle = Math.PI * (3 - Math.sqrt(5));
  const dagLinks = [
    [0, 2], [1, 2], [0, 3], [1, 5],
    [2, 3], [2, 5], [3, 4], [5, 4],
    [3, 6], [4, 6], [5, 6]
  ];

  for (let i = 0; i < count; i++) {
    const i3 = i * 3;
    const i4 = i * 4;
    const u = i / count;
    const rnd1 = Math.sin(i * 12.9898) * 43758.5453;
    const rA = rnd1 - Math.floor(rnd1);
    const rnd2 = Math.sin(i * 78.233 + 1.7) * 29432.123;
    const rB = rnd2 - Math.floor(rnd2);
    const rnd3 = Math.sin(i * 39.425 + 4.1) * 19283.711;
    const rC = rnd3 - Math.floor(rnd3);

    const clusterIdx = i % pluginCount;
    seeds[i4] = rA * Math.PI * 2;
    seeds[i4 + 1] = clusterIdx;
    seeds[i4 + 2] = u;
    seeds[i4 + 3] = rB;

    /* FORM 0: Caustic Horizontal Water-Ripple Mirror + Suspended Droplet Mist */
    if (i < count * 0.68) {
      const discR = 1.45 + Math.pow(rB, 0.72) * 5.2;
      const ang = rA * Math.PI * 2;
      form0[i3] = Math.cos(ang) * discR;
      form0[i3 + 1] = Math.sin(discR * 3.4) * 0.16 - 0.95;
      form0[i3 + 2] = Math.sin(ang) * discR * 0.85;
    } else {
      const rad = 1.68 + rC * 1.82;
      const y = 1 - ((i - count * 0.68) / (count * 0.32)) * 2;
      const ry = Math.sqrt(Math.max(0, 1 - y * y));
      const th = goldenAngle * i;
      form0[i3] = Math.cos(th) * ry * rad;
      form0[i3 + 1] = y * rad;
      form0[i3 + 2] = Math.sin(th) * ry * rad;
    }

    /* FORM 1: 4 Parallel Z-Explodable 880:544 Superellipse Glass Sheets */
    const layerIdx = i % 4;
    const zBase = (layerIdx - 1.5) * 0.68;
    const aW = 3.28, aH = 2.03;
    if (rB < 0.56) {
      const ang1 = rA * Math.PI * 2;
      const c1 = Math.cos(ang1), s1 = Math.sin(ang1);
      const band = 0.86 + (layerIdx * 0.045);
      form1[i3] = Math.sign(c1) * Math.pow(Math.abs(c1), 0.42) * aW * band;
      form1[i3 + 1] = Math.sign(s1) * Math.pow(Math.abs(s1), 0.42) * aH * band;
      form1[i3 + 2] = zBase;
    } else {
      form1[i3] = (rA * 2 - 1) * (aW * 0.82);
      form1[i3 + 1] = (rC * 2 - 1) * (aH * 0.82);
      form1[i3 + 2] = zBase;
    }

    /* FORM 2: 11-Fold Orbital Corona + Double-Helix Host Bridges */
    const cAngle = (clusterIdx / pluginCount) * Math.PI * 2;
    const orbitR = 3.42;
    const cx = Math.cos(cAngle) * orbitR;
    const cy = Math.sin(cAngle) * orbitR * 0.86;
    const cz = Math.sin(cAngle * 2.0) * 0.70;

    if (rB < 0.52) {
      const localR = 0.22 + Math.pow(rC, 0.6) * 0.42;
      const th = rA * Math.PI * 2;
      const ph = ((u * 211.7) % 1) * Math.PI;
      form2[i3] = cx + Math.sin(ph) * Math.cos(th) * localR;
      form2[i3 + 1] = cy + Math.sin(ph) * Math.sin(th) * localR;
      form2[i3 + 2] = cz + Math.cos(ph) * localR;
    } else {
      const s = 0.50 + rC * 0.48;
      const uHelix = (s - 0.50) / 0.48;
      const strand = (i % 2 === 0 ? 1 : -1);
      const helixA = uHelix * Math.PI * 3.5 + cAngle;
      const perpR = Math.sin(uHelix * Math.PI) * 0.19;
      form2[i3] = cx * s + Math.cos(helixA) * perpR * strand;
      form2[i3 + 1] = cy * s + Math.sin(helixA) * perpR * strand;
      form2[i3 + 2] = cz * s + Math.sin(uHelix * Math.PI) * 0.28;
    }

    /* FORM 3: Tilted 5-Arm Titanium Accretion Funnel */
    const arm = i % 5;
    const vProg = Math.pow(rB, 0.68);
    const vRad = 1.56 + vProg * 3.55;
    const vAng = (arm / 5) * Math.PI * 2 + vProg * 6.4 + (rA - 0.5) * 0.36;
    const funnelDepth = -Math.pow(1 - vProg, 2.2) * 1.45 * (i % 2 === 0 ? 1 : -1);
    const rawX = Math.cos(vAng) * vRad;
    const rawY = funnelDepth + (rC - 0.5) * 0.22;
    const rawZ = Math.sin(vAng) * vRad;
    const tilt = 0.92;
    form3[i3] = rawX;
    form3[i3 + 1] = rawY * Math.cos(tilt) - rawZ * Math.sin(tilt);
    form3[i3 + 2] = rawY * Math.sin(tilt) + rawZ * Math.cos(tilt);

    /* FORM 4: 4-Tier Acyclic Crystal Lattice Framing Central Diamond */
    if (rB < 0.44) {
      const node = DAG_NODES[i % DAG_NODES.length].pos;
      const nr = 0.18 + Math.pow(rC, 0.55) * 0.34;
      const na = rA * Math.PI * 2;
      const nb = ((i * 1.618) % 1) * Math.PI;
      form4[i3] = node[0] + Math.sin(nb) * Math.cos(na) * nr;
      form4[i3 + 1] = node[1] + Math.cos(nb) * nr;
      form4[i3 + 2] = node[2] + Math.sin(nb) * Math.sin(na) * nr;
    } else {
      const edge = dagLinks[i % dagLinks.length];
      const pA = DAG_NODES[edge[0]].pos;
      const pB = DAG_NODES[edge[1]].pos;
      const t = rC;
      const arcZ = Math.sin(t * Math.PI) * 0.28;
      const spread = (rA - 0.5) * 0.08;
      form4[i3] = pA[0] + (pB[0] - pA[0]) * t + spread;
      form4[i3 + 1] = pA[1] + (pB[1] - pA[1]) * t;
      form4[i3 + 2] = pA[2] + (pB[2] - pA[2]) * t + arcZ + spread;
    }

    /* FORM 5: Finale Ice-Silver Eclipse Corona Ring & Rising Motes */
    const ringR = 2.35 + Math.pow(rB, 1.8) * 3.6;
    const ringA = rA * Math.PI * 2;
    form5[i3] = Math.cos(ringA) * ringR;
    form5[i3 + 1] = Math.sin(ringA) * ringR * 0.88;
    form5[i3 + 2] = (rC - 0.5) * (0.4 + (ringR - 2.35) * 0.8);
  }

  return { form0, form1, form2, form3, form4, form5, seeds };
}

/* --------------------------------------------------------------------------
   8. Fast Multi-Mirror Three.js Loader & Stage Positioning
   -------------------------------------------------------------------------- */
function loadUmdScript(url) {
  return new Promise((resolve, reject) => {
    if (window.THREE && window.THREE.WebGLRenderer) {
      resolve(window.THREE);
      return;
    }
    const s = document.createElement('script');
    s.async = true;
    s.src = url;
    s.onload = () => {
      if (window.THREE && window.THREE.WebGLRenderer) resolve(window.THREE);
      else reject(new Error('No THREE'));
    };
    s.onerror = () => reject(new Error('Load error'));
    document.head.appendChild(s);
  });
}

async function resolveRealThree() {
  if (window.THREE && window.THREE.WebGLRenderer) return window.THREE;

  const candidates = [
    ...UMD_CANDIDATES.map((u) => loadUmdScript(u)),
    ...ESM_CANDIDATES.map((u) => import(u).then((m) => {
      if (m && m.WebGLRenderer) return m;
      throw new Error('Bad ESM');
    }))
  ];

  return new Promise((resolve) => {
    let left = candidates.length;
    let done = false;
    const finish = (v) => { if (!done) { done = true; resolve(v); } };
    const timer = setTimeout(() => finish(null), CDN_RACE_TIMEOUT_MS);
    candidates.forEach((p) => {
      p.then((lib) => { clearTimeout(timer); finish(lib); })
        .catch(() => {
          left -= 1;
          if (left <= 0) { clearTimeout(timer); finish(null); }
        });
    });
  });
}

function getTargetSculptureOffsetX() {
  if (window.innerWidth <= 900) return 0;
  const xMag = window.innerWidth <= 1120 ? 2.12 : 2.48;
  const anchors = [0.0, xMag, -xMag, xMag, -xMag, 0.0];
  const scaled = Math.max(0, Math.min(5, state.sceneProgress));
  const i0 = Math.floor(scaled);
  const i1 = Math.min(5, i0 + 1);
  const f = scaled - i0;
  return anchors[i0] + (anchors[i1] - anchors[i0]) * f;
}

function getTargetSculptureOffsetY() {
  const isNarrow = window.innerWidth <= 900;
  const anchors = isNarrow
    ? [1.18, 1.15, 1.15, 1.15, 1.15, 1.24]
    : [1.12, 0.04, 0.04, 0.04, 0.04, 1.24];
  const scaled = Math.max(0, Math.min(5, state.sceneProgress));
  const i0 = Math.floor(scaled);
  const i1 = Math.min(5, i0 + 1);
  const f = scaled - i0;
  return anchors[i0] + (anchors[i1] - anchors[i0]) * f;
}

function getMorphStage() {
  return Math.max(0, Math.min(5.0, state.sceneProgress));
}

/* ==========================================================================
   9A. Primary WebGL2 Optical Crystal Engine (Smooth themeBlend, Zero Neon Pink)
   ========================================================================== */
function mountWebGLShaderFilm(container, THREE) {
  const renderer = new THREE.WebGLRenderer({
    antialias: true,
    powerPreference: 'high-performance',
    alpha: false
  });
  renderer.setPixelRatio(Math.min(window.devicePixelRatio || 1, 2));
  renderer.setSize(window.innerWidth, window.innerHeight);
  container.appendChild(renderer.domElement);

  const scene = new THREE.Scene();
  const camera = new THREE.PerspectiveCamera(40, window.innerWidth / window.innerHeight, 0.1, 120);
  camera.position.set(0, 0, 10.8);

  /* Continuous Theme Interpolation State (0.0 = Obsidian Dark, 1.0 = Light Frost) */
  let targetThemeBlend = state.theme === 'pure-frost' ? 1.0 : 0.0;
  let themeBlend = targetThemeBlend;

  const darkBgColor = new THREE.Color(0x0b0c0f);
  const lightBgColor = new THREE.Color(0xf5f5f7);
  const liveBgColor = darkBgColor.clone().lerp(lightBgColor, themeBlend);
  scene.background = liveBgColor;

  const hemiDarkSky = new THREE.Color(0xdbeafe);
  const hemiLightSky = new THREE.Color(0xffffff);
  const hemiDarkGround = new THREE.Color(0x11151d);
  const hemiLightGround = new THREE.Color(0xdce4f0);
  const rimDarkCol = new THREE.Color(0x64b5ff);
  const rimLightCol = new THREE.Color(0x2997ff);
  const trailDarkCol = new THREE.Color(0x64b5ff);
  const trailLightCol = new THREE.Color(0x0071e3);

  /* Studio Three-Point Lighting Rig */
  const hemiLight = new THREE.HemisphereLight(0xdbeafe, 0x11151d, 1.5);
  scene.add(hemiLight);

  const keyLight = new THREE.DirectionalLight(0xffffff, 2.7);
  keyLight.position.set(4.8, 7.2, 6.4);
  scene.add(keyLight);

  const rimLight = new THREE.DirectionalLight(0x64b5ff, 1.35);
  rimLight.position.set(-5.6, -2.4, -4.2);
  scene.add(rimLight);

  const rootGroup = new THREE.Group();
  scene.add(rootGroup);

  /* Premultiplied Alpha Blending Config (Enables 100% continuous Dark <-> Light transitions with ZERO pop!) */
  const premultipliedBlend = {
    transparent: true,
    depthWrite: false,
    blending: THREE.CustomBlending,
    blendEquation: THREE.AddEquation,
    blendSrc: THREE.OneFactor,
    blendDst: THREE.OneMinusSrcAlphaFactor
  };

  /* 1. World-Space Decoupled Atmospheric Halation Plane */
  const haloUniforms = {
    uTime: { value: 0 },
    uMorph: { value: 0 },
    uLightMode: { value: themeBlend },
    uPulse: { value: 0 }
  };
  const haloMat = new THREE.ShaderMaterial({
    uniforms: haloUniforms,
    depthTest: false,
    ...premultipliedBlend,
    vertexShader: `
      varying vec2 vUv;
      void main() {
        vUv = uv;
        gl_Position = projectionMatrix * modelViewMatrix * vec4(position, 1.0);
      }
    `,
    fragmentShader: `
      uniform float uMorph;
      uniform float uLightMode;
      uniform float uPulse;
      varying vec2 vUv;

      // Industrial 6-Act Palette (Zero Neon Pink/Purple)
      vec3 stageTint(float m) {
        vec3 c0 = vec3(0.161, 0.592, 1.000); // 00 Apple Ice Blue #2997FF
        vec3 c1 = vec3(0.000, 0.443, 0.890); // 01 Apple Sky Blue #0071E3
        vec3 c2 = vec3(0.369, 0.486, 0.886); // 02 Titanium Indigo #5E7CE2
        vec3 c3 = vec3(0.851, 0.608, 0.263); // 03 Warm Titanium Gold #D99B43
        vec3 c4 = vec3(0.188, 0.820, 0.345); // 04 Emerald Green #30D158
        vec3 c5 = vec3(0.580, 0.722, 0.910); // 05 Ice Silver Corona #94B8E8
        if (m < 1.0) return mix(c0, c1, m);
        if (m < 2.0) return mix(c1, c2, m - 1.0);
        if (m < 3.0) return mix(c2, c3, m - 2.0);
        if (m < 4.0) return mix(c3, c4, m - 3.0);
        return mix(c4, c5, clamp(m - 4.0, 0.0, 1.0));
      }

      void main() {
        vec2 w = (vUv - 0.5) * 2.0;
        float rNorm = length(w);
        if (rNorm >= 0.96) discard;

        float rWorld = rNorm * (10.0 / 5.1);
        float glowA = exp(-rWorld * rWorld * 3.8);
        float glowB = exp(-rWorld * rWorld * 1.45) * 0.34;
        float radialWindow = smoothstep(0.96, 0.28, rNorm);
        radialWindow *= radialWindow;

        vec3 tint = stageTint(uMorph);
        vec3 col = mix(tint, mix(tint, vec3(0.76, 0.87, 0.98), 0.42), uLightMode);
        float rawAlpha = (glowA * 0.28 + glowB * 0.18) * radialWindow
                       * (1.0 + uPulse * 0.65) * mix(1.0, 0.26, uLightMode);
        float ditherMask = smoothstep(0.0, 0.012, rawAlpha);
        float dither = (fract(sin(dot(gl_FragCoord.xy, vec2(12.9898, 78.233))) * 43758.5453) - 0.5)
                     * 0.004 * ditherMask;
        float a = max(0.0, rawAlpha + dither);
        if (a <= 0.00012) discard;

        // Premultiplied continuous additive (dark) -> normal (light)
        float outA = mix(a * 0.12, a, uLightMode);
        gl_FragColor = vec4(col * a, outA);
      }
    `
  });
  const haloMesh = new THREE.Mesh(new THREE.PlaneGeometry(20.0, 20.0), haloMat);
  haloMesh.position.set(0, 1.12, -2.4);
  haloMesh.renderOrder = -10;
  scene.add(haloMesh);

  /* 2. Six-Surface Optical Crystal Core Shader (Alabaster Frost <-> Titanium Obsidian) */
  const coreNormalMat = new THREE.Matrix3();
  const coreUniforms = {
    uTime: { value: 0 },
    uMorph: { value: 0 },
    uPulse: { value: 0 },
    uHoldCharge: { value: 0 },
    uForgePinch: { value: 0 },
    uLightMode: { value: themeBlend },
    uPointerLocal: { value: new THREE.Vector3(0, 0, 2) },
    uCoreNormalMat: { value: coreNormalMat }
  };

  const coreGeo = new THREE.IcosahedronGeometry(1.0, 48);
  const coreMat = new THREE.ShaderMaterial({
    uniforms: coreUniforms,
    transparent: true,
    vertexShader: `
      uniform float uTime;
      uniform float uMorph;
      uniform float uPulse;
      uniform float uHoldCharge;
      uniform float uForgePinch;
      uniform vec3 uPointerLocal;

      varying vec3 vWorldPos;
      varying vec3 vLocalPos;
      varying vec3 vSmoothNormal;
      varying float vDisp;
      varying float vCavity;

      vec3 evalCoreSurface(vec3 d, float m, float t, out float outCavity) {
        // S0: Breathing Optical Liquid Droplet
        float w0 = sin(d.x * 3.2 + t * 1.25) * cos(d.y * 3.2 - t * 0.95) * 0.11
                 + sin(d.z * 4.0 + t * 0.85) * 0.06;
        vec3 s0 = d * (1.28 + w0);
        float c0 = clamp(0.72 + w0 * 1.8, 0.36, 1.0);

        // S1: 880 : 544 Superellipse Optical Glass Tablet
        vec3 q1 = abs(d) / vec3(2.06, 1.27, 0.24);
        float denom1 = pow(pow(q1.x, 5.0) + pow(q1.y, 5.0) + pow(q1.z, 5.0), 0.2);
        vec3 s1 = d / max(denom1, 1e-4);
        s1.z += sin(s1.x * 2.2 + t * 1.4) * 0.030;
        float c1 = clamp(0.76 + 0.24 * abs(d.z), 0.58, 1.0);

        // S2: Sculpted 8-Petal Astrolabe Star-Crown
        float angXY = atan(d.y, d.x);
        float petalWave = cos(angXY * 8.0 - t * 0.75);
        float petal = 1.24 + 0.36 * petalWave;
        vec3 s2 = vec3(d.xy * petal, d.z * (0.46 + 0.14 * petalWave));
        float c2 = clamp(0.54 + 0.46 * petalWave, 0.16, 1.0);

        // S3: Twisted Tri-Lobe Spiral Helicoid Forge
        float twist = d.y * 4.2 - t * 2.0;
        float angXZ = atan(d.z, d.x);
        float lobeWave = sin(angXZ * 3.0 + twist);
        float lobe = 1.02 + 0.38 * lobeWave;
        vec3 s3 = vec3(d.x * lobe, d.y * 1.56, d.z * lobe);
        float c3 = clamp(0.52 + 0.48 * lobeWave, 0.14, 1.0);

        // S4: Micro-Chamfered Octahedral Diamond Spire
        vec3 ad4 = sqrt(d * d + vec3(0.00042));
        float octNorm = ad4.x / 0.84 + ad4.y / 1.30 + ad4.z / 0.84;
        vec3 s4 = d / max(octNorm, 1e-4);
        float minAxis = min(min(abs(s4.x), abs(s4.y) * 0.64), abs(s4.z));
        float c4 = clamp(1.0 - smoothstep(0.0, 0.38, minAxis) * 0.18, 0.78, 1.0);

        // S5: Serene Ice-Silver Eclipse Corona Disc
        float corWave = sin(angXY * 12.0 + t * 1.15);
        float ringWave = 1.66 + 0.09 * corWave;
        vec3 s5 = vec3(d.xy * ringWave, d.z * 0.28);
        float c5 = clamp(0.68 + 0.32 * corWave, 0.38, 1.0);

        vec3 p;
        if (m < 1.0) {
          float k = smoothstep(0.0, 1.0, m);
          p = mix(s0, s1, k);
          outCavity = mix(c0, c1, k);
        } else if (m < 2.0) {
          float k = smoothstep(1.0, 2.0, m);
          p = mix(s1, s2, k);
          outCavity = mix(c1, c2, k);
        } else if (m < 3.0) {
          float k = smoothstep(2.0, 3.0, m);
          p = mix(s2, s3, k);
          outCavity = mix(c2, c3, k);
        } else if (m < 4.0) {
          float k = smoothstep(3.0, 4.0, m);
          p = mix(s3, s4, k);
          outCavity = mix(c3, c4, k);
        } else {
          float k = smoothstep(4.0, 5.0, m);
          p = mix(s4, s5, k);
          outCavity = mix(c4, c5, k);
        }

        float ptrDist = length(p - uPointerLocal);
        float ptrWave = sin(ptrDist * 5.5 - t * 4.8) * exp(-ptrDist * 1.1) * 0.075;
        vec3 pullVec = (uPointerLocal - p) * exp(-ptrDist * 0.55) * uHoldCharge * 0.24;
        float pulseBurst = uPulse * 0.17 * sin(d.y * 8.0 + t * 8.5);

        p = p * (1.0 - uForgePinch * 0.38) + d * (ptrWave + pulseBurst) + pullVec;
        return p;
      }

      void buildTangentBasis(vec3 n, out vec3 b1, out vec3 b2) {
        float s = n.z >= 0.0 ? 1.0 : -1.0;
        float a = -1.0 / (s + n.z);
        float b = n.x * n.y * a;
        b1 = vec3(1.0 + s * n.x * n.x * a, s * b, -s * n.x);
        b2 = vec3(b, s + n.y * n.y * a, -n.y);
      }

      void main() {
        vec3 dir = normalize(position);
        float cavCenter = 1.0;
        vec3 pos = evalCoreSurface(dir, uMorph, uTime, cavCenter);
        vLocalPos = pos;
        vCavity = cavCenter;
        vDisp = length(pos) - 1.25;

        float eps = 0.016;
        vec3 tA, tB;
        buildTangentBasis(dir, tA, tB);
        float dummyC;
        vec3 pPlusA = evalCoreSurface(normalize(dir + tA * eps), uMorph, uTime, dummyC);
        vec3 pMinusA = evalCoreSurface(normalize(dir - tA * eps), uMorph, uTime, dummyC);
        vec3 pPlusB = evalCoreSurface(normalize(dir + tB * eps), uMorph, uTime, dummyC);
        vec3 pMinusB = evalCoreSurface(normalize(dir - tB * eps), uMorph, uTime, dummyC);
        vec3 surfN = normalize(cross(pPlusA - pMinusA, pPlusB - pMinusB) + dir * 1e-6);

        vec4 wp = modelMatrix * vec4(pos, 1.0);
        vWorldPos = wp.xyz;
        vSmoothNormal = normalize(mat3(modelMatrix) * surfN);
        gl_Position = projectionMatrix * viewMatrix * wp;
      }
    `,
    fragmentShader: `
      uniform float uTime;
      uniform float uMorph;
      uniform float uPulse;
      uniform float uHoldCharge;
      uniform float uLightMode;
      uniform mat3 uCoreNormalMat;

      varying vec3 vWorldPos;
      varying vec3 vLocalPos;
      varying vec3 vSmoothNormal;
      varying float vDisp;
      varying float vCavity;

      vec3 softSign(vec3 v, float sharpness) {
        float inv2 = 1.0 / (sharpness * sharpness);
        return v * inversesqrt(v * v + vec3(inv2));
      }

      // Industrial 6-Act Accent Progression (Zero Neon Pink / Purple)
      vec3 stageAccent(float m) {
        vec3 a0 = vec3(0.161, 0.592, 1.000); // 00 Apple Ice Blue #2997FF
        vec3 a1 = vec3(0.000, 0.443, 0.890); // 01 Apple Sky Blue #0071E3
        vec3 a2 = vec3(0.369, 0.486, 0.886); // 02 Titanium Indigo #5E7CE2
        vec3 a3 = vec3(0.851, 0.608, 0.263); // 03 Warm Titanium Gold #D99B43
        vec3 a4 = vec3(0.188, 0.820, 0.345); // 04 Emerald Green #30D158
        vec3 a5 = vec3(0.580, 0.722, 0.910); // 05 Ice Silver Corona #94B8E8
        if (m < 1.0) return mix(a0, a1, m);
        if (m < 2.0) return mix(a1, a2, m - 1.0);
        if (m < 3.0) return mix(a2, a3, m - 2.0);
        if (m < 4.0) return mix(a3, a4, m - 3.0);
        return mix(a4, a5, clamp(m - 4.0, 0.0, 1.0));
      }

      vec3 stageSecondary(float m) {
        vec3 b0 = vec3(0.863, 0.902, 0.961); // Silver White
        vec3 b1 = vec3(0.722, 0.831, 0.961); // Ice Silver
        vec3 b2 = vec3(0.392, 0.710, 1.000); // Ice Blue
        vec3 b3 = vec3(0.769, 0.808, 0.863); // Cool Silver
        vec3 b4 = vec3(0.165, 0.663, 0.878); // Deep Sea Cyan #2AA9E0
        vec3 b5 = vec3(0.114, 0.337, 0.722); // Deep Space Blue
        if (m < 1.0) return mix(b0, b1, m);
        if (m < 2.0) return mix(b1, b2, m - 1.0);
        if (m < 3.0) return mix(b2, b3, m - 2.0);
        if (m < 4.0) return mix(b3, b4, m - 3.0);
        return mix(b4, b5, clamp(m - 4.0, 0.0, 1.0));
      }

      // Studio 360-Degree Softbox Environment (Porcelain White Softboxes <-> Deep Titanium Studio)
      vec3 studioEnv(vec3 dir, float lightMode, vec3 accent, vec3 secondary) {
        float up = clamp(dir.y * 0.5 + 0.5, 0.0, 1.0);
        float frontSoftA = smoothstep(0.74, 0.992, dot(dir, normalize(vec3(0.48, 0.72, 0.64))));
        float frontSoftB = smoothstep(0.70, 0.98, dot(dir, normalize(vec3(-0.62, -0.18, 0.56))));
        float rearTransA = smoothstep(0.35, 0.94, dot(dir, normalize(vec3(-0.28, -0.32, -0.90))));
        float rearTransB = smoothstep(0.42, 0.95, dot(dir, normalize(vec3(0.45, 0.48, -0.75))));

        // Obsidian Dark Studio: Pure Neutral Graphite + Cool Silver & Industrial Accent
        vec3 darkEnv = mix(vec3(0.042, 0.048, 0.062), vec3(0.105, 0.132, 0.185), up);
        darkEnv += accent * (rearTransA * 0.44 + rearTransB * 0.28);
        darkEnv += secondary * frontSoftB * 0.26;
        darkEnv += vec3(0.96, 0.98, 1.0) * frontSoftA * 1.08;

        // Light Frost Studio: Pure Porcelain Alabaster Softboxes + Crisp Ice-Blue Dispersion
        vec3 lightEnv = mix(vec3(0.86, 0.89, 0.94), vec3(0.99, 0.995, 1.0), up);
        lightEnv += mix(vec3(0.52, 0.78, 1.0), accent, 0.45) * (rearTransA * 0.22 + frontSoftB * 0.14);
        lightEnv += vec3(1.0) * frontSoftA * 0.55;

        return mix(darkEnv, lightEnv, lightMode);
      }

      void main() {
        float s4Weight = smoothstep(0.12, 0.88, 1.0 - clamp(abs(uMorph - 4.0), 0.0, 1.0));
        vec3 smoothN = normalize(vSmoothNormal);
        vec3 octLocalN = normalize(softSign(vLocalPos, 36.0) / vec3(0.84, 1.30, 0.84));
        vec3 octWorldN = normalize(uCoreNormalMat * octLocalN);
        vec3 N = normalize(mix(smoothN, octWorldN, s4Weight * 0.92));

        vec3 V = normalize(cameraPosition - vWorldPos);
        if (dot(N, V) < -0.25) N = normalize(mix(N, V, 0.35));

        vec3 accent = stageAccent(uMorph);
        vec3 secondary = stageSecondary(uMorph);
        float ao = mix(0.42, 1.0, clamp(vCavity, 0.0, 1.0));

        vec3 keyL = normalize(vec3(0.48, 0.72, 0.64));
        vec3 fillL = normalize(vec3(-0.62, -0.22, 0.52));
        float ndl = dot(N, keyL);
        float keyWrap = clamp((ndl + 0.38) / 1.38, 0.0, 1.0);
        float fillWrap = clamp((dot(N, fillL) + 0.30) / 1.30, 0.0, 1.0);

        float s0Weight = clamp(1.0 - uMorph, 0.0, 1.0);
        float waterBounce = s0Weight * clamp(-N.y * 0.85 + 0.15, 0.0, 1.0);
        float s5Weight = clamp(uMorph - 4.0, 0.0, 1.0);

        // Optical Chromatic Dispersion (Clean Ice-Blue / Silver Separation)
        vec3 rDir = refract(-V, N, 1.0 / 1.36);
        vec3 gDir = refract(-V, N, 1.0 / 1.44);
        vec3 bDir = refract(-V, N, 1.0 / 1.53);
        vec3 refracted = vec3(
          studioEnv(rDir, uLightMode, accent, secondary).r,
          studioEnv(gDir, uLightMode, accent, secondary).g,
          studioEnv(bDir, uLightMode, accent, secondary).b
        );

        float ndv = clamp(dot(N, V), 0.0, 1.0);
        float fresnel = pow(1.0 - ndv, 2.85);
        vec3 reflDir = reflect(-V, N);
        vec3 reflected = studioEnv(reflDir, uLightMode, accent, secondary);

        // Subtle Cool-Silver & Ice-Blue Optical Sheen (Zero Magenta/Neon)
        vec3 coolSheen = mix(secondary, accent, 0.5 + 0.5 * sin(ndv * 5.2 + vDisp * 4.5 + uTime * 0.45));

        // Crisp Studio Clearcoat Specular
        vec3 halfV = normalize(keyL + V);
        float specMask = smoothstep(-0.10, 0.36, ndl) * ao;
        float softSheen = pow(max(dot(N, halfV), 0.0), 24.0) * 0.28 * specMask;
        float coatSpec = pow(max(dot(N, halfV), 0.0), 124.0) * 1.28 * specMask;

        // DARK MODE: Deep Space Titanium Obsidian Optical Glass
        vec3 darkShadow = mix(vec3(0.035, 0.042, 0.056), accent * 0.14, 0.30 + fillWrap * 0.28);
        vec3 darkLit = mix(refracted, accent * 0.42 + vec3(0.14, 0.17, 0.22), 0.34);
        vec3 darkBody = mix(darkShadow, darkLit, keyWrap) * ao;
        darkBody += accent * waterBounce * 0.22 * ao;
        darkBody *= mix(1.0, mix(0.28, 1.0, fresnel), s5Weight * 0.72);

        float rimDirGate = mix(mix(0.34, 1.0, keyWrap) * ao, 0.94, s5Weight * 0.75);
        vec3 darkRim = mix(coolSheen, vec3(0.86, 0.92, 1.0), 0.36) * fresnel * rimDirGate
                     * (1.02 + uPulse * 1.05 + uHoldCharge * 0.85 + s5Weight * 0.42);
        vec3 darkFinal = mix(darkBody, reflected * ao, fresnel * 0.48)
                       + darkRim
                       + mix(accent, vec3(0.86, 0.93, 1.0), 0.45) * softSheen
                       + vec3(coatSpec);

        // LIGHT MODE: High-Clarity Porcelain Alabaster Optical Crystal (Zero Muddy Dark)
        vec3 frostLit = mix(refracted, vec3(0.985, 0.992, 1.0), 0.56);
        vec3 frostIceCore = mix(vec3(0.82, 0.88, 0.96), mix(vec3(0.55, 0.80, 1.0), accent, 0.42), 0.32);
        vec3 frostBody = mix(frostIceCore, frostLit, 0.32 + 0.68 * keyWrap) * mix(0.84, 1.0, ao);
        vec3 frostEdgeRefract = mix(vec3(0.68, 0.78, 0.91), mix(accent, vec3(0.16, 0.59, 1.0), 0.45), 0.48);
        vec3 frostFinal = mix(frostBody, frostEdgeRefract, fresnel * 0.44);
        frostFinal += mix(vec3(0.16, 0.59, 1.0), accent, 0.5) * fresnel * (0.18 + uPulse * 0.38);
        frostFinal += vec3(0.96, 0.98, 1.0) * (coatSpec * 0.92 + softSheen * 0.52);

        vec3 finalCol = mix(darkFinal, frostFinal, uLightMode);
        float finalAlpha = mix(0.94, 0.92, uLightMode);
        gl_FragColor = vec4(finalCol, finalAlpha);
      }
    `
  });

  const coreMesh = new THREE.Mesh(coreGeo, coreMat);
  coreMesh.renderOrder = 1;
  rootGroup.add(coreMesh);

  /* 3. Stage-Specific Companion 3D Sculptures (11 Satellites, 3 Titanium Gyro Rings, 7 DAG Nodes) */
  const raycastTargets = [];

  const satGroup = new THREE.Group();
  satGroup.renderOrder = 2;
  rootGroup.add(satGroup);
  const satGeo = new THREE.OctahedronGeometry(0.21, 0);
  const satRecords = PLUGINS.map((p, i) => {
    const mat = new THREE.MeshPhysicalMaterial({
      color: p.color,
      emissive: p.color,
      emissiveIntensity: 0.16,
      roughness: 0.10,
      metalness: 0.22,
      clearcoat: 1.0,
      clearcoatRoughness: 0.06,
      transparent: true,
      opacity: 0
    });
    const mesh = new THREE.Mesh(satGeo, mat);
    mesh.renderOrder = 2;
    mesh.userData = { kind: 'plugin', plugin: p, index: i, hoverScale: 1 };
    satGroup.add(mesh);
    raycastTargets.push(mesh);
    return { mesh, mat, plugin: p, index: i };
  });

  // Stage 03: Warm Titanium Gold + Brushed Cool Silver + Titanium Indigo Gyro Rings
  const gyroGroup = new THREE.Group();
  gyroGroup.renderOrder = 2;
  rootGroup.add(gyroGroup);
  const gyroRings = [
    { r: 2.05, col: 0xd99b43 },
    { r: 2.55, col: 0xb8c4d4 },
    { r: 3.05, col: 0x5e7ce2 }
  ].map(({ r, col }, idx) => {
    const mat = new THREE.MeshStandardMaterial({
      color: col,
      emissive: col,
      emissiveIntensity: 0.20,
      roughness: 0.18,
      metalness: 0.80,
      transparent: true,
      opacity: 0
    });
    const mesh = new THREE.Mesh(new THREE.TorusGeometry(r, 0.023, 14, 108), mat);
    mesh.renderOrder = 2;
    mesh.rotation.set(idx * 0.7, idx * 0.5, 0);
    gyroGroup.add(mesh);
    return { mesh, mat };
  });

  // Stage 04: 7 Acyclic DAG Diamond Nodes
  const dagGroup = new THREE.Group();
  dagGroup.renderOrder = 2;
  rootGroup.add(dagGroup);
  const dagNodeGeo = new THREE.OctahedronGeometry(0.20, 0);
  const dagRecords = DAG_NODES.map((d, i) => {
    const mat = new THREE.MeshPhysicalMaterial({
      color: d.color,
      emissive: d.color,
      emissiveIntensity: 0.18,
      roughness: 0.10,
      metalness: 0.22,
      clearcoat: 1.0,
      clearcoatRoughness: 0.06,
      transparent: true,
      opacity: 0
    });
    const mesh = new THREE.Mesh(dagNodeGeo, mat);
    mesh.renderOrder = 2;
    mesh.position.set(d.pos[0], d.pos[1], d.pos[2]);
    mesh.userData = { kind: 'dag', dag: d, index: i, hoverScale: 1 };
    dagGroup.add(mesh);
    raycastTargets.push(mesh);
    return { mesh, mat, dag: d };
  });

  /* 4. 3D Luminous Cursor Ribbon Trail */
  const TRAIL_LEN = 56;
  const trailPoints = Array.from({ length: TRAIL_LEN }, () => new THREE.Vector3(0, 0, 0));
  const trailPosArr = new Float32Array(TRAIL_LEN * 3);
  const trailAlphaArr = new Float32Array(TRAIL_LEN);
  for (let i = 0; i < TRAIL_LEN; i++) trailAlphaArr[i] = 1.0 - i / TRAIL_LEN;

  const trailGeo = new THREE.BufferGeometry();
  trailGeo.setAttribute('position', new THREE.BufferAttribute(trailPosArr, 3));
  trailGeo.setAttribute('aAlpha', new THREE.BufferAttribute(trailAlphaArr, 1));
  const trailUniforms = {
    uOpacity: { value: 0 },
    uLightMode: { value: themeBlend },
    uColor: { value: trailDarkCol.clone().lerp(trailLightCol, themeBlend) }
  };
  const trailMat = new THREE.ShaderMaterial({
    uniforms: trailUniforms,
    ...premultipliedBlend,
    vertexShader: `
      attribute float aAlpha;
      varying float vA;
      void main() {
        vA = aAlpha;
        gl_Position = projectionMatrix * modelViewMatrix * vec4(position, 1.0);
      }
    `,
    fragmentShader: `
      uniform float uOpacity;
      uniform float uLightMode;
      uniform vec3 uColor;
      varying float vA;
      void main() {
        float a = pow(vA, 1.8) * uOpacity;
        float outA = mix(a * 0.16, a, uLightMode);
        gl_FragColor = vec4(uColor * a, outA);
      }
    `
  });
  const trailLine = new THREE.Line(trailGeo, trailMat);
  trailLine.renderOrder = 4;
  scene.add(trailLine);

  /* 5. 28,000-Particle Six-Stage GPU Morphing & Force-Field Cloud */
  const PARTICLE_COUNT = 28000;
  const forms = generateSixMorphForms(PARTICLE_COUNT);

  const pGeo = new THREE.BufferGeometry();
  pGeo.setAttribute('position', new THREE.BufferAttribute(forms.form0, 3));
  pGeo.setAttribute('aPos1', new THREE.BufferAttribute(forms.form1, 3));
  pGeo.setAttribute('aPos2', new THREE.BufferAttribute(forms.form2, 3));
  pGeo.setAttribute('aPos3', new THREE.BufferAttribute(forms.form3, 3));
  pGeo.setAttribute('aPos4', new THREE.BufferAttribute(forms.form4, 3));
  pGeo.setAttribute('aPos5', new THREE.BufferAttribute(forms.form5, 3));
  pGeo.setAttribute('aSeed', new THREE.BufferAttribute(forms.seeds, 4));

  const pluginMaskArray = new Float32Array(11);
  function updatePluginMaskUniform() {
    PLUGINS.forEach((p, i) => {
      pluginMaskArray[i] = state.enabledPlugins.has(p.id) ? 1.0 : 0.16;
    });
  }
  updatePluginMaskUniform();

  const pUniforms = {
    uTime: { value: 0 },
    uMorph: { value: 0 },
    uPixelRatio: { value: Math.min(window.devicePixelRatio || 1, 2) },
    uPointer: { value: new THREE.Vector3(99, 99, 0) },
    uPointerVel: { value: new THREE.Vector3(0, 0, 0) },
    uHoldCharge: { value: 0 },
    uLayerSpread: { value: 0 },
    uShockRadius: { value: 0 },
    uShockStrength: { value: 0 },
    uForgePinch: { value: 0 },
    uVortexPhase: { value: 0 },
    uLightMode: { value: themeBlend },
    uPluginMask: { value: pluginMaskArray }
  };

  const pMat = new THREE.ShaderMaterial({
    uniforms: pUniforms,
    ...premultipliedBlend,
    vertexShader: `
      attribute vec3 aPos1;
      attribute vec3 aPos2;
      attribute vec3 aPos3;
      attribute vec3 aPos4;
      attribute vec3 aPos5;
      attribute vec4 aSeed;

      uniform float uTime;
      uniform float uMorph;
      uniform float uPixelRatio;
      uniform vec3 uPointer;
      uniform vec3 uPointerVel;
      uniform float uHoldCharge;
      uniform float uLayerSpread;
      uniform float uShockRadius;
      uniform float uShockStrength;
      uniform float uForgePinch;
      uniform float uVortexPhase;
      uniform float uLightMode;
      uniform float uPluginMask[11];

      varying vec3 vColor;
      varying float vAlpha;

      float getMask(int idx) {
        for (int k = 0; k < 11; k++) {
          if (k == idx) return uPluginMask[k];
        }
        return 1.0;
      }

      void main() {
        float m = clamp(uMorph, 0.0, 5.0);

        // Stage 00 Dynamic Concentric Water Ripple
        vec3 p0 = position;
        float r0 = length(p0.xz);
        float waterContactShade = 1.0;
        float waterCausticRing = 0.0;
        if (p0.y < -0.5) {
          p0.y = -0.95 + sin(r0 * 3.2 - uTime * 2.2) * 0.15 * exp(-r0 * 0.18);
          float s0Vis = clamp(1.0 - m, 0.0, 1.0);
          waterContactShade = mix(1.0, 0.48 + 0.52 * smoothstep(0.35, 1.55, r0), s0Vis);
          waterCausticRing = exp(-pow(r0 - 1.52, 2.0) * 4.2) * 0.38 * s0Vis;
        }

        // Stage 01 Cursor-Driven 4-Layer Z-Explosion Fan-Out
        vec3 p1 = aPos1;
        p1.z *= (1.0 + uLayerSpread * 1.45);

        vec3 baseP;
        if (m < 1.0) baseP = mix(p0, p1, smoothstep(0.0, 1.0, m));
        else if (m < 2.0) baseP = mix(p1, aPos2, smoothstep(1.0, 2.0, m));
        else if (m < 3.0) baseP = mix(aPos2, aPos3, smoothstep(2.0, 3.0, m));
        else if (m < 4.0) baseP = mix(aPos3, aPos4, smoothstep(3.0, 4.0, m));
        else baseP = mix(aPos4, aPos5, smoothstep(4.0, 5.0, m));

        // Stage 02 11-Plugin Corona Mask
        float coronaWeight = 1.0 - clamp(abs(m - 2.0), 0.0, 1.0);
        int cIdx = int(floor(aSeed.y + 0.5));
        float pMask = getMask(cIdx);
        if (coronaWeight > 0.01) {
          baseP *= mix(1.0, mix(1.40, 1.0, pMask), coronaWeight);
        }

        // Stage 03 Monotonic Accretion Spin & Forge Pinch
        float vortexWeight = smoothstep(0.0, 1.0, 1.0 - clamp(abs(m - 3.0), 0.0, 1.0));
        float vortexBlend = clamp(vortexWeight + uForgePinch * 0.85, 0.0, 1.0);
        if (vortexBlend > 0.002) {
          float spin = uVortexPhase * (0.42 + (1.0 - aSeed.w) * 0.58);
          float cs = cos(spin), sn = sin(spin);
          vec3 spunP = baseP;
          spunP.xz = mat2(cs, -sn, sn, cs) * baseP.xz;
          baseP = mix(baseP, spunP, vortexBlend);
          baseP *= (1.0 - uForgePinch * 0.56);
        }

        // Gentle Curl Breathing
        baseP += vec3(
          sin(baseP.y * 1.5 + uTime * 0.75 + aSeed.x),
          cos(baseP.z * 1.5 - uTime * 0.65 + aSeed.x),
          sin(baseP.x * 1.5 + uTime * 0.55 + aSeed.x)
        ) * 0.06;

        vec4 worldPos = modelMatrix * vec4(baseP, 1.0);

        float dagKeep = 1.0 - clamp(abs(m - 4.0), 0.0, 1.0);
        vec3 toPtr = worldPos.xyz - uPointer;
        float ptrDist = length(toPtr);
        float nearField = exp(-ptrDist * ptrDist * 0.45);
        vec3 tangent = normalize(cross(toPtr + vec3(0.001), vec3(0.0, 0.0, 1.0)));

        worldPos.xyz += (normalize(toPtr + vec3(0.001)) * 0.34 + tangent * 0.44) * nearField * (1.0 - uHoldCharge);
        worldPos.xyz += uPointerVel * nearField * 0.13;

        float gravityField = exp(-ptrDist * 0.42) * uHoldCharge;
        float gravScale = mix(1.0, 0.38, dagKeep);
        worldPos.xyz += (-toPtr * 0.65 + tangent * 1.25) * (gravityField * gravScale);

        float ringDelta = abs(length(baseP) - uShockRadius);
        float shock = exp(-ringDelta * ringDelta * 3.2) * uShockStrength;
        worldPos.xyz += normalize(baseP + vec3(0.001)) * shock * 0.70;

        // Smooth 3D Keep-Out Shield around Central Core
        vec3 coreCenter = modelMatrix[3].xyz;
        vec3 relCore = worldPos.xyz - coreCenter;
        vec3 coreRadii = mix(vec3(1.42, 1.48, 1.42), vec3(1.06, 1.48, 1.06), dagKeep);
        float coreNormDist = length(relCore / coreRadii);
        if (coreNormDist < 1.0 && m > 0.35) {
          vec3 pushDir = normalize(relCore + vec3(0.0, 0.0, 0.001));
          worldPos.xyz += pushDir * (1.0 - coreNormDist) * length(coreRadii) * 0.62;
        }

        vec4 mvPos = viewMatrix * worldPos;
        gl_Position = projectionMatrix * mvPos;

        // 6-Act Industrial Color Progression (Zero Neon Pink / Purple!)
        float h = fract(aSeed.z * 2.1 + uTime * 0.025);
        vec3 pal0 = mix(vec3(0.161, 0.592, 1.000), vec3(0.863, 0.902, 0.961), h); // Apple Ice Blue + Silver White
        vec3 pal1 = mix(vec3(0.000, 0.443, 0.890), vec3(0.722, 0.831, 0.961), h); // Apple Sky Blue + Ice Silver
        vec3 pal2 = mix(vec3(0.369, 0.486, 0.886), vec3(0.392, 0.710, 1.000), h); // Titanium Indigo + Ice Blue
        vec3 pal3 = mix(vec3(0.851, 0.608, 0.263), vec3(0.769, 0.808, 0.863), h); // Warm Titanium Gold + Cool Silver
        vec3 pal4 = mix(vec3(0.188, 0.820, 0.345), vec3(0.165, 0.663, 0.878), h); // Emerald Green + Deep Sea Cyan
        vec3 pal5 = mix(vec3(0.580, 0.722, 0.910), vec3(0.114, 0.337, 0.722), h); // Ice Silver Corona + Deep Space Blue

        vec3 darkCol;
        if (m < 1.0) darkCol = mix(pal0, pal1, m);
        else if (m < 2.0) darkCol = mix(pal1, pal2, m - 1.0);
        else if (m < 3.0) darkCol = mix(pal2, pal3, m - 2.0);
        else if (m < 4.0) darkCol = mix(pal3, pal4, m - 3.0);
        else darkCol = mix(pal4, pal5, clamp(m - 4.0, 0.0, 1.0));

        // Light Frost: Clean Crisp Graphite Silver-Gray & Apple Blue Particle Cloud (Never Muddy)
        vec3 graphiteTone = mix(vec3(0.24, 0.26, 0.31), vec3(0.42, 0.46, 0.54), aSeed.w);
        vec3 appleBlueTone = mix(vec3(0.000, 0.443, 0.890), darkCol * 0.85, 0.45);
        vec3 lightCol = mix(graphiteTone, appleBlueTone, smoothstep(0.22, 0.86, h));

        vec3 col = mix(darkCol, lightCol, uLightMode) * mix(waterContactShade, 1.0, uLightMode * 0.55);

        float dagWeight = 1.0 - clamp(abs(m - 4.0), 0.0, 1.0);
        float dagPulse = dagWeight * pow(0.5 + 0.5 * sin(baseP.y * 3.2 + uTime * 3.4), 3.0);

        // Cool Luminous Ice-Blue Impulse (Zero Fluorescent Pink!)
        vec3 impulseTint = mix(vec3(0.56, 0.82, 1.0), vec3(0.00, 0.44, 0.89), uLightMode);
        col += impulseTint * (gravityField * 0.95 + shock * 1.2 + nearField * 0.52 + dagPulse * 0.48 + waterCausticRing * 0.8);

        vColor = col;
        float baseAlpha = mix(0.76, 0.62, uLightMode) * (0.48 + 0.52 * sin(uTime * 1.6 + aSeed.x)) * waterContactShade;
        baseAlpha *= mix(1.0, pMask, coronaWeight);
        vAlpha = clamp(baseAlpha + shock * 0.50 + nearField * 0.32 + gravityField * 0.44 + waterCausticRing * 0.36, 0.04, 1.0);

        float depthScale = clamp(11.0 / max(1.5, -mvPos.z), 0.35, 2.8);
        float sizeBoost = 1.0 + shock * 1.30 + nearField * 0.80 + gravityField * 1.05 + dagPulse * 0.60;
        gl_PointSize = (1.50 + aSeed.w * 2.25) * uPixelRatio * depthScale * sizeBoost;
      }
    `,
    fragmentShader: `
      uniform float uLightMode;
      varying vec3 vColor;
      varying float vAlpha;
      void main() {
        vec2 uv = gl_PointCoord - 0.5;
        float r = length(uv) * 2.0;
        if (r > 1.0) discard;
        float core = exp(-r * r * 4.4);
        float halo = smoothstep(1.0, 0.0, r) * 0.34;
        float a = clamp((core + halo) * vAlpha, 0.0, 1.0);
        // Premultiplied continuous additive (dark) -> crisp normal (light)
        float outA = mix(a * 0.14, a, uLightMode);
        gl_FragColor = vec4(vColor * a, outA);
      }
    `
  });

  const particleCloud = new THREE.Points(pGeo, pMat);
  particleCloud.renderOrder = 3;
  rootGroup.add(particleCloud);

  /* ------------------------------------------------------------------------
     Interactive State: Cursor Physics, Hold Pulse, Raycasting & Springs
     ------------------------------------------------------------------------ */
  let morphCurrent = getMorphStage();
  let offsetXCurrent = getTargetSculptureOffsetX();
  let offsetXVel = 0;
  let offsetYCurrent = getTargetSculptureOffsetY();
  let offsetYVel = 0;

  const pointerNDC = new THREE.Vector2(99, 99);
  const pointerScreen = { x: -240, y: -240, smoothX: -240, smoothY: -240 };
  const pointerWorldTarget = new THREE.Vector3(99, 99, 0);
  const pointerWorldSmooth = new THREE.Vector3(99, 99, 0);
  const prevPointerWorld = new THREE.Vector3(99, 99, 0);
  const pointerVelVec = new THREE.Vector3(0, 0, 0);
  const localPtrVec = new THREE.Vector3(0, 0, 2);

  let isPointerDown = false;
  let isDraggingStage = false;
  let downTimeMs = 0;
  let downCoords = { x: 0, y: 0 };
  let prevDrag = { x: 0, y: 0 };
  let dragYaw = 0;
  let dragPitch = 0;
  let holdCharge = 0;
  let layerSpread = 0;
  let trailFade = 0;

  let shockRadius = 0;
  let shockStrength = 0;
  let corePulse = 0;
  let forgePinchProgress = 0;
  let isForging = false;

  const raycaster = new THREE.Raycaster();
  let hovered3DNode = null;
  let prevHovered3DNode = null;

  function applyBlendedThemeToScene(blend) {
    liveBgColor.copy(darkBgColor).lerp(lightBgColor, blend);
    scene.background = liveBgColor;

    hemiLight.color.copy(hemiDarkSky).lerp(hemiLightSky, blend);
    hemiLight.groundColor.copy(hemiDarkGround).lerp(hemiLightGround, blend);
    hemiLight.intensity = 1.45 + blend * 0.45;
    keyLight.intensity = 2.85 - blend * 0.35;
    rimLight.color.copy(rimDarkCol).lerp(rimLightCol, blend);
    rimLight.intensity = 1.45 - blend * 0.32;

    const satEmissive = 0.22 - blend * 0.13;
    const dagEmissive = 0.24 - blend * 0.14;
    const gyroEmissive = 0.28 - blend * 0.16;
    satRecords.forEach((rec) => { rec.mat.emissiveIntensity = satEmissive; });
    dagRecords.forEach((rec) => { rec.mat.emissiveIntensity = dagEmissive; });
    gyroRings.forEach((g) => { g.mat.emissiveIntensity = gyroEmissive; });

    coreUniforms.uLightMode.value = blend;
    haloUniforms.uLightMode.value = blend;
    pUniforms.uLightMode.value = blend;
    trailUniforms.uLightMode.value = blend;
    trailUniforms.uColor.value.copy(trailDarkCol).lerp(trailLightCol, blend);
  }

  applyBlendedThemeToScene(themeBlend);

  shaderBridge = {
    triggerPulse: (power = 1.0, soundOpt = true) => {
      shockRadius = 0.22;
      shockStrength = power;
      corePulse = power;
      if (soundOpt) {
        const opts = typeof soundOpt === 'object' ? soundOpt : { scene: state.activeScene };
        soundApi?.playPulse?.(power, opts);
      }
    },
    triggerForgeCollapse: () => {
      isForging = true;
      forgePinchProgress = 0.001;
      corePulse = 1.15;
      soundApi?.playForgeCollapse?.();
    },
    syncPluginMask: () => {
      updatePluginMaskUniform();
    },
    syncTheme: (themeId) => {
      targetThemeBlend = themeId === 'pure-frost' ? 1.0 : 0.0;
    }
  };

  window.addEventListener('pointermove', (e) => {
    pointerScreen.x = e.clientX;
    pointerScreen.y = e.clientY;
    pointerNDC.x = (e.clientX / window.innerWidth) * 2 - 1;
    pointerNDC.y = -(e.clientY / window.innerHeight) * 2 + 1;

    const halfH = Math.tan((camera.fov * Math.PI) / 360) * camera.position.z;
    const halfW = halfH * camera.aspect;
    pointerWorldTarget.set(pointerNDC.x * halfW, pointerNDC.y * halfH, 0.45);
    trailFade = Math.min(1.0, trailFade + 0.35);

    if (isPointerDown) {
      const dx = e.clientX - prevDrag.x;
      const dy = e.clientY - prevDrag.y;
      if (Math.hypot(e.clientX - downCoords.x, e.clientY - downCoords.y) > 4) {
        isDraggingStage = true;
      }
      dragYaw += dx * 0.0065;
      dragPitch = Math.max(-0.85, Math.min(0.85, dragPitch + dy * 0.0055));
      prevDrag = { x: e.clientX, y: e.clientY };
    }
  });

  window.addEventListener('pointerdown', (e) => {
    if (e.target?.closest?.('button, a, .glass-surface, .header-capsule, .timecode-rail')) return;
    isPointerDown = true;
    isDraggingStage = false;
    downTimeMs = performance.now();
    downCoords = { x: e.clientX, y: e.clientY };
    prevDrag = { x: e.clientX, y: e.clientY };
  });

  window.addEventListener('pointerup', (e) => {
    if (!isPointerDown) return;
    isPointerDown = false;
    isDraggingStage = false;
    const heldMs = performance.now() - downTimeMs;
    const movedPx = Math.hypot(e.clientX - downCoords.x, e.clientY - downCoords.y);

    const nx = (e.clientX / Math.max(1, window.innerWidth)) * 2 - 1;
    const ny = -(e.clientY / Math.max(1, window.innerHeight)) * 2 + 1;

    if (movedPx < 8 && hovered3DNode) {
      const ud = hovered3DNode.userData;
      if (ud.kind === 'plugin') {
        togglePluginById(ud.plugin.id);
      } else if (ud.kind === 'dag') {
        shaderBridge.triggerPulse(1.15, { nx, ny, scene: state.activeScene });
      }
    } else if (holdCharge > 0.25) {
      shaderBridge.triggerPulse(1.35 + holdCharge * 0.85, false);
      soundApi?.playShockRelease?.(1.0 + holdCharge * 0.55, { nx, ny, scene: state.activeScene });
    } else if (movedPx < 10 && heldMs < 260) {
      shaderBridge.triggerPulse(0.95, { nx, ny, scene: state.activeScene });
    }
  });

  window.addEventListener('resize', () => {
    camera.aspect = window.innerWidth / window.innerHeight;
    camera.updateProjectionMatrix();
    renderer.setSize(window.innerWidth, window.innerHeight);
    pUniforms.uPixelRatio.value = Math.min(window.devicePixelRatio || 1, 2);
  });

  if (typeof renderer.compile === 'function') {
    satGroup.visible = true;
    gyroGroup.visible = true;
    dagGroup.visible = true;
    renderer.compile(scene, camera);
  }

  let coreYawPhase = 0;
  let vortexPhase = 0;
  let forgeShockFired = false;
  let firstFrameRendered = false;
  let simTime = 0;
  const clock = new THREE.Clock();

  function animate() {
    requestAnimationFrame(animate);
    const rawDt = Math.min(0.05, clock.getDelta());
    const motionScale = isReducedMotion() ? 0.16 : 1.0;
    const dt = rawDt * motionScale;
    simTime += dt;

    stepAutoPlay(rawDt);

    /* Continuous Smooth themeBlend Interpolation (Zero Instant Flash!) */
    if (Math.abs(targetThemeBlend - themeBlend) > 0.0004) {
      const blendRate = isReducedMotion() ? 1.0 : (1 - Math.exp(-5.8 * rawDt));
      themeBlend += (targetThemeBlend - themeBlend) * blendRate;
      if (Math.abs(targetThemeBlend - themeBlend) <= 0.0004) themeBlend = targetThemeBlend;
      applyBlendedThemeToScene(themeBlend);
    }

    /* 1. Morph Stage & Counter-Choreography Position Springs */
    const targetMorph = getMorphStage();
    morphCurrent += (targetMorph - morphCurrent) * (1 - Math.exp(-4.8 * rawDt));

    const targetX = getTargetSculptureOffsetX();
    const targetY = getTargetSculptureOffsetY();
    const omega = 4.0, zeta = 0.90;
    const f = 1 + 2 * rawDt * zeta * omega;
    const oo = omega * omega;
    const hoo = rawDt * oo;
    const hhoo = rawDt * hoo;
    const detInv = 1 / (f + hhoo);

    const nextX = (f * offsetXCurrent + rawDt * offsetXVel + hhoo * targetX) * detInv;
    offsetXVel = (offsetXVel + hoo * (targetX - offsetXCurrent)) * detInv;
    offsetXCurrent = nextX;

    const nextY = (f * offsetYCurrent + rawDt * offsetYVel + hhoo * targetY) * detInv;
    offsetYVel = (offsetYVel + hoo * (targetY - offsetYCurrent)) * detInv;
    offsetYCurrent = nextY;

    if (!isPointerDown) {
      dragYaw *= Math.pow(0.48, rawDt);
      dragPitch *= Math.pow(0.48, rawDt);
    }

    const bobY = Math.sin(simTime * 0.48) * 0.055;
    rootGroup.position.x = offsetXCurrent;
    rootGroup.position.y = offsetYCurrent + bobY;

    const ptrX = pointerNDC.x < 10 ? pointerNDC.x : 0;
    const ptrY = pointerNDC.y < 10 ? pointerNDC.y : 0;

    const s1Weight = Math.max(0, 1 - Math.abs(morphCurrent - 1.0));
    const s3Weight = Math.max(0, 1 - Math.abs(morphCurrent - 3.0));
    const s5Weight = Math.max(0, 1 - Math.abs(morphCurrent - 5.0));
    const planarLock = Math.min(1, s1Weight + s5Weight);

    const autoOrbitY = Math.sin(simTime * 0.22) * 0.22;
    rootGroup.rotation.y = autoOrbitY * (1 - planarLock * 0.65) + ptrX * 0.14 + dragYaw;
    rootGroup.rotation.x = Math.sin(simTime * 0.26) * 0.06 - ptrY * 0.10 + dragPitch;

    haloMesh.position.set(offsetXCurrent, offsetYCurrent + bobY, -2.4);
    haloMesh.lookAt(camera.position);

    if (isForging) {
      forgePinchProgress += rawDt * 0.46;
      if (!forgeShockFired && forgePinchProgress >= 0.52) {
        forgeShockFired = true;
        shockRadius = 0.24;
        shockStrength = 1.20;
        soundApi?.playForgeConfirm?.();
      }
      if (forgePinchProgress >= 1.0) {
        isForging = false;
        forgePinchProgress = 0;
        forgeShockFired = false;
      }
    } else {
      forgeShockFired = false;
    }
    const pinchCurve = isForging ? 0.5 * (1 - Math.cos(forgePinchProgress * Math.PI * 2)) : 0;

    const spinMask = Math.max(0, 1 - planarLock);
    coreYawPhase -= dt * (0.15 + s3Weight * 0.50 + pinchCurve * 0.70) * spinMask;
    coreYawPhase = Math.atan2(Math.sin(coreYawPhase), Math.cos(coreYawPhase));
    if (planarLock > 0.01) {
      coreYawPhase *= Math.pow(0.06, rawDt * planarLock);
    }

    vortexPhase += dt * (0.35 + s3Weight * 0.46 + pinchCurve * 1.40);
    const lensYaw = -0.24 + Math.sin(simTime * 0.42) * 0.07;
    const eclipseYaw = Math.sin(simTime * 0.34) * 0.12;
    coreMesh.rotation.y = coreYawPhase + s1Weight * lensYaw + s5Weight * eclipseYaw;
    coreMesh.rotation.x = s1Weight * 0.15 + s5Weight * (Math.cos(simTime * 0.28) * 0.06);

    coreMesh.updateMatrixWorld();
    coreNormalMat.getNormalMatrix(coreMesh.matrixWorld);

    /* 2. Companion 3D Sculptures */
    const s2Vis = Math.max(0, 1 - Math.abs(morphCurrent - 2.0) * 1.15);
    satGroup.visible = s2Vis > 0.02;
    if (satGroup.visible) {
      const nSat = satRecords.length;
      satRecords.forEach((rec, i) => {
        const mounted = state.enabledPlugins.has(rec.plugin.id);
        const cAng = (i / nSat) * Math.PI * 2 + simTime * (mounted ? 0.20 : 0.065);
        const r = (mounted ? 3.42 : 4.48) * (0.72 + 0.28 * s2Vis);
        rec.mesh.position.set(
          Math.cos(cAng) * r,
          Math.sin(cAng) * r * 0.86,
          Math.sin(cAng * 2.0) * 0.70
        );
        rec.mesh.rotation.y = simTime * 0.85 + i;
        rec.mesh.rotation.x = simTime * 0.55;
        const targetHov = hovered3DNode === rec.mesh ? 1.55 : (mounted ? 1.0 : 0.66);
        rec.mesh.userData.hoverScale += (targetHov - rec.mesh.userData.hoverScale) * 0.16;
        rec.mesh.scale.setScalar(rec.mesh.userData.hoverScale * s2Vis);
        rec.mat.opacity = s2Vis * (mounted ? 0.95 : 0.38);
      });
    }

    const s3Vis = Math.max(0, 1 - Math.abs(morphCurrent - 3.0) * 1.15);
    gyroGroup.visible = s3Vis > 0.02;
    if (gyroGroup.visible) {
      const speedMult = 1 + pinchCurve * 2.4 + holdCharge * 2.1;
      gyroRings[0].mesh.rotation.x += dt * 0.92 * speedMult;
      gyroRings[1].mesh.rotation.y += dt * 1.10 * speedMult;
      gyroRings[2].mesh.rotation.z += dt * 0.82 * speedMult;
      gyroRings.forEach((g) => {
        g.mesh.scale.setScalar(0.82 + 0.18 * s3Vis);
        g.mat.opacity = s3Vis * 0.60;
      });
    }

    const s4Vis = Math.max(0, 1 - Math.abs(morphCurrent - 4.0) * 1.15);
    dagGroup.visible = s4Vis > 0.02;
    if (dagGroup.visible) {
      dagRecords.forEach((rec, i) => {
        const bp = rec.dag.pos;
        const dx = localPtrVec.x - bp[0];
        const dy = localPtrVec.y - bp[1];
        const dz = localPtrVec.z - bp[2];
        const dPtr = Math.hypot(dx, dy, dz);
        const pull = dPtr < 12 ? Math.exp(-dPtr * 0.42) * holdCharge * 0.24 : 0;
        rec.mesh.position.set(bp[0] + dx * pull, bp[1] + dy * pull, bp[2] + dz * pull);
        rec.mesh.rotation.y = simTime * 0.7 + i * 0.5;
        const targetHov = hovered3DNode === rec.mesh ? 1.55 : 1.0;
        rec.mesh.userData.hoverScale += (targetHov - rec.mesh.userData.hoverScale) * 0.16;
        rec.mesh.scale.setScalar(rec.mesh.userData.hoverScale * s4Vis);
        rec.mat.opacity = s4Vis * 0.94;
      });
    }

    /* 3. Cursor Trail, Layer Fan-Out & Raycast Hover Pill (Native Cursor Preserved!) */
    prevPointerWorld.copy(pointerWorldSmooth);
    pointerWorldSmooth.lerp(pointerWorldTarget, 1 - Math.exp(-11.0 * rawDt));
    if (pointerWorldSmooth.x < 50 && prevPointerWorld.x < 50) {
      pointerVelVec.subVectors(pointerWorldSmooth, prevPointerWorld).multiplyScalar(1 / Math.max(0.008, rawDt));
      pointerVelVec.clampLength(0, 18);
    } else {
      pointerVelVec.set(0, 0, 0);
    }

    if (pointerWorldSmooth.x < 50) {
      trailPoints[0].lerp(pointerWorldSmooth, 0.55);
      for (let i = 1; i < TRAIL_LEN; i++) {
        trailPoints[i].lerp(trailPoints[i - 1], 0.46);
      }
      for (let i = 0; i < TRAIL_LEN; i++) {
        trailPosArr[i * 3] = trailPoints[i].x;
        trailPosArr[i * 3 + 1] = trailPoints[i].y;
        trailPosArr[i * 3 + 2] = trailPoints[i].z;
      }
      trailGeo.attributes.position.needsUpdate = true;
    }
    trailFade *= Math.pow(0.18, rawDt);
    trailUniforms.uOpacity.value = Math.min(0.55, trailFade * 0.55 + holdCharge * 0.30) * motionScale;

    const distToSculpture = Math.hypot(pointerWorldSmooth.x - offsetXCurrent, pointerWorldSmooth.y - offsetYCurrent);
    const cursorSpread = (s1Weight > 0.25 && distToSculpture < 4.2) ? (1 - distToSculpture / 4.2) : 0;
    const spreadTarget = Math.max(cursorSpread, s1Weight * state.autoLayerShowcase);
    layerSpread += (spreadTarget - layerSpread) * (1 - Math.exp(-6.0 * rawDt));

    const chargeActive = isPointerDown && !isDraggingStage && (performance.now() - downTimeMs > 180);
    holdCharge += ((chargeActive ? 1.0 : 0.0) - holdCharge) * (1 - Math.exp(-5.5 * rawDt));

    if (pointerNDC.x < 10 && (satGroup.visible || dagGroup.visible)) {
      raycaster.setFromCamera(pointerNDC, camera);
      const candidates = satGroup.visible ? satRecords.map((r) => r.mesh) : dagRecords.map((r) => r.mesh);
      const hits = raycaster.intersectObjects(candidates, false);
      hovered3DNode = hits.length > 0 ? hits[0].object : null;
    } else {
      hovered3DNode = null;
    }

    if (hovered3DNode && hovered3DNode !== prevHovered3DNode) {
      const ud = hovered3DNode.userData;
      soundApi?.playNodeHover?.(ud.kind, ud.index ?? 0, pointerNDC.x < 10 ? pointerNDC.x : 0);
    }
    prevHovered3DNode = hovered3DNode;

    // Native macOS cursor semantics (zero crosshair!)
    if (isDraggingStage) container.style.cursor = 'grabbing';
    else if (hovered3DNode) container.style.cursor = 'pointer';
    else container.style.cursor = 'default';

    if (cursorAura && pointerScreen.x > -50) {
      pointerScreen.smoothX += (pointerScreen.x - pointerScreen.smoothX) * 0.30;
      pointerScreen.smoothY += (pointerScreen.y - pointerScreen.smoothY) * 0.30;
      cursorAura.style.transform = `translate3d(${pointerScreen.smoothX.toFixed(1)}px, ${pointerScreen.smoothY.toFixed(1)}px, 0)`;
      cursorAura.classList.toggle('charging', chargeActive);
      cursorAura.classList.toggle('hovering-node', Boolean(hovered3DNode) && !chargeActive);

      if (cursorNodeLabel) {
        if (chargeActive) {
          cursorNodeLabel.textContent = state.lang === 'zh' ? '⌥Space · 松手释放光学脉冲' : '⌥SPACE · RELEASE OPTICAL PULSE';
        } else if (hovered3DNode) {
          const ud = hovered3DNode.userData;
          if (ud.kind === 'plugin') {
            const on = state.enabledPlugins.has(ud.plugin.id);
            const name = state.lang === 'zh' ? ud.plugin.zh : ud.plugin.en;
            const status = state.lang === 'zh' ? (on ? '已启用' : '未启用 · 0 内存') : (on ? 'ACTIVE' : 'OFF · 0 RAM');
            cursorNodeLabel.textContent = `${name} · ${status}`;
          } else if (ud.kind === 'dag') {
            cursorNodeLabel.textContent = state.lang === 'zh' ? (ud.dag.zh || ud.dag.id) : (ud.dag.en || ud.dag.id);
          }
        }
      }
    }

    /* 4. Shockwave & Pulse Decay */
    if (shockStrength > 0.002) {
      shockRadius += rawDt * 6.0;
      shockStrength *= Math.pow(0.07, rawDt);
    } else {
      shockStrength = 0;
    }
    if (corePulse > 0.002) corePulse *= Math.pow(0.06, rawDt);
    else corePulse = 0;

    /* 5. Push Uniforms & Render */
    localPtrVec.copy(pointerWorldSmooth).sub(rootGroup.position);

    coreUniforms.uTime.value = simTime;
    coreUniforms.uMorph.value = morphCurrent;
    coreUniforms.uPulse.value = corePulse;
    coreUniforms.uHoldCharge.value = holdCharge;
    coreUniforms.uForgePinch.value = pinchCurve;
    coreUniforms.uPointerLocal.value.copy(localPtrVec);

    haloUniforms.uTime.value = simTime;
    haloUniforms.uMorph.value = morphCurrent;
    haloUniforms.uPulse.value = corePulse + holdCharge * 0.55;

    pUniforms.uTime.value = simTime;
    pUniforms.uMorph.value = morphCurrent;
    pUniforms.uPointer.value.copy(pointerWorldSmooth);
    pUniforms.uPointerVel.value.copy(pointerVelVec);
    pUniforms.uHoldCharge.value = holdCharge;
    pUniforms.uLayerSpread.value = layerSpread;
    pUniforms.uShockRadius.value = shockRadius;
    pUniforms.uShockStrength.value = shockStrength;
    pUniforms.uForgePinch.value = pinchCurve;
    pUniforms.uVortexPhase.value = vortexPhase;

    soundApi?.updateFrame?.({
      scene: state.activeScene,
      holdCharge,
      layerSpread,
      pointerSpeed: pointerVelVec.length(),
      pluginRatio: state.enabledPlugins.size / PLUGINS.length,
      lightMode: state.theme === 'pure-frost'
    });

    renderer.render(scene, camera);

    if (!firstFrameRendered) {
      firstFrameRendered = true;
      scheduleBootDismissAfterFirstFrame();
    }
  }

  animate();
}

/* ==========================================================================
   9B. Offline High-Art 2D Canvas Fallback (Synced Palette + Smooth themeBlend)
   ========================================================================== */
function mountOfflineParticleFilm(container) {
  const canvas = document.createElement('canvas');
  container.appendChild(canvas);
  const ctx = canvas.getContext('2d');

  let w = window.innerWidth;
  let h = window.innerHeight;
  let dpr = Math.min(window.devicePixelRatio || 1, 2);

  function resize() {
    w = window.innerWidth;
    h = window.innerHeight;
    dpr = Math.min(window.devicePixelRatio || 1, 2);
    canvas.width = Math.round(w * dpr);
    canvas.height = Math.round(h * dpr);
  }
  resize();
  window.addEventListener('resize', resize);

  const COUNT = 3200;
  const forms = generateSixMorphForms(COUNT);
  let morphCurrent = getMorphStage();
  let offsetXCurrent = getTargetSculptureOffsetX();
  let offsetYCurrent = getTargetSculptureOffsetY();
  let targetThemeBlend = state.theme === 'pure-frost' ? 1.0 : 0.0;
  let themeBlend = targetThemeBlend;
  let shockRadius = 0;
  let shockStrength = 0;
  let ptrX = 0, ptrY = 0;
  let firstFrameRendered = false;

  // Identical 6-Act Industrial RGB Palette
  const STAGE_RGB = [
    [41, 151, 255],  // 00 Apple Ice Blue
    [0, 113, 227],   // 01 Apple Sky Blue
    [94, 124, 226],  // 02 Titanium Indigo
    [217, 155, 67],  // 03 Warm Titanium Gold
    [48, 209, 88],   // 04 Emerald Green
    [148, 184, 232]  // 05 Ice Silver Corona
  ];

  function lerp(a, b, t) { return a + (b - a) * t; }

  window.addEventListener('pointermove', (e) => {
    ptrX = (e.clientX / Math.max(1, w)) * 2 - 1;
    ptrY = -(e.clientY / Math.max(1, h)) * 2 + 1;
  });

  window.addEventListener('pointerdown', (e) => {
    if (e.target?.closest?.('button, a, .glass-surface, .header-capsule, .timecode-rail')) return;
    shockRadius = 0.2;
    shockStrength = 1.1;
    const nx = (e.clientX / Math.max(1, w)) * 2 - 1;
    const ny = -(e.clientY / Math.max(1, h)) * 2 + 1;
    soundApi?.playPulse?.(1.0, { nx, ny, scene: state.activeScene });
  });

  shaderBridge = {
    triggerPulse: (p = 1.0, soundOpt = true) => {
      shockRadius = 0.2;
      shockStrength = p;
      if (soundOpt) {
        const opts = typeof soundOpt === 'object' ? soundOpt : { scene: state.activeScene };
        soundApi?.playPulse?.(p, opts);
      }
    },
    triggerForgeCollapse: () => {
      shockRadius = 0.2;
      shockStrength = 1.3;
      soundApi?.playForgeCollapse?.();
    },
    syncPluginMask: () => {},
    syncTheme: (themeId) => {
      targetThemeBlend = themeId === 'pure-frost' ? 1.0 : 0.0;
    }
  };

  let lastT = performance.now() * 0.001;
  let simTime = 0;

  function loop() {
    requestAnimationFrame(loop);
    const now = performance.now() * 0.001;
    const rawDt = Math.min(0.05, Math.max(0.001, now - lastT));
    lastT = now;
    const motionScale = isReducedMotion() ? 0.16 : 1.0;
    simTime += rawDt * motionScale;

    stepAutoPlay(rawDt);
    soundApi?.updateFrame?.({
      scene: state.activeScene,
      pluginRatio: state.enabledPlugins.size / PLUGINS.length,
      lightMode: state.theme === 'pure-frost'
    });

    if (Math.abs(targetThemeBlend - themeBlend) > 0.0004) {
      const rate = isReducedMotion() ? 1.0 : (1 - Math.exp(-5.8 * rawDt));
      themeBlend += (targetThemeBlend - themeBlend) * rate;
    }

    morphCurrent += (getMorphStage() - morphCurrent) * (1 - Math.exp(-5.0 * rawDt));
    offsetXCurrent += (getTargetSculptureOffsetX() - offsetXCurrent) * (1 - Math.exp(-5.0 * rawDt));
    offsetYCurrent += (getTargetSculptureOffsetY() - offsetYCurrent) * (1 - Math.exp(-5.0 * rawDt));

    if (shockStrength > 0.002) {
      shockRadius += rawDt * 5.6;
      shockStrength *= Math.pow(0.08, rawDt);
    } else shockStrength = 0;

    // Continuous Background RGB (#0B0C0F <-> #F5F5F7)
    const bgR = Math.round(lerp(11, 245, themeBlend));
    const bgG = Math.round(lerp(12, 245, themeBlend));
    const bgB = Math.round(lerp(15, 247, themeBlend));

    const m = Math.max(0, Math.min(5, morphCurrent));
    const seg = Math.min(4, Math.floor(m));
    const frac = m - seg;
    const smooth = frac * frac * (3 - 2 * frac);

    const cA = STAGE_RGB[seg];
    const cB = STAGE_RGB[seg + 1];
    const accR = lerp(cA[0], cB[0], smooth);
    const accG = lerp(cA[1], cB[1], smooth);
    const accB = lerp(cA[2], cB[2], smooth);

    ctx.save();
    ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    ctx.fillStyle = `rgb(${bgR},${bgG},${bgB})`;
    ctx.fillRect(0, 0, w, h);

    const fovScale = (h * 0.5) / Math.tan((40 * Math.PI) / 360);
    const coreScreenX = w * 0.5 + offsetXCurrent * (fovScale / 10.8);
    const coreScreenY = h * 0.5 - offsetYCurrent * (fovScale / 10.8);
    const haloR = Math.min(w, h) * 0.38;

    // Atmospheric Halation + Translucent Optical Crystal Orb
    const haloGrad = ctx.createRadialGradient(coreScreenX, coreScreenY, 0, coreScreenX, coreScreenY, haloR);
    haloGrad.addColorStop(0, `rgba(${Math.round(accR)},${Math.round(accG)},${Math.round(accB)},${(0.24 - themeBlend * 0.12).toFixed(3)})`);
    haloGrad.addColorStop(0.55, `rgba(${Math.round(accR)},${Math.round(accG)},${Math.round(accB)},${(0.08 - themeBlend * 0.04).toFixed(3)})`);
    haloGrad.addColorStop(1, 'rgba(0,0,0,0)');
    ctx.fillStyle = haloGrad;
    ctx.fillRect(0, 0, w, h);

    const orbR = Math.min(w, h) * 0.145;
    const orbGrad = ctx.createRadialGradient(
      coreScreenX - orbR * 0.28,
      coreScreenY - orbR * 0.30,
      orbR * 0.06,
      coreScreenX,
      coreScreenY,
      orbR
    );
    if (themeBlend > 0.5) {
      orbGrad.addColorStop(0, 'rgba(255,255,255,0.94)');
      orbGrad.addColorStop(0.55, `rgba(${Math.round(lerp(220, accR, 0.28))},${Math.round(lerp(232, accG, 0.28))},${Math.round(lerp(248, accB, 0.28))},0.72)`);
      orbGrad.addColorStop(1, `rgba(${Math.round(accR)},${Math.round(accG)},${Math.round(accB)},0.06)`);
    } else {
      orbGrad.addColorStop(0, 'rgba(235,244,255,0.72)');
      orbGrad.addColorStop(0.42, `rgba(${Math.round(accR)},${Math.round(accG)},${Math.round(accB)},0.34)`);
      orbGrad.addColorStop(1, 'rgba(11,12,15,0)');
    }
    ctx.fillStyle = orbGrad;
    ctx.beginPath();
    ctx.arc(coreScreenX, coreScreenY, orbR, 0, Math.PI * 2);
    ctx.fill();

    // Projected 3D Particle Cloud
    const ry = Math.sin(simTime * 0.22) * 0.22 + ptrX * 0.16;
    const rx = Math.sin(simTime * 0.30) * 0.08 - ptrY * 0.12;
    const cy = Math.cos(ry), sy = Math.sin(ry);
    const cx = Math.cos(rx), sx = Math.sin(rx);

    const arrList = [forms.form0, forms.form1, forms.form2, forms.form3, forms.form4, forms.form5];
    const srcA = arrList[seg];
    const srcB = arrList[seg + 1];

    const pDarkStyle = `rgba(${Math.round(accR)},${Math.round(accG)},${Math.round(accB)},0.70)`;
    const pLightBlueStyle = `rgba(${Math.round(lerp(0, accR, 0.45))},${Math.round(lerp(113, accG, 0.45))},${Math.round(lerp(227, accB, 0.45))},0.56)`;
    const pLightGraphiteStyle = 'rgba(72,76,88,0.44)';

    for (let i = 0; i < COUNT; i++) {
      const i3 = i * 3;
      let px = srcA[i3] + (srcB[i3] - srcA[i3]) * smooth;
      let py = srcA[i3 + 1] + (srcB[i3 + 1] - srcA[i3 + 1]) * smooth;
      let pz = srcA[i3 + 2] + (srcB[i3 + 2] - srcA[i3 + 2]) * smooth;

      if (shockStrength > 0.01) {
        const len = Math.hypot(px, py, pz) || 1;
        const delta = Math.abs(len - shockRadius);
        const boost = Math.exp(-delta * delta * 3.5) * shockStrength * 0.65;
        px += (px / len) * boost;
        py += (py / len) * boost;
        pz += (pz / len) * boost;
      }

      const x1 = px * cy + pz * sy;
      const z1 = -px * sy + pz * cy;
      const y2 = py * cx - z1 * sx;
      const z2 = py * sx + z1 * cx;

      const depth = 10.8 - z2;
      if (depth < 1.2) continue;
      const scale = fovScale / depth;
      const sx2 = w * 0.5 + (x1 + offsetXCurrent) * scale;
      const sy2 = h * 0.5 - (y2 + offsetYCurrent) * scale;

      ctx.fillStyle = themeBlend > 0.5
        ? (i % 3 === 0 ? pLightGraphiteStyle : pLightBlueStyle)
        : pDarkStyle;
      const r = Math.max(1.0, Math.min(2.8, 1.75 * (scale / 100)));
      ctx.fillRect(sx2, sy2, r, r);
    }

    ctx.restore();

    if (!firstFrameRendered) {
      firstFrameRendered = true;
      scheduleBootDismissAfterFirstFrame();
    }
  }

  loop();
}

/* --------------------------------------------------------------------------
   10. Boot Orchestrator
   -------------------------------------------------------------------------- */
async function boot() {
  const container = document.getElementById('canvasContainer');
  if (!container) {
    dismissBootVeilImmediate();
    return;
  }

  if (bootBarFill) bootBarFill.style.width = '68%';
  const THREE = await resolveRealThree();

  try {
    if (THREE) {
      mountWebGLShaderFilm(container, THREE);
    } else {
      mountOfflineParticleFilm(container);
    }
  } catch (_) {
    container.innerHTML = '';
    mountOfflineParticleFilm(container);
  }
}

boot();
})();
