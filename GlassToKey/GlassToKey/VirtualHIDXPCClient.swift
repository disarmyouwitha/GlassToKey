import Foundation

final class VirtualHIDXPCClient: @unchecked Sendable {
    static let shared = VirtualHIDXPCClient()

    private let connectionQueue = DispatchQueue(
        label: "com.kyome.GlassToKey.VirtualHID.XPC",
        qos: .utility
    )
    private var connection: NSXPCConnection?
    private var isAvailable = false
    private var lastError: String?

    func currentAvailability() -> Bool {
        connectionQueue.sync {
            isAvailable
        }
    }

    func currentError() -> String? {
        connectionQueue.sync {
            lastError
        }
    }

    func refreshAvailability() {
        connectionQueue.async { [weak self] in
            guard let self else { return }
            let connection = self.ensureConnection()
            let proxy = connection.remoteObjectProxyWithErrorHandler { _ in
                self.isAvailable = false
            }
            guard let service = proxy as? VirtualHIDXPCServiceProtocol else {
                self.isAvailable = false
                self.lastError = "XPC service unavailable"
                return
            }
            service.fetchStatus { [weak self] ok, _ in
                guard let self else { return }
                let queue = self.connectionQueue
                queue.async { [weak self] in
                    self?.isAvailable = ok
                    if !ok {
                        self?.lastError = "VirtualHID helper not ready"
                    }
                }
            }
        }
    }

    func sendKeyStroke(
        code: Int,
        flags: UInt64,
        completion: @escaping @Sendable (Result<Void, VirtualHIDError>) -> Void
    ) {
        connectionQueue.async { [weak self] in
            guard let self else { return }
            let connection = self.ensureConnection()
            let proxy = connection.remoteObjectProxyWithErrorHandler { error in
                self.updateError(error.localizedDescription)
                completion(.failure(.sendFailed(error.localizedDescription)))
            }
            guard let service = proxy as? VirtualHIDXPCServiceProtocol else {
                self.updateError("XPC service unavailable")
                completion(.failure(.sendFailed("XPC service unavailable")))
                return
            }
            service.sendKeyStroke(code: code, flags: flags) { ok, error in
                if ok {
                    completion(.success(()))
                } else {
                    self.updateError(error ?? "VirtualHID send failed")
                    completion(.failure(.sendFailed(error ?? "VirtualHID send failed")))
                }
            }
        }
    }

    func sendKey(
        code: Int,
        flags: UInt64,
        keyDown: Bool,
        completion: @escaping @Sendable (Result<Void, VirtualHIDError>) -> Void
    ) {
        connectionQueue.async { [weak self] in
            guard let self else { return }
            let connection = self.ensureConnection()
            let proxy = connection.remoteObjectProxyWithErrorHandler { error in
                self.updateError(error.localizedDescription)
                completion(.failure(.sendFailed(error.localizedDescription)))
            }
            guard let service = proxy as? VirtualHIDXPCServiceProtocol else {
                self.updateError("XPC service unavailable")
                completion(.failure(.sendFailed("XPC service unavailable")))
                return
            }
            service.sendKey(code: code, flags: flags, keyDown: keyDown) { ok, error in
                if ok {
                    completion(.success(()))
                } else {
                    self.updateError(error ?? "VirtualHID send failed")
                    completion(.failure(.sendFailed(error ?? "VirtualHID send failed")))
                }
            }
        }
    }

    private func ensureConnection() -> NSXPCConnection {
        if let connection {
            return connection
        }
        let connection = NSXPCConnection(
            machServiceName: VirtualHIDHelperMachServiceName,
            options: .privileged
        )
        connection.remoteObjectInterface = NSXPCInterface(
            with: VirtualHIDXPCServiceProtocol.self
        )
        connection.invalidationHandler = { [weak self] in
            guard let self else { return }
            self.connectionQueue.async { [weak self] in
                self?.isAvailable = false
                self?.lastError = "XPC connection invalidated"
                self?.connection = nil
            }
        }
        connection.interruptionHandler = { [weak self] in
            guard let self else { return }
            self.connectionQueue.async { [weak self] in
                self?.isAvailable = false
                self?.lastError = "XPC connection interrupted"
            }
        }
        connection.resume()
        self.connection = connection
        return connection
    }

    private func updateError(_ message: String) {
        connectionQueue.async { [weak self] in
            self?.lastError = message
        }
    }
}
