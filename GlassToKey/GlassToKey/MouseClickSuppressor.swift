import CoreGraphics
import Foundation
import os

final class MouseClickSuppressor {
    typealias ShouldSuppress = @Sendable () -> Bool

    private let shouldSuppress: ShouldSuppress
    private let stateLock = OSAllocatedUnfairLock<Bool>(uncheckedState: false)
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var runLoop: CFRunLoop?
    private var thread: Thread?

    init(shouldSuppress: @escaping ShouldSuppress) {
        self.shouldSuppress = shouldSuppress
    }

    func start() {
        let shouldStart = stateLock.withLockUnchecked { running -> Bool in
            if running { return false }
            running = true
            return true
        }
        if !shouldStart { return }

        let thread = Thread(target: self, selector: #selector(runLoopThread), object: nil)
        self.thread = thread
        thread.name = "GlassToKey.MouseClickSuppressor"
        thread.start()
    }

    func stop() {
        let shouldStop = stateLock.withLockUnchecked { running -> Bool in
            if !running { return false }
            running = false
            return true
        }
        if !shouldStop { return }
        if let runLoop = runLoop {
            CFRunLoopStop(runLoop)
            CFRunLoopWakeUp(runLoop)
        }
    }

    private func setupEventTap() {
        let mask = (1 << CGEventType.leftMouseDown.rawValue)
            | (1 << CGEventType.leftMouseUp.rawValue)
        let callback: CGEventTapCallBack = { _, type, event, refcon in
            guard let refcon else { return Unmanaged.passUnretained(event) }
            let suppressor = Unmanaged<MouseClickSuppressor>.fromOpaque(refcon).takeUnretainedValue()
            return suppressor.handle(type: type, event: event)
        }
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(mask),
            callback: callback,
            userInfo: refcon
        ) else {
            return
        }
        eventTap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        runLoopSource = source
        if let source {
            CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
        }
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    private func teardownEventTap() {
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
        }
        runLoopSource = nil
        eventTap = nil
        runLoop = nil
        thread = nil
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let eventTap {
                CGEvent.tapEnable(tap: eventTap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }
        switch type {
        case .leftMouseDown, .leftMouseUp:
            if shouldSuppress() {
                return nil
            }
            return Unmanaged.passUnretained(event)
        default:
            return Unmanaged.passUnretained(event)
        }
    }

    @objc private func runLoopThread() {
        setupEventTap()
        self.runLoop = CFRunLoopGetCurrent()
        CFRunLoopRun()
        teardownEventTap()
    }
}
