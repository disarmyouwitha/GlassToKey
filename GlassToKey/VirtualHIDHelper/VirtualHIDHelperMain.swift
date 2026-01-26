import CoreGraphics
import Foundation

final class VirtualHIDHelper: NSObject, NSXPCListenerDelegate, VirtualHIDXPCServiceProtocol {
    private let daemonClient = VirtualHIDDaemonClient()

    func listener(
        _ listener: NSXPCListener,
        shouldAcceptNewConnection newConnection: NSXPCConnection
    ) -> Bool {
        newConnection.exportedInterface = NSXPCInterface(
            with: VirtualHIDXPCServiceProtocol.self
        )
        newConnection.exportedObject = self
        newConnection.resume()
        return true
    }

    func sendKeyStroke(
        code: Int,
        flags: UInt64,
        reply: @escaping (Bool, String?) -> Void
    ) {
        let result = daemonClient.sendKeyStroke(
            code: CGKeyCode(code),
            flags: CGEventFlags(rawValue: flags)
        )
        reply(result.0, result.1)
    }

    func sendKey(
        code: Int,
        flags: UInt64,
        keyDown: Bool,
        reply: @escaping (Bool, String?) -> Void
    ) {
        let result = daemonClient.sendKey(
            code: CGKeyCode(code),
            flags: CGEventFlags(rawValue: flags),
            keyDown: keyDown
        )
        reply(result.0, result.1)
    }

    func fetchStatus(reply: @escaping (Bool, String?) -> Void) {
        let status = daemonClient.status()
        reply(status.0, status.1)
    }
}

@main
struct VirtualHIDHelperMain {
    static func main() {
        let helper = VirtualHIDHelper()
        let listener = NSXPCListener(machServiceName: VirtualHIDHelperMachServiceName)
        listener.delegate = helper
        listener.resume()
        RunLoop.current.run()
    }
}
