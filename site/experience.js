/* ==========================================================================
   Lumakey — Six-Morphology GPU Shader & Interactive Force-Field Film Engine
   6 Distinct 3D Sculptural Stages:
     00 · Liquid Prismatic Droplet & Caustic Mirror
     01 · 880:544 Superellipse Optical Lens & 4 Interactive Z-Layers
     02 · 8-Petal Astrolabe Star-Crown & 8 Raycastable Crystal Satellites
     03 · Twisted Tri-Lobe Helicoid Forge, 3 Gyro Rings & Accretion Vortex
     04 · Razor-Sharp Octahedral Diamond Spire & 7 Raycastable DAG Nodes
     05 · Celestial Solar-Eclipse Corona & Ascending Stardust
   5 Mouse Interactions:
     1. Velocity-Driven Fluid Wake + 3D Luminous Cursor Ribbon Trail
     2. Click-and-Hold Gravity Whirlpool Charge -> Supernova Shockwave Release
     3. Drag-to-Orbit 3D Sculpture Inspection with Inertial Spring Return
     4. Cursor-Proximity Z-Layer Fan-Out (Stage 01)
     5. Direct 3D Raycast Hover & Click on Crystal Satellites & DAG Nodes
   ========================================================================== */

(() => {
'use strict';

/* --------------------------------------------------------------------------
   1. Safe Storage & Shared State Synced with site/index.html
   -------------------------------------------------------------------------- */
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

const GH_HOST = ['https://', 'github.com', '/lengsukq/Lumakey'].join('');
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

const PLUGINS = [
  { id: 'ai-quota', zh: 'AI 额度雷达', en: 'AI Quota HUD', color: 0xec4899 },
  { id: 'translate-hub', zh: '流光译站', en: 'Translate Hub', color: 0xa855f7 },
  { id: 'browser-hub', zh: '三端书签', en: 'Browser Hub', color: 0x6366f1 },
  { id: 'quick-remind', zh: '闪电提醒', en: 'Quick Remind', color: 0xf59e0b },
  { id: 'mac-pilot', zh: '桌面中控台', en: 'Mac Pilot', color: 0x0ea5e9 },
  { id: 'screen-shield', zh: '状态屏遮罩', en: 'Screen Shield', color: 0x14b8a6 },
  { id: 'lumalink-companion', zh: '流光随行', en: 'LumaLink', color: 0x38bdf8 },
  { id: 'notion-bookmarks', zh: 'Notion 密钥箱', en: 'Notion Vault', color: 0x10b981 }
];

const DAG_NODES = [
  { id: 'Lumakey.app', zh: 'Lumakey.app · 双主题与自由浮窗', en: 'Lumakey.app · Native UI & HUD', pos: [-1.62, 2.28, 0.18], color: 0x38bdf8 },
  { id: 'lumakey-mcp', zh: 'lumakey-mcp · 16 项 AI 定制工具', en: 'lumakey-mcp · 16 MCP Tools', pos: [1.62, 2.28, 0.18], color: 0xa855f7 },
  { id: 'LumakeyCore', zh: 'LumakeyCore · 启动页定制 & Plugin v3.7', en: 'LumakeyCore · HomeLayout & Plugin v3.7', pos: [0.0, 1.74, 0.36], color: 0x6366f1 },
  { id: 'LumakeySearch', zh: 'LumakeySearch · LMKYIDX3 秒搜', en: 'LumakeySearch · LMKYIDX3 mmap', pos: [-2.26, -0.12, 0.22], color: 0x0ea5e9 },
  { id: 'LumakeyMedia', zh: 'LumakeyMedia · 截图标注 & 离线识字', en: 'LumakeyMedia · Capture, OCR & HEVC', pos: [0.0, -1.68, 0.36], color: 0xec4899 },
  { id: 'LumakeySystem', zh: 'LumakeySystem · 功耗脉搏 & 120Hz 滚轮', en: 'LumakeySystem · Mach & 120Hz Wheel', pos: [2.26, -0.12, 0.22], color: 0x10b981 },
  { id: 'LumakeyFoundation', zh: 'LumakeyFoundation · 密钥箱 & 自洁进程', en: 'LumakeyFoundation · AES-GCM Vault', pos: [0.0, -2.42, 0.18], color: 0xf59e0b }
];

const STAGE_LABELS = {
  zh: [
    '00 · 轻巧可定制的快捷中枢',
    '01 · 启动面板定制与秒搜',
    '02 · 高度定制与 Plugin v3.7',
    '03 · lumakey-mcp AI 共创',
    '04 · 五大原生利器与架构',
    '05 · 获取与开源共建'
  ],
  en: [
    '00 · CUSTOMIZABLE NATIVE HUB',
    '01 · LAUNCH PANEL & SEARCH',
    '02 · DEEP CUSTOM & PLUGIN V3.7',
    '03 · LUMAKEY-MCP (16 TOOLS)',
    '04 · NATIVE TOOLS & DAG',
    '05 · DOWNLOAD & OPEN SOURCE'
  ]
};

const FORGE_PRESETS = {
  pr: {
    zhQuote: '“输入 pr 列出待我 Review 的合并请求，按回车直接打开，访问凭据存入加密保险箱。”',
    enQuote: '"Type pr to list pull requests awaiting my review, press Return to open, and store my token in the AES-GCM vault."',
    zhMeta: 'scaffold → validate → run_plugin_test · FSEvents 350ms 热重载生效',
    enMeta: 'scaffold → validate → run_plugin_test · FSEvents 350ms Hot-Reload'
  },
  home: {
    zhQuote: '“新建一套『极简开发』启动面板：保留 16 格混合应用坞，挂上 GitHub 与本地 3000 端口书签架，隐藏底部提示。”',
    enQuote: '"Create a Minimal Dev launch profile: keep a 16-slot hybrid dock, add a GitHub & localhost:3000 shelf, and hide tips."',
    zhMeta: 'lumakey_get_home_layout → lumakey_update_home_layout · 0ms 实时热刷新',
    enMeta: 'lumakey_get_home_layout → lumakey_update_home_layout · Instant Reload'
  },
  port: {
    zhQuote: '“输入 port 秒查本机监听端口与占用进程，支持按回车安全释放端口并弹出系统通知横幅。”',
    enQuote: '"Type port to inspect listening local ports and owning PIDs, press Return to free cleanly with a native notification."',
    zhMeta: 'scaffold → validate → Seatbelt 进程隔离实测 · 0ms 免重启挂载',
    enMeta: 'scaffold → validate → Seatbelt isolated test · Live in ⌥Space'
  }
};

const savedPluginsRaw = safeGetStorage('lumakey-enabled-plugins-v1');
let initialPlugins = ['ai-quota', 'translate-hub', 'browser-hub', 'quick-remind', 'mac-pilot'];
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

const state = {
  theme: safeGetStorage('lumakey-showcase-theme-v2', 'prism-pulse'),
  lang: safeGetStorage('lumakey-showcase-lang-v2', 'zh'),
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
  safeSetStorage('lumakey-enabled-plugins-v1', JSON.stringify([...state.enabledPlugins]));
}

document.querySelectorAll('[data-gh-path]').forEach((el) => {
  const sub = el.getAttribute('data-gh-path') || '';
  el.setAttribute('href', `${GH_HOST}${sub}`);
  el.setAttribute('target', '_blank');
  el.setAttribute('rel', 'noopener noreferrer');
});

/* --------------------------------------------------------------------------
   2. Bilingual Product Story Copy (Semantic Clause Grouping, Zero Orphan Wrap)
   -------------------------------------------------------------------------- */
const I18N = {
  zh: {
    nav_overview: '2D 图文详解',
    btn_play: '自动放映',
    btn_playing: '放映中',
    btn_replay: '重新放映',
    theme_dark: '暗曜',
    theme_light: '凝霜',
    nav_get: '获取 DMG',
    s0_eyebrow: 'APPLE SILICON NATIVE  ·  SWIFT 6  ·  PLUGIN V3.7  ·  16 MCP TOOLS',
    s0_title: '一触流光，|用完即焚。',
    s0_desc: '按一下 ⌥Space，找软件、搜文件、翻剪贴板、截屏识字一步直达；~从启动面板到专属插件皆可随心定制，松手即净不占后台。',
    s0_trigger: '体验 ⌥Space 瞬间唤醒',
    s0_scroll: '向下滚动了解五大核心能力 · 或点击右上角「自动放映」\u00a0↓',
    s1_eyebrow: '01 / 05  ·  CUSTOM LAUNCH PANEL & UNIFIED SEARCH',
    s1_title: '启动面板随心摆，\n一框秒搜全盘与日常。',
    s1_desc: '呼出瞬间就是你亲手布置的专属主页：大号 Bento 磁贴（2/3/4 列）、混排本机应用与常用目录的 8/16 格高频坞、多组命名书签胶囊架皆可自由开关排序，还能按「工作 / 极简 / 开发」切换多套场景面板。直接打字即可免前缀秒搜拼音应用、移动硬盘文件、剪贴板历史（支持 15 步撤回）、算账换算与开发小工具，880 × 544 固定视窗绝不乱跳。',
    s1_m1: '磁贴、混合坞、书签架自由编排，搜索结果右键一键钉上主页',
    s1_m2: 'LMKYIDX3 内存映射快照 + FSEvents 实时增量全盘秒搜',
    s1_m3: '收起 30s 销毁视图缓存、空闲 90s 卸载索引页，安静省电不赖内存',
    s1_link: '前往交互实验台在线切换启动面板布局与实时搜索',
    s2_eyebrow: '02 / 05  ·  DEEP CUSTOMIZATION & PLUGIN V3.7',
    s2_title: '从菜单栏到桌面挂件，\n装上即原生一等公民。',
    s2_desc: '不用的功能零内存、零后台打扰；常用的能力支持精简排序顶部菜单栏、改唤醒词、录不抢焦点的静默快捷键，还能开启 Plugin v3.7 无边框透明桌面悬浮窗（如支持紧凑折叠态的 AI 额度雷达）、跨应用划词即弹工具栏与双语朗读，内置一键安装 Python 3 向导，粘贴任意仓库链接经 SHA-256 核验订阅 8 款官方扩展：',
    s2_link: '进入模块化自由拼装台体验 8 款官方扩展详情',
    s3_eyebrow: '03 / 05  ·  BUILT-IN LUMAKEY-MCP (16 TOOLS)',
    s3_title: '不会写代码也能定制，\n一句话造插件排主页。',
    s3_desc: '安装包直接内置 lumakey-mcp 服务（16 项标准工具），免配环境一键接入 Claude Code、Cursor、Codex 与 Gemini CLI。无论是用大白话让 AI 替你写一个专属小工具，还是让它按你的习惯自动排好整套启动面板与书签架，几秒钟即可经 Seatbelt 沙箱实测并热重载生效：',
    f_pr: '一句话造插件 · PR 审查雷达',
    f_home: '一句话排主页 · 极简开发启动面板',
    f_port: '一句话管本机 · 端口秒查与安全释放',
    s3_trigger: '模拟 AI 自动编排与 350ms 热重载',
    s3_trigger_done: '✓ 已通过沙箱校验并实时热刷新至 ⌥Space',
    s3_link: '查阅全部 16 项内置 MCP 工具与安全沙箱闭环',
    s4_eyebrow: '04 / 05  ·  EVERYDAY NATIVE TOOLS & SWIFT 6 DAG',
    s4_title: '开箱即享五大原生利器，\n零依赖极客级纯粹架构。',
    s4_desc: '没装任何插件前，高频刚需就已一应俱全：多屏幕高清截图标注与单击窗口抠图贴屏（⌥A）、轻巧区域 GIF 录屏（⌥G）、一秒离线识字（⌥O）、不改触控板手感的物理鼠标 120Hz 平滑滚轮、双栏文件整理台（⌥E），以及按需查看芯片功耗（⌥M）、软件实时网速（⌥N）与秒开 Markdown / 4K 视频阅读窗——全部浓缩在约 10 MB 纯正原生安装包中。',
    s4_m1: '100% 纯原生 Swift 6 直连 Apple Silicon 框架，拒绝网页套壳臃肿',
    s4_m2: '九大单向无环模块分层，构建门禁每次严查单文件 ≤ 300 行',
    s4_m3: 'Seatbelt 内核沙箱、LMKYVLT2 256-bit 密钥箱与 WebDAV 加密备份',
    s4_link: '查阅九大模块架构蓝图与五大原生利器详解',
    s5_eyebrow: 'MACOS 14+  ·  APPLE SILICON ARM64  ·  ~10 MB  ·  MIT OPEN SOURCE',
    s5_title: '让每一次按键，|如流光掠影。',
    s5_desc: 'MIT 协议免费开源，内置「凝霜留白 / 霓彩流光」双视觉主题、中英双语免重启秒切、应用内自动升级保留本机权限与整机配置一键备份漫游。立即下载原生 DMG，或进入 2D 实验台亲手定制你的 Lumakey。',
    s5_cta_dmg: '下载 macOS 原生 DMG',
    s5_cta_home: '进入 2D 图文详解与定制实验台\u00a0→',
    p_hero: '启动面板与全搜模拟',
    p_builder: '全维度自由拼装台',
    p_mcp: 'AI 造插件与排主页',
    p_bento: '五大日常原生利器',
    p_arch: '极客 DAG 架构蓝图'
  },
  en: {
    nav_overview: '2D Overview',
    btn_play: 'Play Tour',
    btn_playing: 'Playing',
    btn_replay: 'Replay Tour',
    theme_dark: 'Obsidian',
    theme_light: 'Frost',
    nav_get: 'Get DMG',
    s0_eyebrow: 'APPLE SILICON NATIVE  ·  SWIFT 6  ·  PLUGIN V3.7  ·  16 MCP TOOLS',
    s0_title: 'Summon Light. |Leave Zero Trace.',
    s0_desc: 'Press ⌥Space to launch apps, search drives, browse clipboard history, or OCR your screen — ~customize every zone & plugin freely, with zero background bloat.',
    s0_trigger: 'Experience ⌥Space Instant Wake',
    s0_scroll: 'SCROLL TO EXPLORE 5 PILLARS · OR CLICK PLAY TOUR\u00a0↑',
    s1_eyebrow: '01 / 05  ·  CUSTOM LAUNCH PANEL & UNIFIED SEARCH',
    s1_title: 'Shape Your Launch Panel.\nSearch Everything in One Bar.',
    s1_desc: 'Open ⌥Space to a home screen built your way: arrange 2/3/4-column Bento tiles, an 8/16-slot hybrid Omni Dock mixing apps, bookmarks & folders, and up to 6 named pill shelves across switchable scene profiles. Type right away to search apps, external drives, clipboard history (15-step undo), unit math, and offline dev tools inside a zero-jitter 880 × 544 frame.',
    s1_m1: 'Reorder Bento, Omni Dock & shelves freely; right-click any result to pin',
    s1_m2: 'LMKYIDX3 zero-copy mmap snapshot + live FSEvents full-disk search',
    s1_m3: 'Tears down UI cache in 30s and unmaps index heap after 90s idle',
    s1_link: 'Switch Launch Panel Presets & Search Live in 2D',
    s2_eyebrow: '02 / 05  ·  DEEP CUSTOMIZATION & PLUGIN V3.7',
    s2_title: 'From Menu Bar to Glass HUD.\nFirst-Class Native Extensions.',
    s2_desc: 'Unused features take zero RAM or background polling. Trim and reorder the menu bar, customize keywords and silent global hotkeys, launch compact Plugin v3.7 glass HUDs (like AI Quota HUD), use the Selection Quick Bar & dual TTS, or install Python 3 in 1 click. Paste any repo URL for SHA-256 verified installs — toggle 8 official plugins below:',
    s2_link: 'Explore All 8 Official Extensions in the Workbench',
    s3_eyebrow: '03 / 05  ·  BUILT-IN LUMAKEY-MCP (16 TOOLS)',
    s3_title: 'No Coding Required.\nOne Sentence Builds Tools & Layouts.',
    s3_desc: 'Ships with an embedded lumakey-mcp server (16 JSON-RPC 2.0 tools) ready for Claude Code, Cursor, Codex, and Gemini CLI. Describe a custom tool or ask AI to arrange your entire Launch Panel and bookmark shelves — validated inside Seatbelt and hot-reloaded in milliseconds:',
    f_pr: 'Build Plugin · PR Review Radar',
    f_home: 'Arrange Home · Minimal Dev Launch Panel',
    f_port: 'Inspect Mac · Port Finder & Clean Release',
    s3_trigger: 'Simulate AI Orchestration & Live Reload',
    s3_trigger_done: '✓ Verified in Seatbelt & Hot-Reloaded to ⌥Space',
    s3_link: 'Explore All 16 MCP Tools & Sandbox Security',
    s4_eyebrow: '04 / 05  ·  EVERYDAY NATIVE TOOLS & SWIFT 6 DAG',
    s4_title: 'Five Everyday Tools Built In.\nPure Zero-Dependency Architecture.',
    s4_desc: 'Before installing a single plugin, everyday essentials are ready: multi-display HD capture & 1-click window cutouts (⌥A), lightweight GIF recording (⌥G), 1-second offline Vision OCR (⌥O), 120Hz smooth mouse wheel that leaves Trackpad untouched, dual-pane file workspace (⌥E), plus on-demand chip wattage (⌥M), app bandwidth (⌥N), and native Markdown / 4K video viewers in a ~10 MB app.',
    s4_m1: '100% pure Swift 6 atop Apple Silicon frameworks — zero web-wrapper bloat',
    s4_m2: '9 acyclic Swift targets with automated ≤ 300 LOC per-file build gates',
    s4_m3: 'Kernel Seatbelt sandbox, LMKYVLT2 256-bit vault & WebDAV backup',
    s4_link: 'Inspect 9-Module DAG Blueprint & 5 Native Tools',
    s5_eyebrow: 'MACOS 14+  ·  APPLE SILICON ARM64  ·  ~10 MB  ·  MIT OPEN SOURCE',
    s5_title: 'Every Keystroke, |Pure Velocity.',
    s5_desc: 'Free & open source under MIT with Pure Frost / Prism Pulse dual themes, instant bilingual switching, in-app DMG auto-updates preserving local permissions, and one-file encrypted backup across Macs. Download the native DMG or customize your Lumakey live in the 2D workbench.',
    s5_cta_dmg: 'Download Native macOS DMG',
    s5_cta_home: 'Open 2D Overview & Customizer\u00a0→',
    p_hero: 'Launch Panel Simulator',
    p_builder: 'Deep Custom Workbench',
    p_mcp: 'AI Plugin & Home Forge',
    p_bento: '5 Everyday Native Tools',
    p_arch: 'Geek DAG Architecture'
  }
};

/* --------------------------------------------------------------------------
   3. Curtain, Magnetic Cursor Ring & Editorial UI Bindings
   -------------------------------------------------------------------------- */
const bootVeil = document.getElementById('bootVeil');
const bootBarFill = document.getElementById('bootBarFill');
const timecodeIndex = document.getElementById('timecodeIndex');
const timecodeFill = document.getElementById('timecodeFill');
const stageMorphTag = document.getElementById('stageMorphTag');
const filmPlayBtn = document.getElementById('filmPlayBtn');
const filmPlayLabel = document.getElementById('filmPlayLabel');
const themeToggleBtn = document.getElementById('themeToggleBtn');
const themeToggleLabel = document.getElementById('themeToggleLabel');
const langToggleBtn = document.getElementById('langToggleBtn');
const pluginWhisperList = document.getElementById('pluginWhisperList');
const pluginSummaryLine = document.getElementById('pluginSummaryLine');
const forgePromptQuote = document.getElementById('forgePromptQuote');
const forgePromptMeta = document.getElementById('forgePromptMeta');
const igniteForgeText = document.getElementById('igniteForgeText');
const cursorAura = document.getElementById('cursorAura');
const cursorNodeLabel = document.getElementById('cursorNodeLabel');

function dismissBootVeil() {
  if (bootBarFill) bootBarFill.style.width = '100%';
  if (bootVeil) bootVeil.classList.add('ready');
}
setTimeout(dismissBootVeil, 1150);

let shaderBridge = {
  triggerPulse: () => {},
  triggerForgeCollapse: () => {},
  syncPluginMask: () => {},
  syncTheme: () => {}
};

function syncStageMorphLabel() {
  if (!stageMorphTag) return;
  const list = STAGE_LABELS[state.lang] || STAGE_LABELS.zh;
  stageMorphTag.textContent = list[state.activeScene] || list[0];
}

function renderForgePrompt() {
  const preset = FORGE_PRESETS[state.forgePreset] || FORGE_PRESETS.pr;
  const zh = state.lang === 'zh';
  if (forgePromptQuote) forgePromptQuote.textContent = zh ? preset.zhQuote : preset.enQuote;
  if (forgePromptMeta) forgePromptMeta.textContent = zh ? preset.zhMeta : preset.enMeta;
}

function renderPluginWhispers() {
  if (!pluginWhisperList) return;
  const zh = state.lang === 'zh';
  pluginWhisperList.innerHTML = PLUGINS.map((p, idx) => {
    const mounted = state.enabledPlugins.has(p.id);
    return `
      <button type="button" class="plugin-whisper-chip ${mounted ? 'mounted' : ''}" data-pid="${p.id}" data-pidx="${idx}">
        <span class="chip-dot"></span>
        <span>${zh ? p.zh : p.en}</span>
      </button>
    `;
  }).join('');

  if (pluginSummaryLine) {
    const n = state.enabledPlugins.size;
    pluginSummaryLine.textContent = zh
      ? `已按需启用 ${n} / 8 款扩展  ·  常驻守护进程：0  ·  Seatbelt 沙箱隔离`
      : `ACTIVE PLUGINS: ${n} / 8  ·  RESIDENT DAEMONS: 0  ·  SEATBELT ISOLATED`;
  }

  pluginWhisperList.querySelectorAll('[data-pid]').forEach((btn) => {
    btn.addEventListener('click', () => {
      const id = btn.getAttribute('data-pid');
      togglePluginById(id);
    });
  });
}

function togglePluginById(id) {
  if (state.enabledPlugins.has(id)) state.enabledPlugins.delete(id);
  else state.enabledPlugins.add(id);
  persistPlugins();
  renderPluginWhispers();
  shaderBridge.syncPluginMask();
  shaderBridge.triggerPulse(0.75);
}

function applyTheme(themeId) {
  state.theme = themeId;
  document.documentElement.setAttribute('data-theme', themeId);
  safeSetStorage('lumakey-showcase-theme-v2', themeId);
  const dict = I18N[state.lang];
  if (themeToggleLabel) {
    themeToggleLabel.textContent = themeId === 'pure-frost' ? dict.theme_light : dict.theme_dark;
  }
  shaderBridge.syncTheme(themeId);
}

function applyLanguage(lang) {
  state.lang = lang;
  document.documentElement.lang = lang === 'zh' ? 'zh-CN' : 'en';
  safeSetStorage('lumakey-showcase-lang-v2', lang);
  const dict = I18N[lang];

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

  if (langToggleBtn) langToggleBtn.textContent = lang === 'zh' ? 'EN' : '中文';
  if (themeToggleLabel) {
    themeToggleLabel.textContent = state.theme === 'pure-frost' ? dict.theme_light : dict.theme_dark;
  }
  syncPlayButtonUi();
  const tcTitles = STAGE_LABELS[lang] || STAGE_LABELS.zh;
  document.querySelectorAll('#timecodeDots .tc-dot').forEach((dot, idx) => {
    if (tcTitles[idx]) dot.setAttribute('title', tcTitles[idx]);
  });
  const rail = document.querySelector('.timecode-rail');
  if (rail) rail.setAttribute('aria-label', lang === 'zh' ? '产品章节导航' : 'Product chapter navigation');
  if (pluginWhisperList) {
    pluginWhisperList.setAttribute('aria-label', lang === 'zh' ? '插件按需挂载切换' : 'Toggle opt-in plugins');
  }
  document.title = lang === 'zh'
    ? '流光 Lumakey — 一触流光，用完即焚 (可深度定制的 Apple Silicon 原生效率中枢)'
    : 'Lumakey — Summon Light, Leave Zero Trace (Customizable Apple Silicon Native Hub)';

  syncStageMorphLabel();
  renderForgePrompt();
  renderPluginWhispers();
}

/* Cinema Keyframe Auto-Director: Snappy start on current scene, comfortable dwell on newly arrived scenes */
const SCENE_DWELL_SECONDS = [1.15, 3.6, 3.6, 3.6, 3.6, 0];
let autoPhase = 'hold'; // 'hold' | 'glide'
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

function computeSceneStops() {
  return cachedStops;
}

function easeInOutCubic(t) {
  return t < 0.5 ? 4 * t * t * t : 1 - Math.pow(-2 * t + 2, 3) / 2;
}

function syncPlayButtonUi() {
  const dict = I18N[state.lang] || I18N.zh;
  filmPlayBtn?.classList.toggle('playing', state.autoPlaying);
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

function startAutoPlayFromCurrent() {
  const stops = computeSceneStops();
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
  shaderBridge.triggerPulse(0.75);

  if (matchedIdx >= 0 && matchedIdx < stops.length - 1) {
    window.scrollTo(0, stops[matchedIdx]);
    if (rewoundFromBottom) {
      autoPhase = 'hold';
      autoSceneIdx = matchedIdx;
      autoCurrentHoldDur = SCENE_DWELL_SECONDS[0];
      autoStageTriggered = true;
    } else {
      autoPhase = 'hold';
      autoSceneIdx = matchedIdx;
      autoCurrentHoldDur = 0.32;
      autoStageTriggered = true;
    }
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
  if (idx === 0) shaderBridge.triggerPulse(0.85);
  else if (idx === 2) shaderBridge.triggerPulse(0.85);
  else if (idx === 3) shaderBridge.triggerForgeCollapse();
  else if (idx === 4) shaderBridge.triggerPulse(0.95);
}

function stepAutoPlay(dt) {
  if (!state.autoPlaying) return;
  const stops = computeSceneStops();
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
        shaderBridge.triggerPulse(1.2);
        return;
      }
      autoPhase = 'hold';
      autoPhaseTime = 0;
      autoCurrentHoldDur = SCENE_DWELL_SECONDS[autoSceneIdx] ?? 3.6;
      autoStageTriggered = false;
    }
  }
}

themeToggleBtn?.addEventListener('click', () => {
  applyTheme(state.theme === 'pure-frost' ? 'prism-pulse' : 'pure-frost');
});

langToggleBtn?.addEventListener('click', () => {
  applyLanguage(state.lang === 'zh' ? 'en' : 'zh');
});

filmPlayBtn?.addEventListener('click', () => {
  if (state.autoPlaying) {
    stopAutoPlay(false);
  } else {
    startAutoPlayFromCurrent();
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
  window.scrollTo({ top: 0, behavior: 'smooth' });
});

document.querySelectorAll('[data-jump]').forEach((dot) => {
  dot.addEventListener('click', () => {
    stopAutoPlay(false);
    const idx = Number(dot.getAttribute('data-jump'));
    document.getElementById(`sec-${idx}`)?.scrollIntoView({ behavior: 'smooth' });
  });
});

document.getElementById('heroPulseBtn')?.addEventListener('click', () => {
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
  btn.addEventListener('click', () => {
    state.forgePreset = btn.getAttribute('data-forge');
    document.querySelectorAll('[data-forge]').forEach((b) => b.classList.toggle('active', b === btn));
    renderForgePrompt();
    shaderBridge.triggerForgeCollapse();
    flashForgeSuccess();
  });
});

document.getElementById('igniteForgeBtn')?.addEventListener('click', () => {
  shaderBridge.triggerForgeCollapse();
  flashForgeSuccess();
});

window.addEventListener('keydown', (e) => {
  if ((e.altKey && e.code === 'Space') || e.key === '/') {
    e.preventDefault();
    shaderBridge.triggerPulse(1.3);
  } else if (e.key >= '1' && e.key <= '6') {
    document.getElementById(`sec-${Number(e.key) - 1}`)?.scrollIntoView({ behavior: 'smooth' });
  }
});

applyTheme(state.theme);
applyLanguage(state.lang);

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
   4. Scroll-Scrubbed Optical Depth-of-Field Kinetic Typography Engine
   -------------------------------------------------------------------------- */
const sceneSections = Array.from(document.querySelectorAll('.film-scene'));
const timecodeDotEls = Array.from(document.querySelectorAll('.tc-dot'));
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
    timecodeFill.style.transform = `scaleY(${Math.max(0.04, state.scrollNorm).toFixed(4)})`;
  }

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
      const fadeDist = Math.max(0, (absOff - 0.38) / 0.68);
      const alpha = Math.max(0, Math.min(1, 1 - Math.pow(fadeDist, 1.45)));
      const scale = 1 - Math.min(0.035, fadeDist * 0.035);
      const driftY = absOff <= 0.38
        ? normOffset * -7
        : Math.sign(normOffset) * (-2.66 - (absOff - 0.38) * 26);
      copy.style.opacity = alpha.toFixed(3);
      copy.style.transform = `translate3d(0, ${driftY.toFixed(1)}px, 0) scale(${scale.toFixed(4)})`;
    }
  });

  if (closestIdx !== state.activeScene) {
    state.activeScene = closestIdx;
    if (timecodeIndex) {
      timecodeIndex.textContent = String(closestIdx).padStart(2, '0');
    }
    timecodeDotEls.forEach((d, i) => d.classList.toggle('active', i === closestIdx));
    syncStageMorphLabel();
  }
}

refreshLayoutMetrics();
window.addEventListener('scroll', updateScrollAndKineticDOM, { passive: true });
window.addEventListener('resize', () => {
  refreshLayoutMetrics();
  updateScrollAndKineticDOM();
});
window.addEventListener('load', () => {
  refreshLayoutMetrics();
  updateScrollAndKineticDOM();
});
updateScrollAndKineticDOM();

/* --------------------------------------------------------------------------
   5. Six-Stage Mathematical 3D Point-Cloud Sculptures
   -------------------------------------------------------------------------- */
function generateSixMorphForms(count) {
  const form0 = new Float32Array(count * 3); // 00: Liquid Droplet Halo + Wide Caustic Water Mirror
  const form1 = new Float32Array(count * 3); // 01: 4 Parallel Z-Stacked 880:544 Superellipse Sheets
  const form2 = new Float32Array(count * 3); // 02: 8-Fold Orbital Corona + 16 Double-Helix Filaments
  const form3 = new Float32Array(count * 3); // 03: Tilted 5-Arm Relativistic Black-Hole Accretion Funnel
  const form4 = new Float32Array(count * 3); // 04: Sharp Octahedral Spire & 4-Tier Sacred DAG Lattice
  const form5 = new Float32Array(count * 3); // 05: Expansive Solar-Eclipse Corona Ring & Rising Motes
  const seeds = new Float32Array(count * 4); // [phase, clusterOrLayerIdx, uNorm, rand]

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

    const clusterIdx = i % 8;
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
      const gx = (rA * 2 - 1) * (aW * 0.82);
      const gy = (rC * 2 - 1) * (aH * 0.82);
      form1[i3] = gx;
      form1[i3 + 1] = gy;
      form1[i3 + 2] = zBase;
    }

    /* FORM 2: 8-Fold Astrolabe Corona + Double-Helix Host Bridges (Outside Core!) */
    const cAngle = (clusterIdx / 8) * Math.PI * 2;
    const orbitR = 3.35;
    const cx = Math.cos(cAngle) * orbitR;
    const cy = Math.sin(cAngle) * orbitR * 0.85;
    const cz = Math.sin(cAngle * 2.0) * 0.72;

    if (rB < 0.52) {
      const localR = 0.24 + Math.pow(rC, 0.6) * 0.48;
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
      const perpR = Math.sin(uHelix * Math.PI) * 0.22;
      form2[i3] = cx * s + Math.cos(helixA) * perpR * strand;
      form2[i3 + 1] = cy * s + Math.sin(helixA) * perpR * strand;
      form2[i3 + 2] = cz * s + Math.sin(uHelix * Math.PI) * 0.30;
    }

    /* FORM 3: Dramatic Tilted 5-Arm Black-Hole Accretion Funnel (Clear of Core!) */
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

    /* FORM 4: 4-Tier Sacred Acyclic Crystal Lattice Framing Central Diamond */
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

    /* FORM 5: Finale Solar-Eclipse Corona Ring & Rising Stardust */
    const ringR = 2.35 + Math.pow(rB, 1.8) * 3.6;
    const ringA = rA * Math.PI * 2;
    form5[i3] = Math.cos(ringA) * ringR;
    form5[i3 + 1] = Math.sin(ringA) * ringR * 0.88;
    form5[i3 + 2] = (rC - 0.5) * (0.4 + (ringR - 2.35) * 0.8);
  }

  return { form0, form1, form2, form3, form4, form5, seeds };
}

/* --------------------------------------------------------------------------
   6. Fast Multi-Mirror Three.js Loader & Stage Positioning
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
  const anchors = [0.0, 2.42, -2.42, 2.42, -2.42, 0.0];
  const scaled = Math.max(0, Math.min(5, state.sceneProgress));
  const i0 = Math.floor(scaled);
  const i1 = Math.min(5, i0 + 1);
  const f = scaled - i0;
  return anchors[i0] + (anchors[i1] - anchors[i0]) * f;
}

function getTargetSculptureOffsetY() {
  const anchors = [0.92, 0.06, 0.06, 0.06, 0.06, 1.18];
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
   7A. Primary WebGL2 Six-Morphology Shader + Studio Lighting & Force-Field
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

  /* Studio Three-Point Lighting Rig (Synced with Core Shader keyL / fillL!)
     Ensures Stage 02 Crystal Satellites, Stage 03 Metallic Rings & Stage 04 DAG
     Diamond Nodes exhibit crisp 3D facet shading, clearcoat glints & shadows. */
  const hemiLight = new THREE.HemisphereLight(0xdbeafe, 0x090d1f, 1.4);
  scene.add(hemiLight);

  const keyLight = new THREE.DirectionalLight(0xffffff, 2.8);
  keyLight.position.set(4.8, 7.2, 6.4);
  scene.add(keyLight);

  const rimLight = new THREE.DirectionalLight(0x818cf8, 1.5);
  rimLight.position.set(-5.6, -2.6, -4.2);
  scene.add(rimLight);

  const rootGroup = new THREE.Group();
  scene.add(rootGroup);

  /* 1. World-Space Decoupled Spectral Halation Plane (Strictly Behind Sculpture!)
        Mounted directly on `scene` with renderOrder = -10 and depthTest = false so
        rootGroup / dragYaw rotation NEVER swings the plane across coreMesh or flips
        transparent painter's sort order. */
  const haloUniforms = {
    uTime: { value: 0 },
    uMorph: { value: 0 },
    uLightMode: { value: state.theme === 'pure-frost' ? 1.0 : 0.0 },
    uPulse: { value: 0 }
  };
  const haloMat = new THREE.ShaderMaterial({
    uniforms: haloUniforms,
    transparent: true,
    depthTest: false,
    depthWrite: false,
    blending: state.theme === 'pure-frost' ? THREE.NormalBlending : THREE.AdditiveBlending,
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

      vec3 stageTint(float m) {
        vec3 c0 = vec3(0.08, 0.56, 0.96); // 00 Cyan-Sapphire
        vec3 c1 = vec3(0.12, 0.78, 0.92); // 01 Arctic Lens
        vec3 c2 = vec3(0.62, 0.28, 0.96); // 02 Amethyst Corona
        vec3 c3 = vec3(0.96, 0.36, 0.42); // 03 Solar-Rose Forge
        vec3 c4 = vec3(0.08, 0.76, 0.58); // 04 Emerald-Cyan Diamond
        vec3 c5 = vec3(0.38, 0.52, 0.98); // 05 Celestial Halo
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

        // Preserve world-space glow scale around sculpture while guaranteeing
        // C2-smooth zero value & zero gradient strictly inside the circular support!
        float rWorld = rNorm * (10.0 / 5.1);
        float glowA = exp(-rWorld * rWorld * 3.8);
        float glowB = exp(-rWorld * rWorld * 1.45) * 0.36;
        float radialWindow = smoothstep(0.96, 0.28, rNorm);
        radialWindow *= radialWindow;

        vec3 col = stageTint(uMorph);
        float rawAlpha = (glowA * 0.30 + glowB * 0.20) * radialWindow
                       * (1.0 + uPulse * 0.72) * mix(1.0, 0.22, uLightMode);
        float ditherMask = smoothstep(0.0, 0.012, rawAlpha);
        float dither = (fract(sin(dot(gl_FragCoord.xy, vec2(12.9898, 78.233))) * 43758.5453) - 0.5)
                     * 0.004 * ditherMask;
        float alpha = max(0.0, rawAlpha + dither);
        if (alpha <= 0.00012) discard;
        gl_FragColor = vec4(col, alpha);
      }
    `
  });
  const haloMesh = new THREE.Mesh(new THREE.PlaneGeometry(20.0, 20.0), haloMat);
  haloMesh.position.set(0, 0.92, -2.4);
  haloMesh.renderOrder = -10;
  scene.add(haloMesh);

  /* 2. Six-Surface Parametric Chromatic-Dispersion & Cavity-Shaded Core Shader */
  const coreNormalMat = new THREE.Matrix3();
  const coreUniforms = {
    uTime: { value: 0 },
    uMorph: { value: 0 },
    uPulse: { value: 0 },
    uHoldCharge: { value: 0 },
    uForgePinch: { value: 0 },
    uLightMode: { value: state.theme === 'pure-frost' ? 1.0 : 0.0 },
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

      // Exact 6-Stage Parametric 3D Surface + Analytical Cavity Prominence Evaluator
      vec3 evalCoreSurface(vec3 d, float m, float t, out float outCavity) {
        // S0: Breathing Liquid Prismatic Droplet
        float w0 = sin(d.x * 3.2 + t * 1.3) * cos(d.y * 3.2 - t * 1.0) * 0.11
                 + sin(d.z * 4.0 + t * 0.9) * 0.06;
        vec3 s0 = d * (1.28 + w0);
        float c0 = clamp(0.72 + w0 * 1.8, 0.35, 1.0);

        // S1: 880 : 544 Rounded Superellipse Optical Glass Tablet (2.06 x 1.27 x 0.24)
        vec3 q1 = abs(d) / vec3(2.06, 1.27, 0.24);
        float denom1 = pow(pow(q1.x, 5.0) + pow(q1.y, 5.0) + pow(q1.z, 5.0), 0.2);
        vec3 s1 = d / max(denom1, 1e-4);
        s1.z += sin(s1.x * 2.2 + t * 1.5) * 0.032;
        float c1 = clamp(0.76 + 0.24 * abs(d.z), 0.58, 1.0);

        // S2: Sculpted 8-Petal Astrolabe Star-Crown
        float angXY = atan(d.y, d.x);
        float petalWave = cos(angXY * 8.0 - t * 0.8);
        float petal = 1.24 + 0.38 * petalWave;
        vec3 s2 = vec3(d.xy * petal, d.z * (0.46 + 0.14 * petalWave));
        float c2 = clamp(0.54 + 0.46 * petalWave, 0.14, 1.0);

        // S3: Twisted Tri-Lobe Spiral Helicoid Forge
        float twist = d.y * 4.2 - t * 2.1;
        float angXZ = atan(d.z, d.x);
        float lobeWave = sin(angXZ * 3.0 + twist);
        float lobe = 1.02 + 0.40 * lobeWave;
        vec3 s3 = vec3(d.x * lobe, d.y * 1.58, d.z * lobe);
        float c3 = clamp(0.52 + 0.48 * lobeWave, 0.12, 1.0);

        // S4: Sleek Micro-Chamfered Octahedral Diamond Spire (0.84 x 1.30 x 0.84, Zero Silhouette Sawtooth)
        vec3 ad4 = sqrt(d * d + vec3(0.00042));
        float octNorm = ad4.x / 0.84 + ad4.y / 1.30 + ad4.z / 0.84;
        vec3 s4 = d / max(octNorm, 1e-4);
        float minAxis = min(min(abs(s4.x), abs(s4.y) * 0.64), abs(s4.z));
        float c4 = clamp(1.0 - smoothstep(0.0, 0.38, minAxis) * 0.18, 0.78, 1.0);

        // S5: Serene Solar-Eclipse Corona Ring-Disc
        float corWave = sin(angXY * 12.0 + t * 1.2);
        float ringWave = 1.66 + 0.10 * corWave;
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

        // Cursor Magnetic Ripple + Gravity Hold Stretch + Pulse Wave
        float ptrDist = length(p - uPointerLocal);
        float ptrWave = sin(ptrDist * 5.5 - t * 5.0) * exp(-ptrDist * 1.1) * 0.08;
        vec3 pullVec = (uPointerLocal - p) * exp(-ptrDist * 0.55) * uHoldCharge * 0.25;
        float pulseBurst = uPulse * 0.18 * sin(d.y * 8.0 + t * 9.0);

        p = p * (1.0 - uForgePinch * 0.38) + d * (ptrWave + pulseBurst) + pullVec;
        return p;
      }

      // Branchless Pixar Orthonormal Basis (Duff et al. 2017): cross(b1, b2) == +n everywhere
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

        // Central finite difference on oriented tangent plane -> exact outward normal
        // without radial dot(surfN, dir) < 0 sign-flip seams on steep overhanging lobes!
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

      vec3 stageAccent(float m) {
        vec3 a0 = vec3(0.14, 0.74, 0.98);
        vec3 a1 = vec3(0.20, 0.86, 0.98);
        vec3 a2 = vec3(0.70, 0.38, 0.98);
        vec3 a3 = vec3(0.98, 0.48, 0.34);
        vec3 a4 = vec3(0.10, 0.86, 0.68);
        vec3 a5 = vec3(0.42, 0.68, 1.00);
        if (m < 1.0) return mix(a0, a1, m);
        if (m < 2.0) return mix(a1, a2, m - 1.0);
        if (m < 3.0) return mix(a2, a3, m - 2.0);
        if (m < 4.0) return mix(a3, a4, m - 3.0);
        return mix(a4, a5, clamp(m - 4.0, 0.0, 1.0));
      }

      // Full-Sphere 360-Degree Studio Environment (Front Reflection + Rear Transmission Softboxes)
      vec3 studioEnv(vec3 dir, float lightMode, vec3 accent) {
        float up = clamp(dir.y * 0.5 + 0.5, 0.0, 1.0);
        float frontSoftA = smoothstep(0.76, 0.992, dot(dir, normalize(vec3(0.48, 0.72, 0.64))));
        float frontSoftB = smoothstep(0.72, 0.98, dot(dir, normalize(vec3(-0.62, -0.18, 0.56))));
        float rearTransA = smoothstep(0.35, 0.94, dot(dir, normalize(vec3(-0.28, -0.32, -0.90))));
        float rearTransB = smoothstep(0.42, 0.95, dot(dir, normalize(vec3(0.45, 0.48, -0.75))));

        vec3 darkEnv = mix(vec3(0.032, 0.052, 0.125), vec3(0.085, 0.175, 0.36), up);
        darkEnv += accent * (rearTransA * 0.52 + rearTransB * 0.34);
        darkEnv += accent.bgr * frontSoftB * 0.28;
        darkEnv += vec3(1.0) * frontSoftA * 1.05;

        vec3 lightEnv = mix(vec3(0.76, 0.83, 0.94), vec3(0.97, 0.985, 1.0), up);
        lightEnv += accent * (rearTransA * 0.18 + frontSoftB * 0.15);
        lightEnv += vec3(1.0) * frontSoftA * 0.45;

        return mix(darkEnv, lightEnv, lightMode);
      }

      void main() {
        // Analytical micro-beveled octahedral facet normal in Stage 04 (zero mesh saw-tooth!)
        float s4Weight = smoothstep(0.12, 0.88, 1.0 - clamp(abs(uMorph - 4.0), 0.0, 1.0));
        vec3 smoothN = normalize(vSmoothNormal);
        vec3 octLocalN = normalize(softSign(vLocalPos, 36.0) / vec3(0.84, 1.30, 0.84));
        vec3 octWorldN = normalize(uCoreNormalMat * octLocalN);
        vec3 N = normalize(mix(smoothN, octWorldN, s4Weight * 0.92));

        vec3 V = normalize(cameraPosition - vWorldPos);
        if (dot(N, V) < -0.25) N = normalize(mix(N, V, 0.35));

        vec3 accent = stageAccent(uMorph);
        float ao = mix(0.34, 1.0, clamp(vCavity, 0.0, 1.0));

        // Studio Key (Top-Right-Front) & Cool Fill (Bottom-Left) Directional Rig
        vec3 keyL = normalize(vec3(0.48, 0.72, 0.64));
        vec3 fillL = normalize(vec3(-0.62, -0.22, 0.52));
        float ndl = dot(N, keyL);
        float keyWrap = clamp((ndl + 0.36) / 1.36, 0.0, 1.0);
        float fillWrap = clamp((dot(N, fillL) + 0.30) / 1.30, 0.0, 1.0);

        // Stage 00 Caustic Water-Mirror Upward Bounce Light on Lower Hemisphere
        float s0Weight = clamp(1.0 - uMorph, 0.0, 1.0);
        float waterBounce = s0Weight * clamp(-N.y * 0.85 + 0.15, 0.0, 1.0);

        // Stage 05 Solar-Eclipse Corona Weight (Velvety Umbra Core + Radiant Rim)
        float s5Weight = clamp(uMorph - 4.0, 0.0, 1.0);

        // Chromatic Dispersion (RGB IOR Separation)
        vec3 rDir = refract(-V, N, 1.0 / 1.35);
        vec3 gDir = refract(-V, N, 1.0 / 1.44);
        vec3 bDir = refract(-V, N, 1.0 / 1.54);
        vec3 refracted = vec3(
          studioEnv(rDir, uLightMode, accent).r,
          studioEnv(gDir, uLightMode, accent).g,
          studioEnv(bDir, uLightMode, accent).b
        );

        float ndv = clamp(dot(N, V), 0.0, 1.0);
        float fresnel = pow(1.0 - ndv, 2.75);
        vec3 reflDir = reflect(-V, N);
        vec3 reflected = studioEnv(reflDir, uLightMode, accent);

        vec3 iridescence = 0.5 + 0.5 * cos(vec3(0.0, 2.1, 4.2) + ndv * 6.4 + vDisp * 6.5 + uTime * 0.55);

        // Self-shadowed Blinn-Phong Studio Specular (Broad Sheen + Crisp Clearcoat)
        vec3 halfV = normalize(keyL + V);
        float specMask = smoothstep(-0.10, 0.38, ndl) * ao;
        float softSheen = pow(max(dot(N, halfV), 0.0), 22.0) * 0.28 * specMask;
        float coatSpec = pow(max(dot(N, halfV), 0.0), 108.0) * 1.18 * specMask;

        // Dark Theme: Intuitive Key-Lit Translucent Crystal + Cavity-Occluded Rim
        vec3 darkShadowTone = mix(vec3(0.022, 0.036, 0.088), accent * 0.16, 0.35 + fillWrap * 0.35);
        vec3 darkLitTone = mix(refracted, accent * 0.62 + vec3(0.14, 0.20, 0.34), 0.36);
        vec3 darkBody = mix(darkShadowTone, darkLitTone, keyWrap) * ao;
        darkBody += accent * waterBounce * 0.24 * ao;
        // Solar-eclipse velvety central umbra in Stage 05
        darkBody *= mix(1.0, mix(0.28, 1.0, fresnel), s5Weight * 0.72);

        float rimDirGate = mix(mix(0.30, 1.0, keyWrap) * ao, 0.92, s5Weight * 0.75);
        vec3 darkRim = mix(accent, iridescence, 0.42) * fresnel * rimDirGate
                     * (1.08 + uPulse * 1.15 + uHoldCharge * 0.95 + s5Weight * 0.45);
        vec3 darkFinal = mix(darkBody, reflected * ao, fresnel * 0.44)
                       + darkRim
                       + accent * softSheen
                       + vec3(coatSpec);

        // Light Theme (Pure Frost): Porcelain Alabaster Crystal with Beer-Lambert Edge & Shadow Depth
        vec3 frostLit = mix(refracted, vec3(0.95, 0.975, 1.0), 0.45);
        vec3 frostShadow = mix(vec3(0.56, 0.65, 0.80), accent * 0.72, 0.38);
        vec3 frostBody = mix(frostShadow, frostLit, 0.26 + 0.74 * keyWrap) * mix(0.68, 1.0, ao);
        vec3 frostEdgeAbsorb = mix(vec3(0.42, 0.54, 0.74), accent * 0.68, 0.52);
        vec3 frostFinal = mix(frostBody, frostEdgeAbsorb, fresnel * 0.52);
        frostFinal += mix(accent, iridescence, 0.35) * fresnel * keyWrap * (0.24 + uPulse * 0.45);
        frostFinal += vec3(coatSpec * 0.85 + softSheen * 0.45);

        vec3 finalCol = mix(darkFinal, frostFinal, uLightMode);
        float finalAlpha = mix(0.92, 0.90, uLightMode);
        gl_FragColor = vec4(finalCol, finalAlpha);
      }
    `
  });

  const coreMesh = new THREE.Mesh(coreGeo, coreMat);
  coreMesh.renderOrder = 1;
  rootGroup.add(coreMesh);

  /* 3. Stage-Specific Sculptural Companions:
        - Stage 02: 8 Raycastable Refractive Crystal Satellites
        - Stage 03: 3 Precessing Metallic Gyroscopic Forge Rings
        - Stage 04: 7 Raycastable Diamond DAG Nodes */
  const raycastTargets = [];

  // 8 Plugin Crystal Satellites (Emerge in Stage 02!)
  const satGroup = new THREE.Group();
  satGroup.renderOrder = 2;
  rootGroup.add(satGroup);
  const satGeo = new THREE.OctahedronGeometry(0.23, 0);
  const satRecords = PLUGINS.map((p, i) => {
    const mat = new THREE.MeshPhysicalMaterial({
      color: p.color,
      emissive: p.color,
      emissiveIntensity: 0.22,
      roughness: 0.12,
      metalness: 0.18,
      clearcoat: 1.0,
      clearcoatRoughness: 0.08,
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

  // 3 Metallic Gyroscopic Rings (Emerge & Precess Fast in Stage 03!)
  const gyroGroup = new THREE.Group();
  gyroGroup.renderOrder = 2;
  rootGroup.add(gyroGroup);
  const gyroRings = [
    { r: 2.05, col: 0xf59e0b },
    { r: 2.55, col: 0xec4899 },
    { r: 3.05, col: 0x8b5cf6 }
  ].map(({ r, col }, idx) => {
    const mat = new THREE.MeshStandardMaterial({
      color: col,
      emissive: col,
      emissiveIntensity: 0.30,
      roughness: 0.20,
      metalness: 0.76,
      transparent: true,
      opacity: 0
    });
    const mesh = new THREE.Mesh(new THREE.TorusGeometry(r, 0.024, 14, 108), mat);
    mesh.renderOrder = 2;
    mesh.rotation.set(idx * 0.7, idx * 0.5, 0);
    gyroGroup.add(mesh);
    return { mesh, mat };
  });

  // 7 DAG Crystal Nodes (Emerge in Stage 04!)
  const dagGroup = new THREE.Group();
  dagGroup.renderOrder = 2;
  rootGroup.add(dagGroup);
  const dagNodeGeo = new THREE.OctahedronGeometry(0.20, 0);
  const dagRecords = DAG_NODES.map((d, i) => {
    const mat = new THREE.MeshPhysicalMaterial({
      color: d.color,
      emissive: d.color,
      emissiveIntensity: 0.24,
      roughness: 0.10,
      metalness: 0.18,
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

  /* 4. 3D Luminous Cursor Ribbon Trail (64 Spring-Inertial Vertices!) */
  const TRAIL_LEN = 64;
  const trailPoints = Array.from({ length: TRAIL_LEN }, () => new THREE.Vector3(0, 0, 0));
  const trailPosArr = new Float32Array(TRAIL_LEN * 3);
  const trailAlphaArr = new Float32Array(TRAIL_LEN);
  for (let i = 0; i < TRAIL_LEN; i++) trailAlphaArr[i] = 1.0 - i / TRAIL_LEN;

  const trailGeo = new THREE.BufferGeometry();
  trailGeo.setAttribute('position', new THREE.BufferAttribute(trailPosArr, 3));
  trailGeo.setAttribute('aAlpha', new THREE.BufferAttribute(trailAlphaArr, 1));
  const trailUniforms = {
    uOpacity: { value: 0 },
    uColor: { value: new THREE.Color(0x7dd3fc) }
  };
  const trailMat = new THREE.ShaderMaterial({
    uniforms: trailUniforms,
    transparent: true,
    depthWrite: false,
    blending: state.theme === 'pure-frost' ? THREE.NormalBlending : THREE.AdditiveBlending,
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
      uniform vec3 uColor;
      varying float vA;
      void main() {
        gl_FragColor = vec4(uColor, pow(vA, 1.8) * uOpacity);
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

  const pluginMaskArray = new Float32Array(8);
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
    uLightMode: { value: state.theme === 'pure-frost' ? 1.0 : 0.0 },
    uPluginMask: { value: pluginMaskArray }
  };

  const pMat = new THREE.ShaderMaterial({
    uniforms: pUniforms,
    transparent: true,
    depthWrite: false,
    blending: state.theme === 'pure-frost' ? THREE.NormalBlending : THREE.AdditiveBlending,
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
      uniform float uPluginMask[8];

      varying vec3 vColor;
      varying float vAlpha;

      float getMask(int idx) {
        for (int k = 0; k < 8; k++) {
          if (k == idx) return uPluginMask[k];
        }
        return 1.0;
      }

      void main() {
        float m = clamp(uMorph, 0.0, 5.0);

        // Stage 00 Dynamic Concentric Water Ripple + Droplet Contact Shadow & Caustic Ring
        vec3 p0 = position;
        float r0 = length(p0.xz);
        float waterContactShade = 1.0;
        float waterCausticRing = 0.0;
        if (p0.y < -0.5) {
          p0.y = -0.95 + sin(r0 * 3.2 - uTime * 2.4) * 0.16 * exp(-r0 * 0.18);
          float s0Vis = clamp(1.0 - m, 0.0, 1.0);
          waterContactShade = mix(1.0, 0.42 + 0.58 * smoothstep(0.35, 1.55, r0), s0Vis);
          waterCausticRing = exp(-pow(r0 - 1.52, 2.0) * 4.2) * 0.42 * s0Vis;
        }

        // Stage 01 Cursor-Driven 4-Layer Z-Explosion Fan-Out!
        vec3 p1 = aPos1;
        p1.z *= (1.0 + uLayerSpread * 1.45);

        vec3 baseP;
        if (m < 1.0) baseP = mix(p0, p1, smoothstep(0.0, 1.0, m));
        else if (m < 2.0) baseP = mix(p1, aPos2, smoothstep(1.0, 2.0, m));
        else if (m < 3.0) baseP = mix(aPos2, aPos3, smoothstep(2.0, 3.0, m));
        else if (m < 4.0) baseP = mix(aPos3, aPos4, smoothstep(3.0, 4.0, m));
        else baseP = mix(aPos4, aPos5, smoothstep(4.0, 5.0, m));

        // Stage 02 Plugin Corona Mask
        float coronaWeight = 1.0 - clamp(abs(m - 2.0), 0.0, 1.0);
        int cIdx = int(floor(aSeed.y + 0.5));
        float pMask = getMask(cIdx);
        if (coronaWeight > 0.01) {
          baseP *= mix(1.0, mix(1.42, 1.0, pMask), coronaWeight);
        }

        // Stage 03 Smooth Monotonic Accretion Spin & C1-Continuous Forge Pinch
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

        // Subtle Curl Breathing
        baseP += vec3(
          sin(baseP.y * 1.5 + uTime * 0.8 + aSeed.x),
          cos(baseP.z * 1.5 - uTime * 0.7 + aSeed.x),
          sin(baseP.x * 1.5 + uTime * 0.6 + aSeed.x)
        ) * 0.065;

        vec4 worldPos = modelMatrix * vec4(baseP, 1.0);

        // Rich Mouse Force-Field + Core Keep-Out Deflection Shield (Zero Particle Embedding!):
        float dagKeep = 1.0 - clamp(abs(m - 4.0), 0.0, 1.0);
        vec3 toPtr = worldPos.xyz - uPointer;
        float ptrDist = length(toPtr);
        float nearField = exp(-ptrDist * ptrDist * 0.45);
        vec3 tangent = normalize(cross(toPtr + vec3(0.001), vec3(0.0, 0.0, 1.0)));

        worldPos.xyz += (normalize(toPtr + vec3(0.001)) * 0.36 + tangent * 0.48) * nearField * (1.0 - uHoldCharge);
        worldPos.xyz += uPointerVel * nearField * 0.14;

        float gravityField = exp(-ptrDist * 0.42) * uHoldCharge;
        float gravScale = mix(1.0, 0.38, dagKeep);
        worldPos.xyz += (-toPtr * 0.68 + tangent * 1.35) * (gravityField * gravScale);

        float ringDelta = abs(length(baseP) - uShockRadius);
        float shock = exp(-ringDelta * ringDelta * 3.2) * uShockStrength;
        worldPos.xyz += normalize(baseP + vec3(0.001)) * shock * 0.72;

        // Smooth 3D Keep-Out Shield around Central Core so particles flow around, never inside!
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

        // Stage-Specific Chromatic Palettes!
        float h = fract(aSeed.z * 2.1 + uTime * 0.03);
        vec3 pal0 = mix(vec3(0.14, 0.78, 0.98), vec3(0.35, 0.42, 0.96), h);
        vec3 pal1 = mix(vec3(0.18, 0.88, 0.98), vec3(0.75, 0.92, 1.00), h);
        vec3 pal2 = mix(vec3(0.68, 0.32, 0.98), vec3(0.96, 0.36, 0.72), h);
        vec3 pal3 = mix(vec3(0.98, 0.62, 0.16), vec3(0.96, 0.26, 0.56), h);
        vec3 pal4 = mix(vec3(0.08, 0.88, 0.64), vec3(0.22, 0.76, 0.98), h);
        vec3 pal5 = mix(vec3(0.36, 0.68, 1.00), vec3(0.82, 0.56, 0.98), h);

        vec3 darkCol;
        if (m < 1.0) darkCol = mix(pal0, pal1, m);
        else if (m < 2.0) darkCol = mix(pal1, pal2, m - 1.0);
        else if (m < 3.0) darkCol = mix(pal2, pal3, m - 2.0);
        else if (m < 4.0) darkCol = mix(pal3, pal4, m - 3.0);
        else darkCol = mix(pal4, pal5, clamp(m - 4.0, 0.0, 1.0));

        vec3 lightCol = darkCol * 0.62;
        vec3 col = mix(darkCol, lightCol, uLightMode) * waterContactShade;

        float dagWeight = 1.0 - clamp(abs(m - 4.0), 0.0, 1.0);
        float dagPulse = dagWeight * pow(0.5 + 0.5 * sin(baseP.y * 3.2 + uTime * 3.6), 3.0);

        col += vec3(0.95, 0.55, 0.85) * gravityField * 1.1;
        col += vec3(0.55, 0.88, 1.0) * (shock * 1.5 + nearField * 0.65 + dagPulse * 0.6 + waterCausticRing);

        vColor = col;
        float baseAlpha = mix(0.78, 0.60, uLightMode) * (0.48 + 0.52 * sin(uTime * 1.7 + aSeed.x)) * waterContactShade;
        baseAlpha *= mix(1.0, pMask, coronaWeight);
        vAlpha = clamp(baseAlpha + shock * 0.55 + nearField * 0.35 + gravityField * 0.5 + waterCausticRing * 0.4, 0.04, 1.0);

        float depthScale = clamp(11.0 / max(1.5, -mvPos.z), 0.35, 2.8);
        float sizeBoost = 1.0 + shock * 1.35 + nearField * 0.85 + gravityField * 1.1 + dagPulse * 0.65;
        gl_PointSize = (1.55 + aSeed.w * 2.35) * uPixelRatio * depthScale * sizeBoost;
      }
    `,
    fragmentShader: `
      varying vec3 vColor;
      varying float vAlpha;
      void main() {
        vec2 uv = gl_PointCoord - 0.5;
        float r = length(uv) * 2.0;
        if (r > 1.0) discard;
        float core = exp(-r * r * 4.2);
        float halo = smoothstep(1.0, 0.0, r) * 0.38;
        gl_FragColor = vec4(vColor, (core + halo) * vAlpha);
      }
    `
  });

  const particleCloud = new THREE.Points(pGeo, pMat);
  particleCloud.renderOrder = 3;
  rootGroup.add(particleCloud);

  /* ------------------------------------------------------------------------
     Interactive State: Cursor Physics, Gravity Charge, Raycasting & Springs
     ------------------------------------------------------------------------ */
  let morphCurrent = getMorphStage(state.scrollNorm);
  let offsetXCurrent = getTargetSculptureOffsetX(state.scrollNorm);
  let offsetXVel = 0;
  let offsetYCurrent = getTargetSculptureOffsetY(state.scrollNorm);
  let offsetYVel = 0;

  const pointerNDC = new THREE.Vector2(99, 99);
  const pointerScreen = { x: -100, y: -100, smoothX: -100, smoothY: -100 };
  const pointerWorldTarget = new THREE.Vector3(99, 99, 0);
  const pointerWorldSmooth = new THREE.Vector3(99, 99, 0);
  const prevPointerWorld = new THREE.Vector3(99, 99, 0);
  const pointerVelVec = new THREE.Vector3(0, 0, 0);
  const localPtrVec = new THREE.Vector3(0, 0, 2);

  let isPointerDown = false;
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

  shaderBridge = {
    triggerPulse: (power = 1.0) => {
      shockRadius = 0.22;
      shockStrength = power;
      corePulse = power;
    },
    triggerForgeCollapse: () => {
      isForging = true;
      forgePinchProgress = 0.001;
      corePulse = 1.2;
    },
    syncPluginMask: () => {
      updatePluginMaskUniform();
    },
    syncTheme: (themeId) => {
      const isLight = themeId === 'pure-frost';
      scene.background = new THREE.Color(isLight ? 0xf3f6fc : 0x03040a);

      // Sync Studio Three-Point Lights & PBR Crystal Emissive Balance
      hemiLight.color.setHex(isLight ? 0xffffff : 0xdbeafe);
      hemiLight.groundColor.setHex(isLight ? 0xcbd5e1 : 0x090d1f);
      hemiLight.intensity = isLight ? 1.75 : 1.40;
      keyLight.intensity = isLight ? 2.45 : 2.85;
      rimLight.color.setHex(isLight ? 0x38bdf8 : 0x818cf8);
      rimLight.intensity = isLight ? 1.15 : 1.55;

      satRecords.forEach((rec) => { rec.mat.emissiveIntensity = isLight ? 0.09 : 0.22; });
      dagRecords.forEach((rec) => { rec.mat.emissiveIntensity = isLight ? 0.10 : 0.24; });
      gyroRings.forEach((g) => { g.mat.emissiveIntensity = isLight ? 0.14 : 0.30; });

      coreUniforms.uLightMode.value = isLight ? 1.0 : 0.0;
      haloUniforms.uLightMode.value = isLight ? 1.0 : 0.0;
      haloMat.blending = isLight ? THREE.NormalBlending : THREE.AdditiveBlending;
      haloMat.needsUpdate = true;
      pUniforms.uLightMode.value = isLight ? 1.0 : 0.0;
      pMat.blending = isLight ? THREE.NormalBlending : THREE.AdditiveBlending;
      pMat.needsUpdate = true;
      trailMat.blending = isLight ? THREE.NormalBlending : THREE.AdditiveBlending;
      trailUniforms.uColor.value.setHex(isLight ? 0x0284c7 : 0x7dd3fc);
      trailMat.needsUpdate = true;
    }
  };

  shaderBridge.syncTheme(state.theme);

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
      dragYaw += dx * 0.0065;
      dragPitch = Math.max(-0.85, Math.min(0.85, dragPitch + dy * 0.0055));
      prevDrag = { x: e.clientX, y: e.clientY };
    }
  });

  window.addEventListener('pointerdown', (e) => {
    if (e.target?.closest?.('button, a')) return;
    isPointerDown = true;
    downTimeMs = performance.now();
    downCoords = { x: e.clientX, y: e.clientY };
    prevDrag = { x: e.clientX, y: e.clientY };
  });

  window.addEventListener('pointerup', (e) => {
    if (!isPointerDown) return;
    isPointerDown = false;
    const heldMs = performance.now() - downTimeMs;
    const movedPx = Math.hypot(e.clientX - downCoords.x, e.clientY - downCoords.y);

    if (movedPx < 8 && hovered3DNode) {
      const ud = hovered3DNode.userData;
      if (ud.kind === 'plugin') {
        togglePluginById(ud.plugin.id);
      } else if (ud.kind === 'dag') {
        shaderBridge.triggerPulse(1.15);
      }
    } else if (holdCharge > 0.25) {
      shaderBridge.triggerPulse(1.35 + holdCharge * 0.9);
    } else if (movedPx < 10 && heldMs < 260) {
      shaderBridge.triggerPulse(0.95);
    }
  });

  window.addEventListener('resize', () => {
    camera.aspect = window.innerWidth / window.innerHeight;
    camera.updateProjectionMatrix();
    renderer.setSize(window.innerWidth, window.innerHeight);
    pUniforms.uPixelRatio.value = Math.min(window.devicePixelRatio || 1, 2);
  });

  /* Pre-compile all stage shaders & upload all VBOs upfront so Stage 03 entry has 0ms stall */
  if (typeof renderer.compile === 'function') {
    satGroup.visible = true;
    gyroGroup.visible = true;
    dagGroup.visible = true;
    renderer.compile(scene, camera);
  }

  let coreYawPhase = 0;
  let vortexPhase = 0;
  let forgeShockFired = false;
  const clock = new THREE.Clock();

  function animate() {
    requestAnimationFrame(animate);
    const dt = Math.min(0.05, clock.getDelta());
    const elapsed = clock.getElapsedTime();

    stepAutoPlay(dt);

    /* 1. Morph Stage & Counter-Choreography Position Springs */
    const targetMorph = getMorphStage(state.scrollNorm);
    morphCurrent += (targetMorph - morphCurrent) * (1 - Math.exp(-4.5 * dt));

    const targetX = getTargetSculptureOffsetX(state.scrollNorm);
    const targetY = getTargetSculptureOffsetY(state.scrollNorm);
    const omega = 4.0, zeta = 0.90;
    const f = 1 + 2 * dt * zeta * omega;
    const oo = omega * omega;
    const hoo = dt * oo;
    const hhoo = dt * hoo;
    const detInv = 1 / (f + hhoo);

    const nextX = (f * offsetXCurrent + dt * offsetXVel + hhoo * targetX) * detInv;
    offsetXVel = (offsetXVel + hoo * (targetX - offsetXCurrent)) * detInv;
    offsetXCurrent = nextX;

    const nextY = (f * offsetYCurrent + dt * offsetYVel + hhoo * targetY) * detInv;
    offsetYVel = (offsetYVel + hoo * (targetY - offsetYCurrent)) * detInv;
    offsetYCurrent = nextY;

    if (!isPointerDown) {
      dragYaw *= Math.pow(0.48, dt);
      dragPitch *= Math.pow(0.48, dt);
    }

    const bobY = Math.sin(elapsed * 0.48) * 0.06;
    rootGroup.position.x = offsetXCurrent;
    rootGroup.position.y = offsetYCurrent + bobY;

    const ptrX = pointerNDC.x < 10 ? pointerNDC.x : 0;
    const ptrY = pointerNDC.y < 10 ? pointerNDC.y : 0;

    // Gentle parallax sway on planar stages (01 & 05) so particle sheets & eclipse corona stay poised;
    // gentle ambient orbit on radial 3D stages (00, 02, 03, 04) + full 360° manual dragYaw!
    const s1Weight = Math.max(0, 1 - Math.abs(morphCurrent - 1.0));
    const s3Weight = Math.max(0, 1 - Math.abs(morphCurrent - 3.0));
    const s4Weight = Math.max(0, 1 - Math.abs(morphCurrent - 4.0));
    const s5Weight = Math.max(0, 1 - Math.abs(morphCurrent - 5.0));
    const planarLock = Math.min(1, s1Weight + s5Weight);

    const autoOrbitY = Math.sin(elapsed * 0.22) * 0.22;
    rootGroup.rotation.y = autoOrbitY * (1 - planarLock * 0.65) + ptrX * 0.14 + dragYaw;
    rootGroup.rotation.x = Math.sin(elapsed * 0.26) * 0.06 - ptrY * 0.10 + dragPitch;

    // Keep world-space halo strictly behind sculpture center without orbiting into +Z!
    haloMesh.position.set(offsetXCurrent, offsetYCurrent + bobY, -2.4);
    haloMesh.lookAt(camera.position);

    if (isForging) {
      forgePinchProgress += dt * 0.46;
      if (!forgeShockFired && forgePinchProgress >= 0.52) {
        forgeShockFired = true;
        shockRadius = 0.24;
        shockStrength = 1.25;
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

    // Wrap coreYawPhase to [-PI, PI] and smoothly align planar stages (01 Lens & 05 Eclipse)
    // with their companion particle sheets/corona while keeping radial stages spinning!
    const spinMask = Math.max(0, 1 - planarLock);
    coreYawPhase -= dt * (0.15 + s3Weight * 0.52 + pinchCurve * 0.72) * spinMask;
    coreYawPhase = Math.atan2(Math.sin(coreYawPhase), Math.cos(coreYawPhase));
    if (planarLock > 0.01) {
      coreYawPhase *= Math.pow(0.06, dt * planarLock);
    }

    vortexPhase += dt * (0.36 + s3Weight * 0.48 + pinchCurve * 1.45);
    const lensYaw = -0.24 + Math.sin(elapsed * 0.42) * 0.07;
    const eclipseYaw = Math.sin(elapsed * 0.34) * 0.12;
    coreMesh.rotation.y = coreYawPhase + s1Weight * lensYaw + s5Weight * eclipseYaw;
    coreMesh.rotation.x = s1Weight * 0.15 + s5Weight * (Math.cos(elapsed * 0.28) * 0.06);

    coreMesh.updateMatrixWorld();
    coreNormalMat.getNormalMatrix(coreMesh.matrixWorld);

    /* 2. Update Stage-Specific Companion 3D Sculptures */
    const s2Vis = Math.max(0, 1 - Math.abs(morphCurrent - 2.0) * 1.15);
    satGroup.visible = s2Vis > 0.02;
    if (satGroup.visible) {
      satRecords.forEach((rec, i) => {
        const mounted = state.enabledPlugins.has(rec.plugin.id);
        const cAng = (i / 8) * Math.PI * 2 + elapsed * (mounted ? 0.22 : 0.07);
        const r = (mounted ? 3.35 : 4.45) * (0.72 + 0.28 * s2Vis);
        rec.mesh.position.set(
          Math.cos(cAng) * r,
          Math.sin(cAng) * r * 0.85,
          Math.sin(cAng * 2.0) * 0.72
        );
        rec.mesh.rotation.y = elapsed * 0.9 + i;
        rec.mesh.rotation.x = elapsed * 0.6;
        const targetHov = hovered3DNode === rec.mesh ? 1.55 : (mounted ? 1.0 : 0.68);
        rec.mesh.userData.hoverScale += (targetHov - rec.mesh.userData.hoverScale) * 0.16;
        rec.mesh.scale.setScalar(rec.mesh.userData.hoverScale * s2Vis);
        rec.mat.opacity = s2Vis * (mounted ? 0.95 : 0.38);
      });
    }

    const s3Vis = Math.max(0, 1 - Math.abs(morphCurrent - 3.0) * 1.15);
    gyroGroup.visible = s3Vis > 0.02;
    if (gyroGroup.visible) {
      const speedMult = 1 + pinchCurve * 2.4 + holdCharge * 2.2;
      gyroRings[0].mesh.rotation.x += dt * 0.95 * speedMult;
      gyroRings[1].mesh.rotation.y += dt * 1.15 * speedMult;
      gyroRings[2].mesh.rotation.z += dt * 0.85 * speedMult;
      gyroRings.forEach((g) => {
        g.mesh.scale.setScalar(0.82 + 0.18 * s3Vis);
        g.mat.opacity = s3Vis * 0.56;
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
        rec.mesh.rotation.y = elapsed * 0.7 + i * 0.5;
        const targetHov = hovered3DNode === rec.mesh ? 1.6 : 1.0;
        rec.mesh.userData.hoverScale += (targetHov - rec.mesh.userData.hoverScale) * 0.16;
        rec.mesh.scale.setScalar(rec.mesh.userData.hoverScale * s4Vis);
        rec.mat.opacity = s4Vis * 0.94;
      });
    }

    /* 3. Cursor Velocity, 3D Light-Ribbon Trail, Hold-to-Charge & Layer Fan-Out */
    prevPointerWorld.copy(pointerWorldSmooth);
    pointerWorldSmooth.lerp(pointerWorldTarget, 1 - Math.exp(-11.0 * dt));
    if (pointerWorldSmooth.x < 50 && prevPointerWorld.x < 50) {
      pointerVelVec.subVectors(pointerWorldSmooth, prevPointerWorld).multiplyScalar(1 / Math.max(0.008, dt));
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
    trailFade *= Math.pow(0.18, dt);
    trailUniforms.uOpacity.value = Math.min(0.65, trailFade * 0.65 + holdCharge * 0.35);

    const distToSculpture = Math.hypot(pointerWorldSmooth.x - offsetXCurrent, pointerWorldSmooth.y - offsetYCurrent);
    const cursorSpread = (s1Weight > 0.25 && distToSculpture < 4.2) ? (1 - distToSculpture / 4.2) : 0;
    const spreadTarget = Math.max(cursorSpread, s1Weight * state.autoLayerShowcase);
    layerSpread += (spreadTarget - layerSpread) * (1 - Math.exp(-6.0 * dt));

    const chargeActive = isPointerDown && (performance.now() - downTimeMs > 150);
    holdCharge += ((chargeActive ? 1.0 : 0.0) - holdCharge) * (1 - Math.exp(-5.5 * dt));

    if (pointerNDC.x < 10 && (satGroup.visible || dagGroup.visible)) {
      raycaster.setFromCamera(pointerNDC, camera);
      const candidates = satGroup.visible ? satRecords.map((r) => r.mesh) : dagRecords.map((r) => r.mesh);
      const hits = raycaster.intersectObjects(candidates, false);
      hovered3DNode = hits.length > 0 ? hits[0].object : null;
    } else {
      hovered3DNode = null;
    }

    if (cursorAura && pointerScreen.x > -50) {
      pointerScreen.smoothX += (pointerScreen.x - pointerScreen.smoothX) * 0.28;
      pointerScreen.smoothY += (pointerScreen.y - pointerScreen.smoothY) * 0.28;
      cursorAura.style.transform = `translate3d(${pointerScreen.smoothX.toFixed(1)}px, ${pointerScreen.smoothY.toFixed(1)}px, 0)`;
      cursorAura.classList.toggle('charging', chargeActive);
      cursorAura.classList.toggle('hovering-node', Boolean(hovered3DNode) && !chargeActive);

      if (cursorNodeLabel) {
        if (chargeActive) {
          cursorNodeLabel.textContent = state.lang === 'zh' ? '⌥Space · 松手唤醒流光脉冲' : '⌥SPACE · RELEASE PULSE';
        } else if (hovered3DNode) {
          const ud = hovered3DNode.userData;
          if (ud.kind === 'plugin') {
            const on = state.enabledPlugins.has(ud.plugin.id);
            const name = state.lang === 'zh' ? ud.plugin.zh : ud.plugin.en;
            const status = state.lang === 'zh' ? (on ? '已启用' : '未启用 · 0内存') : (on ? 'ACTIVE' : 'OFF · 0 RAM');
            cursorNodeLabel.textContent = `${name} · ${status}`;
          } else if (ud.kind === 'dag') {
            cursorNodeLabel.textContent = state.lang === 'zh' ? (ud.dag.zh || ud.dag.id) : (ud.dag.en || ud.dag.id);
          }
        }
      }
    }

    /* 4. Shockwave & MCP Collapse Decay */
    if (shockStrength > 0.002) {
      shockRadius += dt * 6.2;
      shockStrength *= Math.pow(0.07, dt);
    } else {
      shockStrength = 0;
    }
    if (corePulse > 0.002) corePulse *= Math.pow(0.06, dt);
    else corePulse = 0;

    /* 5. Push Uniforms & Render */
    localPtrVec.copy(pointerWorldSmooth).sub(rootGroup.position);

    coreUniforms.uTime.value = elapsed;
    coreUniforms.uMorph.value = morphCurrent;
    coreUniforms.uPulse.value = corePulse;
    coreUniforms.uHoldCharge.value = holdCharge;
    coreUniforms.uForgePinch.value = pinchCurve;
    coreUniforms.uPointerLocal.value.copy(localPtrVec);

    haloUniforms.uTime.value = elapsed;
    haloUniforms.uMorph.value = morphCurrent;
    haloUniforms.uPulse.value = corePulse + holdCharge * 0.6;

    pUniforms.uTime.value = elapsed;
    pUniforms.uMorph.value = morphCurrent;
    pUniforms.uPointer.value.copy(pointerWorldSmooth);
    pUniforms.uPointerVel.value.copy(pointerVelVec);
    pUniforms.uHoldCharge.value = holdCharge;
    pUniforms.uLayerSpread.value = layerSpread;
    pUniforms.uShockRadius.value = shockRadius;
    pUniforms.uShockStrength.value = shockStrength;
    pUniforms.uForgePinch.value = pinchCurve;
    pUniforms.uVortexPhase.value = vortexPhase;

    renderer.render(scene, camera);
  }

  animate();
}

/* ==========================================================================
   7B. Offline High-Art 3D-Projected Six-Morphology Particle Fallback
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

  const COUNT = 3400;
  const forms = generateSixMorphForms(COUNT);
  let morphCurrent = getMorphStage(state.scrollNorm);
  let offsetXCurrent = getTargetSculptureOffsetX(state.scrollNorm);
  let offsetYCurrent = getTargetSculptureOffsetY(state.scrollNorm);
  let shockRadius = 0;
  let shockStrength = 0;
  let ptrX = 0, ptrY = 0;

  window.addEventListener('pointermove', (e) => {
    ptrX = (e.clientX / Math.max(1, w)) * 2 - 1;
    ptrY = -(e.clientY / Math.max(1, h)) * 2 + 1;
  });

  window.addEventListener('pointerdown', (e) => {
    if (e.target?.closest?.('button, a')) return;
    shockRadius = 0.2;
    shockStrength = 1.1;
  });

  shaderBridge = {
    triggerPulse: (p = 1.0) => { shockRadius = 0.2; shockStrength = p; },
    triggerForgeCollapse: () => { shockRadius = 0.2; shockStrength = 1.35; },
    syncPluginMask: () => {},
    syncTheme: () => {}
  };

  let lastT = performance.now() * 0.001;

  function loop() {
    requestAnimationFrame(loop);
    const now = performance.now() * 0.001;
    const dt = Math.min(0.05, Math.max(0.001, now - lastT));
    lastT = now;

    stepAutoPlay(dt);

    morphCurrent += (getMorphStage(state.scrollNorm) - morphCurrent) * 0.08;
    offsetXCurrent += (getTargetSculptureOffsetX(state.scrollNorm) - offsetXCurrent) * 0.08;
    offsetYCurrent += (getTargetSculptureOffsetY(state.scrollNorm) - offsetYCurrent) * 0.08;

    if (shockStrength > 0.002) {
      shockRadius += dt * 5.6;
      shockStrength *= Math.pow(0.08, dt);
    } else shockStrength = 0;

    const isLight = state.theme === 'pure-frost';
    ctx.save();
    ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    ctx.fillStyle = isLight ? '#f3f6fc' : '#03040a';
    ctx.fillRect(0, 0, w, h);

    const fovScale = (h * 0.5) / Math.tan((40 * Math.PI) / 360);
    const ry = Math.sin(now * 0.22) * 0.22 + ptrX * 0.18;
    const rx = Math.sin(now * 0.3) * 0.08 - ptrY * 0.12;
    const cy = Math.cos(ry), sy = Math.sin(ry);
    const cx = Math.cos(rx), sx = Math.sin(rx);

    const m = Math.max(0, Math.min(5, morphCurrent));
    const seg = Math.min(4, Math.floor(m));
    const frac = m - seg;
    const smooth = frac * frac * (3 - 2 * frac);
    const arrList = [forms.form0, forms.form1, forms.form2, forms.form3, forms.form4, forms.form5];
    const srcA = arrList[seg];
    const srcB = arrList[seg + 1];

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

      ctx.fillStyle = isLight ? 'rgba(2,132,199,0.52)' : 'rgba(103,232,249,0.75)';
      const r = Math.max(0.9, Math.min(3.0, 1.8 * (scale / 100)));
      ctx.fillRect(sx2, sy2, r, r);
    }

    ctx.restore();
  }

  loop();
}

/* --------------------------------------------------------------------------
   8. Boot Orchestrator
   -------------------------------------------------------------------------- */
async function boot() {
  const container = document.getElementById('canvasContainer');
  if (!container) {
    dismissBootVeil();
    return;
  }

  if (bootBarFill) bootBarFill.style.width = '72%';
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
  } finally {
    dismissBootVeil();
  }
}

boot();
})();
