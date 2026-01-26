import CoreGraphics
import Foundation

enum VirtualHIDError: Error {
    case unsupported
    case sendFailed(String)

    var message: String {
        switch self {
        case .unsupported:
            return "VirtualHID client not configured"
        case .sendFailed(let detail):
            return detail
        }
    }
}

final class VirtualHIDClient: @unchecked Sendable {
    static var isAvailable: Bool {
        VirtualHIDXPCClient.shared.currentAvailability()
    }

    static var lastError: String? {
        VirtualHIDXPCClient.shared.currentError()
    }

    static func refreshAvailability() {
        VirtualHIDXPCClient.shared.refreshAvailability()
    }

    func sendKeyStroke(
        code: CGKeyCode,
        flags: CGEventFlags,
        completion: @escaping @Sendable (Result<Void, VirtualHIDError>) -> Void
    ) {
        VirtualHIDXPCClient.shared.sendKeyStroke(
            code: Int(code),
            flags: flags.rawValue,
            completion: completion
        )
    }

    func sendKey(
        code: CGKeyCode,
        flags: CGEventFlags,
        keyDown: Bool,
        completion: @escaping @Sendable (Result<Void, VirtualHIDError>) -> Void
    ) {
        VirtualHIDXPCClient.shared.sendKey(
            code: Int(code),
            flags: flags.rawValue,
            keyDown: keyDown,
            completion: completion
        )
    }
}

final class VirtualHIDKeyDispatcher: @unchecked Sendable, KeyDispatching {
    private let queue = DispatchQueue(
        label: "com.kyome.GlassToKey.KeyDispatch.VirtualHID",
        qos: .userInteractive
    )
    private let client: VirtualHIDClient
    private let onFailure: (VirtualHIDError) -> Void

    init(
        client: VirtualHIDClient,
        onFailure: @escaping (VirtualHIDError) -> Void
    ) {
        self.client = client
        self.onFailure = onFailure
    }

    func postKeyStroke(code: CGKeyCode, flags: CGEventFlags, token: RepeatToken?) {
        queue.async { [self] in
            if let token, !token.isActive {
                return
            }
            client.sendKeyStroke(
                code: code,
                flags: flags
            ) { [weak self] result in
                if case .failure(let error) = result {
                    self?.onFailure(error)
                }
            }
        }
    }

    func postKey(code: CGKeyCode, flags: CGEventFlags, keyDown: Bool, token: RepeatToken?) {
        queue.async { [self] in
            if let token, !token.isActive {
                return
            }
            client.sendKey(
                code: code,
                flags: flags,
                keyDown: keyDown
            ) { [weak self] result in
                if case .failure(let error) = result {
                    self?.onFailure(error)
                }
            }
        }
    }

    func postLeftClick(clickCount: Int) {
        queue.async { [self] in
            let error = VirtualHIDError.sendFailed("VirtualHID does not support mouse clicks")
            onFailure(error)
        }
    }

    func postRightClick() {
        queue.async { [self] in
            let error = VirtualHIDError.sendFailed("VirtualHID does not support mouse clicks")
            onFailure(error)
        }
    }
}
