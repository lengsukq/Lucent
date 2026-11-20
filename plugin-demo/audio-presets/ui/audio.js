"use strict";

const copy = {
  current: ["当前音频设备", "Current audio devices"], refresh: ["刷新设备", "Refresh devices"],
  input: ["麦克风", "Microphone"], output: ["扬声器", "Speakers"],
  permissionText: ["允许查看和切换系统默认音频设备。", "Allow access to read and switch default audio devices."],
  grant: ["允许访问", "Allow access"], presets: ["已保存的组合", "Saved presets"], new: ["新建组合", "New preset"],
  empty: ["把现在用的扬声器和麦克风存成一套。", "Save your current speakers and microphone together."],
  saveCurrent: ["保存当前组合", "Save current setup"], name: ["组合名称", "Preset name"],
  cancel: ["取消", "Cancel"], save: ["保存", "Save"], remove: ["删除", "Delete"],
  edit: ["编辑组合", "Edit preset"], favorite: ["设为常用", "Mark as favorite"], unfavorite: ["取消常用", "Remove favorite"],
  removeTitle: ["删除这个组合？", "Delete this preset?"], unavailable: ["不可用", "Unavailable"],
  disconnected: ["未连接", "Disconnected"], noDevice: ["未检测到设备", "No device detected"],
  select: ["选择设备", "Choose a device"], switching: ["正在切换…", "Switching…"],
  applied: ["已切换", "Applied"], active: ["当前组合", "Active"],
  restored: ["切换失败，之前的设备已恢复。", "Switch failed. The previous devices were restored."],
  partial: ["未能完全恢复，请核对当前设备。", "Couldn’t fully restore audio. Check the current devices."],
  failed: ["无法完成操作，请重试。", "Couldn’t complete the action. Try again."],
  pending: ["正在读取…", "Checking…"], denied: ["尚未允许访问音频设备。", "Audio device access hasn’t been granted."],
  host: ["请从 Lucent 打开此面板。", "Open this panel from Lucent."], saved: ["组合已保存", "Preset saved"],
};

const host = window.lucent;
const element = id => document.getElementById(id);
const state = {
  language: "zh",
  devices: [],
  actual: {},
  presets: [],
  favorite: null,
  editable: null,
  removing: null,
  busy: false,
  permission: false,
  focusPreset: host?.env.initialState?.presetID,
};
const text = key => copy[key][state.language === "en" ? 1 : 0];

function translate() {
  state.language = (host?.env.locale || navigator.language).startsWith("en") ? "en" : "zh";
  document.documentElement.lang = state.language === "en" ? "en" : "zh-Hans";
  document.documentElement.dataset.theme = host?.env.theme || "pure-frost";
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

function showActual() {
  for (const direction of ["output", "input"]) {
    const uid = state.actual[direction + "UID"];
    const device = state.devices.find(item => item.uid === uid);
    const name = device?.name || (uid ? text("unavailable") : text("noDevice"));
    element(direction).textContent = state.permission ? name : "—";
    element(direction).title = state.permission ? name : "";
  }
  element("permission").hidden = state.permission;
  element("new").disabled = !state.permission || state.busy;
  element("refresh").disabled = state.busy || !state.permission;
  element("save-current").disabled = state.busy || !state.actual.inputUID || !state.actual.outputUID;
}

function deviceFor(uid, direction) {
  return state.devices.find(item => item.uid === uid && item[direction]);
}

function missingDevices(preset) {
  return ["output", "input"]
    .filter(direction => !deviceFor(preset[direction + "UID"], direction))
    .map(direction => preset[direction + "Name"] || text(direction));
}

function button(kind, label, glyph, handler) {
  const node = document.createElement("button");
  node.type = "button";
  node.className = kind;
  node.textContent = glyph;
  node.title = label;
  node.setAttribute("aria-label", label);
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
    row.className = "preset surface";
    const connected = state.permission;
    const missing = connected ? missingDevices(preset) : [];
    const active = connected && preset.inputUID === state.actual.inputUID && preset.outputUID === state.actual.outputUID;
    row.classList.toggle("active", active);

    const apply = button("preset-apply", preset.name, "", () => applyPreset(preset));
    apply.id = "preset-" + preset.id;
    apply.dataset.key = preset.id + "-apply";
    apply.disabled = state.busy;
    const title = document.createElement("span");
    title.className = "preset-name";
    title.textContent = preset.name;
    const subtitle = document.createElement("span");
    subtitle.className = "preset-detail" + (missing.length ? " warning" : "");
    subtitle.textContent = missing.length ? `${text("disconnected")}: ${missing.join(" · ")}`
      : active ? `✓ ${text("active")} · ${preset.outputName} · ${preset.inputName}`
      : `${preset.outputName} · ${preset.inputName}`;
    apply.title = subtitle.textContent;
    apply.setAttribute("aria-label", preset.name + " · " + subtitle.textContent);
    apply.append(title, subtitle);

    const tools = document.createElement("div");
    tools.className = "preset-tools";
    const favorite = preset.id === state.favorite;
    const star = button("icon-button", text(favorite ? "unfavorite" : "favorite"), favorite ? "★" : "☆",
      () => modify("--set-favorite", preset.id));
    star.setAttribute("aria-pressed", String(favorite));
    const edit = button("icon-button", text("edit"), "✎", () => openEditor(preset));
    const remove = button("icon-button", text("remove"), "−", () => {
      state.removing = preset.id;
      element("remove-name").textContent = preset.name;
      element("remove-dialog").showModal();
    });
    [star, edit, remove].forEach((control, index) => {
      control.dataset.key = preset.id + "-" + index;
      control.disabled = state.busy || (control === edit && !state.permission);
      tools.append(control);
    });
    row.append(apply, tools);
    fragment.append(row);
  }
  list.replaceChildren(fragment);
  element("empty").hidden = state.presets.length > 0 || !state.permission;
  if (focused) [...list.querySelectorAll("button")].find(control => control.dataset.key === focused)?.focus();
  if (state.focusPreset) {
    element("preset-" + state.focusPreset)?.focus();
    state.focusPreset = null;
  }
}

async function loadPresets() {
  const response = await host.run(["--list"]);
  acceptDocument(response);
}

function acceptDocument(response) {
  if (!response?.ok || !response.data || response.data.error) throw new Error(response?.data?.error || text("failed"));
  state.presets = response.data.presets || [];
  state.favorite = response.data.favorite || null;
}

async function refresh() {
  state.permission = host.env.grantedCapabilities.includes("audioDevices");
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

async function applyPreset(preset) {
  if (state.busy) return;
  if (!state.permission && !(await grant())) return;
  state.busy = true;
  const before = { ...state.actual };
  showStatus(text("switching"));
  render();
  try {
    const response = await host.bridge("audioDevices", "apply", {inputUID: preset.inputUID, outputUID: preset.outputUID});
    if (!response?.ok) throw new Error(text("failed"));
    const data = response.data;
    state.actual = data.actual || {};
    await refresh();
    if (data.status === "applied") {
      showStatus("✓ " + text("applied") + " · " + preset.name);
      for (const direction of ["input", "output"]) {
        if (before[direction + "UID"] !== state.actual[direction + "UID"]) {
          element(direction + "-card").classList.add("flash");
          setTimeout(() => element(direction + "-card").classList.remove("flash"), 720);
        }
      }
    } else if (data.status === "unavailable") {
      const names = data.missing.map(direction => preset[direction + "Name"] || text(direction));
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

function choose(direction, uid, previousName) {
  const select = element(direction + "-select");
  const placeholder = new Option(text("select"), "", !uid, !uid);
  placeholder.disabled = true;
  select.replaceChildren(placeholder);
  for (const device of state.devices.filter(device => device[direction])) select.append(new Option(device.name, device.uid));
  if (uid && !deviceFor(uid, direction)) select.append(new Option(`${previousName || text(direction)} · ${text("disconnected")}`, uid));
  select.value = uid || "";
}

function openEditor(preset = null) {
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
  const hex = Array.from(bytes, byte => byte.toString(16).padStart(2, "0")).join("");
  return [hex.slice(0, 8), hex.slice(8, 12), hex.slice(12, 16), hex.slice(16, 20), hex.slice(20)].join("-").toUpperCase();
}

async function save(event) {
  event.preventDefault();
  if (state.busy) return;
  const nameField = element("name");
  const name = nameField.value.trim();
  if (!name) { nameField.focus(); return; }
  const preset = {id: state.editable?.id || newID(), name};
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
for (const direction of ["output", "input"]) element(direction).textContent = text("pending");
if (host) {
  element("refresh").addEventListener("click", () => report(refresh()));
  element("grant").addEventListener("click", () => report(grant()));
  element("new").addEventListener("click", () => openEditor());
  element("save-current").addEventListener("click", () => openEditor());
  element("cancel").addEventListener("click", () => element("editor").close());
  element("preset-form").addEventListener("submit", save);
  element("remove-dialog").addEventListener("close", () => {
    if (element("remove-dialog").returnValue === "remove" && state.removing) modify("--delete", state.removing);
    element("remove-dialog").returnValue = "";
    state.removing = null;
  });
  const activeRefresh = () => { if (!state.busy && !element("editor").open) report(refresh()); };
  window.addEventListener("focus", activeRefresh);
  host.onEnvChanged(() => { translate(); activeRefresh(); });
  if (host.env.initialState?.message) showStatus(host.env.initialState.message, true);
  report(Promise.all([loadPresets(), refresh()]).then(render));
} else {
  element("new").disabled = true;
  element("refresh").disabled = true;
  showStatus(text("host"), true);
}
