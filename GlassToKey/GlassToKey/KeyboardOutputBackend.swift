import Foundation

enum KeyboardOutputBackend: String, CaseIterable, Identifiable {
    case cgevent
    case virtualhid

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .cgevent:
            return "CGEvent (Compatibility)"
        case .virtualhid:
            return "VirtualHID (Karabiner)"
        }
    }
}

enum VirtualHIDActivationState: String {
    case unknown
    case active
    case inactive
}

enum VirtualHIDReachability: String {
    case unknown
    case reachable
    case unreachable
    case permissionDenied
}

struct VirtualHIDStatus: Equatable {
    var isInstalled: Bool
    var activationState: VirtualHIDActivationState
    var reachability: VirtualHIDReachability
    var socketPath: String?
    var lastError: String?

    var isHealthy: Bool {
        isInstalled && reachability == .reachable
    }
}

struct KeyboardBackendStatus: Equatable {
    var preference: KeyboardOutputBackend
    var activeBackend: KeyboardOutputBackend
    var virtualHID: VirtualHIDStatus
    var lastError: String?

    static func initial() -> KeyboardBackendStatus {
        KeyboardBackendStatus(
            preference: .cgevent,
            activeBackend: .cgevent,
            virtualHID: VirtualHIDStatus(
                isInstalled: false,
                activationState: .unknown,
                reachability: .unknown,
                socketPath: nil,
                lastError: nil
            ),
            lastError: nil
        )
    }
}

@MainActor
final class KeyboardOutputStatusCenter: ObservableObject {
    static let shared = KeyboardOutputStatusCenter()

    @Published private(set) var status = KeyboardBackendStatus.initial()

    func update(_ status: KeyboardBackendStatus) {
        if self.status != status {
            self.status = status
        }
    }
}
