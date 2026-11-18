import AppKit
import Foundation
import LumakeyCore

extension AppViewModel {
    func reloadScripts() {
        IconCache.shared.invalidateCustomIcons()
        scripts = ScriptLibraryStore.shared.syncWithDisk()
    }

    func reloadScriptsAndHotKeys() {
        reloadScripts()
        (hotKeyManager ?? GlobalHotKeyManager.activeInstance)?.updateExternalPluginHotKeys(allExternalHotKeyBindings())
        NotificationCenter.default.post(name: .lumakeyMenuBarConfigDidChange, object: nil)
    }

    func installScriptObservers() {
        removeScriptObservers()
        scriptsInProcessObserver = NotificationCenter.default.addObserver(
            forName: .lumakeyScriptsDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                IconCache.shared.invalidateCustomIcons()
                self.scripts = ScriptLibraryStore.shared.allScripts(includeDisabled: true)
                (self.hotKeyManager ?? GlobalHotKeyManager.activeInstance)?.updateExternalPluginHotKeys(self.allExternalHotKeyBindings())
                NotificationCenter.default.post(name: .lumakeyMenuBarConfigDidChange, object: nil)
            }
        }
        scriptsDistributedObserver = DistributedNotificationCenter.default().addObserver(
            forName: ScriptLibraryStore.distributedReloadNotificationName,
            object: nil,
            queue: .main
        ) { [weak self] note in
            let expected = ScriptLibraryStore.defaultIndexFileURL().standardizedFileURL.path
            if let sender = note.object as? String, !sender.isEmpty, sender != expected { return }
            MainActor.assumeIsolated {
                self?.reloadScriptsAndHotKeys()
            }
        }
        scriptsWatcher = PluginDirectoryWatcher(
            directoryURL: ScriptLibraryStore.defaultScriptsDirectory(),
            debounceInterval: 0.35,
            watchDataRoot: false
        ) { [weak self] in
            Task { @MainActor [weak self] in
                self?.reloadScriptsAndHotKeys()
            }
        }
    }

    func removeScriptObservers() {
        if let obs = scriptsInProcessObserver {
            NotificationCenter.default.removeObserver(obs)
            scriptsInProcessObserver = nil
        }
        if let dist = scriptsDistributedObserver {
            DistributedNotificationCenter.default().removeObserver(dist)
            scriptsDistributedObserver = nil
        }
        scriptsWatcher?.stop()
        scriptsWatcher = nil
    }

    var allExternalHotKeys: [ExternalPluginHotKey] {
        var list = externalPluginHotKeys
        for script in scripts where script.isEnabled {
            if let raw = script.hotKey, let chord = HotKeyChord.parse(raw) {
                list.append(ExternalPluginHotKey(
                    pluginID: "script:\(script.id)",
                    pluginName: L10n.pick("脚本 · \(script.displayTitle)", "Script · \(script.displayTitle)"),
                    chord: chord
                ))
            }
        }
        return list
    }

    func allExternalHotKeyBindings() -> [ExternalHotKeyBinding] {
        var bindings = externalPluginHotKeyBindings()
        for script in scripts where script.isEnabled {
            if let raw = script.hotKey, let chord = HotKeyChord.parse(raw) {
                let sid = script.id
                bindings.append(ExternalHotKeyBinding(pluginID: "script:\(sid)", chord: chord) { [weak self] in
                    self?.triggerScriptHotKey(scriptID: sid)
                })
            }
        }
        return bindings
    }

    func triggerScriptHotKey(scriptID: String) {
        guard let script = scripts.first(where: { $0.id == scriptID && $0.isEnabled }) else { return }
        let captured = PluginSelectionReader.captureFrontmostSelection(allowCopyFallback: false)
        lastCapturedSelection = captured
        if script.outputMode == .inlinePreview {
            skipNextSelectionCapture = true
            onShowOverlayRequest?(.all)
            skipNextSelectionCapture = false
            lastCapturedSelection = captured
        }
        runScript(script, query: captured.text, fromHotKey: true)
    }

    func openScriptSettings(selecting scriptID: String? = nil) {
        if let scriptID { activeScriptSettingsID = scriptID }
        openRoute(.settings(.scripts))
    }

    func toggleScriptQuickBarPin(_ script: ScriptRecord) {
        var updated = script
        updated.pinnedInQuickBar.toggle()
        let code = ScriptLibraryStore.shared.readCode(for: script)
        _ = try? ScriptLibraryStore.shared.upsert(updated, code: code)
        reloadScripts()
        serviceMessage = updated.pinnedInQuickBar
            ? L10n.pick("已将脚本「\(script.displayTitle)」添加到快捷按钮栏", "Added \"\(script.displayTitle)\" to Quick Bar")
            : L10n.pick("已从快捷按钮栏移除「\(script.displayTitle)」", "Removed \"\(script.displayTitle)\" from Quick Bar")
    }

    func toggleScriptMenuBarPin(_ script: ScriptRecord) {
        var updated = script
        updated.showInMenuBar.toggle()
        let code = ScriptLibraryStore.shared.readCode(for: script)
        _ = try? ScriptLibraryStore.shared.upsert(updated, code: code)
        reloadScriptsAndHotKeys()
        serviceMessage = updated.showInMenuBar
            ? L10n.pick("已将脚本「\(script.displayTitle)」挂载到状态栏菜单", "Pinned \"\(script.displayTitle)\" to Menu Bar")
            : L10n.pick("已从状态栏菜单移除「\(script.displayTitle)」", "Removed \"\(script.displayTitle)\" from Menu Bar")
    }

    func runScript(_ script: ScriptRecord, query: String = "", fromHotKey: Bool = false) {
        pluginRunTask?.cancel()
        let runToken = UUID()
        activePluginRunToken = runToken
        isRunningPlugin = true
        let clipText = clipboardItems.first(where: { $0.textValue != nil })?.textValue
            ?? NSPasteboard.general.string(forType: .string)
            ?? ""
        let selText = lastCapturedSelection?.text ?? ""
        serviceMessage = L10n.pick("正在运行脚本：\(script.displayTitle)…", "Running script: \(script.displayTitle)…")

        pluginRunTask = Task { [weak self] in
            defer {
                if let self, self.activePluginRunToken == runToken {
                    self.isRunningPlugin = false
                }
            }
            do {
                let outcome = try await ScriptRunner.runAsync(
                    script,
                    query: query,
                    clipboardText: clipText,
                    selectedText: selText
                )
                guard !Task.isCancelled, let self else { return }
                self.applyScriptOutcome(outcome, for: script, fromHotKey: fromHotKey)
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled, let self else { return }
                let msg = (error as? LumakeyError)?.diagnostic.reason ?? error.localizedDescription
                self.serviceMessage = msg
                if self.isOverlayVisible {
                    self.inlinePluginViewPayload = nil
                    self.inlineResultTitle = script.displayTitle
                    self.inlineResultBody = msg
                }
            }
        }
    }

    private func applyScriptOutcome(_ outcome: ScriptRunOutcome, for script: ScriptRecord, fromHotKey: Bool) {
        let trimmedOut = outcome.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        let fullText = outcome.combinedOutput
        if outcome.exitCode != 0 {
            let errSummary = fullText.isEmpty ? "退出码 \(outcome.exitCode)" : fullText
            serviceMessage = L10n.pick("脚本「\(script.displayTitle)」执行异常", "Script \"\(script.displayTitle)\" failed")
            if isOverlayVisible {
                inlinePluginViewPayload = nil
                inlineResultTitle = "\(script.displayTitle) (Exit \(outcome.exitCode))"
                inlineResultBody = errSummary
            }
            return
        }

        switch script.outputMode {
        case .toast:
            let firstLine = trimmedOut.components(separatedBy: .newlines).first?.trimmingCharacters(in: .whitespaces) ?? ""
            serviceMessage = firstLine.isEmpty
                ? L10n.pick("✓ \(script.displayTitle) 执行完成 (\(outcome.durationMs) ms)", "✓ \(script.displayTitle) done (\(outcome.durationMs) ms)")
                : "✓ \(script.displayTitle)：\(String(firstLine.prefix(64)))"
            if isOverlayVisible && !isOverlayPinned && !fromHotKey { onHideOverlayRequest?() }
        case .inlinePreview:
            if !isOverlayVisible { onShowOverlayRequest?(.all) }
            inlinePluginViewPayload = nil
            inlineResultTitle = script.displayTitle
            inlineResultBody = fullText.isEmpty ? L10n.pick("(执行成功，无输出内容)", "(Completed with empty output)") : fullText
            serviceMessage = L10n.pick("✓ \(script.displayTitle) 完成 (\(outcome.durationMs) ms)", "✓ \(script.displayTitle) ready (\(outcome.durationMs) ms)")
        case .copyToClipboard:
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(trimmedOut, forType: .string)
            capturePasteboardOnceIfChanged()
            serviceMessage = L10n.pick("✓ 已复制脚本输出：\(script.displayTitle)", "✓ Copied script output: \(script.displayTitle)")
            if isOverlayVisible && !isOverlayPinned { onHideOverlayRequest?() }
        case .pasteToFrontApp:
            if !trimmedOut.isEmpty {
                _ = performPluginPasteBack(trimmedOut)
                serviceMessage = L10n.pick("✓ 已回填粘贴：\(script.displayTitle)", "✓ Pasted output: \(script.displayTitle)")
            } else {
                serviceMessage = L10n.pick("脚本无输出可粘贴", "Script produced empty output")
            }
        case .openReader:
            let capturesDir = FileManager.default.temporaryDirectory
                .appendingPathComponent("lumakey-captures", isDirectory: true)
            try? FileManager.default.createDirectory(
                at: capturesDir,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            let tmpURL = capturesDir.appendingPathComponent("lumakey-script-\(script.id).md")
            let md = "# \(script.displayTitle)\n\n```text\n\(fullText.isEmpty ? "(empty)" : fullText)\n```\n"
            try? Data(md.utf8).write(to: tmpURL, options: .atomic)
            openMediaWindow(for: tmpURL, kind: .markdown)
        }
    }
}
