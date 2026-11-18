/* ==========================================================================
   Lumakey Showcase — Interactive Launch Panel Customizer, Deep Customization
   Workbench, 880×544 Hub Simulator, Plugin v3.7 + 16 MCP Tools & Bilingual UI
   ========================================================================== */
(() => {
  'use strict';

  const REPO_BASE = 'https://github.com/lengsukq/Lumakey';
  const SCHEME_PREFIX = ['lumakey', '://'].join('');

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

  let savedPluginIds = ['translate-hub', 'browser-hub', 'quick-remind', 'mac-pilot', 'screen-shield'];
  try {
    const rawSaved = safeGet('lumakey-enabled-plugins-v1');
    if (rawSaved) {
      const parsed = JSON.parse(rawSaved);
      if (Array.isArray(parsed)) savedPluginIds = parsed;
    }
  } catch (_) {}

  const state = {
    theme: safeGet('lumakey-showcase-theme-v2', 'pure-frost'),
    lang: safeGet('lumakey-showcase-lang-v2', 'zh'),
    preset: 'bento',
    homeProfile: 'balanced',
    scope: 'all',
    query: '',
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
    enabledPlugins: new Set(savedPluginIds)
  };

  function saveEnabledPlugins() {
    safeSet('lumakey-enabled-plugins-v1', JSON.stringify([...state.enabledPlugins]));
  }

  let toastTimer = null;
  function showPanelToast(msg) {
    const el = document.getElementById('panelActionToast');
    if (!el) return;
    el.textContent = msg;
    if (toastTimer) clearTimeout(toastTimer);
    toastTimer = setTimeout(() => { el.textContent = ''; }, 2400);
  }

  function syncGlider(containerSelector, gliderId, activeSelector) {
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
    glider.style.width = `${aRect.width.toFixed(1)}px`;
    glider.style.transform = `translateX(${offsetX.toFixed(1)}px)`;
    container.classList.add('glider-ready');
  }

  // Hydrate repository links cleanly
  document.querySelectorAll('[data-gh-path]').forEach((el) => {
    const sub = el.getAttribute('data-gh-path') || '';
    el.setAttribute('href', `${REPO_BASE}${sub}`);
    el.setAttribute('target', '_blank');
    el.setAttribute('rel', 'noopener noreferrer');
  });

  /* ------------------------------------------------------------------------
     1. Bilingual Copy Dictionary (简体中文 / English)
     ------------------------------------------------------------------------ */
  const I18N = {
    zh: {
      brand_cn: '流光',
      nav_launcher: '启动面板',
      nav_builder: '高度定制',
      nav_theatre: 'AI 共创',
      nav_bento: '日常利器',
      nav_philosophy: '设计哲学',
      nav_arch: '极客架构',
      nav_3d_exp: '返回 3D 主页',
      nav_download: '下载 DMG',
      theme_frost: '凝霜留白',
      theme_prism: '霓彩流光',
      hero_badge_1: '全新启动面板自定义 · Plugin v3.7 · 16 项 MCP 工具',
      hero_badge_3: '秒呼即走 · 不占后台',
      hero_title_1: '轻巧顺手的 Mac 效率底座，',
      hero_title_2: '从启动面板到插件全随你定。',
      hero_subtitle: '按一下 ⌥Space，找软件、搜电脑与移动硬盘文件、翻剪贴板、截屏识字、算账换算一框搞定；用完切走自动释放内存。更把选择权彻底交还给你：启动面板怎么排、顶部菜单留哪几项、快捷键怎么顺手全可自由编排，还能对 AI 说一句话十秒造出你独有的新工具。',
      cta_builder: '亲手定制你的专属 Lumakey',
      cta_3d_exp: '返回 3D 沉浸式主页',
      cta_download: '下载 macOS 安装包 (.dmg)',
      jump_3d_plugins: '返回 3D 主页 · 插件生态 →',
      jump_3d_mcp: '返回 3D 主页 · MCP 共创 →',
      jump_3d_dag: '返回 3D 主页 · 原生架构 →',
      foot_3d_exp: '返回 3D 主页',
      preset_try: '切换启动面板布局 / 试搜指令：',
      preset_bento: '✦ 均衡默认主页',
      preset_home_min: '◐ 极简 16 格混合坞',
      preset_home_dev: '⌘ 开发者主页与书签架',
      preset_home_shelf: '📑 4 列磁贴与分类架',
      preset_translate: '🌐 划词/OCR 翻译',
      preset_remind: '⏰ 10m 喝水提醒',
      preset_dev: '∑ 算式与色板换算',
      scope_all: '全部',
      scope_plugins: '插件',
      scope_files: '文件',
      scope_clip: '剪贴板',
      hint_open: '执行 / 打开',
      hint_quick: '盲按快选',
      hint_tab: '右键钉上主页',
      hint_focus: '聚焦体验框',
      scroll_hint: '向下滚动，体验全维度自由定制与 AI 一句话共创',
      builder_eyebrow: 'DEEP CUSTOMIZATION WORKBENCH · 全维度高度自定义拼装台',
      builder_title: '一千个人手里，|有一千种长相的 Lumakey',
      builder_desc: '讨厌装完多出一堆关不掉的按钮和后台进程？这里所有扩展默认零打扰：不开启即零内存、零后台轮询；开启后可按需钉入启动面板或顶部状态栏菜单、自由修改唤醒词、录制不抢焦点的静默快捷键，甚至弹出无边框透明桌面挂件。点按下方开关亲手试拼：',
      prof_minimal: '◐ 纯粹微内核底座 (0 插件)',
      prof_daily: '✦ 日常省心高频套装',
      prof_dev: '⌘ 极客 AI 与远控开发流',
      prof_full: '⚡ 7 款官方旗舰 + AI 自制满配',
      cat_head_title: '7 款官方旗舰扩展 + AI 自制示例（点击查看能力 / 开关挂载）',
      prev_live_badge: '● 实时联动：上方启动面板与菜单栏形态',
      zone_quick_title: '按需挂载至启动面板胶囊架 & 状态栏菜单（默认关闭不挤占）',
      zone_accepts_title: '跨模块右键联动（自动接入离线识字 / 剪贴板 / 双栏文件台）',
      theatre_eyebrow: 'AI CO-CREATION & PLUGIN V3.7 · 不会写代码也能深度定制',
      theatre_title: '不仅能装现成插件，|还能一句话让 AI 造工具、排主页',
      s1_title: '内置 16 项 MCP 工具：一句话十秒造插件，也能一句话排好启动面板',
      s1_desc: '安装包自带零依赖 lumakey-mcp 服务，连接 Claude Code、Cursor、Codex 或 Gemini CLI 后，用大白话说出你想要的小工具或主页布局，AI 自动生成代码、过沙箱实测并热刷新生效。',
      s2_title: '零前端自动生成设置页，亦支持无边框透明玻璃桌面悬浮挂件',
      s2_desc: '一份 plugin.json 自动渲染滑块、加密密钥框与子功能静默热键；进阶玩家还可开启 window / floatingWindow 自由画布，打造 120Hz 顺滑拖拽、点击穿透的置顶悬浮小窗（关窗即释放内存）。',
      s3_title: '单输入框四级智能嗅探：粘贴任意 GitHub 链接即可安心订阅',
      s3_desc: '不用分清是插件压缩包、仓库子目录还是商店 JSON，粘贴进去自动识别并强制核对 64 位 SHA-256 与权限边界；后续更新插件完整保留你改过的唤醒词、快捷键与密钥。',
      s4_title: '内核级 Seatbelt 沙箱 · 本机加密保险箱 · 整机备份跨机漫游',
      s4_desc: '外部插件默认无权联网或碰隐私目录，填入的 API Key 经 256-bit AES-GCM 加密存放；通过 .lumakeybackup (LZFSE + WebDAV) 可把启动面板、菜单配置、自制插件与密钥一键带去新 Mac。',
      sc0_prompt: '“帮我做一个查待审 PR 的插件（Token 存加密箱），顺便在我的启动面板新建一个『日常开发』主页，把双栏文件台、这个新插件和 GitHub 书签架排上去。”',
      sc0_st1: '读取内置插件与启动面板双规范及可用能力池',
      sc0_st2: '自动生成插件并在 Seatbelt 沙箱内完成实跑验证',
      sc0_st3: '创建新主页 Profile、挂载磁贴与书签架并实时热刷新',
      sc0_live_t: '✦ 已热刷新至 ⌥Space：新插件与「日常开发」启动面板同步就绪',
      sc0_live_d: '全程无需重启 Lumakey，不满意还能随时在设置页或通过 undoLastChange 一键撤回上次面板改动。',
      sc0_f1: '12 项插件全生命周期工具',
      sc0_f2: '4 项启动面板实时编排工具',
      sc0_f3: '内置 3 套一键脚手架模板',
      sc1_slider_t: '免写界面的原生设置页（拖动下方滑块实时体验）',
      sc1_slider_d: '自动渲染输入框、AES-GCM 密钥框、连续滑块、下拉单选、路径选择器与标签组，改动瞬间自动保存。',
      sc1_hk_t: '子命令静默热键 & 权重覆盖',
      sc1_hk_d: '每条细分动作都能独立绑快捷键后台静默秒跑；不改插件源码就能自定义唤醒词、菜单栏挂载与搜索排序权重。',
      sc1_dl_t: '自由画布透明桌面挂件',
      sc1_dl_d: '支持无边框透明毛玻璃 HUD、置顶悬浮与点击穿透，自动注入 window.lumakey 双向桥并在关窗瞬间销毁回收。',
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
      sc2_f1: 'lumakey_package_plugin_for_store 一键发版',
      sc2_f2: '插件更新免重复勾选系统权限',
      sc3_r1: '未声明联网或子进程即由系统内核硬阻断，无条件隔离钥匙串与敏感目录',
      sc3_r2: '11 项受控宿主桥接（OCR / 划词 / 截屏 / 通知等），一次性令牌随进程结束即焚',
      sc3_r3: '双轨 256-bit 随机主密钥 AES-GCM 加密存放 API Key，磁盘零明文残留',
      sc3_r4: 'LZFSE 压缩打包启动面板、菜单配置、自制插件与密钥，云盘与 NAS 一键漫游',
      sc3_f1: '21 项全景权限审计面板',
      sc3_f2: '子进程超时自动回收兜底',
      sc3_f3: 'HKDF + AES-GCM 备份口令保护',
      bento_eyebrow: 'EVERYDAY NATIVE ESSENTIALS · 不装任何插件也超好用的五大原生利器',
      bento_title: '把五六个日常小软件，|浓缩进一个 10 MB 原生底座',
      bento_desc: '平时最常用的搜索、剪贴板、截屏贴图、GIF 录屏、离线识字与外接鼠标平滑滚轮全部原生内置，用起来直觉顺手，关掉即刻释放内存：',
      hk_all: '全部内置利器',
      hk_search: '自定义主页与全盘秒搜',
      hk_shot: '截图标注 · GIF · 离线识字',
      hk_pulse: '芯片功耗贴边胶囊',
      hk_net: '软件网速与清缓存',
      hk_ws: '双栏整理 & 鼠标丝滑滚轮',
      fc1_title: '可定制启动面板 · 全盘秒搜 · 15 步可撤回剪贴板',
      fc1_desc: '未打字时展示你自定义的 Bento 磁贴、混合应用坞与分组书签架；输入即免前缀并发秒搜中文双音字/拼音应用、本机与移动硬盘文件、富媒体剪贴板历史（自动跳过密码）、10 类日常单位算式换算、;短语扩展与离线开发小工具。',
      fc1_c1: '4 区 × 多场景 Profile',
      fc1_c2: 'LMKYIDX3 mmap 零拷贝秒搜',
      fc1_c3: '880×544 防跳行不抢焦点',
      fc2_title: '多屏超清截图标注 · 轻巧区域 GIF · 一秒离线识字贴图',
      fc2_desc: '多块不同分辨率屏幕拼接也能原画质框选与一键抠出独立圆角窗口；自带箭头、荧光笔、实时马赛克、序号、放大镜按 C 取色及半透明悬浮钉图（按 T 穿透对照），还能直接录轻巧 GIF 动图或离线提取图中文字与二维码。',
      fc2_c1: 'ScreenCaptureKit 零延迟冻屏',
      fc2_c2: '零 ffmpeg 流式 GIF89a',
      fc2_c3: 'Vision 本地离线 OCR',
      fc3_title: '芯片脉搏贴边小胶囊',
      fc3_desc: '默认关闭不打扰；开启后以超低开销实时显示芯片大小核负载、频率、内存压力与整机瓦数功耗 (W)，靠近屏幕边缘自动贴边收起。',
      fc4_title: '软件网速透视 & 安全清缓存',
      fc4_desc: '不用装复杂的抓包或后台监控服务，随时看清哪个软件正在占用网速、连向哪里，并可分门别类把临时缓存安全移入废纸篓。',
      fc5_title: '外接鼠标丝滑滚轮 & 双栏文件台',
      fc5_desc: '让普通外接鼠标拥有 120Hz 顺滑滚动与独立方向反转（完全不动触控板手感）；按需呼出双栏文件整理台（NTFS 移动硬盘只读护航）与秒开 Markdown / 4K 视频窗。',
      phil_eyebrow: 'CORE PHILOSOPHY · 为什么普通用户与极客都喜欢它',
      phil_title: '底座极度克制，|定制自由无限生长',
      phil_desc: '好的工具开箱就足够好懂顺手，深入使用又能把每一寸面板、每一枚热键和每一个私人工作流都调教成你最舒服的模样。',
      p1_title: '全维度高度可定制，却绝不强迫折腾',
      p1_desc: '开箱自带精心打磨的默认体验；想折腾时，启动面板四大分区与多套场景 Profile、顶部状态栏菜单顺序、全局与子功能静默热键、唤醒词与排序权重，乃至一句话 AI 定制插件全部向你敞开。',
      p2_title: '约 10 MB 纯正 Mac 原生，拒绝网页套壳',
      p2_desc: '不用笨重的浏览器内核套桌面壳子，全仓零第三方外部依赖，100% 纯 Swift 6 直接调用 Apple Silicon 硬件加速框架，启动秒开、发热极低。',
      p3_title: '不乱跳的窗口，稳稳当当的肌肉记忆',
      p3_desc: '主窗口固定锁定 880 × 544，切分类不位移、打中文拼音不误触回车、后台刷新索引绝不抢走你正选中的那一行，配合克制跟手的原生弹簧动效，盲操行云流水。',
      p4_title: '用完即走省内存，本机沙箱守隐私',
      p4_desc: '主面板收起 30 秒自动销毁界面缓存，文件索引空闲 90 秒自动卸载；外部插件关进 macOS Seatbelt 内核沙箱，API 密钥经 256-bit AES-GCM 加密存放本机。',
      duality_eyebrow: 'PURE FROST & PRISM PULSE · 双生液态玻璃主题',
      duality_title: '「凝霜留白」的温润瓷感，|或「霓彩流光」的深邃光谱',
      duality_desc: '喜欢干净清爽的白昼质感，还是深邃通透的暗夜毛玻璃？点击右侧即可实时切换两套原生外观，软件内切换时还会自动同步给所有已开启的插件与悬浮窗。',
      btn_frost: '◐ 凝霜留白 Pure Frost',
      btn_prism: '✦ 霓彩流光 Prism Pulse',
      bound_title: '清晰克制的产品边界：|把自由留给定制，让底座永远轻快',
      bound_sub: '知道「什么该做到极致」与「什么绝不往底座硬塞」，才能让你的 Mac 长久保持清爽不卡顿。',
      yes_1: '<strong>你的界面你做主：</strong>启动面板四分区、顶部状态栏菜单、全局快捷键、唤醒词与插件挂件全部支持按需开启与自由排布。',
      yes_2: '<strong>普通人也能玩的 AI 扩展：</strong>内置 16 项 lumakey-mcp 工具与单框智能商店嗅探，一句话就能定制新插件或新主页。',
      yes_3: '<strong>100% 专为 M 系列芯片打造：</strong>纯 arm64 原生编译与 macOS 14+ 系统框架直连，没有跨平台兼容包袱。',
      no_1: '<strong>绝不做关不掉的臃肿全家桶：</strong>刚装好时零悬浮球、零菜单栏强塞读数、零后台守护进程，一切按需点亮。',
      no_2: '<strong>绝不拿几百 MB 网页内核套主界面：</strong>内置文档阅读与主面板坚持纯 Swift 原生渲染；插件自由浮窗关窗即刻销毁。',
      no_3: '<strong>绝不裸奔跑脚本或冒险强写脏硬盘：</strong>外部脚本强制进内核沙箱、密钥加密存放，遇到带脏标记的 NTFS 盘严格只读护航。',
      arch_eyebrow: 'UNDER THE HOOD FOR GEEKS · 给极客看的硬核工程纪律',
      arch_title: '九大单向无环模块 · |单文件硬性严控 ≤ 300 行',
      arch_desc: '代码库与产品一样干净克制：每次构建均由自动化脚本强制核验模块单向 DAG 依赖、单 .swift 文件行数上限、文档死链与真实 lumakey-mcp JSON-RPC 往返联调。',
      m_1: '内置 lumakey-mcp 造插件与排主页工具',
      m_2: '第三方 SwiftPM / CocoaPods 外部依赖',
      m_3: '单 .swift 源码文件硬性行数上限',
      m_4: '浮窗销毁 / 索引自动归还内存窗口',
      dag_app: 'SwiftUI + AppKit 双主题前端 · 启动面板/菜单栏定制 · 自由画布窗口',
      dag_mcp: '内置 16 项 JSON-RPC 2.0 工具：AI 插件脚手架、沙箱测试与启动面板实时编排',
      dag_core: 'HomeLayout 多场景启动面板 · Plugin v3.7 宿主桥与 TCC 代申 · Seatbelt 沙箱 · 智能商店嗅探 · WebDAV 备份',
      dag_search: 'LMKYIDX3 mmap 零拷贝快照 · FSEvents 实时增量 · 批量改名预检',
      dag_media: '逐屏冻屏标注合成 · Vision 离线 OCR · hev1 4K 硬解 · 纯原生 Markdown',
      dag_sys: 'Mach/IOKit 功耗遥测 · 进程网速去向 · 120Hz 鼠标平滑滚轮 · 三层热键防冲突',
      dag_found: '凝霜/流光双主题模型 · 中英双语免重启 · LMKYVLT2 256-bit AES-GCM 密钥箱 · ProcessSupervisor',
      dl_eyebrow: 'START BUILDING YOUR LUMAKEY · 立即免费使用',
      dl_title: '下载 10 MB 轻巧底座，\n搭出最懂你的效率流',
      dl_desc: 'MIT 协议免费开源，支持 macOS 14.0+ 全系 M1 / M2 / M3 / M4 设备。拖入应用程序即可使用，后续支持应用内一键下载 DMG 自动更新并保留本机权限（缺 Python 3 时亦有一键安装向导）；右侧附上 AI 接入与源码命令：',
      dl_btn_dmg: '下载最新 DMG 安装包',
      dl_btn_store: '浏览 7 款官方插件库',
      dl_btn_star: 'GitHub 点亮 Star ★',
      term_tab_mcp: '接入 AI 造插件/排主页',
      term_tab_plugins: '安装 7 款官方插件',
      term_tab_install: '免重复授权 & 源码构建',
      term_copy: '复制代码',
      foot_brand: 'Lumakey 流光',
      foot_plugin_doc: '插件与 MCP 规范',
      foot_docs: '工程文档',
      foot_contrib: '参与共建',
      placeholder_search: '直接打字搜软件、移动硬盘文件、算式，或试输：tr 翻译 / bh 书签 / rem 10m 喝水...'
    },
    en: {
      brand_cn: '',
      nav_launcher: 'Launch Panel',
      nav_builder: 'Customize',
      nav_theatre: 'AI & MCP',
      nav_bento: 'Native Tools',
      nav_philosophy: 'Philosophy',
      nav_arch: 'Architecture',
      nav_3d_exp: '3D Stage',
      nav_download: 'Get DMG',
      theme_frost: 'Pure Frost',
      theme_prism: 'Prism Pulse',
      hero_badge_1: 'New Launch Panel Customizer · Plugin v3.7 · 16 MCP Tools',
      hero_badge_3: 'Instant Wake · Zero Bloat',
      hero_title_1: 'Effortless Everyday Mac Hub. ',
      hero_title_2: 'Customizable from Launch Panel to Plugins.',
      hero_subtitle: 'Press ⌥Space to launch apps, search internal & external drives, pull up clipboard history, capture & OCR your screen, or convert units in one bar — then release memory automatically when done. Want it tailored? Customize every Launch Panel zone, trim the menu bar, bind silent hotkeys, or ask AI to build a custom plugin in 10 seconds.',
      cta_builder: 'Customize Your Own Lumakey',
      cta_3d_exp: 'Back to 3D Main Stage',
      cta_download: 'Download for macOS (.dmg)',
      jump_3d_plugins: 'View in 3D Main Stage →',
      jump_3d_mcp: 'Open in 3D Main Stage →',
      jump_3d_dag: 'Inspect in 3D Main Stage →',
      foot_3d_exp: '3D Main Stage',
      preset_try: 'Switch Launch Panel Layout / Try Search:',
      preset_bento: '✦ Balanced Home',
      preset_home_min: '◐ Minimal 16-Slot Dock',
      preset_home_dev: '⌘ Developer Home & Shelves',
      preset_home_shelf: '📑 4-Col Bento & Bookmarks',
      preset_translate: '🌐 Selection/OCR Translate',
      preset_remind: '⏰ 10m Water Reminder',
      preset_dev: '∑ Math & #HEX Swatch',
      scope_all: 'All',
      scope_plugins: 'Plugins',
      scope_files: 'Files',
      scope_clip: 'Clipboard',
      hint_open: 'Run / Open',
      hint_quick: 'Quick Pick',
      hint_tab: 'Right-Click Pin to Home',
      hint_focus: 'Focus Input',
      scroll_hint: 'Scroll down to explore deep customization & 1-sentence AI co-creation',
      builder_eyebrow: 'DEEP CUSTOMIZATION WORKBENCH',
      builder_title: 'A Thousand Workflows, |A Thousand Custom Lumakeys',
      builder_desc: 'Tired of apps cluttering your Mac with unremovable icons and daemons? Every extension here is opt-in: zero RAM and zero polling when off; when enabled, pin it to your Launch Panel or menu bar, rename keywords, record silent hotkeys, or open frameless glass desktop widgets. Toggle modules below:',
      prof_minimal: '◐ Pure Micro-Core (0 Plugins)',
      prof_daily: '✦ Everyday Productivity Pack',
      prof_dev: '⌘ Geek AI & Remote Flow',
      prof_full: '⚡ All 7 Official + AI Custom',
      cat_head_title: '7 Official Flagship Plugins + AI Custom Example (Click to Inspect / Toggle)',
      prev_live_badge: '● Live Sync: Updates Launch Panel & Menu Bar Above',
      zone_quick_title: 'Mounted to Launch Panel Shelf & Menu Bar (Off by Default)',
      zone_accepts_title: 'Cross-Module Context Menu Hooks (OCR / Clipboard / Workspace)',
      theatre_eyebrow: 'AI CO-CREATION & PLUGIN V3.7',
      theatre_title: 'Install Curated Plugins — |Or Ask AI to Build Tools & Arrange Home',
      s1_title: '16 Built-in MCP Tools: Build a Plugin or Arrange Your Launch Panel in One Sentence',
      s1_desc: 'Ships with an embedded zero-dependency lumakey-mcp binary. Connect Claude Code, Cursor, Codex, or Gemini CLI and describe your tool or home layout in plain words — AI scaffolds, tests in Seatbelt, and hot-reloads live.',
      s2_title: 'Zero-Frontend Native Settings Forms + Frameless Glass Desktop HUDs',
      s2_desc: 'A single plugin.json auto-renders sliders, AES-GCM secret inputs, and per-subcommand silent hotkeys; power users can also declare window / floatingWindow for 120Hz draggable, click-through glass widgets destroyed on close.',
      s3_title: 'Single-Box 4-Tier URL Sniffer: Paste Any GitHub Link to Subscribe',
      s3_desc: 'Paste a zip archive, repo subdirectory, or store JSON — Lumakey auto-resolves it, verifies 64-bit SHA-256 digests and capability boundaries, and preserves your custom keywords, hotkeys, and secrets across upgrades.',
      s4_title: 'Kernel Seatbelt Sandbox · 256-Bit Vault · Cross-Mac Backup Sync',
      s4_desc: 'Plugins cannot touch the network or private folders unless declared, API keys stay inside a 256-bit AES-GCM vault, and .lumakeybackup (LZFSE + WebDAV) carries your Launch Panel, menu bar, plugins, and secrets to any Mac.',
      sc0_prompt: '"Build me a PR review plugin (token in encrypted vault), and create a Daily Dev Launch Panel profile with Dual Workspace, this new plugin, and a GitHub bookmark shelf."',
      sc0_st1: 'Reads built-in plugin-v3 + home-layout-v1 specs & capability audit',
      sc0_st2: 'Scaffolds plugin & executes live test inside Seatbelt sandbox',
      sc0_st3: 'Creates new Home Profile, mounts tiles/shelves & hot-reloads UI',
      sc0_live_t: '✦ Live in ⌥Space: New Plugin & "Daily Dev" Launch Panel Ready',
      sc0_live_d: 'Zero app restart needed — revert any layout tweak anytime via 1-click Undo in Settings or MCP.',
      sc0_f1: '12 Plugin Lifecycle MCP Tools',
      sc0_f2: '4 Live Home Layout Tools',
      sc0_f3: '3 Built-In Scaffold Templates',
      sc1_slider_t: 'Auto-Generated Native Settings UI (Drag Slider Below)',
      sc1_slider_d: 'Renders text, AES-GCM secrets, continuous sliders, dropdowns, path pickers & tags — saved immediately as you tweak.',
      sc1_hk_t: 'Silent Subcommand Hotkeys & Overrides',
      sc1_hk_d: 'Bind global hotkeys to any subcommand for silent background execution; override keywords, menu bar pins & ranking weights without touching plugin code.',
      sc1_dl_t: 'Freeform Transparent Desktop Widgets',
      sc1_dl_d: 'Supports frameless blurred HUDs, always-on-top pins & click-through with window.lumakey bridge and instant teardown on close.',
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
      sc2_f1: '1-Command lumakey_package_plugin_for_store',
      sc2_f2: 'Preserves TCC Permissions Across Updates',
      sc3_r1: 'Undeclared network or subprocess calls blocked at kernel level; Keychain & private dirs isolated',
      sc3_r2: '11 scoped Host Bridges (OCR, selection, capture, notify) via one-time 0700 UDS token',
      sc3_r3: 'Dual-track 256-bit random master key AES-GCM vault with zero plaintext on disk',
      sc3_r4: 'LZFSE archive syncs Launch Panel profiles, menu bar, custom plugins & secrets via WebDAV / NAS',
      sc3_f1: '21-Item Permission Audit Matrix',
      sc3_f2: 'Auto Timeout Subprocess Reaping',
      sc3_f3: 'HKDF + AES-GCM Backup Passphrase',
      bento_eyebrow: 'EVERYDAY NATIVE ESSENTIALS',
      bento_title: 'Replace Five Everyday Utilities |with One ~10 MB Native App',
      bento_desc: 'App & drive search, clipboard history, multi-monitor screenshot annotation, GIF recording, offline OCR, and smooth mouse scrolling are all built right in — intuitive to use and freed from RAM on close:',
      hk_all: 'All Built-In Tools',
      hk_search: 'Custom Home & Disk Search',
      hk_shot: 'Capture · GIF · Offline OCR',
      hk_pulse: 'Chip Wattage Pill',
      hk_net: 'App Bandwidth & Cache',
      hk_ws: 'Dual Pane & Smooth Wheel',
      fc1_title: 'Custom Launch Panel · Full-Disk Search · 15-Step Undo Clipboard',
      fc1_desc: 'Shows your custom Bento tiles, hybrid Omni Dock, and bookmark shelves before typing; type immediately to search localized apps, internal & external drives, rich clipboard history (auto-skipping passwords), 10-category unit math, ;snippets, and offline dev tools.',
      fc1_c1: '4 Zones × Multi-Scene Profiles',
      fc1_c2: 'LMKYIDX3 mmap 0-Copy Search',
      fc1_c3: 'Zero-Jitter 880×544 Frame',
      fc2_title: 'Multi-Display HD Capture · Lightweight GIF · 1s Offline OCR Pins',
      fc2_desc: 'Crisp per-display freeze capture and 1-click rounded window cutouts across mixed-DPI monitors; includes arrows, highlighter, live mosaic, step badges, C-key color loupe, translucent desktop pins (T for click-through), streaming GIF89a recording, and offline Vision OCR.',
      fc2_c1: 'ScreenCaptureKit Freeze Capture',
      fc2_c2: 'Zero-ffmpeg Streaming GIF89a',
      fc2_c3: 'Local Offline Vision OCR',
      fc3_title: 'Edge-Docking Chip Pulse Pill',
      fc3_desc: 'Off by default; when enabled, shows P/E-core load, GHz, memory pressure, and live system wattage (W) with minimal overhead and auto-hiding edge snap.',
      fc4_title: 'Per-App Bandwidth & Safe Cache Cleaner',
      fc4_desc: 'See which app is using bandwidth and where it connects without root daemons, plus move categorized app caches safely to Trash.',
      fc5_title: 'Smooth External Mouse Wheel & Dual Workspace',
      fc5_desc: 'Brings 120Hz smooth scrolling and independent scroll direction to physical mice without altering your Apple Trackpad; summon a dual-pane file organizer (read-only NTFS guard) and instant Markdown / 4K video viewers on demand.',
      phil_eyebrow: 'CORE PHILOSOPHY',
      phil_title: 'Restrained Native Core, |Boundless Personal Freedom',
      phil_desc: 'Simple enough to feel effortless on minute one, deep enough to shape every panel zone, hotkey, and private workflow around your habits.',
      p1_title: 'Deeply Customizable Without Forced Tinkering',
      p1_desc: 'Thoughtful defaults work right away; whenever you want, customize 4 Launch Panel zones & multi-scene Profiles, status bar menu order, global & silent subcommand hotkeys, keywords, ranking weights, or AI-built plugins.',
      p2_title: '~10 MB Pure Native Swift 6 — Zero Web Wrapper',
      p2_desc: 'No bulky browser shell pretending to be a desktop app: zero external packages, 100% Swift 6 talking straight to Apple Silicon frameworks.',
      p3_title: 'Zero-Jitter Geometry for Reliable Muscle Memory',
      p3_desc: 'Locked 880 × 544 frame that never jumps across scopes, guards CJK IME Return keys, and anchors selection during async updates with crisp native spring motion.',
      p4_title: 'Self-Cleaning Memory & Local Sandbox Privacy',
      p4_desc: 'Tears down UI caches 30s after hide, unmaps disk index pages after 90s idle, isolates plugins inside macOS Seatbelt, and encrypts secrets via 256-bit AES-GCM.',
      duality_eyebrow: 'PURE FROST & PRISM PULSE · DUAL LIQUID GLASS THEMES',
      duality_title: 'Porcelain Clarity in Pure Frost, |or Deep Aurora in Prism Pulse',
      duality_desc: 'Prefer crisp daylight porcelain or deep obsidian glass? Switch live on the right — inside the app, your theme syncs automatically across every open plugin and floating HUD.',
      btn_frost: '◐ Pure Frost (Light)',
      btn_prism: '✦ Prism Pulse (Dark)',
      bound_title: 'Clear Product Boundaries: |Leave Freedom to Customization, Keep the Core Light',
      bound_sub: 'Knowing what to polish natively and what never to force into the base keeps your Mac fast.',
      yes_1: '<strong>Your Interface, Your Rules:</strong> Launch Panel zones, status bar menu items, global hotkeys, keywords & widgets are all opt-in and reorderable.',
      yes_2: '<strong>AI Customization Anyone Can Use:</strong> 16 built-in lumakey-mcp tools and single-box store sniffing turn plain words into plugins or layouts.',
      yes_3: '<strong>100% Built for Apple Silicon:</strong> Pure arm64 binaries wired directly to modern macOS 14+ frameworks.',
      no_1: '<strong>No Unremovable All-in-One Bloatware:</strong> Zero forced floating balls, menu-bar tickers, or background daemons out of the box.',
      no_2: '<strong>No Multi-Hundred-MB Web Shell for Main UI:</strong> Native Swift renders the hub & readers; optional plugin web windows destroy immediately on close.',
      no_3: '<strong>No Unsandboxed Scripts or Unsafe Dirty-NTFS Writes:</strong> Enforces kernel Seatbelt, encrypted vaults, and read-only protection on dirty NTFS drives.',
      arch_eyebrow: 'UNDER THE HOOD FOR GEEKS',
      arch_title: '9 Acyclic Swift 6 Targets · |Strictly ≤ 300 Lines per File',
      arch_desc: 'Every build runs automated gates verifying acyclic module boundaries, per-file ≤ 300 LOC limits, doc links, and live lumakey-mcp JSON-RPC roundtrips.',
      m_1: 'Built-in lumakey-mcp Plugin & Home Tools',
      m_2: 'External SwiftPM / CocoaPods Dependencies',
      m_3: 'Hard Max Lines per .swift Source File',
      m_4: 'UI Cache Teardown / Index Unmap Window',
      dag_app: 'SwiftUI + AppKit Dual-Theme UI · Launch Panel/Menu Customizer · Freeform Windows',
      dag_mcp: 'Embedded 16 JSON-RPC 2.0 Tools: Plugin Scaffold, Sandbox Test & Live Home Layout',
      dag_core: 'HomeLayout Multi-Profile · Plugin v3.7 Host & TCC Broker · Seatbelt · Store Sniffer · Backup',
      dag_search: 'LMKYIDX3 mmap Snapshot · Live FSEvents · Batch Rename Preflight',
      dag_media: 'Per-Display Freeze Capture · Offline Vision OCR · hev1 4K · Native Markdown',
      dag_sys: 'Mach/IOKit Wattage · Socket Bandwidth · 120Hz Smooth Wheel · 3-Tier Hotkey Guard',
      dag_found: 'Pure Frost / Prism Pulse · Instant Bilingual · LMKYVLT2 256-bit Vault · ProcessSupervisor',
      dl_eyebrow: 'START BUILDING YOUR LUMAKEY',
      dl_title: 'Grab the ~10 MB Native Hub,\nShape Your Personal Flow',
      dl_desc: 'Free & open source (MIT) for macOS 14.0+ on M1 / M2 / M3 / M4 Macs. Drag to Applications to start, with in-app DMG auto-updates that preserve local TCC permissions and 1-click Python 3 setup; copy MCP, plugin, or build commands on the right:',
      dl_btn_dmg: 'Download Latest DMG',
      dl_btn_store: 'Browse 7 Official Plugins',
      dl_btn_star: 'Star on GitHub ★',
      term_tab_mcp: 'Connect AI (Plugin + Home)',
      term_tab_plugins: 'Install 7 Official Plugins',
      term_tab_install: 'Keep Permissions & Build',
      term_copy: 'Copy',
      foot_brand: 'Lumakey',
      foot_plugin_doc: 'Plugin & MCP Spec',
      foot_docs: 'Docs Index',
      foot_contrib: 'Contributing',
      placeholder_search: 'Type to search apps, external drives, math, or try: tr hello / bh safari / rem 10m water...'
    }
  };

  /* ------------------------------------------------------------------------
     2. Complete 7 Official Store Plugins + 1 MCP Custom Plugin Dataset
     ------------------------------------------------------------------------ */
  const PLUGINS = [
    {
      id: 'translate-hub',
      icon: '🌐',
      grad: 'linear-gradient(135deg,#7c3aed,#a855f7)',
      tagZh: '官方旗舰',
      tagEn: 'Official',
      nameZh: '流光译站 Translate Hub',
      nameEn: 'Translate Hub',
      shortZh: '跨应用划词工具栏 / 离线 OCR 截图多源翻译、双语 TTS 朗读与生词本',
      shortEn: 'Cross-app Selection Quick Bar & offline OCR translation + dual TTS & vocab',
      detailZh: `选中文本即弹悬浮快捷工具栏，零配置内置双语词典开箱即用，支持并行对比本地 Ollama 大模型译文、原文/译文双语 TTS 朗读按钮、一键归档生词并通过 ${SCHEME_PREFIX}reader 打开或导出 Anki 词卡。`,
      detailEn: `Instant Selection Quick Bar + zero-config built-in dictionary, parallel local Ollama LLM translation, dual source/target TTS buttons, vocabulary notebook, native ${SCHEME_PREFIX}reader view & Anki TSV/CSV export.`,
      quickZh: '🌐 划词秒译',
      quickEn: '🌐 Translate',
      acceptsZh: ['选中文本秒译 (text)', 'OCR 截图框选翻译 (image)'],
      acceptsEn: ['Selection Text (text)', 'OCR Capture Image (image)'],
      sandbox: 'Seatbelt: network + filesystem · Bridge: selection, ocr, audio',
      cmds: [
        ['tr / fy', '⌥⇧T 静默划词译', '⌥⇧T Silent Selection Translate'],
        ['tr ocr', '⌥⇧O 截图识字译', '⌥⇧O Screenshot OCR Translate'],
        ['tr word', '收藏至生词本', 'Save to Vocab Notebook'],
        ['tr anki', '导出 Anki 词卡', 'Export Anki Flashcards']
      ]
    },
    {
      id: 'browser-hub',
      icon: '🧭',
      grad: 'linear-gradient(135deg,#4338ca,#6366f1)',
      tagZh: '0ms 索引',
      tagEn: '0ms Index',
      nameZh: '三端书签与历史中枢 Browser Hub',
      nameEn: 'Browser Bookmarks & History Hub',
      shortZh: '无锁直连 Edge、Chrome（多配置档）与 Safari 书签和历史',
      shortEn: 'Lock-free SQLite search across Edge, Chrome & Safari bookmarks/history',
      detailZh: 'SQLite WAL 无锁快照直读三端浏览器全部 Profile 书签、Safari 阅读列表与近期历史，后台同步为 0ms 预建索引，在 ⌥Space 免前缀直接秒搜并按源浏览器打开。',
      detailEn: 'Reads Edge, Chrome multi-profile, and Safari bookmarks + history without DB locks, injecting a 0ms pre-built index into ⌥Space.',
      quickZh: '🧭 搜书签',
      quickEn: '🧭 Bookmarks',
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
      icon: '⏰',
      grad: 'linear-gradient(135deg,#ea580c,#f59e0b)',
      tagZh: '零守护进程',
      tagEn: 'Zero Daemon',
      nameZh: '闪电提醒 Quick Remind',
      nameEn: 'Quick Remind',
      shortZh: '一句话自然语言倒计时（10m 喝水）直通 macOS 原生提醒事项',
      shortEn: 'Natural phrase timers ("10m water") synced to native macOS Reminders',
      detailZh: '支持「10m 喝水」「18:30 拿快递」「明天 9:00 交周报」，写入系统原生提醒事项并持久准点响铃——即使退出 Lumakey 也绝不漏提醒，内置 25 分钟番茄钟。',
      detailEn: 'Parses natural phrases into native macOS Reminders so alerts fire reliably with zero background daemon, plus a 25m Pomodoro focus timer.',
      quickZh: '🍅 25m 番茄钟',
      quickEn: '🍅 25m Focus',
      acceptsZh: ['剪贴板文本转提醒 (text)'],
      acceptsEn: ['Clipboard Text to Reminder (text)'],
      sandbox: 'Seatbelt: Reminders sync · Bridge: audio',
      cmds: [
        ['rem 10m 喝水', '一句话设倒计时', 'Natural Language Countdown'],
        ['rem pomo', '启动 25m 番茄钟', 'Start 25m Pomodoro Focus'],
        ['rem list', '待办提醒看板', 'Upcoming Reminders Board'],
        ['rem snooze', '一键贪睡顺延 10m', 'Snooze +10m in 1 Key']
      ]
    },
    {
      id: 'mac-pilot',
      icon: '🎛️',
      grad: 'linear-gradient(135deg,#0066dc,#0284c7)',
      tagZh: '官方旗舰',
      tagEn: 'Official',
      nameZh: '桌面中控台 Mac Pilot',
      nameEn: 'Mac Pilot Control Deck',
      shortZh: '音量/防休眠控制、16 项系统设置免前缀直达、退盘与访达新建文件',
      shortEn: 'Volume/Caffeine, 16 System Settings panes, safe eject & Finder helper',
      detailZh: '将 16 个高频系统设置页（蓝牙/网络/显示器/隐私等）注入 0ms 索引，一键安全弹出外置硬盘、在当前访达目录新建 Markdown/代码文件，以及秒退异常卡死应用。',
      detailEn: 'Injects 16 macOS System Settings panes into 0ms search, ejects external drives safely, creates files in active Finder folder, and quits hung apps.',
      quickZh: '☕ 防休眠开关',
      quickEn: '☕ Caffeine',
      acceptsZh: ['访达文件/目录快捷操作 (file, directory)'],
      acceptsEn: ['Finder File & Folder Actions (file, directory)'],
      sandbox: 'Seatbelt: scoped AppleEvents · Bridge: systemControl, clipboard',
      cmds: [
        ['vol / mute', '精准音量与静音', 'Precision Volume & Mute'],
        ['eject', '安全退外置磁盘', 'Safely Eject Drives'],
        ['new md', '访达原地新建文件', 'New File in Active Finder'],
        ['bluetooth', '0ms 直达系统设置', '0ms System Settings Jump']
      ]
    },
    {
      id: 'screen-shield',
      icon: '🛡️',
      grad: 'linear-gradient(135deg,#0d9488,#14b8a6)',
      tagZh: '防误触锁屏',
      tagEn: 'Input Shield',
      nameZh: '状态屏遮罩 Screen Shield',
      nameEn: 'Screen Shield',
      shortZh: '擦拭键盘屏幕防误触黑屏、任务运行中防误碰保护遮罩',
      shortEn: 'Multi-display keyboard/trackpad lock for screen cleaning or running tasks',
      detailZh: '一键覆盖全部显示器（🧹 清洁屏幕中 / ⚡ 编译任务运行中请勿触碰 / ☕ 马上回来），拦截键盘与滚轮误触同时保持后台任务满速运行，长按 Esc 2 秒优雅解锁。',
      detailEn: 'Covers all displays and blocks accidental keystrokes/clicks while cleaning your Mac or running long builds; hold Esc for 2s to exit.',
      quickZh: '🧹 擦键盘锁屏',
      quickEn: '🧹 Clean Screen',
      acceptsZh: [],
      acceptsEn: [],
      sandbox: 'Seatbelt: local status only · Bridge: systemControl',
      cmds: [
        ['clean', '开启清洁屏幕遮罩', 'Keyboard Cleaning Lock'],
        ['shield task', '任务运行防碰模式', 'Build/Task Guard Overlay'],
        ['shield brb', '暂离自定义标语屏', 'Custom BRB Status Screen'],
        ['Hold Esc 2s', '防误触安全退出', 'Hold Esc 2s to Unlock']
      ]
    },
    {
      id: 'lumalink-companion',
      icon: '📡',
      grad: 'linear-gradient(135deg,#0891b2,#2563eb)',
      tagZh: '远控伴侣',
      tagEn: 'Remote Hub',
      nameZh: '流光随行 LumaLink 远控伴侣',
      nameEn: 'LumaLink Remote Companion',
      shortZh: '局域网/组网切换、6 位配对码与高清二维码、物理黑屏与 H.264 远控',
      shortEn: 'LAN/Tunnel switcher, 6-digit PIN & QR popup, Privacy Curtain & RDP',
      detailZh: '无需点开设置窗，在 ⌥Space 内直接切换局域网或虚拟组网网卡、弹出高清扫码连接卡、开启物理防窥黑屏或切换 Retina HiDPI 远控画质。',
      detailEn: 'Switch LAN or tunnel interfaces inline, pop up crisp pairing QR codes, toggle physical Privacy Curtain, and manage trusted devices.',
      quickZh: '📡 远控配对码',
      quickEn: '📡 Pairing QR',
      acceptsZh: [],
      acceptsEn: [],
      sandbox: 'Seatbelt: zero external scopes · Bridge: lumaLinkStatus',
      cmds: [
        ['lumalink qr', '弹出配对码与二维码', 'Show 6-Digit PIN & QR'],
        ['lumalink net', '秒切局域网/穿透网卡', 'Switch LAN / Tunnel NIC'],
        ['lumalink curtain', '远控物理防窥黑屏', 'Privacy Curtain Blackout'],
        ['lumalink hidpi', '切换 Retina 清晰度', 'Toggle Retina HiDPI']
      ]
    },
    {
      id: 'notion-bookmarks',
      icon: '📑',
      grad: 'linear-gradient(135deg,#334155,#0f766e)',
      tagZh: 'AES-GCM 密钥箱',
      tagEn: 'Vault Secret',
      nameZh: 'Notion 加密书签箱 Notion Vault',
      nameEn: 'Notion Bookmarks Vault',
      shortZh: '双轨 AES-GCM 加密存储凭据，一键剪贴板链接入库与离线秒搜',
      shortEn: 'AES-GCM encrypted Notion token, one-key clipboard URL save & 0ms search',
      detailZh: '集成凭据经 LMKYVLT2 256-bit 随机主密钥加密存储，支持为「保存当前剪贴板链接」绑定全局静默快捷键，并将云端书签同步至本地 0ms 索引。',
      detailEn: 'Stores your Notion token inside the 256-bit AES-GCM vault, saves clipboard URLs silently via hotkey, and syncs pages to 0ms local search.',
      quickZh: '📑 速存 Notion',
      quickEn: '📑 Save URL',
      acceptsZh: ['网页链接与文本速存 (url, text)'],
      acceptsEn: ['Save URL & Text to Notion (url, text)'],
      sandbox: 'Seatbelt: HTTPS + PluginData · Vault: 256-bit AES-GCM',
      cmds: [
        ['bm save', '静默速存剪贴板 URL', 'Silently Save Clipboard URL'],
        ['bm <关键词>', '0ms 秒搜已存页面', '0ms Search Saved Pages'],
        ['bm sync', '增量同步云端数据库', 'Sync Cloud Database'],
        ['bm tag', '默认标签自动归类', 'Auto-Tag Bookmarks']
      ]
    },
    {
      id: 'gh-pr-radar',
      icon: '🤖',
      grad: 'linear-gradient(135deg,#db2777,#7c3aed)',
      tagZh: 'MCP 10s 自制',
      tagEn: 'MCP Custom',
      nameZh: 'PR 审查雷达 (AI 一句话生成示例)',
      nameEn: 'PR Review Radar (MCP AI-Generated)',
      shortZh: '通过 lumakey-mcp 对 AI 说一句话生成的个人专属工作流插件',
      shortEn: 'Custom personal workflow plugin generated in 10s via lumakey-mcp',
      detailZh: '演示「不会写代码也能定制」：只需在 Claude Code 或 Cursor 中描述你的私有业务需求（内部工单、合并请求、服务器探针、主页排布），AI 自动完成脚手架、沙箱实测与热重载挂载。',
      detailEn: 'Demonstrates 1-sentence customization: describe any private workflow (tickets, MRs, homelab, or home layout) and lumakey-mcp scaffolds & tests it automatically.',
      quickZh: '🤖 待审 PR (3)',
      quickEn: '🤖 Open PRs (3)',
      acceptsZh: ['代码仓库链接快速预审 (url)'],
      acceptsEn: ['Inspect Repo Link (url)'],
      sandbox: 'Seatbelt: scoped HTTPS · Hot-Reloaded via FSEvents',
      cmds: [
        ['pr review', '查看待我 Review 列表', 'List PRs Awaiting Review'],
        ['pr mine', '查看我发起的流水线', 'Check My Open Pipelines'],
        ['pr refresh', '后台静默刷新索引', 'Background Index Refresh'],
        [`${SCHEME_PREFIX}reader`, '原生预览变更摘要', 'Native Reader Diff View']
      ]
    }
  ];

  const BUILDER_PROFILES = {
    minimal: [],
    daily: ['translate-hub', 'browser-hub', 'quick-remind', 'mac-pilot', 'screen-shield'],
    dev: ['translate-hub', 'browser-hub', 'mac-pilot', 'lumalink-companion', 'gh-pr-radar'],
    full: PLUGINS.map((p) => p.id)
  };

  /* ------------------------------------------------------------------------
     3. Render Interactive "Build Your Own Lumakey" Workbench (#builder)
     ------------------------------------------------------------------------ */
  const toggleListEl = document.getElementById('pluginToggleList');
  const enabledCountBadge = document.getElementById('enabledCountBadge');
  const mountedQuickPills = document.getElementById('mountedQuickPills');
  const mountedAcceptsPills = document.getElementById('mountedAcceptsPills');
  const quickMountCount = document.getElementById('quickMountCount');
  const spotlightBox = document.getElementById('pluginSpotlightBox');
  const auditSummaryBar = document.getElementById('auditSummaryBar');
  const previewDaemonStat = document.getElementById('previewDaemonStat');

  function renderWorkbench() {
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

    toggleListEl.innerHTML = PLUGINS.map((p) => {
      const isOn = state.enabledPlugins.has(p.id);
      const isFocused = state.focusedPluginId === p.id;
      return `
        <div class="plugin-toggle-item ${isFocused ? 'focused' : ''}" data-plugin-id="${p.id}">
          <div class="plugin-toggle-left">
            <span class="squircle-badge" style="background:${p.grad}">${p.icon}</span>
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
            aria-label="${zh ? '切换插件开关' : 'Toggle plugin'}"
            aria-pressed="${isOn}"
          ></button>
        </div>
      `;
    }).join('');

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
          .map((p) => `<span class="mounted-pill">${zh ? p.quickZh : p.quickEn}</span>`)
          .join('');
      }
    }

    if (mountedAcceptsPills) {
      const hooks = [];
      enabledList.forEach((p) => {
        const arr = zh ? p.acceptsZh : p.acceptsEn;
        arr.forEach((h) => hooks.push(`${p.icon} ${h}`));
      });
      if (hooks.length === 0) {
        mountedAcceptsPills.innerHTML = `<span class="empty-mount-note">${
          zh
            ? '未挂载外部右键联动（开启「流光译站 / 桌面中控台 / Notion」即可把动作自动注入截图识字与剪贴板）。'
            : 'No context hooks mounted (enable Translate Hub, Mac Pilot, or Notion to inject actions into OCR & Clipboard).'
        }</span>`;
      } else {
        mountedAcceptsPills.innerHTML = hooks
          .map((h) => `<span class="mounted-pill">${h}</span>`)
          .join('');
      }
    }

    const focused = PLUGINS.find((p) => p.id === state.focusedPluginId) || PLUGINS[0];
    const focusedOn = state.enabledPlugins.has(focused.id);
    if (spotlightBox && focused) {
      spotlightBox.innerHTML = `
        <div class="spotlight-head">
          <div class="spotlight-title-wrap">
            <span class="squircle-badge" style="background:${focused.grad}">${focused.icon}</span>
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
        <span>🛡️ ${
          zh
            ? `Seatbelt 沙箱强隔离 · 未启用扩展 (${PLUGINS.length - enabledList.length} 款) 零进程零轮询`
            : `Seatbelt Enforced · ${PLUGINS.length - enabledList.length} disabled plugin(s) use 0 RAM`
        }</span>
        <span class="mono">MenuBar + HomeLayout Synced</span>
      `;
    }

    toggleListEl.querySelectorAll('.plugin-toggle-item').forEach((row) => {
      row.addEventListener('click', (e) => {
        const pid = row.getAttribute('data-plugin-id');
        if (!pid) return;
        state.focusedPluginId = pid;
        if (e.target.closest('.mac-switch')) {
          if (state.enabledPlugins.has(pid)) state.enabledPlugins.delete(pid);
          else state.enabledPlugins.add(pid);
          state.builderProfile = 'custom';
          saveEnabledPlugins();
          syncProfileButtons();
        }
        renderWorkbench();
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
      renderWorkbench();
      renderLauncher();
    });
  });

  /* ------------------------------------------------------------------------
     4. Interactive 880×544 Launch Panel Customizer & Unified Search Simulator
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
      badgeBg: 'linear-gradient(135deg,#7c3aed,#a855f7)',
      badgeText: '🌐',
      titleZh: '流光译站：Ephemeral micro-core architecture (用完即焚的微内核架构)',
      titleEn: 'Translate Hub: Ephemeral micro-core architecture (用完即焚的微内核架构)',
      subZh: 'Translate Hub · 内置词典 + 本地 Ollama + 双语 TTS · 右键可钉上启动面板',
      subEn: 'Translate Hub · Built-in Dict + Local Ollama + Dual TTS · Right-click to pin',
      shortcut: '⌘1',
      lens: {
        tag: 'Plugin v3.7 · translate-hub',
        bigZh: '双源秒译 + OCR',
        bigEn: 'Dual-Engine + OCR',
        big: '双源秒译 + OCR',
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
      badgeBg: 'linear-gradient(135deg,#ea580c,#f59e0b)',
      badgeText: '⏰',
      titleZh: '新建闪电提醒：10 分钟后「站起来喝口水休息眼睛」',
      titleEn: 'Create Quick Reminder: In 10m — "Hydrate & rest eyes"',
      subZh: 'Quick Remind · 零常驻进程直通系统提醒事项 · 准点系统级响铃',
      subEn: 'Quick Remind · Syncs to native macOS Reminders with 0 background daemon',
      shortcut: '⌘1',
      lens: {
        tag: 'Plugin v3.7 · quick-remind',
        big: 'T-10:00',
        descZh: '支持「10m 喝水」「18:30 拿快递」「明天 9:00 交周报」与 25m 番茄专注，退出软件亦由 macOS 准时提醒。',
        descEn: 'Supports relative ("10m") & calendar times plus 25m Pomodoro; persisted natively in macOS Reminders.',
        kvs: [
          ['Daemon Overhead', '0 MB (Native Reminders)'],
          ['Quick Action', '↵ Create · Snooze +10m'],
          ['Pin Support', 'Right-Click → Omni Dock']
        ]
      }
    },
    {
      id: 'item-browser',
      scopes: ['all', 'plugins'],
      match: ['bh', 'apple', 'human', 'interface', 'bookmark', 'safari', 'chrome', 'edge', '书签'],
      badgeBg: 'linear-gradient(135deg,#4338ca,#6366f1)',
      badgeText: '🧭',
      titleZh: 'Human Interface Guidelines — Apple Developer (Safari 书签)',
      titleEn: 'Human Interface Guidelines — Apple Developer (Safari)',
      subZh: 'Browser Hub · 0ms 预建索引命中 · 右键可钉入主页分组书签架',
      subEn: 'Browser Hub · 0ms Pre-Indexed · Right-click to pin to Home Shelf',
      shortcut: '⌘1',
      lens: {
        tag: '0ms Pre-Indexed · browser-hub',
        big: '0.2ms Hit',
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
      badgeBg: 'linear-gradient(135deg,#0066dc,#0284c7)',
      badgeText: '∑',
      titleZh: '262,144 Bytes = 0.25 MiB (0.262 MB)',
      titleEn: '262,144 Bytes = 0.25 MiB (0.262 MB)',
      subZh: '内置算式换算与 DevToolkit · 同时支持 #HEX 色板 / JWT / 时间戳 / 二维码',
      subEn: 'Built-in Math & DevToolkit · Also evaluates #HEX, JWT, Timestamps & QR',
      shortcut: '⌘1',
      lens: {
        tag: 'Native Base · Unit & DevToolkit',
        big: '0.25 MiB',
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
      match: ['swift', 'lmky', 'file', 'plugin', 'home', '文件'],
      badgeBg: 'linear-gradient(135deg,#ea580c,#db2777)',
      badgeText: 'S',
      titleZh: 'HomeCustomizationSettingsView.swift',
      titleEn: 'HomeCustomizationSettingsView.swift',
      subZh: 'Sources/Lumakey · LMKYIDX3 mmap 零拷贝全盘与外置硬盘秒搜命中',
      subEn: 'Sources/Lumakey · Instant LMKYIDX3 mmap internal & external drive hit',
      shortcut: '⌘2',
      lens: {
        tag: 'LMKYIDX3 · Zero-WebKit Reader',
        big: '≤ 300 Lines',
        descZh: '按 ↵ 在纯原生代码阅读窗秒开（0 MB 网页内核开销），按 ⌘↵ 在访达定位，或右键将常用目录钉上启动面板。',
        descEn: 'Press ↵ for pure-Swift reader (0 MB WebKit), ⌘↵ to reveal in Finder, or right-click to pin folder to Home.',
        kvs: [
          ['Index Format', 'LMKYIDX3 mmap + FSEvents'],
          ['External Drives', 'Supported + NTFS Guard'],
          ['Idle Unload', '90s Auto Heap Return']
        ]
      }
    },
    {
      id: 'clip-1',
      scopes: ['all', 'clip'],
      match: ['clip', 'paste', 'mcp', '剪贴板'],
      badgeBg: 'linear-gradient(135deg,#059669,#0d9488)',
      badgeText: '📋',
      titleZh: 'claude mcp add lumakey /Applications/Lumakey.app/Contents/MacOS/lumakey-mcp',
      titleEn: 'claude mcp add lumakey /Applications/Lumakey.app/Contents/MacOS/lumakey-mcp',
      subZh: '剪贴板历史 · 支持 15 步误删撤回 · 自动跳过密码管理器敏感条目',
      subEn: 'Clipboard History · 15-step delete undo · Auto-skips password manager secrets',
      shortcut: '⌘3',
      lens: {
        tag: 'ClipboardMonitor · 15-Step Undo',
        big: 'SHA-256 Pinned',
        descZh: '回车直接粘贴回刚才的前台应用，误删支持 15 步撤回，还能一键交给声明了 accepts: ["text"] 的插件接着处理。',
        descEn: 'Press Return to paste straight into your active app, undo accidental deletes up to 15 steps, or route to plugins.',
        kvs: [
          ['Media Support', 'Text · #HEX · Image · File · GIF'],
          ['Privacy Filter', 'Concealed / Transient Skipped'],
          ['Sync', '.lumakeybackup + WebDAV']
        ]
      }
    }
  ];

  const leftPane = document.getElementById('launcherLeftPane');
  const rightLens = document.getElementById('launcherRightLens');
  const launcherInput = document.getElementById('launcherInput');
  const engineStatus = document.getElementById('panelEngineStatus');

  function renderBentoHome() {
    const zh = state.lang === 'zh';
    const enabledList = PLUGINS.filter((p) => state.enabledPlugins.has(p.id));
    const prof = state.homeProfile || 'balanced';

    let leftHtml = '';
    let lensTag = '';
    let lensBig = '';
    let lensDesc = '';
    let lensKvs = [];
    let statusLabel = '';

    if (prof === 'minimal') {
      // Preset 2: Minimal Focus — Bento hidden, 2-row (16-slot style) Hybrid Omni Dock + Quick Shelf
      statusLabel = `Home: Minimal Focus · ${enabledList.length} Active Plugins`;
      const dockRows = [
        [
          { dot: 'linear-gradient(135deg,#0284c7,#2563eb)', label: 'Xcode' },
          { dot: 'linear-gradient(135deg,#059669,#10b981)', label: 'Ghostty' },
          { dot: 'linear-gradient(135deg,#7c3aed,#4338ca)', label: 'Cursor' },
          { dot: 'linear-gradient(135deg,#ea580c,#ef4444)', label: 'Safari' }
        ],
        [
          { dot: 'linear-gradient(135deg,#7c3aed,#a855f7)', label: zh ? '流光译站' : 'Translate' },
          { dot: 'linear-gradient(135deg,#0d9488,#14b8a6)', label: '~/Code' },
          { dot: 'linear-gradient(135deg,#f59e0b,#ea580c)', label: 'GitHub' },
          { dot: 'linear-gradient(135deg,#4f46e5,#0ea5e9)', label: 'Obsidian' }
        ]
      ];
      leftHtml = `
        <div class="home-profile-strip">
          <span>${zh ? '当前启动面板方案：极简纯搜 (已隐藏大磁贴与底部提示)' : 'Active Profile: Minimal Focus (Bento & Tips Hidden)'}</span>
          <span class="mono">2×8 Omni Dock</span>
        </div>
        <div class="dock-strip-label">
          <span>${zh ? '双排混合高频坞 (本机 App + 插件 + 常用目录 + 书签混排)' : '2-Row Hybrid Omni Dock (Apps + Plugins + Folders + URLs)'}</span>
          <span class="mono">⌘1..8</span>
        </div>
        ${dockRows.map((row) => `
          <div class="dock-mini-row">
            ${row.map((it) => `<div class="dock-app-pill"><span class="dock-app-dot" style="background:${it.dot}"></span>${it.label}</div>`).join('')}
          </div>
        `).join('')}
        <div class="quick-btn-bar-mock">
          <span class="quick-btn-label">${zh ? '快捷入口架：' : 'Quick Access:'}</span>
          <span class="quick-btn-pill" data-preset-jump="translate">${zh ? '✂️ 区域截图' : '✂️ Capture'}</span>
          <span class="quick-btn-pill" data-preset-jump="translate">${zh ? '🔎 离线识字' : '🔎 Offline OCR'}</span>
          <span class="quick-btn-pill" data-preset-jump="remind">${zh ? '📋 剪贴板历史' : '📋 Clipboard'}</span>
          <span class="quick-btn-pill" data-preset-jump="dev">${zh ? '∑ 算式换算' : '∑ Unit Math'}</span>
        </div>
      `;
      lensTag = 'HomeLayoutPreset · minimal';
      lensBig = zh ? '极简双排混合坞' : 'Minimal 16-Slot';
      lensDesc = zh
        ? '不喜欢花哨磁贴？一键切换「极简纯搜」方案即可关掉大号 Bento 磁贴与提示条，只留双排混合高频坞（支持把常用软件、~/Code 目录、网页和插件混排在一起）。'
        : 'Prefer zero visual clutter? Minimal Focus hides Bento tiles and tips, leaving a clean 2-row hybrid Omni Dock mixing native apps, folders, URLs, and plugins.';
      lensKvs = [
        [zh ? '可见分区' : 'Visible Zones', 'omniDock (2 Rows) + pillShelves'],
        [zh ? '补位策略' : 'Fill Mode', 'smartHybrid (Pinned + log₂)'],
        [zh ? '安全回退' : 'Safety Undo', '1-Click undoLastChange']
      ];
    } else if (prof === 'developer') {
      // Preset 3: Developer Workbench — 6 Dev Bento tiles + Dev Plugins & Dev Bookmarks Shelves + Query Chips
      statusLabel = `Home: Developer Workbench · ${enabledList.length} Active Plugins`;
      const devTiles = [
        { bg: 'linear-gradient(135deg,#0284c7,#2563eb)', icon: '▤', t: zh ? '双栏文件台' : 'Workspace', s: '⌥E · NTFS Guard', jump: '#capabilities' },
        { bg: 'linear-gradient(135deg,#db2777,#e11d48)', icon: '📌', t: zh ? '贴图与标注' : 'Pin & Capture', s: '⌥A · Click-Thru', jump: '#capabilities' },
        { bg: 'linear-gradient(135deg,#7c3aed,#a855f7)', icon: '🔎', t: zh ? '离线 OCR' : 'Offline OCR', s: '⌥O · Vision', preset: 'translate' },
        { bg: 'linear-gradient(135deg,#4f46e5,#0ea5e9)', icon: '⇄', t: zh ? '实时进程网速' : 'Socket Net', s: '⌥N · Endpoints', jump: '#capabilities' },
        { bg: 'linear-gradient(135deg,#059669,#10b981)', icon: '⚡', t: zh ? '芯片功耗脉搏' : 'Chip Wattage', s: '⌥M · P/E Cores', jump: '#capabilities' },
        { bg: 'linear-gradient(135deg,#ea580c,#f59e0b)', icon: '🧹', t: zh ? '缓存清理' : 'Cache Clean', s: 'Safe to Trash', jump: '#capabilities' }
      ];
      leftHtml = `
        <div class="bento-mini-grid">
          ${devTiles.map((tile, idx) => `
            <div class="bento-tile" data-dev-idx="${idx}">
              <span class="squircle-badge" style="background:${tile.bg}">${tile.icon}</span>
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
            <span class="quick-btn-pill">🌐 GitHub</span>
            <span class="quick-btn-pill">⚡ Localhost :3000</span>
            <span class="quick-btn-pill">📘 cursor://repo</span>
            <span class="quick-btn-pill" data-jump-builder="translate-hub">🌐 Translate</span>
          </div>
          <div class="quick-btn-bar-mock">
            <span class="quick-btn-label">${zh ? '试搜芯片：' : 'Query Chips:'}</span>
            <span class="quick-btn-pill mono" data-fill-query="port 3000">port 3000</span>
            <span class="quick-btn-pill mono" data-fill-query="swift">ext:swift</span>
            <span class="quick-btn-pill mono" data-fill-query="256 * 1024 bytes to mb">256 KiB → MB</span>
          </div>
        </div>
      `;
      lensTag = 'HomeLayoutPreset · developer';
      lensBig = zh ? '开发者工作台主页' : 'Developer Hub';
      lensDesc = zh
        ? '专为写代码与联调配置的主页 Profile：置顶双栏整理台、功耗与网速监控，并挂载支持 cursor:// / vscode:// 协议与指定浏览器打开的开发书签架；也可让 lumakey-mcp 一句话自动生成！'
        : 'Tailored for coding & debugging: pins Dual Workspace, Wattage & Socket monitors alongside URL shelves supporting cursor://, vscode://, and per-bookmark browser overrides.';
      lensKvs = [
        [zh ? '书签协议白名单' : 'Safe URL Schemes', 'https · cursor · vscode · obsidian'],
        [zh ? '分组胶囊架' : 'Pill Shelves', zh ? '最多 6 组自定义命名架' : 'Up to 6 Named Shelves'],
        [zh ? 'AI 自动编排' : 'MCP Orchestration', 'lumakey_update_home_layout']
      ];
    } else if (prof === 'creatorBookmarks') {
      // Preset 4: 4-Column Compact Bento (8 tiles) + Curated Bookmarks & Custom Apps Shelves
      statusLabel = `Home: 4-Col Apps & Bookmarks · ${enabledList.length} Active Plugins`;
      const compactTiles = [
        { bg: 'linear-gradient(135deg,#0066dc,#2563eb)', icon: '✂️', t: zh ? '区域截图' : 'Capture', s: '⌥A' },
        { bg: 'linear-gradient(135deg,#db2777,#e11d48)', icon: '🎞️', t: zh ? '录制 GIF' : 'GIF Rec', s: '⌥G' },
        { bg: 'linear-gradient(135deg,#7c3aed,#a855f7)', icon: '🔎', t: zh ? '离线识字' : 'OCR', s: '⌥O' },
        { bg: 'linear-gradient(135deg,#059669,#0d9488)', icon: '📋', t: zh ? '剪贴板' : 'Clips', s: '15 Undo' },
        { bg: 'linear-gradient(135deg,#0891b2,#2563eb)', icon: '📡', t: zh ? '流光随行' : 'LumaLink', s: 'Plugin' },
        { bg: 'linear-gradient(135deg,#4338ca,#6366f1)', icon: '🌐', t: zh ? '流光译站' : 'Translate', s: 'Plugin' },
        { bg: 'linear-gradient(135deg,#ea580c,#f59e0b)', icon: '⏰', t: zh ? '闪电提醒' : 'Remind', s: 'Plugin' },
        { bg: 'linear-gradient(135deg,#0284c7,#0369a1)', icon: '🎛️', t: zh ? '中控台' : 'Mac Pilot', s: 'Plugin' }
      ];
      leftHtml = `
        <div class="bento-mini-grid cols-4">
          ${compactTiles.map((tile) => `
            <div class="bento-tile" data-jump-builder="translate-hub">
              <span class="squircle-badge" style="background:${tile.bg}">${tile.icon}</span>
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
            <span class="quick-btn-pill">🧭 Safari 阅读单</span>
            <span class="quick-btn-pill">📑 Notion 知识库</span>
            <span class="quick-btn-pill">🎨 Figma 设计稿</span>
          </div>
          <div class="quick-btn-bar-mock">
            <span class="quick-btn-label">${zh ? '自制与扩展：' : 'Custom Apps:'}</span>
            ${(enabledList.length > 0 ? enabledList.slice(0, 3) : PLUGINS.slice(0, 3)).map((p) => `
              <span class="quick-btn-pill" data-jump-builder="${p.id}">${zh ? p.quickZh : p.quickEn}</span>
            `).join('')}
          </div>
        </div>
      `;
      lensTag = 'HomeLayoutPreset · 4-Column Bento';
      lensBig = zh ? '4 列紧凑 × 书签架' : '4-Col + Shelves';
      lensDesc = zh
        ? '高频入口比较多？把 Bento 磁贴切成 4 列紧凑模式即可一屏放下 8 枚彩色磁贴，搭配下方多组命名书签架，搜到任何结果点右键就能直接钉进来！'
        : 'Have lots of daily shortcuts? Switch Bento to 4-column compact density (up to 16 tiles) paired with named bookmark & custom plugin shelves.';
      lensKvs = [
        [zh ? '磁贴列数可选' : 'Bento Columns', '2 Wide / 3 Standard / 4 Compact'],
        [zh ? '单条目外观定制' : 'Per-Item Style', zh ? '自定义标题 / 图标 / 强调色' : 'Custom Title, Icon & Color'],
        [zh ? '跨机加密漫游' : 'Cross-Mac Sync', 'home-layout.json in Backup v2']
      ];
    } else {
      // Default Preset 1: Balanced Home (3×2 Bento + Mounted Plugin Quick Shelf + Smart Hybrid Dock)
      statusLabel = `Home: Balanced · ${enabledList.length} Active Plugin(s)`;
      const tiles = [
        { bg: 'linear-gradient(135deg,#0066dc,#2563eb)', icon: '🔍', t: zh ? '全盘秒搜' : 'Disk Search', s: 'LMKYIDX3 mmap', scope: 'files' },
        { bg: 'linear-gradient(135deg,#4338ca,#6366f1)', icon: '🧭', t: zh ? '三端书签' : 'Browser Hub', s: '0ms SQLite Index', fillQ: 'bh' },
        { bg: 'linear-gradient(135deg,#7c3aed,#a855f7)', icon: '🌐', t: zh ? '流光译站' : 'Translate Hub', s: 'Plugin · OCR/划词', preset: 'translate' },
        { bg: 'linear-gradient(135deg,#db2777,#e11d48)', icon: '✂️', t: zh ? '截图与 GIF' : 'Capture & GIF', s: '⌥A / ⌥G / ⌥O', jump: '#capabilities' },
        { bg: 'linear-gradient(135deg,#ea580c,#f59e0b)', icon: '⏰', t: zh ? '闪电提醒' : 'Quick Remind', s: 'Plugin · 10m 喝水', preset: 'remind' },
        { bg: 'linear-gradient(135deg,#059669,#0d9488)', icon: '🧩', t: zh ? '高度定制台' : 'Customizer', s: `${enabledList.length} Active`, jump: '#builder' }
      ];

      const quickBarHtml = enabledList.length > 0
        ? `
          <div class="quick-btn-bar-mock">
            <span class="quick-btn-label">${zh ? '已钉胶囊架：' : 'Pinned Shelf:'}</span>
            ${enabledList.slice(0, 4).map((p) => `
              <span class="quick-btn-pill" data-jump-builder="${p.id}">${zh ? p.quickZh : p.quickEn}</span>
            `).join('')}
          </div>
        `
        : `
          <div class="quick-btn-bar-mock">
            <span class="quick-btn-label">${zh ? '纯净微内核态：未挂载任何扩展胶囊（可在下方定制台按需开启）' : 'Pure Micro-Core: Plugin shelf hidden (enable below)'}</span>
          </div>
        `;

      leftHtml = `
        <div class="bento-mini-grid">
          ${tiles.map((tile, idx) => `
            <div class="bento-tile" data-bal-idx="${idx}">
              <span class="squircle-badge" style="background:${tile.bg}">${tile.icon}</span>
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
          <div class="dock-app-pill"><span class="dock-app-dot" style="background:linear-gradient(135deg,#0284c7,#2563eb)"></span>Xcode</div>
          <div class="dock-app-pill"><span class="dock-app-dot" style="background:linear-gradient(135deg,#059669,#10b981)"></span>Ghostty</div>
          <div class="dock-app-pill"><span class="dock-app-dot" style="background:linear-gradient(135deg,#7c3aed,#4338ca)"></span>Cursor</div>
          <div class="dock-app-pill"><span class="dock-app-dot" style="background:linear-gradient(135deg,#ea580c,#ef4444)"></span>Safari</div>
        </div>
      `;

      lensTag = zh ? '全新启动面板自定义' : 'Customizable Launch Panel';
      lensBig = zh ? `4 区自由编排` : `4 Modular Zones`;
      lensDesc = zh
        ? '点击上方按钮即可实时切换「均衡默认 / 极简 16 格坞 / 开发者主页 / 4 列书签架」4 套主页方案！左侧胶囊架还与下方高度定制台实时联动，支持多套场景 Profile 与 AI 一句话排布。'
        : 'Click the preset chips above to switch live between Balanced, Minimal 16-Slot Dock, Developer Hub, and 4-Column Bookmark layouts — synced live with the workbench below!';
      lensKvs = [
        [zh ? '多场景主页方案' : 'Home Profiles', zh ? '最多 8 套独立方案秒切' : 'Up to 8 Switchable Profiles'],
        [zh ? '视窗恒定尺寸' : 'Constant Frame', '880 × 544 (Zero-Jitter)'],
        [zh ? 'AI 定制工具数' : 'Embedded MCP', 'lumakey-mcp (16 Tools)']
      ];

      setTimeout(() => {
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
              document.querySelector(t.jump)?.scrollIntoView({ behavior: 'smooth' });
            }
          });
        });
      }, 0);
    }

    if (engineStatus) engineStatus.textContent = statusLabel;
    leftPane.innerHTML = leftHtml;

    rightLens.innerHTML = `
      <div class="lens-card">
        <div>
          <div class="lens-header">
            <span class="accent-pill">${lensTag}</span>
            <span class="mono" style="font-size:11px;color:var(--text-tertiary)">⌥Space</span>
          </div>
          <div class="lens-big-value gradient-text">${lensBig}</div>
          <p class="lens-desc">${lensDesc}</p>
        </div>
        <div class="lens-kv-list">
          ${lensKvs.map(([k, v]) => `<div class="lens-kv"><span>${k}</span><span class="mono">${v}</span></div>`).join('')}
        </div>
      </div>
    `;

    leftPane.querySelectorAll('[data-jump-builder]').forEach((pill) => {
      pill.addEventListener('click', () => {
        state.focusedPluginId = pill.getAttribute('data-jump-builder') || 'translate-hub';
        renderWorkbench();
        document.getElementById('builder')?.scrollIntoView({ behavior: 'smooth' });
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
        else document.getElementById('capabilities')?.scrollIntoView({ behavior: 'smooth' });
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
          <div class="lens-big-value gradient-text mono">${zh ? (l.bigZh || l.big) : (l.bigEn || l.big)}</div>
          <p class="lens-desc">${zh ? l.descZh : l.descEn}</p>
        </div>
        <div class="lens-kv-list">
          ${l.kvs.map(([k, v]) => `<div class="lens-kv"><span>${k}</span><span class="mono">${v}</span></div>`).join('')}
        </div>
      </div>
    `;
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
          badgeBg: 'linear-gradient(135deg,#0066dc,#4338ca)',
          badgeText: '✦',
          titleZh: `并发检索全盘、剪贴板与已启用插件：“${state.query}”`,
          titleEn: `Unified Core + Plugin Match: "${state.query}"`,
          subZh: '同时扫描本地应用 · LMKYIDX3 移动硬盘与全盘 · 剪贴板 · 0ms 插件索引',
          subEn: 'Scans Apps · LMKYIDX3 Drives · Clipboard · 0ms Plugin Index',
          shortcut: '⌘1',
          lens: {
            tag: 'LauncherEngine · 0.3ms',
            big: state.query.slice(0, 14),
            descZh: '搜到的任意结果点右键即可直接钉上你的自定义启动面板；若想新增专属指令，对 Claude / Cursor 说一句话就能十秒造出插件！',
            descEn: 'Right-click any hit to pin straight onto your Launch Panel, or ask Claude / Cursor via lumakey-mcp to build a custom command in 10s.',
            kvs: [
              ['Scope', state.scope.toUpperCase()],
              ['Frame Lock', '880 × 544 Constant'],
              ['Pin Action', 'Right-Click → Home Profile']
            ]
          }
        }
      ];
    }

    if (engineStatus) {
      engineStatus.textContent = `Matched ${matches.length} item(s) · Right-Click to Pin · 0.3ms`;
    }

    leftPane.innerHTML = `
      <div class="result-list">
        ${matches.map((item, idx) => `
          <div class="result-row ${idx === 0 ? 'selected' : ''}" data-idx="${idx}">
            <div class="result-row-main">
              <span class="squircle-badge" style="background:${item.badgeBg};width:30px;height:30px;font-size:13px">${item.badgeText}</span>
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
      const selectRow = () => {
        leftPane.querySelectorAll('.result-row').forEach((r) => r.classList.remove('selected'));
        row.classList.add('selected');
        const item = matches[Number(row.dataset.idx)];
        if (item) renderLensForItem(item);
      };
      row.addEventListener('mouseenter', selectRow);
      row.addEventListener('click', selectRow);
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
    document.getElementById('heroPanel')?.scrollIntoView({ behavior: 'smooth', block: 'center' });
    setTimeout(() => launcherInput?.focus(), 220);
    showPanelToast(state.lang === 'zh' ? '⌥Space 已聚焦体验框' : '⌥Space Focused');
  });

  document.querySelectorAll('#panelFooterHints .footer-hint-btn').forEach((btn) => {
    btn.addEventListener('click', () => {
      const act = btn.dataset.footerAct;
      const zh = state.lang === 'zh';
      if (act === 'exec') {
        const selTitle = leftPane?.querySelector('.result-row.selected .result-title')?.textContent?.trim();
        showPanelToast(selTitle ? (zh ? `↵ 已执行：${selTitle.slice(0, 18)}…` : `↵ Executed: ${selTitle.slice(0, 18)}…`) : (zh ? '↵ 已打开当前选中项' : '↵ Opened selected item'));
      } else if (act === 'quick') {
        applyPreset('translate');
        showPanelToast(zh ? '⌘1 盲按快选：流光译站' : '⌘1 Quick Pick: Translate');
      } else if (act === 'pin') {
        showPanelToast(zh ? '📌 在左侧任意磁贴/结果点右键即可钉上主页' : '📌 Right-click any tile/hit to pin to Home');
      } else if (act === 'focus') {
        launcherInput?.focus();
        showPanelToast(zh ? '⌥Space 搜索框已聚焦' : '⌥Space Input Focused');
      }
    });
  });

  launcherInput?.addEventListener('input', (e) => {
    state.query = e.target.value;
    document.querySelectorAll('.preset-chip').forEach((c) => c.classList.remove('active'));
    renderLauncher();
  });

  launcherInput?.addEventListener('keydown', (e) => {
    if (e.key === 'Tab') {
      e.preventDefault();
      const order = ['all', 'plugins', 'files', 'clip'];
      const next = order[(order.indexOf(state.scope) + 1) % order.length];
      state.scope = next;
      syncScopeButtons();
      renderLauncher();
    } else if (e.key === 'Escape') {
      applyPreset('bento');
      launcherInput.blur();
    }
  });

  window.addEventListener('keydown', (e) => {
    if ((e.altKey && e.code === 'Space') || (e.key === '/' && document.activeElement !== launcherInput)) {
      e.preventDefault();
      document.getElementById('hero')?.scrollIntoView({ behavior: 'smooth' });
      setTimeout(() => launcherInput?.focus(), 260);
    }
  });

  /* ------------------------------------------------------------------------
     5. Interactive Stage Widgets inside #theatre (Scenes 0-3 + Capabilities)
     ------------------------------------------------------------------------ */
  // Scene 0: MCP Pipeline Sequence & Apply Demo Card
  let mcpTimers = [];
  function playMcpSequence() {
    mcpTimers.forEach((t) => clearTimeout(t));
    mcpTimers = [];
    const items = Array.from(document.querySelectorAll('#mcpSceneStage .mcp-seq-item'));
    items.forEach((el) => el.classList.remove('seq-lit', 'seq-current'));
    items.forEach((el, idx) => {
      const t = setTimeout(() => {
        items.forEach((other) => other.classList.remove('seq-current'));
        el.classList.add('seq-lit');
        if (el.classList.contains('mcp-step-row')) el.classList.add('seq-current');
      }, 120 + idx * 240);
      mcpTimers.push(t);
    });
  }
  playMcpSequence();

  document.getElementById('mcpReplayBtn')?.addEventListener('click', playMcpSequence);

  const mcpApplyCard = document.getElementById('mcpApplyDemoCard');
  if (mcpApplyCard) {
    const triggerApply = () => {
      applyPreset('home_dev');
      document.getElementById('heroPanel')?.scrollIntoView({ behavior: 'smooth', block: 'center' });
      showPanelToast(state.lang === 'zh' ? '✦ 已按 AI 指令热刷新为「开发者主页」' : '✦ Hot-reloaded "Developer Hub" Profile');
    };
    mcpApplyCard.addEventListener('click', triggerApply);
    mcpApplyCard.addEventListener('keydown', (e) => {
      if (e.key === 'Enter' || e.key === ' ') {
        e.preventDefault();
        triggerApply();
      }
    });
  }

  // Scene 1: Slider + Model Select + AES-GCM Vault + Silent Hotkey + Freeform Glass HUD
  const sliderTrack = document.getElementById('demoSliderTrack');
  const sliderFill = document.getElementById('demoSliderFill');
  const sliderKnob = document.getElementById('demoSliderKnob');
  const sliderBadge = document.getElementById('sliderValueBadge');
  const sliderModeLabel = document.getElementById('sliderModeLabel');
  const sliderSamplePreview = document.getElementById('sliderSamplePreview');
  const autoSaveBadge = document.getElementById('settingsAutoSaveBadge');

  function flashAutoSaved() {
    if (!autoSaveBadge) return;
    autoSaveBadge.textContent = state.lang === 'zh' ? '✓ 已实时保存 settings.json' : '✓ settings.json Synced';
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
        sliderModeLabel.textContent = zh ? '🎯 精准严谨 · Precise' : '🎯 Precise · Deterministic';
        sliderSamplePreview.textContent = zh
          ? '实时译文预览：“用完即焚的微内核架构。”'
          : 'Live Preview: "Ephemeral micro-core architecture."';
      } else if (clamped < 0.68) {
        sliderModeLabel.textContent = zh ? '⚖️ 均衡自然 · Balanced' : '⚖️ Balanced · Natural';
        sliderSamplePreview.textContent = zh
          ? '实时译文预览：“用完即焚的原生微内核，轻巧不占内存。”'
          : 'Live Preview: "Ephemeral native micro-core, light on memory."';
      } else {
        sliderModeLabel.textContent = zh ? '✨ 灵动润色 · Creative' : '✨ Creative · Expressive';
        sliderSamplePreview.textContent = zh
          ? '实时译文预览：“一触流光，用完即焚的轻盈桌面艺术品。”'
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
        ? '🔓 sk-lumakey-demo-8a4c9f2a (Decrypted)'
        : '🔒 sk-••••9f2a (AES-GCM)';
    }
    flashAutoSaved();
  });

  const DEMO_HOTKEYS = [
    ['⌥⇧T', '✓ 三层热键无冲突 · 唤醒词可改', '✓ 3-Tier Guard Clear · Custom Keyword'],
    ['⌥⇧D', '✓ 已绑定后台静默划词译', '✓ Bound to Silent Selection Translate'],
    ['⌃⌥Space', '✓ 全局直达子命令 · 0 抢焦点', '✓ Direct Subcommand · Zero Focus Steal']
  ];
  const hotkeyCard = document.getElementById('demoHotkeyCard');
  if (hotkeyCard) {
    const cycleHotkey = () => {
      state.hotkeyIdx = (state.hotkeyIdx + 1) % DEMO_HOTKEYS.length;
      const [kbd, zhMsg, enMsg] = DEMO_HOTKEYS[state.hotkeyIdx];
      const kbdEl = document.getElementById('demoHotkeyKbd');
      const stEl = document.getElementById('demoHotkeyStatus');
      if (kbdEl) kbdEl.textContent = kbd;
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

  // Scene 2: 4-Tier Smart Sniffer
  const SNIFFER_MODES = {
    repo: {
      url: `${REPO_BASE}/tree/main/plugin-demo`,
      kind: 'Store Registry (7 Plugins)',
      sha: 'SHA-256: 8f4c…d91a ✓',
      descZh: '自动识别开源仓库子目录并定位 lumakey-registry.json，一键订阅全部 7 款官方原生 Swift 插件并强制核对 SHA-256。',
      descEn: 'Auto-resolves repository subdirectory to lumakey-registry.json, subscribing all 7 native Swift plugins with SHA-256 verification.'
    },
    registry: {
      url: `${REPO_BASE}/blob/main/plugin-demo/lumakey-registry.json`,
      kind: 'JSON Store Manifest',
      sha: 'SHA-256: 3a9e…44b2 ✓',
      descZh: '直接解析商店索引清单 JSON，支持增量检查版本更新与防伪装沙箱权限比对，任何悄悄越权都会被拦截。',
      descEn: 'Parses store manifest JSON directly with one-click version updates and anti-spoofing capability boundary checks.'
    },
    archive: {
      url: 'plugin-demo/dist/translate-hub.zip',
      kind: 'Direct Plugin Package',
      sha: 'SHA-256: c710…e208 ✓',
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
    if (mockEl) {
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

  // Scene 3: Security & Backup Layer Selector
  const SANDBOX_TAGS = ['Seatbelt Isolated', 'UDS 0700 Scoped', 'AES-GCM 256-bit', 'LZFSE + WebDAV'];
  document.querySelectorAll('#sandboxLayerList .sec-row').forEach((row) => {
    row.addEventListener('click', () => {
      const idx = Number(row.dataset.secIdx || 0);
      state.secIdx = idx;
      document.querySelectorAll('#sandboxLayerList .sec-row').forEach((r) => {
        r.classList.toggle('sec-active', Number(r.dataset.secIdx) === idx);
      });
      const tagEl = document.getElementById('sandboxActiveTag');
      if (tagEl) tagEl.textContent = SANDBOX_TAGS[idx] || 'Defense in Depth';
    });
  });

  // Capabilities (#capabilities) Micro-Stages
  const MS_TICKERS = {
    bento: 'HomeCustomization.swift',
    home_min: 'OmniDock · 16 Hybrid Slots',
    home_dev: 'cursor://lumakey-repo',
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

  const SWATCH_COLORS = ['#38BDF8', '#A855F7', '#10B981', '#F59E0B'];
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
    if (lbl) lbl.textContent = `${hex} Copied ✓`;
    setTimeout(() => {
      btn.classList.remove('copied');
      if (dot) dot.style.background = nextHex;
      if (lbl) lbl.textContent = `${nextHex} · Copy C`;
    }, 1100);
  });

  /* ------------------------------------------------------------------------
     6. Dual-Theme (Default Pure Frost!) & Bilingual Live Switching
     ------------------------------------------------------------------------ */
  function applyTheme(themeId, originEvent = null) {
    const commit = () => {
      state.theme = themeId;
      document.documentElement.setAttribute('data-theme', themeId);
      safeSet('lumakey-showcase-theme-v2', themeId);

      const label = document.getElementById('themeToggleLabel');
      const dict = I18N[state.lang];
      if (label) {
        label.textContent = themeId === 'pure-frost' ? dict.theme_frost : dict.theme_prism;
      }

      document.querySelectorAll('[data-set-theme]').forEach((btn) => {
        btn.classList.toggle('active', btn.dataset.setTheme === themeId);
      });

      renderLauncher();
    };

    if (
      originEvent &&
      typeof document.startViewTransition === 'function' &&
      !window.matchMedia('(prefers-reduced-motion: reduce)').matches
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
          { duration: 480, easing: 'cubic-bezier(0.22, 1, 0.36, 1)', pseudoElement: '::view-transition-new(root)' }
        );
      }).catch(() => {});
    } else {
      commit();
    }
  }

  function applyLanguage(lang) {
    state.lang = lang;
    document.documentElement.lang = lang === 'zh' ? 'zh-CN' : 'en';
    safeSet('lumakey-showcase-lang-v2', lang);

    const dict = I18N[lang];
    document.querySelectorAll('[data-i18n]').forEach((el) => {
      const key = el.getAttribute('data-i18n');
      if (dict[key] !== undefined) {
        const val = dict[key];
        if (val.includes('<strong>')) {
          el.innerHTML = val;
        } else if (val.includes('|')) {
          el.innerHTML = val
            .split('|')
            .map((s) => {
              const trail = /\s$/.test(s) ? ' ' : '';
              return `<span class="title-clause">${s.trim()}</span>${trail}`;
            })
            .join('');
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
      ? '流光 Lumakey — 2D 图文详解与启动面板定制实验台'
      : 'Lumakey — 2D Overview & Interactive Launch Panel Workbench';

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
    syncGlider('#navLinks', 'navGlider', 'a.active');
  }

  document.getElementById('themeToggleBtn')?.addEventListener('click', (e) => {
    applyTheme(state.theme === 'pure-frost' ? 'prism-pulse' : 'pure-frost', e);
  });

  document.querySelectorAll('[data-set-theme]').forEach((btn) => {
    btn.addEventListener('click', (e) => applyTheme(btn.dataset.setTheme, e));
  });

  document.getElementById('langToggleBtn')?.addEventListener('click', () => {
    applyLanguage(state.lang === 'zh' ? 'en' : 'zh');
  });

  /* ------------------------------------------------------------------------
     7. Hotkey Bar, Specular Card Spotlight & Adaptive Code Studio Tabs
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

  document.querySelectorAll('.f-card, .pillar-card').forEach((card) => {
    card.addEventListener('pointermove', (e) => {
      const r = card.getBoundingClientRect();
      card.style.setProperty('--mx', `${(e.clientX - r.left).toFixed(0)}px`);
      card.style.setProperty('--my', `${(e.clientY - r.top).toFixed(0)}px`);
    });
  });

  const MCP_BIN_PATH = '/Applications/Lumakey.app/Contents/MacOS/lumakey-mcp';
  const RESIGN_URL = 'https://raw.githubusercontent.com/lengsukq/Lumakey/main/scripts/resign-local-app.sh';
  const TERMINAL_SNIPPETS = {
    mcp: {
      raw: `claude mcp add lumakey ${MCP_BIN_PATH}`,
      htmlZh: `<span class="cmd-comment"># 1. 一行命令接入 Claude Code（内置 16 项造插件与排主页工具）：</span>
<span class="cmd-prompt">$ </span>claude mcp add lumakey ${MCP_BIN_PATH}

<span class="cmd-comment">// 或写入 Cursor / Codex / Gemini CLI 的 MCP 配置文件：</span>
{
  <span class="cmd-key">"mcpServers"</span>: {
    <span class="cmd-key">"lumakey"</span>: { <span class="cmd-key">"command"</span>: <span class="cmd-str">"${MCP_BIN_PATH}"</span> }
  }
}
<span class="cmd-comment"># 2. 直接用大白话对 AI 说：“帮我配一套极简开发启动面板，再做个查端口插件”</span>`,
      htmlEn: `<span class="cmd-comment"># 1. Register built-in 16-tool MCP server with Claude Code:</span>
<span class="cmd-prompt">$ </span>claude mcp add lumakey ${MCP_BIN_PATH}

<span class="cmd-comment">// Or add to Cursor / Codex / Gemini CLI MCP config:</span>
{
  <span class="cmd-key">"mcpServers"</span>: {
    <span class="cmd-key">"lumakey"</span>: { <span class="cmd-key">"command"</span>: <span class="cmd-str">"${MCP_BIN_PATH}"</span> }
  }
}
<span class="cmd-comment"># 2. Ask AI: "Set up a Minimal Dev launch panel & build me a port inspector plugin"</span>`
    },
    plugins: {
      raw: `${REPO_BASE}/tree/main/plugin-demo`,
      htmlZh: `<span class="cmd-comment"># 方法 A（推荐普通用户）：打开「设置 → 插件中心」，粘贴下面链接一键订阅</span>
<span class="cmd-str">${REPO_BASE}/tree/main/plugin-demo</span>

<span class="cmd-comment"># 方法 B（极客终端）：克隆仓库后一键部署全部 7 款官方原生 Swift 旗舰插件</span>
<span class="cmd-prompt">$ </span>bash plugin-demo/install.sh`,
      htmlEn: `<span class="cmd-comment"># Option A (Easiest): Paste repo URL into Settings → Plugins smart bar</span>
<span class="cmd-str">${REPO_BASE}/tree/main/plugin-demo</span>

<span class="cmd-comment"># Option B (CLI): Install all 7 official native Swift plugins locally (hot-reloads live)</span>
<span class="cmd-prompt">$ </span>bash plugin-demo/install.sh`
    },
    install: {
      raw: `curl -fsSL ${RESIGN_URL} | bash`,
      htmlZh: `<span class="cmd-comment"># 升级小技巧：绑定本机自签名证书，今后替换新版 .app 免重复勾选系统权限</span>
<span class="cmd-prompt">$ </span>curl -fsSL ${RESIGN_URL} | bash

<span class="cmd-comment"># 极客从源码构建安装至 /Applications/Lumakey.app 并跑全量门禁校验</span>
<span class="cmd-prompt">$ </span>git clone ${REPO_BASE}.git && cd Lumakey
<span class="cmd-prompt">$ </span>bash scripts/install-macos.sh && bash scripts/verify-macos.sh`,
      htmlEn: `<span class="cmd-comment"># Upgrade Tip: Bind a local machine cert so future DMG updates keep macOS TCC grants</span>
<span class="cmd-prompt">$ </span>curl -fsSL ${RESIGN_URL} | bash

<span class="cmd-comment"># Build native arm64 bundle from source & run full DAG + 300-LOC + MCP gates</span>
<span class="cmd-prompt">$ </span>git clone ${REPO_BASE}.git && cd Lumakey
<span class="cmd-prompt">$ </span>bash scripts/install-macos.sh && bash scripts/verify-macos.sh`
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
      renderTerminal();
    });
  });

  document.getElementById('copyCmdBtn')?.addEventListener('click', async (e) => {
    const btn = e.currentTarget;
    const raw = (TERMINAL_SNIPPETS[state.termMode] || TERMINAL_SNIPPETS.mcp).raw;
    try {
      await navigator.clipboard.writeText(raw);
      const prev = btn.textContent;
      btn.textContent = state.lang === 'zh' ? '已复制 ✓' : 'Copied ✓';
      setTimeout(() => { btn.textContent = prev; }, 1600);
    } catch (_) {}
  });

  /* ------------------------------------------------------------------------
     8. 60fps Scroll-Driven Kinematic Engine (rAF + Sticky Theatre + DAG Lit)
     ------------------------------------------------------------------------ */
  const prefersReducedMotion = window.matchMedia('(prefers-reduced-motion: reduce)').matches;
  const scrollBeam = document.getElementById('scrollBeam');
  const heroPanel = document.getElementById('heroPanel');
  const heroCopy = document.getElementById('heroCopy');
  const orb1 = document.getElementById('orb1');
  const orb2 = document.getElementById('orb2');
  const theatreSection = document.getElementById('theatre');
  const theatreFill = document.getElementById('theatreProgressFill');
  const stepCards = Array.from(document.querySelectorAll('.step-card'));
  const stageScenes = Array.from(document.querySelectorAll('.stage-scene'));
  const mobileSceneTabs = Array.from(document.querySelectorAll('.theatre-mobile-tab'));
  const dagTiers = Array.from(document.querySelectorAll('.dag-tier'));
  const archSection = document.getElementById('architecture');
  const navLinks = Array.from(document.querySelectorAll('#navLinks a'));
  const trackedSections = ['hero', 'builder', 'theatre', 'capabilities', 'philosophy', 'architecture']
    .map((id) => document.getElementById(id))
    .filter(Boolean);

  function setActiveScene(idx) {
    if (state.activeStep === idx) return;
    state.activeStep = idx;
    stepCards.forEach((c, i) => c.classList.toggle('active', i === idx));
    stageScenes.forEach((s, i) => s.classList.toggle('active', i === idx));
    mobileSceneTabs.forEach((t, i) => t.classList.toggle('active', i === idx));
  }

  mobileSceneTabs.forEach((tab, idx) => {
    tab.addEventListener('click', () => setActiveScene(idx));
  });

  stepCards.forEach((card, idx) => {
    card.addEventListener('click', () => {
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
    });
  });

  let ticking = false;
  function updateOnScroll() {
    ticking = false;
    const scrollY = window.scrollY || window.pageYOffset;
    const docHeight = Math.max(1, document.documentElement.scrollHeight - window.innerHeight);
    const totalProgress = Math.min(1, Math.max(0, scrollY / docHeight));

    if (scrollBeam) {
      scrollBeam.style.transform = `scaleX(${totalProgress.toFixed(4)})`;
    }

    const isDesktop = window.innerWidth > 980;
    if (!prefersReducedMotion && isDesktop) {
      const heroProgress = Math.min(1, Math.max(0, scrollY / 420));
      if (heroPanel) {
        const rotX = (1 - heroProgress) * 6.5;
        const scale = 0.972 + heroProgress * 0.028;
        const transY = (1 - heroProgress) * 12;
        heroPanel.style.transform = `rotateX(${rotX.toFixed(2)}deg) translateY(${transY.toFixed(1)}px) scale(${scale.toFixed(4)})`;
      }
      if (heroCopy && scrollY < 600) {
        const copyFade = Math.max(0.28, 1 - scrollY / 580);
        heroCopy.style.opacity = copyFade.toFixed(3);
        heroCopy.style.transform = `translateY(${(scrollY * 0.11).toFixed(1)}px)`;
      }
      if (orb1 && orb2) {
        orb1.style.transform = `translate3d(${(scrollY * 0.03).toFixed(1)}px, ${(scrollY * -0.05).toFixed(1)}px, 0)`;
        orb2.style.transform = `translate3d(${(scrollY * -0.025).toFixed(1)}px, ${(scrollY * 0.04).toFixed(1)}px, 0)`;
      }
    } else {
      if (heroPanel) heroPanel.style.transform = '';
      if (heroCopy) {
        heroCopy.style.opacity = '';
        heroCopy.style.transform = '';
      }
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
    navLinks.forEach((link) => {
      link.classList.toggle('active', link.getAttribute('href') === `#${currentId}`);
    });
  }

  window.addEventListener('scroll', () => {
    if (!ticking) {
      window.requestAnimationFrame(updateOnScroll);
      ticking = true;
    }
  }, { passive: true });

  window.addEventListener('resize', () => {
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
     9. Boot Initialization
     ------------------------------------------------------------------------ */
  applyTheme(state.theme);
  applyLanguage(state.lang);
  updateOnScroll();
})();
