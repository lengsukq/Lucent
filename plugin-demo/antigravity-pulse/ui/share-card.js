(() => {
  const FONT = `-apple-system, BlinkMacSystemFont, "SF Pro Display", "SF Pro Text", "PingFang SC", sans-serif`;

  const THEMES = {
    obsidian: {
      name: "曜石暗夜",
      dark: true,
      bgStops: ["#0A0D13", "#101520", "#0C1018"],
      bloomA: "rgba(56, 139, 253, 0.16)",
      bloomB: "rgba(48, 209, 88, 0.11)",
      bloomC: "rgba(139, 92, 246, 0.09)",
      dotColor: "rgba(255, 255, 255, 0.035)",
      frameStroke: "rgba(255, 255, 255, 0.075)",
      cardBg: "rgba(255, 255, 255, 0.042)",
      cardBgAlt: "rgba(255, 255, 255, 0.032)",
      cardStroke: "rgba(255, 255, 255, 0.095)",
      cardSpecular: "rgba(255, 255, 255, 0.22)",
      cardShadow: "rgba(0, 0, 0, 0.34)",
      divider: "rgba(255, 255, 255, 0.08)",
      track: "rgba(255, 255, 255, 0.09)",
      text: "#F5F7FA",
      textSec: "#A0AABF",
      textMut: "#6D788D",
      blue: "#58A6FF",
      blueSoft: "rgba(88, 166, 255, 0.16)",
      green: "#39D353",
      greenBar: "#30D158",
      greenSoft: "rgba(48, 209, 88, 0.16)",
      amber: "#FBBF24",
      amberSoft: "rgba(251, 191, 36, 0.16)",
      red: "#FF6961",
      redSoft: "rgba(255, 105, 97, 0.16)",
      violet: "#A78BFA",
      pillBg: "rgba(255, 255, 255, 0.075)",
      heat: ["#1A202B", "#0E4429", "#006D32", "#26A641", "#39D353"],
      heatStroke: "rgba(255, 255, 255, 0.055)",
      heatPeakGlow: "rgba(57, 211, 83, 0.42)",
      emblemStops: ["#1E88FF", "#10B981"]
    },
    porcelain: {
      name: "晴霜白瓷",
      dark: false,
      bgStops: ["#F8FAFD", "#EEF2F8", "#F4F7FC"],
      bloomA: "rgba(0, 113, 227, 0.085)",
      bloomB: "rgba(48, 183, 85, 0.075)",
      bloomC: "rgba(124, 58, 237, 0.055)",
      dotColor: "rgba(15, 23, 42, 0.04)",
      frameStroke: "rgba(15, 23, 42, 0.065)",
      cardBg: "rgba(255, 255, 255, 0.94)",
      cardBgAlt: "#F4F6FB",
      cardStroke: "rgba(15, 23, 42, 0.078)",
      cardSpecular: "rgba(255, 255, 255, 0.95)",
      cardShadow: "rgba(15, 23, 42, 0.065)",
      divider: "rgba(15, 23, 42, 0.075)",
      track: "rgba(15, 23, 42, 0.075)",
      text: "#141821",
      textSec: "#4C5568",
      textMut: "#7A8499",
      blue: "#0071E3",
      blueSoft: "rgba(0, 113, 227, 0.10)",
      green: "#16803C",
      greenBar: "#2EB854",
      greenSoft: "rgba(46, 184, 84, 0.13)",
      amber: "#B45309",
      amberSoft: "rgba(245, 158, 11, 0.14)",
      red: "#C92A2A",
      redSoft: "rgba(239, 68, 68, 0.12)",
      violet: "#7C3AED",
      pillBg: "rgba(15, 23, 42, 0.055)",
      heat: ["#E7ECF3", "#9BE9A8", "#40C463", "#30A14E", "#216E39"],
      heatStroke: "rgba(15, 23, 42, 0.06)",
      heatPeakGlow: "rgba(33, 110, 57, 0.16)",
      emblemStops: ["#0071E3", "#22C55E"]
    },
    aurora: {
      name: "极光深蓝",
      dark: true,
      bgStops: ["#06101E", "#0C1B30", "#081424"],
      bloomA: "rgba(56, 189, 248, 0.18)",
      bloomB: "rgba(20, 184, 166, 0.17)",
      bloomC: "rgba(168, 85, 247, 0.11)",
      dotColor: "rgba(186, 230, 253, 0.04)",
      frameStroke: "rgba(125, 211, 252, 0.12)",
      cardBg: "rgba(186, 230, 253, 0.048)",
      cardBgAlt: "rgba(186, 230, 253, 0.036)",
      cardStroke: "rgba(125, 211, 252, 0.14)",
      cardSpecular: "rgba(186, 230, 253, 0.28)",
      cardShadow: "rgba(2, 8, 20, 0.42)",
      divider: "rgba(125, 211, 252, 0.11)",
      track: "rgba(186, 230, 253, 0.10)",
      text: "#F0F8FF",
      textSec: "#93B5D6",
      textMut: "#6284A7",
      blue: "#38BDF8",
      blueSoft: "rgba(56, 189, 248, 0.17)",
      green: "#2DD4BF",
      greenBar: "#14B8A6",
      greenSoft: "rgba(45, 212, 191, 0.17)",
      amber: "#FBBF24",
      amberSoft: "rgba(251, 191, 36, 0.17)",
      red: "#FB7185",
      redSoft: "rgba(251, 113, 133, 0.17)",
      violet: "#C084FC",
      pillBg: "rgba(186, 230, 253, 0.09)",
      heat: ["#13253B", "#0B4F4A", "#0D8377", "#14B8A6", "#5EEAD4"],
      heatStroke: "rgba(186, 230, 253, 0.07)",
      heatPeakGlow: "rgba(94, 234, 212, 0.44)",
      emblemStops: ["#38BDF8", "#14B8A6"]
    }
  };

  function roundRectPath(ctx, x, y, w, h, r) {
    const rad = Math.min(r, w / 2, h / 2);
    ctx.beginPath();
    ctx.moveTo(x + rad, y);
    ctx.arcTo(x + w, y, x + w, y + h, rad);
    ctx.arcTo(x + w, y + h, x, y + h, rad);
    ctx.arcTo(x, y + h, x, y, rad);
    ctx.arcTo(x, y, x + w, y, rad);
    ctx.closePath();
  }

  function truncate(ctx, text, maxW) {
    const str = String(text || "");
    if (ctx.measureText(str).width <= maxW) return str;
    const ell = "…";
    let lo = 0;
    let hi = str.length;
    while (lo < hi) {
      const mid = (lo + hi + 1) >> 1;
      if (ctx.measureText(str.slice(0, mid) + ell).width <= maxW) lo = mid;
      else hi = mid - 1;
    }
    return str.slice(0, Math.max(1, lo)) + ell;
  }

  function drawPill(ctx, x, y, text, bg, fg, opts = {}) {
    const h = opts.h || 22;
    const px = opts.px || 9;
    ctx.save();
    ctx.font = opts.font || `600 11px ${FONT}`;
    const tw = ctx.measureText(text).width;
    const w = tw + px * 2;
    const dx = opts.alignRight ? x - w : x;
    roundRectPath(ctx, dx, y, w, h, h / 2);
    ctx.fillStyle = bg;
    ctx.fill();
    if (opts.stroke) {
      ctx.strokeStyle = opts.stroke;
      ctx.lineWidth = 1;
      ctx.stroke();
    }
    ctx.fillStyle = fg;
    ctx.textAlign = "left";
    ctx.textBaseline = "middle";
    ctx.fillText(text, dx + px, y + h / 2 + 0.5);
    ctx.restore();
    return w;
  }

  function drawGlassCard(ctx, x, y, w, h, r, t, opts = {}) {
    ctx.save();
    if (!opts.flat) {
      ctx.shadowColor = t.cardShadow;
      ctx.shadowBlur = t.dark ? 22 : 16;
      ctx.shadowOffsetX = 0;
      ctx.shadowOffsetY = t.dark ? 10 : 6;
    }
    roundRectPath(ctx, x, y, w, h, r);
    ctx.fillStyle = opts.fill || t.cardBg;
    ctx.fill();
    ctx.restore();

    if (opts.glowColor) {
      ctx.save();
      roundRectPath(ctx, x, y, w, h, r);
      ctx.clip();
      const g = ctx.createRadialGradient(x + w * 0.16, y, 4, x + w * 0.16, y, w * 0.72);
      g.addColorStop(0, opts.glowColor);
      g.addColorStop(1, "rgba(0,0,0,0)");
      ctx.fillStyle = g;
      ctx.fillRect(x, y, w, h);
      ctx.restore();
    }

    ctx.save();
    roundRectPath(ctx, x + 0.5, y + 0.5, w - 1, h - 1, r);
    ctx.strokeStyle = opts.stroke || t.cardStroke;
    ctx.lineWidth = 1;
    ctx.stroke();

    // Subtle top specular highlight
    const spec = ctx.createLinearGradient(x + r, y, x + w - r, y);
    spec.addColorStop(0, "rgba(255,255,255,0)");
    spec.addColorStop(0.5, t.cardSpecular);
    spec.addColorStop(1, "rgba(255,255,255,0)");
    ctx.strokeStyle = spec;
    ctx.lineWidth = 1;
    ctx.beginPath();
    ctx.moveTo(x + r, y + 0.75);
    ctx.lineTo(x + w - r, y + 0.75);
    ctx.stroke();
    ctx.restore();
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

  function fmtAxisTokens(n) {
    const v = Number(n || 0);
    const abs = Math.abs(v);
    if (abs < 1) return "0";
    if (abs >= 1e9) return `${(v / 1e9).toFixed(abs >= 1e10 ? 0 : 1)}B`;
    if (abs >= 1e6) return `${(v / 1e6).toFixed(abs >= 1e7 ? 0 : 1)}M`;
    if (abs >= 1e3) return `${Math.round(v / 1e3)}K`;
    return String(Math.round(v));
  }

  function fmtMoney(usd, currency, rate, compact = false) {
    const raw = Number(usd || 0);
    const sym = currency === "CNY" ? "¥" : "$";
    const val = currency === "CNY" ? raw * Number(rate || 7.25) : raw;
    if (compact && val >= 10_000) return `${sym}${(val / 1000).toFixed(1)}k`;
    if (compact && val >= 1000) return `${sym}${Math.round(val).toLocaleString()}`;
    return val < 0.005 ? `${sym}0.00` : `${sym}${val.toFixed(2)}`;
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

  function expandHeatmapDays(startDateStr, endDateStr, activeRows) {
    const byDate = new Map();
    (activeRows || []).forEach((r) => { if (r && r.d) byDate.set(r.d, r); });
    const parseYMD = (s) => {
      const m = /^(\d{4})-(\d{2})-(\d{2})$/.exec(String(s || ""));
      return m ? new Date(Number(m[1]), Number(m[2]) - 1, Number(m[3])) : null;
    };
    const fmtYMD = (dt) => `${dt.getFullYear()}-${String(dt.getMonth() + 1).padStart(2, "0")}-${String(dt.getDate()).padStart(2, "0")}`;
    const s = parseYMD(startDateStr);
    const e = parseYMD(endDateStr);
    if (!s || !e || s > e) return [];
    const out = [];
    const cur = new Date(s.getTime());
    while (cur <= e && out.length < 400) {
      const key = fmtYMD(cur);
      const hit = byDate.get(key);
      const lv = (hit && Array.isArray(hit.lv)) ? hit.lv : [0, 0, 0, 0];
      out.push({
        date: key,
        weekday: cur.getDay(),
        levels: [Number(lv[0] || 0), Number(lv[1] || 0), Number(lv[2] || 0), Number(lv[3] || 0)]
      });
      cur.setDate(cur.getDate() + 1);
    }
    return out;
  }

  function classifyChronotype(peakHour) {
    if (peakHour >= 22 || peakHour <= 3) return "深夜极客";
    if (peakHour >= 4 && peakHour <= 9) return "晨间先锋";
    if (peakHour >= 10 && peakHour <= 13) return "上午专注";
    if (peakHour >= 14 && peakHour <= 18) return "午后高能";
    return "晚间冲刺";
  }

  function drawEmblem(ctx, x, y, size, t) {
    ctx.save();
    ctx.shadowColor = t.dark ? "rgba(56, 189, 248, 0.35)" : "rgba(0, 113, 227, 0.25)";
    ctx.shadowBlur = 16;
    ctx.shadowOffsetY = 5;
    roundRectPath(ctx, x, y, size, size, 13);
    const g = ctx.createLinearGradient(x, y, x + size, y + size);
    g.addColorStop(0, t.emblemStops[0]);
    g.addColorStop(1, t.emblemStops[1]);
    ctx.fillStyle = g;
    ctx.fill();
    ctx.restore();

    ctx.save();
    roundRectPath(ctx, x + 0.5, y + 0.5, size - 1, size - 1, 13);
    ctx.strokeStyle = "rgba(255, 255, 255, 0.36)";
    ctx.lineWidth = 1;
    ctx.stroke();

    // Crisp pulse waveform vector path
    const s = size / 46;
    ctx.strokeStyle = "#FFFFFF";
    ctx.lineWidth = 3 * s;
    ctx.lineCap = "round";
    ctx.lineJoin = "round";
    ctx.beginPath();
    ctx.moveTo(x + 10 * s, y + 29 * s);
    ctx.lineTo(x + 18.5 * s, y + 18 * s);
    ctx.lineTo(x + 24.5 * s, y + 25.5 * s);
    ctx.lineTo(x + 31.8 * s, y + 13.5 * s);
    ctx.lineTo(x + 36.5 * s, y + 19.5 * s);
    ctx.stroke();

    ctx.fillStyle = "#FFFFFF";
    ctx.beginPath();
    ctx.arc(x + 31.8 * s, y + 13.5 * s, 3.2 * s, 0, Math.PI * 2);
    ctx.fill();
    ctx.restore();
  }

  function renderShareCard(canvas, data, options = {}) {
    if (!canvas || !data) return null;
    const t = THEMES[options.theme] || THEMES.obsidian;
    const currency = options.currency || data.currency || "USD";
    const rate = Number(options.rate || data.usdToCnyRate || 7.25);
    const heatmapMetric = options.heatmapMetric || "total";
    const hideProjects = Boolean(options.hideProjects);

    const W = 1080;
    const M = 40;
    const CW = W - M * 2;
    const scale = options.scale || 2;

    const headerH = 66;
    const kpiH = 122;
    const heatH = 242;
    const bottomH = 220;
    const footerH = 38;
    const H = 36 + headerH + 20 + kpiH + 16 + heatH + 16 + bottomH + 20 + footerH + 22;

    canvas.width = Math.round(W * scale);
    canvas.height = Math.round(H * scale);
    const ctx = canvas.getContext("2d");
    ctx.save();
    ctx.scale(scale, scale);

    // 1. Studio Gradient Backdrop + Optical Blooms + Subtle Dot Texture
    const bg = ctx.createLinearGradient(0, 0, W * 0.4, H);
    bg.addColorStop(0, t.bgStops[0]);
    bg.addColorStop(0.55, t.bgStops[1]);
    bg.addColorStop(1, t.bgStops[2]);
    ctx.fillStyle = bg;
    ctx.fillRect(0, 0, W, H);

    const drawBloom = (cx, cy, radius, color) => {
      const g = ctx.createRadialGradient(cx, cy, 0, cx, cy, radius);
      g.addColorStop(0, color);
      g.addColorStop(1, "rgba(0,0,0,0)");
      ctx.fillStyle = g;
      ctx.fillRect(0, 0, W, H);
    };
    drawBloom(W * 0.14, 90, 440, t.bloomA);
    drawBloom(W * 0.88, H * 0.72, 460, t.bloomB);
    drawBloom(W * 0.50, H * 0.36, 420, t.bloomC);

    // Subtle studio dot grid in margins
    ctx.fillStyle = t.dotColor;
    for (let gx = 20; gx < W; gx += 26) {
      for (let gy = 20; gy < H; gy += 26) {
        ctx.fillRect(gx, gy, 1.2, 1.2);
      }
    }

    // Crisp outer museum-print hairline frame
    roundRectPath(ctx, 14.5, 14.5, W - 29, H - 29, 24);
    ctx.strokeStyle = t.frameStroke;
    ctx.lineWidth = 1;
    ctx.stroke();

    let y = 36;
    const ov = data.overview || {};
    const st = data.streaks || {};

    // 2. Header Bar
    drawEmblem(ctx, M, y + 6, 48, t);

    ctx.font = `700 25px ${FONT}`;
    ctx.fillStyle = t.text;
    ctx.textAlign = "left";
    ctx.textBaseline = "top";
    const titleStr = "Antigravity Pulse";
    ctx.fillText(titleStr, M + 62, y + 6);
    let badgeX = M + 62 + ctx.measureText(titleStr).width + 12;

    badgeX += drawPill(ctx, badgeX, y + 10, ov.rangeLabel || "用量统计", t.blueSoft, t.blue, { h: 22, px: 10 }) + 7;
    drawPill(ctx, badgeX, y + 10, "本机用量报告", t.pillBg, t.textSec, { h: 22, px: 9 });

    ctx.font = `500 12.5px ${FONT}`;
    ctx.fillStyle = t.textSec;
    const subLine = `${ov.rangeLabel || "统计周期"}  ·  本机活跃 ${ov.activeDays || 0} 天  ·  ${Number(ov.sessions || 0).toLocaleString()} 场会话  ·  ${Number(ov.turns || 0).toLocaleString()} 轮对话`;
    ctx.fillText(truncate(ctx, subLine, 590), M + 62, y + 39);

    const nowDt = new Date();
    const dateStamp = `${nowDt.getFullYear()}-${String(nowDt.getMonth() + 1).padStart(2, "0")}-${String(nowDt.getDate()).padStart(2, "0")}`;
    const curBadge = currency === "CNY" ? "¥ CNY" : "$ USD";
    drawPill(ctx, W - M, y + 8, `${dateStamp}  ·  ${curBadge}`, t.pillBg, t.text, { alignRight: true, h: 24, px: 11, font: `600 11.5px ${FONT}` });

    ctx.font = `500 11px ${FONT}`;
    ctx.fillStyle = t.textMut;
    ctx.textAlign = "right";
    ctx.fillText("本机日志零侵入生成 · 仅含当前设备消耗", W - M, y + 40);

    y += headerH + 20;

    // 3. Four Hero KPI Cards
    const kpiGap = 14;
    const kpiW = (CW - kpiGap * 3) / 4;
    const kpis = [
      {
        label: "本机总处理量",
        pill: { text: "含缓存", bg: t.blueSoft, fg: t.blue },
        val: fmtTokens(ov.totalTokens),
        valColor: t.text,
        sub: `入 ${fmtTokens(ov.inputTokens)} · 缓 ${fmtTokens(ov.cacheReadTokens)} · 出 ${fmtTokens(ov.outputTokens)}`,
        glow: t.dark ? "rgba(88, 166, 255, 0.08)" : "rgba(0, 113, 227, 0.04)",
        barMode: "composition"
      },
      {
        label: "本机净用量",
        pill: { text: `${Number(ov.turns || 0).toLocaleString()} 轮`, bg: t.pillBg, fg: t.textSec },
        val: fmtTokens(ov.netTokens),
        valColor: t.text,
        sub: `${Number(ov.sessions || 0).toLocaleString()} 场会话 · 活跃 ${ov.activeDays || 0} 天`,
        foot: `活跃日均 ${fmtTokens(st.avgDailyTotalTokens || 0, true)}`,
        glow: t.dark ? "rgba(167, 139, 250, 0.07)" : "rgba(124, 58, 237, 0.035)"
      },
      {
        label: "本机估算价值",
        pill: { text: `省 ${fmtMoney(ov.estimatedSavedUSD, currency, rate, true)}`, bg: t.greenSoft, fg: t.green },
        val: fmtMoney(ov.estimatedCostUSD, currency, rate),
        valColor: t.text,
        sub: `无缓存原价约 ${fmtMoney(ov.estimatedUncachedUSD, currency, rate, true)}`,
        foot: "按公开 API 费率参考估算",
        glow: t.dark ? "rgba(48, 209, 88, 0.075)" : "rgba(46, 184, 84, 0.04)"
      },
      {
        label: "缓存命中率",
        pill: { text: fmtSpeed(ov.avgTokensPerSec), bg: t.blueSoft, fg: t.blue },
        val: fmtPct(ov.cacheHitRate),
        valColor: t.green,
        sub: "上下文复用效率与平均输出速度",
        glow: t.dark ? "rgba(48, 209, 88, 0.09)" : "rgba(46, 184, 84, 0.045)",
        barMode: "cache"
      }
    ];

    kpis.forEach((k, i) => {
      const kx = M + i * (kpiW + kpiGap);
      drawGlassCard(ctx, kx, y, kpiW, kpiH, 16, t, { glowColor: k.glow });

      ctx.font = `600 12px ${FONT}`;
      ctx.fillStyle = t.textSec;
      ctx.textAlign = "left";
      ctx.textBaseline = "top";
      ctx.fillText(k.label, kx + 16, y + 16);

      drawPill(ctx, kx + kpiW - 14, y + 12, k.pill.text, k.pill.bg, k.pill.fg, { alignRight: true, h: 20, px: 8, font: `600 10.5px ${FONT}` });

      ctx.font = `700 30px ${FONT}`;
      ctx.fillStyle = k.valColor;
      ctx.textAlign = "left";
      ctx.fillText(truncate(ctx, k.val, kpiW - 32), kx + 16, y + 42);

      ctx.font = `500 11px ${FONT}`;
      ctx.fillStyle = t.textMut;
      ctx.fillText(truncate(ctx, k.sub, kpiW - 32), kx + 16, y + 81);

      if (k.barMode === "composition") {
        const bx = kx + 16, by = y + 103, bw = kpiW - 32, bh = 5;
        roundRectPath(ctx, bx, by, bw, bh, 2.5);
        ctx.fillStyle = t.track;
        ctx.fill();
        const tot = Math.max(1, Number(ov.totalTokens || 0));
        const cw = Math.max(0, (Number(ov.cacheReadTokens || 0) / tot) * bw);
        const iw = Math.max(0, (Number(ov.inputTokens || 0) / tot) * bw);
        const ow = Math.max(0, bw - cw - iw);
        ctx.save();
        roundRectPath(ctx, bx, by, bw, bh, 2.5);
        ctx.clip();
        if (cw > 0) { ctx.fillStyle = t.greenBar; ctx.fillRect(bx, by, cw, bh); }
        if (iw > 0) { ctx.fillStyle = t.blue; ctx.fillRect(bx + cw, by, iw, bh); }
        if (ow > 0) { ctx.fillStyle = t.violet; ctx.fillRect(bx + cw + iw, by, ow, bh); }
        ctx.restore();
      } else if (k.barMode === "cache") {
        const bx = kx + 16, by = y + 103, bw = kpiW - 32, bh = 5;
        roundRectPath(ctx, bx, by, bw, bh, 2.5);
        ctx.fillStyle = t.track;
        ctx.fill();
        const ratio = Math.max(0, Math.min(1, Number(ov.cacheHitRate || 0)));
        if (ratio > 0) {
          roundRectPath(ctx, bx, by, Math.max(6, bw * ratio), bh, 2.5);
          const g = ctx.createLinearGradient(bx, by, bx + bw, by);
          g.addColorStop(0, t.blue);
          g.addColorStop(1, t.greenBar);
          ctx.fillStyle = g;
          ctx.fill();
        }
      } else if (k.foot) {
        ctx.font = `600 10.5px ${FONT}`;
        ctx.fillStyle = t.textSec;
        ctx.fillText(truncate(ctx, k.foot, kpiW - 32), kx + 16, y + 99);
      }
    });

    y += kpiH + 16;

    // 4. Signature Centerpiece: 52-Week GitHub-Style Token Contribution Heatmap
    drawGlassCard(ctx, M, y, CW, heatH, 18, t, {
      glowColor: t.dark ? "rgba(48, 209, 88, 0.065)" : "rgba(46, 184, 84, 0.035)"
    });

    const metricLabels = {
      total: "含缓存总处理量 (M)",
      net: "净用量 (M)",
      cost: "估算金额",
      turns: "对话轮次"
    };
    const metricIdx = { total: 0, net: 1, cost: 2, turns: 3 }[heatmapMetric] ?? 0;

    ctx.font = `700 15px ${FONT}`;
    ctx.fillStyle = t.text;
    ctx.textAlign = "left";
    ctx.textBaseline = "middle";
    const hmTitle = "52 周每日 Token 贡献热力图";
    ctx.fillText(hmTitle, M + 22, y + 25);
    drawPill(ctx, M + 22 + ctx.measureText(hmTitle).width + 10, y + 14.5, metricLabels[heatmapMetric] || metricLabels.total, t.greenSoft, t.green, { h: 21, px: 9 });

    ctx.font = `600 12px ${FONT}`;
    ctx.fillStyle = t.textSec;
    ctx.textAlign = "right";
    ctx.fillText(
      `本机年度累计 ${fmtTokens(st.totalTokensYear || 0)}（净 ${fmtTokens(st.netTokensYear || 0)}） · 活跃 ${st.activeDaysYear || 0} 天`,
      W - M - 22,
      y + 25
    );

    const days = expandHeatmapDays(data.heatmapStartDate, data.heatmapEndDate, data.heatmap);
    const cols = Math.max(1, Math.ceil(days.length / 7));
    const gridAreaX = M + 44;
    const gridAreaW = CW - 66;
    const cellGap = 3.5;
    const cellSize = Math.min(14.2, (gridAreaW - (cols - 1) * cellGap) / cols);
    const pitch = cellSize + cellGap;
    const actualGridW = cols * pitch - cellGap;
    const gridX = gridAreaX + Math.max(0, (gridAreaW - actualGridW) / 2);
    const gridY = y + 66;

    // Month labels
    const monthNames = ["1月", "2月", "3月", "4月", "5月", "6月", "7月", "8月", "9月", "10月", "11月", "12月"];
    let lastM = -1;
    let lastMX = -50;
    ctx.font = `500 10.5px ${FONT}`;
    ctx.fillStyle = t.textMut;
    ctx.textAlign = "left";
    ctx.textBaseline = "top";
    days.forEach((d, idx) => {
      if (d.weekday !== 0 && idx !== 0) return;
      const col = Math.floor(idx / 7);
      const m = parseInt(d.date.slice(5, 7), 10) - 1;
      const mx = gridX + col * pitch;
      if (m !== lastM && mx - lastMX >= 32) {
        lastM = m;
        lastMX = mx;
        ctx.fillText(monthNames[m] || "", mx, y + 48);
      }
    });

    // Weekday gutter labels
    ctx.textAlign = "right";
    ctx.textBaseline = "middle";
    [[1, "一"], [3, "三"], [5, "五"]].forEach(([row, txt]) => {
      ctx.fillText(txt, gridX - 8, gridY + row * pitch + cellSize / 2);
    });

    // Draw 52-week contribution cells
    days.forEach((d, idx) => {
      const col = Math.floor(idx / 7);
      const row = idx % 7;
      const cx = gridX + col * pitch;
      const cy = gridY + row * pitch;
      const lv = Math.max(0, Math.min(4, d.levels[metricIdx] || 0));

      ctx.save();
      if (lv === 4 && t.dark) {
        ctx.shadowColor = t.heatPeakGlow;
        ctx.shadowBlur = 7;
      }
      roundRectPath(ctx, cx, cy, cellSize, cellSize, 3.2);
      ctx.fillStyle = t.heat[lv];
      ctx.fill();
      ctx.restore();

      roundRectPath(ctx, cx + 0.4, cy + 0.4, cellSize - 0.8, cellSize - 0.8, 3);
      ctx.strokeStyle = t.heatStroke;
      ctx.lineWidth = 0.8;
      ctx.stroke();
    });

    // Heatmap Footer Divider + Streaks + Legend
    const hfY = y + heatH - 42;
    ctx.strokeStyle = t.divider;
    ctx.lineWidth = 1;
    ctx.beginPath();
    ctx.moveTo(M + 22, hfY);
    ctx.lineTo(W - M - 22, hfY);
    ctx.stroke();

    const avgStr = heatmapMetric === "net"
      ? fmtTokens(st.avgDailyNetTokens || 0, true)
      : fmtTokens(st.avgDailyTotalTokens || 0, true);
    const peakStr = st.peakDate
      ? `${st.peakDate} (${fmtTokens(heatmapMetric === "net" ? st.peakNetTokens : st.peakTotalTokens, true)})`
      : "--";

    const streakParts = [
      ["当前连续 ", `${st.currentStreakDays || 0} 天`],
      ["最长连续 ", `${st.longestStreakDays || 0} 天`],
      ["活跃日均 ", avgStr],
      ["峰值日 ", peakStr]
    ];
    let sx = M + 22;
    const sy = hfY + 21;
    ctx.textAlign = "left";
    ctx.textBaseline = "middle";
    streakParts.forEach(([k, v], i) => {
      if (i > 0) {
        ctx.font = `500 11.5px ${FONT}`;
        ctx.fillStyle = t.textMut;
        ctx.fillText("  ·  ", sx, sy);
        sx += ctx.measureText("  ·  ").width;
      }
      ctx.font = `500 11.5px ${FONT}`;
      ctx.fillStyle = t.textSec;
      ctx.fillText(k, sx, sy);
      sx += ctx.measureText(k).width;
      ctx.font = `700 11.5px ${FONT}`;
      ctx.fillStyle = t.text;
      ctx.fillText(v, sx, sy);
      sx += ctx.measureText(v).width;
    });

    // Legend on right
    let lx = W - M - 22;
    ctx.font = `500 11px ${FONT}`;
    ctx.fillStyle = t.textMut;
    ctx.textAlign = "right";
    ctx.fillText("多", lx, sy);
    lx -= ctx.measureText("多").width + 6;
    for (let lv = 4; lv >= 0; lv--) {
      lx -= 11;
      roundRectPath(ctx, lx, sy - 5.5, 11, 11, 2.5);
      ctx.fillStyle = t.heat[lv];
      ctx.fill();
      ctx.strokeStyle = t.heatStroke;
      ctx.lineWidth = 0.8;
      ctx.stroke();
      lx -= 4;
    }
    ctx.fillStyle = t.textMut;
    ctx.fillText("少", lx - 2, sy);

    y += heatH + 16;

    // 6. Bottom Insights Row (2 Cards: Top Models + Top Projects OR 24h Rhythm Privacy Mode)
    const colGap = 14;
    const colW = (CW - colGap) / 2;

    // Left Card: Top 4 Models
    drawGlassCard(ctx, M, y, colW, bottomH, 18, t);
    const models = (data.models || []).slice(0, 4);
    ctx.font = `700 14.5px ${FONT}`;
    ctx.fillStyle = t.text;
    ctx.textAlign = "left";
    ctx.textBaseline = "middle";
    ctx.fillText("主力模型分布", M + 20, y + 24);
    ctx.font = `500 11.5px ${FONT}`;
    ctx.fillStyle = t.textMut;
    ctx.textAlign = "right";
    ctx.fillText(`共 ${(data.models || []).length} 个模型`, M + colW - 20, y + 24);

    const modelColors = [t.blue, t.greenBar, t.violet, t.amber];
    if (!models.length) {
      ctx.font = `500 12.5px ${FONT}`;
      ctx.fillStyle = t.textMut;
      ctx.textAlign = "center";
      ctx.fillText("所选周期暂无模型用量记录", M + colW / 2, y + bottomH / 2 + 8);
    } else {
      models.forEach((m, i) => {
        const ry = y + 48 + i * 40;
        const accent = modelColors[i % modelColors.length];
        const share = Math.max(0.03, Math.min(1, Number(m.shareRatio || 0)));

        ctx.fillStyle = accent;
        ctx.beginPath();
        ctx.arc(M + 24, ry + 7, 3.5, 0, Math.PI * 2);
        ctx.fill();

        const rightVal = `${fmtTokens(m.totalTokens, true)} · ${fmtMoney(m.estimatedCostUSD, currency, rate)}`;
        ctx.font = `700 12px ${FONT}`;
        const rvW = ctx.measureText(rightVal).width;

        ctx.font = `600 12px ${FONT}`;
        ctx.fillStyle = t.text;
        ctx.textAlign = "left";
        ctx.textBaseline = "middle";
        ctx.fillText(truncate(ctx, m.modelName, colW - 60 - rvW), M + 34, ry + 7);

        ctx.font = `700 12px ${FONT}`;
        ctx.textAlign = "right";
        ctx.fillText(rightVal, M + colW - 20, ry + 7);

        const bx = M + 20, by = ry + 18, bw = colW - 40, bh = 5;
        roundRectPath(ctx, bx, by, bw, bh, 2.5);
        ctx.fillStyle = t.track;
        ctx.fill();
        roundRectPath(ctx, bx, by, Math.max(8, bw * share), bh, 2.5);
        ctx.fillStyle = accent;
        ctx.fill();

        const spd = m.avgTokensPerSec ? ` · ${fmtSpeed(m.avgTokensPerSec)}` : "";
        const rightSub = `${Number(m.turns || 0).toLocaleString()} 轮 · 省 ${fmtMoney(m.estimatedSavedUSD, currency, rate, true)}`;
        ctx.font = `500 10.5px ${FONT}`;
        ctx.fillStyle = t.textMut;
        const rsW = ctx.measureText(rightSub).width;
        ctx.textAlign = "left";
        ctx.fillText(truncate(ctx, `净 ${fmtTokens(m.netTokens)} · 缓存 ${fmtPct(m.cacheHitRate)}${spd}`, colW - 52 - rsW), M + 20, ry + 31);
        ctx.textAlign = "right";
        ctx.fillText(rightSub, M + colW - 20, ry + 31);
      });
    }

    // Right Card: Top 4 Projects OR 24h Rhythm (when privacy toggle ON or no projects)
    const rx = M + colW + colGap;
    drawGlassCard(ctx, rx, y, colW, bottomH, 18, t);
    const projects = (data.projects || []).slice(0, 4);
    const showRhythm = hideProjects || !projects.length;

    if (!showRhythm) {
      ctx.font = `700 14.5px ${FONT}`;
      ctx.fillStyle = t.text;
      ctx.textAlign = "left";
      ctx.textBaseline = "middle";
      ctx.fillText("本机项目投入排行", rx + 20, y + 24);
      ctx.font = `500 11.5px ${FONT}`;
      ctx.fillStyle = t.textMut;
      ctx.textAlign = "right";
      ctx.fillText(`按处理量 Top ${projects.length}`, rx + colW - 20, y + 24);

      projects.forEach((p, i) => {
        const ry = y + 48 + i * 40;
        const share = Math.max(0.03, Math.min(1, Number(p.shareRatio || 0)));
        const rightVal = `${fmtTokens(p.totalTokens, true)} (${(share * 100).toFixed(1)}%)`;
        ctx.font = `700 12px ${FONT}`;
        const rvW = ctx.measureText(rightVal).width;

        drawPill(ctx, rx + 20, ry - 2, `#${i + 1}`, t.greenSoft, t.green, { h: 17, px: 6, font: `700 10px ${FONT}` });
        ctx.font = `600 12px ${FONT}`;
        ctx.fillStyle = t.text;
        ctx.textAlign = "left";
        ctx.textBaseline = "middle";
        ctx.fillText(truncate(ctx, p.projectName, colW - 76 - rvW), rx + 52, ry + 7);

        ctx.font = `700 12px ${FONT}`;
        ctx.textAlign = "right";
        ctx.fillText(rightVal, rx + colW - 20, ry + 7);

        const bx = rx + 20, by = ry + 18, bw = colW - 40, bh = 5;
        roundRectPath(ctx, bx, by, bw, bh, 2.5);
        ctx.fillStyle = t.track;
        ctx.fill();
        const barG = ctx.createLinearGradient(bx, by, bx + bw, by);
        barG.addColorStop(0, t.greenBar);
        barG.addColorStop(1, t.blue);
        roundRectPath(ctx, bx, by, Math.max(8, bw * share), bh, 2.5);
        ctx.fillStyle = barG;
        ctx.fill();

        const rightSub = `${Number(p.turns || 0).toLocaleString()} 轮 · ${fmtMoney(p.estimatedCostUSD, currency, rate)}`;
        ctx.font = `500 10.5px ${FONT}`;
        ctx.fillStyle = t.textMut;
        const rsW = ctx.measureText(rightSub).width;
        ctx.textAlign = "left";
        ctx.fillText(truncate(ctx, `${p.sessions} 场会话 · 净 ${fmtTokens(p.netTokens)} · 缓存 ${fmtPct(p.cacheHitRate)}`, colW - 52 - rsW), rx + 20, ry + 31);
        ctx.textAlign = "right";
        ctx.fillText(rightSub, rx + colW - 20, ry + 31);
      });
    } else {
      const hrs = data.hourlyRhythm || [];
      let maxTot = 0;
      let peakH = -1;
      hrs.forEach((h) => { if (h.totalTokens > maxTot) { maxTot = h.totalTokens; peakH = h.hour; } });
      const peakBadge = peakH >= 0 && maxTot > 0
        ? `峰值 ${String(peakH).padStart(2, "0")}:00 · ${classifyChronotype(peakH)}`
        : "全天节律";

      ctx.font = `700 14.5px ${FONT}`;
      ctx.fillStyle = t.text;
      ctx.textAlign = "left";
      ctx.textBaseline = "middle";
      ctx.fillText("24 小时编码节律", rx + 20, y + 24);
      drawPill(ctx, rx + colW - 20, y + 13.5, peakBadge, t.blueSoft, t.blue, { alignRight: true, h: 21, px: 9 });

      const padL = 62, padR = 20, topY = y + 58, plotH = 104;
      const plotX = rx + padL;
      const plotW = colW - padL - padR;
      const denom = Math.max(1, maxTot * 1.15);

      ctx.strokeStyle = t.divider;
      ctx.fillStyle = t.textMut;
      ctx.font = `500 10.5px ${FONT}`;
      ctx.textAlign = "right";
      ctx.textBaseline = "middle";
      for (let i = 0; i <= 2; i++) {
        const ratio = i / 2;
        const gy = topY + plotH * (1 - ratio);
        ctx.beginPath();
        ctx.moveTo(plotX, gy);
        ctx.lineTo(plotX + plotW, gy);
        ctx.stroke();
        ctx.fillText(fmtAxisTokens(denom * ratio), plotX - 8, gy);
      }

      const step = plotW / 24;
      const barW = Math.max(6, step * 0.60);
      for (let hr = 0; hr < 24; hr++) {
        const item = hrs[hr] || { totalTokens: 0, netTokens: 0 };
        const bx = plotX + step * (hr + 0.5) - barW / 2;
        if (item.totalTokens > 0) {
          const th = Math.max(3, (item.totalTokens / denom) * plotH);
          const nh = Math.max(2, (item.netTokens / denom) * plotH);
          ctx.save();
          if (hr === peakH && t.dark) { ctx.shadowColor = t.greenBar; ctx.shadowBlur = 8; }
          roundRectPath(ctx, bx, topY + plotH - th, barW, th, 3);
          ctx.fillStyle = hr === peakH ? t.greenBar : (t.dark ? "rgba(48, 209, 88, 0.36)" : "rgba(46, 184, 84, 0.34)");
          ctx.fill();
          ctx.restore();

          roundRectPath(ctx, bx, topY + plotH - nh, barW, nh, 2);
          ctx.fillStyle = t.blue;
          ctx.fill();
        }
      }

      ctx.fillStyle = t.textMut;
      ctx.font = `500 10px ${FONT}`;
      ctx.textAlign = "center";
      ctx.textBaseline = "top";
      [0, 4, 8, 12, 16, 20, 23].forEach((hr) => {
        ctx.fillText(`${String(hr).padStart(2, "0")}h`, plotX + step * (hr + 0.5), topY + plotH + 7);
      });

      // Legend & privacy note
      const legY = y + bottomH - 20;
      ctx.fillStyle = t.greenBar;
      roundRectPath(ctx, rx + 20, legY - 4, 8, 8, 2);
      ctx.fill();
      ctx.fillStyle = t.textSec;
      ctx.font = `500 10.5px ${FONT}`;
      ctx.textAlign = "left";
      ctx.textBaseline = "middle";
      ctx.fillText("总处理量", rx + 32, legY);

      ctx.fillStyle = t.blue;
      roundRectPath(ctx, rx + 86, legY - 4, 8, 8, 2);
      ctx.fill();
      ctx.fillStyle = t.textSec;
      ctx.fillText("净用量", rx + 98, legY);

      ctx.textAlign = "right";
      ctx.fillStyle = t.textMut;
      ctx.fillText(hideProjects ? "隐私脱敏模式 · 已隐藏项目名称" : "全天活跃分布", rx + colW - 20, legY);
    }

    y += bottomH + 20;

    // 7. Editorial Footer
    ctx.strokeStyle = t.divider;
    ctx.lineWidth = 1;
    ctx.beginPath();
    ctx.moveTo(M, y);
    ctx.lineTo(W - M, y);
    ctx.stroke();

    const fy = y + 21;
    ctx.font = `600 11.5px ${FONT}`;
    ctx.fillStyle = t.textSec;
    ctx.textAlign = "left";
    ctx.textBaseline = "middle";
    ctx.fillText("Lucent · Antigravity Pulse", M, fy);

    ctx.font = `500 11px ${FONT}`;
    ctx.fillStyle = t.textMut;
    ctx.textAlign = "right";
    ctx.fillText("本机本地日志统计 · 金额按公开 API 费率参考估算", W - M, fy);

    ctx.restore();
    return { width: canvas.width, height: canvas.height, logicalWidth: W, logicalHeight: H };
  }

  function renderToDataURL(data, options = {}) {
    const canvas = document.createElement("canvas");
    const meta = renderShareCard(canvas, data, options);
    if (!meta) return null;
    return {
      dataUrl: canvas.toDataURL("image/png"),
      ...meta
    };
  }

  window.AntigravityShareCard = {
    themes: THEMES,
    render: renderShareCard,
    renderToDataURL
  };
})();
