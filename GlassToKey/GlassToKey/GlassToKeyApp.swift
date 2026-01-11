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
    private var typingModeCancellable: AnyCancellable?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        controller.start()
        configureStatusItem()
        observeTypingMode()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
              window == configWindow else {
            return
        }
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
        menu.addItem(.separator())

        let quitItem = NSMenuItem(
            title: "Quit GlassToKey",
            action: #selector(quitApp),
            keyEquivalent: "q"
        )
        quitItem.target = self
        menu.addItem(quitItem)

        item.menu = menu
        statusItem = item
        updateStatusIndicator(isTypingEnabled: controller.viewModel.isTypingEnabled)
    }

    private func observeTypingMode() {
        typingModeCancellable = controller.viewModel.$isTypingEnabled
            .removeDuplicates()
            .sink { [weak self] isTypingEnabled in
                self?.updateStatusIndicator(isTypingEnabled: isTypingEnabled)
            }
    }

    private func updateStatusIndicator(isTypingEnabled: Bool) {
        guard let button = statusItem?.button else { return }
        button.image = statusIndicatorImage(isTypingEnabled: isTypingEnabled)
        button.toolTip = isTypingEnabled ? "Keyboard mode" : "Mouse mode"
    }

    private func statusIndicatorImage(isTypingEnabled: Bool) -> NSImage {
        let size = NSSize(width: 10, height: 10)
        let image = NSImage(size: size)
        image.isTemplate = false
        image.lockFocus()
        let rect = NSRect(origin: .zero, size: size).insetBy(dx: 1, dy: 1)
        let path = NSBezierPath(ovalIn: rect)
        let color = isTypingEnabled ? NSColor.systemGreen : NSColor.systemRed
        color.setFill()
        path.fill()
        image.unlockFocus()
        return image
    }

    @objc private func openConfigWindow() {
        let window = configWindow ?? makeConfigWindow()
        configWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }

    private func makeConfigWindow() -> NSWindow {
        let contentView = ContentView(viewModel: controller.viewModel)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 984, height: 560),
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
