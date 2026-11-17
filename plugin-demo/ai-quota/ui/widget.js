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

  function renderRingCard(label, pct, centerText) {
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
          <text class="ring-center" x="23" y="26.5" text-anchor="middle">${centerText}</text>
        </svg>
        <div class="ring-label">${label}</div>
      </div>
    `;
  }

  function renderTelemetry(data) {
    if (!data || !Array.isArray(data.providers)) return;
    lastSummary = data.statusSummary || "";
    subEl.textContent = `${data.updatedClock || ""} · ${data.cacheState || "live"} · ${data.intervalSeconds || 30}s`;

    const ringItems = [];
    const rowHTML = [];

    for (const p of data.providers) {
      const pct = typeof p.primaryPercent === "number" ? Math.round(p.primaryPercent) : null;
      if (ringItems.length < 4) {
        const center = pct !== null ? `${pct}%` : (p.shortValue || "—").slice(0, 5);
        ringItems.push(renderRingCard(p.shortName, pct, center));
      }

      const badgeCls = !p.active ? "off" : (pct !== null && pct <= 30 ? "warn" : "");
      const barBlock = pct !== null
        ? `<div class="bar-track"><div class="bar-fill" style="width:${Math.max(2, pct)}%"></div></div>`
        : "";
      rowHTML.push(`
        <div class="prov-row">
          <div class="prov-top">
            <span class="prov-name">${escapeHTML(p.title)}</span>
            <span class="prov-badge ${badgeCls}">${escapeHTML(p.badge || "READY")}</span>
          </div>
          ${barBlock}
          <div class="prov-meta">${escapeHTML(p.detail || "")}</div>
        </div>
      `);
    }

    ringsEl.innerHTML = ringItems.join("");
    listEl.innerHTML = rowHTML.join("");
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
    if (sdk) await sdk.window.resize(392, isCompact ? 156 : 488, true);
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

  refresh(false);
  setInterval(() => {
    if (!document.hidden) refresh(false);
  }, 30000);
})();
