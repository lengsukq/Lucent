"use strict";

const copy = {
  appTitle: ["一键音频组合", "Audio Presets"],
  current: ["点击卡片直切设备", "Click a card to switch"],
  refresh: ["刷新设备", "Refresh devices"],
  pin: ["窗口置顶", "Pin on top"],
  dock: ["贴边收起为胶囊", "Dock as edge pill"],
  close: ["关闭 (Esc)", "Close (Esc)"],
  input: ["麦克风", "Microphone"],
  output: ["扬声器", "Speakers"],
  pickOutput: ["选择默认扬声器", "Choose default speakers"],
  pickInput: ["选择默认麦克风", "Choose default microphone"],
  permissionText: ["允许查看和切换系统默认音频设备。", "Allow access to read and switch default audio devices."],
  grant: ["允许访问", "Allow access"],
  presets: ["已保存的组合", "Saved presets"],
  new: ["+ 新建组合", "+ New"],
  empty: ["把常用的扬声器与麦克风保存成一套，之后可在主搜索框一键切换。", "Save a speaker and microphone pair to switch instantly from Search."],
  saveCurrent: ["保存当前组合", "Save current setup"],
  name: ["组合名称", "Preset name"],
  cancel: ["取消", "Cancel"],
  save: ["保存", "Save"],
  remove: ["删除", "Delete"],
  edit: ["编辑组合", "Edit preset"],
  favorite: ["设为常用", "Mark as favorite"],
  unfavorite: ["取消常用", "Remove favorite"],
  removeTitle: ["删除这个组合？", "Delete this preset?"],
  unavailable: ["不可用", "Unavailable"],
  disconnected: ["未连接", "Disconnected"],
  noDevice: ["未检测到设备", "No device detected"],
  select: ["选择设备", "Choose a device"],
  switching: ["正在切换…", "Switching…"],
  applied: ["已切换", "Applied"],
  active: ["当前生效", "Active"],
  restored: ["切换失败，之前的设备已恢复。", "Switch failed. Previous devices restored."],
  partial: ["未能完全恢复，请核对当前设备。", "Couldn’t fully restore audio. Check current devices."],
  failed: ["无法完成操作，请重试。", "Couldn’t complete the action. Try again."],
  pending: ["正在读取…", "Checking…"],
  denied: ["尚未允许访问音频设备。", "Audio device access hasn’t been granted."],
  host: ["请从 Lucent 打开此面板。", "Open this panel from Lucent."],
  saved: ["组合已保存", "Preset saved"],
};

const SVG_NS = "http://www.w3.org/2000/svg";
const ICONS = {
  starFilled: "M12 3.5 14.6 8.8l5.9.9-4.3 4.2 1 5.8L12 17l-5.2 2.7 1-5.8-4.3-4.2 5.9-.9Z",
  starOutline: "M12 3.5 14.6 8.8l5.9.9-4.3 4.2 1 5.8L12 17l-5.2 2.7 1-5.8-4.3-4.2 5.9-.9Z",
  edit: "M16.5 4.5 19.5 7.5 8 19H5v-3L16.5 4.5Z",
  trash: "M4 7h16M9 7V4h6v3M7 7l1 13h8l1-13",
  check: "M5 13l4 4L19 7",
};

const host = window.lucent;
const element = id => document.getElementById(id);
const EXPANDED = { width: 396, height: 456 };
const PILL = { width: 178, height: 50 };

const state = {
  language: "zh",
  devices: [],
  actual: {},
  presets: [],
  favorite: null,
  editable: null,
  removing: null,
  pickerDirection: null,
  busy: false,
  permission: false,
  pinned: host?.env?.pinOnTop ?? true,
  isPill: false,
  dockedEdge: "right",
  focusPreset: host?.env?.initialState?.presetID || null,
};

const text = key => copy[key][state.language === "en" ? 1 : 0];

function makeSvg(pathData, filled = false) {
  const svg = document.createElementNS(SVG_NS, "svg");
  svg.setAttribute("viewBox", "0 0 24 24");
  svg.setAttribute("aria-hidden", "true");
  const path = document.createElementNS(SVG_NS, "path");
  path.setAttribute("d", pathData);
  if (filled) path.setAttribute("fill", "currentColor");
  svg.append(path);
  return svg;
}

function translate() {
  state.language = (host?.env?.locale || navigator.language).startsWith("en") ? "en" : "zh";
  document.documentElement.lang = state.language === "en" ? "en" : "zh-Hans";
  const hostTheme = host?.env?.theme;
  if (hostTheme === "prism-pulse" || hostTheme === "pure-frost") {
    document.documentElement.dataset.theme = hostTheme;
  } else {
    document.documentElement.dataset.theme = window.matchMedia("(prefers-color-scheme: dark)").matches
      ? "prism-pulse" : "pure-frost";
  }
  state.pinned = host?.env?.pinOnTop ?? state.pinned;
  element("pin-toggle")?.setAttribute("aria-pressed", String(Boolean(state.pinned)));
  for (const node of document.querySelectorAll("[data-text]")) node.textContent = text(node.dataset.text);
  for (const node of document.querySelectorAll("[data-label]")) {
    node.setAttribute("aria-label", text(node.dataset.label));
    node.title = text(node.dataset.label);
  }
}

function showStatus(message, warning = false) {
  const node = element("status");
  node.textContent = message || "";
  node.hidden = !message;
  node.classList.toggle("warning", warning);
}

function deviceFor(uid, direction) {
  return state.devices.find(item => item.uid === uid && item[direction]);
}

function missingDevices(preset) {
  return ["output", "input"]
    .filter(direction => !deviceFor(preset[direction + "UID"], direction))
    .map(direction => preset[direction + "Name"] || text(direction));
}

function activePreset() {
  if (!state.permission) return null;
  return state.presets.find(p => p.inputUID === state.actual.inputUID && p.outputUID === state.actual.outputUID) || null;
}

function showActual() {
  for (const direction of ["output", "input"]) {
    const uid = state.actual[direction + "UID"];
    const device = state.devices.find(item => item.uid === uid);
    const name = device?.name || (uid ? text("unavailable") : text("noDevice"));
    element(direction).textContent = state.permission ? name : "—";
    element(direction).title = state.permission ? name : "";
    element(direction + "-card").disabled = state.busy;
    element(direction + "-card").classList.toggle("open", state.pickerDirection === direction);
  }
  const active = activePreset();
  const outName = state.devices.find(d => d.uid === state.actual.outputUID)?.name;
  element("pill-label").textContent = active?.name || outName || text("appTitle");
  element("permission").hidden = state.permission;
  element("new").disabled = !state.permission || state.busy;
  element("refresh").disabled = state.busy || !state.permission;
  element("save-current").disabled = state.busy || !state.actual.inputUID || !state.actual.outputUID;
  renderPicker();
}

function renderPicker() {
  const picker = element("quick-picker");
  const dir = state.pickerDirection;
  if (!dir || !state.permission) {
    picker.hidden = true;
    return;
  }
  picker.hidden = false;
  element("picker-title").textContent = text(dir === "output" ? "pickOutput" : "pickInput");
  const list = element("picker-list");
  const frag = document.createDocumentFragment();
  const candidates = state.devices.filter(d => d[dir]);
  const currentUID = state.actual[dir + "UID"];
  for (const device of candidates) {
    const item = document.createElement("button");
    item.type = "button";
    item.className = "picker-item" + (device.uid === currentUID ? " selected" : "");
    item.disabled = state.busy;
    const label = document.createElement("span");
    label.textContent = device.name;
    item.append(label);
    if (device.uid === currentUID) item.append(makeSvg(ICONS.check));
    item.addEventListener("click", () => applySingleDevice(dir, device));
    frag.append(item);
  }
  list.replaceChildren(frag);
}

function makeIconButton(label, iconPath, handler, { filled = false, extraClass = "" } = {}) {
  const node = document.createElement("button");
  node.type = "button";
  node.className = ("icon-btn " + extraClass).trim();
  node.title = label;
  node.setAttribute("aria-label", label);
  node.append(makeSvg(iconPath, filled));
  node.addEventListener("click", handler);
  return node;
}

function render() {
  showActual();
  const list = element("preset-list");
  const focused = list.contains(document.activeElement) ? document.activeElement.dataset.key : null;
  const fragment = document.createDocumentFragment();
  for (const preset of state.presets) {
    const row = document.createElement("article");
    row.className = "preset glass-card";
    const connected = state.permission;
    const missing = connected ? missingDevices(preset) : [];
    const active = connected && preset.inputUID === state.actual.inputUID && preset.outputUID === state.actual.outputUID;
    row.classList.toggle("active", active);

    const applyBtn = document.createElement("button");
    applyBtn.type = "button";
    applyBtn.className = "preset-apply";
    applyBtn.id = "preset-" + preset.id;
    applyBtn.dataset.key = preset.id + "-apply";
    applyBtn.disabled = state.busy;
    applyBtn.addEventListener("click", () => applyPreset(preset));

    const title = document.createElement("span");
    title.className = "preset-name";
    if (active) {
      const dot = document.createElement("span");
      dot.className = "active-dot";
      title.append(dot);
    }
    title.append(document.createTextNode(preset.name));

    const subtitle = document.createElement("span");
    subtitle.className = "preset-detail" + (missing.length ? " warning" : "");
    subtitle.textContent = missing.length
      ? `${text("disconnected")}: ${missing.join(" · ")}`
      : `${preset.outputName} · ${preset.inputName}`;
    applyBtn.title = subtitle.textContent;
    applyBtn.append(title, subtitle);

    const tools = document.createElement("div");
    tools.className = "preset-tools";
    const fav = preset.id === state.favorite;
    const star = makeIconButton(
      text(fav ? "unfavorite" : "favorite"),
      fav ? ICONS.starFilled : ICONS.starOutline,
      () => modify("--set-favorite", preset.id),
      { filled: fav }
    );
    star.setAttribute("aria-pressed", String(fav));
    const edit = makeIconButton(text("edit"), ICONS.edit, () => openEditor(preset));
    const remove = makeIconButton(text("remove"), ICONS.trash, () => {
      state.removing = preset.id;
      element("remove-name").textContent = preset.name;
      element("remove-dialog").showModal();
    }, { extraClass: "danger-btn" });

    [star, edit, remove].forEach((control, index) => {
      control.dataset.key = preset.id + "-" + index;
      control.disabled = state.busy || (control === edit && !state.permission);
      tools.append(control);
    });
    row.append(applyBtn, tools);
    fragment.append(row);
  }
  list.replaceChildren(fragment);
  element("empty").hidden = state.presets.length > 0 || !state.permission;
  if (focused) [...list.querySelectorAll("button")].find(c => c.dataset.key === focused)?.focus();
  if (state.focusPreset) {
    element("preset-" + state.focusPreset)?.focus();
    state.focusPreset = null;
  }
}

async function loadPresets() {
  acceptDocument(await host.run(["--list"]));
}

function acceptDocument(response) {
  if (!response?.ok || !response.data || response.data.error) throw new Error(response?.data?.error || text("failed"));
  state.presets = response.data.presets || [];
  state.favorite = response.data.favorite || null;
}

async function refresh() {
  state.permission = (host?.env?.grantedCapabilities || []).includes("audioDevices");
  if (!state.permission) {
    state.devices = [];
    state.actual = {};
  } else {
    const response = await host.bridge("audioDevices", "list");
    if (!response?.ok) {
      if (response?.error === "capability_not_granted") state.permission = false;
      render();
      throw new Error(text(state.permission ? "failed" : "denied"));
    }
    state.devices = response.data.devices || [];
    state.actual = response.data.actual || {};
  }
  render();
}

async function grant() {
  const response = await host.permissions.request("audioDevices");
  if (!response?.granted) {
    showStatus(text("denied"), true);
    return false;
  }
  if (!host.env.grantedCapabilities.includes("audioDevices")) host.env.grantedCapabilities.push("audioDevices");
  await refresh();
  showStatus("");
  return true;
}

function flashCard(direction) {
  const card = element(direction + "-card");
  card.classList.add("flash");
  setTimeout(() => card.classList.remove("flash"), 650);
}

async function applySingleDevice(direction, device) {
  if (state.busy) return;
  state.busy = true;
  state.pickerDirection = null;
  showStatus(text("switching"));
  render();
  try {
    const response = await host.bridge("audioDevices", "setDevice", { direction, uid: device.uid });
    if (!response?.ok) throw new Error(text("failed"));
    const data = response.data;
    state.actual = data.actual || {};
    await refresh();
    if (data.status === "applied") {
      showStatus("✓ " + text("applied") + " · " + device.name);
      flashCard(direction);
    } else if (data.status === "unavailable") {
      showStatus(text("disconnected") + ": " + device.name, true);
    } else {
      showStatus(text(data.status === "restored" ? "restored" : "partial"), true);
    }
  } catch (error) {
    showStatus(error.message || text("failed"), true);
  } finally {
    state.busy = false;
    render();
  }
}

async function applyPreset(preset) {
  if (state.busy) return;
  if (!state.permission && !(await grant())) return;
  state.busy = true;
  state.pickerDirection = null;
  const before = { ...state.actual };
  showStatus(text("switching"));
  render();
  try {
    const response = await host.bridge("audioDevices", "apply", { inputUID: preset.inputUID, outputUID: preset.outputUID });
    if (!response?.ok) throw new Error(text("failed"));
    const data = response.data;
    state.actual = data.actual || {};
    await refresh();
    if (data.status === "applied") {
      showStatus("✓ " + text("applied") + " · " + preset.name);
      for (const dir of ["input", "output"]) {
        if (before[dir + "UID"] !== state.actual[dir + "UID"]) flashCard(dir);
      }
    } else if (data.status === "unavailable") {
      const names = data.missing.map(dir => preset[dir + "Name"] || text(dir));
      showStatus(text("disconnected") + ": " + names.join(" · "), true);
    } else {
      showStatus(text(data.status === "restored" ? "restored" : "partial"), true);
    }
  } catch (error) {
    showStatus(error.message || text("failed"), true);
  } finally {
    state.busy = false;
    render();
  }
}

async function setPillMode(toPill, edgeHint = null) {
  state.isPill = toPill;
  if (edgeHint === "left" || edgeHint === "right") state.dockedEdge = edgeHint;
  document.documentElement.dataset.mode = toPill ? "pill" : "expanded";
  element("mini-pill").hidden = !toPill;
  element("full-view").hidden = toPill;
  if (!host?.window) return;
  const anchor = state.dockedEdge === "left" ? "topLeft" : "topRight";
  if (toPill) {
    await host.window.snapToEdge(state.dockedEdge, { width: PILL.width, height: PILL.height, margin: 10, animate: true });
  } else {
    await host.window.morph({ width: EXPANDED.width, height: EXPANDED.height, anchor, animate: true, keepOnScreen: true });
  }
}

function choose(direction, uid, previousName) {
  const select = element(direction + "-select");
  const placeholder = new Option(text("select"), "", !uid, !uid);
  placeholder.disabled = true;
  select.replaceChildren(placeholder);
  for (const device of state.devices.filter(d => d[direction])) select.append(new Option(device.name, device.uid));
  if (uid && !deviceFor(uid, direction)) select.append(new Option(`${previousName || text(direction)} · ${text("disconnected")}`, uid));
  select.value = uid || "";
}

function openEditor(preset = null) {
  state.pickerDirection = null;
  state.editable = preset;
  element("editor-title").textContent = text(preset ? "edit" : "new");
  element("name").value = preset?.name || "";
  for (const direction of ["output", "input"]) {
    choose(direction, preset?.[direction + "UID"] || state.actual[direction + "UID"], preset?.[direction + "Name"]);
  }
  element("form-error").hidden = true;
  element("editor").showModal();
  element("name").focus();
}

function newID() {
  if (typeof crypto.randomUUID === "function") return crypto.randomUUID().toUpperCase();
  const bytes = crypto.getRandomValues(new Uint8Array(16));
  bytes[6] = (bytes[6] & 15) | 64;
  bytes[8] = (bytes[8] & 63) | 128;
  const hex = Array.from(bytes, b => b.toString(16).padStart(2, "0")).join("");
  return [hex.slice(0, 8), hex.slice(8, 12), hex.slice(12, 16), hex.slice(16, 20), hex.slice(20)].join("-").toUpperCase();
}

async function save(event) {
  event.preventDefault();
  if (state.busy) return;
  const nameField = element("name");
  const name = nameField.value.trim();
  if (!name) { nameField.focus(); return; }
  const preset = { id: state.editable?.id || newID(), name };
  for (const direction of ["input", "output"]) {
    const uid = element(direction + "-select").value;
    const device = deviceFor(uid, direction);
    preset[direction + "UID"] = uid;
    preset[direction + "Name"] = device?.name || state.editable?.[direction + "Name"] || text(direction);
  }
  state.busy = true;
  element("save").disabled = true;
  try {
    acceptDocument(await host.run(["--save"], JSON.stringify(preset)));
    element("editor").close();
    state.focusPreset = preset.id;
    showStatus("✓ " + text("saved"));
  } catch (error) {
    element("form-error").textContent = error.message || text("failed");
    element("form-error").hidden = false;
  } finally {
    state.busy = false;
    element("save").disabled = false;
    render();
  }
}

async function modify(command, id) {
  if (state.busy) return;
  state.busy = true;
  render();
  try {
    acceptDocument(await host.run([command, id]));
    showStatus("");
  } catch (error) {
    showStatus(error.message || text("failed"), true);
  } finally {
    state.busy = false;
    render();
  }
}

function report(operation) {
  return operation.catch(error => showStatus(error.message || text("failed"), true));
}

translate();
for (const dir of ["output", "input"]) element(dir).textContent = text("pending");

if (host) {
  element("refresh").addEventListener("click", () => report(refresh()));
  element("grant").addEventListener("click", () => report(grant()));
  element("new").addEventListener("click", () => openEditor());
  element("save-current").addEventListener("click", () => openEditor());
  element("cancel").addEventListener("click", () => element("editor").close());
  element("preset-form").addEventListener("submit", save);
  element("picker-close").addEventListener("click", () => { state.pickerDirection = null; renderPicker(); showActual(); });
  element("close-win").addEventListener("click", () => host.window.close());
  element("pill-close").addEventListener("click", () => host.window.close());
  element("expand-pill").addEventListener("click", () => setPillMode(false));
  element("dock-toggle").addEventListener("click", async () => {
    const frame = await host.window.getFrame();
    const edge = frame?.nearestEdge === "left" ? "left" : "right";
    await setPillMode(true, edge);
  });
  element("pin-toggle").addEventListener("click", async () => {
    const next = !state.pinned;
    const res = await host.window.setPinned(next);
    if (res?.ok) {
      state.pinned = Boolean(res.pinned);
      element("pin-toggle").setAttribute("aria-pressed", String(state.pinned));
    }
  });
  element("grip-bar").addEventListener("dblclick", () => host.window.resetFrame());

  for (const dir of ["output", "input"]) {
    element(dir + "-card").addEventListener("click", async () => {
      if (!state.permission && !(await grant())) return;
      state.pickerDirection = state.pickerDirection === dir ? null : dir;
      showActual();
    });
  }

  element("remove-dialog").addEventListener("close", () => {
    if (element("remove-dialog").returnValue === "remove" && state.removing) modify("--delete", state.removing);
    element("remove-dialog").returnValue = "";
    state.removing = null;
  });

  document.addEventListener("keydown", ev => {
    if (ev.key !== "Escape") return;
    if (element("editor").open || element("remove-dialog").open) return;
    if (state.pickerDirection) { state.pickerDirection = null; showActual(); return; }
    host.window.close();
  });

  host.window.onDragEnd(detail => {
    const edge = detail?.nearEdge;
    if (edge === "left" || edge === "right") {
      state.dockedEdge = edge;
      host.window.snapToEdge(edge, { margin: 10, animate: true });
    }
  });

  const activeRefresh = () => {
    if (!state.busy && !element("editor").open && !element("remove-dialog").open) report(refresh());
  };
  window.addEventListener("focus", activeRefresh);
  host.onEnvChanged(() => { translate(); activeRefresh(); });
  setInterval(() => { if (!document.hidden) activeRefresh(); }, 4000);

  if (host.env.initialState?.message) showStatus(host.env.initialState.message, true);
  report(Promise.all([loadPresets(), refresh()]).then(render));
} else {
  element("new").disabled = true;
  element("refresh").disabled = true;
  showStatus(text("host"), true);
}
