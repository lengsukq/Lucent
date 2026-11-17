(function () {
  const sdk = window.lumakey;
  const isEn = sdk && sdk.env && String(sdk.env.locale || "").toLowerCase().startsWith("en");

  const shell = document.getElementById("hud-shell");
  const titleEl = document.getElementById("hud-title");
  const subEl = document.getElementById("hud-sub");
  const dotEl = document.getElementById("live-dot");
  const ringsEl = document.getElementById("rings-strip");
  const listEl = document.getElementById("provider-list");
  const btnCompact = document.getElementById("btn-compact");
  const btnPin = document.getElementById("btn-pin");
  const btnRefresh = document.getElementById("btn-refresh");
  const btnClose = document.getElementById("btn-close");
  const btnNotify = document.getElementById("btn-notify");
  const btnSettings = document.getElementById("btn-settings");
  const opacitySlider = document.getElementById("opacity-slider");

  let isCompact = false;
  let isPinned = sdk && sdk.env ? Boolean(sdk.env.pinOnTop) : true;
  let lastSummary = "";
  let refreshTimer = null;
  let currentIntervalMs = 30000;

  if (isEn) {
    titleEl.textContent = "AI Quota Glass HUD";
    subEl.textContent = "Sampling local CLIs…";
    btnNotify.textContent = "Notify Summary";
    btnSettings.textContent = "API Keys";
  }

  function ringColor(pct) {
    if (pct === null || pct === undefined) return "#64748b";
    if (pct <= 20) return "#f43f5e";
    if (pct <= 45) return "#f59e0b";
    return "#10b981";
  }

  function renderRingCard(label, pct, centerText, subValue) {
    const r = 18;
    const c = 2 * Math.PI * r;
    const safePct = pct === null ? 0 : Math.max(0, Math.min(100, pct));
    const offset = c * (1 - safePct / 100);
    const stroke = ringColor(pct);
    return `
      <div class="ring-card">
        <svg class="ring-svg" viewBox="0 0 46 46">
          <circle class="ring-track" cx="23" cy="23" r="${r}"></circle>
          <circle class="ring-fill" cx="23" cy="23" r="${r}"
            stroke="${stroke}" stroke-dasharray="${c.toFixed(1)}" stroke-dashoffset="${offset.toFixed(1)}"></circle>
          <text class="ring-center" x="23" y="26.5" text-anchor="middle">${escapeHTML(centerText)}</text>
        </svg>
        <div class="ring-info">
          <div class="ring-label">${escapeHTML(label)}</div>
          <div class="ring-sub">${escapeHTML(subValue || centerText)}</div>
        </div>
      </div>
    `;
  }

  let visibleProviderCount = 0;

  async function syncWindowSizeForMode(animate) {
    if (!sdk) return;
    if (!isCompact) {
      await sdk.window.resize(412, 514, animate);
      return;
    }
    const targetW = visibleProviderCount <= 2 ? 336 : 412;
    await new Promise((r) => requestAnimationFrame(() => requestAnimationFrame(r)));
    const measuredShellH = Math.ceil(shell.getBoundingClientRect().height);
    const targetH = Math.max(128, Math.min(220, measuredShellH + 42));
    await sdk.window.resize(targetW, targetH, animate);
  }

  function renderTelemetry(data) {
    if (!data || !Array.isArray(data.providers)) return;
    lastSummary = data.statusSummary || "";
    const hiddenNote = data.hiddenCount > 0 ? (isEn ? ` · ${data.hiddenCount} hidden` : ` · 已隐藏 ${data.hiddenCount} 项未安装`) : "";
    subEl.textContent = `${data.updatedClock || ""} · ${data.cacheState || "live"}${hiddenNote}`;

    const ringItems = [];
    const rowHTML = [];
    visibleProviderCount = data.providers.length;

    for (const p of data.providers) {
      const pct = typeof p.primaryPercent === "number" ? Math.round(p.primaryPercent) : null;
      if (ringItems.length < 4) {
        const center = pct !== null ? `${pct}%` : (p.shortValue || "—").slice(0, 5);
        const subTxt = pct !== null ? `${pct}% · ${p.badge || ""}`.replace(/ · $/, "") : (p.shortValue || p.badge || "Ready");
        ringItems.push(renderRingCard(p.shortName, pct, center, subTxt));
      }

      const badgeCls = !p.active ? "off" : (pct !== null && pct <= 30 ? "warn" : "");
      const barBlock = pct !== null
        ? `<div class="bar-track"><div class="bar-fill" style="width:${Math.max(2, pct)}%"></div></div>`
        : "";
      const setupHint = (!p.active && p.id === "deepseek") ? ' data-open-settings="1" style="cursor:pointer"' : "";
      rowHTML.push(`
        <div class="prov-row"${setupHint}>
          <div class="prov-top">
            <span class="prov-name">${escapeHTML(p.title)}</span>
            <span class="prov-badge ${badgeCls}">${escapeHTML(p.badge || "READY")}</span>
          </div>
          ${barBlock}
          <div class="prov-meta">${escapeHTML(p.detail || "")}</div>
        </div>
      `);
    }

    if (ringItems.length === 0) {
      ringsEl.innerHTML = `<div class="rings-empty" data-open-settings="1">${
        isEn ? "No active AI CLIs or keys found · Click to configure" : "暂未检测到本机 CLI 或密钥 · 点击去设置"
      }</div>`;
      listEl.innerHTML = `<div class="prov-row" data-open-settings="1" style="cursor:pointer">
        <div class="prov-top">
          <span class="prov-name">${isEn ? "Nothing installed yet" : "当前无已激活的监控源"}</span>
          <span class="prov-badge off">SETUP</span>
        </div>
        <div class="prov-meta">${
          isEn ? "Add DeepSeek API Key or turn on 'Show uninstalled providers' in Settings." : "可在设置填入 DeepSeek Key，或开启「显示未安装/未配置的监控源」。"
        }</div>
      </div>`;
    } else {
      ringsEl.innerHTML = ringItems.join("");
      listEl.innerHTML = rowHTML.join("");
    }
    document.querySelectorAll('[data-open-settings="1"]').forEach((el) => {
      el.addEventListener("click", () => sdk && sdk.openExternal("lumakey://settings/plugin/ai-quota"));
    });

    if (isCompact) {
      syncWindowSizeForMode(false);
    }

    const nextMs = Math.max(15000, Number(data.intervalSeconds || 30) * 1000);
    if (nextMs !== currentIntervalMs) {
      currentIntervalMs = nextMs;
      scheduleAutoRefresh();
    }
  }

  function escapeHTML(str) {
    return String(str || "")
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;");
  }

  async function refresh(force = false) {
    if (!sdk) return;
    dotEl.classList.add("loading");
    try {
      const args = force ? ["--json", "--refresh"] : ["--json"];
      const res = await sdk.run(args, "");
      if (res && res.ok && res.data) {
        renderTelemetry(res.data);
      } else {
        subEl.textContent = (res && res.error) ? res.error : "Sample failed";
      }
    } catch (err) {
      subEl.textContent = String(err);
    } finally {
      dotEl.classList.remove("loading");
    }
  }

  btnCompact.addEventListener("click", async () => {
    isCompact = !isCompact;
    shell.classList.toggle("compact", isCompact);
    await syncWindowSizeForMode(true);
  });

  btnPin.addEventListener("click", async () => {
    isPinned = !isPinned;
    btnPin.classList.toggle("active", isPinned);
    if (sdk) await sdk.window.setPinned(isPinned);
  });

  btnRefresh.addEventListener("click", () => refresh(true));
  btnClose.addEventListener("click", () => sdk && sdk.window.close());
  btnSettings.addEventListener("click", () => sdk && sdk.openExternal("lumakey://settings/plugin/ai-quota"));

  opacitySlider.addEventListener("input", () => {
    const val = Number(opacitySlider.value) / 100;
    if (sdk) sdk.window.setOpacity(val);
  });

  btnNotify.addEventListener("click", async () => {
    if (!sdk) return;
    const perm = await sdk.permissions.request("notifications");
    if (perm && perm.granted) {
      await sdk.bridge("notifications", "send", {
        title: isEn ? "AI Quota HUD Snapshot" : "AI 额度挂件实时摘要",
        body: lastSummary || (isEn ? "All configured AI CLIs checked." : "已完成本机 AI CLI 与余额采样"),
        sound: false
      });
    }
  });

  function scheduleAutoRefresh() {
    if (refreshTimer) clearInterval(refreshTimer);
    refreshTimer = setInterval(() => {
      if (!document.hidden) refresh(false);
    }, currentIntervalMs);
  }

  refresh(false);
  scheduleAutoRefresh();
})();
