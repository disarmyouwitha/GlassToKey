import AppKit
import Combine
import SwiftUI

@main
struct GlassToKeyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private let controller = GlassToKeyController()
    private var statusItem: NSStatusItem?
    private var configWindow: NSWindow?
    private var statusCancellable: AnyCancellable?
    private static let configWindowDefaultHeight: CGFloat = 600

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        controller.start()
        configureStatusItem()
        observeStatus()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
              window == configWindow else {
            return
        }
        disableVisuals()
        controller.viewModel.setTouchSnapshotRecordingEnabled(false)
        controller.viewModel.setStatusVisualsEnabled(false)
        controller.viewModel.clearVisualCaches()
        window.delegate = nil
        window.contentView = nil
        window.contentViewController = nil
        configWindow = nil
    }

    private func configureStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            button.title = ""
            button.imagePosition = .imageLeading
        }

        let menu = NSMenu()
        let configItem = NSMenuItem(
            title: "Config...",
            action: #selector(openConfigWindow),
            keyEquivalent: ","
        )
        configItem.target = self
        menu.addItem(configItem)
        let syncItem = NSMenuItem(
            title: "Sync devices",
            action: #selector(syncDevices),
            keyEquivalent: "s"
        )
        syncItem.target = self
        menu.addItem(syncItem)
        menu.addItem(.separator())

        let restartItem = NSMenuItem(
            title: "Restart GlassToKey",
            action: #selector(restartApp),
            keyEquivalent: ""
        )
        restartItem.target = self
        menu.addItem(restartItem)

        let quitItem = NSMenuItem(
            title: "Quit GlassToKey",
            action: #selector(quitApp),
            keyEquivalent: "q"
        )
        quitItem.target = self
        menu.addItem(quitItem)

        item.menu = menu
        statusItem = item
        updateStatusIndicator(
            isTypingEnabled: controller.viewModel.isTypingEnabled,
            activeLayer: controller.viewModel.activeLayer,
            hasDisconnectedTrackpads: controller.viewModel.hasDisconnectedTrackpads,
            keyboardModeEnabled: controller.viewModel.keyboardModeEnabled
        )
    }

    private func observeStatus() {
        statusCancellable = Publishers.CombineLatest4(
            controller.viewModel.$isTypingEnabled.removeDuplicates(),
            controller.viewModel.$activeLayer.removeDuplicates(),
            controller.viewModel.$hasDisconnectedTrackpads.removeDuplicates(),
            controller.viewModel.$keyboardModeEnabled.removeDuplicates()
        )
        .sink { [weak self] isTypingEnabled, activeLayer, hasDisconnected, keyboardModeEnabled in
            self?.updateStatusIndicator(
                isTypingEnabled: isTypingEnabled,
                activeLayer: activeLayer,
                hasDisconnectedTrackpads: hasDisconnected,
                keyboardModeEnabled: keyboardModeEnabled
            )
        }
    }

    private func updateStatusIndicator(
        isTypingEnabled: Bool,
        activeLayer: Int,
        hasDisconnectedTrackpads: Bool,
        keyboardModeEnabled: Bool
    ) {
        guard let button = statusItem?.button else { return }
        button.image = statusIndicatorImage(
            isTypingEnabled: isTypingEnabled,
            activeLayer: activeLayer,
            hasWarning: hasDisconnectedTrackpads,
            keyboardModeEnabled: keyboardModeEnabled
        )
        let modeText: String
        if isTypingEnabled {
            modeText = keyboardModeEnabled ? "Keyboard mode" : "Mixed mode"
        } else {
            modeText = "Mouse mode"
        }
        button.toolTip = hasDisconnectedTrackpads
            ? "\(modeText) – missing trackpad"
            : modeText
    }

    private func statusIndicatorImage(
        isTypingEnabled: Bool,
        activeLayer: Int,
        hasWarning: Bool,
        keyboardModeEnabled: Bool
    ) -> NSImage {
        let size = NSSize(width: 10, height: 10)
        let image = NSImage(size: size)
        image.isTemplate = false
        image.lockFocus()
        let rect = NSRect(origin: .zero, size: size).insetBy(dx: 1, dy: 1)
        let path = NSBezierPath(ovalIn: rect)
        let color = activeLayer == 1
            ? NSColor.systemBlue
            : (isTypingEnabled
                ? (keyboardModeEnabled ? NSColor.systemPurple : NSColor.systemGreen)
                : NSColor.systemRed)
        color.setFill()
        path.fill()

        if hasWarning {
            let dotRadius: CGFloat = 3.5
            let dotCenter = CGPoint(
                x: rect.maxX - dotRadius - 0.5,
                y: rect.maxY - dotRadius - 0.5
            )
            let warning = NSBezierPath()
            warning.appendArc(
                withCenter: dotCenter,
                radius: dotRadius,
                startAngle: 0,
                endAngle: 360
            )
            NSColor.systemYellow.setFill()
            warning.fill()
        }

        image.unlockFocus()
        return image
    }

    @objc private func openConfigWindow() {
        let window = configWindow ?? makeConfigWindow()
        configWindow = window
        controller.viewModel.setTouchSnapshotRecordingEnabled(true)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func syncDevices() {
        controller.viewModel.loadDevices(preserveSelection: true)
    }

    @objc private func restartApp() {
        let bundlePath = Bundle.main.bundlePath
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        task.arguments = ["-n", bundlePath]
        try? task.run()
        NSApp.terminate(nil)
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }

    private func disableVisuals() {
        UserDefaults.standard.set(false, forKey: GlassToKeyDefaultsKeys.visualsEnabled)
    }

    private func makeConfigWindow() -> NSWindow {
        let contentView = ContentView(viewModel: controller.viewModel)
        let window = NSWindow(
            contentRect: NSRect(
                x: 0,
                y: 0,
                width: 984,
                height: Self.configWindowDefaultHeight
            ),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.center()
        window.title = "GlassToKey"
        window.contentView = NSHostingView(rootView: contentView)
        window.isReleasedWhenClosed = false
        window.delegate = self
        return window
    }
}
