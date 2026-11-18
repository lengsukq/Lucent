import AppKit
import Darwin
import SwiftUI

@MainActor
final class LucentAppDelegate: NSObject, NSApplicationDelegate {
    private let viewModel = AppViewModel()
    private var coordinator: MenuBarAndWindowCoordinator?
    private var signalSources: [DispatchSourceSignal] = []
    private var powerOffObserver: NSObjectProtocol?
    private var hasShutdown = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.applicationIconImage = LucentBrandIcon.appIconImage()
        installStandardEditMainMenu()
        installTerminationSignals()
        let coord = MenuBarAndWindowCoordinator(viewModel: viewModel)
        self.coordinator = coord
        coord.start()
    }

    private func installStandardEditMainMenu() {
        let mainMenu = NSMenu()
        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Quit Lucent", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        mainMenu.addItem(appItem)

        let editItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = NSMenuItem(title: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(redo)
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = editMenu
        mainMenu.addItem(editItem)
        NSApp.mainMenu = mainMenu
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        coordinator?.handleDockReopen()
        return true
    }

    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        coordinator?.buildDockMenu()
    }

    func applicationWillTerminate(_ notification: Notification) {
        shutdownOnce()
    }

    private func installTerminationSignals() {
        for sig in [SIGTERM, SIGINT, SIGHUP] {
            signal(sig, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: sig, queue: .main)
            source.setEventHandler { [weak self] in
                MainActor.assumeIsolated {
                    self?.performShutdownAndExit()
                }
            }
            source.resume()
            signalSources.append(source)
        }
        powerOffObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.willPowerOffNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.shutdownOnce()
            }
        }
    }

    private func performShutdownAndExit() {
        shutdownOnce()
        NSApp.terminate(nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            Darwin.exit(0)
        }
    }

    private func shutdownOnce() {
        guard !hasShutdown else { return }
        hasShutdown = true
        for src in signalSources { src.cancel() }
        signalSources.removeAll()
        if let obs = powerOffObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(obs)
            powerOffObserver = nil
        }
        coordinator?.shutdown()
    }
}

@main
@MainActor
struct LucentMain {
    static let delegate = LucentAppDelegate()

    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        app.delegate = delegate
        app.run()
    }
}
