"use strict";

const copy = {
  refresh: ["刷新设备", "Refresh devices"],
  dock: ["贴边收起为小浮窗", "Dock to screen edge"],
  close: ["关闭并停止会话 (Esc)", "Close & stop session (Esc)"],
  openSettings: ["打开插件设置", "Settings"],
  incomingBadge: ["收到传输请求", "Incoming"],
  decline: ["拒绝", "Decline"],
  accept: ["接收保存", "Accept"],
  retrySend: ["验证并发送", "Send with PIN"],
  cancel: ["取消", "Cancel"],
  queueTitle: ["待发送内容", "Send Queue"],
  loadClipboard: ["载入剪贴板", "Clipboard"],
  clearQueue: ["清空", "Clear"],
  dropHint: ["拖入文件/文件夹（支持从访达或文件中转站直接拖入），或输入文字后点击下方设备发送。", "Drop files/folders from Finder or File Shelf, or type text below, then click a peer to send."],
  textPlaceholder: ["输入要发送给手机/电脑的文字或链接…", "Type text or URL to beam to a nearby device…"],
  peersTitle: ["附近设备", "Nearby Devices"],
  deepScan: ["深度扫描", "Deep Scan"],
  scanning: ["扫描中…", "Scanning…"],
  addIP: ["+ IP 直连", "+ IP"],
  connect: ["连接", "Probe"],
  peersEmpty: ["正在局域网广播发现设备… 请确保手机或电脑已打开 LocalSend，或点击「深度扫描 / + IP 直连」。", "Searching LAN peers… Open LocalSend on your phone/PC, or use Deep Scan / + IP."],
  activityTitle: ["传输历史", "History"],
  filterAll: ["全部", "All"],
  filterRecv: ["接收", "Received"],
  filterSend: ["发送", "Sent"],
  historyEmpty: ["暂无收发历史 · 传输记录会自动保存在本机", "No transfer history yet · Saved locally on this Mac"],
  fileMoved: ["原文件已移动或删除", "Original file moved or deleted"],
  clear: ["清空", "Clear"],
  receiveModeLabel: ["接收策略", "Receive Mode"],
  modePrompt: ["确认接收", "Ask to Save"],
  modeQuick: ["自动保存", "Quick Save"],
  modeSendOnly: ["仅发送", "Send Only"],
  saveToPrefix: ["保存到 ", "Save to "],
  sendBtn: ["发送", "Send"],
  waitingPeer: ["等待对方确认…", "Waiting for peer…"],
  sending: ["正在发送", "Sending"],
  receiving: ["正在接收", "Receiving"],
  sentDone: ["已发送完成", "Sent"],
  recvDone: ["已接收保存", "Received"],
  failed: ["传输失败", "Failed"],
  copyText: ["复制内容", "Copy"],
  openFile: ["打开", "Open"],
  quickLook: ["快速预览", "Quick Look"],
  revealFinder: ["在访达中显示", "Show in Finder"],
  revealedAppNote: ["出于安全考虑已在访达中定位该应用/安装包", "Revealed app/installer in Finder for safety"],
  fileMissing: ["文件不存在或已被移动", "File not found or moved"],
  pinImage: ["原位钉屏", "Pin Image"],
  openReader: ["阅读窗打开", "Reader"],
  openURL: ["打开链接", "Open URL"],
  lumaBadge: ["流光随行", "LumaLink"],
  favBadge: ["收藏", "Fav"],
  pinPromptPrefix: ["目标设备需要 PIN 口令：", "PIN required by "],
  dropHere: ["松手加入发送队列", "Drop to queue files"],
  noPayload: ["请先拖入文件或输入要发送的内容", "Drop files or enter text first"],
  clipEmpty: ["剪贴板为空或未授权读取", "Clipboard empty or access denied"],
  routedOK: ["已发送到：", "Routed to: "],
  routedFail: ["无法转交插件（请检查权限）", "Could not route (check permission)"],
  enableLinkage: ["开启跨插件联动", "Enable Plugin Linkage"],
  copiedOK: ["已写入剪贴板", "Copied to clipboard"],
  probeFail: ["未找到该 IP 上的 LocalSend 设备", "No LocalSend device at that IP"],
  probeOK: ["已连接并收藏：", "Connected & saved: "],
  netBlocked: ["网络权限未启用，无法发现局域网设备。", "Network scope is disabled; LAN discovery cannot run."],
  sessionStopped: ["会话已停止，点击刷新重连。", "Session stopped. Click refresh to reconnect."],
  pillIdle: ["就绪 · 悬停展开", "Ready · Hover to expand"],
  dockedToast: ["已贴边 · 悬停或拖文件展开", "Docked · Hover or drop to expand"],
  undockedToast: ["已切回自由悬浮窗", "Floating HUD restored"],
  dockUnpin: ["取消贴边（切回自由悬浮窗）", "Undock to free floating HUD"],
};

const host = window.lucent;
const el = id => document.getElementById(id);
const EXPANDED = { width: 436, height: 560 };
const STRIP_SIZES = {
  left: { width: 184, height: 74 },
  right: { width: 184, height: 74 },
  top: { width: 238, height: 56 },
};
const VALID_EDGES = ["left", "right", "top"];
const IMAGE_EXTS = new Set(["png", "jpg", "jpeg", "webp", "gif", "heic", "bmp", "tiff"]);
const READER_EXTS = new Set(["md", "markdown", "txt", "json", "swift", "js", "ts", "py", "sh", "yaml", "yml", "toml", "css", "html"]);

const state = {
  lang: "zh",
  docked: false,
  expanded: true,
  edge: "right",
  dragging: false,
  fileDragging: false,
  morphing: false,
  mouseInside: false,
  ignoreAutoUntil: 0,
  ignoreHoverUntil: 0,
  expandTimer: null,
  retractTimer: null,
  selfInfo: null,
  serverStatus: null,
  peers: [],
  queueFiles: [],
  incoming: null,
  pinRetry: null,
  transfers: [],
  historyFilter: "all",
  scanning: false,
};

const t = key => copy[key][state.lang === "en" ? 1 : 0];

function resolveTheme(env) {
  if (env && (env.appearance || env.theme)) {
    return (env.appearance === "dark" || env.theme === "dark" || env.theme === "prism-pulse") ? "prism-pulse" : "pure-frost";
  }
  return window.matchMedia?.("(prefers-color-scheme: dark)")?.matches ? "prism-pulse" : "pure-frost";
}

function applyLocaleAndTheme(env = host?.env) {
  state.lang = (env?.locale || navigator.language || "zh").toLowerCase().startsWith("en") ? "en" : "zh";
  document.documentElement.lang = state.lang === "en" ? "en" : "zh-Hans";
  document.documentElement.dataset.theme = resolveTheme(env);
  for (const node of document.querySelectorAll("[data-text]")) node.textContent = t(node.dataset.text);
  for (const node of document.querySelectorAll("[data-label]")) {
    node.setAttribute("aria-label", t(node.dataset.label));
    node.title = t(node.dataset.label);
  }
  const textArea = el("text-input");
  if (textArea) textArea.placeholder = t("textPlaceholder");
  renderHeader();
  renderPeers();
  renderTransfers();
  syncDockUI();
}

let toastTimer = null;

function renderIdleFooterHint() {
  const node = el("toast-line");
  if (!node) return;
  node.classList.remove("active");
  const saveDir = state.selfInfo?.saveDirectory;
  node.textContent = saveDir ? `${t("saveToPrefix")}${fileBasename(saveDir)}` : "";
  if (saveDir) node.title = saveDir;
}

function setToast(msg, durationMs = 3000) {
  const node = el("toast-line");
  if (!node) return;
  if (toastTimer) { clearTimeout(toastTimer); toastTimer = null; }
  const clean = (msg || "").trim();
  if (!clean) {
    renderIdleFooterHint();
    return;
  }
  node.textContent = clean;
  node.title = clean;
  node.classList.add("active");
  if (durationMs > 0) {
    toastTimer = setTimeout(() => {
      toastTimer = null;
      renderIdleFooterHint();
    }, durationMs);
  }
}

function formatBytes(bytes) {
  const n = Number(bytes) || 0;
  if (n < 1024) return `${n} B`;
  if (n < 1048576) return `${(n / 1024).toFixed(1)} KB`;
  if (n < 1073741824) return `${(n / 1048576).toFixed(1)} MB`;
  return `${(n / 1073741824).toFixed(2)} GB`;
}

function fileBasename(p) {
  const parts = String(p || "").split("/").filter(Boolean);
  return parts[parts.length - 1] || p;
}

function fileExtension(p) {
  const name = fileBasename(p);
  const idx = name.lastIndexOf(".");
  return idx > 0 ? name.slice(idx + 1).toLowerCase() : "";
}

function showWarning(msg) {
  const box = el("warning-banner");
  const txt = el("warning-text");
  if (!msg) { box.hidden = true; return; }
  txt.textContent = msg;
  box.hidden = false;
}

function renderHeader() {
  const info = state.selfInfo;
  const st = state.serverStatus;
  el("device-alias").textContent = info?.alias || "LocalSend";
  const dot = el("listen-dot");
  const meta = el("listen-meta");
  const ip = info?.ip || "LAN";
  const port = st?.port ?? info?.port ?? 53317;
  const proto = (st?.protocol || info?.protocol || "https").toUpperCase();
  const mode = st?.receiveMode || info?.receiveMode || "prompt";

  if (st?.listening) {
    dot.className = "status-dot live";
    meta.textContent = `${ip}:${port} · ${proto}`;
  } else if (mode === "sendOnly") {
    dot.className = "status-dot warn";
    meta.textContent = `${ip} · ${t("modeSendOnly")}`;
  } else {
    dot.className = "status-dot";
    meta.textContent = `${ip}:${port}`;
  }

  const modeSelect = el("receive-mode-select");
  if (modeSelect) modeSelect.value = mode;
  const modeDot = el("mode-dot");
  if (modeDot) modeDot.dataset.mode = mode;
  if (!toastTimer) renderIdleFooterHint();
  updateMiniPillLabel();
}

function updateMiniPillLabel() {
  const label = el("pill-label");
  const dot = el("pill-dot");
  if (!label) return;
  if (dot) {
    const mode = state.serverStatus?.receiveMode || state.selfInfo?.receiveMode || "prompt";
    dot.className = state.serverStatus?.listening ? "status-dot live" : (mode === "sendOnly" ? "status-dot warn" : "status-dot");
  }
  const active = state.transfers.find(x => x.status === "sending" || x.status === "receiving" || x.status === "waiting");
  if (active) {
    const pct = Math.round((active.fraction || 0) * 100);
    label.textContent = `${active.direction === "send" ? "↑" : "↓"} ${pct}% · ${active.peerAlias || ""}`;
  } else if (state.incoming) {
    label.textContent = `${t("incomingBadge")} · ${state.incoming.senderAlias}`;
  } else if (state.peers.length > 0) {
    label.textContent = state.lang === "en" ? `${state.peers.length} peer(s)` : `${state.peers.length} 台附近设备`;
  } else {
    label.textContent = t("pillIdle");
  }
}

function renderQueue() {
  const chips = el("queue-chips");
  const clearBtn = el("clear-queue-btn");
  chips.innerHTML = "";
  const hasFiles = state.queueFiles.length > 0;
  chips.hidden = !hasFiles;
  clearBtn.hidden = !hasFiles && !el("text-input").value.trim();
  for (const path of state.queueFiles) {
    const chip = document.createElement("span");
    chip.className = "chip";
    const span = document.createElement("span");
    span.textContent = fileBasename(path);
    span.title = path;
    const rm = document.createElement("button");
    rm.type = "button";
    rm.textContent = "×";
    rm.addEventListener("click", () => {
      state.queueFiles = state.queueFiles.filter(p => p !== path);
      renderQueue();
    });
    chip.append(span, rm);
    chips.append(chip);
  }
}

function applyIncomingPayload(payload) {
  if (!payload || typeof payload !== "object") return;
  const ctx = payload.pendingContext || payload;
  if (Array.isArray(ctx.filePaths) && ctx.filePaths.length > 0) {
    const existing = new Set(state.queueFiles);
    for (const p of ctx.filePaths) {
      if (typeof p === "string" && p && !existing.has(p)) {
        state.queueFiles.push(p);
        existing.add(p);
      }
    }
    renderQueue();
    ensureExpandedForInteraction();
  } else if (typeof ctx.url === "string" && ctx.url.trim()) {
    el("text-input").value = ctx.url.trim();
    renderQueue();
    ensureExpandedForInteraction();
  } else if (typeof ctx.text === "string" && ctx.text.trim()) {
    el("text-input").value = ctx.text.trim();
    renderQueue();
    ensureExpandedForInteraction();
  }
}

function renderPeers() {
  const list = el("peers-list");
  const empty = el("peers-empty");
  el("peers-count").textContent = String(state.peers.length);
  list.innerHTML = "";
  empty.hidden = state.peers.length > 0;

  for (const peer of state.peers) {
    const card = document.createElement("div");
    card.className = "peer-card";
    card.role = "button";
    card.tabIndex = 0;

    const left = document.createElement("div");
    left.className = "peer-left";

    const avatar = document.createElement("div");
    avatar.className = "peer-avatar";
    avatar.textContent = (peer.alias || "?").slice(0, 1).toUpperCase();

    const meta = document.createElement("div");
    meta.className = "peer-meta";

    const nameRow = document.createElement("div");
    nameRow.className = "peer-name-row";
    const name = document.createElement("span");
    name.className = "peer-name";
    name.textContent = peer.alias;
    nameRow.append(name);
    if (peer.isLumaLinkPaired) {
      const b = document.createElement("span");
      b.className = "badge ok";
      b.textContent = t("lumaBadge");
      nameRow.append(b);
    }
    if (peer.isFavorite) {
      const b = document.createElement("span");
      b.className = "badge accent";
      b.textContent = t("favBadge");
      nameRow.append(b);
    }

    const sub = document.createElement("div");
    sub.className = "peer-sub";
    sub.textContent = `${peer.ip}:${peer.port} · ${(peer.protocol || "https").toUpperCase()}${peer.deviceModel ? " · " + peer.deviceModel : ""}`;

    meta.append(nameRow, sub);
    left.append(avatar, meta);

    const actions = document.createElement("div");
    actions.className = "peer-actions";
    const favBtn = document.createElement("button");
    favBtn.type = "button";
    favBtn.className = "icon-btn compact";
    favBtn.textContent = peer.isFavorite ? "★" : "☆";
    favBtn.addEventListener("click", ev => {
      ev.stopPropagation();
      host?.session.send({ cmd: "toggleFavorite", fingerprint: peer.fingerprint });
    });
    const sendTag = document.createElement("span");
    sendTag.className = "send-tag";
    sendTag.textContent = t("sendBtn");
    actions.append(favBtn, sendTag);

    card.append(left, actions);
    card.addEventListener("click", () => sendCurrentQueueToPeer(peer));
    card.addEventListener("keydown", ev => { if (ev.key === "Enter") sendCurrentQueueToPeer(peer); });
    list.append(card);
  }
  updateMiniPillLabel();
}

function sendCurrentQueueToPeer(peer, pin = null) {
  const files = [...state.queueFiles];
  const textVal = el("text-input").value.trim();
  if (files.length === 0 && !textVal) {
    setToast(t("noPayload"));
    return;
  }
  const transferId = `tx-${Date.now()}-${Math.random().toString(16).slice(2, 6)}`;
  const isFileSend = files.length > 0;
  upsertTransfer({
    id: transferId,
    direction: "send",
    peerAlias: peer.alias,
    peerFingerprint: peer.fingerprint,
    status: "waiting",
    fraction: 0,
    totalBytes: 0,
    payloadFiles: files,
    payloadText: isFileSend ? "" : textVal,
    label: isFileSend ? `${files.length} 个文件` : textVal.slice(0, 48),
  });
  if (isFileSend) {
    host?.session.send({ cmd: "sendFiles", transferId, targetFingerprint: peer.fingerprint, filePaths: files, pin });
  } else {
    host?.session.send({ cmd: "sendText", transferId, targetFingerprint: peer.fingerprint, text: textVal, pin });
  }
}

function formatHistoryTime(epochSec) {
  const sec = Number(epochSec);
  if (!Number.isFinite(sec) || sec <= 0) return "";
  const d = new Date(sec * 1000);
  const now = new Date();
  const hh = String(d.getHours()).padStart(2, "0");
  const mm = String(d.getMinutes()).padStart(2, "0");
  const sameDay = d.getFullYear() === now.getFullYear() && d.getMonth() === now.getMonth() && d.getDate() === now.getDate();
  if (sameDay) return `${hh}:${mm}`;
  return `${d.getMonth() + 1}/${d.getDate()} ${hh}:${mm}`;
}

function hydrateHistoryItem(raw) {
  const paths = Array.isArray(raw.existingPaths) ? raw.existingPaths : (Array.isArray(raw.filePaths) ? raw.filePaths : []);
  const allPaths = Array.isArray(raw.filePaths) ? raw.filePaths : paths;
  const txt = typeof raw.text === "string" ? raw.text : "";
  const kind = raw.kind || (txt ? "text" : "file");
  const routePayload = txt
    ? { kind, text: txt, url: kind === "url" ? txt : undefined, source: "local-send" }
    : (paths.length > 0 ? { kind, filePaths: paths, source: "local-send" } : null);
  return {
    id: raw.id || `hist-${Math.random().toString(16).slice(2, 8)}`,
    direction: raw.direction === "send" ? "send" : "receive",
    peerAlias: raw.peerAlias || "",
    status: "completed",
    fraction: 1.0,
    totalBytes: Number(raw.totalBytes) || 0,
    label: raw.label || (txt ? txt.slice(0, 48) : (allPaths.length === 1 ? fileBasename(allPaths[0]) : `${allPaths.length} 个文件`)),
    receivedPaths: paths,
    allPaths,
    missingFiles: Boolean(raw.missingFiles),
    receivedText: txt,
    receivedKind: kind,
    timestampEpoch: Number(raw.timestampEpoch) || 0,
    routePayload,
    matchedPlugins: [],
    fromHistory: true,
  };
}

function mergePersistedHistory(rawItems) {
  const active = state.transfers.filter(x => x.status === "waiting" || x.status === "sending" || x.status === "receiving");
  const existingById = new Map(state.transfers.map(x => [x.id, x]));
  const hydrated = (Array.isArray(rawItems) ? rawItems : []).map(raw => {
    const item = hydrateHistoryItem(raw);
    const prev = existingById.get(item.id);
    if (prev && Array.isArray(prev.matchedPlugins) && prev.matchedPlugins.length > 0) {
      item.matchedPlugins = prev.matchedPlugins;
    }
    return item;
  });
  const activeIds = new Set(active.map(x => x.id));
  state.transfers = [...active, ...hydrated.filter(x => !activeIds.has(x.id))];
  renderTransfers();
  // Enrich recent receive history entries with matched Lucent plugins (without triggering auto-route/auto-copy)
  for (const item of hydrated.slice(0, 6)) {
    if (item.direction === "receive" && item.routePayload && item.matchedPlugins.length === 0) {
      enrichReceivedTransferWithPlugins(item.id, item.routePayload, false);
    }
  }
}

function upsertTransfer(patch) {
  const idx = state.transfers.findIndex(x => x.id === patch.id);
  if (idx >= 0) state.transfers[idx] = Object.assign({}, state.transfers[idx], patch);
  else state.transfers.unshift(patch);
  if (state.transfers.length > 44) state.transfers.length = 44;
  renderTransfers();
}

function renderIncoming() {
  const card = el("incoming-card");
  if (!state.incoming) { card.hidden = true; updateMiniPillLabel(); return; }
  const inc = state.incoming;
  card.hidden = false;
  el("incoming-sender").textContent = `${inc.senderAlias} (${inc.remoteIP || ""})`;
  el("incoming-summary").textContent = `${(inc.files || []).length} 项 · ${formatBytes(inc.totalBytes)}`;
  const list = el("incoming-files");
  list.innerHTML = "";
  for (const f of (inc.files || []).slice(0, 6)) {
    const chip = document.createElement("span");
    chip.className = "chip";
    const sp = document.createElement("span");
    sp.textContent = f.preview && f.fileType?.startsWith("text/") ? f.preview.slice(0, 42) : f.fileName;
    chip.append(sp);
    list.append(chip);
  }
  updateMiniPillLabel();
}

function renderTransfers() {
  const list = el("transfer-list");
  const empty = el("history-empty");
  const clearBtn = el("clear-history-btn");
  const countEl = el("history-count");

  const filtered = state.transfers.filter(item => {
    if (item.status === "waiting" || item.status === "sending" || item.status === "receiving") return true;
    if (state.historyFilter === "receive") return item.direction === "receive";
    if (state.historyFilter === "send") return item.direction === "send";
    return true;
  });

  if (countEl) countEl.textContent = String(filtered.length);
  if (clearBtn) clearBtn.hidden = state.transfers.filter(x => x.status === "completed" || x.status === "failed").length === 0;
  if (empty) empty.hidden = filtered.length > 0;
  list.innerHTML = "";

  for (const item of filtered) {
    const card = document.createElement("div");
    card.className = "glass-card transfer-card";

    const top = document.createElement("div");
    top.className = "transfer-top";
    const metaRow = document.createElement("div");
    metaRow.className = "transfer-meta-row";
    const title = document.createElement("span");
    title.className = "transfer-title";
    const dirArrow = item.direction === "send" ? "↑" : "↓";
    title.textContent = `${dirArrow} ${item.peerAlias || ""} · ${item.label || ""}`;
    metaRow.append(title);
    const timeStr = formatHistoryTime(item.timestampEpoch);
    if (timeStr) {
      const tm = document.createElement("span");
      tm.className = "transfer-time";
      tm.textContent = item.totalBytes > 0 ? `${timeStr} · ${formatBytes(item.totalBytes)}` : timeStr;
      metaRow.append(tm);
    }

    const right = document.createElement("div");
    right.className = "row-actions";
    const statusBadge = document.createElement("span");
    statusBadge.className = item.status === "completed" ? "badge ok" : (item.status === "failed" ? "badge" : "badge accent");
    if (item.status === "waiting") statusBadge.textContent = t("waitingPeer");
    else if (item.status === "sending") statusBadge.textContent = `${Math.round((item.fraction || 0) * 100)}%`;
    else if (item.status === "receiving") statusBadge.textContent = `${Math.round((item.fraction || 0) * 100)}%`;
    else if (item.status === "completed") statusBadge.textContent = item.direction === "send" ? t("sentDone") : t("recvDone");
    else statusBadge.textContent = t("failed");
    right.append(statusBadge);

    if (item.status === "waiting" || item.status === "sending" || item.status === "receiving") {
      const cancelBtn = document.createElement("button");
      cancelBtn.type = "button";
      cancelBtn.className = "pill-btn small";
      cancelBtn.textContent = t("cancel");
      cancelBtn.addEventListener("click", () => {
        host?.session.send({ cmd: "cancelTransfer", transferId: item.id, sessionId: item.id });
      });
      right.append(cancelBtn);
    } else {
      const delBtn = document.createElement("button");
      delBtn.type = "button";
      delBtn.className = "mini-remove-btn";
      delBtn.textContent = "×";
      delBtn.addEventListener("click", () => {
        state.transfers = state.transfers.filter(x => x.id !== item.id);
        renderTransfers();
        host?.session.send({ cmd: "deleteHistoryItem", id: item.id });
      });
      right.append(delBtn);
    }

    top.append(metaRow, right);
    card.append(top);

    if (item.status === "sending" || item.status === "receiving" || item.status === "waiting") {
      const track = document.createElement("div");
      track.className = "progress-track";
      const bar = document.createElement("div");
      bar.className = "progress-bar";
      bar.style.width = `${Math.max(4, Math.round((item.fraction || 0) * 100))}%`;
      track.append(bar);
      card.append(track);
    }

    if (item.error) {
      const errP = document.createElement("p");
      errP.className = "muted-line tiny";
      errP.textContent = item.error;
      card.append(errP);
    }

    if (item.status === "completed") {
      if (item.missingFiles) {
        const missP = document.createElement("p");
        missP.className = "muted-line tiny";
        missP.textContent = t("fileMoved");
        card.append(missP);
      } else if (Array.isArray(item.receivedPaths) && item.receivedPaths.length > 0) {
        const filesRow = document.createElement("div");
        filesRow.className = "received-files";
        for (const p of item.receivedPaths) {
          const fBtn = document.createElement("button");
          fBtn.type = "button";
          fBtn.className = "file-chip-btn";
          fBtn.title = p;
          const sp = document.createElement("span");
          sp.textContent = fileBasename(p);
          fBtn.append(sp);
          fBtn.addEventListener("click", () => invokeFileAction("open", [p]));
          filesRow.append(fBtn);
        }
        card.append(filesRow);
      }
      if (!item.missingFiles) {
        const strip = buildInboundLinkageStrip(item);
        if (strip.childElementCount > 0) card.append(strip);
      }
    }

    list.append(card);
  }
  updateMiniPillLabel();
}

async function invokeFileAction(action, paths) {
  if (!host?.files || !Array.isArray(paths) || paths.length === 0) return;
  const resp = await host.files[action](paths);
  if (!resp?.ok) {
    setToast(resp?.message || t("fileMissing"));
    return;
  }
  if (action === "open" && resp.revealedInstead) {
    setToast(t("revealedAppNote"));
  }
}

function buildInboundLinkageStrip(item) {
  const strip = document.createElement("div");
  strip.className = "route-strip";

  if (item.receivedText) {
    addRoutePill(strip, t("copyText"), "primary", async () => {
      const ok = await callBridgeWithPrompt("clipboard", "write", { text: item.receivedText });
      if (ok?.ok) setToast(t("copiedOK"));
    });
    if (item.receivedKind === "url") {
      addRoutePill(strip, t("openURL"), "neutral", () => host?.openExternal(item.receivedText));
    }
  } else if (Array.isArray(item.receivedPaths) && item.receivedPaths.length > 0) {
    const first = item.receivedPaths[0];
    const ext = fileExtension(first);
    addRoutePill(strip, t("openFile"), "primary", () => invokeFileAction("open", item.receivedPaths));
    addRoutePill(strip, t("quickLook"), "neutral", () => invokeFileAction("quickLook", item.receivedPaths));
    addRoutePill(strip, t("revealFinder"), "neutral", () => invokeFileAction("reveal", item.receivedPaths));
    if (item.receivedPaths.length === 1 && IMAGE_EXTS.has(ext)) {
      addRoutePill(strip, t("pinImage"), "neutral", () => host?.openExternal(`lucent://pin?path=${encodeURIComponent(first)}`));
    }
    if (item.receivedPaths.length === 1 && READER_EXTS.has(ext)) {
      addRoutePill(strip, t("openReader"), "neutral", () => host?.openExternal(`lucent://reader?path=${encodeURIComponent(first)}`));
    }
  }

  for (const plug of item.matchedPlugins || []) {
    addRoutePill(strip, plug.name, "accent", async () => {
      const params = Object.assign({ targetPluginId: plug.id, source: "local-send" }, item.routePayload);
      const resp = await callBridgeWithPrompt("contextRouter", "route", params);
      setToast(resp?.ok ? `${t("routedOK")}${plug.name}` : t("routedFail"));
    });
  }
  if (item.needsRouterPermission && item.routePayload) {
    addRoutePill(strip, t("enableLinkage"), "accent", async () => {
      const resp = await callBridgeWithPrompt("contextRouter", "match", item.routePayload);
      if (resp?.ok && Array.isArray(resp.data?.plugins)) {
        upsertTransfer({ id: item.id, matchedPlugins: resp.data.plugins, needsRouterPermission: false });
      }
    });
  }
  return strip;
}

function addRoutePill(container, label, tone, onClick) {
  const btn = document.createElement("button");
  btn.type = "button";
  btn.className = tone === "primary" ? "route-pill primary" : (tone === "neutral" ? "route-pill neutral" : "route-pill");
  btn.textContent = label;
  btn.addEventListener("click", onClick);
  container.append(btn);
}

async function callBridgeWithPrompt(capability, action, params = {}) {
  if (!host?.bridge) return null;
  let resp = await host.bridge(capability, action, params);
  if (resp && resp.error === "capability_not_granted") {
    const perm = await host.permissions.request(capability);
    if (perm?.granted) resp = await host.bridge(capability, action, params);
  }
  return resp;
}

async function enrichReceivedTransferWithPlugins(transferId, routePayload, allowAutoActions = true) {
  let matched = [];
  let needsPerm = false;
  const resp = await host?.bridge("contextRouter", "match", routePayload);
  if (resp?.ok && Array.isArray(resp.data?.plugins)) {
    matched = resp.data.plugins;
  } else if (resp?.error === "capability_not_granted") {
    needsPerm = true;
  }
  upsertTransfer({ id: transferId, matchedPlugins: matched, needsRouterPermission: needsPerm, routePayload });

  if (!allowAutoActions) return;
  if (state.selfInfo?.autoRouteFilesToShelf && Array.isArray(routePayload.filePaths) && routePayload.filePaths.length > 0) {
    const shelf = matched.find(p => p.id === "file-shelf");
    if (shelf) {
      const r = await host?.bridge("contextRouter", "route", Object.assign({ targetPluginId: shelf.id, source: "local-send" }, routePayload));
      if (r?.ok) setToast(`${t("routedOK")}${shelf.name}`);
    }
  }
  if (state.selfInfo?.autoCopyReceivedText && routePayload.text) {
    const r = await host?.bridge("clipboard", "write", { text: routePayload.text });
    if (r?.ok) setToast(t("copiedOK"));
  }
}

function handleSessionEvent(ev) {
  if (!ev || typeof ev !== "object") return;
  switch (ev.type) {
    case "ready":
      state.selfInfo = ev.self || null;
      state.peers = Array.isArray(ev.peers) ? ev.peers : [];
      if (Array.isArray(ev.history)) mergePersistedHistory(ev.history);
      renderHeader();
      renderPeers();
      break;
    case "history":
      mergePersistedHistory(ev.items);
      break;
    case "serverStatus":
      state.serverStatus = ev;
      showWarning(ev.warning || "");
      renderHeader();
      break;
    case "peers":
      state.peers = Array.isArray(ev.peers) ? ev.peers : [];
      renderPeers();
      break;
    case "scanState":
      state.scanning = Boolean(ev.scanning);
      el("deep-scan-btn").textContent = state.scanning ? t("scanning") : t("deepScan");
      el("deep-scan-btn").disabled = state.scanning;
      break;
    case "probeResult":
      if (ev.ok && ev.peer) {
        setToast(`${t("probeOK")}${ev.peer.alias}`);
        el("manual-ip-box").hidden = true;
      } else {
        setToast(t("probeFail"));
      }
      break;
    case "incomingRequest":
      state.incoming = ev;
      renderIncoming();
      if (state.docked && !state.expanded) {
        expandDockToFull();
        host?.bridge("notifications", "send", { title: "LocalSend", body: `${ev.senderAlias}: ${(ev.files || []).length} item(s)`, sound: true });
      }
      break;
    case "transferProgress": {
      const id = ev.transferId || ev.sessionId;
      upsertTransfer({
        id,
        direction: ev.direction,
        peerAlias: ev.peerAlias,
        status: ev.status || (ev.direction === "send" ? "sending" : "receiving"),
        fraction: ev.fraction || 0,
        totalBytes: ev.totalBytes || 0,
        label: ev.fileName || (ev.direction === "receive" ? formatBytes(ev.totalBytes) : undefined),
      });
      break;
    }
    case "transferPinRequired": {
      state.pinRetry = { transferId: ev.transferId, peerFingerprint: ev.peerFingerprint, peerAlias: ev.peerAlias };
      el("pin-prompt-label").textContent = `${t("pinPromptPrefix")}${ev.peerAlias}`;
      el("pin-input").value = "";
      el("pin-card").hidden = false;
      el("pin-input").focus();
      break;
    }
    case "transferFailed": {
      const id = ev.transferId || ev.sessionId || `err-${Date.now()}`;
      upsertTransfer({ id, direction: ev.direction || "send", peerAlias: ev.peerAlias || "", status: "failed", error: ev.error || t("failed") });
      break;
    }
    case "transferCompleted": {
      const id = ev.transferId || ev.sessionId || `done-${Date.now()}`;
      const paths = Array.isArray(ev.filePaths) ? ev.filePaths : [];
      const txt = typeof ev.text === "string" ? ev.text : "";
      const ts = Number(ev.timestampEpoch) || Math.floor(Date.now() / 1000);
      if (ev.direction === "send") {
        const kind = txt ? (ev.kind || "text") : (paths.length === 1 && IMAGE_EXTS.has(fileExtension(paths[0])) ? "image" : "file");
        const label = txt ? txt.slice(0, 48) : (paths.length === 1 ? fileBasename(paths[0]) : (paths.length > 1 ? `${paths.length} 个文件` : undefined));
        upsertTransfer({
          id, direction: "send", peerAlias: ev.peerAlias, status: "completed", fraction: 1.0,
          totalBytes: Number(ev.totalBytes) || 0, label, receivedPaths: paths, receivedText: txt,
          receivedKind: kind, timestampEpoch: ts,
        });
        state.queueFiles = [];
        el("text-input").value = "";
        renderQueue();
      } else {
        const kind = txt ? (ev.kind || "text") : (paths.length === 1 && IMAGE_EXTS.has(fileExtension(paths[0])) ? "image" : "file");
        const label = txt ? txt.slice(0, 48) : (paths.length === 1 ? fileBasename(paths[0]) : `${paths.length} 个文件`);
        upsertTransfer({
          id, direction: "receive", peerAlias: ev.peerAlias, status: "completed", fraction: 1.0,
          totalBytes: Number(ev.totalBytes) || 0, label, receivedPaths: paths, receivedText: txt,
          receivedKind: kind, timestampEpoch: ts, matchedPlugins: [],
        });
        const routePayload = txt
          ? { kind, text: txt, url: kind === "url" ? txt : undefined, source: "local-send" }
          : { kind, filePaths: paths, source: "local-send" };
        enrichReceivedTransferWithPlugins(id, routePayload, true);
      }
      break;
    }
  }
}

function anchorForEdge(edge) {
  if (edge === "left") return "leftCenter";
  if (edge === "top") return "topCenter";
  return "rightCenter";
}

function stripSizeForEdge(edge) {
  return STRIP_SIZES[edge] || STRIP_SIZES.right;
}

function clearDockTimers() {
  if (state.expandTimer) { clearTimeout(state.expandTimer); state.expandTimer = null; }
  if (state.retractTimer) { clearTimeout(state.retractTimer); state.retractTimer = null; }
}

function syncDockUI() {
  const showFull = state.expanded || !state.docked;
  document.documentElement.dataset.docked = state.docked ? "true" : "false";
  document.documentElement.dataset.expanded = showFull ? "true" : "false";
  document.documentElement.dataset.edge = state.edge;
  el("full-view").hidden = !showFull;
  el("mini-pill").hidden = showFull;
  const dockBtn = el("dock-toggle");
  if (dockBtn) {
    dockBtn.setAttribute("aria-pressed", String(state.docked));
    const tip = state.docked ? t("dockUnpin") : t("dock");
    dockBtn.setAttribute("aria-label", tip);
    dockBtn.title = tip;
  }
  updateMiniPillLabel();
}

function pickNearestDockEdge(edges, threshold = 28) {
  if (!edges) return null;
  const candidates = [
    ["top", Number(edges.distTop)],
    ["left", Number(edges.distLeft)],
    ["right", Number(edges.distRight)],
  ].filter(([, d]) => Number.isFinite(d) && d <= threshold);
  if (candidates.length === 0) return null;
  candidates.sort((a, b) => a[1] - b[1]);
  return candidates[0][0];
}

function isInteractionLocked() {
  if (state.fileDragging || state.dragging || state.incoming || state.pinRetry) return true;
  if (!el("manual-ip-box").hidden) return true;
  const active = document.activeElement;
  return Boolean(active && (active.tagName === "TEXTAREA" || active.tagName === "INPUT" || active.tagName === "SELECT"));
}

async function retractToDockStrip(edgeOverride = null, showHint = false) {
  if (state.morphing) return;
  if (edgeOverride && VALID_EDGES.includes(edgeOverride)) state.edge = edgeOverride;
  clearDockTimers();
  el("shell")?.removeAttribute("data-near-edge");

  state.morphing = true;
  state.docked = true;
  state.expanded = false;
  state.ignoreAutoUntil = Date.now() + 650;
  state.ignoreHoverUntil = Date.now() + 280;
  syncDockUI();

  const sz = stripSizeForEdge(state.edge);
  try {
    const res = await host?.window?.snapToEdge?.(state.edge, {
      width: sz.width,
      height: sz.height,
      margin: 0,
      durationMs: 210,
      easing: "spring",
    });
    if (res?.snappedEdge && VALID_EDGES.includes(res.snappedEdge)) {
      state.edge = res.snappedEdge;
      syncDockUI();
    }
    if (showHint) setToast(t("dockedToast"));
  } finally {
    setTimeout(() => { state.morphing = false; }, 60);
  }
}

async function expandDockToFull() {
  if (!state.docked || state.expanded || state.morphing) return;
  clearDockTimers();
  state.morphing = true;
  state.expanded = true;
  state.ignoreAutoUntil = Date.now() + 500;
  syncDockUI();

  try {
    await host?.window?.morph?.({
      width: EXPANDED.width,
      height: EXPANDED.height,
      anchor: anchorForEdge(state.edge),
      durationMs: 190,
      easing: "spring",
      keepOnScreen: true,
    });
  } finally {
    setTimeout(() => {
      state.morphing = false;
      if (!state.mouseInside && state.docked && state.expanded && !isInteractionLocked()) {
        scheduleDockRetract(280);
      }
    }, 50);
  }
}

async function switchToFreeFloatingFull(showHint = false) {
  if (state.morphing) return;
  clearDockTimers();
  el("shell")?.removeAttribute("data-near-edge");
  const wasCollapsed = !state.expanded;
  state.morphing = true;
  state.docked = false;
  state.expanded = true;
  state.ignoreAutoUntil = Date.now() + 650;
  syncDockUI();

  try {
    if (wasCollapsed) {
      await host?.window?.morph?.({
        width: EXPANDED.width,
        height: EXPANDED.height,
        anchor: anchorForEdge(state.edge),
        durationMs: 200,
        easing: "spring",
        keepOnScreen: true,
      });
    }
    if (showHint) setToast(t("undockedToast"));
  } finally {
    setTimeout(() => { state.morphing = false; }, 50);
  }
}

function ensureExpandedForInteraction() {
  if (state.docked && !state.expanded) {
    expandDockToFull();
  }
}

function scheduleDockExpand(delayMs = 110) {
  if (!state.docked || state.expanded || state.dragging || state.morphing) return;
  if (Date.now() < state.ignoreHoverUntil) return;
  if (state.retractTimer) { clearTimeout(state.retractTimer); state.retractTimer = null; }
  if (state.expandTimer) return;
  state.expandTimer = setTimeout(() => {
    state.expandTimer = null;
    if (state.mouseInside && state.docked && !state.expanded && !state.dragging) {
      expandDockToFull();
    }
  }, delayMs);
}

function scheduleDockRetract(delayMs = 320) {
  if (!state.docked || !state.expanded || isInteractionLocked()) return;
  if (state.expandTimer) { clearTimeout(state.expandTimer); state.expandTimer = null; }
  if (state.retractTimer) clearTimeout(state.retractTimer);
  state.retractTimer = setTimeout(() => {
    state.retractTimer = null;
    if (state.mouseInside || !state.docked || !state.expanded || isInteractionLocked()) return;
    if (state.morphing) { scheduleDockRetract(150); return; }
    retractToDockStrip();
  }, delayMs);
}

async function handleDockToggleButton() {
  if (state.docked) {
    await switchToFreeFloatingFull(true);
    return;
  }
  const frame = await host?.window?.getFrame?.();
  const edges = frame?.edges;
  let targetEdge = state.edge;
  if (edges) {
    const ordered = [
      ["right", Number(edges.distRight)],
      ["left", Number(edges.distLeft)],
      ["top", Number(edges.distTop)],
    ].filter(([, d]) => Number.isFinite(d)).sort((a, b) => a[1] - b[1]);
    if (ordered.length > 0) targetEdge = ordered[0][0];
  }
  await retractToDockStrip(targetEdge, true);
}

async function handleNativeDragEnd(detail) {
  state.dragging = false;
  el("shell")?.removeAttribute("data-near-edge");
  if (state.morphing || Date.now() < state.ignoreAutoUntil) return;
  if (!detail || (detail.movedDistance !== undefined && detail.movedDistance < 4)) return;
  const edges = detail.edges;
  if (!edges) return;

  const near = pickNearestDockEdge(edges, state.docked ? 36 : 28);
  if (near) {
    await retractToDockStrip(near, true);
    return;
  }
  if (state.docked) {
    const minDist = Math.min(Number(edges.distLeft), Number(edges.distRight), Number(edges.distTop));
    if (Number.isFinite(minDist) && minDist > 52) {
      await switchToFreeFloatingFull(true);
    }
  }
}

function wireEdgeDockEvents() {
  host?.window?.setEdgeBehavior?.({ keepOnScreen: true, autoClampOnDrag: true, edgeThreshold: 28 });

  host?.window?.onDragStart?.(() => {
    state.dragging = true;
    clearDockTimers();
  });

  host?.window?.onEdgeProximity?.(detail => {
    const shell = el("shell");
    if (!shell) return;
    if (!state.dragging) { shell.removeAttribute("data-near-edge"); return; }
    const edge = pickNearestDockEdge(detail?.edges || detail, 28);
    if (edge) shell.dataset.nearEdge = edge;
    else shell.removeAttribute("data-near-edge");
  });

  host?.window?.onDragEnd?.(detail => { handleNativeDragEnd(detail); });

  const shell = el("shell");
  if (shell) {
    shell.addEventListener("mouseenter", () => {
      state.mouseInside = true;
      if (state.retractTimer) { clearTimeout(state.retractTimer); state.retractTimer = null; }
      if (state.docked && !state.expanded) scheduleDockExpand(100);
    });
    shell.addEventListener("mouseleave", () => {
      state.mouseInside = false;
      if (state.expandTimer) { clearTimeout(state.expandTimer); state.expandTimer = null; }
      if (state.docked && state.expanded) scheduleDockRetract(320);
    });
  }
}

async function startSession() {
  if (!host?.session) return;
  if (host.env && host.env.networkAllowed === false) {
    showWarning(t("netBlocked"));
    return;
  }
  const resp = await host.session.start(["--session"]);
  if (!resp?.ok) showWarning(resp?.error || t("sessionStopped"));
}

function wireUI() {
  el("refresh-btn").addEventListener("click", async () => {
    const sent = await host?.session.send({ cmd: "refresh" });
    if (!sent?.ok) {
      showWarning("");
      await startSession();
    }
    setToast("…");
  });
  el("dock-toggle").addEventListener("click", () => handleDockToggleButton());
  el("expand-pill").addEventListener("click", () => expandDockToFull());
  const closeAll = () => host?.window.close();
  el("close-win").addEventListener("click", closeAll);
  el("pill-close").addEventListener("click", closeAll);
  el("open-settings-btn").addEventListener("click", () => host?.openExternal("lucent://settings/plugin/local-send"));

  el("paste-clip-btn").addEventListener("click", async () => {
    const resp = await callBridgeWithPrompt("clipboard", "read", {});
    const val = (resp?.data?.text || "").trim();
    if (!val) { setToast(t("clipEmpty")); return; }
    el("text-input").value = val;
    renderQueue();
  });
  el("clear-queue-btn").addEventListener("click", () => {
    state.queueFiles = [];
    el("text-input").value = "";
    renderQueue();
  });
  el("text-input").addEventListener("input", () => renderQueue());

  el("deep-scan-btn").addEventListener("click", () => host?.session.send({ cmd: "deepScan" }));
  el("manual-ip-toggle").addEventListener("click", () => {
    const box = el("manual-ip-box");
    box.hidden = !box.hidden;
    if (!box.hidden) el("manual-ip-input").focus();
  });
  el("manual-ip-go").addEventListener("click", () => {
    const ip = el("manual-ip-input").value.trim();
    const port = Number(el("manual-port-input").value) || 53317;
    if (!ip) return;
    host?.session.send({ cmd: "probeIP", ip, port, saveFavorite: true });
  });

  el("incoming-accept").addEventListener("click", () => {
    if (!state.incoming) return;
    host?.session.send({ cmd: "respondIncoming", sessionId: state.incoming.sessionId, accepted: true });
    state.incoming = null;
    renderIncoming();
  });
  el("incoming-decline").addEventListener("click", () => {
    if (!state.incoming) return;
    host?.session.send({ cmd: "respondIncoming", sessionId: state.incoming.sessionId, accepted: false });
    state.incoming = null;
    renderIncoming();
  });

  el("pin-submit").addEventListener("click", () => {
    const retry = state.pinRetry;
    const pin = el("pin-input").value.trim();
    el("pin-card").hidden = true;
    state.pinRetry = null;
    if (!retry || !pin) return;
    const peer = state.peers.find(p => p.fingerprint === retry.peerFingerprint);
    if (peer) sendCurrentQueueToPeer(peer, pin);
  });
  el("pin-cancel").addEventListener("click", () => { el("pin-card").hidden = true; state.pinRetry = null; });

  el("clear-history-btn").addEventListener("click", () => {
    state.transfers = state.transfers.filter(x => x.status === "sending" || x.status === "receiving" || x.status === "waiting");
    renderTransfers();
    host?.session.send({ cmd: "clearHistory" });
  });

  for (const tab of document.querySelectorAll(".filter-tab")) {
    tab.addEventListener("click", () => {
      state.historyFilter = tab.dataset.filter || "all";
      for (const other of document.querySelectorAll(".filter-tab")) {
        other.classList.toggle("active", other === tab);
      }
      renderTransfers();
    });
  }

  el("receive-mode-select")?.addEventListener("change", ev => {
    const mode = ev.target.value;
    const modeDot = el("mode-dot");
    if (modeDot) modeDot.dataset.mode = mode;
    host?.session.send({ cmd: "setReceiveMode", mode });
    ev.target.blur();
  });

  document.addEventListener("keydown", ev => {
    if (ev.key === "Escape") host?.window.close();
  });
}

function bootstrap() {
  wireUI();
  wireEdgeDockEvents();
  syncDockUI();
  applyLocaleAndTheme(host?.env);
  host?.window?.setPinned?.(true);
  host?.window?.getFrame?.().then(frame => {
    if (!state.docked && frame && (Number(frame.width) < 360 || Number(frame.height) < 420)) {
      host?.window?.morph?.({ width: EXPANDED.width, height: EXPANDED.height, durationMs: 0, keepOnScreen: true });
    }
  });
  if (host?.env?.initialState) applyIncomingPayload(host.env.initialState);

  host?.onEnvChanged?.(env => applyLocaleAndTheme(env));
  host?.window?.onPayload?.(payload => applyIncomingPayload(payload));
  host?.window?.onFileDragState?.(detail => {
    const ov = el("drop-overlay");
    state.fileDragging = Boolean(detail?.active);
    if (!state.fileDragging) {
      ov.hidden = true;
      if (!state.mouseInside && state.docked && state.expanded) scheduleDockRetract(320);
      return;
    }
    ensureExpandedForInteraction();
    el("drop-overlay-text").textContent = `${t("dropHere")} (${detail.count || 1})`;
    ov.hidden = false;
  });
  host?.window?.onFilesDropped?.(detail => {
    state.fileDragging = false;
    el("drop-overlay").hidden = true;
    if (Array.isArray(detail?.filePaths) && detail.filePaths.length > 0) {
      applyIncomingPayload({ filePaths: detail.filePaths });
    }
  });
  host?.session?.onEvent?.(handleSessionEvent);
  host?.session?.onExit?.(info => {
    showWarning(info?.stderr?.trim() || t("sessionStopped"));
  });

  startSession();
}

bootstrap();
