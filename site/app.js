/* ==========================================================================
   Lumakey Showcase — Interactive Plugin Workbench, 880×544 Hub Simulator,
   Scroll-Scrubbed Co-Creation Tour, Pure Frost / Prism Pulse & Bilingual UI
   ========================================================================== */
(() => {
  'use strict';

  const REPO_BASE = 'https://github.com/lengsukq/Lumakey';
  const SCHEME_PREFIX = ['lumakey', '://'].join('');

  const state = {
    theme: localStorage.getItem('lumakey-showcase-theme-v2') || 'pure-frost',
    lang: localStorage.getItem('lumakey-showcase-lang-v2') || 'zh',
    preset: 'bento',
    scope: 'all',
    query: '',
    termMode: 'mcp',
    activeStep: 0,
    snifferMode: 'repo',
    sliderRatio: 0.35,
    builderProfile: 'daily',
    focusedPluginId: 'translate-hub',
    enabledPlugins: new Set(['translate-hub', 'browser-hub', 'quick-remind', 'mac-pilot'])
  };

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
      nav_launcher: '全能底座',
      nav_builder: '自由拼装',
      nav_theatre: '插件共创',
      nav_bento: '原生引擎',
      nav_philosophy: '核心思想',
      nav_arch: '工程架构',
      nav_download: '下载 DMG',
      theme_frost: '凝霜留白',
      theme_prism: '霓彩流光',
      hero_badge_1: 'Plugin v3.4 开放插件底座 · 内置 lumakey-mcp',
      hero_badge_3: '零抖动秒呼',
      hero_title_1: '精悍原生底座，',
      hero_title_2: '自由生长出你的 Lumakey。',
      hero_subtitle: '我们拒绝把所有人塞进同一套臃肿的全家桶。Lumakey 提供零依赖的 Swift 6 极速核心（全盘秒搜、截图标注、离线 OCR、平滑滚轮），并通过一等公民插件架构与内置 MCP AI 协议桥，让你按需拼装、甚至一句话定制完全属于自己的专属效率中枢——不装不占，装上即原生。',
      cta_builder: '亲手拼装你的专属 Lumakey',
      cta_download: '下载 macOS 安装包 (.dmg)',
      preset_try: '实时体验底座 + 插件联动：',
      preset_bento: '专属 Bento 面板',
      preset_translate: '流光译站 · 划词/OCR',
      preset_remind: '闪电提醒 · 10m 喝水',
      preset_browser: '三端书签 0ms 全搜',
      preset_dev: '算式换算与色板',
      scope_all: '全部',
      scope_plugins: '插件',
      scope_files: '文件',
      scope_clip: '剪贴板',
      hint_open: '执行 / 打开',
      hint_quick: '快选',
      hint_tab: '零抖动切分类',
      hint_focus: '聚焦体验框',
      scroll_hint: '向下滚动，亲手自由组装你的专属 Lumakey',
      builder_eyebrow: 'BUILD YOUR OWN LUMAKEY · 模块化自由拼装台',
      builder_title: '一千个人手里，有一千种形态的 Lumakey',
      builder_desc: '所有扩展能力默认零打扰：不启用即零内存、零后台进程；开启瞬间即可挂载为搜索框快捷按钮、独立静默热键、0ms 免前缀检索源，甚至直接注入「离线 OCR / 剪贴板 / 访达右键」上下文菜单。试试勾选或切换下方预设方案：',
      prof_minimal: '◐ 极简纯粹底座 (0 插件)',
      prof_daily: '✦ 日常高频效率套装',
      prof_dev: '⌘ 极客与远控开发流',
      prof_full: '⚡ 7 款官方旗舰 + AI 自制满配',
      cat_head_title: '插件仓库与 AI 自制扩展（点击查看详情 / 开关挂载）',
      prev_live_badge: '● 实时预览：你的专属 Lumakey 形态',
      zone_quick_title: '按需挂载至 ⌥Space 快捷按钮栏（默认关闭不挤占）',
      zone_accepts_title: '跨模块原生联动（自动注入 OCR / 剪贴板 / 双栏工作台）',
      theatre_eyebrow: 'SCROLL-DRIVEN PLUGIN ARCHITECTURE · 滚动拆解插件共创闭环',
      theatre_title: '不仅能装别人的插件，更能让 AI 十秒为你造一个',
      s1_title: '内置 lumakey-mcp：对 AI 说一句话，十秒生成专属插件',
      s1_desc: '安装包原生内置 JSON-RPC 2.0 MCP 服务，向 Claude Code、Cursor 或 Codex 暴露 plugin-v3 规范与 12 项脚手架、静态校验与沙箱实测工具，写完即刻经 FSEvents 热重载生效。',
      s2_title: '一等公民原生融合：自动配置面板、子命令静默热键与深链',
      s2_desc: '声明 plugin.json 即可自动渲染带连续滑块、加密凭据框与路径选择器的原生设置页；每个子命令均可独立录制全局热键并静默执行，还能通过原生深链直接唤起 Markdown 阅读窗与悬浮钉图。',
      s3_title: '单地址框四级智能嗅探：粘贴任意仓库链接即可订阅',
      s3_desc: 'PluginStoreSniffer 自动分辨独立插件归档包、开源仓库子目录、lumakey-registry.json 商店索引或本地文件夹；安装前强制核验 64 位 SHA-256 与防伪装能力边界，无损升级完整保留你的自定义唤醒词与凭据。',
      s4_title: '系统级 Seatbelt 沙箱 · 双轨加密保险箱 · 整机备份漫游',
      s4_desc: '所有插件在 macOS 内核级沙箱与 8 秒超时监管下隔离运行，敏感凭据经 LMKYVLT2 256-bit 随机主密钥加密存储；通过 .lumakeybackup v2 (LZFSE + WebDAV) 可将自制插件、数据与配置一键同步至任意新 Mac。',
      sc0_prompt: '“帮我做一个 Lumakey 插件：输入 pr 即可列出我名下待 Review 的代码合并请求，按回车打开，支持每 5 分钟刷新 0ms 索引，访问凭据走加密保险箱。”',
      sc0_st1: '读取内置插件协议规范与宿主可用能力清单',
      sc0_st2: '自动生成 plugin.json + icon.svg + 执行脚本',
      sc0_st3: '静态契约审计 + lumakey_run_plugin_test 沙箱实跑',
      sc0_live_t: '✦ 已热重载至 ⌥Space：PR 审查雷达 (gh-pr-radar)',
      sc0_live_d: '无需重启 Lumakey，FSEvents 毫秒级感知目录变更，立即支持 pr 关键词检索与加密凭据配置。',
      sc1_slider_t: '原生声明式配置页（点击或拖动下方滑块实时体验）',
      sc1_slider_d: '支持 text / secret (自动进 AES-GCM 保险箱) / slider / select / path / tags，修改瞬间自动持久化无需保存按钮。',
      sc1_hk_t: '子命令独立静默热键',
      sc1_hk_d: '开启 silentWhenHotKeyTriggered 后，热键触发后台瞬时执行并弹原生 HUD，全程不打断当前全屏应用。',
      sc1_dl_t: '宿主原生窗口深链',
      sc1_dl_d: '插件可直接唤起宿主纯原生 Markdown 阅读窗、无损看图窗与桌面半透明置顶钉图，无需自带 UI 框架。',
      sniff_btn_1: '试贴开源仓库子目录',
      sniff_btn_2: '试贴商店索引 JSON',
      sniff_btn_3: '试贴 .lumakeyplugin 包',
      sc2_verify_t: '防伪装双端能力核验',
      sc2_verify_d: '下载落盘前强制计算 64 位 SHA-256 摘要，并比对压缩包内 plugin.json 与商店声明的沙箱权限，越权即刻拦截回滚。',
      sc2_upg_t: '无损平滑版本升级',
      sc2_upg_d: '只读插件代码与 PluginData 数据目录严格分离，更新版本自动保留你的自定义唤醒词、子命令热键与加密凭据。',
      sc3_r1: '未声明网络与子进程作用域即由内核规则硬阻断，严禁触碰系统敏感凭据目录',
      sc3_r2: '8 项受控宿主桥接（OCR / 划词 / 音频 / 全搜），一次性 48-bit 令牌随进程退出即焚',
      sc3_r3: '双轨 256-bit 随机主密钥 AES-GCM 加密插件凭据，磁盘零明文残留',
      sc3_r4: 'LZFSE 高速压缩打包自制插件、生词本与加密配置，云盘与 NAS 一键漫游',
      bento_eyebrow: 'ZERO-DEPENDENCY NATIVE BASE · 开箱即享的五大纯原生引擎',
      bento_title: '插件未装之前，底座本身已是锋利瑞士军刀',
      bento_desc: '核心高频能力由纯 Swift 6 直接调用 ScreenCaptureKit、Vision、AVKit、Darwin Mach 与 CGEventTap 实现，零第三方包依赖，并为所有插件提供免重复造轮子的原生桥接能力：',
      hk_all: '全部原生底座',
      hk_search: '统一全搜与工具箱',
      hk_shot: '冻屏标注 · GIF · OCR',
      hk_pulse: '系统脉搏胶囊',
      hk_net: '进程流量与缓存清理',
      hk_ws: '双栏工作台 & 120Hz 滚轮',
      fc1_title: '恒定 880×544 全搜中枢 & LMKYIDX3 内存映射秒搜',
      fc1_desc: '无需前缀并发检索本地化拼音应用、全盘与外置盘文件（mmap 零拷贝 + FSEvents 实时增量）、富文本/图片剪贴板历史、算式进制换算、端口占用进程、; 动态短语与离线开发工具箱（JWT / 时间戳 / #HEX / 二维码）。',
      fc2_title: '毫秒冻屏标注 · 零 ffmpeg 区域 GIF · 离线 OCR 钉屏',
      fc2_desc: '基于 ScreenCaptureKit 实现窗口智能吸附、像素放大镜按 C 取色、9 种矢量与实时马赛克批注、灵动岛流式 GIF89a 动图录制，以及亚秒级离线 Vision 识字与半透明原位悬浮钉图——识别结果可一键流转至任意已装插件。',
      fc3_title: '系统脉搏贴边胶囊',
      fc3_desc: 'Darwin Mach / IOKit 零子进程读取 CPU P/E 核负载、等效频率 (GHz)、GPU、Swap 与整机实时瓦数功耗 (W)，支持三边贴边隐藏与默认不打扰。',
      fc4_title: '免提权流量去向 & 缓存管家',
      fc4_desc: '无需常驻提权服务即可实时透视各应用上下行速率与远端连接去向，配套分桶缓存盘点与安全废纸篓清理。',
      fc5_title: '双栏工作台 · 零 WebKit 阅读 · 120Hz 滚轮',
      fc5_desc: '按需呼出双栏磁盘工作台（只读 NTFS 安全护航）、纯 Swift Markdown 阅读窗、4K HEVC 硬解影院，以及互不干扰触控板的物理鼠标 120Hz 平滑滚轮。',
      phil_eyebrow: 'CORE PHILOSOPHY · 核心设计思想',
      phil_title: '底座极度克制，边界无限生长',
      phil_desc: '优秀的效率工具不替用户做臃肿的决定，而是提供一块零延迟、零负担的原生基石，把定义工作流的自由完整交还给你。',
      p1_title: '微内核底座 × 一等公民插件共创',
      p1_desc: '核心只保留系统级高频刚需，个性化长尾场景全部交由 Plugin v3.4 与内置 lumakey-mcp 实现。未安装或已停用的模块绝不占用一丝内存或后台轮询；一旦启用，便拥有与内置功能完全平权的 UI、热键与上下文联动。',
      p2_title: '纯原生 Swift 6，零第三方依赖',
      p2_desc: '不引入浏览器渲染栈，不拼凑跨平台兼容层。全仓零外部 SwiftPM / CocoaPods 依赖，直接驱动 Apple Silicon 硬件解码与系统图形管线，安装包小巧纯粹。',
      p3_title: '恒定几何与丝滑原生弹簧动效',
      p3_desc: '主视窗锁定 880 × 544 拒绝跳变，分类切换零位移，异步索引绝不抢焦点；同时为面板呼出收起、钉图浮现与贴边胶囊注入阻尼考究的原生弹簧微动效。',
      p4_title: '用完即焚自洁架构与默认安全沙箱',
      p4_desc: '浮窗隐藏 30 秒自动销毁视图树，全盘索引空闲 90 秒自动卸载堆页；外部脚本强制经由 Seatbelt 沙箱与 256-bit AES-GCM 密钥箱守护，兼顾自由度与系统级安全。',
      duality_title: '「凝霜留白」的纯粹瓷感，或「霓彩流光」的深邃光谱',
      duality_desc: '默认采用零色晕、高对比分层阴影的「凝霜留白 Pure Frost」工作室浅色美学；亦可一键切换至棱镜高光的「霓彩流光 Prism Pulse」深色形态。你的选择也会实时同步给所有已启用插件。',
      btn_frost: '◐ 凝霜留白 Pure Frost',
      btn_prism: '✦ 霓彩流光 Prism Pulse',
      bound_title: '清晰的产品边界：把复杂留给插件按需扩展，让底座永远轻盈',
      bound_sub: '明确「底座全力做好什么」与「坚决不往底座塞什么」，是 Lumakey 长期保持毫秒级响应的根基。',
      yes_1: '<strong>微内核快捷中枢优先：</strong>菜单栏常驻、热键秒呼即走，所有扩展能力按需开关、支持自定义图标与独立静默快捷键。',
      yes_2: '<strong>AI 友好的开放协议底座：</strong>内置 lumakey-mcp 标准服务与单框智能商店嗅探，让每个人都能低门槛创造并分享工具。',
      yes_3: '<strong>100% 专注 Apple Silicon：</strong>纯 arm64 编译与 macOS 14+ 现代框架直连，拒绝跨架构历史包袱。',
      no_1: '<strong>不做强制开启的臃肿全家桶：</strong>绝不预装无法关闭的悬浮球或常驻后台守护进程，快捷按钮与插件均默认按需挂载。',
      no_2: '<strong>不引入重型浏览器渲染内核：</strong>拒绝为看一篇 Markdown 或插件卡片而拉起数百 MB 浏览器渲染进程。',
      no_3: '<strong>不做裸奔脚本执行器与脏盘强写：</strong>拒绝无沙箱明文存储凭据，亦绝不绕过脏标记冒险强写外置 NTFS 数据盘。',
      arch_eyebrow: 'CLEAN CODE & DAG ARCHITECTURE · 工程纪律',
      arch_title: '九大单向无环模块 · 单文件严控 ≤ 300 行',
      arch_desc: '每次构建均由自动化脚本强制核验模块依赖拓扑、单文件代码行数、文档索引一致性以及真实 lumakey-mcp JSON-RPC 往返联调。',
      m_1: '内置 lumakey-mcp AI 造插件工具',
      m_2: '第三方 SwiftPM / CocoaPods 依赖',
      m_3: '单 .swift 源码文件硬性行数上限',
      m_4: '浮窗销毁 / 索引自动归还堆页窗口',
      dag_app: 'SwiftUI + AppKit 双主题前端与丝滑窗口动效矩阵',
      dag_mcp: '内置 JSON-RPC 2.0 AI 插件脚手架、审计与打包服务',
      dag_core: 'Plugin v3.4 宿主桥接 · Seatbelt 沙箱 · 智能商店嗅探 · 统一搜索 · WebDAV 备份',
      dag_search: 'LMKYIDX3 mmap 快照 · FSEvents · 批量改名预检',
      dag_media: '冻屏标注合成 · Vision OCR · hev1 硬解 · 原生 Markdown',
      dag_sys: 'Mach/IOKit 遥测 · 进程流量 · 120Hz 滚轮 · 热键冲突探测',
      dag_found: '凝霜/流光双主题模型 · 中英双语 · LMKYVLT2 AES-GCM 密钥箱 · ProcessSupervisor',
      dl_eyebrow: 'START BUILDING YOUR LUMAKEY · 立即启程',
      dl_title: '下载极速底座，组装只属于你的效率流',
      dl_desc: 'MIT 协议免费开源，支持 macOS 14.0+ 全系 M1 / M2 / M3 / M4 设备。右侧可查看 AI MCP 造插件配置、7 款官方旗舰插件安装及源码构建命令：',
      dl_btn_dmg: '下载最新 DMG 安装包',
      dl_btn_store: '浏览官方插件示例库',
      dl_btn_star: 'GitHub 点亮 Star ★',
      term_tab_mcp: 'AI MCP 造插件',
      term_tab_plugins: '安装 7 款官方插件',
      term_tab_install: '源码一键构建',
      term_copy: '复制代码',
      foot_plugin_doc: '插件与 MCP 规范',
      foot_docs: '工程文档',
      foot_contrib: '参与共建',
      placeholder_search: '搜应用、全盘文件、算式，或直接输入插件指令：tr 翻译 / rem 10m 喝水 / bh 书签...'
    },
    en: {
      brand_cn: '',
      nav_launcher: 'Micro-Core',
      nav_builder: 'Customize',
      nav_theatre: 'Plugin & MCP',
      nav_bento: 'Base Engines',
      nav_philosophy: 'Philosophy',
      nav_arch: 'Architecture',
      nav_download: 'Download DMG',
      theme_frost: 'Pure Frost',
      theme_prism: 'Prism Pulse',
      hero_badge_1: 'Plugin v3.4 Open Platform · Embedded lumakey-mcp',
      hero_badge_3: 'Zero-Jitter Chord',
      hero_title_1: 'Razor-Sharp Native Core. ',
      hero_title_2: 'Freely Shape Your Own Lumakey.',
      hero_subtitle: 'Instead of forcing everyone into a bloated all-in-one suite, Lumakey pairs a zero-dependency Swift 6 micro-core (mmap disk search, ScreenCaptureKit annotation, offline OCR, 120Hz smooth mouse wheel) with a first-class Plugin v3.4 architecture and embedded MCP server — assemble only what you love, or build a custom plugin with one AI sentence.',
      cta_builder: 'Assemble Your Own Lumakey',
      cta_download: 'Download for macOS (.dmg)',
      preset_try: 'Try Core + Plugin Workflows:',
      preset_bento: 'Custom Bento Hub',
      preset_translate: 'Translate Hub · Selection/OCR',
      preset_remind: 'Quick Remind · 10m Water',
      preset_browser: 'Browser Hub · 0ms Bookmarks',
      preset_dev: 'Math & #HEX Swatch',
      scope_all: 'All',
      scope_plugins: 'Plugins',
      scope_files: 'Files',
      scope_clip: 'Clipboard',
      hint_open: 'Run / Open',
      hint_quick: 'Quick Pick',
      hint_tab: '0-Jitter Scope',
      hint_focus: 'Focus Input',
      scroll_hint: 'Scroll down to assemble your custom Lumakey live',
      builder_eyebrow: 'BUILD YOUR OWN LUMAKEY · INTERACTIVE WORKBENCH',
      builder_title: 'A Thousand Workflows, A Thousand Custom Lumakeys',
      builder_desc: 'Every extension is opt-in by design: zero RAM and zero background polling when disabled; instant Quick Buttons, silent global hotkeys, 0ms search index, and cross-module OCR / Clipboard / Finder actions when enabled. Toggle modules or pick a preset:',
      prof_minimal: '◐ Pure Micro-Core (0 Plugins)',
      prof_daily: '✦ Daily Productivity Pack',
      prof_dev: '⌘ Developer & Remote Flow',
      prof_full: '⚡ All 7 Official + AI Custom',
      cat_head_title: 'Official Store & AI-Crafted Plugins (Click to Inspect / Toggle)',
      prev_live_badge: '● Live Preview: Your Assembled Lumakey',
      zone_quick_title: 'Mounted on ⌥Space Quick Bar (Off by Default, Opt-In)',
      zone_accepts_title: 'Cross-Module Context Hooks (OCR / Clipboard / Workspace)',
      theatre_eyebrow: 'SCROLL-DRIVEN PLUGIN ARCHITECTURE',
      theatre_title: 'Install Curated Plugins — Or Ask AI to Build Yours in 10 Seconds',
      s1_title: 'Embedded lumakey-mcp: One Sentence to a Live Native Plugin',
      s1_desc: 'Ships with a zero-dependency JSON-RPC 2.0 MCP server exposing plugin-v3 specs and 12 scaffold, validation, and sandbox test tools to Claude Code, Cursor, or Codex — hot-reloaded immediately via FSEvents.',
      s2_title: 'First-Class Citizen UI: Auto Settings, Silent Hotkeys & Deep Links',
      s2_desc: 'Declare plugin.json to get native settings forms (continuous sliders, AES-GCM secret fields, path pickers), per-subcommand silent global hotkeys, and deep links into the native Markdown reader and floating pins.',
      s3_title: 'Single-Box 4-Tier URL Sniffer: Paste Any Repo Link to Subscribe',
      s3_desc: 'PluginStoreSniffer auto-detects .lumakeyplugin archives, GitHub repo subdirectories, lumakey-registry.json stores, or local folders — enforcing 64-bit SHA-256 and anti-spoofing permission checks with lossless upgrades.',
      s4_title: 'Kernel Seatbelt Sandbox · Dual-Track Vault · Backup v2 Sync',
      s4_desc: 'Every plugin runs inside macOS Seatbelt with 8s timeouts and 256-bit AES-GCM encrypted secrets, while .lumakeybackup v2 (LZFSE + WebDAV) carries your custom plugins, data, and keys across Macs.',
      sc0_prompt: '"Build me a Lumakey plugin: typing pr lists my open review requests, Return opens the PR, refreshes a 0ms index every 5m, and stores my token encrypted."',
      sc0_st1: 'Reads built-in plugin-v3 spec & host capability audit',
      sc0_st2: 'Scaffolds plugin.json + icon.svg + entry script',
      sc0_st3: 'Static contract check + lumakey_run_plugin_test in Seatbelt',
      sc0_live_t: '✦ Hot-Reloaded into ⌥Space: PR Review Radar (gh-pr-radar)',
      sc0_live_d: 'Zero app restart needed — FSEvents picks up changes immediately with 0ms search and encrypted token UI.',
      sc1_slider_t: 'Declarative Native Settings UI (Click or Drag Slider Live)',
      sc1_slider_d: 'Supports text, secret (AES-GCM vault), slider, select, path & tags — auto-persisted immediately without Save buttons.',
      sc1_hk_t: 'Per-Subcommand Silent Hotkeys',
      sc1_hk_d: 'With silentWhenHotKeyTriggered, global hotkeys execute in background and show a crisp HUD without stealing focus.',
      sc1_dl_t: 'Native Host Window Deep Links',
      sc1_dl_d: 'Open native Markdown reader, lossless image viewer, or translucent desktop pins without bundling any UI framework.',
      sniff_btn_1: 'Paste Repo Subdirectory',
      sniff_btn_2: 'Paste Registry JSON',
      sniff_btn_3: 'Paste .lumakeyplugin File',
      sc2_verify_t: 'Anti-Spoofing Capability Audit',
      sc2_verify_d: 'Verifies 64-bit SHA-256 digest and cross-checks packaged plugin.json permissions against registry metadata before install.',
      sc2_upg_t: 'Lossless Version Upgrades',
      sc2_upg_d: 'Immutable code lives separately from PluginData, preserving your custom keywords, subcommand hotkeys, and encrypted secrets.',
      sc3_r1: 'Undeclared network/subprocess scopes blocked at kernel level; system credential stores isolated',
      sc3_r2: '8 scoped Host Bridges (OCR, selection, audio, search) via transient 0700 UDS token',
      sc3_r3: 'Dual-track 256-bit random master key AES-GCM secret storage with zero plaintext on disk',
      sc3_r4: 'LZFSE archive bundles custom plugins, vocab & encrypted settings across WebDAV / NAS',
      bento_eyebrow: 'ZERO-DEPENDENCY NATIVE BASE',
      bento_title: 'Even Before Any Plugin, the Base Core Is Razor-Sharp',
      bento_desc: 'Built 100% in Swift 6 atop ScreenCaptureKit, Vision, AVKit, Darwin Mach, and CGEventTap with zero third-party packages — doubling as the host bridge for all plugins:',
      hk_all: 'All Base Engines',
      hk_search: 'Unified Search & DevKit',
      hk_shot: 'Capture · GIF · OCR',
      hk_pulse: 'System Pulse',
      hk_net: 'Socket Traffic & Cache',
      hk_ws: 'Workspace & 120Hz Mouse',
      fc1_title: 'Constant 880×544 Hub & LMKYIDX3 mmap Disk Search',
      fc1_desc: 'Concurrently searches localized apps, full & external drives (mmap + FSEvents), rich clipboard history, math/unit conversions, port owners, ; snippets, and offline developer tools.',
      fc2_title: '0ms Freeze Annotation · ffmpeg-Free GIF · Vision OCR Pins',
      fc2_desc: 'Window-snapping capture, pixel loupe #HEX copy, 9 vector & live mosaic tools, streaming GIF89a HUD, and sub-second offline Vision OCR that hands recognized text straight to your plugins.',
      fc3_title: 'Edge-Docking System Pulse',
      fc3_desc: 'Zero-subprocess Mach/IOKit P/E-core load, effective GHz, GPU, Swap, and real-time wattage (W) with edge-snapping auto-hide.',
      fc4_title: 'Rootless Socket Traffic & Cache Cleaner',
      fc4_desc: 'Inspect live per-process bandwidth and remote endpoints without privileged daemons, paired with safe bucketed cache cleanup.',
      fc5_title: 'Dual Workspace · Zero-WebKit Reader · 120Hz Wheel',
      fc5_desc: 'On-demand dual-pane file workspace (read-only NTFS guard), pure-Swift Markdown reader, 4K HEVC cinema, and 120Hz smooth mouse scrolling.',
      phil_eyebrow: 'CORE PHILOSOPHY',
      phil_title: 'Minimalist Core, Infinite Personal Expression',
      phil_desc: 'Great tools never force bloat on everyone — they give you an ultra-fast native foundation and complete freedom to shape the rest.',
      p1_title: 'Micro-Core Base × First-Class Plugin Co-Creation',
      p1_desc: 'Keep the core lean and empower long-tail workflows via Plugin v3.4 and lumakey-mcp. Disabled modules consume zero RAM or CPU; enabled ones fuse seamlessly as native citizens.',
      p2_title: '100% Native Swift 6, Zero External Dependencies',
      p2_desc: 'No browser rendering stack, no cross-platform bloat — direct Apple Silicon hardware acceleration from top to bottom.',
      p3_title: 'Constant Geometry & Silky Native Spring Motion',
      p3_desc: 'Locked 880 × 544 frame with ID-anchored focus so async results never hijack Return, paired with tuned native spring window choreography.',
      p4_title: 'Ephemeral Memory & Seatbelt Defense-in-Depth',
      p4_desc: 'View trees teardown 30s after hide, disk indexes unmap after 90s idle, and plugins run inside kernel Seatbelt + 256-bit AES-GCM vaults.',
      duality_title: 'Porcelain Clarity in Pure Frost, or Deep Aurora in Prism Pulse',
      duality_desc: 'Defaults to crisp, high-contrast Pure Frost studio daylight; toggle live to Prism Pulse obsidian glass anytime — propagated automatically to active plugins.',
      btn_frost: '◐ Pure Frost (Light)',
      btn_prism: '✦ Prism Pulse (Dark)',
      bound_title: 'Clear Product Boundaries: Keep Complexity Opt-In, Keep the Core Light',
      bound_sub: 'Knowing what belongs in the micro-core versus opt-in plugins keeps Lumakey fast forever.',
      yes_1: '<strong>Composable Micro-Core First:</strong> Menu-bar resident hub with opt-in Quick Buttons, custom icons, and per-subcommand silent hotkeys.',
      yes_2: '<strong>AI-Native Open Protocol:</strong> Built-in lumakey-mcp server and single-URL store sniffer so anyone can build and share plugins effortlessly.',
      yes_3: '<strong>100% Dedicated to Apple Silicon:</strong> Pure arm64 binaries tuned for macOS 14+ without legacy translation layers.',
      no_1: '<strong>No Forced All-in-One Bloatware:</strong> Zero unremovable floating balls or background daemons; every widget and plugin is opt-in.',
      no_2: '<strong>No Heavy Browser Rendering Engines:</strong> Never spawns hundreds of MBs of browser processes just to render Markdown or plugin cards.',
      no_3: '<strong>No Unsandboxed Scripts or Unsafe Dirty-NTFS Writes:</strong> Enforces Seatbelt + encrypted vaults and protects dirty NTFS volumes.',
      arch_eyebrow: 'CLEAN CODE & DAG ARCHITECTURE',
      arch_title: '9 Acyclic Swift 6 Targets · Strictly ≤ 300 Lines per File',
      arch_desc: 'Continuously verified by automated scripts checking module DAG boundaries, file line caps, doc links, and live MCP roundtrips.',
      m_1: 'Built-in lumakey-mcp AI Plugin Tools',
      m_2: 'External SwiftPM / CocoaPods Dependencies',
      m_3: 'Hard Max Lines per .swift Source File',
      m_4: 'View Tree Teardown / Index Unmap Window',
      dag_app: 'SwiftUI + AppKit Dual-Theme Frontend & Spring Window Matrix',
      dag_mcp: 'Embedded JSON-RPC 2.0 AI Plugin Scaffold, Audit & Packager',
      dag_core: 'Plugin v3.4 Host · Seatbelt · Smart Store Sniffer · Ranking · WebDAV Backup',
      dag_search: 'LMKYIDX3 mmap Snapshot · FSEvents · Batch Rename Preflight',
      dag_media: 'Freeze Annotation · Vision OCR · hev1 Cinema · Native Markdown',
      dag_sys: 'Mach/IOKit Telemetry · Socket Traffic · 120Hz Wheel · HotKey Guard',
      dag_found: 'Pure Frost / Prism Pulse · Bilingual · LMKYVLT2 Vault · ProcessSupervisor',
      dl_eyebrow: 'START BUILDING YOUR LUMAKEY',
      dl_title: 'Grab the Native Core, Assemble Your Personal Flow',
      dl_desc: 'Free & open source (MIT) for macOS 14.0+ on M1 / M2 / M3 / M4 Macs. Explore AI MCP plugin creation, the 7 official plugins, or source build commands:',
      dl_btn_dmg: 'Download Latest DMG',
      dl_btn_store: 'Browse Official Plugins',
      dl_btn_star: 'Star on GitHub ★',
      term_tab_mcp: 'AI MCP Config',
      term_tab_plugins: 'Install 7 Plugins',
      term_tab_install: 'Build from Source',
      term_copy: 'Copy',
      foot_plugin_doc: 'Plugin & MCP Spec',
      foot_docs: 'Docs Index',
      foot_contrib: 'Contributing',
      placeholder_search: 'Search apps, files, math, or run plugins: tr hello / rem 10m water / bh swift...'
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
      shortZh: '跨应用划词 / 离线 OCR 截图多源翻译、本地 Ollama 与生词本',
      shortEn: 'Cross-app selection & offline OCR translation + local Ollama & vocab',
      detailZh: `零配置内置双语词典开箱即用，支持并行对比本地 Ollama 大模型译文、TTS 朗读、一键归档生词并通过 ${SCHEME_PREFIX}reader 在原生阅读窗打开或导出 Anki 词卡。`,
      detailEn: `Zero-config built-in dictionary + parallel local Ollama LLM translation, TTS speech, vocabulary notebook, native ${SCHEME_PREFIX}reader view & Anki TSV/CSV export.`,
      quickZh: '🌐 划词秒译',
      quickEn: '🌐 Translate',
      acceptsZh: ['选中文本秒译 (text)', 'OCR 截图框选翻译 (image)'],
      acceptsEn: ['Selection Text (text)', 'OCR Capture Image (image)'],
      sandbox: 'Seatbelt: network + filesystem · Bridge: selection, ocr, audio',
      cmds: [
        ['tr / fy', '⌥⇧T 静默划词译'],
        ['tr ocr', '⌥⇧O 截图识字译'],
        ['tr word', '收藏至生词本'],
        ['tr anki', '导出 Anki 词卡']
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
        ['bh <词>', '0ms 全搜三端书签'],
        ['bh hist', '检索近期浏览历史'],
        ['bh sync', '刷新浏览器快照'],
        ['↵ 回车', '原浏览器精准打开']
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
        ['rem 10m 喝水', '一句话设倒计时'],
        ['rem pomo', '启动 25m 番茄钟'],
        ['rem list', '待办提醒看板'],
        ['rem snooze', '一键贪睡顺延 10m']
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
        ['vol / mute', '精准音量与静音'],
        ['eject', '安全退外置磁盘'],
        ['new md', '访达原地新建文件'],
        ['bluetooth', '0ms 直达系统设置']
      ]
    },
    {
      id: 'screen-shield',
      icon: '🛡️',
      grad: 'linear-gradient(135deg,#0d9488,#14b8a6)',
      tagZh: '防误触锁屏',
      tagEn: 'Input Shield',
      nameZh: '状态屏 Screen Shield',
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
        ['clean', '开启清洁屏幕遮罩'],
        ['shield task', '任务运行防碰模式'],
        ['shield brb', '暂离自定义标语屏'],
        ['Hold Esc 2s', '防误触安全退出']
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
        ['lumalink qr', '弹出配对码与二维码'],
        ['lumalink net', '秒切局域网/穿透网卡'],
        ['lumalink curtain', '远控物理防窥黑屏'],
        ['lumalink hidpi', '切换 Retina 清晰度']
      ]
    },
    {
      id: 'notion-bookmarks',
      icon: '📑',
      grad: 'linear-gradient(135deg,#334155,#0f766e)',
      tagZh: 'AES-GCM 密钥箱',
      tagEn: 'Vault Secret',
      nameZh: 'Notion 书签收藏 Notion Vault',
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
        ['bm save', '静默速存剪贴板 URL'],
        ['bm <关键词>', '0ms 秒搜已存页面'],
        ['bm sync', '增量同步云端数据库'],
        ['bm tag', '默认标签自动归类']
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
      detailZh: '演示「自由构建属于你的 Lumakey」：只需在 Claude Code 或 Cursor 中描述你的私有业务需求（内部工单、合并请求、服务器探针、智能家居），AI 自动完成脚手架、沙箱实测与热重载挂载。',
      detailEn: 'Demonstrates building your own tool: describe any private workflow (internal tickets, MRs, homelab, SSH) and lumakey-mcp scaffolds & tests it automatically.',
      quickZh: '🤖 待审 PR (3)',
      quickEn: '🤖 Open PRs (3)',
      acceptsZh: ['代码仓库链接快速预审 (url)'],
      acceptsEn: ['Inspect Repo Link (url)'],
      sandbox: 'Seatbelt: scoped HTTPS · Hot-Reloaded via FSEvents',
      cmds: [
        ['pr review', '查看待我 Review 列表'],
        ['pr mine', '查看我发起的流水线'],
        ['pr refresh', '后台静默刷新索引'],
        [`${SCHEME_PREFIX}reader`, '原生预览变更摘要']
      ]
    }
  ];

  const BUILDER_PROFILES = {
    minimal: [],
    daily: ['translate-hub', 'browser-hub', 'quick-remind', 'mac-pilot'],
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
      quickMountCount.textContent = zh ? `${enabledList.length} 个快捷按钮` : `${enabledList.length} Mounted`;
    }
    if (mountedQuickPills) {
      if (enabledList.length === 0) {
        mountedQuickPills.innerHTML = `<span class="empty-mount-note">${
          zh
            ? '当前为纯粹微内核模式：快捷按钮栏完全隐藏，保持极致留白，仅运行五大原生底座引擎。'
            : 'Pure Micro-Core Mode: Quick Button bar stays hidden for maximum whitespace; only the 5 native base engines run.'
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
            ? '未挂载外部上下文动作（开启「流光译站 / 桌面中控台 / Notion」即可把动作注入 OCR 截图窗与剪贴板）。'
            : 'No external context hooks mounted (enable Translate Hub, Mac Pilot, or Notion to inject actions into OCR & Clipboard).'
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
            .map(([cmd, desc]) => `<div class="cmd-sub-chip"><code class="mono">${cmd}</code><span>${desc}</span></div>`)
            .join('')}
        </div>
      `;
    }

    if (auditSummaryBar) {
      auditSummaryBar.innerHTML = `
        <span>🛡️ ${
          zh
            ? `Seatbelt 沙箱强隔离 · 未启用插件 (${PLUGINS.length - enabledList.length} 款) 零进程零轮询`
            : `Seatbelt Enforced · ${PLUGINS.length - enabledList.length} disabled plugin(s) use 0 RAM`
        }</span>
        <span class="mono">Backup v2 (.lumakeybackup) Ready</span>
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
      if (list.length > 0 && !state.enabledPlugins.has(state.focusedPluginId)) {
        state.focusedPluginId = list[0];
      }
      syncProfileButtons();
      renderWorkbench();
      renderLauncher();
    });
  });

  /* ------------------------------------------------------------------------
     4. Interactive 880×544 Hero Launcher Simulator (Synced with Enabled Plugins!)
     ------------------------------------------------------------------------ */
  const PRESETS = {
    bento: { query: '', scope: 'all' },
    translate: { query: 'tr Ephemeral micro-core architecture', scope: 'all' },
    remind: { query: 'rem 10m 站起来喝口水休息眼睛', scope: 'all' },
    browser: { query: 'bh Apple Developer Human Interface', scope: 'plugins' },
    dev: { query: '256 * 1024 bytes to mb', scope: 'all' }
  };

  const CATALOG = [
    {
      id: 'item-translate',
      scopes: ['all', 'plugins'],
      match: ['tr', 'fy', 'translate', 'ephemeral', '翻译', '译站', 'ocr'],
      badgeBg: 'linear-gradient(135deg,#7c3aed,#a855f7)',
      badgeText: '🌐',
      titleZh: '流光译站：用完即焚的微内核架构 (Ephemeral micro-core...)',
      titleEn: 'Translate Hub: 用完即焚的微内核架构',
      subZh: 'Translate Hub · 内置词典 + 本地 Ollama 双源对照 · ⌘S 存入生词本',
      subEn: 'Translate Hub · Built-in Dict + Local Ollama LLM · ⌘S Save to Vocab',
      shortcut: '⌘1',
      lens: {
        tag: 'Plugin v3.4 · translate-hub',
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
        tag: 'Plugin v3.4 · quick-remind',
        big: 'T-10:00',
        descZh: '支持「10m 喝水」「18:30 拿快递」「明天 9:00 交周报」与 25m 番茄专注，退出软件亦由 macOS 准时提醒。',
        descEn: 'Supports relative ("10m") & calendar times plus 25m Pomodoro; persisted natively in macOS Reminders.',
        kvs: [
          ['Daemon Overhead', '0 MB (Native Reminders)'],
          ['Quick Action', '↵ Create · Snooze +10m'],
          ['Voice Alert', 'Optional macOS TTS']
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
      subZh: 'Browser Hub · 0ms 预建索引命中 · 同时检索 Edge / Chrome 多配置档',
      subEn: 'Browser Hub · 0ms Pre-Indexed · Searches Edge, Chrome Profiles & Safari',
      shortcut: '⌘1',
      lens: {
        tag: '0ms Pre-Indexed · browser-hub',
        big: '0.2ms Hit',
        descZh: '无锁读取 Safari、Chrome 与 Edge 书签及历史记录注入主搜索流，无需输入前缀也能直接秒搜网页收藏。',
        descEn: 'Lock-free SQLite snapshot across Safari, Chrome & Edge injected into 0ms unified search.',
        kvs: [
          ['Sandbox Scope', 'Read-Only Browser DBs'],
          ['Open Behavior', 'Source Browser Direct'],
          ['Index Refresh', 'Background Incremental']
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
        descZh: '底座原生内置数学表达式、存储进制换算、#HEX 对比度色板、UUID 与离线二维码生成。',
        descEn: 'Zero-plugin native math, storage units, #HEX contrast swatches, UUIDs & offline QR generator.',
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
      match: ['swift', 'lmky', 'file', 'plugin', '文件'],
      badgeBg: 'linear-gradient(135deg,#ea580c,#db2777)',
      badgeText: 'S',
      titleZh: 'PluginHostService.swift',
      titleEn: 'PluginHostService.swift',
      subZh: 'Sources/LumakeyCore · LMKYIDX3 mmap 零拷贝全盘秒搜命中',
      subEn: 'Sources/LumakeyCore · Instant LMKYIDX3 mmap full-disk hit',
      shortcut: '⌘2',
      lens: {
        tag: 'LMKYIDX3 · Zero-WebKit Reader',
        big: '≤ 300 Lines',
        descZh: '按 ↵ 在纯原生代码阅读窗打开（0 MB WebKit 开销），或按 ⌘↵ 在访达中定位。',
        descEn: 'Press ↵ for pure-Swift code reader (0 MB WebKit), or ⌘↵ to reveal in Finder.',
        kvs: [
          ['Index Format', 'LMKYIDX3 mmap + SHA-256'],
          ['External Drives', 'Supported + FSEvents'],
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
      titleZh: 'swift test --arch arm64',
      titleEn: 'swift test --arch arm64',
      subZh: '剪贴板历史 · 刚刚复制 · 可一键流转至已启用插件处理',
      subEn: 'Clipboard History · Copied just now · Hand off to any active plugin',
      shortcut: '⌘3',
      lens: {
        tag: 'ClipboardMonitor + accepts[]',
        big: 'SHA-256 Pinned',
        descZh: '剪贴板条目不仅支持置顶收藏与加密备份，还能直接交给声明了 accepts: ["text"] 的插件一键处理。',
        descEn: 'Pinned items sync via .lumakeybackup and route directly into plugins declaring accepts: ["text"].',
        kvs: [
          ['Media Support', 'Text · Image · File · GIF'],
          ['Plugin Handoff', '1-Key Context Action'],
          ['Sync', 'LZFSE + WebDAV Backup']
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

    const tiles = [
      { bg: 'linear-gradient(135deg,#0066dc,#2563eb)', icon: '🔍', t: zh ? '全盘秒搜' : 'Disk Search', s: 'LMKYIDX3 mmap', scope: 'files' },
      { bg: 'linear-gradient(135deg,#7c3aed,#a855f7)', icon: '🌐', t: zh ? '流光译站' : 'Translate Hub', s: 'Plugin · OCR/划词', preset: 'translate' },
      { bg: 'linear-gradient(135deg,#ea580c,#f59e0b)', icon: '⏰', t: zh ? '闪电提醒' : 'Quick Remind', s: 'Plugin · 10m 喝水', preset: 'remind' },
      { bg: 'linear-gradient(135deg,#db2777,#e11d48)', icon: '✂️', t: zh ? '冻屏与 GIF' : 'Capture & GIF', s: '⌥A / ⌥G / ⌥O', jump: '#capabilities' },
      { bg: 'linear-gradient(135deg,#4338ca,#6366f1)', icon: '🧭', t: zh ? '三端书签' : 'Browser Hub', s: 'Plugin · 0ms 全搜', preset: 'browser' },
      { bg: 'linear-gradient(135deg,#059669,#0d9488)', icon: '🧩', t: zh ? '自由拼装台' : 'Plugin Builder', s: `${enabledList.length} Active`, jump: '#builder' }
    ];

    const quickBarHtml = enabledList.length > 0
      ? `
        <div class="quick-btn-bar-mock">
          <span class="quick-btn-label">${zh ? '已挂载快捷按钮：' : 'Quick Bar:'}</span>
          ${enabledList.slice(0, 4).map((p) => `
            <span class="quick-btn-pill" data-jump-builder="${p.id}">${zh ? p.quickZh : p.quickEn}</span>
          `).join('')}
        </div>
      `
      : `
        <div class="quick-btn-bar-mock">
          <span class="quick-btn-label">${zh ? '纯净微内核态：未挂载任何快捷按钮（可在下方拼装台按需开启）' : 'Pure Micro-Core: Quick Bar hidden (enable plugins below)'}</span>
        </div>
      `;

    leftPane.innerHTML = `
      <div class="bento-mini-grid">
        ${tiles.map((tile, idx) => `
          <div class="bento-tile" data-tile-idx="${idx}">
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
        <span>${zh ? '智能常驻应用坞 (log₂ 活跃时长加权)' : 'Smart App Dock (log₂ Active Weighted)'}</span>
        <span class="mono">⌘1..4</span>
      </div>
      <div class="dock-mini-row">
        <div class="dock-app-pill"><span class="dock-app-dot" style="background:linear-gradient(135deg,#0284c7,#2563eb)"></span>Xcode</div>
        <div class="dock-app-pill"><span class="dock-app-dot" style="background:linear-gradient(135deg,#059669,#10b981)"></span>Ghostty</div>
        <div class="dock-app-pill"><span class="dock-app-dot" style="background:linear-gradient(135deg,#7c3aed,#4338ca)"></span>Cursor</div>
        <div class="dock-app-pill"><span class="dock-app-dot" style="background:linear-gradient(135deg,#ea580c,#ef4444)"></span>Safari</div>
      </div>
    `;

    rightLens.innerHTML = `
      <div class="lens-card">
        <div>
          <div class="lens-header">
            <span class="accent-pill">${zh ? '底座 + 插件一等公民' : 'Core + Native Plugins'}</span>
            <span class="mono" style="font-size:11px;color:var(--text-tertiary)">⌥Space</span>
          </div>
          <div class="lens-big-value gradient-text">${
            zh ? `已挂载 ${enabledList.length} 款扩展` : `${enabledList.length} Plugins Active`
          }</div>
          <p class="lens-desc">
            ${zh
              ? '左侧快捷按钮栏与下方「自由拼装台」实时双向联动！你可以保持 0 插件极简底座，也可将官方插件或 AI 生成的私有工具无缝融为一等公民。'
              : 'Synced live with the Customize Workbench below! Run with 0 plugins for pure minimalism, or fuse curated & AI-generated tools seamlessly.'}
          </p>
        </div>
        <div class="lens-kv-list">
          <div class="lens-kv"><span>${zh ? '当前视觉主题' : 'Active Theme'}</span><span>${
            state.theme === 'pure-frost' ? (zh ? '凝霜留白 Pure Frost' : 'Pure Frost') : (zh ? '霓彩流光 Prism Pulse' : 'Prism Pulse')
          }</span></div>
          <div class="lens-kv"><span>${zh ? '视窗恒定尺寸' : 'Constant Frame'}</span><span class="mono">880 × 544 (0-Jitter)</span></div>
          <div class="lens-kv"><span>${zh ? 'AI 造插件协议' : 'AI Plugin Bridge'}</span><span class="mono">lumakey-mcp (12 Tools)</span></div>
        </div>
      </div>
    `;

    leftPane.querySelectorAll('.bento-tile').forEach((el, idx) => {
      el.addEventListener('click', () => {
        const t = tiles[idx];
        if (t.preset) applyPreset(t.preset);
        else if (t.scope) {
          state.scope = t.scope;
          syncScopeButtons();
          renderLauncher();
        } else if (t.jump) {
          document.querySelector(t.jump)?.scrollIntoView({ behavior: 'smooth' });
        }
      });
    });

    leftPane.querySelectorAll('[data-jump-builder]').forEach((pill) => {
      pill.addEventListener('click', () => {
        state.focusedPluginId = pill.getAttribute('data-jump-builder');
        renderWorkbench();
        document.getElementById('builder')?.scrollIntoView({ behavior: 'smooth' });
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
          <div class="lens-big-value gradient-text mono">${l.big}</div>
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
    const activeCount = state.enabledPlugins.size;

    if (!q && state.scope === 'all') {
      if (engineStatus) {
        engineStatus.textContent = `Core + ${activeCount} Active Plugin(s) · 0ms Ready`;
      }
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
          titleZh: `并发检索底座与已启用插件：“${state.query}”`,
          titleEn: `Unified Core + Plugin Match: "${state.query}"`,
          subZh: '同时扫描本地应用 · LMKYIDX3 全盘文件 · 剪贴板 · 0ms 插件索引',
          subEn: 'Scans Apps · LMKYIDX3 Disk · Clipboard · 0ms Plugin Index',
          shortcut: '⌘1',
          lens: {
            tag: 'LauncherEngine · 0.3ms',
            big: state.query.slice(0, 14),
            descZh: '如果现有插件不满足这个指令，只需对 Claude / Cursor 说一句话，lumakey-mcp 就能在 10 秒内为你生成对应插件！',
            descEn: 'Need a custom command for this? Ask Claude or Cursor via lumakey-mcp to scaffold and hot-reload it in 10 seconds.',
            kvs: [
              ['Scope', state.scope.toUpperCase()],
              ['Frame Lock', '880 × 544 Constant'],
              ['Selection Guard', 'ID-Anchored (Zero Jump)']
            ]
          }
        }
      ];
    }

    if (engineStatus) {
      engineStatus.textContent = `Matched ${matches.length} item(s) · 0.3ms`;
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
      row.addEventListener('mouseenter', () => {
        leftPane.querySelectorAll('.result-row').forEach((r) => r.classList.remove('selected'));
        row.classList.add('selected');
        const item = matches[Number(row.dataset.idx)];
        if (item) renderLensForItem(item);
      });
    });
  }

  function syncScopeButtons() {
    document.querySelectorAll('.scope-pill').forEach((btn) => {
      btn.classList.toggle('active', btn.dataset.scope === state.scope);
    });
  }

  function applyPreset(presetKey) {
    const p = PRESETS[presetKey];
    if (!p) return;
    state.preset = presetKey;
    state.query = p.query;
    state.scope = p.scope;
    if (launcherInput) launcherInput.value = p.query;
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
     5. Interactive Stage Widgets inside #theatre (Slider + Smart URL Sniffer)
     ------------------------------------------------------------------------ */
  const sliderTrack = document.getElementById('demoSliderTrack');
  const sliderFill = document.getElementById('demoSliderFill');
  const sliderKnob = document.getElementById('demoSliderKnob');
  const sliderBadge = document.getElementById('sliderValueBadge');

  function updateSlider(ratio) {
    const clamped = Math.min(1, Math.max(0, ratio));
    state.sliderRatio = clamped;
    const pct = `${(clamped * 100).toFixed(0)}%`;
    if (sliderFill) sliderFill.style.width = pct;
    if (sliderKnob) sliderKnob.style.left = pct;
    if (sliderBadge) sliderBadge.textContent = `temperature: ${clamped.toFixed(2)}`;
  }

  if (sliderTrack) {
    let draggingSlider = false;
    const setFromEvent = (e) => {
      const r = sliderTrack.getBoundingClientRect();
      if (r.width <= 0) return;
      updateSlider((e.clientX - r.left) / r.width);
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
    updateSlider(state.sliderRatio);
  }

  const SNIFFER_MODES = {
    repo: {
      url: `${REPO_BASE}/tree/main/plugin-demo`,
      kind: 'Store Registry (7 Plugins)',
      descZh: '自动识别开源仓库子目录并定位 lumakey-registry.json，一键订阅全部 7 款官方插件并校验 SHA-256。',
      descEn: 'Auto-resolves repository subdirectory to lumakey-registry.json, subscribing all 7 curated plugins with SHA-256 verification.'
    },
    registry: {
      url: `${REPO_BASE}/blob/main/plugin-demo/lumakey-registry.json`,
      kind: 'JSON Store Manifest',
      descZh: '直接解析商店索引清单 JSON，支持增量检查版本更新与防伪装沙箱能力比对。',
      descEn: 'Parses store manifest JSON directly with one-click version updates and capability boundary checks.'
    },
    archive: {
      url: 'plugin-demo/dist/translate-hub-1.0.0.zip',
      kind: 'Direct Plugin Package',
      descZh: '无需搭建商店，直接嗅探独立 .lumakeyplugin / .zip 归档包并在展示所需沙箱权限后安全安装。',
      descEn: 'Installs standalone .lumakeyplugin / .zip packages directly after previewing requested Seatbelt permissions.'
    }
  };

  function renderSnifferDemo() {
    const mode = SNIFFER_MODES[state.snifferMode] || SNIFFER_MODES.repo;
    const urlEl = document.getElementById('snifferUrlText');
    const kindEl = document.getElementById('snifferDetectedKind');
    const descEl = document.getElementById('snifferDetailDesc');
    if (urlEl) urlEl.textContent = mode.url;
    if (kindEl) kindEl.textContent = mode.kind;
    if (descEl) descEl.textContent = state.lang === 'zh' ? mode.descZh : mode.descEn;
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

  /* ------------------------------------------------------------------------
     6. Dual-Theme (Default Pure Frost!) & Bilingual Live Switching
     ------------------------------------------------------------------------ */
  function applyTheme(themeId) {
    state.theme = themeId;
    document.documentElement.setAttribute('data-theme', themeId);
    localStorage.setItem('lumakey-showcase-theme-v2', themeId);

    const label = document.getElementById('themeToggleLabel');
    const dict = I18N[state.lang];
    if (label) {
      label.textContent = themeId === 'pure-frost' ? dict.theme_frost : dict.theme_prism;
    }

    document.querySelectorAll('[data-set-theme]').forEach((btn) => {
      btn.classList.toggle('active', btn.dataset.setTheme === themeId);
    });

    renderLauncher();
  }

  function applyLanguage(lang) {
    state.lang = lang;
    document.documentElement.lang = lang === 'zh' ? 'zh-CN' : 'en';
    localStorage.setItem('lumakey-showcase-lang-v2', lang);

    const dict = I18N[lang];
    document.querySelectorAll('[data-i18n]').forEach((el) => {
      const key = el.getAttribute('data-i18n');
      if (dict[key] !== undefined) {
        if (dict[key].includes('<strong>')) {
          el.innerHTML = dict[key];
        } else {
          el.textContent = dict[key];
        }
      }
    });

    const langBtn = document.getElementById('langToggleBtn');
    if (langBtn) langBtn.textContent = lang === 'zh' ? 'EN' : '中文';

    const themeLabel = document.getElementById('themeToggleLabel');
    if (themeLabel) {
      themeLabel.textContent = state.theme === 'pure-frost' ? dict.theme_frost : dict.theme_prism;
    }

    if (launcherInput) launcherInput.placeholder = dict.placeholder_search;
    renderWorkbench();
    renderLauncher();
    renderSnifferDemo();
    renderTerminal();
  }

  document.getElementById('themeToggleBtn')?.addEventListener('click', () => {
    applyTheme(state.theme === 'pure-frost' ? 'prism-pulse' : 'pure-frost');
  });

  document.querySelectorAll('[data-set-theme]').forEach((btn) => {
    btn.addEventListener('click', () => applyTheme(btn.dataset.setTheme));
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
  const TERMINAL_SNIPPETS = {
    mcp: {
      raw: `{
  "mcpServers": {
    "lumakey": {
      "command": "${MCP_BIN_PATH}"
    }
  }
}`,
      htmlZh: `<span class="cmd-comment">// 接入 Claude Code / Cursor / Codex，对 AI 说一句话即可造插件：</span>
{
  <span class="cmd-key">"mcpServers"</span>: {
    <span class="cmd-key">"lumakey"</span>: {
      <span class="cmd-key">"command"</span>: <span class="cmd-str">"${MCP_BIN_PATH}"</span>
    }
  }
}
<span class="cmd-comment">// 或一行命令注册至 Claude Code：</span>
<span class="cmd-prompt">$ </span>claude mcp add lumakey ${MCP_BIN_PATH}`,
      htmlEn: `<span class="cmd-comment">// Connect Claude Code / Cursor / Codex to build plugins in 1 sentence:</span>
{
  <span class="cmd-key">"mcpServers"</span>: {
    <span class="cmd-key">"lumakey"</span>: {
      <span class="cmd-key">"command"</span>: <span class="cmd-str">"${MCP_BIN_PATH}"</span>
    }
  }
}
<span class="cmd-comment">// Or register with Claude Code in one command:</span>
<span class="cmd-prompt">$ </span>claude mcp add lumakey ${MCP_BIN_PATH}`
    },
    plugins: {
      raw: `git clone ${REPO_BASE}.git
cd Lumakey
bash plugin-demo/install-demo-plugins.sh`,
      htmlZh: `<span class="cmd-comment"># 方法 A：在「设置 → 插件」单地址框直接粘贴仓库链接自动订阅</span>
<span class="cmd-str">${REPO_BASE}/tree/main/plugin-demo</span>

<span class="cmd-comment"># 方法 B：终端一键部署全部 7 款官方旗舰插件（热重载立即生效）</span>
<span class="cmd-prompt">$ </span>bash plugin-demo/install-demo-plugins.sh`,
      htmlEn: `<span class="cmd-comment"># Option A: Paste repo URL into Settings → Plugins smart bar</span>
<span class="cmd-str">${REPO_BASE}/tree/main/plugin-demo</span>

<span class="cmd-comment"># Option B: Install all 7 official flagship plugins locally</span>
<span class="cmd-prompt">$ </span>bash plugin-demo/install-demo-plugins.sh`
    },
    install: {
      raw: `git clone ${REPO_BASE}.git
cd Lumakey
bash scripts/install-macos.sh`,
      htmlZh: `<span class="cmd-comment"># 克隆源码并一键构建安装至 /Applications/Lumakey.app</span>
<span class="cmd-prompt">$ </span>git clone ${REPO_BASE}.git
<span class="cmd-prompt">$ </span>cd Lumakey
<span class="cmd-prompt">$ </span>bash scripts/install-macos.sh

<span class="cmd-comment"># 运行全量架构门禁 + 单测 + lumakey-mcp 往返校验</span>
<span class="cmd-prompt">$ </span>bash scripts/verify-macos.sh`,
      htmlEn: `<span class="cmd-comment"># Clone & build native arm64 bundle to /Applications/Lumakey.app</span>
<span class="cmd-prompt">$ </span>git clone ${REPO_BASE}.git
<span class="cmd-prompt">$ </span>cd Lumakey
<span class="cmd-prompt">$ </span>bash scripts/install-macos.sh

<span class="cmd-comment"># Run DAG check + Swift 6 tests + live lumakey-mcp audit</span>
<span class="cmd-prompt">$ </span>bash scripts/verify-macos.sh`
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
  }

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

    if (!prefersReducedMotion) {
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
    }, { threshold: 0.12, rootMargin: '0px 0px -40px 0px' });
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
