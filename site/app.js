/* ==========================================================================
   Lucent 2D Showcase — Authentic macOS Liquid Glass Workbench,
   880×544 Hub Simulator (Full Keyboard Flow + ⌘K Action Drawer + Context Menu),
   11 Official Swift Plugins + 21 MCP Tools & 10 Tactile Control Physics
   ========================================================================== */
(() => {
  'use strict';

  const REPO_BASE = 'https://github.com/lengsukq/Lucent';
  const SCHEME_PREFIX = ['lucent', '://'].join('');
  const THEME_KEY = 'lucent-showcase-theme-v2';
  const LANG_KEY = 'lucent-showcase-lang-v2';
  const PLUGINS_KEY = 'lucent-enabled-plugins-v2';

  const reducedMotionQuery = window.matchMedia('(prefers-reduced-motion: reduce)');
  let prefersReducedMotion = reducedMotionQuery.matches;
  reducedMotionQuery.addEventListener?.('change', (e) => { prefersReducedMotion = e.matches; });

  function safeGet(key, fallback = null) {
    try {
      const v = window.localStorage.getItem(key);
      return v !== null ? v : fallback;
    } catch (_) {
      return fallback;
    }
  }

  function safeSet(key, val) {
    try {
      window.localStorage.setItem(key, val);
    } catch (_) {}
  }

  function resolveInitialTheme() {
    const stored = safeGet(THEME_KEY, null);
    if (stored === 'pure-frost' || stored === 'prism-pulse') return stored;
    return window.matchMedia('(prefers-color-scheme: dark)').matches ? 'prism-pulse' : 'pure-frost';
  }

  /* ------------------------------------------------------------------------
     0. Unified 1.75px SF-Symbols Inline SVG Icon Library (Zero Emojis)
     ------------------------------------------------------------------------ */
  const ICON_PATHS = {
    globe: '<circle cx="12" cy="12" r="9"/><path d="M3 12h18"/><path d="M12 3a13 13 0 0 1 3.5 9 13 13 0 0 1-3.5 9 13 13 0 0 1-3.5-9A13 13 0 0 1 12 3Z"/>',
    tray: '<path d="M4 13V6a2 2 0 0 1 2-2h12a2 2 0 0 1 2 2v7"/><path d="M3 13h5l2 3h4l2-3h5v5a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-5Z"/>',
    audio: '<path d="M9 18V5l12-2v13"/><circle cx="6" cy="18" r="3"/><circle cx="18" cy="16" r="3"/>',
    pulse: '<polyline points="22 12 18 12 15 20 9 4 6 12 2 12"/>',
    chart: '<polyline points="22 7 13.5 15.5 8.5 10.5 2 17"/><polyline points="16 7 22 7 22 13"/>',
    compass: '<circle cx="12" cy="12" r="9"/><polygon points="16.24 7.76 14.12 14.12 7.76 16.24 9.88 9.88 16.24 7.76"/>',
    clock: '<circle cx="12" cy="13" r="8"/><path d="M12 9v4l2.5 1.5"/><path d="M5 3 2 6M22 6l-3-3"/>',
    sliders: '<line x1="4" y1="6" x2="20" y2="6"/><circle cx="9" cy="6" r="2"/><line x1="4" y1="12" x2="20" y2="12"/><circle cx="15" cy="12" r="2"/><line x1="4" y1="18" x2="20" y2="18"/><circle cx="11" cy="18" r="2"/>',
    shield: '<path d="M12 3 4.5 6v6c0 4.6 3.2 8.2 7.5 9.5 4.3-1.3 7.5-4.9 7.5-9.5V6L12 3Z"/><polyline points="9 12 11 14 15 10"/>',
    wifi: '<path d="M5 12.55a11 11 0 0 1 14.08 0"/><path d="M8.53 16.11a6 6 0 0 1 6.95 0"/><circle cx="12" cy="19.5" r="1"/>',
    bookmark: '<path d="M6 4h12a1 1 0 0 1 1 1v16l-7-4-7 4V5a1 1 0 0 1 1-1Z"/>',
    git: '<circle cx="6" cy="6" r="2.5"/><circle cx="18" cy="6" r="2.5"/><circle cx="6" cy="18" r="2.5"/><path d="M6 8.5v7"/><path d="M18 8.5c0 4-3 5.5-12 5.5"/>',
    search: '<circle cx="11" cy="11" r="7.5"/><line x1="20.5" y1="20.5" x2="16.4" y2="16.4"/>',
    crop: '<path d="M4 8V6a2 2 0 0 1 2-2h2M16 4h2a2 2 0 0 1 2 2v2M20 16v2a2 2 0 0 1-2 2h-2M8 20H6a2 2 0 0 1-2-2v-2"/><circle cx="12" cy="12" r="3"/>',
    grid: '<rect x="3" y="3" width="7" height="7" rx="1.5"/><rect x="14" y="3" width="7" height="7" rx="1.5"/><rect x="3" y="14" width="7" height="7" rx="1.5"/><rect x="14" y="14" width="7" height="7" rx="1.5"/>',
    columns: '<rect x="3" y="4" width="18" height="16" rx="2.5"/><line x1="12" y1="4" x2="12" y2="20"/>',
    pin: '<path d="M12 17v5"/><path d="M9 10.76a2 2 0 0 1-1.11 1.79l-1.78.9A2 2 0 0 0 5 15.24V16h14v-.76a2 2 0 0 0-1.11-1.79l-1.78-.9A2 2 0 0 1 15 10.76V7a1 1 0 0 1 1-1h1V4H7v2h1a1 1 0 0 1 1 1v3.76Z"/>',
    clipboard: '<rect x="8" y="3" width="8" height="4" rx="1.2"/><path d="M16 5h2a2 2 0 0 1 2 2v13a2 2 0 0 1-2 2H6a2 2 0 0 1-2-2V7a2 2 0 0 1 2-2h2"/>',
    calc: '<rect x="4" y="3" width="16" height="18" rx="3"/><line x1="8" y1="8" x2="16" y2="8"/><path d="M8 13h2M14 13h2M8 17h2M14 17h2"/>',
    file: '<path d="M14 3H6a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V9Z"/><polyline points="14 3 14 9 20 9"/>',
    network: '<path d="M7 16V4m0 0-3 3m3-3 3 3"/><path d="M17 8v12m0 0-3-3m3 3 3-3"/>',
    trash: '<polyline points="3 6 5 6 21 6"/><path d="M19 6v14a2 2 0 0 1-2 2H7a2 2 0 0 1-2-2V6"/><path d="M8 6V4a2 2 0 0 1 2-2h4a2 2 0 0 1 2 2v2"/>',
    copy: '<rect x="9" y="9" width="13" height="13" rx="2"/><path d="M5 15H4a2 2 0 0 1-2-2V4a2 2 0 0 1 2-2h9a2 2 0 0 1 2 2v1"/>',
    check: '<polyline points="20 6 9 17 4 12"/>',
    terminal: '<polyline points="4 17 10 11 4 5"/><line x1="12" y1="19" x2="20" y2="19"/>',
    folder: '<path d="M3 7a2 2 0 0 1 2-2h4l2 2h8a2 2 0 0 1 2 2v8a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V7Z"/>',
    video: '<rect x="3" y="6" width="14" height="12" rx="2"/><polygon points="22 8 17 12 22 16 22 8"/>',
    command: '<path d="M18 3a3 3 0 0 0-3 3v12a3 3 0 0 0 3 3 3 3 0 0 0 3-3 3 3 0 0 0-3-3H6a3 3 0 0 0-3 3 3 3 0 0 0 3 3 3 3 0 0 0 3-3V6a3 3 0 0 0-3-3 3 3 0 0 0-3 3 3 3 0 0 0 3 3h12a3 3 0 0 0 3-3 3 3 0 0 0-3-3Z"/>'
  };

  function iconSvg(name, size = 15, extraClass = '') {
    const body = ICON_PATHS[name] || ICON_PATHS.grid;
    const cls = extraClass ? ` class="${extraClass}"` : '';
    return `<svg${cls} width="${size}" height="${size}" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.75" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">${body}</svg>`;
  }

  /* ------------------------------------------------------------------------
     1. Application State
     ------------------------------------------------------------------------ */
  let savedPluginIds = ['translate-hub', 'file-shelf', 'audio-presets', 'browser-hub', 'quick-remind', 'mac-pilot'];
  try {
    const rawSaved = safeGet(PLUGINS_KEY);
    if (rawSaved) {
      const parsed = JSON.parse(rawSaved);
      if (Array.isArray(parsed)) savedPluginIds = parsed;
    }
  } catch (_) {}

  const state = {
    theme: resolveInitialTheme(),
    userChoseTheme: safeGet(THEME_KEY, null) !== null,
    lang: safeGet(LANG_KEY, 'zh'),
    preset: 'bento',
    homeProfile: 'balanced',
    scope: 'all',
    query: '',
    selectedResultIdx: 0,
    currentMatches: [],
    pinnedCustomItems: [],
    drawerOpen: false,
    drawerTarget: null,
    drawerSelectedIdx: 0,
    contextMenuOpen: false,
    termMode: 'mcp',
    activeStep: 0,
    snifferMode: 'repo',
    sliderRatio: 0.35,
    modelIdx: 0,
    secretRevealed: false,
    hotkeyIdx: 0,
    hudCompact: false,
    secIdx: 0,
    builderProfile: 'daily',
    focusedPluginId: 'translate-hub',
    lastToggledPluginId: null,
    enabledPlugins: new Set(savedPluginIds)
  };

  function saveEnabledPlugins() {
    safeSet(PLUGINS_KEY, JSON.stringify([...state.enabledPlugins]));
  }

  /* ------------------------------------------------------------------------
     2. Floating Liquid Glass Toast Island & Panel Toast
     ------------------------------------------------------------------------ */
  let glassToastTimer = null;
  function showGlassToast(msg, variant = 'ok') {
    const island = document.getElementById('glassToastIsland');
    const textEl = document.getElementById('glassToastText');
    const iconEl = document.getElementById('glassToastIcon');
    if (island && textEl) {
      textEl.textContent = msg;
      if (iconEl) {
        iconEl.classList.toggle('tone-accent', variant === 'accent');
        iconEl.innerHTML = variant === 'accent'
          ? iconSvg('command', 13)
          : iconSvg('check', 14, 'svg-check-draw');
      }
      island.classList.add('visible');
      if (glassToastTimer) clearTimeout(glassToastTimer);
      glassToastTimer = setTimeout(() => { island.classList.remove('visible'); }, 2300);
    }
    const panelToast = document.getElementById('panelActionToast');
    if (panelToast) {
      panelToast.textContent = msg;
      clearTimeout(panelToast._t);
      panelToast._t = setTimeout(() => { panelToast.textContent = ''; }, 2400);
    }
  }

  /* ------------------------------------------------------------------------
     3. Liquid Droplet Sliding Glider with Stretch-Settle Physics
     ------------------------------------------------------------------------ */
  const gliderPositions = new Map();

  function syncGlider(containerSelector, gliderId, activeSelector, animateDroplet = true) {
    const container = document.querySelector(containerSelector);
    const glider = document.getElementById(gliderId);
    if (!container || !glider) return;
    const active = container.querySelector(activeSelector);
    if (!active || active.offsetWidth <= 0) {
      container.classList.remove('glider-ready');
      return;
    }
    const cRect = container.getBoundingClientRect();
    const aRect = active.getBoundingClientRect();
    const offsetX = aRect.left - cRect.left;
    const prevX = gliderPositions.get(gliderId);
    const moved = prevX !== undefined && Math.abs(prevX - offsetX) > 3;
    gliderPositions.set(gliderId, offsetX);

    glider.style.width = `${aRect.width.toFixed(1)}px`;
    if (moved && animateDroplet && !prefersReducedMotion) {
      glider.style.transform = `translateX(${offsetX.toFixed(1)}px) scaleX(1.12) scaleY(0.94)`;
      glider.classList.remove('glider-glint');
      clearTimeout(glider._settleTimer);
      glider._settleTimer = setTimeout(() => {
        glider.style.transform = `translateX(${offsetX.toFixed(1)}px) scaleX(1) scaleY(1)`;
        glider.classList.add('glider-glint');
        setTimeout(() => glider.classList.remove('glider-glint'), 260);
      }, 150);
    } else {
      glider.style.transform = `translateX(${offsetX.toFixed(1)}px) scaleX(1) scaleY(1)`;
    }
    container.classList.add('glider-ready');
  }

  /* ------------------------------------------------------------------------
     4. Tactile Click Physics (Primary Ripple, Bento 3D Tilt + Perimeter Glint,
        Keycap 2.5px Press + Release Halo)
     ------------------------------------------------------------------------ */
  function triggerPrimaryButtonFx(btn, e) {
    if (prefersReducedMotion || !btn) return;
    const rect = btn.getBoundingClientRect();
    const x = e.clientX ? e.clientX - rect.left : rect.width * 0.5;
    const y = e.clientY ? e.clientY - rect.top : rect.height * 0.5;
    const size = Math.max(rect.width, rect.height);

    const ripple = document.createElement('span');
    ripple.className = 'fx-ripple';
    ripple.style.left = `${x}px`;
    ripple.style.top = `${y}px`;
    ripple.style.width = `${size}px`;
    ripple.style.height = `${size}px`;
    btn.appendChild(ripple);
    setTimeout(() => ripple.remove(), 620);

    const sheen = document.createElement('span');
    sheen.className = 'fx-sheen';
    btn.appendChild(sheen);
    setTimeout(() => sheen.remove(), 560);

    btn.classList.remove('fx-spring-pop');
    void btn.offsetWidth;
    btn.classList.add('fx-spring-pop');
    setTimeout(() => btn.classList.remove('fx-spring-pop'), 450);
  }

  function triggerBentoCardFx(card, e) {
    if (prefersReducedMotion || !card) return;
    const rect = card.getBoundingClientRect();
    const relX = ((e.clientX - rect.left) / Math.max(1, rect.width)) - 0.5;
    const relY = ((e.clientY - rect.top) / Math.max(1, rect.height)) - 0.5;
    const rotY = (relX * 7).toFixed(2);
    const rotX = (-relY * 6.5).toFixed(2);

    card.style.transform = `perspective(720px) rotateX(${rotX}deg) rotateY(${rotY}deg) scale(0.978)`;
    setTimeout(() => {
      card.style.transform = '';
    }, 190);

    const existing = card.querySelector('.fx-perimeter-trace');
    if (existing) existing.remove();
    const trace = document.createElement('span');
    trace.className = 'fx-perimeter-trace';
    card.appendChild(trace);
    setTimeout(() => trace.remove(), 660);
  }

  function pulseKeycap(kbdEl) {
    if (!kbdEl || prefersReducedMotion) return;
    kbdEl.classList.add('pressed');
    setTimeout(() => {
      kbdEl.classList.remove('pressed');
      kbdEl.classList.remove('keycap-released');
      void kbdEl.offsetWidth;
      kbdEl.classList.add('keycap-released');
      setTimeout(() => kbdEl.classList.remove('keycap-released'), 460);
    }, 115);
  }

  document.addEventListener('pointerdown', (e) => {
    const primaryBtn = e.target.closest('.fx-primary-btn');
    if (primaryBtn) {
      triggerPrimaryButtonFx(primaryBtn, e);
      return;
    }
    const bentoCard = e.target.closest('.bento-tile, .fx-bento-card');
    if (bentoCard && !e.target.closest('button, a')) {
      triggerBentoCardFx(bentoCard, e);
    }
    const kbdWrap = e.target.closest('button, kbd.keycap');
    if (kbdWrap) {
      const kbd = kbdWrap.matches('kbd.keycap') ? kbdWrap : kbdWrap.querySelector('kbd.keycap');
      if (kbd) pulseKeycap(kbd);
    }
  });

  // Hydrate repository links cleanly
  document.querySelectorAll('[data-gh-path]').forEach((el) => {
    const sub = el.getAttribute('data-gh-path') || '';
    el.setAttribute('href', `${REPO_BASE}${sub}`);
    el.setAttribute('target', '_blank');
    el.setAttribute('rel', 'noopener noreferrer');
  });

  /* ------------------------------------------------------------------------
     5. Bilingual Copy Dictionary (简体中文 / English — Aligned with STATUS.md)
     ------------------------------------------------------------------------ */
  const I18N = {
    zh: {
      brand_cn: '流光',
      nav_launcher: '启动面板',
      nav_compare: '竞品对比',
      nav_builder: '高度定制',
      nav_theatre: 'AI 共创',
      nav_bento: '日常利器',
      nav_philosophy: '设计哲学',
      nav_arch: '极客架构',
      nav_3d_exp: '3D 舞台',
      nav_download: '下载 DMG',
      theme_frost: '晴霜浅色',
      theme_prism: '曜石暗色',
      hero_capsule: 'MIT 开源免费 · ~10 MB Swift 6 · 0 订阅 · 0 登录',
      hero_title_1: '10 MB 纯原生底座，',
      hero_title_2: '<span class="nowrap">替掉 5 个</span><span class="nowrap">付费工具。</span>',
      hero_subtitle: '按 ⌥Space 搞定全盘秒搜、长截图与穿透贴图、GIF/MP4 录屏、鼠标平滑与磁吸中转站；连上 Claude Code 十秒造插件。',
      cta_download: '下载 macOS DMG',
      cta_builder: '定制你的 Lucent',
      cta_3d_exp: '前往 3D 舞台 →',
      preset_try: '切换启动面板 / 试搜指令：',
      preset_bento: '均衡默认主页',
      preset_home_min: '极简 16 格混合坞',
      preset_home_dev: '开发者主页与书签架',
      preset_home_shelf: '4 列磁贴与分类架',
      preset_translate: '划词 / OCR 翻译',
      preset_remind: '10m 喝水提醒',
      preset_dev: '算式与色板换算',
      scope_all: '全部',
      scope_plugins: '插件',
      scope_files: '文件',
      scope_clip: '剪贴板',
      drawer_foot_nav: '↑↓ 选择 · ↵ 执行 · Esc 关闭',
      hint_open: '执行 / 打开',
      hint_actions: '动作抽屉',
      hint_scope: '切换分类',
      hint_tab: '右键菜单',
      scroll_hint: '向下滚动，查看竞品对比、自由定制与 AI 一句话共创',
      cmp_eyebrow: 'WHY LUCENT · 一眼看清差异',
      cmp_title: '别人收费的，|这里全免费原生',
      cmp_desc: '免费开源、不卖 AI 会员，把 5 个常驻工具合进 ~10 MB 原生底座。',
      cmp_h_dim: '核心维度',
      cmp_h_lucent: '流光 Lucent',
      cmp_h_raycast: 'Raycast (Free / Pro)',
      cmp_h_utools: 'uTools',
      cmp_h_alfred: 'Alfred + 常用单品',
      cmp_r1_k: '开源与收费',
      cmp_r1_l: '<strong>MIT 开源 · 全免费 · 免登录</strong>',
      cmp_r1_r: '闭源 · Pro 订阅解锁同步 / AI',
      cmp_r1_u: '闭源 · 需登录与会员',
      cmp_r1_a: '闭源 · 买断 + 另购多款 App',
      cmp_r2_k: 'AI / MCP',
      cmp_r2_l: '<strong>21 MCP · 直连你的 AI</strong>',
      cmp_r2_r: '自家 AI Credits 订阅',
      cmp_r2_u: '自家 AI 会员',
      cmp_r2_a: '无原生 MCP',
      cmp_r3_k: '系统原生利器',
      cmp_r3_l: '<strong>长截图 · 穿透贴图 · 录屏 · 鼠标平滑 · 磁吸托盘</strong>',
      cmp_r3_r: '无内置',
      cmp_r3_u: '依赖第三方插件',
      cmp_r3_a: '需另装 4–5 个软件',
      cmp_r4_k: '插件形态',
      cmp_r4_l: '<strong>原生页 + 透明穿透挂件 + 沙箱</strong>',
      cmp_r4_r: '仅列表 / 表单',
      cmp_r4_u: 'Electron 独立窗',
      cmp_r4_a: '仅列表 / Workflow',
      cmp_r5_k: '体量与内存',
      cmp_r5_l: '<strong>~10 MB Swift 6 · 用完即焚</strong>',
      cmp_r5_r: '原生 + Node 扩展',
      cmp_r5_u: 'Electron 偏重',
      cmp_r5_a: '多软件同时常驻',
      builder_eyebrow: 'DEEP CUSTOMIZATION WORKBENCH · 全维度高度自定义拼装台',
      builder_title: '千人千面，|不用即零内存',
      builder_desc: '11 款官方原生 Swift 扩展默认关闭、零后台打扰；按需点亮，即装即原生。',
      jump_3d_plugins: '在 3D 舞台查看插件生态 →',
      prof_minimal: '纯粹微内核底座 (0 插件)',
      prof_daily: '日常省心高频套装',
      prof_dev: '极客 AI 与悬浮挂件流',
      prof_full: '11 款官方旗舰 + AI 自制满配',
      cat_head_title: '11 款官方原生 Swift 扩展 + AI 自制示例',
      prev_live_badge: '实时联动：上方启动面板与菜单栏形态',
      zone_quick_title: '按需挂载至启动面板胶囊架 & 状态栏菜单（默认关闭不挤占）',
      zone_accepts_title: '跨模块 ⌘K 动作流 & 右键联动（OCR / 剪贴板 / 文件工作台）',
      theatre_eyebrow: 'ZERO AI MARKUP · 内置 21 项 MCP 工具直连你已有的 AI 客户端',
      theatre_title: '不卖 AI 会员，|把 Claude Code / Cursor 变成你的<span class="nowrap">原生插件工厂</span>',
      jump_3d_mcp: '在 3D 舞台查看 MCP 共创 →',
      s1_title: '21 项 MCP：造脚本、造插件、排主页',
      s1_desc: '直连你已有的 Claude Code / Cursor，一句话生成脚本、插件或主页并 350ms 热重载。',
      s2_title: '零前端设置页 + 透明穿透悬浮挂件',
      s2_desc: '一份 plugin.json 自动生成原生设置，亦支持 120Hz 透明点击穿透与贴边磁吸浮窗。',
      s3_title: '贴个链接直接装，升级无损保留配置',
      s3_desc: '粘贴 GitHub 或插件包链接自动识别并校验 SHA-256，更新完整保留快捷键与密钥。',
      s4_title: '内核沙箱 · 加密密钥箱 · WebDAV 同步',
      s4_desc: 'Seatbelt 硬隔离网络与隐私目录，密钥 AES-GCM 加密，整机配置一键漫游。',
      sc0_prompt: '“帮我做一个查待审 PR 的插件（Token 存加密箱），顺便在我的启动面板新建一个『日常开发』主页，把双栏文件台、这个新插件和 GitHub 书签架排上去。”',
      sc0_st1: '读取内置脚本库、插件与启动面板规范及可用能力池',
      sc0_st2: '自动生成插件或脚本并在 Seatbelt 沙箱内完成实跑验证',
      sc0_st3: '创建新主页 Profile、挂载磁贴并支持只读本地文件检索',
      sc0_live_t: '已热刷新至 ⌥Space：新插件与「日常开发」启动面板同步就绪',
      sc0_try_btn: '点击在上方体验 ↗',
      sc0_live_d: '全程无需重启 Lucent，不满意还能随时在设置页或通过 undoLastChange 一键撤回上次面板改动。',
      sc0_f1: '12 项插件生命周期工具',
      sc0_f2: '4 项快捷脚本 + 4 项主页编排',
      sc0_f3: 'lucent_search_files 离线快照检索',
      sc1_slider_t: '免写界面的原生设置页（拖动滑块或点选控件实时体验）',
      sc1_slider_d: '自动渲染输入框、AES-GCM 密钥框、连续滑块、下拉单选、路径选择器与标签组，改动瞬间自动保存并同步插件：',
      sc1_hk_t: '子命令静默热键 & 权重覆盖',
      sc1_hk_d: '每条细分动作都能独立绑快捷键后台静默秒跑；点击此卡片可轮换测试热键并实时核验冲突：',
      sc1_dl_t: '自由画布透明桌面挂件',
      sc1_dl_d: '支持无边框透明毛玻璃 HUD、贴边磁吸与跨重启恢复；点击下方挂件切换「完整 / 紧凑穿透」态：',
      sc1_f1: '宿主统一代申系统 TCC 权限',
      sc1_f2: '中英双语与深浅主题实时热同步',
      sc1_f3: '三层全局热键防冲突检测',
      sniff_btn_1: '试贴开源仓库子目录',
      sniff_btn_2: '试贴商店索引 JSON',
      sniff_btn_3: '试贴独立插件压缩包',
      sc2_verify_t: '防伪装双端权限核验',
      sc2_verify_d: '安装前强制核对 64 位 SHA-256 指纹，并比对包内真实权限与商店声明，任何悄悄越权夹带都会被当场拦截。',
      sc2_upg_t: '无损平滑检查更新',
      sc2_upg_d: '只读插件代码与个人数据目录严格分离，跨商店批量更新时完整保留你的自定义唤醒词、热键与加密凭据。',
      sc2_f1: 'lucent_package_plugin_for_store 一键发版',
      sc2_f2: '插件更新免重复勾选系统权限',
      sc3_r1: '未声明联网或子进程即由系统内核硬阻断，无条件隔离钥匙串与敏感目录',
      sc3_r2: '受控宿主桥接（OCR / 划词 / 截屏 / 音频 / 通知等），一次性令牌随进程结束即焚',
      sc3_r3: '双轨 256-bit 随机主密钥 AES-GCM 加密存放 API Key，磁盘零明文残留',
      sc3_r4: 'LZFSE 压缩打包启动面板、快捷脚本库、自制插件与密钥，云盘与 NAS 一键漫游',
      sc3_f1: '全景权限审计矩阵',
      sc3_f2: '子进程超时自动回收兜底',
      sc3_f3: 'HKDF + AES-GCM 备份口令保护',
      bento_eyebrow: 'EVERYDAY NATIVE ESSENTIALS · 不装任何插件也超好用的五大原生利器',
      bento_title: '一个 10 MB 底座，|替掉 5 个常驻软件',
      bento_desc: '搜索、截图贴图、录屏、离线识字与鼠标平滑全原生内置，关窗即释放内存。',
      hk_all: '全部内置利器',
      hk_search: '自定义主页与全盘秒搜',
      hk_shot: '截图标注 · GIF · 离线识字',
      hk_pulse: '芯片功耗贴边胶囊',
      hk_net: '软件网速与清缓存',
      hk_ws: '双栏整理 & 鼠标丝滑滚轮',
      fc1_title: '启动面板 · 全盘秒搜 · ⌘K 与剪贴板',
      fc1_desc: '自定义主页、免前缀秒搜本机与移动硬盘、15 步撤回剪贴板，按 ⌘K 串联全部动作。',
      fc1_c1: '⌘K 上下文动作抽屉',
      fc1_c2: 'LCNTIDX3 mmap 零拷贝秒搜',
      fc1_c3: 'SearchAffinity 自适应排序',
      fc2_title: '截图标注 · 长截图 · GIF/MP4 · 穿透钉屏',
      fc2_desc: '多屏原画 11 种矢量标注、滚动长截图、按 T 穿透钉屏、零 FFmpeg 录屏与离线识字。',
      fc2_c1: 'ScreenCaptureKit 零延迟冻屏',
      fc2_c2: '滚动长截图 & 流式 GIF89a',
      fc2_c3: 'Vision 本地离线 OCR',
      fc3_title: '芯片功耗小胶囊',
      fc3_desc: '默认关闭；开启后实时显示大小核负载与整机瓦数 (W)，靠边自动隐藏。',
      fc4_title: '软件网速透视 & 安全清缓存',
      fc4_desc: '免 Root 看清各软件实时网速与连向，顺手安全清理应用缓存。',
      fc5_title: '外接鼠标平滑 & 双栏文件台',
      fc5_desc: '外接鼠标 120Hz 平滑反转（不动触控板），按需呼出双栏整理与原生读图播片。',
      phil_eyebrow: 'CORE PHILOSOPHY · 为什么普通用户与极客都喜欢它',
      phil_title: '底座克制，|定制自由',
      phil_desc: '开箱即用，按需生长，绝不在后台拖慢你的 Mac。',
      p1_title: '深度可定制，但不强迫折腾',
      p1_desc: '默认即顺手；想定制时，启动面板、菜单栏、静默热键与 AI 插件全开放。',
      p2_title: '~10 MB 纯 Swift 6，拒绝套壳',
      p2_desc: '零第三方依赖，直连 Apple Silicon 系统框架，秒开低发热。',
      p3_title: '固定 880×544，稳稳的肌肉记忆',
      p3_desc: '切分类不跳变、中文拼音不误触、索引刷新不抢焦，盲操顺手。',
      p4_title: '用完即焚省内存，沙箱守隐私',
      p4_desc: '收起 30s 毁视图、空闲 90s 卸索引；插件进 Seatbelt 沙箱，密钥 AES-GCM 加密。',
      duality_eyebrow: 'LIGHT FROST & OBSIDIAN DARK · 双生液态玻璃主题',
      duality_title: '「晴霜浅色」的清冽瓷白，|或「曜石暗色」的深邃玻璃',
      duality_desc: '默认自动跟随 macOS 系统外观，亦可随时点击右侧实时迷你窗口预览卡一键切换；软件内切换外观时将同步广播给所有已开启的原生浮窗与自由画布挂件。',
      btn_frost: '晴霜浅色',
      btn_prism: '曜石暗色',
      bound_title: '清晰克制的产品边界：|把自由留给定制，让底座永远轻快',
      bound_sub: '知道「什么该做到极致」与「什么绝不往底座硬塞」，才能让你的 Mac 长久保持清爽不卡顿。',
      yes_1: '<strong>你的界面你做主：</strong>启动面板四分区、⌘K 动作流、快捷脚本库、顶部状态栏菜单、全局快捷键与插件挂件全部支持按需开启与自由排布。',
      yes_2: '<strong>普通人也能玩的 AI 扩展：</strong>内置 21 项 lucent-mcp 工具与单框智能商店嗅探，一句话就能定制快捷脚本、新插件或新主页。',
      yes_3: '<strong>100% 专为 M 系列芯片打造：</strong>纯 arm64 原生编译与 macOS 14+ 系统框架直连，没有跨平台兼容包袱。',
      no_1: '<strong>绝不做关不掉的臃肿全家桶：</strong>刚装好时零悬浮球、零菜单栏强塞读数、零后台守护进程，一切按需点亮。',
      no_2: '<strong>绝不拿几百 MB 网页内核套主界面：</strong>内置文档阅读与主面板坚持纯 Swift 原生渲染；插件自由浮窗关窗即刻销毁。',
      no_3: '<strong>绝不裸奔跑脚本或冒险强写脏硬盘：</strong>外部脚本强制进内核沙箱、密钥加密存放，遇到带脏标记的 NTFS 盘严格只读护航。',
      arch_eyebrow: 'UNDER THE HOOD FOR GEEKS · 给极客看的硬核工程纪律',
      arch_title: '单向无环 Swift 6 模块分层 · |单文件硬性严控 ≤ 300 行',
      arch_desc: '代码库与产品一样干净克制：每次构建均由自动化脚本强制核验模块单向 DAG 依赖、单 .swift 文件行数上限、文档死链与真实 lucent-mcp JSON-RPC 往返联调。',
      jump_3d_dag: '在 3D 舞台查看原生架构 →',
      m_1: '内置 lucent-mcp 脚本、插件、主页与检索工具',
      m_2: '第三方 SwiftPM / CocoaPods 外部依赖',
      m_3: '单 .swift 源码文件硬性行数上限',
      m_4: '浮窗销毁 / 索引自动归还内存窗口',
      dag_app: 'SwiftUI + AppKit 双主题前端 · ⌘K 动作抽屉 · 启动面板/脚本库定制 · 自由画布悬浮窗',
      dag_mcp: '内置 21 项 JSON-RPC 2.0 工具：快捷脚本与 SVG 图标、插件脚手架、主页编排与离线文件检索',
      dag_core: 'HomeLayout 多场景启动面板 · OverlayActionCatalog · Quick Scripts · Plugin v3.7 宿主桥 · Seatbelt 沙箱 · WebDAV 备份',
      dag_search: 'LCNTIDX3 mmap 零拷贝快照 · getattrlistbulk · FSEvents 实时增量 · 批量改名预检',
      dag_media: '逐屏冻屏 11 工具矢量标注 · 滚动长截图 · Vision 离线 OCR · hev1 4K 硬解 · 原生 Markdown',
      dag_sys: 'Mach/IOKit 功耗遥测 · nettop 进程网速 · 120Hz 鼠标平滑滚轮 · 三层热键防冲突',
      dag_found: '晴霜/曜石双主题模型 · 中英双语免重启 · LCNTVLT2 256-bit AES-GCM 密钥箱 · ProcessSupervisor',
      dl_eyebrow: 'START BUILDING YOUR LUCENT · 立即免费使用',
      dl_title: '下载 10 MB 轻巧底座，\n搭出最懂你的效率流',
      dl_desc: 'MIT 协议免费开源，支持 macOS 14.0+ 全系 M1 / M2 / M3 / M4 设备。拖入应用程序即可开箱使用，11 款官方插件全原生 Swift 二进制（零 Python 依赖），并支持应用内一键更新保留本机权限：',
      dl_btn_dmg: '下载最新 DMG 安装包',
      dl_btn_store: '浏览 11 款官方插件库',
      dl_btn_star: 'GitHub 点亮 Star',
      term_tab_mcp: '接入 AI / MCP',
      term_tab_plugins: '11 款官方插件',
      term_tab_install: '免重授权 & 源码',
      term_copy: '复制代码',
      foot_brand: 'Lucent 流光',
      foot_3d_exp: '前往 3D 舞台',
      foot_plugin_doc: '插件与 MCP 规范',
      foot_docs: '工程文档',
      foot_contrib: '参与共建',
      placeholder_search: '直接打字搜软件、移动硬盘文件、算式，或试输：tr 翻译 / bh 书签 / rem 10m 喝水...'
    },
    en: {
      brand_cn: '',
      nav_launcher: 'Launch Panel',
      nav_compare: 'Compare',
      nav_builder: 'Customize',
      nav_theatre: 'AI & MCP',
      nav_bento: 'Native Tools',
      nav_philosophy: 'Philosophy',
      nav_arch: 'Architecture',
      nav_3d_exp: '3D Stage',
      nav_download: 'Get DMG',
      theme_frost: 'Light Frost',
      theme_prism: 'Obsidian Dark',
      hero_capsule: 'MIT Open Source · ~10 MB Swift 6 · Zero Subscriptions · Zero Login',
      hero_title_1: 'One 10 MB Native Hub.',
      hero_title_2: 'Replaces Five Paid Apps.',
      hero_subtitle: 'Press ⌥Space for disk search, scroll capture & click-through pins, GIF/MP4, 120Hz mouse wheel & magnetic File Shelf — build plugins in 10s via Claude Code.',
      cta_download: 'Download macOS DMG',
      cta_builder: 'Customize Lucent',
      cta_3d_exp: 'Open 3D Stage →',
      preset_try: 'Switch Launch Panel / Try Search:',
      preset_bento: 'Balanced Home',
      preset_home_min: 'Minimal 16-Slot Dock',
      preset_home_dev: 'Developer Hub & Shelves',
      preset_home_shelf: '4-Col Bento & Shelves',
      preset_translate: 'Selection / OCR Translate',
      preset_remind: '10m Water Reminder',
      preset_dev: 'Math & Color Swatch',
      scope_all: 'All',
      scope_plugins: 'Plugins',
      scope_files: 'Files',
      scope_clip: 'Clipboard',
      drawer_foot_nav: '↑↓ Select · ↵ Run · Esc Close',
      hint_open: 'Run / Open',
      hint_actions: 'Actions',
      hint_scope: 'Cycle Scope',
      hint_tab: 'Context Menu',
      scroll_hint: 'Scroll down to compare with major launchers & explore AI co-creation',
      cmp_eyebrow: 'WHY LUCENT · AT A GLANCE',
      cmp_title: 'Paid Elsewhere, |Free & Native Here',
      cmp_desc: 'Open-source, zero AI markup, five utilities in one ~10 MB native app.',
      cmp_h_dim: 'Dimension',
      cmp_h_lucent: 'Lucent',
      cmp_h_raycast: 'Raycast (Free / Pro)',
      cmp_h_utools: 'uTools',
      cmp_h_alfred: 'Alfred + Add-On Apps',
      cmp_r1_k: 'License & Price',
      cmp_r1_l: '<strong>MIT Open Source · Free · No Login</strong>',
      cmp_r1_r: 'Closed · Pro for Sync / AI',
      cmp_r1_u: 'Closed · Account & VIP',
      cmp_r1_a: 'Closed · Paid + 4–5 Apps',
      cmp_r2_k: 'AI / MCP',
      cmp_r2_l: '<strong>21 MCP · Bring Your Own AI</strong>',
      cmp_r2_r: 'Paid AI Credits',
      cmp_r2_u: 'Proprietary AI VIP',
      cmp_r2_a: 'No native MCP',
      cmp_r3_k: 'Native Utilities',
      cmp_r3_l: '<strong>Scroll Capture · Pins · GIF/MP4 · 120Hz Wheel · Shelf</strong>',
      cmp_r3_r: 'None built-in',
      cmp_r3_u: '3rd-party plugins',
      cmp_r3_a: '4–5 separate apps',
      cmp_r4_k: 'Plugins & HUDs',
      cmp_r4_l: '<strong>Native UI + Click-Through HUDs + Sandbox</strong>',
      cmp_r4_r: 'Lists / forms only',
      cmp_r4_u: 'Electron windows',
      cmp_r4_a: 'Lists / Workflows',
      cmp_r5_k: 'Footprint',
      cmp_r5_l: '<strong>~10 MB Swift 6 · Ephemeral</strong>',
      cmp_r5_r: 'Native + Node runtime',
      cmp_r5_u: 'Electron runtime',
      cmp_r5_a: 'Multiple resident apps',
      builder_eyebrow: 'DEEP CUSTOMIZATION WORKBENCH',
      builder_title: 'Built Your Way, |Zero RAM When Off',
      builder_desc: 'All 11 native Swift plugins stay off by default with zero background polling — enable only what you use.',
      jump_3d_plugins: 'Explore Plugins in 3D Stage →',
      prof_minimal: 'Pure Micro-Core (0 Plugins)',
      prof_daily: 'Everyday Essentials Pack',
      prof_dev: 'Geek AI & Floating HUDs',
      prof_full: 'All 11 Official + AI Custom',
      cat_head_title: '11 Official Native Swift Plugins + AI Custom Example',
      prev_live_badge: 'Live Sync: Updates Launch Panel & Menu Bar Above',
      zone_quick_title: 'Mounted to Launch Panel Shelf & Menu Bar (Off by Default)',
      zone_accepts_title: 'Cross-Module ⌘K Actions & Context Hooks (OCR / Clipboard / Workspace)',
      theatre_eyebrow: 'ZERO AI MARKUP · 21 EMBEDDED MCP TOOLS FOR YOUR OWN AI CLIENT',
      theatre_title: 'Zero AI Subscriptions — |Turn Claude Code / Cursor into Your Plugin Factory',
      jump_3d_mcp: 'Explore MCP in 3D Stage →',
      s1_title: '21 MCP Tools: Scripts, Plugins & Layouts',
      s1_desc: 'Wire into Claude Code / Cursor — one sentence builds & hot-reloads in 350ms.',
      s2_title: 'Auto Settings + Click-Through Glass HUDs',
      s2_desc: 'One plugin.json renders native settings or 120Hz edge-docking glass widgets.',
      s3_title: 'Paste Any Link to Install & Upgrade Losslessly',
      s3_desc: 'Auto-resolves GitHub or zips with SHA-256 checks while keeping your hotkeys & keys.',
      s4_title: 'Seatbelt Sandbox · AES-GCM Vault · WebDAV',
      s4_desc: 'Kernel-isolated plugins, 256-bit encrypted keys, and 1-click cross-Mac backup.',
      sc0_prompt: '"Build me a PR review plugin (token in encrypted vault), and create a Daily Dev Launch Panel profile with Dual Workspace, this new plugin, and a GitHub bookmark shelf."',
      sc0_st1: 'Reads built-in scripts-v1, plugin-v3 & home-layout-v1 specs + capability audit',
      sc0_st2: 'Scaffolds plugin or script & executes live test inside Seatbelt sandbox',
      sc0_st3: 'Creates new Home Profile, mounts tiles & supports read-only file lookup',
      sc0_live_t: 'Live in ⌥Space: New Plugin & "Daily Dev" Launch Panel Ready',
      sc0_try_btn: 'Try Above ↗',
      sc0_live_d: 'Zero app restart needed — revert any layout tweak anytime via 1-click Undo in Settings or MCP.',
      sc0_f1: '12 Plugin Lifecycle Tools',
      sc0_f2: '4 Quick Script + 4 Home Layout Tools',
      sc0_f3: 'lucent_search_files Snapshot Lookup',
      sc1_slider_t: 'Auto-Generated Native Settings UI (Drag Slider Below)',
      sc1_slider_d: 'Renders text, AES-GCM secrets, continuous sliders, dropdowns, path pickers & tags — saved immediately as you tweak:',
      sc1_hk_t: 'Silent Subcommand Hotkeys & Overrides',
      sc1_hk_d: 'Bind global hotkeys to any subcommand for silent background execution; click to test conflict checks:',
      sc1_dl_t: 'Freeform Transparent Desktop Widgets',
      sc1_dl_d: 'Supports frameless blurred HUDs, edge snapping & restart restore; click below to toggle compact mode:',
      sc1_f1: 'Host-Brokered macOS TCC Auth',
      sc1_f2: 'Live Bilingual & Theme Sync',
      sc1_f3: '3-Tier Hotkey Conflict Guard',
      sniff_btn_1: 'Paste Repo Subdirectory',
      sniff_btn_2: 'Paste Registry JSON',
      sniff_btn_3: 'Paste Plugin Zip Package',
      sc2_verify_t: 'Anti-Spoofing Capability Check',
      sc2_verify_d: 'Verifies 64-bit SHA-256 fingerprint and cross-checks packaged plugin.json permissions against store declarations before install.',
      sc2_upg_t: 'Lossless One-Click Upgrades',
      sc2_upg_d: 'Read-only plugin code stays separate from personal PluginData, preserving custom keywords, hotkeys, and encrypted tokens.',
      sc2_f1: '1-Command lucent_package_plugin_for_store',
      sc2_f2: 'Preserves TCC Permissions Across Updates',
      sc3_r1: 'Undeclared network or subprocess calls blocked at kernel level; Keychain & private dirs isolated',
      sc3_r2: 'Scoped Host Bridges (OCR, selection, capture, audio, notify) via one-time 0700 UDS token',
      sc3_r3: 'Dual-track 256-bit random master key AES-GCM vault with zero plaintext on disk',
      sc3_r4: 'LZFSE archive syncs Launch Panel profiles, Quick Scripts, custom plugins & secrets via WebDAV / NAS',
      sc3_f1: 'Full Permission Audit Matrix',
      sc3_f2: 'Auto Timeout Subprocess Reaping',
      sc3_f3: 'HKDF + AES-GCM Backup Passphrase',
      bento_eyebrow: 'EVERYDAY NATIVE ESSENTIALS',
      bento_title: 'One 10 MB Core, |Five Resident Apps Gone',
      bento_desc: 'Search, capture, pins, recording, OCR & smooth mouse wheel — built natively, freed on close.',
      hk_all: 'All Built-In Tools',
      hk_search: 'Custom Home & Disk Search',
      hk_shot: 'Capture · GIF · Offline OCR',
      hk_pulse: 'Chip Wattage Pill',
      hk_net: 'App Bandwidth & Cache',
      hk_ws: 'Dual Pane & Smooth Wheel',
      fc1_title: 'Launch Panel · Disk Search · ⌘K & Clipboard',
      fc1_desc: 'Custom home, instant internal/external drive search, 15-step undo clipboard & ⌘K actions.',
      fc1_c1: '⌘K Contextual Action Drawer',
      fc1_c2: 'LCNTIDX3 mmap 0-Copy Search',
      fc1_c3: 'SearchAffinity Smart Ranking',
      fc2_title: 'Capture · Scroll Stitch · GIF/MP4 · Pins',
      fc2_desc: '11-tool vector capture, scrolling stitch, press-T click-through pins, GIF/MP4 & offline OCR.',
      fc2_c1: 'ScreenCaptureKit Freeze Capture',
      fc2_c2: 'Scrolling Stitch & GIF89a',
      fc2_c3: 'Local Offline Vision OCR',
      fc3_title: 'Chip Wattage Pill',
      fc3_desc: 'Off by default; shows live P/E-core load & wattage (W) with edge auto-hide.',
      fc4_title: 'App Bandwidth & Cache Cleaner',
      fc4_desc: 'Rootless per-app network speed monitor & safe cache cleanup to Trash.',
      fc5_title: '120Hz Mouse Wheel & Dual Pane',
      fc5_desc: 'Smooth external mouse scroll (Trackpad untouched) + on-demand dual-pane file workspace.',
      phil_eyebrow: 'CORE PHILOSOPHY',
      phil_title: 'Restrained Core, |Boundless Freedom',
      phil_desc: 'Effortless out of the box, grows on demand, never slows your Mac.',
      p1_title: 'Customizable Without Bloat',
      p1_desc: 'Great defaults; customize panels, menu bar, silent hotkeys & AI plugins anytime.',
      p2_title: '~10 MB Pure Swift 6',
      p2_desc: 'Zero external packages, wired directly to Apple Silicon frameworks.',
      p3_title: 'Locked 880×544 Muscle Memory',
      p3_desc: 'Zero layout jumps, CJK IME safe, selection anchored during updates.',
      p4_title: 'Ephemeral & Sandboxed',
      p4_desc: '30s UI teardown, 90s index unload, Seatbelt sandbox & AES-GCM vault.',
      duality_eyebrow: 'LIGHT FROST & OBSIDIAN DARK · DUAL LIQUID GLASS THEMES',
      duality_title: 'Crisp Porcelain in Light Frost, |or Deep Glass in Obsidian Dark',
      duality_desc: 'Follows macOS system appearance automatically by default, or click either live mini desktop card to switch instantly — synced across every open native window and floating plugin HUD.',
      btn_frost: 'Light Frost',
      btn_prism: 'Obsidian Dark',
      bound_title: 'Clear Product Boundaries: |Leave Freedom to Customization, Keep the Core Light',
      bound_sub: 'Knowing what to polish natively and what never to force into the base keeps your Mac fast.',
      yes_1: '<strong>Your Interface, Your Rules:</strong> Launch Panel zones, ⌘K action flow, Quick Scripts, status bar items, global hotkeys & widgets are all opt-in and reorderable.',
      yes_2: '<strong>AI Customization Anyone Can Use:</strong> 21 built-in lucent-mcp tools and single-box store sniffing turn plain words into Quick Scripts, plugins, or layouts.',
      yes_3: '<strong>100% Built for Apple Silicon:</strong> Pure arm64 binaries wired directly to modern macOS 14+ frameworks.',
      no_1: '<strong>No Unremovable All-in-One Bloatware:</strong> Zero forced floating balls, menu-bar tickers, or background daemons out of the box.',
      no_2: '<strong>No Multi-Hundred-MB Web Shell for Main UI:</strong> Native Swift renders the hub & readers; optional plugin web windows destroy cleanly on close.',
      no_3: '<strong>No Unsandboxed Scripts or Unsafe Dirty-NTFS Writes:</strong> Enforces kernel Seatbelt, encrypted vaults, and read-only protection on dirty NTFS drives.',
      arch_eyebrow: 'UNDER THE HOOD FOR GEEKS',
      arch_title: 'Acyclic Swift 6 Module Layers · |Strictly ≤ 300 Lines per File',
      arch_desc: 'Every build runs automated gates verifying acyclic module boundaries, per-file ≤ 300 LOC limits, doc links, and live lucent-mcp JSON-RPC roundtrips.',
      jump_3d_dag: 'Inspect Architecture in 3D Stage →',
      m_1: 'Built-in lucent-mcp Script, Plugin, Home & Search Tools',
      m_2: 'External SwiftPM / CocoaPods Dependencies',
      m_3: 'Hard Max Lines per .swift Source File',
      m_4: 'UI Cache Teardown / Index Unmap Window',
      dag_app: 'SwiftUI + AppKit Dual-Theme UI · ⌘K Action Drawer · Launch Panel/Script Customizer · Freeform HUDs',
      dag_mcp: 'Embedded 21 JSON-RPC 2.0 Tools: Quick Scripts & SVG Icons, Plugin Scaffold, Home Layout & File Search',
      dag_core: 'HomeLayout Multi-Profile · OverlayActionCatalog · Quick Scripts · Plugin v3.7 Host · Seatbelt · Backup',
      dag_search: 'LCNTIDX3 mmap Snapshot · getattrlistbulk · Live FSEvents · Batch Rename Preflight',
      dag_media: 'Per-Display 11-Tool Vector Capture · Scrolling Stitch · Offline Vision OCR · hev1 4K · Native Markdown',
      dag_sys: 'Mach/IOKit Wattage · Rootless nettop · 120Hz Smooth Wheel · 3-Tier Hotkey Guard',
      dag_found: 'Light Frost / Obsidian Dark · Instant Bilingual · LCNTVLT2 256-bit Vault · ProcessSupervisor',
      dl_eyebrow: 'START BUILDING YOUR LUCENT',
      dl_title: 'Grab the ~10 MB Native Hub,\nShape Your Personal Flow',
      dl_desc: 'Free & open source (MIT) for macOS 14.0+ on M1 / M2 / M3 / M4 Macs. Drag to Applications to start — all 11 official plugins run as native Swift binaries (zero Python needed), with in-app DMG updates preserving local TCC permissions:',
      dl_btn_dmg: 'Download Latest DMG',
      dl_btn_store: 'Browse 11 Official Plugins',
      dl_btn_star: 'Star on GitHub',
      term_tab_mcp: 'AI & MCP',
      term_tab_plugins: '11 Plugins',
      term_tab_install: 'Sign & Build',
      term_copy: 'Copy',
      foot_brand: 'Lucent',
      foot_3d_exp: '3D Stage',
      foot_plugin_doc: 'Plugin & MCP Spec',
      foot_docs: 'Docs Index',
      foot_contrib: 'Contributing',
      placeholder_search: 'Type to search apps, external drives, math, or try: tr hello / bh safari / rem 10m water...'
    }
  };

  /* ------------------------------------------------------------------------
     6. All 11 Official Native Swift Plugins + 1 MCP Custom Example
     ------------------------------------------------------------------------ */
  const PLUGINS = [
    {
      id: 'translate-hub',
      icon: 'globe',
      tone: 'tone-indigo',
      tagZh: '官方旗舰',
      tagEn: 'Official',
      nameZh: '流光译站 Translate Hub',
      nameEn: 'Translate Hub',
      shortZh: '跨应用划词工具栏 / 离线 OCR 截图多源翻译、双语朗读与生词本',
      shortEn: 'Selection Quick Bar & offline OCR multi-engine translation + dual TTS',
      detailZh: `选中文本即弹悬浮快捷工具栏，零配置内置双语词典开箱即用，支持并行对比本地 Ollama 译文、双语 TTS 朗读、归档生词并通过 ${SCHEME_PREFIX}reader 打开或导出 Anki 词卡。`,
      detailEn: `Instant Selection Quick Bar + zero-config dictionary, parallel local Ollama LLM translation, dual TTS buttons, vocabulary notebook, native ${SCHEME_PREFIX}reader view & Anki export.`,
      quickZh: '划词秒译',
      quickEn: 'Translate',
      acceptsZh: ['选中文本秒译 (text)', 'OCR 截图翻译 (image)'],
      acceptsEn: ['Selection Text (text)', 'OCR Capture (image)'],
      sandbox: 'Seatbelt: network + filesystem · Bridge: selection, ocr, audio',
      cmds: [
        ['tr / fy', '⌥⇧T 静默划词译', '⌥⇧T Silent Selection'],
        ['tr ocr', '⌥⇧O 截图识字译', '⌥⇧O Screenshot OCR'],
        ['tr word', '收藏至生词本', 'Save to Vocab'],
        ['tr anki', '导出 Anki 词卡', 'Export Anki Deck']
      ]
    },
    {
      id: 'file-shelf',
      icon: 'tray',
      tone: 'tone-blue',
      tagZh: '液态浮窗',
      tagEn: 'Glass HUD',
      nameZh: '文件中转站 File Shelf',
      nameEn: 'File Shelf',
      shortZh: '原生液态玻璃三向磁吸边缘停靠浮窗，跨重启保存多文件引用与原生多选拖出',
      shortEn: '3-way magnetic edge-docking liquid-glass drop tray with cross-restart restore',
      detailZh: '采用 RoundedGlassContainerView 原生液态玻璃浮窗，支持左/右/上三向边缘磁吸停靠隐藏、悬停或拖入自动滑出、⌘K 一键送入及跨重启会话自动恢复，并校验源文件身份。',
      detailEn: 'Native liquid-glass floating tray with 3-way magnetic edge docking, hover/drag slide-out, ⌘K handoff, optional remove-on-drag-out, and cross-restart session restore.',
      quickZh: '文件中转站',
      quickEn: 'File Shelf',
      acceptsZh: ['文件/目录送入中转站 (file, directory)'],
      acceptsEn: ['Send File / Folder to Shelf (file, directory)'],
      sandbox: 'Seatbelt: filesystem · Native Floating Panel + Session Restore',
      cmds: [
        ['shelf', '呼出液态玻璃中转站', 'Toggle Floating Shelf'],
        ['⌘K → Shelf', '搜索结果一键放入', 'Send Hit via ⌘K'],
        ['Edge Snap', '贴边自动隐藏与滑出', 'Auto Edge-Snap Hide'],
        ['Drag Out', '原生多选拖出至任意 App', 'Multi-File Drag Out']
      ]
    },
    {
      id: 'audio-presets',
      icon: 'audio',
      tone: 'tone-cyan',
      tagZh: 'Core Audio',
      tagEn: 'Core Audio',
      nameZh: '一键音频组合 Audio Presets',
      nameEn: 'Audio Presets',
      shortZh: '无边框双主题液态玻璃悬浮控制台，一键切扬声器与麦克风组合',
      shortEn: 'Frameless dual-theme glass console to switch speaker & mic presets',
      detailZh: '保存常用输入/输出音频设备组合，支持靠边胶囊收起、点击设备卡直切单个设备，通过 Core Audio 回读核验并在部分失败时自动恢复，配合原生液态玻璃 HUD 反馈。',
      detailEn: 'Save input/output device pairs, collapse into an edge pill, switch single devices inline, verify via Core Audio readback with automatic rollback on partial failure.',
      quickZh: '音频组合',
      quickEn: 'Audio Deck',
      acceptsZh: [],
      acceptsEn: [],
      sandbox: 'Seatbelt: Core Audio bridge · Frameless Glass Console',
      cmds: [
        ['audio', '呼出悬浮音频控制台', 'Open Audio Console'],
        ['audio work', '一键切会议耳麦组合', 'Switch Meeting Preset'],
        ['audio studio', '切外接声卡监听组合', 'Switch Studio Preset'],
        ['Readback', 'Core Audio 实时回读核验', 'Verified Device Readback']
      ]
    },
    {
      id: 'antigravity-pulse',
      icon: 'pulse',
      tone: 'tone-indigo',
      tagZh: '统计大窗 · HUD',
      tagEn: 'Analytics + HUD',
      nameZh: 'Antigravity Pulse 用量与额度监控',
      nameEn: 'Antigravity Pulse',
      shortZh: '52 周 GitHub 风格自适应热力图、一键精美分享海报、缩边 HUD 与官方实时额度',
      shortEn: '52-week responsive token heatmap, 1-click Retina share poster, edge HUD & live quota',
      detailZh: '零侵入双层增量索引本地对话日志，提供缩边悬浮窗与独立可缩放全景统计大窗：内置 52 周自适应每日 M Token 贡献热力图与日期下钻、多维趋势与 24h 编码节律、模型/项目排行、USD/CNY 切换、一键生成 @2x Retina 分享海报复制剪贴板，以及官方 agy statusLine 共享/本机独享实时额度监控。',
      detailEn: 'Zero-intrusion dual-tier local transcript analytics with an edge-retractable HUD and resizable dashboard: full-width 52-week GitHub-style daily token heatmap with drill-down, trends & 24h coding rhythm, model/project rankings, USD/CNY switch, 1-click @2x Retina share poster copy, and official agy statusLine shared/exclusive quota tracking.',
      quickZh: 'Pulse 统计',
      quickEn: 'AG Pulse',
      acceptsZh: [],
      acceptsEn: [],
      sandbox: 'Seatbelt: read-only logs · floatingWindow + Native Clipboard Image',
      cmds: [
        ['agstat', '打开全景统计与热力图大窗', 'Open Usage & Heatmap Dashboard'],
        ['aghud', '呼出缩边悬停展开悬浮窗', 'Toggle Edge-Retractable HUD'],
        ['⌘⇧C Poster', '一键生成 Retina 分享海报', '1-Click Retina Share Poster'],
        ['statusLine', '官方共享 / 独享实时额度', 'Official Shared / Exclusive Quota']
      ]
    },
    {
      id: 'gold-monitor',
      icon: 'chart',
      tone: 'tone-orange',
      tagZh: '自由画布',
      tagEn: 'Freeform HUD',
      nameZh: '黄金大盘悬浮窗 Au99.99',
      nameEn: 'Gold Monitor Au99.99',
      shortZh: '实时监控上海金 Au99.99 / Au(T+D)，标准分时/Mini 条/贴边极简原地变形',
      shortEn: 'Live Shanghai Gold Au99.99 / Au(T+D) ticker with 3-state morphing HUD',
      detailZh: '实时跟踪人民币元/克黄金行情，支持标准分时图卡片、Mini 悬浮条与贴边极简挂件原地丝滑变形，内置滞回防抖价格预警与跨重启悬浮窗位置恢复。',
      detailEn: 'Tracks CNY/g spot gold in real time with smooth in-place morphing across chart card, mini bar, and edge widget, plus hysteresis price alerts and restart restore.',
      quickZh: 'Au99.99 行情',
      quickEn: 'Au99.99',
      acceptsZh: [],
      acceptsEn: [],
      sandbox: 'Seatbelt: scoped HTTPS · floatingWindow + Hysteresis Alerts',
      cmds: [
        ['gold', '展开分时图悬浮卡片', 'Open Chart Card HUD'],
        ['gold mini', '切换极简贴边报价条', 'Morph to Edge Ticker'],
        ['gold alert', '设置滞回防抖价格预警', 'Set Price Threshold'],
        ['Auto Restore', '跨重启自动恢复位置', 'Session Restore']
      ]
    },
    {
      id: 'browser-hub',
      icon: 'compass',
      tone: 'tone-blue',
      tagZh: '0ms 索引',
      tagEn: '0ms Index',
      nameZh: '三端书签与历史中枢 Browser Hub',
      nameEn: 'Browser Bookmarks & History Hub',
      shortZh: 'SQLite WAL 无锁直连 Edge、Chrome（多配置档）与 Safari 书签和历史',
      shortEn: 'Lock-free SQLite search across Edge, Chrome & Safari bookmarks/history',
      detailZh: '无锁读取三端浏览器全部 Profile 书签、Safari 阅读列表与近期历史，后台同步为 0ms 预建索引，在 ⌥Space 免前缀直接秒搜并按源浏览器打开。',
      detailEn: 'Reads Edge, Chrome multi-profile, and Safari bookmarks + history without DB locks, injecting a 0ms pre-built index into ⌥Space.',
      quickZh: '搜三端书签',
      quickEn: 'Bookmarks',
      acceptsZh: [],
      acceptsEn: [],
      sandbox: 'Seatbelt: read-only browser profiles · 0 Host Capabilities',
      cmds: [
        ['bh <词>', '0ms 全搜三端书签', '0ms Search All 3 Browsers'],
        ['bh hist', '检索近期浏览历史', 'Search Recent History'],
        ['bh sync', '刷新浏览器快照', 'Refresh Browser Snapshot'],
        ['↵ 回车', '原浏览器精准打开', 'Open in Source Browser']
      ]
    },
    {
      id: 'quick-remind',
      icon: 'clock',
      tone: 'tone-orange',
      tagZh: '零守护进程',
      tagEn: 'Zero Daemon',
      nameZh: '闪电提醒 Quick Remind',
      nameEn: 'Quick Remind',
      shortZh: '一句话自然语言倒计时（10m 喝水）直通 macOS 原生提醒事项',
      shortEn: 'Natural phrase timers ("10m water") synced to native macOS Reminders',
      detailZh: '支持「10m 喝水」「18:30 拿快递」「明天 9:00 交周报」，写入系统原生提醒事项并准点响铃——即使退出 Lucent 也绝不漏提醒，内置 25 分钟番茄钟。',
      detailEn: 'Parses natural phrases into native macOS Reminders so alerts fire reliably with zero background daemon, plus a 25m Pomodoro focus timer.',
      quickZh: '25m 番茄钟',
      quickEn: '25m Focus',
      acceptsZh: ['剪贴板文本转提醒 (text)'],
      acceptsEn: ['Clipboard Text to Reminder (text)'],
      sandbox: 'Seatbelt: Reminders sync · Bridge: audio',
      cmds: [
        ['rem 10m 喝水', '一句话设倒计时', 'Natural Language Timer'],
        ['rem pomo', '启动 25m 番茄钟', 'Start 25m Pomodoro'],
        ['rem list', '待办提醒看板', 'Upcoming Board'],
        ['rem snooze', '一键贪睡顺延 10m', 'Snooze +10m']
      ]
    },
    {
      id: 'mac-pilot',
      icon: 'sliders',
      tone: 'tone-graphite',
      tagZh: '官方旗舰',
      tagEn: 'Official',
      nameZh: '桌面中控台 Mac Pilot',
      nameEn: 'Mac Pilot Control Deck',
      shortZh: '音量/防休眠控制、16 项系统设置免前缀直达、安全退盘与访达新建文件',
      shortEn: 'Volume/Caffeine, 16 System Settings panes, safe eject & Finder helper',
      detailZh: '将 16 个高频系统设置页（蓝牙/网络/显示器/隐私等）注入 0ms 索引，一键安全弹出外置硬盘、在当前访达目录防重名新建文件，以及秒退异常卡死应用。',
      detailEn: 'Injects 16 macOS System Settings panes into 0ms search, ejects external drives safely, creates files in active Finder folder, and quits hung apps.',
      quickZh: '防休眠开关',
      quickEn: 'Caffeine',
      acceptsZh: ['访达文件/目录快捷操作 (file, directory)'],
      acceptsEn: ['Finder File & Folder Actions (file, directory)'],
      sandbox: 'Seatbelt: scoped AppleEvents · Bridge: systemControl, clipboard',
      cmds: [
        ['vol / mute', '精准音量与静音', 'Precision Volume'],
        ['eject', '安全退外置磁盘', 'Safely Eject Drives'],
        ['new md', '访达原地新建文件', 'New File in Finder'],
        ['bluetooth', '0ms 直达系统设置', '0ms Settings Jump']
      ]
    },
    {
      id: 'screen-shield',
      icon: 'shield',
      tone: 'tone-green',
      tagZh: '防误触锁屏',
      tagEn: 'Input Shield',
      nameZh: '状态屏遮罩 Screen Shield',
      nameEn: 'Screen Shield',
      shortZh: '擦拭键盘屏幕防误触黑屏、任务运行中防误碰保护遮罩',
      shortEn: 'Multi-display keyboard/trackpad lock for cleaning or running tasks',
      detailZh: '一键覆盖全部显示器（清洁屏幕中 / 编译任务运行中请勿触碰 / 马上回来），拦截键盘与滚轮误触同时保持后台满速运行，长按 Esc 2 秒优雅解锁。',
      detailEn: 'Covers all displays and blocks accidental keystrokes/clicks while cleaning your Mac or running long builds; hold Esc for 2s to exit.',
      quickZh: '擦键盘锁屏',
      quickEn: 'Clean Lock',
      acceptsZh: [],
      acceptsEn: [],
      sandbox: 'Seatbelt: local status only · Bridge: systemControl',
      cmds: [
        ['clean', '开启清洁屏幕遮罩', 'Keyboard Cleaning Lock'],
        ['shield task', '任务运行防碰模式', 'Build/Task Guard'],
        ['shield brb', '暂离自定义标语屏', 'Custom BRB Screen'],
        ['Hold Esc 2s', '防误触安全退出', 'Hold Esc 2s Unlock']
      ]
    },
    {
      id: 'lumalink-companion',
      icon: 'wifi',
      tone: 'tone-cyan',
      tagZh: '远控伴侣',
      tagEn: 'Remote Hub',
      nameZh: '流光随行 LumaLink 远控伴侣',
      nameEn: 'LumaLink Companion',
      shortZh: '局域网/组网切换、6 位配对码与二维码、物理黑屏与 Retina HiDPI',
      shortEn: 'LAN/Tunnel switcher, 6-digit PIN & QR popup, Privacy Curtain & HiDPI',
      detailZh: '纯外部沙盒（零额外资源权限）配合受控宿主桥接，在 ⌥Space 内直接弹出高清配对二维码、切换多屏 HiDPI 与防窥黑屏。',
      detailEn: 'Zero-external-scope sandbox with scoped host bridge to pop up pairing QR codes, toggle Privacy Curtain, and switch multi-display HiDPI.',
      quickZh: '远控配对码',
      quickEn: 'Pairing QR',
      acceptsZh: [],
      acceptsEn: [],
      sandbox: 'Seatbelt: zero external scopes · Bridge: lumaLinkStatus',
      cmds: [
        ['lumalink qr', '弹出配对码与二维码', 'Show PIN & QR'],
        ['lumalink net', '秒切局域网/穿透网卡', 'Switch LAN / Tunnel'],
        ['lumalink curtain', '远控物理防窥黑屏', 'Privacy Curtain'],
        ['lumalink hidpi', '切换 Retina 清晰度', 'Toggle Retina HiDPI']
      ]
    },
    {
      id: 'notion-bookmarks',
      icon: 'bookmark',
      tone: 'tone-graphite',
      tagZh: 'AES-GCM 密钥箱',
      tagEn: 'Vault Secret',
      nameZh: 'Notion 加密书签箱 Notion Vault',
      nameEn: 'Notion Bookmarks Vault',
      shortZh: '双轨 AES-GCM 加密存储凭据，一键剪贴板链接入库与离线秒搜',
      shortEn: 'AES-GCM encrypted Notion token, 1-key URL save & 0ms search',
      detailZh: '集成凭据经 LCNTVLT2 256-bit 随机主密钥加密存储，支持为「保存当前剪贴板链接」绑定全局静默快捷键，并将云端书签同步至本地 0ms 索引。',
      detailEn: 'Stores your Notion token inside the 256-bit AES-GCM vault, saves clipboard URLs silently via hotkey, and syncs pages to 0ms local search.',
      quickZh: '速存 Notion',
      quickEn: 'Save URL',
      acceptsZh: ['网页链接与文本速存 (url, text)'],
      acceptsEn: ['Save URL & Text to Notion (url, text)'],
      sandbox: 'Seatbelt: HTTPS + PluginData · Vault: 256-bit AES-GCM',
      cmds: [
        ['bm save', '静默速存剪贴板 URL', 'Save Clipboard URL'],
        ['bm <词>', '0ms 秒搜已存页面', '0ms Search Pages'],
        ['bm sync', '增量同步云端数据库', 'Sync Cloud DB'],
        ['bm tag', '默认标签自动归类', 'Auto-Tag Bookmarks']
      ]
    },
    {
      id: 'gh-pr-radar',
      icon: 'git',
      tone: 'tone-blue',
      tagZh: 'MCP 10s 自制',
      tagEn: 'MCP Custom',
      nameZh: 'PR 审查雷达 (AI 一句话生成示例)',
      nameEn: 'PR Review Radar (MCP AI-Generated)',
      shortZh: '通过 lucent-mcp 对 AI 说一句话生成的个人专属工作流插件',
      shortEn: 'Custom personal workflow plugin generated in 10s via lucent-mcp',
      detailZh: '演示「不会写代码也能定制」：只需在 Claude Code 或 Cursor 中描述私有业务需求（工单、PR、探针或主页排布），AI 自动脚手架生成、过 Seatbelt 实测并热重载挂载。',
      detailEn: 'Demonstrates 1-sentence customization: describe any private workflow and lucent-mcp scaffolds, Seatbelt-tests, and hot-reloads it automatically.',
      quickZh: '待审 PR (3)',
      quickEn: 'Open PRs (3)',
      acceptsZh: ['代码仓库链接快速预审 (url)'],
      acceptsEn: ['Inspect Repo Link (url)'],
      sandbox: 'Seatbelt: scoped HTTPS · Hot-Reloaded via FSEvents',
      cmds: [
        ['pr review', '查看待我 Review 列表', 'List Pending PRs'],
        ['pr mine', '查看我发起的流水线', 'Check My Pipelines'],
        ['pr refresh', '后台静默刷新索引', 'Refresh Index'],
        [`${SCHEME_PREFIX}reader`, '原生预览变更摘要', 'Native Reader Diff']
      ]
    }
  ];

  const BUILDER_PROFILES = {
    minimal: [],
    daily: ['translate-hub', 'file-shelf', 'audio-presets', 'browser-hub', 'quick-remind', 'mac-pilot'],
    dev: ['antigravity-pulse', 'gold-monitor', 'file-shelf', 'browser-hub', 'lumalink-companion', 'gh-pr-radar'],
    full: PLUGINS.map((p) => p.id)
  };

  /* ------------------------------------------------------------------------
     7. Render Interactive Customization Workbench (#builder)
     ------------------------------------------------------------------------ */
  const toggleListEl = document.getElementById('pluginToggleList');
  const enabledCountBadge = document.getElementById('enabledCountBadge');
  const mountedQuickPills = document.getElementById('mountedQuickPills');
  const mountedAcceptsPills = document.getElementById('mountedAcceptsPills');
  const quickMountCount = document.getElementById('quickMountCount');
  const spotlightBox = document.getElementById('pluginSpotlightBox');
  const auditSummaryBar = document.getElementById('auditSummaryBar');
  const previewDaemonStat = document.getElementById('previewDaemonStat');

  function renderWorkbench(justEnabledId = null) {
    if (!toggleListEl) return;
    const zh = state.lang === 'zh';
    const enabledList = PLUGINS.filter((p) => state.enabledPlugins.has(p.id));

    if (enabledCountBadge) {
      enabledCountBadge.textContent = zh
        ? `已按需启用 ${enabledList.length} / ${PLUGINS.length}`
        : `${enabledList.length} / ${PLUGINS.length} Active`;
    }
    if (previewDaemonStat) {
      previewDaemonStat.textContent = zh ? '0 常驻守护进程 · 按需唤醒' : '0 Resident Daemons';
    }

    const prevScroll = toggleListEl.scrollTop;
    toggleListEl.innerHTML = PLUGINS.map((p) => {
      const isOn = state.enabledPlugins.has(p.id);
      const isFocused = state.focusedPluginId === p.id;
      const hopClass = justEnabledId === p.id ? ' icon-hop' : '';
      return `
        <div class="plugin-toggle-item ${isFocused ? 'focused' : ''}" data-plugin-id="${p.id}">
          <div class="plugin-toggle-left">
            <span class="squircle-badge ${p.tone}${hopClass}">${iconSvg(p.icon, 16)}</span>
            <div class="plugin-toggle-meta">
              <div class="plugin-toggle-name">
                <span>${zh ? p.nameZh : p.nameEn}</span>
                <span class="plugin-tag-pill">${zh ? p.tagZh : p.tagEn}</span>
              </div>
              <div class="plugin-toggle-desc">${zh ? p.shortZh : p.shortEn}</div>
            </div>
          </div>
          <button
            type="button"
            class="mac-switch ${isOn ? 'on' : ''}"
            data-switch-id="${p.id}"
            aria-label="${zh ? `切换 ${p.nameZh}` : `Toggle ${p.nameEn}`}"
            aria-pressed="${isOn}"
          ></button>
        </div>
      `;
    }).join('');
    toggleListEl.scrollTop = prevScroll;

    if (quickMountCount) {
      quickMountCount.textContent = zh ? `${enabledList.length} 个胶囊入口` : `${enabledList.length} Mounted`;
    }
    if (mountedQuickPills) {
      if (enabledList.length === 0) {
        mountedQuickPills.innerHTML = `<span class="empty-mount-note">${
          zh
            ? '当前为纯粹微内核模式：不挂载任何插件胶囊，保持极致留白，仅运行五大日常原生利器。'
            : 'Pure Micro-Core Mode: No plugin pills mounted; only the 5 built-in everyday native tools run.'
        }</span>`;
      } else {
        mountedQuickPills.innerHTML = enabledList
          .map((p) => {
            const splash = justEnabledId === p.id ? ' pill-splash' : '';
            return `<span class="mounted-pill${splash}">${iconSvg(p.icon, 13)}<span>${zh ? p.quickZh : p.quickEn}</span></span>`;
          })
          .join('');
      }
    }

    if (mountedAcceptsPills) {
      const hooks = [];
      enabledList.forEach((p) => {
        const arr = zh ? p.acceptsZh : p.acceptsEn;
        arr.forEach((h) => hooks.push({ icon: p.icon, label: h, fresh: justEnabledId === p.id }));
      });
      if (hooks.length === 0) {
        mountedAcceptsPills.innerHTML = `<span class="empty-mount-note">${
          zh
            ? '未挂载外部右键联动（开启「流光译站 / 文件中转站 / 桌面中控台 / Notion」即可自动接入 ⌘K 与右键菜单）。'
            : 'No context hooks mounted (enable Translate Hub, File Shelf, Mac Pilot, or Notion to inject actions into ⌘K & OCR).'
        }</span>`;
      } else {
        mountedAcceptsPills.innerHTML = hooks
          .map((h) => `<span class="mounted-pill${h.fresh ? ' pill-splash' : ''}">${iconSvg(h.icon, 13)}<span>${h.label}</span></span>`)
          .join('');
      }
    }

    const focused = PLUGINS.find((p) => p.id === state.focusedPluginId) || PLUGINS[0];
    const focusedOn = state.enabledPlugins.has(focused.id);
    if (spotlightBox && focused) {
      spotlightBox.innerHTML = `
        <div class="spotlight-head">
          <div class="spotlight-title-wrap">
            <span class="squircle-badge ${focused.tone}">${iconSvg(focused.icon, 16)}</span>
            <div>
              <div class="spotlight-title">${zh ? focused.nameZh : focused.nameEn}</div>
              <div class="mono" style="font-size:11px;color:var(--text-tertiary)">${focused.sandbox}</div>
            </div>
          </div>
          <span class="${focusedOn ? 'ok-pill' : 'subtle-chip'}">${
            focusedOn ? (zh ? '已挂载生效' : 'Mounted') : (zh ? '已停用 · 0 内存' : 'Disabled · 0 RAM')
          }</span>
        </div>
        <p class="spotlight-desc">${zh ? focused.detailZh : focused.detailEn}</p>
        <div class="cmd-sub-list">
          ${focused.cmds
            .map(([cmd, descZh, descEn]) => `<div class="cmd-sub-chip"><code class="mono">${cmd}</code><span>${zh ? descZh : (descEn || descZh)}</span></div>`)
            .join('')}
        </div>
      `;
    }

    if (auditSummaryBar) {
      auditSummaryBar.innerHTML = `
        <span class="audit-summary-left">${iconSvg('shield', 14)}<span>${
          zh
            ? `Seatbelt 沙箱强隔离 · 未启用扩展 (${PLUGINS.length - enabledList.length} 款) 零进程零轮询`
            : `Seatbelt Enforced · ${PLUGINS.length - enabledList.length} disabled plugin(s) use 0 RAM`
        }</span></span>
        <span class="mono">MenuBar + HomeLayout Synced</span>
      `;
    }

    toggleListEl.querySelectorAll('.plugin-toggle-item').forEach((row) => {
      row.addEventListener('click', (e) => {
        const pid = row.getAttribute('data-plugin-id');
        if (!pid) return;
        state.focusedPluginId = pid;
        let enabledNow = null;
        if (e.target.closest('.mac-switch')) {
          if (state.enabledPlugins.has(pid)) {
            state.enabledPlugins.delete(pid);
          } else {
            state.enabledPlugins.add(pid);
            enabledNow = pid;
          }
          state.builderProfile = 'custom';
          saveEnabledPlugins();
          syncProfileButtons();
          if (!prefersReducedMotion && enabledNow) {
            const rect = row.getBoundingClientRect();
            const ripple = document.createElement('span');
            ripple.className = 'fx-ripple fx-ripple-subtle';
            ripple.style.left = `${e.clientX - rect.left}px`;
            ripple.style.top = `${e.clientY - rect.top}px`;
            ripple.style.width = `${rect.width * 0.75}px`;
            ripple.style.height = `${rect.width * 0.75}px`;
            row.appendChild(ripple);
            setTimeout(() => ripple.remove(), 600);
          }
        }
        renderWorkbench(enabledNow);
        renderLauncher();
      });
    });
  }

  function syncProfileButtons() {
    document.querySelectorAll('#builderProfileBar .builder-profile-btn').forEach((btn) => {
      btn.classList.toggle('active', btn.dataset.profile === state.builderProfile);
    });
  }

  document.querySelectorAll('#builderProfileBar .builder-profile-btn').forEach((btn) => {
    btn.addEventListener('click', () => {
      const prof = btn.dataset.profile;
      const list = BUILDER_PROFILES[prof];
      if (!list) return;
      state.builderProfile = prof;
      state.enabledPlugins = new Set(list);
      saveEnabledPlugins();
      if (list.length > 0 && !state.enabledPlugins.has(state.focusedPluginId)) {
        state.focusedPluginId = list[0];
      }
      syncProfileButtons();
      renderWorkbench(list[0] || null);
      renderLauncher();
    });
  });

  /* ------------------------------------------------------------------------
     8. 880×544 Launch Panel Simulator (Full Keyboard + ⌘K Drawer + Context Menu)
     ------------------------------------------------------------------------ */
  const PRESETS = {
    bento: { queryZh: '', queryEn: '', scope: 'all', homeProfile: 'balanced' },
    home_min: { queryZh: '', queryEn: '', scope: 'all', homeProfile: 'minimal' },
    home_dev: { queryZh: '', queryEn: '', scope: 'all', homeProfile: 'developer' },
    home_shelf: { queryZh: '', queryEn: '', scope: 'all', homeProfile: 'creatorBookmarks' },
    translate: { queryZh: 'tr 用完即焚的微内核架构', queryEn: 'tr Ephemeral micro-core architecture', scope: 'all' },
    remind: { queryZh: 'rem 10m 站起来喝口水休息眼睛', queryEn: 'rem 10m Hydrate and rest eyes', scope: 'all' },
    dev: { queryZh: '256 * 1024 bytes to mb', queryEn: '256 * 1024 bytes to mb', scope: 'all' }
  };

  const CATALOG = [
    {
      id: 'item-translate',
      scopes: ['all', 'plugins'],
      match: ['tr', 'fy', 'translate', 'ephemeral', '翻译', '译站', 'ocr'],
      tone: 'tone-indigo',
      icon: 'globe',
      titleZh: '流光译站：Ephemeral micro-core architecture',
      titleEn: 'Translate Hub: Ephemeral micro-core architecture',
      subZh: 'Translate Hub · 内置词典 + 本地 Ollama + 双语 TTS · 按 ⌘K 更多动作',
      subEn: 'Translate Hub · Built-in Dict + Local Ollama + Dual TTS · Press ⌘K',
      shortcut: '⌘1',
      lens: {
        tag: 'Plugin v3.7 · translate-hub',
        bigZh: '双源秒译 + OCR',
        bigEn: 'Dual-Engine + OCR',
        descZh: '既可在 ⌥Space 输入 tr 翻译，也可在任意应用选中文字按静默热键 ⌥⇧T 或从 ⌥O 离线截图识字窗一键送译。',
        descEn: 'Run via tr in ⌥Space, trigger silently via ⌥⇧T on selected text, or hand off directly from ⌥O Vision OCR.',
        kvs: [
          ['Host Bridges', 'selection · ocr · audio'],
          ['Reader Deep Link', `${SCHEME_PREFIX}reader (Native MD)`],
          ['Vocab Export', 'Anki .tsv / .csv']
        ]
      }
    },
    {
      id: 'item-remind',
      scopes: ['all', 'plugins'],
      match: ['rem', '10m', '喝水', 'water', '提醒', '番茄', 'pomo'],
      tone: 'tone-orange',
      icon: 'clock',
      titleZh: '新建闪电提醒：10 分钟后「站起来喝口水休息眼睛」',
      titleEn: 'Create Quick Reminder: In 10m — "Hydrate & rest eyes"',
      subZh: 'Quick Remind · 零常驻进程直通系统提醒事项 · 准点系统级响铃',
      subEn: 'Quick Remind · Syncs to native macOS Reminders with 0 daemon',
      shortcut: '⌘1',
      lens: {
        tag: 'Plugin v3.7 · quick-remind',
        bigZh: 'T-10:00',
        bigEn: 'T-10:00',
        descZh: '支持「10m 喝水」「18:30 拿快递」「明天 9:00 交周报」与 25m 番茄专注，退出软件亦由 macOS 准时提醒。',
        descEn: 'Supports relative ("10m") & calendar times plus 25m Pomodoro; persisted natively in macOS Reminders.',
        kvs: [
          ['Daemon Overhead', '0 MB (Native Reminders)'],
          ['Quick Action', '↵ Create · ⌘K Actions'],
          ['Pin Support', 'Right-Click → Home Shelf']
        ]
      }
    },
    {
      id: 'item-browser',
      scopes: ['all', 'plugins'],
      match: ['bh', 'apple', 'human', 'interface', 'bookmark', 'safari', 'chrome', 'edge', '书签'],
      tone: 'tone-blue',
      icon: 'compass',
      titleZh: 'Human Interface Guidelines — Apple Developer',
      titleEn: 'Human Interface Guidelines — Apple Developer',
      subZh: 'Browser Hub · 0ms 预建索引命中 · 按 ⌘K 或右键钉入主页书签架',
      subEn: 'Browser Hub · 0ms Pre-Indexed · Press ⌘K or right-click to pin',
      shortcut: '⌘1',
      lens: {
        tag: '0ms Pre-Indexed · browser-hub',
        bigZh: '0.2ms Hit',
        bigEn: '0.2ms Hit',
        descZh: '无锁读取 Safari、Chrome 与 Edge 书签及历史记录注入主搜索流，无需输入前缀也能直接秒搜网页收藏。',
        descEn: 'Lock-free SQLite snapshot across Safari, Chrome & Edge injected into 0ms unified search.',
        kvs: [
          ['Sandbox Scope', 'Read-Only Browser DBs'],
          ['Open Behavior', 'Source Browser Direct'],
          ['Home Pinning', 'Custom Browser Override']
        ]
      }
    },
    {
      id: 'calc-item',
      scopes: ['all'],
      match: ['256', 'mb', 'bytes', 'kb', 'gb', '*', '+', 'calc', 'hex', '换算'],
      tone: 'tone-cyan',
      icon: 'calc',
      titleZh: '262,144 Bytes = 0.25 MiB (0.262 MB)',
      titleEn: '262,144 Bytes = 0.25 MiB (0.262 MB)',
      subZh: '内置算式换算与 DevToolkit · 支持 #HEX 色板 / JWT / 时间戳 / 二维码',
      subEn: 'Built-in Math & DevToolkit · Evaluates #HEX, JWT, Timestamps & QR',
      shortcut: '⌘1',
      lens: {
        tag: 'Native Base · Unit & DevToolkit',
        bigZh: '0.25 MiB',
        bigEn: '0.25 MiB',
        descZh: '底座原生内置 10 类日常单位换算、数学算式、#HEX 对比度色板、UUID 与离线二维码生成。',
        descEn: 'Zero-plugin native math, 10-category unit conversions, #HEX contrast swatches, UUIDs & offline QR generator.',
        kvs: [
          ['Decimal (SI)', '0.262144 MB'],
          ['Binary (IEC)', '0.25 MiB / 256 KiB'],
          ['Hexadecimal', '0x40000']
        ]
      }
    },
    {
      id: 'file-1',
      scopes: ['all', 'files'],
      match: ['swift', 'lcnt', 'file', 'plugin', 'home', '文件'],
      tone: 'tone-orange',
      icon: 'file',
      titleZh: 'HomeCustomizationSettingsView.swift',
      titleEn: 'HomeCustomizationSettingsView.swift',
      subZh: 'Sources/Lucent · LCNTIDX3 mmap 零拷贝全盘与外置硬盘秒搜命中',
      subEn: 'Sources/Lucent · Instant LCNTIDX3 mmap internal & external drive hit',
      shortcut: '⌘2',
      lens: {
        tag: 'LCNTIDX3 · Zero-WebKit Reader',
        bigZh: '≤ 300 Lines',
        bigEn: '≤ 300 Lines',
        descZh: '按 ↵ 在纯原生代码阅读窗秒开（0 MB 网页内核开销），按 ⌘K 放进文件中转站或在访达定位。',
        descEn: 'Press ↵ for pure-Swift reader (0 MB WebKit), or press ⌘K to send to File Shelf or reveal in Finder.',
        kvs: [
          ['Index Format', 'LCNTIDX3 mmap + FSEvents'],
          ['External Drives', 'Supported + NTFS Guard'],
          ['Idle Unload', '90s Auto Heap Return']
        ]
      }
    },
    {
      id: 'clip-1',
      scopes: ['all', 'clip'],
      match: ['clip', 'paste', 'mcp', '剪贴板'],
      tone: 'tone-green',
      icon: 'clipboard',
      titleZh: 'claude mcp add lucent /Applications/Lucent.app/Contents/MacOS/lucent-mcp',
      titleEn: 'claude mcp add lucent /Applications/Lucent.app/Contents/MacOS/lucent-mcp',
      subZh: '剪贴板历史 · 0600 本地持久化 · 15 步误删撤回 · 自动跳过密码条目',
      subEn: 'Clipboard History · 0600 Local Persistence · 15-step undo · Privacy-filtered',
      shortcut: '⌘3',
      lens: {
        tag: 'ClipboardMonitor · 15-Step Undo',
        bigZh: '0600 Persisted',
        bigEn: '0600 Persisted',
        descZh: '回车直接粘贴回前台应用，误删支持 15 步撤回，或按 ⌘K 一键交给声明了 accepts 的插件接着处理。',
        descEn: 'Press Return to paste straight into active app, undo up to 15 deletes, or press ⌘K to route to plugins.',
        kvs: [
          ['Media Support', 'Text · #HEX · Image · File · GIF'],
          ['Privacy Filter', 'Concealed / Transient Skipped'],
          ['Sync', '.lucentbackup + WebDAV']
        ]
      }
    }
  ];

  const leftPane = document.getElementById('launcherLeftPane');
  const rightLens = document.getElementById('launcherRightLens');
  const launcherInput = document.getElementById('launcherInput');
  const engineStatus = document.getElementById('panelEngineStatus');
  const actionDrawer = document.getElementById('panelActionDrawer');
  const drawerTargetTitle = document.getElementById('drawerTargetTitle');
  const drawerActionList = document.getElementById('drawerActionList');
  const contextMenu = document.getElementById('panelContextMenu');

  function getActiveTargetDescriptor() {
    const zh = state.lang === 'zh';
    if (state.currentMatches.length > 0 && (state.query.trim() || state.scope !== 'all')) {
      const m = state.currentMatches[state.selectedResultIdx] || state.currentMatches[0];
      if (m) {
        return {
          id: m.id,
          label: zh ? m.titleZh : m.titleEn,
          shortLabel: (zh ? m.titleZh : m.titleEn).slice(0, 14),
          icon: m.icon || 'file',
          kind: 'result'
        };
      }
    }
    return {
      id: `home-${state.homeProfile}`,
      label: zh ? '当前启动面板选中项' : 'Active Launch Panel Item',
      shortLabel: zh ? '快捷入口' : 'Quick Pin',
      icon: 'grid',
      kind: 'home'
    };
  }

  function isPinnedToHome(id) {
    return state.pinnedCustomItems.some((item) => item.id === id);
  }

  function togglePinToHome(target) {
    const zh = state.lang === 'zh';
    const idx = state.pinnedCustomItems.findIndex((x) => x.id === target.id);
    if (idx >= 0) {
      state.pinnedCustomItems.splice(idx, 1);
      showGlassToast(zh ? `已从启动面板胶囊架移除「${target.shortLabel}」` : `Unpinned "${target.shortLabel}" from Home`, 'accent');
    } else {
      state.pinnedCustomItems.unshift({
        id: target.id,
        label: target.shortLabel,
        icon: target.icon || 'pin'
      });
      if (state.pinnedCustomItems.length > 4) state.pinnedCustomItems.pop();
      showGlassToast(zh ? `已钉上启动面板胶囊架：${target.shortLabel}` : `Pinned to Home Shelf: ${target.shortLabel}`, 'ok');
    }
    if (!state.query.trim() && state.scope === 'all') {
      renderBentoHome();
    }
  }

  function buildActionsForTarget(target) {
    const zh = state.lang === 'zh';
    const pinned = isPinnedToHome(target.id);
    return [
      {
        id: 'pin',
        icon: 'pin',
        label: pinned
          ? (zh ? '从启动面板取消钉选' : 'Unpin from Launch Panel')
          : (zh ? '钉上启动面板胶囊架' : 'Pin to Launch Panel Shelf'),
        shortcut: '⌘P',
        run: () => togglePinToHome(target)
      },
      {
        id: 'shelf',
        icon: 'tray',
        label: zh ? '放进文件中转站 (File Shelf)' : 'Send to File Shelf',
        shortcut: '⌘S',
        run: () => showGlassToast(zh ? `已放入液态玻璃中转站：${target.shortLabel}` : `Added to File Shelf: ${target.shortLabel}`, 'ok')
      },
      {
        id: 'copy',
        icon: 'copy',
        label: zh ? '拷贝结果 / 指令文本' : 'Copy Result / Command',
        shortcut: '⌘C',
        run: async () => {
          try { await navigator.clipboard?.writeText(target.label); } catch (_) {}
          showGlassToast(zh ? `已拷贝：${target.shortLabel}` : `Copied: ${target.shortLabel}`, 'ok');
        }
      },
      {
        id: 'inspect',
        icon: 'crop',
        label: zh ? '离线 OCR / 在访达中显示' : 'Offline OCR / Reveal in Finder',
        shortcut: '⌘↵',
        run: () => showGlassToast(zh ? `已触发原生动作：${target.shortLabel}` : `Triggered native action: ${target.shortLabel}`, 'accent')
      }
    ];
  }

  function renderDrawerActions() {
    if (!drawerActionList || !state.drawerTarget) return;
    const actions = buildActionsForTarget(state.drawerTarget);
    drawerActionList.innerHTML = actions.map((act, idx) => `
      <button type="button" class="drawer-action-item ${idx === state.drawerSelectedIdx ? 'active' : ''}" data-drawer-idx="${idx}" role="option" aria-selected="${idx === state.drawerSelectedIdx}">
        <span class="drawer-action-left">
          ${iconSvg(act.icon, 14)}
          <span>${act.label}</span>
        </span>
        <kbd class="keycap">${act.shortcut}</kbd>
      </button>
    `).join('');

    drawerActionList.querySelectorAll('.drawer-action-item').forEach((btn) => {
      btn.addEventListener('mouseenter', () => {
        state.drawerSelectedIdx = Number(btn.dataset.drawerIdx || 0);
        drawerActionList.querySelectorAll('.drawer-action-item').forEach((b, i) => {
          b.classList.toggle('active', i === state.drawerSelectedIdx);
          b.setAttribute('aria-selected', String(i === state.drawerSelectedIdx));
        });
      });
      btn.addEventListener('click', () => {
        const idx = Number(btn.dataset.drawerIdx || 0);
        executeDrawerAction(idx);
      });
    });
  }

  function executeDrawerAction(idx) {
    if (!state.drawerTarget) return;
    const actions = buildActionsForTarget(state.drawerTarget);
    const chosen = actions[idx];
    closeActionDrawer();
    if (chosen) chosen.run();
  }

  function openActionDrawer(customTarget = null) {
    closeContextMenu();
    const target = customTarget || getActiveTargetDescriptor();
    state.drawerTarget = target;
    state.drawerSelectedIdx = 0;
    state.drawerOpen = true;
    if (drawerTargetTitle) drawerTargetTitle.textContent = target.label;
    renderDrawerActions();
    if (actionDrawer) {
      actionDrawer.classList.add('open');
      actionDrawer.setAttribute('aria-hidden', 'false');
    }
  }

  function closeActionDrawer() {
    state.drawerOpen = false;
    if (actionDrawer) {
      actionDrawer.classList.remove('open');
      actionDrawer.setAttribute('aria-hidden', 'true');
    }
  }

  /* Real Right-Click macOS Liquid Glass Context Menu */
  function openContextMenu(e, target) {
    e.preventDefault();
    closeActionDrawer();
    if (!contextMenu) return;
    const zh = state.lang === 'zh';
    const actions = buildActionsForTarget(target);

    contextMenu.innerHTML = `
      <div class="ctx-menu-header">${target.label}</div>
      ${actions.slice(0, 3).map((act, i) => `
        <button type="button" class="ctx-menu-item" data-ctx-idx="${i}" role="menuitem">
          <span class="ctx-menu-item-left">${iconSvg(act.icon, 14)}<span>${act.label}</span></span>
          <span class="mono" style="font-size:10.5px;opacity:0.72">${act.shortcut}</span>
        </button>
      `).join('')}
      <div class="ctx-menu-sep" role="separator"></div>
      <button type="button" class="ctx-menu-item" data-ctx-open-drawer="true" role="menuitem">
        <span class="ctx-menu-item-left">${iconSvg('command', 14)}<span>${zh ? '打开 ⌘K 全部上下文动作…' : 'Open ⌘K Action Drawer…'}</span></span>
        <span class="mono" style="font-size:10.5px;opacity:0.72">⌘K</span>
      </button>
    `;

    contextMenu.classList.add('open');
    contextMenu.setAttribute('aria-hidden', 'false');
    state.contextMenuOpen = true;

    const menuRect = contextMenu.getBoundingClientRect();
    const maxX = window.innerWidth - menuRect.width - 12;
    const maxY = window.innerHeight - menuRect.height - 12;
    const posX = Math.max(12, Math.min(e.clientX, maxX));
    const posY = Math.max(12, Math.min(e.clientY, maxY));
    contextMenu.style.left = `${posX}px`;
    contextMenu.style.top = `${posY}px`;

    contextMenu.querySelectorAll('[data-ctx-idx]').forEach((btn) => {
      btn.addEventListener('click', () => {
        const chosen = actions[Number(btn.dataset.ctxIdx)];
        closeContextMenu();
        if (chosen) chosen.run();
      });
    });

    contextMenu.querySelector('[data-ctx-open-drawer]')?.addEventListener('click', () => {
      closeContextMenu();
      openActionDrawer(target);
    });
  }

  function closeContextMenu() {
    if (!state.contextMenuOpen) return;
    state.contextMenuOpen = false;
    if (contextMenu) {
      contextMenu.classList.remove('open');
      contextMenu.setAttribute('aria-hidden', 'true');
    }
  }

  document.addEventListener('click', (e) => {
    if (state.contextMenuOpen && !e.target.closest('#panelContextMenu')) {
      closeContextMenu();
    }
    if (
      state.drawerOpen &&
      !e.target.closest('#panelActionDrawer') &&
      !e.target.closest('[data-footer-act="actions"]')
    ) {
      closeActionDrawer();
    }
  });

  document.getElementById('drawerCloseBtn')?.addEventListener('click', closeActionDrawer);

  function renderBentoHome() {
    const zh = state.lang === 'zh';
    const enabledList = PLUGINS.filter((p) => state.enabledPlugins.has(p.id));
    const prof = state.homeProfile || 'balanced';
    state.currentMatches = [];

    let leftHtml = '';
    let lensTag = '';
    let lensBig = '';
    let lensDesc = '';
    let lensKvs = [];
    let statusLabel = '';

    const userPinnedHtml = state.pinnedCustomItems.map((it) => `
      <span class="quick-btn-pill pill-pinned-user" data-ctx-id="${it.id}" data-ctx-label="${it.label}" data-ctx-icon="${it.icon}">
        ${iconSvg(it.icon, 12)}<span>${it.label}</span>
      </span>
    `).join('');

    if (prof === 'minimal') {
      statusLabel = `Home: Minimal Focus · ${enabledList.length} Active Plugins`;
      const dockRows = [
        [
          { tone: 'tone-blue', icon: 'terminal', label: 'Xcode' },
          { tone: 'tone-graphite', icon: 'terminal', label: 'Ghostty' },
          { tone: 'tone-indigo', icon: 'command', label: 'Cursor' },
          { tone: 'tone-cyan', icon: 'compass', label: 'Safari' }
        ],
        [
          { tone: 'tone-indigo', icon: 'globe', label: zh ? '流光译站' : 'Translate' },
          { tone: 'tone-blue', icon: 'folder', label: '~/Code' },
          { tone: 'tone-graphite', icon: 'git', label: 'GitHub' },
          { tone: 'tone-green', icon: 'tray', label: zh ? '中转站' : 'Shelf' }
        ]
      ];
      leftHtml = `
        <div class="home-profile-strip">
          <span>${zh ? '当前启动面板方案：极简纯搜 (已隐藏大磁贴与底部提示)' : 'Active Profile: Minimal Focus (Bento & Tips Hidden)'}</span>
          <span class="mono">2×8 Omni Dock</span>
        </div>
        <div class="dock-strip-label">
          <span>${zh ? '双排混合高频坞 (本机 App + 插件 + 目录 + 书签混排)' : '2-Row Hybrid Omni Dock (Apps + Plugins + Folders + URLs)'}</span>
          <span class="mono">⌘1..8</span>
        </div>
        ${dockRows.map((row) => `
          <div class="dock-mini-row">
            ${row.map((it) => `<div class="dock-app-pill" data-ctx-id="dock-${it.label}" data-ctx-label="${it.label}" data-ctx-icon="${it.icon}"><span class="dock-app-dot ${it.tone}">${iconSvg(it.icon, 11)}</span>${it.label}</div>`).join('')}
          </div>
        `).join('')}
        <div class="quick-btn-bar-mock">
          <span class="quick-btn-label">${zh ? '快捷入口架：' : 'Quick Access:'}</span>
          ${userPinnedHtml}
          <span class="quick-btn-pill" data-preset-jump="translate">${iconSvg('crop', 12)}<span>${zh ? '区域截图' : 'Capture'}</span></span>
          <span class="quick-btn-pill" data-preset-jump="translate">${iconSvg('search', 12)}<span>${zh ? '离线识字' : 'Offline OCR'}</span></span>
          <span class="quick-btn-pill" data-preset-jump="remind">${iconSvg('clipboard', 12)}<span>${zh ? '剪贴板历史' : 'Clipboard'}</span></span>
          <span class="quick-btn-pill" data-preset-jump="dev">${iconSvg('calc', 12)}<span>${zh ? '算式换算' : 'Unit Math'}</span></span>
        </div>
      `;
      lensTag = 'HomeLayoutPreset · minimal';
      lensBig = zh ? '极简双排混合坞' : 'Minimal 16-Slot';
      lensDesc = zh
        ? '不喜欢花哨磁贴？一键切换「极简纯搜」方案即可关掉大号 Bento 磁贴，只留双排混合高频坞；右键任意条目即可钉入胶囊架或打开 ⌘K 动作抽屉。'
        : 'Prefer zero visual clutter? Minimal Focus hides Bento tiles, leaving a clean 2-row hybrid Omni Dock. Right-click any item to pin or press ⌘K for actions.';
      lensKvs = [
        [zh ? '可见分区' : 'Visible Zones', 'omniDock (2 Rows) + pillShelves'],
        [zh ? '补位策略' : 'Fill Mode', 'smartHybrid (Pinned + log₂)'],
        [zh ? '安全回退' : 'Safety Undo', '1-Click undoLastChange']
      ];
    } else if (prof === 'developer') {
      statusLabel = `Home: Developer Workbench · ${enabledList.length} Active Plugins`;
      const devTiles = [
        { tone: 'tone-blue', icon: 'columns', t: zh ? '双栏文件台' : 'Workspace', s: '⌥E · NTFS Guard' },
        { tone: 'tone-indigo', icon: 'pin', t: zh ? '贴图与标注' : 'Pin & Capture', s: '⌥A · 11 Tools' },
        { tone: 'tone-cyan', icon: 'search', t: zh ? '离线 OCR' : 'Offline OCR', s: '⌥O · Vision' },
        { tone: 'tone-blue', icon: 'network', t: zh ? '实时进程网速' : 'Socket Net', s: '⌥N · nettop' },
        { tone: 'tone-green', icon: 'pulse', t: zh ? '芯片功耗脉搏' : 'Chip Wattage', s: '⌥M · P/E Cores' },
        { tone: 'tone-orange', icon: 'trash', t: zh ? '缓存清理' : 'Cache Clean', s: 'Safe to Trash' }
      ];
      leftHtml = `
        <div class="bento-mini-grid">
          ${devTiles.map((tile, idx) => `
            <div class="bento-tile" data-dev-idx="${idx}" data-ctx-id="dev-${idx}" data-ctx-label="${tile.t}" data-ctx-icon="${tile.icon}">
              <span class="squircle-badge ${tile.tone}">${iconSvg(tile.icon, 16)}</span>
              <div>
                <div class="bento-tile-title">${tile.t}</div>
                <div class="bento-tile-sub mono">${tile.s}</div>
              </div>
            </div>
          `).join('')}
        </div>
        <div class="shelf-group-stack">
          <div class="quick-btn-bar-mock">
            <span class="quick-btn-label">${zh ? '开发书签架：' : 'Dev Bookmarks:'}</span>
            ${userPinnedHtml}
            <span class="quick-btn-pill" data-ctx-id="bm-gh" data-ctx-label="GitHub" data-ctx-icon="git">${iconSvg('git', 12)}<span>GitHub</span></span>
            <span class="quick-btn-pill" data-ctx-id="bm-loc" data-ctx-label="Localhost :3000" data-ctx-icon="terminal">${iconSvg('terminal', 12)}<span>Localhost :3000</span></span>
            <span class="quick-btn-pill" data-jump-builder="translate-hub">${iconSvg('globe', 12)}<span>Translate</span></span>
          </div>
          <div class="quick-btn-bar-mock">
            <span class="quick-btn-label">${zh ? '试搜芯片：' : 'Query Chips:'}</span>
            <span class="quick-btn-pill mono" data-fill-query="swift">ext:swift</span>
            <span class="quick-btn-pill mono" data-fill-query="256 * 1024 bytes to mb">256 KiB → MB</span>
            <span class="quick-btn-pill mono" data-fill-query="mcp">lucent-mcp</span>
          </div>
        </div>
      `;
      lensTag = 'HomeLayoutPreset · developer';
      lensBig = zh ? '开发者工作台主页' : 'Developer Hub';
      lensDesc = zh
        ? '专为写代码与联调配置的主页 Profile：置顶双栏整理台、功耗与网速监控，并挂载支持 cursor:// / vscode:// 协议的开发书签架；也可让 lucent-mcp 一句话自动编排。'
        : 'Tailored for coding & debugging: pins Dual Workspace, Wattage & Socket monitors alongside URL shelves supporting cursor:// and vscode://.';
      lensKvs = [
        [zh ? '书签协议白名单' : 'Safe URL Schemes', 'https · cursor · vscode · obsidian'],
        [zh ? '分组胶囊架' : 'Pill Shelves', zh ? '最多 6 组自定义命名架' : 'Up to 6 Named Shelves'],
        [zh ? 'AI 自动编排' : 'MCP Orchestration', 'lucent_update_home_layout']
      ];
    } else if (prof === 'creatorBookmarks') {
      statusLabel = `Home: 4-Col Apps & Bookmarks · ${enabledList.length} Active Plugins`;
      const compactTiles = [
        { tone: 'tone-blue', icon: 'crop', t: zh ? '区域截图' : 'Capture', s: '⌥A' },
        { tone: 'tone-red', icon: 'video', t: zh ? '录制 GIF' : 'GIF Rec', s: '⌥G' },
        { tone: 'tone-indigo', icon: 'search', t: zh ? '离线识字' : 'OCR', s: '⌥O' },
        { tone: 'tone-green', icon: 'clipboard', t: zh ? '剪贴板' : 'Clips', s: '15 Undo' },
        { tone: 'tone-blue', icon: 'tray', t: zh ? '中转站' : 'File Shelf', s: 'Plugin' },
        { tone: 'tone-cyan', icon: 'audio', t: zh ? '音频组合' : 'Audio', s: 'Plugin' },
        { tone: 'tone-orange', icon: 'chart', t: zh ? '黄金行情' : 'Au99.99', s: 'Plugin' },
        { tone: 'tone-indigo', icon: 'pulse', t: zh ? 'Pulse' : 'AG Pulse', s: 'Plugin' }
      ];
      leftHtml = `
        <div class="bento-mini-grid cols-4">
          ${compactTiles.map((tile, idx) => `
            <div class="bento-tile" data-jump-builder="file-shelf" data-ctx-id="c4-${idx}" data-ctx-label="${tile.t}" data-ctx-icon="${tile.icon}">
              <span class="squircle-badge ${tile.tone}">${iconSvg(tile.icon, 14)}</span>
              <div>
                <div class="bento-tile-title">${tile.t}</div>
                <div class="bento-tile-sub mono">${tile.s}</div>
              </div>
            </div>
          `).join('')}
        </div>
        <div class="shelf-group-stack">
          <div class="quick-btn-bar-mock">
            <span class="quick-btn-label">${zh ? '精选书签架：' : 'Curated Web:'}</span>
            ${userPinnedHtml}
            <span class="quick-btn-pill" data-ctx-id="web-sf" data-ctx-label="Safari Reading" data-ctx-icon="compass">${iconSvg('compass', 12)}<span>${zh ? 'Safari 阅读单' : 'Reading List'}</span></span>
            <span class="quick-btn-pill" data-ctx-id="web-nt" data-ctx-label="Notion Vault" data-ctx-icon="bookmark">${iconSvg('bookmark', 12)}<span>${zh ? 'Notion 知识库' : 'Notion Vault'}</span></span>
          </div>
          <div class="quick-btn-bar-mock">
            <span class="quick-btn-label">${zh ? '已启用扩展：' : 'Active Plugins:'}</span>
            ${(enabledList.length > 0 ? enabledList.slice(0, 3) : PLUGINS.slice(0, 3)).map((p) => `
              <span class="quick-btn-pill" data-jump-builder="${p.id}">${iconSvg(p.icon, 12)}<span>${zh ? p.quickZh : p.quickEn}</span></span>
            `).join('')}
          </div>
        </div>
      `;
      lensTag = 'HomeLayoutPreset · 4-Column Bento';
      lensBig = zh ? '4 列紧凑 × 书签架' : '4-Col + Shelves';
      lensDesc = zh
        ? '高频入口比较多？把 Bento 磁贴切成 4 列紧凑模式即可一屏放下 8 枚磁贴，搭配多组命名书签架，搜到任何结果点右键或按 ⌘K 就能直接钉进来。'
        : 'Have lots of daily shortcuts? Switch Bento to 4-column compact density paired with named bookmark & custom plugin shelves.';
      lensKvs = [
        [zh ? '磁贴列数可选' : 'Bento Columns', '2 Wide / 3 Standard / 4 Compact'],
        [zh ? '单条目外观定制' : 'Per-Item Style', zh ? '自定义标题 / 图标 / 强调色' : 'Custom Title, Icon & Color'],
        [zh ? '跨机加密漫游' : 'Cross-Mac Sync', 'home-layout.json in Backup v2']
      ];
    } else {
      statusLabel = `Home: Balanced · ${enabledList.length} Active Plugin(s)`;
      const tiles = [
        { tone: 'tone-blue', icon: 'search', t: zh ? '全盘秒搜' : 'Disk Search', s: 'LCNTIDX3 mmap', scope: 'files' },
        { tone: 'tone-indigo', icon: 'compass', t: zh ? '三端书签' : 'Browser Hub', s: '0ms SQLite Index', fillQ: 'bh' },
        { tone: 'tone-cyan', icon: 'globe', t: zh ? '流光译站' : 'Translate Hub', s: 'Plugin · OCR/划词', preset: 'translate' },
        { tone: 'tone-orange', icon: 'crop', t: zh ? '截图与 GIF' : 'Capture & GIF', s: '⌥A / ⌥G / ⌥O', jump: '#capabilities' },
        { tone: 'tone-green', icon: 'clock', t: zh ? '闪电提醒' : 'Quick Remind', s: 'Plugin · 10m 喝水', preset: 'remind' },
        { tone: 'tone-graphite', icon: 'grid', t: zh ? '高度定制台' : 'Customizer', s: `${enabledList.length} Active`, jump: '#builder' }
      ];

      const hasShelfItems = enabledList.length > 0 || state.pinnedCustomItems.length > 0;
      const quickBarHtml = hasShelfItems
        ? `
          <div class="quick-btn-bar-mock">
            <span class="quick-btn-label">${zh ? '已钉胶囊架：' : 'Pinned Shelf:'}</span>
            ${userPinnedHtml}
            ${enabledList.slice(0, 4).map((p) => `
              <span class="quick-btn-pill" data-jump-builder="${p.id}" data-ctx-id="plg-${p.id}" data-ctx-label="${zh ? p.quickZh : p.quickEn}" data-ctx-icon="${p.icon}">${iconSvg(p.icon, 12)}<span>${zh ? p.quickZh : p.quickEn}</span></span>
            `).join('')}
          </div>
        `
        : `
          <div class="quick-btn-bar-mock">
            <span class="quick-btn-label">${zh ? '纯净微内核态：未挂载任何扩展胶囊（可在下方定制台按需开启，或右键磁贴钉选）' : 'Pure Micro-Core: Plugin shelf hidden (enable below or right-click a tile to pin)'}</span>
          </div>
        `;

      leftHtml = `
        <div class="bento-mini-grid">
          ${tiles.map((tile, idx) => `
            <div class="bento-tile" data-bal-idx="${idx}" data-ctx-id="tile-${idx}" data-ctx-label="${tile.t}" data-ctx-icon="${tile.icon}">
              <span class="squircle-badge ${tile.tone}">${iconSvg(tile.icon, 16)}</span>
              <div>
                <div class="bento-tile-title">${tile.t}</div>
                <div class="bento-tile-sub mono">${tile.s}</div>
              </div>
            </div>
          `).join('')}
        </div>
        ${quickBarHtml}
        <div class="dock-strip-label">
          <span>${zh ? '混合高频应用坞 (手动钉选优先 + log₂ 智能常驻补位)' : 'Hybrid Omni Dock (Pinned First + log₂ Smart Fill)'}</span>
          <span class="mono">⌘1..4</span>
        </div>
        <div class="dock-mini-row">
          <div class="dock-app-pill" data-ctx-id="app-xcode" data-ctx-label="Xcode" data-ctx-icon="terminal"><span class="dock-app-dot tone-blue">${iconSvg('terminal', 11)}</span>Xcode</div>
          <div class="dock-app-pill" data-ctx-id="app-ghostty" data-ctx-label="Ghostty" data-ctx-icon="terminal"><span class="dock-app-dot tone-graphite">${iconSvg('terminal', 11)}</span>Ghostty</div>
          <div class="dock-app-pill" data-ctx-id="app-cursor" data-ctx-label="Cursor" data-ctx-icon="command"><span class="dock-app-dot tone-indigo">${iconSvg('command', 11)}</span>Cursor</div>
          <div class="dock-app-pill" data-ctx-id="app-safari" data-ctx-label="Safari" data-ctx-icon="compass"><span class="dock-app-dot tone-cyan">${iconSvg('compass', 11)}</span>Safari</div>
        </div>
      `;

      lensTag = zh ? '可定制启动面板 · ⌘K 动作流' : 'Custom Launch Panel · ⌘K';
      lensBig = zh ? '4 区自由编排' : '4 Modular Zones';
      lensDesc = zh
        ? '点击上方预设芯片即可切换 4 套主页方案；右键任意磁贴可呼出原生毛玻璃菜单「钉上启动面板」，或直接按 ⌘K 体验二级上下文动作抽屉。'
        : 'Switch 4 home layouts above, right-click any tile to open the macOS context menu and pin it to the shelf, or press ⌘K for the contextual action drawer.';
      lensKvs = [
        [zh ? '官方原生插件' : 'Official Plugins', zh ? '11 款纯 Swift 二进制' : '11 Native Swift Plugins'],
        [zh ? '视窗恒定尺寸' : 'Constant Frame', '880 × 544 (Zero-Jitter)'],
        [zh ? 'AI 定制工具数' : 'Embedded MCP', 'lucent-mcp (21 Tools)']
      ];

      leftPane.innerHTML = leftHtml;
      leftPane.querySelectorAll('[data-bal-idx]').forEach((el) => {
        el.addEventListener('click', () => {
          const t = tiles[Number(el.getAttribute('data-bal-idx'))];
          if (!t) return;
          if (t.preset) applyPreset(t.preset);
          else if (t.fillQ) {
            state.query = t.fillQ;
            if (launcherInput) launcherInput.value = t.fillQ;
            renderLauncher();
          } else if (t.scope) {
            state.scope = t.scope;
            syncScopeButtons();
            renderLauncher();
          } else if (t.jump) {
            document.querySelector(t.jump)?.scrollIntoView({ behavior: prefersReducedMotion ? 'auto' : 'smooth' });
          }
        });
      });
    }

    if (prof !== 'balanced') {
      leftPane.innerHTML = leftHtml;
    }

    if (engineStatus) engineStatus.textContent = statusLabel;

    rightLens.innerHTML = `
      <div class="lens-card">
        <div>
          <div class="lens-header">
            <span class="accent-pill">${lensTag}</span>
            <kbd class="keycap">⌘K</kbd>
          </div>
          <div class="lens-big-value">${lensBig}</div>
          <p class="lens-desc">${lensDesc}</p>
        </div>
        <div class="lens-kv-list">
          ${lensKvs.map(([k, v]) => `<div class="lens-kv"><span>${k}</span><span class="mono">${v}</span></div>`).join('')}
        </div>
      </div>
    `;

    // Wire home interactions & real right-click context menu on tiles / dock / pills
    leftPane.querySelectorAll('[data-jump-builder]').forEach((pill) => {
      pill.addEventListener('click', () => {
        state.focusedPluginId = pill.getAttribute('data-jump-builder') || 'translate-hub';
        renderWorkbench();
        document.getElementById('builder')?.scrollIntoView({ behavior: prefersReducedMotion ? 'auto' : 'smooth' });
      });
    });

    leftPane.querySelectorAll('[data-preset-jump]').forEach((pill) => {
      pill.addEventListener('click', () => applyPreset(pill.getAttribute('data-preset-jump')));
    });

    leftPane.querySelectorAll('[data-fill-query]').forEach((pill) => {
      pill.addEventListener('click', () => {
        const q = pill.getAttribute('data-fill-query') || '';
        state.query = q;
        if (launcherInput) launcherInput.value = q;
        document.querySelectorAll('.preset-chip').forEach((c) => c.classList.remove('active'));
        renderLauncher();
      });
    });

    leftPane.querySelectorAll('[data-dev-idx]').forEach((el) => {
      el.addEventListener('click', () => {
        const idx = Number(el.getAttribute('data-dev-idx'));
        if (idx === 2) applyPreset('translate');
        else document.getElementById('capabilities')?.scrollIntoView({ behavior: prefersReducedMotion ? 'auto' : 'smooth' });
      });
    });

    leftPane.querySelectorAll('[data-ctx-id]').forEach((el) => {
      el.addEventListener('contextmenu', (e) => {
        const id = el.getAttribute('data-ctx-id');
        const label = el.getAttribute('data-ctx-label') || 'Item';
        const icon = el.getAttribute('data-ctx-icon') || 'grid';
        openContextMenu(e, { id, label, shortLabel: label.slice(0, 12), icon, kind: 'tile' });
      });
    });
  }

  function renderLensForItem(item) {
    const zh = state.lang === 'zh';
    const l = item.lens;
    rightLens.innerHTML = `
      <div class="lens-card">
        <div>
          <div class="lens-header">
            <span class="accent-pill">${l.tag}</span>
            <kbd class="keycap">${item.shortcut}</kbd>
          </div>
          <div class="lens-big-value mono">${zh ? (l.bigZh || l.big) : (l.bigEn || l.big)}</div>
          <p class="lens-desc">${zh ? l.descZh : l.descEn}</p>
        </div>
        <div class="lens-kv-list">
          ${l.kvs.map(([k, v]) => `<div class="lens-kv"><span>${k}</span><span class="mono">${v}</span></div>`).join('')}
        </div>
      </div>
    `;
  }

  function updateResultSelection(idx) {
    const rows = Array.from(leftPane.querySelectorAll('.result-row'));
    if (rows.length === 0) return;
    const bounded = ((idx % rows.length) + rows.length) % rows.length;
    state.selectedResultIdx = bounded;
    rows.forEach((r, i) => r.classList.toggle('selected', i === bounded));
    const item = state.currentMatches[bounded];
    if (item) renderLensForItem(item);
  }

  function renderLauncher() {
    if (!leftPane || !rightLens) return;
    const q = state.query.trim().toLowerCase();
    const zh = state.lang === 'zh';

    if (!q && state.scope === 'all') {
      renderBentoHome();
      return;
    }

    let matches = CATALOG.filter((item) => {
      const inScope = state.scope === 'all' || item.scopes.includes(state.scope);
      if (!inScope) return false;
      if (!q) return true;
      return (
        item.match.some((m) => q.includes(m) || m.includes(q)) ||
        item.titleZh.toLowerCase().includes(q) ||
        item.titleEn.toLowerCase().includes(q)
      );
    });

    if (matches.length === 0) {
      matches = [
        {
          id: 'dynamic-search',
          tone: 'tone-blue',
          icon: 'search',
          titleZh: `并发检索全盘、剪贴板与已启用插件：“${state.query}”`,
          titleEn: `Unified Core + Plugin Match: "${state.query}"`,
          subZh: '同时扫描本地应用 · LCNTIDX3 外置硬盘与全盘 · 剪贴板 · 0ms 插件索引',
          subEn: 'Scans Apps · LCNTIDX3 Drives · Clipboard · 0ms Plugin Index',
          shortcut: '⌘1',
          lens: {
            tag: 'LauncherEngine · 0.3ms',
            bigZh: state.query.slice(0, 14),
            bigEn: state.query.slice(0, 14),
            descZh: '按 ⌘K 呼出上下文动作抽屉，或右键将任意结果钉上你的自定义启动面板。',
            descEn: 'Press ⌘K to open the contextual action drawer, or right-click to pin this item to your Launch Panel.',
            kvs: [
              ['Scope', state.scope.toUpperCase()],
              ['Frame Lock', '880 × 544 Constant'],
              ['Actions', '⌘K Drawer · Right-Click']
            ]
          }
        }
      ];
    }

    state.currentMatches = matches;
    state.selectedResultIdx = 0;

    if (engineStatus) {
      engineStatus.textContent = `Matched ${matches.length} item(s) · ↑↓ + ↵ / ⌘K · 0.3ms`;
    }

    leftPane.innerHTML = `
      <div class="result-list">
        ${matches.map((item, idx) => `
          <div class="result-row ${idx === 0 ? 'selected' : ''}" data-idx="${idx}">
            <div class="result-row-main">
              <span class="squircle-badge ${item.tone}" style="width:30px;height:30px;border-radius:8.5px">${iconSvg(item.icon, 14)}</span>
              <div class="result-text">
                <div class="result-title">${zh ? item.titleZh : item.titleEn}</div>
                <div class="result-sub">${zh ? item.subZh : item.subEn}</div>
              </div>
            </div>
            <kbd class="keycap">⌘${idx + 1}</kbd>
          </div>
        `).join('')}
      </div>
    `;

    renderLensForItem(matches[0]);

    leftPane.querySelectorAll('.result-row').forEach((row) => {
      const idx = Number(row.dataset.idx || 0);
      row.addEventListener('mouseenter', () => updateResultSelection(idx));
      row.addEventListener('click', () => {
        updateResultSelection(idx);
        const item = matches[idx];
        if (item) {
          const t = zh ? item.titleZh : item.titleEn;
          showGlassToast(zh ? `↵ 已执行：${t.slice(0, 20)}` : `↵ Executed: ${t.slice(0, 20)}`, 'ok');
        }
      });
      row.addEventListener('contextmenu', (e) => {
        updateResultSelection(idx);
        const item = matches[idx];
        if (!item) return;
        const label = zh ? item.titleZh : item.titleEn;
        openContextMenu(e, {
          id: item.id,
          label,
          shortLabel: label.slice(0, 12),
          icon: item.icon || 'file',
          kind: 'result'
        });
      });
    });
  }

  function syncScopeButtons() {
    document.querySelectorAll('.scope-pill').forEach((btn) => {
      btn.classList.toggle('active', btn.dataset.scope === state.scope);
    });
    syncGlider('#scopeCapsules', 'scopeGlider', '.scope-pill.active');
  }

  function applyPreset(presetKey) {
    const p = PRESETS[presetKey];
    if (!p) return;
    closeActionDrawer();
    closeContextMenu();
    state.preset = presetKey;
    if (p.homeProfile) state.homeProfile = p.homeProfile;
    const qVal = state.lang === 'zh' ? p.queryZh : p.queryEn;
    state.query = qVal;
    state.scope = p.scope;
    if (launcherInput) launcherInput.value = qVal;
    document.querySelectorAll('.preset-chip').forEach((chip) => {
      chip.classList.toggle('active', chip.dataset.preset === presetKey);
    });
    syncScopeButtons();
    renderLauncher();
  }

  document.querySelectorAll('.preset-chip').forEach((chip) => {
    chip.addEventListener('click', () => applyPreset(chip.dataset.preset));
  });

  document.querySelectorAll('.scope-pill').forEach((pill) => {
    pill.addEventListener('click', () => {
      state.scope = pill.dataset.scope;
      syncScopeButtons();
      renderLauncher();
    });
  });

  document.getElementById('heroFocusShortcutBtn')?.addEventListener('click', () => {
    document.getElementById('heroPanel')?.scrollIntoView({ behavior: prefersReducedMotion ? 'auto' : 'smooth', block: 'center' });
    setTimeout(() => launcherInput?.focus(), 200);
    showGlassToast(state.lang === 'zh' ? '⌥Space 已聚焦交互面板' : '⌥Space Launch Panel Focused', 'accent');
  });

  document.querySelectorAll('#panelFooterHints .footer-hint-btn').forEach((btn) => {
    btn.addEventListener('click', () => {
      const act = btn.dataset.footerAct;
      const zh = state.lang === 'zh';
      if (act === 'exec') {
        const t = getActiveTargetDescriptor();
        showGlassToast(zh ? `↵ 已执行：${t.shortLabel}` : `↵ Executed: ${t.shortLabel}`, 'ok');
      } else if (act === 'actions') {
        if (state.drawerOpen) closeActionDrawer();
        else openActionDrawer();
      } else if (act === 'tab') {
        const order = ['all', 'plugins', 'files', 'clip'];
        state.scope = order[(order.indexOf(state.scope) + 1) % order.length];
        syncScopeButtons();
        renderLauncher();
      } else if (act === 'pin') {
        showGlassToast(zh ? '在面板内任意磁贴或结果行右键即可呼出毛玻璃菜单' : 'Right-click any tile or search hit for context menu', 'accent');
      }
    });
  });

  launcherInput?.addEventListener('input', (e) => {
    state.query = e.target.value;
    closeActionDrawer();
    document.querySelectorAll('.preset-chip').forEach((c) => c.classList.remove('active'));
    renderLauncher();
  });

  // Full 880×544 Keyboard Loop: ↑ / ↓ / ↵ / ⌘K / Tab / Esc
  launcherInput?.addEventListener('keydown', (e) => {
    if ((e.metaKey || e.ctrlKey) && e.key.toLowerCase() === 'k') {
      e.preventDefault();
      e.stopPropagation();
      if (state.drawerOpen) closeActionDrawer();
      else openActionDrawer();
      return;
    }

    if (state.drawerOpen) {
      if (e.key === 'ArrowDown' || e.key === 'ArrowUp') {
        e.preventDefault();
        e.stopPropagation();
        const total = 4;
        state.drawerSelectedIdx = (state.drawerSelectedIdx + (e.key === 'ArrowDown' ? 1 : -1) + total) % total;
        renderDrawerActions();
      } else if (e.key === 'Enter') {
        e.preventDefault();
        e.stopPropagation();
        executeDrawerAction(state.drawerSelectedIdx);
      } else if (e.key === 'Escape') {
        e.preventDefault();
        e.stopPropagation();
        closeActionDrawer();
      }
      return;
    }

    if (e.key === 'ArrowDown' || e.key === 'ArrowUp') {
      if (state.currentMatches.length > 0) {
        e.preventDefault();
        updateResultSelection(state.selectedResultIdx + (e.key === 'ArrowDown' ? 1 : -1));
      }
    } else if (e.key === 'Enter') {
      e.preventDefault();
      const target = getActiveTargetDescriptor();
      showGlassToast(
        state.lang === 'zh' ? `↵ 已执行：${target.shortLabel}` : `↵ Executed: ${target.shortLabel}`,
        'ok'
      );
    } else if (e.key === 'Tab') {
      e.preventDefault();
      const order = ['all', 'plugins', 'files', 'clip'];
      state.scope = order[(order.indexOf(state.scope) + 1) % order.length];
      syncScopeButtons();
      renderLauncher();
    } else if (e.key === 'Escape') {
      e.stopPropagation();
      if (state.contextMenuOpen) {
        closeContextMenu();
      } else {
        applyPreset('bento');
        launcherInput.blur();
      }
    }
  });

  // Global Shortcuts: ⌥Space, ⌘K (when panel visible), Esc, ←/→ for #theatre
  window.addEventListener('keydown', (e) => {
    if (e.key === 'Escape') {
      if (e.target === launcherInput) return;
      if (state.contextMenuOpen) { closeContextMenu(); return; }
      if (state.drawerOpen) { closeActionDrawer(); return; }
    }

    if ((e.metaKey || e.ctrlKey) && e.key.toLowerCase() === 'k') {
      if (e.target === launcherInput) return;
      const panelRect = document.getElementById('heroPanel')?.getBoundingClientRect();
      if (panelRect && panelRect.bottom > 80 && panelRect.top < window.innerHeight - 60) {
        e.preventDefault();
        if (state.drawerOpen) closeActionDrawer();
        else openActionDrawer();
      }
      return;
    }

    if (state.drawerOpen && document.activeElement !== launcherInput) {
      if (e.key === 'ArrowDown' || e.key === 'ArrowUp') {
        e.preventDefault();
        state.drawerSelectedIdx = (state.drawerSelectedIdx + (e.key === 'ArrowDown' ? 1 : -1) + 4) % 4;
        renderDrawerActions();
      } else if (e.key === 'Enter') {
        e.preventDefault();
        executeDrawerAction(state.drawerSelectedIdx);
      }
      return;
    }

    if ((e.altKey && e.code === 'Space') || (e.key === '/' && document.activeElement !== launcherInput && !['INPUT', 'TEXTAREA'].includes(document.activeElement?.tagName))) {
      e.preventDefault();
      document.getElementById('heroPanel')?.scrollIntoView({ behavior: prefersReducedMotion ? 'auto' : 'smooth', block: 'center' });
      setTimeout(() => launcherInput?.focus(), 200);
      return;
    }

    // Theatre keyboard ← / → navigation when #theatre is in viewport
    if ((e.key === 'ArrowLeft' || e.key === 'ArrowRight') && document.activeElement !== launcherInput && document.activeElement?.getAttribute('role') !== 'slider') {
      const tr = theatreSection?.getBoundingClientRect();
      if (tr && tr.top < window.innerHeight * 0.55 && tr.bottom > window.innerHeight * 0.45) {
        e.preventDefault();
        const nextIdx = Math.max(0, Math.min(stepCards.length - 1, state.activeStep + (e.key === 'ArrowRight' ? 1 : -1)));
        navigateTheatreStep(nextIdx);
      }
    }
  });

  // Pointer-reactive specular sheen on the 880×544 Liquid Glass Panel
  const heroPanel = document.getElementById('heroPanel');
  if (heroPanel && !prefersReducedMotion) {
    heroPanel.addEventListener('pointermove', (e) => {
      const r = heroPanel.getBoundingClientRect();
      heroPanel.style.setProperty('--px', `${((e.clientX - r.left) / r.width * 100).toFixed(1)}%`);
      heroPanel.style.setProperty('--py', `${((e.clientY - r.top) / r.height * 100).toFixed(1)}%`);
      heroPanel.style.setProperty('--psheen', '0.42');
    });
    heroPanel.addEventListener('pointerleave', () => {
      heroPanel.style.setProperty('--psheen', '0.22');
    });
  }

  /* ------------------------------------------------------------------------
     9. Interactive Stage Widgets inside #theatre (Scenes 0–3) & Capabilities
     ------------------------------------------------------------------------ */
  let mcpTimers = [];
  function playMcpSequence(isReplay = false) {
    mcpTimers.forEach((t) => clearTimeout(t));
    mcpTimers = [];
    const items = Array.from(document.querySelectorAll('#mcpSceneStage .mcp-seq-item'));
    if (prefersReducedMotion || !isReplay) {
      items.forEach((el) => {
        el.classList.add('seq-lit');
        el.classList.remove('seq-current');
      });
      const lastStep = document.querySelector('#mcpSceneStage .mcp-step-row:last-of-type');
      if (lastStep) lastStep.classList.add('seq-current');
      return;
    }
    items.forEach((el) => {
      if (el.id !== 'mcpApplyDemoCard') el.classList.remove('seq-lit', 'seq-current');
    });
    items.forEach((el, idx) => {
      const t = setTimeout(() => {
        items.forEach((other) => other.classList.remove('seq-current'));
        el.classList.add('seq-lit');
        if (el.classList.contains('mcp-step-row')) el.classList.add('seq-current');
      }, 90 + idx * 180);
      mcpTimers.push(t);
    });
  }
  playMcpSequence(false);

  document.getElementById('mcpReplayBtn')?.addEventListener('click', () => playMcpSequence(true));

  const mcpApplyCard = document.getElementById('mcpApplyDemoCard');
  if (mcpApplyCard) {
    const triggerApply = () => {
      applyPreset('home_dev');
      document.getElementById('heroPanel')?.scrollIntoView({ behavior: prefersReducedMotion ? 'auto' : 'smooth', block: 'center' });
      showGlassToast(state.lang === 'zh' ? '已按 AI 指令热刷新为「开发者主页」' : 'Hot-reloaded "Developer Hub" Profile', 'ok');
    };
    mcpApplyCard.addEventListener('click', triggerApply);
    mcpApplyCard.addEventListener('keydown', (e) => {
      if (e.key === 'Enter' || e.key === ' ') {
        e.preventDefault();
        triggerApply();
      }
    });
  }

  // Scene 1: Slider + Model Select + AES-GCM Vault + Silent Hotkey + Freeform HUD
  const sliderTrack = document.getElementById('demoSliderTrack');
  const sliderFill = document.getElementById('demoSliderFill');
  const sliderKnob = document.getElementById('demoSliderKnob');
  const sliderBadge = document.getElementById('sliderValueBadge');
  const sliderModeLabel = document.getElementById('sliderModeLabel');
  const sliderSamplePreview = document.getElementById('sliderSamplePreview');
  const autoSaveBadge = document.getElementById('settingsAutoSaveBadge');

  function flashAutoSaved() {
    if (!autoSaveBadge) return;
    autoSaveBadge.textContent = state.lang === 'zh' ? '已实时保存 settings.json' : 'settings.json Synced';
  }

  function updateSlider(ratio) {
    const clamped = Math.min(1, Math.max(0, ratio));
    state.sliderRatio = clamped;
    const pct = `${(clamped * 100).toFixed(0)}%`;
    if (sliderFill) sliderFill.style.width = pct;
    if (sliderKnob) sliderKnob.style.left = pct;
    if (sliderBadge) sliderBadge.textContent = `temperature: ${clamped.toFixed(2)}`;
    if (sliderTrack) sliderTrack.setAttribute('aria-valuenow', (clamped * 100).toFixed(0));

    const zh = state.lang === 'zh';
    if (sliderModeLabel && sliderSamplePreview) {
      if (clamped < 0.28) {
        sliderModeLabel.textContent = zh ? '精准严谨 · Precise' : 'Precise · Deterministic';
        sliderSamplePreview.textContent = zh
          ? '实时译文预览：“用完即焚的微内核架构。”'
          : 'Live Preview: "Ephemeral micro-core architecture."';
      } else if (clamped < 0.68) {
        sliderModeLabel.textContent = zh ? '均衡自然 · Balanced' : 'Balanced · Natural';
        sliderSamplePreview.textContent = zh
          ? '实时译文预览：“用完即焚的原生微内核，轻巧不占内存。”'
          : 'Live Preview: "Ephemeral native micro-core, light on memory."';
      } else {
        sliderModeLabel.textContent = zh ? '灵动润色 · Creative' : 'Creative · Expressive';
        sliderSamplePreview.textContent = zh
          ? '实时译文预览：“一触流光，用完即焚的轻盈桌面体验。”'
          : 'Live Preview: "Effortless liquid-glass speed that vanishes cleanly."';
      }
    }
  }

  if (sliderTrack) {
    let draggingSlider = false;
    const setFromEvent = (e) => {
      const r = sliderTrack.getBoundingClientRect();
      if (r.width <= 0) return;
      updateSlider((e.clientX - r.left) / r.width);
      flashAutoSaved();
    };
    sliderTrack.addEventListener('pointerdown', (e) => {
      draggingSlider = true;
      sliderTrack.setPointerCapture?.(e.pointerId);
      setFromEvent(e);
    });
    sliderTrack.addEventListener('pointermove', (e) => {
      if (draggingSlider) setFromEvent(e);
    });
    sliderTrack.addEventListener('pointerup', () => { draggingSlider = false; });
    sliderTrack.addEventListener('keydown', (e) => {
      if (e.key === 'ArrowLeft' || e.key === 'ArrowRight') {
        e.preventDefault();
        updateSlider(state.sliderRatio + (e.key === 'ArrowRight' ? 0.08 : -0.08));
        flashAutoSaved();
      }
    });
    updateSlider(state.sliderRatio);
  }

  const DEMO_MODELS = ['Ollama · qwen2.5', 'Claude 3.7 Sonnet', 'GPT-4o-mini (Proxy)'];
  document.getElementById('demoModelSelectBtn')?.addEventListener('click', () => {
    state.modelIdx = (state.modelIdx + 1) % DEMO_MODELS.length;
    const valEl = document.getElementById('demoModelVal');
    if (valEl) valEl.textContent = DEMO_MODELS[state.modelIdx];
    flashAutoSaved();
  });

  document.getElementById('demoVaultSecretBtn')?.addEventListener('click', () => {
    state.secretRevealed = !state.secretRevealed;
    const valEl = document.getElementById('demoVaultVal');
    if (valEl) {
      valEl.textContent = state.secretRevealed
        ? 'sk-lucent-demo-8a4c9f2a (Decrypted)'
        : 'sk-••••9f2a (AES-GCM)';
    }
    flashAutoSaved();
  });

  const DEMO_HOTKEYS = [
    ['⌥⇧T', '三层热键无冲突 · 唤醒词可改', '3-Tier Guard Clear · Custom Keyword'],
    ['⌥⇧D', '已绑定后台静默划词译', 'Bound to Silent Selection Translate'],
    ['⌃⌥Space', '全局直达子命令 · 0 抢焦点', 'Direct Subcommand · Zero Focus Steal']
  ];
  const hotkeyCard = document.getElementById('demoHotkeyCard');
  if (hotkeyCard) {
    const cycleHotkey = () => {
      state.hotkeyIdx = (state.hotkeyIdx + 1) % DEMO_HOTKEYS.length;
      const [kbd, zhMsg, enMsg] = DEMO_HOTKEYS[state.hotkeyIdx];
      const kbdEl = document.getElementById('demoHotkeyKbd');
      const stEl = document.getElementById('demoHotkeyStatus');
      if (kbdEl) {
        kbdEl.textContent = kbd;
        pulseKeycap(kbdEl);
      }
      if (stEl) stEl.textContent = state.lang === 'zh' ? zhMsg : enMsg;
    };
    hotkeyCard.addEventListener('click', cycleHotkey);
    hotkeyCard.addEventListener('keydown', (e) => {
      if (e.key === 'Enter' || e.key === ' ') {
        e.preventDefault();
        cycleHotkey();
      }
    });
  }

  const hudCard = document.getElementById('demoHudCard');
  if (hudCard) {
    const toggleHud = () => {
      state.hudCompact = !state.hudCompact;
      const miniHud = document.getElementById('demoMiniHud');
      const tagEl = document.getElementById('demoHudModeTag');
      if (miniHud) miniHud.classList.toggle('compact', state.hudCompact);
      if (tagEl) tagEl.textContent = state.hudCompact ? 'compact · click-through' : 'floatingWindow';
    };
    hudCard.addEventListener('click', toggleHud);
    hudCard.addEventListener('keydown', (e) => {
      if (e.key === 'Enter' || e.key === ' ') {
        e.preventDefault();
        toggleHud();
      }
    });
  }

  // Scene 2: 4-Tier Smart Sniffer (11 Plugins)
  const SNIFFER_MODES = {
    repo: {
      url: `${REPO_BASE}/tree/main/plugin-demo`,
      kind: 'Store Registry (11 Plugins)',
      sha: 'SHA-256: 8f4c…d91a',
      descZh: '自动识别开源仓库子目录并定位 lucent-registry.json，一键订阅全部 11 款官方原生 Swift 插件并强制核对 SHA-256。',
      descEn: 'Auto-resolves repository subdirectory to lucent-registry.json, subscribing all 11 native Swift plugins with SHA-256 verification.'
    },
    registry: {
      url: `${REPO_BASE}/blob/main/plugin-demo/lucent-registry.json`,
      kind: 'JSON Store Manifest',
      sha: 'SHA-256: 3a9e…44b2',
      descZh: '直接解析商店索引清单 JSON，支持增量检查版本更新与防伪装沙箱权限比对，任何悄悄越权都会被拦截。',
      descEn: 'Parses store manifest JSON directly with one-click version updates and anti-spoofing capability boundary checks.'
    },
    archive: {
      url: 'plugin-demo/dist/file-shelf.zip',
      kind: 'Direct Plugin Package',
      sha: 'SHA-256: c710…e208',
      descZh: '无需搭建商店，直接嗅探独立插件压缩包并在清晰展示所需沙箱与窗口权限后安心安装。',
      descEn: 'Installs standalone plugin zip packages directly after previewing requested Seatbelt and floatingWindow permissions.'
    }
  };

  function renderSnifferDemo() {
    const mode = SNIFFER_MODES[state.snifferMode] || SNIFFER_MODES.repo;
    const urlEl = document.getElementById('snifferUrlText');
    const kindEl = document.getElementById('snifferDetectedKind');
    const descEl = document.getElementById('snifferDetailDesc');
    const shaEl = document.getElementById('snifferDigestBadge');
    const mockEl = document.getElementById('snifferInputMock');
    if (urlEl) urlEl.textContent = mode.url;
    if (kindEl) kindEl.textContent = mode.kind;
    if (shaEl) shaEl.textContent = mode.sha;
    if (descEl) descEl.textContent = state.lang === 'zh' ? mode.descZh : mode.descEn;
    if (mockEl && !prefersReducedMotion) {
      mockEl.classList.remove('scanning');
      void mockEl.offsetWidth;
      mockEl.classList.add('scanning');
    }
  }

  document.querySelectorAll('#snifferDemoPills .sniffer-demo-btn').forEach((btn) => {
    btn.addEventListener('click', () => {
      state.snifferMode = btn.dataset.sniff;
      document.querySelectorAll('#snifferDemoPills .sniffer-demo-btn').forEach((b) => {
        b.classList.toggle('active', b === btn);
      });
      renderSnifferDemo();
    });
  });

  document.getElementById('snifferInputMock')?.addEventListener('click', renderSnifferDemo);

  // Scene 3: Security Layer Selector
  const SANDBOX_TAGS = ['Seatbelt Isolated', 'UDS 0700 Scoped', 'AES-GCM 256-bit', 'LZFSE + WebDAV'];
  document.querySelectorAll('#sandboxLayerList .sec-row').forEach((row) => {
    const selectLayer = () => {
      const idx = Number(row.dataset.secIdx || 0);
      state.secIdx = idx;
      document.querySelectorAll('#sandboxLayerList .sec-row').forEach((r) => {
        r.classList.toggle('sec-active', Number(r.dataset.secIdx) === idx);
      });
      const tagEl = document.getElementById('sandboxActiveTag');
      if (tagEl) tagEl.textContent = SANDBOX_TAGS[idx] || 'Defense in Depth';
    };
    row.addEventListener('click', selectLayer);
    row.addEventListener('keydown', (e) => {
      if (e.key === 'Enter' || e.key === ' ') {
        e.preventDefault();
        selectLayer();
      }
    });
  });

  // Capabilities Micro-Stages
  const MS_TICKERS = {
    bento: 'HomeCustomization.swift',
    home_min: 'OmniDock · 16 Hybrid Slots',
    home_dev: 'cursor://lucent-repo',
    home_shelf: '4-Col Bento + Bookmarks'
  };
  document.querySelectorAll('#microSearchPills .ms-pill').forEach((pill) => {
    pill.addEventListener('click', () => {
      const key = pill.dataset.msPreset;
      document.querySelectorAll('#microSearchPills .ms-pill').forEach((p) => p.classList.toggle('active', p === pill));
      const ticker = document.getElementById('microSearchTicker');
      if (ticker && MS_TICKERS[key]) ticker.textContent = MS_TICKERS[key];
      if (key) applyPreset(key);
    });
  });

  // Color Loupe Copy Confirmation with Animated SVG Emerald Checkmark + Glass Toast
  const SWATCH_COLORS = ['#0071E3', '#5856D6', '#28CD41', '#FF9500'];
  let swatchIdx = 0;
  document.getElementById('demoCopyColorBtn')?.addEventListener('click', async (e) => {
    const btn = e.currentTarget;
    const hex = SWATCH_COLORS[swatchIdx];
    try { await navigator.clipboard?.writeText(hex); } catch (_) {}
    swatchIdx = (swatchIdx + 1) % SWATCH_COLORS.length;
    const nextHex = SWATCH_COLORS[swatchIdx];
    const dot = document.getElementById('demoSwatchDot');
    const lbl = document.getElementById('demoColorLabel');
    btn.classList.add('copied');
    if (lbl) lbl.innerHTML = `${iconSvg('check', 11, 'svg-check-draw')} ${hex}`;
    showGlassToast(state.lang === 'zh' ? `已复制取色值 ${hex}` : `Copied swatch ${hex}`, 'ok');
    setTimeout(() => {
      btn.classList.remove('copied');
      if (dot) dot.style.background = nextHex;
      if (lbl) lbl.textContent = `${nextHex} · Copy C`;
    }, 1200);
  });

  /* ------------------------------------------------------------------------
     10. Dual-Theme (Auto System Follow + Circular View Transition) & Bilingual
     ------------------------------------------------------------------------ */
  function applyTheme(themeId, originEvent = null, persist = true) {
    const commit = () => {
      state.theme = themeId;
      document.documentElement.setAttribute('data-theme', themeId);
      if (persist) {
        state.userChoseTheme = true;
        safeSet(THEME_KEY, themeId);
      }

      const label = document.getElementById('themeToggleLabel');
      const dict = I18N[state.lang];
      if (label) {
        label.textContent = themeId === 'pure-frost' ? dict.theme_frost : dict.theme_prism;
      }

      document.querySelectorAll('[data-set-theme]').forEach((btn) => {
        const active = btn.dataset.setTheme === themeId;
        btn.classList.toggle('active', active);
        btn.setAttribute('aria-pressed', String(active));
      });

      renderLauncher();
    };

    if (
      originEvent &&
      typeof document.startViewTransition === 'function' &&
      !prefersReducedMotion
    ) {
      const x = originEvent.clientX ?? window.innerWidth * 0.5;
      const y = originEvent.clientY ?? 36;
      const endRadius = Math.hypot(
        Math.max(x, window.innerWidth - x),
        Math.max(y, window.innerHeight - y)
      );
      const transition = document.startViewTransition(commit);
      transition.ready.then(() => {
        document.documentElement.animate(
          {
            clipPath: [
              `circle(0px at ${x}px ${y}px)`,
              `circle(${endRadius.toFixed(0)}px at ${x}px ${y}px)`
            ]
          },
          { duration: 460, easing: 'cubic-bezier(0.22, 1, 0.36, 1)', pseudoElement: '::view-transition-new(root)' }
        );
      }).catch(() => {});
    } else {
      commit();
    }
  }

  // Follow macOS system color-scheme changes if user hasn't explicitly toggled
  window.matchMedia('(prefers-color-scheme: dark)').addEventListener?.('change', (e) => {
    if (!state.userChoseTheme) {
      applyTheme(e.matches ? 'prism-pulse' : 'pure-frost', null, false);
    }
  });

  function applyLanguage(lang) {
    state.lang = lang;
    document.documentElement.lang = lang === 'zh' ? 'zh-CN' : 'en';
    safeSet(LANG_KEY, lang);

    const dict = I18N[lang];
    document.querySelectorAll('[data-i18n]').forEach((el) => {
      const key = el.getAttribute('data-i18n');
      if (dict[key] !== undefined) {
        const val = dict[key];
        if (val.includes('|')) {
          el.innerHTML = val
            .split('|')
            .map((s) => {
              const trail = /\s$/.test(s) ? ' ' : '';
              return `<span class="title-clause">${s.trim()}</span>${trail}`;
            })
            .join('');
        } else if (val.includes('<strong>') || val.includes('<span')) {
          el.innerHTML = val;
        } else if (val.includes('\n')) {
          el.innerHTML = val.split('\n').join('<br/>');
        } else {
          el.textContent = val;
        }
      }
    });

    const langBtn = document.getElementById('langToggleBtn');
    if (langBtn) langBtn.textContent = lang === 'zh' ? 'EN' : '中文';

    const themeLabel = document.getElementById('themeToggleLabel');
    if (themeLabel) {
      themeLabel.textContent = state.theme === 'pure-frost' ? dict.theme_frost : dict.theme_prism;
    }

    document.title = lang === 'zh'
      ? '流光 Lucent — 10 MB 免费开源纯原生 Mac 效率中枢，替掉 5 个付费工具'
      : 'Lucent — One 10 MB Free Open-Source Native Mac Hub Replacing Five Paid Tools';

    const navCap = document.querySelector('.nav-capsule');
    if (navCap) navCap.setAttribute('aria-label', lang === 'zh' ? '主导航' : 'Primary navigation');
    const presetsEl = document.querySelector('.launcher-presets');
    if (presetsEl) presetsEl.setAttribute('aria-label', lang === 'zh' ? '交互式启动面板布局与搜索场景切换' : 'Switch Launch Panel layouts or sample searches');
    const profBar = document.getElementById('builderProfileBar');
    if (profBar) profBar.setAttribute('aria-label', lang === 'zh' ? '一键切换组合方案' : 'Quick plugin bundle presets');

    if (state.preset && PRESETS[state.preset] && document.querySelector(`.preset-chip.active[data-preset="${state.preset}"]`)) {
      const p = PRESETS[state.preset];
      const nextQ = lang === 'zh' ? p.queryZh : p.queryEn;
      state.query = nextQ;
      if (launcherInput) launcherInput.value = nextQ;
    }

    if (launcherInput) launcherInput.placeholder = dict.placeholder_search;
    renderWorkbench();
    renderLauncher();
    renderSnifferDemo();
    renderTerminal();
    updateSlider(state.sliderRatio);
    syncScopeButtons();
    syncGlider('#navLinks', 'navGlider', 'a.active', false);
    syncGlider('#studioTabs', 'studioTabGlider', '.term-tab.active', false);
  }

  document.getElementById('themeToggleBtn')?.addEventListener('click', (e) => {
    applyTheme(state.theme === 'pure-frost' ? 'prism-pulse' : 'pure-frost', e, true);
  });

  document.querySelectorAll('[data-set-theme]').forEach((btn) => {
    btn.addEventListener('click', (e) => applyTheme(btn.dataset.setTheme, e, true));
  });

  document.getElementById('langToggleBtn')?.addEventListener('click', () => {
    applyLanguage(state.lang === 'zh' ? 'en' : 'zh');
  });

  /* ------------------------------------------------------------------------
     11. Hotkey Filter Bar & Xcode-Styled Code Studio Tabs + Animated Checkmark
     ------------------------------------------------------------------------ */
  document.querySelectorAll('#hotkeyBar .hotkey-pill').forEach((pill) => {
    pill.addEventListener('click', () => {
      document.querySelectorAll('#hotkeyBar .hotkey-pill').forEach((p) => p.classList.remove('active'));
      pill.classList.add('active');
      const target = pill.dataset.target;
      document.querySelectorAll('.feature-bento-grid .f-card[id]').forEach((card) => {
        if (target === 'all') {
          card.style.opacity = '1';
          card.classList.remove('highlighted');
        } else if (card.id === target) {
          card.style.opacity = '1';
          card.classList.add('highlighted');
        } else {
          card.style.opacity = '0.38';
          card.classList.remove('highlighted');
        }
      });
    });
  });

  const MCP_BIN_PATH = '/Applications/Lucent.app/Contents/MacOS/lucent-mcp';
  const RESIGN_URL = 'https://raw.githubusercontent.com/lengsukq/Lucent/main/scripts/resign-local-app.sh';
  const TERMINAL_SNIPPETS = {
    mcp: {
      raw: `claude mcp add lucent ${MCP_BIN_PATH}`,
      htmlZh: `<span class="cmd-comment"># 1. 一行命令接入 Claude Code（内置 21 项脚本、插件、主页与离线检索工具）：</span>
<span class="cmd-prompt">$ </span><span class="cmd-kw">claude</span> mcp add lucent ${MCP_BIN_PATH}

<span class="cmd-comment">// 或写入 Cursor / Codex / Gemini CLI 的 MCP 配置文件：</span>
{
  <span class="cmd-key">"mcpServers"</span>: {
    <span class="cmd-key">"lucent"</span>: { <span class="cmd-key">"command"</span>: <span class="cmd-str">"${MCP_BIN_PATH}"</span> }
  }
}
<span class="cmd-comment"># 2. 直接对 AI 说：“写个压缩图片的快捷脚本画上 SVG 图标，再配一套极简开发主页”</span>`,
      htmlEn: `<span class="cmd-comment"># 1. Register built-in 21-tool MCP server with Claude Code:</span>
<span class="cmd-prompt">$ </span><span class="cmd-kw">claude</span> mcp add lucent ${MCP_BIN_PATH}

<span class="cmd-comment">// Or add to Cursor / Codex / Gemini CLI MCP config:</span>
{
  <span class="cmd-key">"mcpServers"</span>: {
    <span class="cmd-key">"lucent"</span>: { <span class="cmd-key">"command"</span>: <span class="cmd-str">"${MCP_BIN_PATH}"</span> }
  }
}
<span class="cmd-comment"># 2. Ask AI: "Write an image-compress Quick Script with SVG icon & set up a Dev home panel"</span>`
    },
    plugins: {
      raw: `${REPO_BASE}/tree/main/plugin-demo`,
      htmlZh: `<span class="cmd-comment"># 方法 A（推荐）：打开「设置 → 插件中心」，粘贴下面链接一键订阅全部 11 款官方插件</span>
<span class="cmd-str">${REPO_BASE}/tree/main/plugin-demo</span>

<span class="cmd-comment"># 方法 B（极客终端）：克隆仓库后一键部署全部 11 款原生 Swift 旗舰插件</span>
<span class="cmd-prompt">$ </span><span class="cmd-kw">bash</span> plugin-demo/install.sh`,
      htmlEn: `<span class="cmd-comment"># Option A (Recommended): Paste repo URL into Settings → Plugins smart bar</span>
<span class="cmd-str">${REPO_BASE}/tree/main/plugin-demo</span>

<span class="cmd-comment"># Option B (CLI): Install all 11 official native Swift plugins locally (hot-reloads live)</span>
<span class="cmd-prompt">$ </span><span class="cmd-kw">bash</span> plugin-demo/install.sh`
    },
    install: {
      raw: `curl -fsSL ${RESIGN_URL} | bash`,
      htmlZh: `<span class="cmd-comment"># 升级小技巧：绑定本机自签名证书，今后替换新版 .app 免重复勾选系统权限</span>
<span class="cmd-prompt">$ </span><span class="cmd-kw">curl</span> -fsSL ${RESIGN_URL} | <span class="cmd-kw">bash</span>

<span class="cmd-comment"># 极客从源码构建安装至 /Applications/Lucent.app 并跑全量门禁校验</span>
<span class="cmd-prompt">$ </span><span class="cmd-kw">git</span> clone ${REPO_BASE}.git && cd Lucent
<span class="cmd-prompt">$ </span><span class="cmd-kw">bash</span> scripts/install-macos.sh && <span class="cmd-kw">bash</span> scripts/verify-macos.sh`,
      htmlEn: `<span class="cmd-comment"># Upgrade Tip: Bind a local machine cert so future DMG updates keep macOS TCC grants</span>
<span class="cmd-prompt">$ </span><span class="cmd-kw">curl</span> -fsSL ${RESIGN_URL} | <span class="cmd-kw">bash</span>

<span class="cmd-comment"># Build native arm64 bundle from source & run full DAG + 300-LOC + MCP gates</span>
<span class="cmd-prompt">$ </span><span class="cmd-kw">git</span> clone ${REPO_BASE}.git && cd Lucent
<span class="cmd-prompt">$ </span><span class="cmd-kw">bash</span> scripts/install-macos.sh && <span class="cmd-kw">bash</span> scripts/verify-macos.sh`
    }
  };

  function renderTerminal() {
    const codeEl = document.getElementById('terminalCode');
    if (!codeEl) return;
    const item = TERMINAL_SNIPPETS[state.termMode] || TERMINAL_SNIPPETS.mcp;
    codeEl.innerHTML = state.lang === 'zh' ? item.htmlZh : item.htmlEn;
  }

  document.querySelectorAll('.term-tab').forEach((tab) => {
    tab.addEventListener('click', () => {
      state.termMode = tab.dataset.term;
      document.querySelectorAll('.term-tab').forEach((t) => t.classList.toggle('active', t === tab));
      syncGlider('#studioTabs', 'studioTabGlider', '.term-tab.active');
      renderTerminal();
    });
  });

  document.getElementById('copyCmdBtn')?.addEventListener('click', async (e) => {
    const btn = e.currentTarget;
    const iconSlot = document.getElementById('copyBtnIcon');
    const lblSlot = document.getElementById('copyBtnLabel');
    const raw = (TERMINAL_SNIPPETS[state.termMode] || TERMINAL_SNIPPETS.mcp).raw;
    try { await navigator.clipboard?.writeText(raw); } catch (_) {}
    btn.classList.add('copied');
    if (iconSlot) iconSlot.innerHTML = iconSvg('check', 13, 'svg-check-draw');
    if (lblSlot) lblSlot.textContent = state.lang === 'zh' ? '已复制' : 'Copied';
    showGlassToast(state.lang === 'zh' ? '命令已复制至剪贴板' : 'Command copied to clipboard', 'ok');
    setTimeout(() => {
      btn.classList.remove('copied');
      if (iconSlot) iconSlot.innerHTML = iconSvg('copy', 13);
      if (lblSlot) lblSlot.textContent = I18N[state.lang].term_copy;
    }, 1500);
  });

  /* ------------------------------------------------------------------------
     12. Scroll Engine (300vh Theatre + Mobile Section Sync + Nav Glider)
     ------------------------------------------------------------------------ */
  const scrollBeam = document.getElementById('scrollBeam');
  const theatreSection = document.getElementById('theatre');
  const theatreFill = document.getElementById('theatreProgressFill');
  const stepCards = Array.from(document.querySelectorAll('.step-card'));
  const stageScenes = Array.from(document.querySelectorAll('.stage-scene'));
  const mobileSceneTabs = Array.from(document.querySelectorAll('.theatre-mobile-tab'));
  const dagTiers = Array.from(document.querySelectorAll('.dag-tier'));
  const archSection = document.getElementById('architecture');
  const navLinks = Array.from(document.querySelectorAll('#navLinks a'));
  const mobileSectionLinks = Array.from(document.querySelectorAll('#mobileSectionBar a'));
  const trackedSections = ['hero', 'compare', 'builder', 'theatre', 'capabilities', 'philosophy', 'architecture']
    .map((id) => document.getElementById(id))
    .filter(Boolean);

  function setActiveScene(idx) {
    if (state.activeStep === idx) return;
    state.activeStep = idx;
    stepCards.forEach((c, i) => c.classList.toggle('active', i === idx));
    stageScenes.forEach((s, i) => s.classList.toggle('active', i === idx));
    mobileSceneTabs.forEach((t, i) => t.classList.toggle('active', i === idx));
    if (idx === 0) playMcpSequence();
  }

  function navigateTheatreStep(idx) {
    if (!theatreSection) return;
    if (window.innerWidth <= 980) {
      setActiveScene(idx);
      return;
    }
    const rect = theatreSection.getBoundingClientRect();
    const absTop = window.scrollY + rect.top;
    const scrollable = Math.max(1, theatreSection.offsetHeight - window.innerHeight);
    const targetY = absTop + ((idx + 0.35) / stepCards.length) * scrollable;
    window.scrollTo({ top: targetY, behavior: prefersReducedMotion ? 'auto' : 'smooth' });
  }

  mobileSceneTabs.forEach((tab, idx) => {
    tab.addEventListener('click', () => setActiveScene(idx));
  });

  stepCards.forEach((card, idx) => {
    card.addEventListener('click', () => navigateTheatreStep(idx));
    card.addEventListener('keydown', (e) => {
      if (e.key === 'Enter' || e.key === ' ') {
        e.preventDefault();
        navigateTheatreStep(idx);
      }
    });
  });

  let lastNavSectionId = 'hero';
  let ticking = false;
  function updateOnScroll() {
    ticking = false;
    closeContextMenu();
    const scrollY = window.scrollY || window.pageYOffset;
    const docHeight = Math.max(1, document.documentElement.scrollHeight - window.innerHeight);
    const totalProgress = Math.min(1, Math.max(0, scrollY / docHeight));

    if (scrollBeam) {
      scrollBeam.style.transform = `scaleX(${totalProgress.toFixed(4)})`;
    }

    if (theatreSection && window.innerWidth > 980) {
      const rect = theatreSection.getBoundingClientRect();
      const scrollable = Math.max(1, theatreSection.offsetHeight - window.innerHeight);
      const rawProgress = -rect.top / scrollable;
      const clamped = Math.min(1, Math.max(0, rawProgress));
      if (theatreFill) {
        theatreFill.style.transform = `scaleY(${Math.max(0.12, clamped).toFixed(4)})`;
      }
      const stepIdx = Math.min(stepCards.length - 1, Math.floor(clamped * stepCards.length));
      setActiveScene(stepIdx);
    }

    if (archSection && dagTiers.length > 0) {
      const ar = archSection.getBoundingClientRect();
      const viewProgress = (window.innerHeight * 0.72 - ar.top) / Math.max(1, ar.height * 0.75);
      const activeTier = Math.floor(Math.min(0.99, Math.max(0, viewProgress)) * dagTiers.length);
      dagTiers.forEach((tier, i) => {
        tier.classList.toggle('tier-lit', viewProgress > 0.05 && i === activeTier);
      });
    }

    let currentId = 'hero';
    const probeY = scrollY + window.innerHeight * 0.34;
    for (const sec of trackedSections) {
      if (sec.offsetTop <= probeY) currentId = sec.id;
    }

    if (currentId !== lastNavSectionId) {
      lastNavSectionId = currentId;
      navLinks.forEach((link) => {
        link.classList.toggle('active', link.getAttribute('href') === `#${currentId}`);
      });
      mobileSectionLinks.forEach((link) => {
        const active = link.getAttribute('href') === `#${currentId}`;
        link.classList.toggle('active', active);
        if (active && window.innerWidth <= 1060) {
          link.scrollIntoView({ behavior: 'smooth', inline: 'center', block: 'nearest' });
        }
      });
      syncGlider('#navLinks', 'navGlider', 'a.active');
    }
  }

  window.addEventListener('scroll', () => {
    if (!ticking) {
      window.requestAnimationFrame(updateOnScroll);
      ticking = true;
    }
  }, { passive: true });

  window.addEventListener('resize', () => {
    syncGlider('#navLinks', 'navGlider', 'a.active', false);
    syncGlider('#scopeCapsules', 'scopeGlider', '.scope-pill.active', false);
    syncGlider('#studioTabs', 'studioTabGlider', '.term-tab.active', false);
    if (!ticking) {
      window.requestAnimationFrame(updateOnScroll);
      ticking = true;
    }
  }, { passive: true });

  const revealEls = document.querySelectorAll('.reveal-up');
  if ('IntersectionObserver' in window && !prefersReducedMotion) {
    const io = new IntersectionObserver((entries) => {
      entries.forEach((entry) => {
        if (entry.isIntersecting) {
          entry.target.classList.add('in-view');
          io.unobserve(entry.target);
        }
      });
    }, { threshold: 0.05, rootMargin: '0px 0px -12px 0px' });
    revealEls.forEach((el) => io.observe(el));
  } else {
    revealEls.forEach((el) => el.classList.add('in-view'));
  }

  /* ------------------------------------------------------------------------
     13. Boot Initialization
     ------------------------------------------------------------------------ */
  applyTheme(state.theme, null, false);
  applyLanguage(state.lang);
  updateOnScroll();
  requestAnimationFrame(() => {
    syncGlider('#navLinks', 'navGlider', 'a.active', false);
    syncGlider('#scopeCapsules', 'scopeGlider', '.scope-pill.active', false);
    syncGlider('#studioTabs', 'studioTabGlider', '.term-tab.active', false);
  });
})();
