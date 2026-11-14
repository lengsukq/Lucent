import AppKit
import Darwin
import SwiftUI

@MainActor
final class LumakeyAppDelegate: NSObject, NSApplicationDelegate {
    private let viewModel = AppViewModel()
    private var coordinator: MenuBarAndWindowCoordinator?
    private var signalSources: [DispatchSourceSignal] = []
    private var powerOffObserver: NSObjectProtocol?
    private var hasShutdown = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        installTerminationSignals()
        let coord = MenuBarAndWindowCoordinator(viewModel: viewModel)
        self.coordinator = coord
        coord.start()
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
struct LumakeyMain {
    static let delegate = LumakeyAppDelegate()

    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        app.delegate = delegate
        app.run()
    }
}
