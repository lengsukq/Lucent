(() => {
  const state = {
    range: "365d",
    currency: "USD",
    rate: 7.25,
    exclusiveQuota: false,
    heatmapMetric: "total",
    trendMetric: "tokens",
    selectedDay: "",
    selectedProject: "",
    searchText: "",
    sourceFilter: "all",
    sortBy: "updated",
    includeSubagents: false,
    themeStyle: "auto",
    shareTheme: null,
    shareHideProjects: false,
    shareLastDataUrl: "",
    shareBusy: false,
    heatmapCols: 53,
    heatmapMonthAnchors: [],
    data: null,
    trendHoverIdx: null,
    rhythmHoverIdx: null,
    loading: false,
    lastFetchAt: 0,
    pollTimer: null,
    runChain: Promise.resolve()
  };

  const $ = (id) => document.getElementById(id);
  const el = {
    syncMeta: $("syncMeta"),
    quotaSection: $("quotaSection"),
    kpiRangeTag: $("kpiRangeTag"),
    kpiTotalVal: $("kpiTotalVal"),
    kpiTotalSub: $("kpiTotalSub"),
    kpiTurnsTag: $("kpiTurnsTag"),
    kpiNetVal: $("kpiNetVal"),
    kpiNetSub: $("kpiNetSub"),
    kpiSavedPill: $("kpiSavedPill"),
    kpiCostVal: $("kpiCostVal"),
    kpiCostSub: $("kpiCostSub"),
    kpiSpeedPill: $("kpiSpeedPill"),
    kpiCacheVal: $("kpiCacheVal"),
    kpiCacheSub: $("kpiCacheSub"),
    heatmapHeadline: $("heatmapHeadline"),
    heatmapMonths: $("heatmapMonths"),
    heatmapGrid: $("heatmapGrid"),
    streakBar: $("streakBar"),
    leg1: $("leg1"), leg2: $("leg2"), leg3: $("leg3"), leg4: $("leg4"),
    heatmapTooltip: $("heatmapTooltip"),
    dayInspector: $("dayInspector"),
    dayInspectorDate: $("dayInspectorDate"),
    dayInspectorSummary: $("dayInspectorSummary"),
    dayInspectorModels: $("dayInspectorModels"),
    dayInspectorSessions: $("dayInspectorSessions"),
    closeDayInspectorBtn: $("closeDayInspectorBtn"),
    trendTitle: $("trendTitle"),
    trendSub: $("trendSub"),
    trendCanvasWrap: $("trendCanvasWrap"),
    trendCanvas: $("trendCanvas"),
    trendTip: $("trendTip"),
    trendLegend: $("trendLegend"),
    rhythmSub: $("rhythmSub"),
    peakHourPill: $("peakHourPill"),
    rhythmCanvasWrap: $("rhythmCanvasWrap"),
    rhythmCanvas: $("rhythmCanvas"),
    rhythmTip: $("rhythmTip"),
    modelsSub: $("modelsSub"),
    modelsList: $("modelsList"),
    projectsSub: $("projectsSub"),
    projectsList: $("projectsList"),
    clearProjFilterBtn: $("clearProjFilterBtn"),
    sessionsCountMeta: $("sessionsCountMeta"),
    sessionSearchInput: $("sessionSearchInput"),
    sessionSourceSelect: $("sessionSourceSelect"),
    sessionSortSelect: $("sessionSortSelect"),
    includeSubagentsCheck: $("includeSubagentsCheck"),
    sessionsTableBody: $("sessionsTableBody"),
    pricingBtn: $("pricingBtn"),
    exportMdBtn: $("exportMdBtn"),
    shareCardBtn: $("shareCardBtn"),
    exportCsvBtn: $("exportCsvBtn"),
    refreshBtn: $("refreshBtn"),
    pricingModal: $("pricingModal"),
    closePricingModalBtn: $("closePricingModalBtn"),
    fxRateInput: $("fxRateInput"),
    saveRateBtn: $("saveRateBtn"),
    pricingRefBody: $("pricingRefBody"),
    shareModal: $("shareModal"),
    closeShareModalBtn: $("closeShareModalBtn"),
    shareStatusBadge: $("shareStatusBadge"),
    shareHideProjCheck: $("shareHideProjCheck"),
    sharePreviewImg: $("sharePreviewImg"),
    shareMetaInfo: $("shareMetaInfo"),
    saveShareImgBtn: $("saveShareImgBtn"),
    copyShareImgBtn: $("copyShareImgBtn"),
    toast: $("toast")
  };

  let toastTimer = null;
  const darkMedia = window.matchMedia?.("(prefers-color-scheme: dark)") || null;

  function showToast(msg) {
    el.toast.textContent = msg;
    el.toast.classList.add("visible");
    clearTimeout(toastTimer);
    toastTimer = setTimeout(() => el.toast.classList.remove("visible"), 2400);
  }

  function escapeHTML(str) {
    return String(str || "").replace(/[<>&"]/g, (c) => ({ "<": "&lt;", ">": "&gt;", "&": "&amp;", "\"": "&quot;" }[c]));
  }

  function runExclusive(args, query = "") {
    const next = state.runChain.then(() => window.lucent?.run ? window.lucent.run(args, query) : null);
    state.runChain = next.catch(() => null);
    return next;
  }

  async function copyText(text) {
    if (!text) return false;
    try {
      if (window.lucent?.bridge) {
        const r = await window.lucent.bridge("clipboard", "write", { text });
        if (r?.ok) return true;
      }
    } catch (_) {}
    try {
      if (navigator.clipboard?.writeText) { await navigator.clipboard.writeText(text); return true; }
    } catch (_) {}
    return false;
  }

  function fmtTokens(n, forceM = false) {
    const v = Number(n || 0);
    const abs = Math.abs(v);
    if (forceM && abs >= 100_000) return `${(v / 1e6).toFixed(abs >= 1e8 ? 1 : 2)}M`;
    if (abs >= 1e9) return `${(v / 1e9).toFixed(2)}B`;
    if (abs >= 1e6) return `${(v / 1e6).toFixed(abs >= 1e8 ? 1 : 2)}M`;
    if (abs >= 1e5) return `${Math.round(v / 1e3)}K`;
    if (abs >= 1e3) return `${(v / 1e3).toFixed(1)}K`;
    return String(Math.round(v));
  }

  function fmtMoney(usd) {
    const val = Number(usd || 0);
    if (state.currency === "CNY") {
      const cny = val * state.rate;
      return cny < 0.005 ? "¥0.00" : `¥${cny.toFixed(2)}`;
    }
    return val < 0.005 ? "$0.00" : `$${val.toFixed(2)}`;
  }

  function fmtPct(r) {
    const p = Math.max(0, Math.min(1, Number(r || 0))) * 100;
    if (p === 0) return "0%";
    if (p < 0.1) return "<0.1%";
    return `${p.toFixed(1)}%`;
  }

  function fmtSpeed(v) {
    const n = Number(v);
    if (!Number.isFinite(n) || n <= 0) return "--";
    return n >= 100 ? `${Math.round(n)} tok/s` : `${n.toFixed(1)} tok/s`;
  }

  function resolveTheme(env) {
    const st = state.themeStyle || "auto";
    if (st === "dark" || st === "light") return st;
    if (env && (env.appearance || env.theme)) {
      return (env.appearance === "dark" || env.theme === "dark" || env.theme === "prism-pulse") ? "dark" : "light";
    }
    return darkMedia?.matches ? "dark" : "light";
  }

  function applyTheme(env) {
    const t = resolveTheme(env);
    if (document.documentElement.getAttribute("data-theme") !== t) {
      document.documentElement.setAttribute("data-theme", t);
    }
    drawTrendChart();
    drawRhythmChart();
  }

  async function jumpToSession(sess) {
    if (!sess) return;
    if (sess.source === "cli") {
      const cmd = sess.resumeCommand || `agy --conversation ${sess.sessionId}`;
      const ok = await copyText(cmd);
      showToast(ok ? "已复制 CLI 续聊命令" : cmd);
      return;
    }
    try {
      const res = await runExclusive(["--focus-session", sess.sessionId || "", sess.title || ""]);
      const payload = res?.data || (res?.stdout ? JSON.parse(res.stdout) : null);
      if (payload?.message) {
        if (!payload.focused && sess.title) await copyText(sess.title);
        showToast(payload.message);
        return;
      }
    } catch (_) {}
    if (sess.title) await copyText(sess.title);
    await window.lucent?.openExternal?.("file:///Applications/Antigravity.app");
    showToast("已切回 Antigravity");
  }

  // --- Official Real-Time Quota Section ---
  function renderQuotaSection(q) {
    if (!q) { el.quotaSection.classList.add("hidden"); return; }
    el.quotaSection.classList.remove("hidden");

    if (!q.available) {
      const hs = q.hookStatus || {};
      let msgHtml = "";
      let actionHtml = "";
      if (hs.installed && hs.managedByPulse) {
        msgHtml = `<strong>官方 agy statusLine 额度同步已启用</strong> · 正在每 3 秒自动检测，在终端打开任意 <code>agy</code> 会话后即刻展示官方实时剩余额度、额度内已用金额与全额度预估。`;
        actionHtml = `<button id="recheckQuotaBtn" class="primary-btn" type="button">立即检测</button><button id="removeHookBtn" class="ghost-btn" type="button">移除钩子</button>`;
      } else if (hs.managedByOther) {
        msgHtml = `<strong>检测到已有外部 statusLine（${escapeHTML(hs.managedByOther)}）</strong> · 将自动兼容读取其配额快照，未改动你的配置。`;
        actionHtml = `<button id="recheckQuotaBtn" class="ghost-btn" type="button">立即检测</button>`;
      } else if (hs.agyInstalled) {
        msgHtml = `<strong>未检测到官方实时额度快照</strong> · 启用 Antigravity CLI 官方 <code>statusLine</code>（零侵入、保留原状态栏）即可自动显示实时额度与全额度预估。`;
        actionHtml = `<button id="setupHookBtn" class="primary-btn" type="button">一键启用官方 statusLine 同步</button>`;
      } else {
        msgHtml = `<strong>纯桌面端统计模式</strong> · 当前基于本地全部对话日志自动统计；安装并使用 <code>agy</code> CLI 后可开启官方实时额度同步。`;
      }
      el.quotaSection.innerHTML = `
        <div class="quota-banner-slim">
          <div class="quota-banner-left">
            <span class="quota-banner-dot ${hs.installed ? "ready" : ""}"></span>
            <span class="quota-banner-text">${msgHtml}</span>
          </div>
          <div class="quota-banner-actions">${actionHtml}</div>
        </div>
      `;
      $("setupHookBtn")?.addEventListener("click", handleSetupHook);
      $("recheckQuotaBtn")?.addEventListener("click", () => fetchAnalytics());
      $("removeHookBtn")?.addEventListener("click", handleRemoveHook);
      return;
    }

    const isExclusive = Boolean(q.exclusiveQuota);
    const renderWinBar = (w) => {
      if (!w) return "";
      const rem = Math.max(0, Math.min(100, Number(w.remainingPercent || 0)));
      const cls = rem <= 15 ? "crit" : (rem <= 35 ? "warn" : "good");
      const expTag = w.expired ? `<span class="pill-badge neutral">已重置</span>` : "";
      const rightMeta = isExclusive
        ? `本机额度内 ${fmtMoney(w.usedInQuotaUSD)} · ${w.fullQuotaUSD != null ? `满额预估 ~${fmtMoney(w.fullQuotaUSD)}` : "窗口消耗达 5% 后推算满额"}`
        : `本机窗口花费 ${fmtMoney(w.usedInQuotaUSD)}（缓存省 ${fmtMoney(w.usedInQuotaSavedUSD)}）`;
      return `
        <div class="quota-win-row">
          <div class="quota-win-top">
            <div class="quota-win-title">
              <span>${escapeHTML(w.label)}</span>
              ${expTag}
            </div>
            <span class="quota-win-pct ${cls} tabular">剩 ${rem.toFixed(1)}%</span>
          </div>
          <div class="progress-track">
            <div class="progress-fill ${cls === "good" ? "" : cls}" style="width:${rem.toFixed(1)}%"></div>
          </div>
          <div class="quota-win-meta tabular">
            <span>${escapeHTML(w.resetLabel)} · 本机已用 ${fmtTokens(w.usedInQuotaTotalTokens)}（净 ${fmtTokens(w.usedInQuotaNetTokens)}）</span>
            <span>${rightMeta}</span>
          </div>
        </div>
      `;
    };

    const primaryWin = q.window5h || q.windowWeekly;
    const weeklyWin = q.windowWeekly;
    const usedPrimary = primaryWin ? fmtMoney(primaryWin.usedInQuotaUSD) : "--";
    const savedPrimary = primaryWin ? fmtMoney(primaryWin.usedInQuotaSavedUSD) : "--";
    const full5h = q.window5h?.fullQuotaUSD != null ? fmtMoney(q.window5h.fullQuotaUSD) : "--";
    const full7d = weeklyWin?.fullQuotaUSD != null ? fmtMoney(weeklyWin.fullQuotaUSD) : "--";
    const fullMonth = q.monthlyFullQuotaUSD != null ? fmtMoney(q.monthlyFullQuotaUSD) : "--";
    const sampleNote = (primaryWin && primaryWin.sampleCount > 0)
      ? `基于 ${primaryWin.sampleCount} 个独享周期自动推算`
      : "消耗达 5% 时自动反推";
    const remValTxt = primaryWin?.remainingValueUSD != null ? `本轮余值约 ${fmtMoney(primaryWin.remainingValueUSD)}` : "自动跟踪本轮剩余价值";

    const othersHtml = (q.otherGroups && q.otherGroups.length)
      ? `<div class="other-groups-bar"><span>其他配额组：</span>${q.otherGroups.map((g) => {
          const ps = [];
          if (g.remaining5hPct != null) ps.push(`5h 剩 ${Math.round(g.remaining5hPct)}%`);
          if (g.remainingWeeklyPct != null) ps.push(`周剩 ${Math.round(g.remainingWeeklyPct)}%`);
          return `<span class="pill-badge neutral tabular">${escapeHTML(g.familyLabel)} · ${ps.join(" / ")}</span>`;
        }).join("")}</div>`
      : "";

    const hookAction = q.hookStatus?.managedByPulse
      ? `<button id="removeHookBtn" class="ghost-btn" type="button">移除钩子</button>`
      : "";

    const modeBadge = isExclusive
      ? `<span class="pill-badge green">本机独享</span>`
      : `<span class="pill-badge warn">账号共享</span>`;

    const modeSwitchHtml = `
      <div id="quotaModeSeg" class="seg-control compact" role="tablist" aria-label="额度归属模式">
        <button class="seg-btn ${isExclusive ? "" : "active"}" data-excl="0" type="button" title="AGY 额度多设备共享，仅统计本机消耗，不做满额推算">共享额度</button>
        <button class="seg-btn ${isExclusive ? "active" : ""}" data-excl="1" type="button" title="确认该账号仅本机独享使用，开启 5h / 7 天满额价值推算">本机独享</button>
      </div>
    `;

    const rightCardHtml = isExclusive
      ? `
        <article class="quota-card">
          <div class="card-header wrap">
            <div class="card-title-group">
              <h2 class="card-title">本机独享预估</h2>
              <span class="card-subtitle">单设备独享 · 自动推算满额</span>
            </div>
            <div class="card-actions">${modeSwitchHtml}</div>
          </div>
          <div class="val-grid">
            <div class="val-tile">
              <span class="val-tile-label">本机当前窗口已用</span>
              <span class="val-tile-num tabular">${usedPrimary}</span>
              <span class="val-tile-sub tabular">${remValTxt}</span>
            </div>
            <div class="val-tile">
              <span class="val-tile-label">5h 全额度预估 (100%)</span>
              <span class="val-tile-num tabular">${full5h}</span>
              <span class="val-tile-sub">${sampleNote}</span>
            </div>
            <div class="val-tile">
              <span class="val-tile-label">7 天全额度预估 (100%)</span>
              <span class="val-tile-num tabular">${full7d}</span>
              <span class="val-tile-sub tabular">月度折算 ≈ ${fullMonth}</span>
            </div>
            <div class="val-tile">
              <span class="val-tile-label">本机周期缓存已节省</span>
              <span class="val-tile-num green tabular">${savedPrimary}</span>
              <span class="val-tile-sub">有效延长单周期可用额度</span>
            </div>
          </div>
        </article>
      `
      : `
        <article class="quota-card">
          <div class="card-header wrap">
            <div class="card-title-group">
              <h2 class="card-title">本机额度消耗</h2>
              <span class="card-subtitle">账号共享 · 仅计本机</span>
            </div>
            <div class="card-actions">${modeSwitchHtml}</div>
          </div>
          <div class="val-grid">
            <div class="val-tile">
              <span class="val-tile-label">本机 5h 窗口已用</span>
              <span class="val-tile-num tabular">${q.window5h ? fmtMoney(q.window5h.usedInQuotaUSD) : "--"}</span>
              <span class="val-tile-sub tabular">${q.window5h ? `总 ${fmtTokens(q.window5h.usedInQuotaTotalTokens)} · 净 ${fmtTokens(q.window5h.usedInQuotaNetTokens)}` : "暂无 5h 窗口数据"}</span>
            </div>
            <div class="val-tile">
              <span class="val-tile-label">本机 7 天窗口已用</span>
              <span class="val-tile-num tabular">${weeklyWin ? fmtMoney(weeklyWin.usedInQuotaUSD) : "--"}</span>
              <span class="val-tile-sub tabular">${weeklyWin ? `总 ${fmtTokens(weeklyWin.usedInQuotaTotalTokens)} · 净 ${fmtTokens(weeklyWin.usedInQuotaNetTokens)}` : "暂无 7 天窗口数据"}</span>
            </div>
            <div class="val-tile">
              <span class="val-tile-label">本机周期缓存已节省</span>
              <span class="val-tile-num green tabular">${savedPrimary}</span>
              <span class="val-tile-sub">仅计本机 · 显著节省共享额度</span>
            </div>
            <div class="val-tile cta-tile">
              <span class="val-tile-label">全额度价值推算（未开启）</span>
              <span class="val-tile-sub">多设备共享时不推算满额；若仅本机使用可一键开启</span>
              <button id="enableExclusiveBtn" class="primary-btn val-tile-cta-btn" type="button">切换为本机独享</button>
            </div>
          </div>
        </article>
      `;

    el.quotaSection.innerHTML = `
      <div class="quota-grid">
        <article class="quota-card">
          <div class="card-header">
            <div class="card-title-group">
              <h2 class="card-title">官方实时额度</h2>
              ${q.planTier ? `<span class="pill-badge blue">${escapeHTML(q.planTier)}</span>` : ""}
              <span class="pill-badge neutral">${escapeHTML(q.activeFamilyLabel)}</span>
              ${modeBadge}
            </div>
            <div class="card-actions">
              <span class="card-subtitle tabular">同步于 ${escapeHTML(q.observedLabel)}</span>
              ${hookAction}
            </div>
          </div>
          ${renderWinBar(q.window5h)}
          ${renderWinBar(q.windowWeekly)}
          ${othersHtml}
        </article>
        ${rightCardHtml}
      </div>
    `;
    $("removeHookBtn")?.addEventListener("click", handleRemoveHook);
    $("enableExclusiveBtn")?.addEventListener("click", () => setExclusiveQuotaMode(true));
    document.querySelectorAll("#quotaModeSeg .seg-btn").forEach((btn) => {
      btn.addEventListener("click", () => {
        const nextExcl = btn.dataset.excl === "1";
        if (nextExcl !== isExclusive) setExclusiveQuotaMode(nextExcl);
      });
    });
  }

  async function setExclusiveQuotaMode(enabled) {
    state.exclusiveQuota = Boolean(enabled);
    await persistPrefs();
    showToast(state.exclusiveQuota ? "已切换为「本机独享」· 自动开启满额价值推算" : "已切换为「共享额度」· 仅显示本机实际消耗");
    await fetchAnalytics();
  }

  async function handleSetupHook() {
    const res = await runExclusive(["--setup-statusline"]);
    const payload = res?.data || (res?.stdout ? JSON.parse(res.stdout) : null);
    showToast(payload?.message || "操作已完成");
    fetchAnalytics();
  }

  async function handleRemoveHook() {
    const res = await runExclusive(["--remove-statusline"]);
    const payload = res?.data || (res?.stdout ? JSON.parse(res.stdout) : null);
    showToast(payload?.message || "已移除钩子");
    fetchAnalytics();
  }

  // --- KPI Row ---
  function renderKPIs(ov) {
    if (!ov) return;
    el.kpiRangeTag.textContent = ov.rangeLabel || state.range;
    el.kpiTotalVal.textContent = fmtTokens(ov.totalTokens);
    el.kpiTotalSub.textContent = `新输入 ${fmtTokens(ov.inputTokens)} · 缓存读 ${fmtTokens(ov.cacheReadTokens)} · 输出 ${fmtTokens(ov.outputTokens)}`;

    el.kpiTurnsTag.textContent = `${ov.turns.toLocaleString()} 轮`;
    el.kpiNetVal.textContent = fmtTokens(ov.netTokens);
    el.kpiNetSub.textContent = `${ov.sessions.toLocaleString()} 场会话 · 活跃 ${ov.activeDays} 天`;

    el.kpiCostVal.textContent = fmtMoney(ov.estimatedCostUSD);
    el.kpiSavedPill.textContent = `缓存省 ${fmtMoney(ov.estimatedSavedUSD)}`;
    el.kpiCostSub.textContent = `若无缓存原价约 ${fmtMoney(ov.estimatedUncachedUSD)}`;

    el.kpiCacheVal.textContent = fmtPct(ov.cacheHitRate);
    el.kpiSpeedPill.textContent = fmtSpeed(ov.avgTokensPerSec);
    el.kpiCacheSub.textContent = ov.avgTokensPerSec
      ? `加权平均输出速度 ${fmtSpeed(ov.avgTokensPerSec)}`
      : "基于历史会话上下文复用统计";
  }

  // --- GitHub-Style 52-Week Contribution Heatmap ---
  function expandHeatmapGrid(startDateStr, endDateStr, activeRows) {
    const byDate = new Map();
    (activeRows || []).forEach((row) => {
      if (row && row.d) byDate.set(row.d, row);
    });
    const parseYMD = (s) => {
      const m = /^(\d{4})-(\d{2})-(\d{2})$/.exec(String(s || ""));
      if (!m) return null;
      return new Date(Number(m[1]), Number(m[2]) - 1, Number(m[3]));
    };
    const fmtYMD = (dt) => `${dt.getFullYear()}-${String(dt.getMonth() + 1).padStart(2, "0")}-${String(dt.getDate()).padStart(2, "0")}`;
    const startDt = parseYMD(startDateStr);
    const endDt = parseYMD(endDateStr);
    if (!startDt || !endDt || startDt > endDt) return [];

    const out = [];
    const cur = new Date(startDt.getTime());
    while (cur <= endDt && out.length < 400) {
      const key = fmtYMD(cur);
      const hit = byDate.get(key);
      const lv = (hit && Array.isArray(hit.lv)) ? hit.lv : [0, 0, 0, 0];
      out.push({
        date: key,
        weekday: cur.getDay(),
        totalTokens: hit ? Number(hit.t || 0) : 0,
        netTokens: hit ? Number(hit.n || 0) : 0,
        inputTokens: hit ? Number(hit.i || 0) : 0,
        cacheReadTokens: hit ? Number(hit.c || 0) : 0,
        outputTokens: hit ? Number(hit.o || 0) : 0,
        turns: hit ? Number(hit.r || 0) : 0,
        sessions: hit ? Number(hit.s || 0) : 0,
        estimatedCostUSD: hit ? Number(hit.u || 0) : 0,
        estimatedSavedUSD: hit ? Number(hit.v || 0) : 0,
        cacheHitRate: hit ? Number(hit.h || 0) : 0,
        avgTokensPerSec: hit && hit.p != null ? Number(hit.p) : null,
        levelTotal: Number(lv[0] || 0),
        levelNet: Number(lv[1] || 0),
        levelCost: Number(lv[2] || 0),
        levelTurns: Number(lv[3] || 0)
      });
      cur.setDate(cur.getDate() + 1);
    }
    return out;
  }

  function renderHeatmap(startDateStr, endDateStr, activeRows, thresholds, streaks) {
    const days = expandHeatmapGrid(startDateStr, endDateStr, activeRows);
    if (!days.length) {
      el.heatmapGrid.innerHTML = `<div class="empty-state">暂无历史对话用量数据</div>`;
      return;
    }

    el.heatmapHeadline.textContent = `过去一年累计处理 ${fmtTokens(streaks.totalTokensYear)}（净用量 ${fmtTokens(streaks.netTokensYear)} · 活跃 ${streaks.activeDaysYear} 天）`;

    const avgVal = state.heatmapMetric === "net"
      ? fmtTokens(streaks.avgDailyNetTokens, true)
      : fmtTokens(streaks.avgDailyTotalTokens, true);
    const peakTxt = streaks.peakDate
      ? `${streaks.peakDate} (${fmtTokens(state.heatmapMetric === "net" ? streaks.peakNetTokens : streaks.peakTotalTokens, true)})`
      : "--";
    el.streakBar.innerHTML = `
      <span>当前连续 <strong>${streaks.currentStreakDays}</strong> 天</span>
      <span class="sep">·</span>
      <span>最长连续 <strong>${streaks.longestStreakDays}</strong> 天</span>
      <span class="sep">·</span>
      <span>活跃日均 <strong>${avgVal}</strong></span>
      <span class="sep">·</span>
      <span>峰值日 <strong>${escapeHTML(peakTxt)}</strong></span>
    `;

    // Legend threshold tooltips
    const thArr = (thresholds && thresholds[state.heatmapMetric]) || [1, 2, 3, 4];
    const fmtTh = (v) => state.heatmapMetric === "cost"
      ? fmtMoney(v)
      : (state.heatmapMetric === "turns" ? `${Math.round(v)} 轮` : fmtTokens(v, true));
    [el.leg1, el.leg2, el.leg3, el.leg4].forEach((node, i) => {
      if (node) node.title = `>= ${fmtTh(thArr[i] || 0)}`;
    });

    // Store month column anchors for dynamic responsive layout
    const monthLabels = ["1月", "2月", "3月", "4月", "5月", "6月", "7月", "8月", "9月", "10月", "11月", "12月"];
    let lastMonth = -1;
    const anchors = [];
    days.forEach((d, idx) => {
      if (d.weekday !== 0 && idx !== 0) return;
      const col = Math.floor(idx / 7);
      const m = parseInt(d.date.slice(5, 7), 10) - 1;
      if (m !== lastMonth) {
        lastMonth = m;
        anchors.push({ col, label: monthLabels[m] || "" });
      }
    });
    state.heatmapCols = Math.max(1, Math.ceil(days.length / 7));
    state.heatmapMonthAnchors = anchors;

    const levelKey = { total: "levelTotal", net: "levelNet", cost: "levelCost", turns: "levelTurns" }[state.heatmapMetric] || "levelTotal";
    const frag = document.createDocumentFragment();
    days.forEach((d) => {
      const lv = d[levelKey] || 0;
      const btn = document.createElement("button");
      btn.type = "button";
      btn.className = `heat-cell l${lv}` + (state.selectedDay === d.date ? " selected" : "");
      btn.dataset.date = d.date;
      btn.setAttribute("aria-label", `${d.date} 总用量 ${fmtTokens(d.totalTokens, true)} 净用量 ${fmtTokens(d.netTokens, true)}`);
      btn.addEventListener("pointerenter", (ev) => showHeatmapTip(d, ev));
      btn.addEventListener("pointermove", (ev) => positionFloatingTip(ev));
      btn.addEventListener("pointerleave", hideHeatmapTip);
      btn.addEventListener("focus", (ev) => {
        const r = btn.getBoundingClientRect();
        showHeatmapTip(d, { clientX: r.left + r.width / 2, clientY: r.top });
      });
      btn.addEventListener("blur", hideHeatmapTip);
      btn.addEventListener("click", () => selectHeatmapDay(d.date));
      frag.appendChild(btn);
    });
    el.heatmapGrid.innerHTML = "";
    el.heatmapGrid.appendChild(frag);
    layoutHeatmapResponsive();
  }

  function layoutHeatmapResponsive() {
    const viewport = el.heatmapGrid?.closest(".heatmap-viewport");
    const inner = el.heatmapGrid?.closest(".heatmap-inner");
    const cols = state.heatmapCols || 53;
    if (!viewport || !inner || cols <= 0) return;

    const availW = viewport.clientWidth - 30; // 4px viewport padding + 18px weekdays + 6px body gap + 2px epsilon
    if (availW <= 120) return;

    const gap = availW >= 1020 ? 4 : (availW >= 780 ? 3.5 : 3);
    const rawCell = (availW - (cols - 1) * gap) / cols;
    const cell = Math.max(10.5, Math.min(24, Math.floor(rawCell * 10) / 10));
    const radius = Math.max(2.5, Math.min(4.8, Number((cell * 0.23).toFixed(1))));

    inner.style.setProperty("--hm-cell", `${cell}px`);
    inner.style.setProperty("--hm-gap", `${gap}px`);
    inner.style.setProperty("--hm-radius", `${radius}px`);

    const pitch = cell + gap;
    let lastX = -40;
    const frags = [];
    (state.heatmapMonthAnchors || []).forEach(({ col, label }) => {
      const x = col * pitch;
      if (x - lastX >= 28) {
        lastX = x;
        frags.push(`<span class="heatmap-month-label" style="left:${x.toFixed(1)}px">${label}</span>`);
      }
    });
    el.heatmapMonths.innerHTML = frags.join("");
  }

  function showHeatmapTip(d, ev) {
    const wdNames = ["周日", "周一", "周二", "周三", "周四", "周五", "周六"];
    const wd = wdNames[d.weekday] || "";
    if (d.totalTokens === 0) {
      el.heatmapTooltip.innerHTML = `<div class="tip-head">${d.date}（${wd}）</div><div class="tip-sub">当日无用量记录</div>`;
    } else {
      const spd = d.avgTokensPerSec ? ` · 均速 ${fmtSpeed(d.avgTokensPerSec)}` : "";
      el.heatmapTooltip.innerHTML = `
        <div class="tip-head">${d.date}（${wd}） · 总 ${fmtTokens(d.totalTokens, true)}</div>
        <div>净用量 ${fmtTokens(d.netTokens, true)}（新入 ${fmtTokens(d.inputTokens)} / 输出 ${fmtTokens(d.outputTokens)} / 缓存 ${fmtTokens(d.cacheReadTokens)}）</div>
        <div class="tip-sub">估算 ${fmtMoney(d.estimatedCostUSD)}（缓存省 ${fmtMoney(d.estimatedSavedUSD)} · 命中 ${fmtPct(d.cacheHitRate)}）</div>
        <div class="tip-sub">${d.turns} 轮 · ${d.sessions} 场会话${spd} · 点击查看当日明细</div>
      `;
    }
    el.heatmapTooltip.classList.add("visible");
    positionFloatingTip(ev);
  }

  function positionFloatingTip(ev) {
    const tip = el.heatmapTooltip;
    const pad = 12;
    const w = tip.offsetWidth || 260;
    const h = tip.offsetHeight || 74;
    let x = ev.clientX + 14;
    let y = ev.clientY - h - 12;
    if (x + w + pad > window.innerWidth) x = Math.max(pad, ev.clientX - w - 14);
    if (y < pad) y = ev.clientY + 18;
    tip.style.left = `${x}px`;
    tip.style.top = `${y}px`;
  }

  function hideHeatmapTip() {
    el.heatmapTooltip.classList.remove("visible");
  }

  async function selectHeatmapDay(dateKey) {
    if (state.selectedDay === dateKey) {
      closeDayInspector();
      return;
    }
    state.selectedDay = dateKey;
    document.querySelectorAll(".heat-cell.selected").forEach((n) => n.classList.remove("selected"));
    document.querySelector(`.heat-cell[data-date="${dateKey}"]`)?.classList.add("selected");

    el.dayInspector.classList.remove("hidden");
    el.dayInspectorDate.textContent = `${dateKey} 明细`;
    el.dayInspectorSummary.textContent = "加载当日记录中…";
    el.dayInspectorModels.innerHTML = "";
    el.dayInspectorSessions.innerHTML = "";

    try {
      const res = await runExclusive(["--day-detail", dateKey]);
      const d = res?.data || (res?.stdout ? JSON.parse(res.stdout) : null);
      if (!d || state.selectedDay !== dateKey) return;
      el.dayInspectorDate.textContent = `${d.date}（${d.weekdayLabel || ""}）`;
      el.dayInspectorSummary.textContent = d.totalTokens > 0
        ? `总用量 ${fmtTokens(d.totalTokens, true)} · 净用量 ${fmtTokens(d.netTokens, true)} · 估算 ${fmtMoney(d.estimatedCostUSD)}（缓存省 ${fmtMoney(d.estimatedSavedUSD)} · 命中 ${fmtPct(d.cacheHitRate)}）· ${d.turns} 轮`
        : "当日无对话用量记录";

      el.dayInspectorModels.innerHTML = (d.models || []).map((m) =>
        `<span class="model-chip tabular">${escapeHTML(m.shortName)} · ${fmtTokens(m.totalTokens, true)} (${fmtMoney(m.estimatedCostUSD)})</span>`
      ).join("");

      if (!d.sessions || !d.sessions.length) {
        el.dayInspectorSessions.innerHTML = `<div class="empty-state">当日没有会话明细</div>`;
      } else {
        el.dayInspectorSessions.innerHTML = "";
        d.sessions.forEach((s) => {
          const row = document.createElement("div");
          row.className = "day-sess-row";
          const proj = s.projectName ? `<span class="proj-tag">${escapeHTML(s.projectName)}</span>` : "";
          const sub = s.isSubagent ? `<span class="sub-tag">子代理</span>` : "";
          row.innerHTML = `
            <div class="day-sess-left">
              ${proj}${sub}
              <span class="day-sess-title" title="${escapeHTML(s.title)}">${escapeHTML(s.title)}</span>
            </div>
            <div class="day-sess-right tabular">
              <span>${escapeHTML(s.modelShortName)}</span>
              <span>总 ${fmtTokens(s.totalTokens, true)} / 净 ${fmtTokens(s.netTokens)}</span>
              <span>${fmtMoney(s.estimatedCostUSD)}</span>
              <button class="jump-btn" type="button">${s.source === "cli" ? "复制命令" : "直达 ↗"}</button>
            </div>
          `;
          row.querySelector(".jump-btn")?.addEventListener("click", () => jumpToSession(s));
          el.dayInspectorSessions.appendChild(row);
        });
      }
    } catch (_) {
      el.dayInspectorSummary.textContent = "加载当日明细失败";
    }
  }

  function closeDayInspector() {
    state.selectedDay = "";
    document.querySelectorAll(".heat-cell.selected").forEach((n) => n.classList.remove("selected"));
    el.dayInspector.classList.add("hidden");
  }

  // --- HiDPI Canvas Charts (Trend & 24h Rhythm) ---
  function prepCanvas(canvas, wrap) {
    const rect = wrap.getBoundingClientRect();
    if (rect.width <= 10 || rect.height <= 10) return null;
    const dpr = window.devicePixelRatio || 1;
    canvas.width = Math.round(rect.width * dpr);
    canvas.height = Math.round(rect.height * dpr);
    const ctx = canvas.getContext("2d");
    ctx.scale(dpr, dpr);
    ctx.clearRect(0, 0, rect.width, rect.height);
    return { ctx, w: rect.width, h: rect.height };
  }

  function drawTrendChart() {
    const pts = state.data?.trends || [];
    const prep = prepCanvas(el.trendCanvas, el.trendCanvasWrap);
    if (!prep || !pts.length) return;
    const { ctx, w, h } = prep;
    const cs = getComputedStyle(document.documentElement);
    const cCache = cs.getPropertyValue("--green-bar").trim() || "#30B755";
    const cInput = cs.getPropertyValue("--blue").trim() || "#0071E3";
    const cOut = cs.getPropertyValue("--purple-bar").trim() || "#8250DF";
    const cGrid = cs.getPropertyValue("--border").trim() || "rgba(0,0,0,0.08)";
    const cText = cs.getPropertyValue("--label-tertiary").trim() || "#6E6E73";

    const isWeek = state.data?.trendGranularity === "week";
    el.trendTitle.textContent = isWeek ? "每周用量趋势" : "每日用量趋势";
    el.trendSub.textContent = `${pts.length} 个${isWeek ? "周" : "自然日"}柱点`;
    el.trendLegend.classList.toggle("hidden", state.trendMetric !== "tokens");

    const padL = 54, padR = 10, padT = 14, padB = 24;
    const plotW = w - padL - padR;
    const plotH = h - padT - padB;

    const getVal = (p) => {
      if (state.trendMetric === "cost") return Number(p.estimatedCostUSD || 0);
      if (state.trendMetric === "speed") return Number(p.avgTokensPerSec || 0);
      return Number(p.totalTokens || 0);
    };

    let maxVal = 0;
    pts.forEach((p) => { const v = getVal(p); if (v > maxVal) maxVal = v; });
    if (maxVal <= 0) maxVal = 1;
    maxVal *= 1.12;

    // Horizontal gridlines + Y labels
    ctx.strokeStyle = cGrid;
    ctx.fillStyle = cText;
    ctx.font = "500 10.5px -apple-system, BlinkMacSystemFont, sans-serif";
    ctx.textAlign = "right";
    ctx.textBaseline = "middle";
    for (let i = 0; i <= 3; i++) {
      const ratio = i / 3;
      const y = padT + plotH * (1 - ratio);
      ctx.beginPath(); ctx.moveTo(padL, y); ctx.lineTo(w - padR, y); ctx.stroke();
      const v = maxVal * ratio;
      const lbl = state.trendMetric === "cost" ? fmtMoney(v) : (state.trendMetric === "speed" ? `${Math.round(v)}` : fmtTokens(v));
      ctx.fillText(lbl, padL - 6, y);
    }

    const step = plotW / pts.length;
    const barW = Math.max(2.5, Math.min(24, step * 0.68));

    pts.forEach((p, idx) => {
      const cx = padL + step * (idx + 0.5);
      const bx = cx - barW / 2;
      const isHover = state.trendHoverIdx === idx;
      if (isHover) {
        ctx.fillStyle = cGrid;
        ctx.fillRect(padL + step * idx, padT, step, plotH);
      }

      if (state.trendMetric === "tokens") {
        const tot = Number(p.totalTokens || 0);
        if (tot > 0) {
          const totalH = (tot / maxVal) * plotH;
          const cacheH = (Number(p.cacheReadTokens || 0) / tot) * totalH;
          const inH = (Number(p.inputTokens || 0) / tot) * totalH;
          const outH = Math.max(0, totalH - cacheH - inH);
          let curY = padT + plotH;
          if (cacheH > 0) { ctx.fillStyle = cCache; ctx.fillRect(bx, curY - cacheH, barW, cacheH); curY -= cacheH; }
          if (inH > 0) { ctx.fillStyle = cInput; ctx.fillRect(bx, curY - inH, barW, inH); curY -= inH; }
          if (outH > 0) { ctx.fillStyle = cOut; ctx.fillRect(bx, curY - outH, barW, outH); }
        }
      } else {
        const v = getVal(p);
        if (v > 0) {
          const bh = (v / maxVal) * plotH;
          ctx.fillStyle = state.trendMetric === "cost" ? cInput : cCache;
          ctx.beginPath();
          ctx.roundRect(bx, padT + plotH - bh, barW, bh, [3, 3, 0, 0]);
          ctx.fill();
        }
      }
    });

    // X-axis sparse labels
    ctx.fillStyle = cText;
    ctx.textAlign = "center";
    ctx.textBaseline = "top";
    const maxLabels = Math.max(2, Math.floor(plotW / 58));
    const stride = Math.max(1, Math.ceil(pts.length / maxLabels));
    for (let i = 0; i < pts.length; i += stride) {
      const cx = padL + step * (i + 0.5);
      ctx.fillText(pts[i].label, cx, padT + plotH + 6);
    }

    if (state.trendHoverIdx != null && pts[state.trendHoverIdx]) {
      const p = pts[state.trendHoverIdx];
      let text = `${p.key}`;
      if (state.trendMetric === "tokens") {
        text += ` · 总 ${fmtTokens(p.totalTokens, true)} (净 ${fmtTokens(p.netTokens)} · 缓存 ${fmtTokens(p.cacheReadTokens)})`;
      } else if (state.trendMetric === "cost") {
        text += ` · 估算 ${fmtMoney(p.estimatedCostUSD)} (缓存省 ${fmtMoney(p.estimatedSavedUSD)})`;
      } else {
        text += ` · 均速 ${fmtSpeed(p.avgTokensPerSec)} · ${p.turns} 轮`;
      }
      el.trendTip.textContent = text;
      el.trendTip.classList.add("visible");
    } else {
      el.trendTip.classList.remove("visible");
    }
  }

  function drawRhythmChart() {
    const hrs = state.data?.hourlyRhythm || [];
    const prep = prepCanvas(el.rhythmCanvas, el.rhythmCanvasWrap);
    if (!prep || !hrs.length) return;
    const { ctx, w, h } = prep;
    const cs = getComputedStyle(document.documentElement);
    const cCache = cs.getPropertyValue("--green-bar").trim() || "#30B755";
    const cInput = cs.getPropertyValue("--blue").trim() || "#0071E3";
    const cGrid = cs.getPropertyValue("--border").trim() || "rgba(0,0,0,0.08)";
    const cText = cs.getPropertyValue("--label-tertiary").trim() || "#6E6E73";

    let maxTot = 0, peakH = -1;
    hrs.forEach((x) => { if (x.totalTokens > maxTot) { maxTot = x.totalTokens; peakH = x.hour; } });
    el.peakHourPill.textContent = peakH >= 0 && maxTot > 0 ? `峰值 ${String(peakH).padStart(2, "0")}:00` : "暂无活跃时段";
    if (maxTot <= 0) maxTot = 1;
    maxTot *= 1.15;

    const padL = 54, padR = 10, padT = 14, padB = 24;
    const plotW = w - padL - padR;
    const plotH = h - padT - padB;
    const step = plotW / 24;
    const barW = Math.max(4, step * 0.62);

    ctx.strokeStyle = cGrid;
    ctx.fillStyle = cText;
    ctx.font = "500 10.5px -apple-system, BlinkMacSystemFont, sans-serif";
    ctx.textAlign = "right";
    ctx.textBaseline = "middle";
    for (let i = 0; i <= 2; i++) {
      const r = i / 2;
      const y = padT + plotH * (1 - r);
      ctx.beginPath(); ctx.moveTo(padL, y); ctx.lineTo(w - padR, y); ctx.stroke();
      ctx.fillText(fmtTokens(maxTot * r), padL - 6, y);
    }

    hrs.forEach((x, idx) => {
      const cx = padL + step * (idx + 0.5);
      const bx = cx - barW / 2;
      if (state.rhythmHoverIdx === idx) {
        ctx.fillStyle = cGrid;
        ctx.fillRect(padL + step * idx, padT, step, plotH);
      }
      if (x.totalTokens > 0) {
        const totH = (x.totalTokens / maxTot) * plotH;
        const netH = (x.netTokens / maxTot) * plotH;
        ctx.fillStyle = cCache + "66";
        ctx.beginPath(); ctx.roundRect(bx, padT + plotH - totH, barW, totH, [3, 3, 0, 0]); ctx.fill();
        ctx.fillStyle = cInput;
        ctx.beginPath(); ctx.roundRect(bx, padT + plotH - Math.max(2, netH), barW, Math.max(2, netH), [2, 2, 0, 0]); ctx.fill();
      }
    });

    ctx.fillStyle = cText;
    ctx.textAlign = "center";
    ctx.textBaseline = "top";
    [0, 4, 8, 12, 16, 20, 23].forEach((hr) => {
      const cx = padL + step * (hr + 0.5);
      ctx.fillText(`${String(hr).padStart(2, "0")}h`, cx, padT + plotH + 6);
    });

    if (state.rhythmHoverIdx != null && hrs[state.rhythmHoverIdx]) {
      const x = hrs[state.rhythmHoverIdx];
      el.rhythmTip.textContent = `${String(x.hour).padStart(2, "0")}:00 · 总 ${fmtTokens(x.totalTokens, true)} · 净 ${fmtTokens(x.netTokens)} · ${x.turns} 轮`;
      el.rhythmTip.classList.add("visible");
    } else {
      el.rhythmTip.classList.remove("visible");
    }
  }

  // --- Models & Projects Breakdown ---
  function renderModels(models) {
    if (!models || !models.length) {
      el.modelsList.innerHTML = `<div class="empty-state">所选周期暂无模型记录</div>`;
      return;
    }
    el.modelsSub.textContent = `共 ${models.length} 个模型 · 按总处理量降序`;
    el.modelsList.innerHTML = models.slice(0, 8).map((m) => {
      const pct = Math.max(2, Math.min(100, (m.shareRatio || 0) * 100));
      const spd = m.avgTokensPerSec ? ` · ${fmtSpeed(m.avgTokensPerSec)}` : "";
      return `
        <div class="rank-row">
          <div class="rank-top">
            <span class="rank-name" title="${escapeHTML(m.modelName)}">${escapeHTML(m.modelName)}</span>
            <span class="rank-val tabular">${fmtTokens(m.totalTokens, true)} · ${fmtMoney(m.estimatedCostUSD)}</span>
          </div>
          <div class="rank-bar-track"><div class="rank-bar-fill" style="width:${pct.toFixed(1)}%"></div></div>
          <div class="rank-meta tabular">
            <span>净 ${fmtTokens(m.netTokens)} · 缓存 ${fmtPct(m.cacheHitRate)}${spd}</span>
            <span>${m.turns.toLocaleString()} 轮 · 省 ${fmtMoney(m.estimatedSavedUSD)}</span>
          </div>
        </div>
      `;
    }).join("");
  }

  function renderProjects(projects) {
    el.clearProjFilterBtn.classList.toggle("hidden", !state.selectedProject);
    if (!projects || !projects.length) {
      el.projectsList.innerHTML = `<div class="empty-state">所选周期暂无项目记录</div>`;
      return;
    }
    el.projectsList.innerHTML = "";
    projects.slice(0, 8).forEach((p) => {
      const pct = Math.max(2, Math.min(100, (p.shareRatio || 0) * 100));
      const isSelected = state.selectedProject === p.projectName;
      const row = document.createElement("div");
      row.className = "rank-row clickable" + (isSelected ? " selected" : "");
      row.innerHTML = `
        <div class="rank-top">
          <span class="rank-name" title="${escapeHTML(p.workspacePath || p.projectName)}">${escapeHTML(p.projectName)}</span>
          <span class="rank-val tabular">${fmtTokens(p.totalTokens, true)} · ${fmtMoney(p.estimatedCostUSD)}</span>
        </div>
        <div class="rank-bar-track"><div class="rank-bar-fill green" style="width:${pct.toFixed(1)}%"></div></div>
        <div class="rank-meta tabular">
          <span>${p.sessions} 场会话 · 净 ${fmtTokens(p.netTokens)} · 缓存 ${fmtPct(p.cacheHitRate)}</span>
          <span>${p.turns.toLocaleString()} 轮 · ${(p.shareRatio * 100).toFixed(1)}%</span>
        </div>
      `;
      row.addEventListener("click", () => {
        state.selectedProject = isSelected ? "" : p.projectName;
        renderProjects(projects);
        renderSessionsTable();
      });
      el.projectsList.appendChild(row);
    });
  }

  // --- Session Explorer Table ---
  function renderSessionsTable() {
    const all = state.data?.sessions || [];
    const kw = state.searchText.trim().toLowerCase();
    const filtered = all.filter((s) => {
      if (!state.includeSubagents && s.isSubagent) return false;
      if (state.selectedProject && (s.projectName || "未归属工作区") !== state.selectedProject) return false;
      if (state.sourceFilter === "desktop" && s.source !== "desktop") return false;
      if (state.sourceFilter === "cli" && s.source !== "cli") return false;
      if (state.sourceFilter === "running" && s.activityState !== "running") return false;
      if (kw) {
        const hay = `${s.projectName} ${s.title} ${s.modelShortName} ${s.sessionId}`.toLowerCase();
        if (!hay.includes(kw)) return false;
      }
      return true;
    });

    filtered.sort((a, b) => {
      if (state.sortBy === "total") return b.totalTokens - a.totalTokens;
      if (state.sortBy === "net") return b.netTokens - a.netTokens;
      if (state.sortBy === "cost") return b.estimatedCostUSD - a.estimatedCostUSD;
      if (state.sortBy === "turns") return b.turns - a.turns;
      return b.updatedAt - a.updatedAt;
    });

    const totalHint = Number(state.data?.totalSessionRows || all.length);
    const projHint = state.selectedProject ? ` · 项目：${state.selectedProject}` : "";
    el.sessionsCountMeta.textContent = `显示 ${filtered.length} / 共 ${totalHint} 场会话${projHint}`;

    if (!filtered.length) {
      el.sessionsTableBody.innerHTML = `<tr><td colspan="9" class="empty-state">没有匹配的会话记录</td></tr>`;
      return;
    }

    const frag = document.createDocumentFragment();
    filtered.slice(0, 120).forEach((s) => {
      const tr = document.createElement("tr");
      const dotCls = `status-dot ${s.activityState === "running" ? "running" : (s.activityState === "error" ? "error" : (s.activityState === "idle" ? "idle" : ""))}`;
      const projTag = s.projectName ? `<span class="proj-tag">${escapeHTML(s.projectName)}</span>` : "";
      const subTag = s.isSubagent ? `<span class="sub-tag">子代理</span>` : "";
      tr.innerHTML = `
        <td>
          <div class="sess-title-cell">
            <span class="${dotCls}" title="${escapeHTML(s.activityLabel)}"></span>
            ${projTag}${subTag}
            <span class="sess-name" title="${escapeHTML(s.title)}">${escapeHTML(s.title)}</span>
          </div>
        </td>
        <td>${escapeHTML(s.modelShortName)}</td>
        <td class="num tabular">${fmtTokens(s.totalTokens, true)}</td>
        <td class="num tabular">${fmtTokens(s.netTokens)}</td>
        <td class="num tabular">${fmtPct(s.cacheHitRate)}</td>
        <td class="num tabular">${fmtSpeed(s.avgTokensPerSec)}</td>
        <td class="num tabular">${fmtMoney(s.estimatedCostUSD)}</td>
        <td class="num tabular">${escapeHTML(s.updatedLabel)}</td>
        <td class="act"><button class="jump-btn" type="button">${s.source === "cli" ? "命令" : "直达↗"}</button></td>
      `;
      tr.querySelector(".jump-btn")?.addEventListener("click", () => jumpToSession(s));
      frag.appendChild(tr);
    });
    el.sessionsTableBody.innerHTML = "";
    el.sessionsTableBody.appendChild(frag);
  }

  function renderPricingRefs(refs) {
    if (!refs || !refs.length) return;
    el.pricingRefBody.innerHTML = refs.map((r) => `
      <tr>
        <td>${escapeHTML(r.name)}</td>
        <td class="num tabular">${r.contextLimitK}K</td>
        <td class="num tabular">$${r.inputPerM.toFixed(2)}</td>
        <td class="num tabular">$${r.cacheReadPerM.toFixed(3)}</td>
        <td class="num tabular">$${r.outputPerM.toFixed(2)}</td>
      </tr>
    `).join("");
  }

  function renderAll() {
    const d = state.data;
    if (!d) return;
    el.syncMeta.textContent = `本机已索引 ${d.totalArchivedFiles} 场会话 · 刷新于 ${d.refreshedAt} (${d.scanDurationMs}ms)`;
    renderQuotaSection(d.quota);
    renderKPIs(d.overview);
    renderHeatmap(d.heatmapStartDate, d.heatmapEndDate, d.heatmap, d.heatmapThresholds, d.streaks);
    drawTrendChart();
    drawRhythmChart();
    renderModels(d.models);
    renderProjects(d.projects);
    renderSessionsTable();
    renderPricingRefs(d.pricingRefs);
    if (!el.shareModal.classList.contains("hidden")) {
      refreshShareCardPreview();
    }
  }

  async function fetchAnalytics() {
    if (state.loading) return;
    state.loading = true;
    el.refreshBtn.classList.add("spinning");
    try {
      const res = await runExclusive(["--analytics", state.range]);
      let payload = null;
      if (res?.data && typeof res.data === "object") {
        payload = res.data;
      } else if (res?.stdout) {
        payload = JSON.parse(res.stdout);
      }
      if (payload?.ok) {
        state.data = payload;
        state.currency = payload.currency || state.currency;
        state.rate = Number(payload.usdToCnyRate || state.rate);
        state.exclusiveQuota = Boolean(payload.quota?.exclusiveQuota);
        state.themeStyle = payload.themeStyle || "auto";
        el.fxRateInput.value = String(state.rate);
        syncCurrencySegUI();
        applyTheme(window.lucent?.env);
        renderAll();
      } else {
        const reason = res?.error || res?.stderr || "后端未返回有效统计数据";
        el.syncMeta.textContent = `加载失败：${String(reason).slice(0, 80)}`;
        showToast(`加载失败：${String(reason).slice(0, 60)}`);
      }
    } catch (err) {
      const msg = err?.message || String(err || "解析异常");
      el.syncMeta.textContent = `加载失败：${msg.slice(0, 80)}`;
      showToast(`加载失败：${msg.slice(0, 60)}`);
    } finally {
      state.loading = false;
      state.lastFetchAt = Date.now();
      el.refreshBtn.classList.remove("spinning");
      scheduleNextPoll();
    }
  }

  function scheduleNextPoll() {
    if (state.pollTimer) clearTimeout(state.pollTimer);
    const waitingFirstQuota = Boolean(state.data?.quota?.hookStatus?.installed && !state.data?.quota?.available);
    const delayMs = waitingFirstQuota ? 3_000 : 10_000;
    state.pollTimer = setTimeout(() => {
      if (!document.hidden) fetchAnalytics();
      else scheduleNextPoll();
    }, delayMs);
  }

  function syncCurrencySegUI() {
    document.querySelectorAll("#currencySeg .seg-btn").forEach((b) => {
      b.classList.toggle("active", b.dataset.cur === state.currency);
    });
  }

  async function persistPrefs() {
    await runExclusive([
      "--set-prefs",
      JSON.stringify({
        currency: state.currency,
        usdToCnyRate: state.rate,
        exclusiveQuota: state.exclusiveQuota
      })
    ]);
  }

  async function copyMarkdownReport() {
    const d = state.data;
    if (!d) return;
    const ov = d.overview;
    const lines = [
      `# Antigravity 本机用量统计报告（${ov.rangeLabel}）`,
      `- 统计时间：${d.refreshedAt} · 币种：${state.currency} · 统计口径：仅当前设备本地日志`,
      `- **本机总处理量（含缓存）**：${fmtTokens(ov.totalTokens)}（新输入 ${fmtTokens(ov.inputTokens)} / 缓存读 ${fmtTokens(ov.cacheReadTokens)} / 输出 ${fmtTokens(ov.outputTokens)}）`,
      `- **本机净用量**：${fmtTokens(ov.netTokens)} · ${ov.turns} 轮 · ${ov.sessions} 场会话 · 活跃 ${ov.activeDays} 天`,
      `- **本机估算 API 金额**：${fmtMoney(ov.estimatedCostUSD)}（缓存命中 ${fmtPct(ov.cacheHitRate)}，累计省 ${fmtMoney(ov.estimatedSavedUSD)}）`,
      `- **年度贡献**：连续 ${d.streaks.currentStreakDays} 天（最长 ${d.streaks.longestStreakDays} 天）· 峰值日 ${d.streaks.peakDate || "--"} (${fmtTokens(d.streaks.peakTotalTokens, true)})`
    ];
    if (d.quota?.available) {
      const q = d.quota;
      const excl = Boolean(q.exclusiveQuota);
      lines.push("", excl ? "## 官方实时额度（本机独享 · 已开启满额推算）" : "## 官方实时额度（账号共享 · 仅计本机消耗）");
      if (q.window5h) {
        const fullTxt = excl && q.window5h.fullQuotaUSD != null ? ` / 满额预估 ~${fmtMoney(q.window5h.fullQuotaUSD)}` : "";
        lines.push(`- 5 小时窗口：剩余 ${q.window5h.remainingPercent.toFixed(1)}%（${q.window5h.resetLabel}）· 本机窗口已用 ${fmtMoney(q.window5h.usedInQuotaUSD)}${fullTxt}`);
      }
      if (q.windowWeekly) {
        const fullTxt = excl && q.windowWeekly.fullQuotaUSD != null ? ` / 满额预估 ~${fmtMoney(q.windowWeekly.fullQuotaUSD)}` : "";
        lines.push(`- 7 天周额度：剩余 ${q.windowWeekly.remainingPercent.toFixed(1)}%（${q.windowWeekly.resetLabel}）· 本机窗口已用 ${fmtMoney(q.windowWeekly.usedInQuotaUSD)}${fullTxt}`);
      }
    }
    if (d.models?.length) {
      lines.push("", "## 模型消耗 Top 5");
      d.models.slice(0, 5).forEach((m) => {
        lines.push(`- **${m.modelName}**：总 ${fmtTokens(m.totalTokens, true)} / 净 ${fmtTokens(m.netTokens)} · 缓存 ${fmtPct(m.cacheHitRate)} · ${fmtMoney(m.estimatedCostUSD)}`);
      });
    }
    const ok = await copyText(lines.join("\n"));
    showToast(ok ? "已复制 Markdown 统计报告到剪贴板" : "复制失败");
  }

  // --- One-Click Share Card Image Generator & Native Clipboard Copy ---
  function defaultShareTheme() {
    const cur = document.documentElement.getAttribute("data-theme");
    return cur === "light" ? "porcelain" : "obsidian";
  }

  function syncShareThemeUI() {
    document.querySelectorAll("#shareThemeSeg .seg-btn").forEach((b) => {
      b.classList.toggle("active", b.dataset.shareTheme === state.shareTheme);
    });
  }

  function refreshShareCardPreview() {
    if (!state.data || !window.AntigravityShareCard) return null;
    if (!state.shareTheme) state.shareTheme = defaultShareTheme();
    syncShareThemeUI();

    const result = window.AntigravityShareCard.renderToDataURL(state.data, {
      theme: state.shareTheme,
      currency: state.currency,
      rate: state.rate,
      heatmapMetric: state.heatmapMetric,
      hideProjects: state.shareHideProjects,
      scale: 2
    });
    if (!result) return null;
    state.shareLastDataUrl = result.dataUrl;
    el.sharePreviewImg.src = result.dataUrl;
    const approxKB = Math.round((result.dataUrl.length * 0.75) / 1024);
    el.shareMetaInfo.textContent = `${result.width} × ${result.height} px · @2x Retina PNG · 约 ${approxKB} KB`;
    return result;
  }

  async function copyCurrentShareImage() {
    if (state.shareBusy) return;
    if (!state.shareLastDataUrl) refreshShareCardPreview();
    if (!state.shareLastDataUrl) {
      showToast("数据尚未加载完成，请稍后重试");
      return;
    }
    state.shareBusy = true;
    el.copyShareImgBtn.disabled = true;
    const prevLabel = el.copyShareImgBtn.textContent;
    el.copyShareImgBtn.textContent = "正在复制…";
    try {
      const res = await runExclusive(["--copy-share-image"], state.shareLastDataUrl);
      const payload = res?.data || (res?.stdout ? JSON.parse(res.stdout) : null);
      let copied = Boolean(payload?.copied);
      if (!copied && payload?.path && window.lucent?.bridge) {
        const br = await window.lucent.bridge("clipboard", "writeImage", { imagePath: payload.path });
        copied = Boolean(br?.ok && br?.data?.written !== false);
      }
      if (copied) {
        el.shareStatusBadge.classList.remove("hidden");
        showToast("精美分享图已复制到剪贴板 ✓（可直接 ⌘V 粘贴）");
      } else {
        el.shareStatusBadge.classList.add("hidden");
        showToast(payload?.message || "复制分享图失败，请检查剪贴板权限");
      }
    } catch (err) {
      el.shareStatusBadge.classList.add("hidden");
      showToast(`生成分享图失败：${String(err?.message || err || "未知错误").slice(0, 60)}`);
    } finally {
      state.shareBusy = false;
      el.copyShareImgBtn.disabled = false;
      el.copyShareImgBtn.textContent = prevLabel;
    }
  }

  async function saveCurrentShareImage() {
    if (state.shareBusy) return;
    if (!state.shareLastDataUrl) refreshShareCardPreview();
    if (!state.shareLastDataUrl) return;
    state.shareBusy = true;
    el.saveShareImgBtn.disabled = true;
    try {
      const res = await runExclusive(["--save-share-image"], state.shareLastDataUrl);
      const payload = res?.data || (res?.stdout ? JSON.parse(res.stdout) : null);
      showToast(payload?.message || (payload?.ok ? "已保存到桌面" : "保存失败"));
    } catch (_) {
      showToast("保存图片到桌面失败");
    } finally {
      state.shareBusy = false;
      el.saveShareImgBtn.disabled = false;
    }
  }

  async function openShareCardModal(autoCopy = true) {
    if (!state.data) {
      showToast("统计数据正在加载中，请稍候");
      return;
    }
    if (!state.shareTheme) state.shareTheme = defaultShareTheme();
    el.shareHideProjCheck.checked = state.shareHideProjects;
    el.shareStatusBadge.classList.add("hidden");
    el.shareModal.classList.remove("hidden");
    refreshShareCardPreview();
    if (autoCopy) {
      await copyCurrentShareImage();
    }
  }

  async function copyDailyCSV() {
    const active = state.data?.heatmap || [];
    if (!active.length) return;
    const header = "date,total_tokens,net_tokens,input_tokens,cache_read_tokens,output_tokens,turns,sessions,cache_hit_rate,estimated_cost_usd,estimated_saved_usd";
    const rows = active.map((d) =>
      [d.d, d.t, d.n, d.i, d.c, d.o, d.r, d.s, Number(d.h || 0).toFixed(4), Number(d.u || 0).toFixed(4), Number(d.v || 0).toFixed(4)].join(",")
    );
    const ok = await copyText([header, ...rows].join("\n"));
    showToast(ok ? `已复制 ${rows.length} 天 CSV 用量明细` : "复制失败");
  }

  // --- Event Bindings ---
  document.querySelectorAll("#rangeSeg .seg-btn").forEach((btn) => {
    btn.addEventListener("click", () => {
      const next = btn.dataset.range || "365d";
      if (next === state.range) return;
      state.range = next;
      document.querySelectorAll("#rangeSeg .seg-btn").forEach((b) => b.classList.toggle("active", b === btn));
      fetchAnalytics();
    });
  });

  document.querySelectorAll("#currencySeg .seg-btn").forEach((btn) => {
    btn.addEventListener("click", async () => {
      const next = btn.dataset.cur === "CNY" ? "CNY" : "USD";
      if (next === state.currency) return;
      state.currency = next;
      syncCurrencySegUI();
      renderAll();
      await persistPrefs();
    });
  });

  document.querySelectorAll("#heatmapMetricSeg .seg-btn").forEach((btn) => {
    btn.addEventListener("click", () => {
      state.heatmapMetric = btn.dataset.metric || "total";
      document.querySelectorAll("#heatmapMetricSeg .seg-btn").forEach((b) => b.classList.toggle("active", b === btn));
      if (state.data) renderHeatmap(state.data.heatmapStartDate, state.data.heatmapEndDate, state.data.heatmap, state.data.heatmapThresholds, state.data.streaks);
    });
  });

  document.querySelectorAll("#trendMetricSeg .seg-btn").forEach((btn) => {
    btn.addEventListener("click", () => {
      state.trendMetric = btn.dataset.trend || "tokens";
      document.querySelectorAll("#trendMetricSeg .seg-btn").forEach((b) => b.classList.toggle("active", b === btn));
      drawTrendChart();
    });
  });

  el.trendCanvasWrap.addEventListener("pointermove", (ev) => {
    const pts = state.data?.trends || [];
    if (!pts.length) return;
    const rect = el.trendCanvasWrap.getBoundingClientRect();
    const rel = (ev.clientX - rect.left - 54) / Math.max(1, rect.width - 64);
    const idx = Math.floor(rel * pts.length);
    state.trendHoverIdx = (idx >= 0 && idx < pts.length) ? idx : null;
    drawTrendChart();
  });
  el.trendCanvasWrap.addEventListener("pointerleave", () => { state.trendHoverIdx = null; drawTrendChart(); });

  el.rhythmCanvasWrap.addEventListener("pointermove", (ev) => {
    const hrs = state.data?.hourlyRhythm || [];
    if (!hrs.length) return;
    const rect = el.rhythmCanvasWrap.getBoundingClientRect();
    const rel = (ev.clientX - rect.left - 54) / Math.max(1, rect.width - 64);
    const idx = Math.floor(rel * 24);
    state.rhythmHoverIdx = (idx >= 0 && idx < 24) ? idx : null;
    drawRhythmChart();
  });
  el.rhythmCanvasWrap.addEventListener("pointerleave", () => { state.rhythmHoverIdx = null; drawRhythmChart(); });

  el.closeDayInspectorBtn.addEventListener("click", closeDayInspector);
  el.clearProjFilterBtn.addEventListener("click", () => {
    state.selectedProject = "";
    if (state.data) renderProjects(state.data.projects);
    renderSessionsTable();
  });

  el.sessionSearchInput.addEventListener("input", (e) => { state.searchText = e.target.value || ""; renderSessionsTable(); });
  el.sessionSourceSelect.addEventListener("change", (e) => { state.sourceFilter = e.target.value || "all"; renderSessionsTable(); });
  el.sessionSortSelect.addEventListener("change", (e) => { state.sortBy = e.target.value || "updated"; renderSessionsTable(); });
  el.includeSubagentsCheck.addEventListener("change", (e) => { state.includeSubagents = Boolean(e.target.checked); renderSessionsTable(); });

  el.refreshBtn.addEventListener("click", () => fetchAnalytics());
  el.exportMdBtn.addEventListener("click", copyMarkdownReport);
  el.shareCardBtn.addEventListener("click", () => openShareCardModal(true));
  el.exportCsvBtn.addEventListener("click", copyDailyCSV);

  el.closeShareModalBtn.addEventListener("click", () => el.shareModal.classList.add("hidden"));
  el.shareModal.addEventListener("click", (e) => { if (e.target === el.shareModal) el.shareModal.classList.add("hidden"); });
  document.querySelectorAll("#shareThemeSeg .seg-btn").forEach((btn) => {
    btn.addEventListener("click", () => {
      state.shareTheme = btn.dataset.shareTheme || "obsidian";
      el.shareStatusBadge.classList.add("hidden");
      refreshShareCardPreview();
    });
  });
  el.shareHideProjCheck.addEventListener("change", (e) => {
    state.shareHideProjects = Boolean(e.target.checked);
    el.shareStatusBadge.classList.add("hidden");
    refreshShareCardPreview();
  });
  el.copyShareImgBtn.addEventListener("click", copyCurrentShareImage);
  el.saveShareImgBtn.addEventListener("click", saveCurrentShareImage);

  el.pricingBtn.addEventListener("click", () => el.pricingModal.classList.remove("hidden"));
  el.closePricingModalBtn.addEventListener("click", () => el.pricingModal.classList.add("hidden"));
  el.pricingModal.addEventListener("click", (e) => { if (e.target === el.pricingModal) el.pricingModal.classList.add("hidden"); });
  el.saveRateBtn.addEventListener("click", async () => {
    const val = parseFloat(el.fxRateInput.value);
    if (!Number.isFinite(val) || val < 1 || val > 20) { showToast("请输入 1 ~ 20 之间的有效汇率"); return; }
    state.rate = val;
    await persistPrefs();
    renderAll();
    el.pricingModal.classList.add("hidden");
    showToast(`汇率已更新：1 USD = ¥${val.toFixed(2)}`);
  });

  window.addEventListener("keydown", (e) => {
    if ((e.metaKey || e.ctrlKey) && e.key.toLowerCase() === "r") {
      e.preventDefault();
      fetchAnalytics();
    } else if ((e.metaKey || e.ctrlKey) && e.shiftKey && e.key.toLowerCase() === "c") {
      e.preventDefault();
      openShareCardModal(true);
    } else if (e.key === "Escape") {
      if (!el.shareModal.classList.contains("hidden")) el.shareModal.classList.add("hidden");
      else if (!el.pricingModal.classList.contains("hidden")) el.pricingModal.classList.add("hidden");
      else if (state.selectedDay) closeDayInspector();
    }
  });

  new ResizeObserver(() => {
    layoutHeatmapResponsive();
    drawTrendChart();
    drawRhythmChart();
  }).observe(document.body);
  if (window.lucent?.onEnvChanged) window.lucent.onEnvChanged((env) => applyTheme(env || window.lucent?.env));
  if (darkMedia?.addEventListener) darkMedia.addEventListener("change", () => applyTheme(window.lucent?.env));
  window.addEventListener("focus", () => { if (state.data) fetchAnalytics(); });
  document.addEventListener("visibilitychange", () => { if (!document.hidden && state.data) fetchAnalytics(); });
  document.addEventListener("pointerenter", () => {
    if (state.data && Date.now() - state.lastFetchAt >= 4_000) fetchAnalytics();
  });

  applyTheme(window.lucent?.env);
  fetchAnalytics();
})();
