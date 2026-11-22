"use strict";

const copy = {
  appTitle: ["窗口分屏与工作区", "Window Snap & Workspaces"],
  refresh: ["刷新窗口状态", "Refresh windows"],
  pin: ["窗口置顶", "Pin on top"],
  dock: ["贴边收起为胶囊", "Dock as edge pill"],
  close: ["关闭 (Esc)", "Close (Esc)"],
  undo: ["撤销", "Undo"],
  undoTitle: ["撤销上次分屏位置", "Restore previous window frame"],
  quickSnap: ["快速分屏（直接作用于前台窗口）", "Quick Snap (acts on active window)"],
  gapLabel: ["边距", "Gap"],
  workspaces: ["多屏工作区布局", "Multi-Display Workspaces"],
  captureNew: ["+ 捕获当前布局", "+ Capture Layout"],
  captureCurrent: ["捕获当前桌面排版", "Capture Current Desktop"],
  empty: ["把当前多个显示器上的应用窗口排版保存为工作区，之后按 ⌥Space 搜名字一键恢复。", "Save your multi-display window arrangement as a reusable workspace and restore it anytime from Search."],
  workspaceName: ["工作区名称", "Workspace name"],
  includedWindows: ["收录的应用窗口", "Included windows"],
  launchMissing: ["恢复时自动启动未打开的应用", "Auto-launch closed apps on restore"],
  cancel: ["取消", "Cancel"],
  save: ["保存布局", "Save"],
  remove: ["删除", "Delete"],
  removeTitle: ["删除这套工作区布局？", "Delete this workspace?"],
  captureDialogTitle: ["捕获当前多屏工作区", "Capture Workspace Layout"],
  editDialogTitle: ["编辑工作区布局", "Edit Workspace"],
  grantCapability: ["允许窗口布局控制", "Allow Window Control"],
  grantAccessibility: ["授予系统「辅助功能」权限", "Grant Accessibility Access"],
  openAccessibility: ["打开隐私设置", "Open System Settings"],
  permCapText: ["允许此插件通过 Lucent 宿主调整前台应用窗口的位置与尺寸（零后台常驻）。", "Allow this plugin to arrange windows via the Lucent host bridge (zero background daemon)."],
  permAccText: ["还需在 macOS「系统设置 › 隐私与安全性 › 辅助功能」中勾选 Lucent，即可执行分屏与多屏工作区恢复。", "Enable Lucent in macOS System Settings › Privacy & Security › Accessibility to move and resize windows."],
  noTarget: ["未检测到前台应用窗口", "No active app window"],
  noTargetSub: ["切到任意应用后，直接点击下方分屏格即可生效", "Focus any app window and click a snap tile below"],
  mainDisplay: ["主屏", "Main"],
  displaysCount: ["块显示器", "displays"],
  singleDisplay: ["单显示器", "1 display"],
  windowsCount: ["个窗口", "windows"],
  saved: ["工作区已保存，可在 ⌥Space 直接搜索恢复", "Workspace saved & indexed for Search"],
  applied: ["已应用", "Applied"],
  restored: ["已恢复上次窗口位置", "Window restored"],
  nothingToUndo: ["当前窗口暂无可撤销记录", "Nothing to restore for this window"],
  noWindowsCaptured: ["当前桌面没有可收录的常规应用窗口。", "No standard application windows found to capture."],
  selectAtLeastOne: ["请至少勾选一个应用窗口。", "Select at least one window to include."],
  failed: ["操作未能完成，请重试。", "Couldn’t complete the action. Please try again."],
  hostOnly: ["请从 Lucent 打开此面板。", "Open this panel from Lucent."],
  favorite: ["设为常用工作区", "Mark as favorite"],
  unfavorite: ["取消常用", "Remove favorite"],
  edit: ["编辑", "Edit"],
  deleteLabel: ["删除", "Delete"],
  fallbackNotice: ["部分外接屏已断开，已自动折回当前屏幕", "Disconnected displays folded onto active screen"],
  skippedPrefix: ["跳过未打开：", "Skipped closed: "],
  arrangedCount: ["已排列窗口：", "Arranged windows: "],
  quickNames: [
    ["编程双屏", "会议协作", "写作专注", "研发调试"],
    ["Coding Dual", "Meeting", "Focus Write", "Debug Setup"]
  ],
};

const SNAP_ACTIONS = [
  { id: "leftHalf", zh: "左半", en: "Left", rect: [2, 2, 11.5, 15] },
  { id: "rightHalf", zh: "右半", en: "Right", rect: [14.5, 2, 11.5, 15] },
  { id: "topHalf", zh: "上半", en: "Top", rect: [2, 2, 24, 7] },
  { id: "bottomHalf", zh: "下半", en: "Bottom", rect: [2, 10, 24, 7] },
  { id: "maximize", zh: "最大化", en: "Max", rect: [2, 2, 24, 15] },
  { id: "center", zh: "居中", en: "Center", rect: [5.5, 4, 17, 11] },

  { id: "leftThird", zh: "左1/3", en: "L 1/3", rect: [2, 2, 7.2, 15] },
  { id: "centerThird", zh: "中1/3", en: "C 1/3", rect: [10.4, 2, 7.2, 15] },
  { id: "rightThird", zh: "右1/3", en: "R 1/3", rect: [18.8, 2, 7.2, 15] },
  { id: "leftTwoThirds", zh: "左2/3", en: "L 2/3", rect: [2, 2, 15.6, 15] },
  { id: "rightTwoThirds", zh: "右2/3", en: "R 2/3", rect: [10.4, 2, 15.6, 15] },
  { id: "almostMax", zh: "微缩", en: "90%", rect: [3.5, 3, 21, 13] },

  { id: "topLeft", zh: "左上", en: "Top L", rect: [2, 2, 11.5, 7] },
  { id: "topRight", zh: "右上", en: "Top R", rect: [14.5, 2, 11.5, 7] },
  { id: "bottomLeft", zh: "左下", en: "Bot L", rect: [2, 10, 11.5, 7] },
  { id: "bottomRight", zh: "右下", en: "Bot R", rect: [14.5, 10, 11.5, 7] },
  { id: "prevDisplay", zh: "上一屏", en: "Prev", arrow: "left" },
  { id: "nextDisplay", zh: "下一屏", en: "Next", arrow: "right" },
];

const SVG_NS = "http://www.w3.org/2000/svg";
const ICONS = {
  star: "M12 3.5 14.6 8.8l5.9.9-4.3 4.2 1 5.8L12 17l-5.2 2.7 1-5.8-4.3-4.2 5.9-.9Z",
  edit: "M16.5 4.5 19.5 7.5 8 19H5v-3L16.5 4.5Z",
  trash: "M4 7h16M9 7V4h6v3M7 7l1 13h8l1-13",
};

const host = window.lucent;
const el = id => document.getElementById(id);
const EXPANDED = { width: 440, height: 556 };
const PILL = { width: 212, height: 74 };
const darkMedia = window.matchMedia?.("(prefers-color-scheme: dark)") || null;
const reducedMotionMedia = window.matchMedia?.("(prefers-reduced-motion: reduce)") || null;

const state = {
  language: "zh",
  capGranted: false,
  accGranted: false,
  settingsURL: "",
  displays: [],
  windows: [],
  activeWindow: null,
  canUndo: false,
  workspaces: [],
  favorite: null,
  gap: 8,
  launchMissing: true,
  showHud: true,
  busy: false,
  pinned: host?.env?.pinOnTop ?? true,
  isPill: false,
  dockedEdge: "right",
  focusWorkspace: host?.env?.initialState?.workspaceID || null,
  editingId: null,
  draftSlots: [],
  removingId: null,
};

const t = key => copy[key][state.language === "en" ? 1 : 0];

function svgEl(tag, attrs = {}) {
  const node = document.createElementNS(SVG_NS, tag);
  for (const [k, v] of Object.entries(attrs)) node.setAttribute(k, String(v));
  return node;
}

function iconSvg(pathData) {
  const s = svgEl("svg", { viewBox: "0 0 24 24", "aria-hidden": "true" });
  s.append(svgEl("path", { d: pathData }));
  return s;
}

function resolveTheme(env) {
  if (env && (env.appearance || env.theme)) {
    const dark = env.appearance === "dark" || env.theme === "dark" || env.theme === "prism-pulse";
    return dark ? "prism-pulse" : "pure-frost";
  }
  return darkMedia?.matches ? "prism-pulse" : "pure-frost";
}

function translate(env = host?.env) {
  state.language = (env?.locale || navigator.language).startsWith("en") ? "en" : "zh";
  document.documentElement.lang = state.language === "en" ? "en" : "zh-Hans";
  document.documentElement.dataset.theme = resolveTheme(env);
  state.pinned = env?.pinOnTop ?? state.pinned;
  el("pin-toggle")?.setAttribute("aria-pressed", String(Boolean(state.pinned)));
  for (const node of document.querySelectorAll("[data-text]")) node.textContent = t(node.dataset.text);
  for (const node of document.querySelectorAll("[data-label]")) {
    node.setAttribute("aria-label", t(node.dataset.label));
    node.title = t(node.dataset.label);
  }
  renderSnapGrid();
}

function syncModalScrim() {
  el("modal-scrim").hidden = !(el("editor")?.open || el("remove-dialog")?.open);
}

function showStatus(message, warning = false, ok = false) {
  const node = el("status");
  node.textContent = message || "";
  node.hidden = !message;
  node.classList.toggle("warning", warning);
  node.classList.toggle("ok", ok && !warning);
}

function spawnRipple(target, ev) {
  if (!target || target.disabled || reducedMotionMedia?.matches) return;
  const r = target.getBoundingClientRect();
  if (r.width <= 0 || r.height <= 0) return;
  const x = ev?.clientX ? ev.clientX - r.left : r.width / 2;
  const y = ev?.clientY ? ev.clientY - r.top : r.height / 2;
  const dot = document.createElement("span");
  dot.className = "lg-ripple";
  dot.style.setProperty("--rx", `${x.toFixed(1)}px`);
  dot.style.setProperty("--ry", `${y.toFixed(1)}px`);
  dot.style.setProperty("--rs", `${Math.max(r.width, r.height).toFixed(1)}px`);
  target.append(dot);
  setTimeout(() => dot.remove(), 460);
}

function bindLiquidInteractions() {
  const shell = el("shell");
  if (shell) {
    let raf = 0, lx = 0, ly = 0;
    shell.addEventListener("pointermove", ev => {
      if (reducedMotionMedia?.matches) return;
      lx = ev.clientX; ly = ev.clientY;
      if (raf) return;
      raf = requestAnimationFrame(() => {
        raf = 0;
        const rect = shell.getBoundingClientRect();
        if (rect.width <= 0 || rect.height <= 0) return;
        shell.style.setProperty("--mx", `${(((lx - rect.left) / rect.width) * 100).toFixed(1)}%`);
        shell.style.setProperty("--my", `${(((ly - rect.top) / rect.height) * 100).toFixed(1)}%`);
        shell.style.setProperty("--sheen-op", "1");
      });
    });
    shell.addEventListener("pointerleave", () => shell.style.setProperty("--sheen-op", "0"));
  }
  document.addEventListener("pointerdown", ev => {
    const btn = ev.target?.closest?.(".snap-btn, .pill-action, .primary, .subtle, .undo-btn, .icon-btn");
    if (btn) spawnRipple(btn, ev);
  });
}

function makeSnapGlyph(action) {
  const svg = svgEl("svg", { class: "snap-glyph", viewBox: "0 0 28 19", "aria-hidden": "true" });
  if (action.arrow) {
    svg.append(svgEl("rect", { x: 1, y: 2.5, width: 11.5, height: 14, rx: 2.2, fill: "var(--wire-bg)", stroke: "var(--wire-frame)", "stroke-width": 1.1 }));
    svg.append(svgEl("rect", { x: 15.5, y: 2.5, width: 11.5, height: 14, rx: 2.2, fill: "var(--wire-bg)", stroke: "var(--wire-frame)", "stroke-width": 1.1 }));
    const d = action.arrow === "right" ? "M10.5 9.5h7m-2.5-2.6 2.6 2.6-2.6 2.6" : "M17.5 9.5h-7m2.5-2.6-2.6 2.6 2.6 2.6";
    svg.append(svgEl("path", { d, fill: "none", stroke: "var(--wire-fill)", "stroke-width": 1.8, "stroke-linecap": "round", "stroke-linejoin": "round" }));
    return svg;
  }
  svg.append(svgEl("rect", { x: 0.75, y: 0.75, width: 26.5, height: 17.5, rx: 3.2, fill: "var(--wire-bg)", stroke: "var(--wire-frame)", "stroke-width": 1.1 }));
  const [x, y, w, h] = action.rect;
  svg.append(svgEl("rect", { x, y, width: w, height: h, rx: 1.8, fill: "var(--wire-fill)" }));
  return svg;
}

function renderSnapGrid() {
  const grid = el("snap-grid");
  if (!grid) return;
  grid.replaceChildren();
  const multiDisplay = state.displays.length > 1;
  for (const action of SNAP_ACTIONS) {
    const btn = document.createElement("button");
    btn.type = "button";
    btn.className = "snap-btn";
    btn.dataset.preset = action.id;
    const label = state.language === "en" ? action.en : action.zh;
    btn.title = label;
    btn.disabled = state.busy || ((action.id === "nextDisplay" || action.id === "prevDisplay") && !multiDisplay && state.displays.length > 0);
    btn.append(makeSnapGlyph(action));
    const span = document.createElement("span");
    span.className = "snap-label";
    span.textContent = label;
    btn.append(span);
    btn.addEventListener("click", () => runSnap(action.id, btn));
    grid.append(btn);
  }
}

function renderWorkspacePreviewSvg(ws) {
  const count = Math.max(1, Math.min(3, ws.displayCount || 1));
  const svg = svgEl("svg", { viewBox: "0 0 60 32", "aria-hidden": "true" });
  const gap = 3;
  const screenW = (60 - gap * (count - 1)) / count;
  for (let i = 0; i < count; i++) {
    const sx = i * (screenW + gap);
    svg.append(svgEl("rect", {
      x: sx + 0.5, y: 1.5, width: screenW - 1, height: 29, rx: 3,
      fill: "var(--wire-bg)", stroke: "var(--wire-frame)", "stroke-width": 1
    }));
  }
  const slots = Array.isArray(ws.slots) ? ws.slots.slice(0, 8) : [];
  for (const s of slots) {
    const dIdx = Math.min(count - 1, Math.max(0, s.displayIndex || 0));
    const sx = dIdx * (screenW + gap) + 2;
    const sw = screenW - 4;
    const sh = 25;
    const rx = Math.max(0, Math.min(0.9, Number(s.rx) || 0));
    const ry = Math.max(0, Math.min(0.9, Number(s.ry) || 0));
    const rw = Math.max(0.14, Math.min(1 - rx, Number(s.rw) || 0.5));
    const rh = Math.max(0.18, Math.min(1 - ry, Number(s.rh) || 0.5));
    svg.append(svgEl("rect", {
      x: (sx + rx * sw).toFixed(1),
      y: (3.5 + ry * sh).toFixed(1),
      width: Math.max(3, rw * sw - 0.8).toFixed(1),
      height: Math.max(3, rh * sh - 0.8).toFixed(1),
      rx: 1.3,
      fill: "var(--wire-fill)",
      "fill-opacity": 0.78
    }));
  }
  return svg;
}

function renderHeaderAndTarget() {
  const count = state.displays.length;
  if (count > 1) {
    el("display-summary").textContent = `${count} ${t("displaysCount")} · ${state.windows.length} ${t("windowsCount")}`;
  } else if (count === 1) {
    const d = state.displays[0];
    el("display-summary").textContent = `${d.name} (${d.frame.width}×${d.frame.height})`;
  } else {
    el("display-summary").textContent = t("singleDisplay");
  }

  const ready = state.capGranted && state.accGranted;
  const permBox = el("permission");
  permBox.hidden = ready;
  if (!ready) {
    el("permission-text").textContent = state.capGranted ? t("permAccText") : t("permCapText");
    el("grant").textContent = state.capGranted ? t("grantAccessibility") : t("grantCapability");
    el("open-settings").hidden = !(state.capGranted && !state.accGranted && state.settingsURL);
  }

  const win = state.activeWindow;
  const dot = el("target-dot");
  if (ready && win) {
    dot.classList.remove("idle");
    el("target-app").textContent = win.appName;
    const disp = win.displayName ? `${win.displayName} · ` : "";
    el("target-sub").textContent = `${disp}${win.title}`;
    el("pill-label").textContent = win.appName;
  } else {
    dot.classList.add("idle");
    el("target-app").textContent = t("noTarget");
    el("target-sub").textContent = t("noTargetSub");
    el("pill-label").textContent = t("appTitle");
  }

  el("undo-snap").disabled = state.busy || !ready || !state.canUndo;
  for (const chip of document.querySelectorAll(".gap-chip")) {
    const g = Number(chip.dataset.gap);
    chip.classList.toggle("active", Math.abs(state.gap - g) <= 2);
  }
}

function renderWorkspaces() {
  const list = el("workspace-list");
  list.replaceChildren();
  el("empty").hidden = state.workspaces.length > 0;
  for (const ws of state.workspaces) {
    const card = document.createElement("div");
    card.className = "ws-card" + (state.focusWorkspace === ws.id ? " focused" : "");
    card.tabIndex = 0;
    card.setAttribute("role", "button");

    const preview = document.createElement("div");
    preview.className = "ws-preview";
    preview.append(renderWorkspacePreviewSvg(ws));

    const meta = document.createElement("div");
    meta.className = "ws-meta";
    const row = document.createElement("div");
    row.className = "ws-title-row";
    const name = document.createElement("span");
    name.className = "ws-name";
    name.textContent = ws.name;
    const badge = document.createElement("span");
    badge.className = "ws-badge";
    const dc = ws.displayCount || 1;
    badge.textContent = state.language === "en" ? `${dc}D · ${ws.slots.length}W` : `${dc}屏 · ${ws.slots.length}窗`;
    row.append(name, badge);

    const apps = document.createElement("div");
    apps.className = "ws-apps";
    const uniq = [...new Set(ws.slots.map(s => s.appName).filter(Boolean))];
    apps.textContent = uniq.slice(0, 4).join(" · ") + (uniq.length > 4 ? ` +${uniq.length - 4}` : "");
    meta.append(row, apps);

    const tools = document.createElement("div");
    tools.className = "ws-tools";

    const isFav = state.favorite === ws.id;
    const favBtn = document.createElement("button");
    favBtn.type = "button";
    favBtn.className = "tool-btn" + (isFav ? " starred" : "");
    favBtn.title = t(isFav ? "unfavorite" : "favorite");
    favBtn.append(iconSvg(ICONS.star));
    favBtn.addEventListener("click", ev => { ev.stopPropagation(); modifyWorkspace("--set-favorite", ws.id); });

    const editBtn = document.createElement("button");
    editBtn.type = "button";
    editBtn.className = "tool-btn";
    editBtn.title = t("edit");
    editBtn.append(iconSvg(ICONS.edit));
    editBtn.addEventListener("click", ev => { ev.stopPropagation(); openEditor(ws); });

    const delBtn = document.createElement("button");
    delBtn.type = "button";
    delBtn.className = "tool-btn danger-hover";
    delBtn.title = t("deleteLabel");
    delBtn.append(iconSvg(ICONS.trash));
    delBtn.addEventListener("click", ev => {
      ev.stopPropagation();
      state.removingId = ws.id;
      el("remove-name").textContent = ws.name;
      el("remove-dialog").showModal();
      syncModalScrim();
    });

    tools.append(favBtn, editBtn, delBtn);
    card.append(preview, meta, tools);
    card.addEventListener("click", () => applyWorkspace(ws));
    card.addEventListener("keydown", ev => {
      if (ev.key === "Enter" || ev.key === " ") { ev.preventDefault(); applyWorkspace(ws); }
    });
    list.append(card);
  }
}

function render() {
  renderHeaderAndTarget();
  renderSnapGrid();
  renderWorkspaces();
}

function acceptDocument(res) {
  if (!res?.ok || !res.data) throw new Error(res?.data?.error || t("failed"));
  const d = res.data;
  state.workspaces = Array.isArray(d.workspaces) ? d.workspaces : [];
  state.favorite = d.favorite || null;
  if (typeof d.configGap === "number") state.gap = d.configGap;
  if (typeof d.configLaunchMissing === "boolean") state.launchMissing = d.configLaunchMissing;
  if (typeof d.configShowHud === "boolean") state.showHud = d.configShowHud;
}

async function loadDocument() {
  const res = await host.run(["--list"]);
  acceptDocument(res);
}

async function refreshSystem() {
  const perm = await host.permissions.status();
  const granted = Array.isArray(perm?.grantedCapabilities) ? perm.grantedCapabilities : [];
  state.capGranted = granted.includes("windowControl");
  if (!state.capGranted) {
    state.accGranted = false;
    state.activeWindow = null;
    state.windows = [];
    render();
    return;
  }
  const resp = await host.bridge("windowControl", "status", {});
  if (resp?.ok && resp.data) {
    state.accGranted = Boolean(resp.data.accessibilityGranted);
    state.settingsURL = resp.data.settingsURL || "";
    state.displays = Array.isArray(resp.data.displays) ? resp.data.displays : [];
    state.windows = Array.isArray(resp.data.windows) ? resp.data.windows : [];
    state.activeWindow = resp.data.activeWindow || null;
    state.canUndo = Boolean(resp.data.canUndo);
  }
  render();
}

async function requestPermission() {
  const res = await host.permissions.request("windowControl");
  if (res?.settingsURL) state.settingsURL = res.settingsURL;
  await refreshSystem();
  if (state.capGranted && !state.accGranted) {
    showStatus(t("permAccText"), true);
    return false;
  }
  if (state.capGranted && state.accGranted) {
    showStatus("");
    return true;
  }
  return false;
}

async function runSnap(preset, buttonNode = null) {
  if (state.busy) return;
  if ((!state.capGranted || !state.accGranted) && !(await requestPermission())) return;
  state.busy = true;
  try {
    const resp = await host.bridge("windowControl", "snap", {
      preset,
      gap: state.gap,
      showFeedback: state.showHud,
    });
    if (!resp?.ok) {
      if (resp?.error === "tcc_not_granted") await requestPermission();
      else showStatus(resp?.message || t("failed"), true);
      return;
    }
    const st = resp.data?.status;
    if (st === "applied") {
      if (buttonNode) {
        buttonNode.classList.add("is-flash");
        setTimeout(() => buttonNode.classList.remove("is-flash"), 420);
      }
      showStatus("✓ " + (resp.data?.message || t("applied")), false, true);
    } else if (st === "nothing_to_restore") {
      showStatus(t("nothingToUndo"), true);
    } else {
      showStatus(resp.data?.message || t("noTarget"), true);
    }
  } finally {
    state.busy = false;
    await refreshSystem();
  }
}

async function applyWorkspace(ws) {
  if (state.busy) return;
  if ((!state.capGranted || !state.accGranted) && !(await requestPermission())) return;
  state.busy = true;
  render();
  try {
    const resp = await host.bridge("windowControl", "applyWorkspace", {
      name: ws.name,
      slots: ws.slots,
      gap: state.gap,
      launchMissing: state.launchMissing,
      showFeedback: state.showHud,
    });
    if (!resp?.ok) {
      showStatus(resp?.message || t("failed"), true);
      return;
    }
    const d = resp.data || {};
    state.focusWorkspace = ws.id;
    const notes = [`${t("arrangedCount")}${d.movedCount || 0}`];
    if (d.usedFallbackDisplay) notes.push(t("fallbackNotice"));
    if (Array.isArray(d.missingApps) && d.missingApps.length) {
      notes.push(t("skippedPrefix") + d.missingApps.slice(0, 3).join("、"));
    }
    showStatus((d.movedCount > 0 ? "✓ " : "") + notes.join(" · "), d.movedCount === 0, d.movedCount > 0);
  } finally {
    state.busy = false;
    await refreshSystem();
  }
}

async function openEditor(existing = null) {
  if (!existing && (!state.capGranted || !state.accGranted)) {
    if (!(await requestPermission())) return;
  }
  await refreshSystem();
  state.editingId = existing ? existing.id : null;
  el("editor-title").textContent = t(existing ? "editDialogTitle" : "captureDialogTitle");
  el("ws-name").value = existing ? existing.name : "";
  el("launch-missing").checked = state.launchMissing;
  el("form-error").hidden = true;

  const chips = el("quick-names");
  chips.replaceChildren();
  const suggestions = t("quickNames");
  for (const label of suggestions) {
    const b = document.createElement("button");
    b.type = "button";
    b.className = "quick-chip";
    b.textContent = label;
    b.addEventListener("click", () => { el("ws-name").value = label; el("ws-name").focus(); });
    chips.append(b);
  }

  if (existing) {
    state.draftSlots = existing.slots.map(s => ({ ...s, included: true }));
  } else {
    const visible = state.windows.filter(w => !w.isMinimized);
    state.draftSlots = visible.map(w => ({
      bundleID: w.bundleID,
      appName: w.appName,
      windowTitle: w.title,
      windowIndex: w.windowIndex,
      displayIndex: w.displayIndex,
      displayID: w.displayID,
      displayName: w.displayName,
      rx: w.rx, ry: w.ry, rw: w.rw, rh: w.rh,
      included: true,
    }));
  }
  renderSlotCheckboxes();
  if (!existing && state.draftSlots.length === 0) {
    el("form-error").textContent = t("noWindowsCaptured");
    el("form-error").hidden = false;
  }
  el("editor").showModal();
  syncModalScrim();
  el("ws-name").focus();
}

function renderSlotCheckboxes() {
  const list = el("slot-list");
  list.replaceChildren();
  const updateCount = () => {
    const checked = state.draftSlots.filter(s => s.included).length;
    el("slot-count").textContent = `${checked}/${state.draftSlots.length}`;
  };
  for (const slot of state.draftSlots) {
    const row = document.createElement("label");
    row.className = "slot-row";
    const cb = document.createElement("input");
    cb.type = "checkbox";
    cb.checked = slot.included;
    cb.addEventListener("change", () => { slot.included = cb.checked; updateCount(); });
    const copyBox = document.createElement("div");
    copyBox.className = "slot-row-copy";
    const app = document.createElement("div");
    app.className = "slot-row-app";
    app.textContent = slot.appName;
    const sub = document.createElement("div");
    sub.className = "slot-row-sub";
    const disp = slot.displayName || `${t("mainDisplay")} #${(slot.displayIndex || 0) + 1}`;
    const pct = `${Math.round((slot.rw || 0.5) * 100)}%×${Math.round((slot.rh || 0.5) * 100)}%`;
    sub.textContent = `${disp} · ${pct} · ${slot.windowTitle || slot.appName}`;
    copyBox.append(app, sub);
    row.append(cb, copyBox);
    list.append(row);
  }
  updateCount();
}

function newUUID() {
  if (typeof crypto.randomUUID === "function") return crypto.randomUUID().toUpperCase();
  const b = crypto.getRandomValues(new Uint8Array(16));
  b[6] = (b[6] & 15) | 64; b[8] = (b[8] & 63) | 128;
  const h = Array.from(b, x => x.toString(16).padStart(2, "0")).join("");
  return [h.slice(0, 8), h.slice(8, 12), h.slice(12, 16), h.slice(16, 20), h.slice(20)].join("-").toUpperCase();
}

async function saveWorkspace(ev) {
  ev.preventDefault();
  if (state.busy) return;
  const name = el("ws-name").value.trim();
  if (!name) { el("ws-name").focus(); return; }
  const chosen = state.draftSlots.filter(s => s.included).map(({ included, ...rest }) => rest);
  if (chosen.length === 0) {
    el("form-error").textContent = t("selectAtLeastOne");
    el("form-error").hidden = false;
    return;
  }
  const usedDisplays = new Set(chosen.map(s => s.displayID ?? s.displayIndex));
  const payload = {
    id: state.editingId || newUUID(),
    name,
    displayCount: Math.max(1, usedDisplays.size),
    slots: chosen,
    updatedAt: new Date().toISOString(),
  };
  state.busy = true;
  el("save").disabled = true;
  try {
    const launchFlag = el("launch-missing").checked;
    if (launchFlag !== state.launchMissing) {
      acceptDocument(await host.run(["--set-launch-missing", String(launchFlag)]));
    }
    acceptDocument(await host.run(["--save-workspace"], JSON.stringify(payload)));
    state.focusWorkspace = payload.id;
    el("editor").close();
    syncModalScrim();
    showStatus("✓ " + t("saved"), false, true);
  } catch (err) {
    el("form-error").textContent = err.message || t("failed");
    el("form-error").hidden = false;
  } finally {
    state.busy = false;
    el("save").disabled = false;
    render();
  }
}

async function modifyWorkspace(cmd, id) {
  if (state.busy) return;
  state.busy = true;
  render();
  try {
    acceptDocument(await host.run([cmd, id]));
    showStatus("");
  } catch (err) {
    showStatus(err.message || t("failed"), true);
  } finally {
    state.busy = false;
    render();
  }
}

async function setGap(nextGap) {
  state.gap = nextGap;
  renderHeaderAndTarget();
  try {
    acceptDocument(await host.run(["--set-gap", String(nextGap)]));
  } catch (_) {}
}

async function setPillMode(toPill, edgeHint = null) {
  state.isPill = toPill;
  if (edgeHint === "left" || edgeHint === "right") state.dockedEdge = edgeHint;
  document.documentElement.dataset.mode = toPill ? "pill" : "expanded";
  el("mini-pill").hidden = !toPill;
  el("full-view").hidden = toPill;
  if (!host?.window) return;
  const anchor = state.dockedEdge === "left" ? "topLeft" : "topRight";
  if (toPill) {
    await host.window.snapToEdge(state.dockedEdge, { width: PILL.width, height: PILL.height, margin: 10, durationMs: 320, easing: "spring", animate: true });
  } else {
    await host.window.morph({ width: EXPANDED.width, height: EXPANDED.height, anchor, durationMs: 320, easing: "spring", animate: true, keepOnScreen: true });
  }
}

function handlePayload(payload) {
  if (!payload) return;
  if (payload.message) showStatus(payload.message, true);
  if (payload.workspaceID) state.focusWorkspace = payload.workspaceID;
  if (payload.openCapture) {
    if (state.isPill) setPillMode(false);
    openEditor(null);
  }
  render();
}

translate();
bindLiquidInteractions();
darkMedia?.addEventListener?.("change", () => translate(host?.env));

if (host) {
  el("refresh").addEventListener("click", () => {
    const btn = el("refresh");
    btn.classList.remove("is-spinning"); void btn.offsetWidth; btn.classList.add("is-spinning");
    setTimeout(() => btn.classList.remove("is-spinning"), 540);
    refreshSystem();
  });
  el("grant").addEventListener("click", () => requestPermission());
  el("open-settings").addEventListener("click", () => { if (state.settingsURL) host.openURL(state.settingsURL); });
  el("undo-snap").addEventListener("click", () => runSnap("restore"));
  el("capture-btn").addEventListener("click", () => openEditor(null));
  el("capture-empty").addEventListener("click", () => openEditor(null));
  el("cancel").addEventListener("click", () => { el("editor").close(); syncModalScrim(); });
  el("editor").addEventListener("close", syncModalScrim);
  el("editor").addEventListener("cancel", syncModalScrim);
  el("workspace-form").addEventListener("submit", saveWorkspace);
  el("close-win").addEventListener("click", () => host.window.close());
  el("pill-close").addEventListener("click", () => host.window.close());

  for (const chip of document.querySelectorAll(".gap-chip")) {
    chip.addEventListener("click", () => setGap(Number(chip.dataset.gap)));
  }

  {
    const expandPill = el("expand-pill");
    let dragged = false;
    expandPill.addEventListener("mousedown", ev => {
      if (ev.button !== 0) return;
      dragged = false;
      const sx = ev.clientX, sy = ev.clientY;
      const cleanup = () => { window.removeEventListener("mousemove", onMove); window.removeEventListener("mouseup", cleanup); };
      const onMove = mv => {
        if (Math.hypot(mv.clientX - sx, mv.clientY - sy) >= 4) { dragged = true; cleanup(); host.window.startDrag(); }
      };
      window.addEventListener("mousemove", onMove);
      window.addEventListener("mouseup", cleanup);
    });
    expandPill.addEventListener("click", () => { if (dragged) { dragged = false; return; } setPillMode(false); });
  }

  el("dock-toggle").addEventListener("click", async () => {
    const frame = await host.window.getFrame();
    await setPillMode(true, frame?.nearestEdge === "left" ? "left" : "right");
  });
  el("pin-toggle").addEventListener("click", async () => {
    const res = await host.window.setPinned(!state.pinned);
    if (res?.ok) {
      state.pinned = Boolean(res.pinned);
      el("pin-toggle").setAttribute("aria-pressed", String(state.pinned));
    }
  });
  el("grip-bar").addEventListener("dblclick", () => host.window.resetFrame());

  el("remove-dialog").addEventListener("close", () => {
    syncModalScrim();
    if (el("remove-dialog").returnValue === "remove" && state.removingId) {
      modifyWorkspace("--delete-workspace", state.removingId);
    }
    el("remove-dialog").returnValue = "";
    state.removingId = null;
  });
  el("remove-dialog").addEventListener("cancel", syncModalScrim);

  document.addEventListener("keydown", ev => {
    if (ev.key === "Escape" && !el("editor").open && !el("remove-dialog").open) {
      host.window.close();
    }
  });

  host.window.onDragEnd(detail => {
    if (detail?.nearEdge === "left" || detail?.nearEdge === "right") {
      state.dockedEdge = detail.nearEdge;
      host.window.snapToEdge(detail.nearEdge, { margin: 10, durationMs: 300, easing: "spring", animate: true });
    }
  });
  host.window.onPayload?.(handlePayload);
  host.onEnvChanged(env => { translate(env || host.env); refreshSystem(); });
  window.addEventListener("focus", () => { if (!state.busy && !el("editor").open) refreshSystem(); });
  setInterval(() => { if (!document.hidden && !state.busy && !el("editor").open) refreshSystem(); }, 2800);

  Promise.all([loadDocument(), refreshSystem()])
    .then(() => {
      render();
      handlePayload(host.env.initialState);
    })
    .catch(err => showStatus(err.message || t("failed"), true));
} else {
  showStatus(t("hostOnly"), true);
}
