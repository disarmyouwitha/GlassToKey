import Foundation

let VirtualHIDHelperMachServiceName = "com.kyome.GlassToKey.VirtualHIDHelper"

@objc protocol VirtualHIDXPCServiceProtocol {
    func sendKeyStroke(
        code: Int,
        flags: UInt64,
        reply: @escaping (Bool, String?) -> Void
    )
    func sendKey(
        code: Int,
        flags: UInt64,
        keyDown: Bool,
        reply: @escaping (Bool, String?) -> Void
    )
    func fetchStatus(reply: @escaping (Bool, String?) -> Void)
}
