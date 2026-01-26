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
    static var isAvailable: Bool { false }

    func sendKeyStroke(
        code: CGKeyCode,
        flags: CGEventFlags
    ) -> Result<Void, VirtualHIDError> {
        .failure(.unsupported)
    }

    func sendKey(
        code: CGKeyCode,
        flags: CGEventFlags,
        keyDown: Bool
    ) -> Result<Void, VirtualHIDError> {
        .failure(.unsupported)
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
            if case .failure(let error) = client.sendKeyStroke(
                code: code,
                flags: flags
            ) {
                onFailure(error)
            }
        }
    }

    func postKey(code: CGKeyCode, flags: CGEventFlags, keyDown: Bool, token: RepeatToken?) {
        queue.async { [self] in
            if let token, !token.isActive {
                return
            }
            if case .failure(let error) = client.sendKey(
                code: code,
                flags: flags,
                keyDown: keyDown
            ) {
                onFailure(error)
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
