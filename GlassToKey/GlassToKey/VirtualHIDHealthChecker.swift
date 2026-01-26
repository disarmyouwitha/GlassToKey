import Foundation

struct VirtualHIDHealthChecker {
    static let installPath = "/Library/Application Support/org.pqrs/Karabiner-DriverKit-VirtualHIDDevice"
    static let managerAppPath = "/Applications/.Karabiner-VirtualHIDDevice-Manager.app"
    static let socketDirectoryPath = "/Library/Application Support/org.pqrs/tmp/rootonly/vhidd_server"

    static func check() -> VirtualHIDStatus {
        let fileManager = FileManager.default
        let isInstalled = fileManager.fileExists(atPath: installPath)
        let hasManagerApp = fileManager.fileExists(atPath: managerAppPath)
        var isDirectory: ObjCBool = false
        let socketDirExists = fileManager.fileExists(
            atPath: socketDirectoryPath,
            isDirectory: &isDirectory
        ) && isDirectory.boolValue
        let activationState: VirtualHIDActivationState = socketDirExists
            ? .active
            : (hasManagerApp ? .inactive : .unknown)

        var reachability: VirtualHIDReachability = .unknown
        var socketPath: String?
        var lastError: String?

        if socketDirExists {
            do {
                let entries = try fileManager.contentsOfDirectory(
                    atPath: socketDirectoryPath
                )
                let sockets = entries.filter { $0.hasSuffix(".sock") }
                if let firstSocket = sockets.first {
                    socketPath = (socketDirectoryPath as NSString).appendingPathComponent(firstSocket)
                    reachability = .reachable
                } else {
                    reachability = .unreachable
                    lastError = "No VirtualHID sockets detected"
                }
            } catch let error as NSError {
                if error.domain == NSCocoaErrorDomain,
                   error.code == NSFileReadNoPermissionError {
                    reachability = .permissionDenied
                    lastError = "Permission denied reading socket directory"
                } else {
                    reachability = .unreachable
                    lastError = error.localizedDescription
                }
            }
        } else if isInstalled {
            reachability = .unreachable
            lastError = "VirtualHID daemon not running"
        }

        if !isInstalled {
            reachability = .unreachable
            lastError = "Karabiner VirtualHIDDevice not installed"
        }

        return VirtualHIDStatus(
            isInstalled: isInstalled,
            activationState: activationState,
            reachability: reachability,
            socketPath: socketPath,
            lastError: lastError
        )
    }
}
