import Carbon
import Foundation

final class VirtualHIDDaemonClient {
    private enum Request: UInt8 {
        case none = 0
        case virtualHIDKeyboardInitialize = 1
        case virtualHIDKeyboardTerminate = 2
        case virtualHIDKeyboardReset = 3
        case virtualHIDPointingInitialize = 4
        case virtualHIDPointingTerminate = 5
        case virtualHIDPointingReset = 6
        case postKeyboardInputReport = 7
        case postConsumerInputReport = 8
        case postAppleVendorKeyboardInputReport = 9
        case postAppleVendorTopCaseInputReport = 10
        case postGenericDesktopInputReport = 11
        case postPointingInputReport = 12
    }

    private enum Response: UInt8 {
        case none = 0
        case driverActivated = 1
        case driverConnected = 2
        case driverVersionMismatched = 3
        case virtualHIDKeyboardReady = 4
        case virtualHIDPointingReady = 5
    }

    private struct KeyboardParameters {
        var vendorID: UInt64
        var productID: UInt64
        var countryCode: UInt64
    }

    private static let protocolVersion: UInt16 = 5
    private static let rootOnlyPath = "/Library/Application Support/org.pqrs/tmp/rootonly"
    private static let serverSocketDirectory = rootOnlyPath + "/vhidd_server"
    private static let clientSocketDirectory = rootOnlyPath + "/vhidd_client"

    private let queue = DispatchQueue(label: "com.kyome.GlassToKey.VirtualHID.Daemon", qos: .userInteractive)
    private var socketFD: Int32 = -1
    private var clientSocketPath: String?
    private var serverSocketPath: String?
    private var readSource: DispatchSourceRead?
    private var keyboardReady = false
    private var driverActivated = false
    private var driverConnected = false
    private var lastError: String?

    private var modifiers: UInt8 = 0
    private var keySlots = [UInt16](repeating: 0, count: 32)
    private var reportBuffer = [UInt8](repeating: 0, count: 67)
    private var sendBuffer = [UInt8](repeating: 0, count: 72)

    func status() -> (Bool, String?) {
        queue.sync {
            let ready = keyboardReady && driverActivated && driverConnected
            return (ready, lastError)
        }
    }

    func sendKeyStroke(code: CGKeyCode, flags: CGEventFlags) -> (Bool, String?) {
        queue.sync {
            guard ensureConnected() else { return (false, lastError) }
            guard let usage = Self.hidUsage(for: code) else {
                return (false, "Unsupported key code: \(code)")
            }
            updateModifiers(flags: flags, keyCode: code, keyDown: true)
            insertKey(usage)
            if !sendReport() { return (false, lastError) }
            updateModifiers(flags: flags, keyCode: code, keyDown: false)
            removeKey(usage)
            if !sendReport() { return (false, lastError) }
            return (true, nil)
        }
    }

    func sendKey(code: CGKeyCode, flags: CGEventFlags, keyDown: Bool) -> (Bool, String?) {
        queue.sync {
            guard ensureConnected() else { return (false, lastError) }
            guard let usage = Self.hidUsage(for: code) else {
                return (false, "Unsupported key code: \(code)")
            }
            updateModifiers(flags: flags, keyCode: code, keyDown: keyDown)
            if keyDown {
                insertKey(usage)
            } else {
                removeKey(usage)
            }
            if !sendReport() { return (false, lastError) }
            return (true, nil)
        }
    }

    private func ensureConnected() -> Bool {
        if socketFD >= 0 {
            return true
        }
        lastError = nil
        keyboardReady = false
        driverActivated = false
        driverConnected = false

        guard prepareDirectories() else { return false }
        guard let serverPath = resolveServerSocketPath() else {
            lastError = "VirtualHID daemon socket not found"
            return false
        }
        serverSocketPath = serverPath

        let fd = socket(AF_UNIX, SOCK_DGRAM, 0)
        if fd < 0 {
            lastError = "Failed to create socket"
            return false
        }
        socketFD = fd

        let clientPath = makeClientSocketPath()
        clientSocketPath = clientPath
        unlink(clientPath)

        var clientAddr = sockaddr_un()
        let clientLen = fillSockAddr(&clientAddr, path: clientPath)
        let bindResult = withUnsafePointer(to: &clientAddr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { ptr in
                bind(fd, ptr, clientLen)
            }
        }
        if bindResult != 0 {
            lastError = "Failed to bind client socket"
            closeSocket()
            return false
        }

        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        source.setEventHandler { [weak self] in
            self?.readResponses()
        }
        source.setCancelHandler { [weak self] in
            guard let self else { return }
            if self.socketFD >= 0 {
                close(self.socketFD)
                self.socketFD = -1
            }
            if let clientPath = self.clientSocketPath {
                unlink(clientPath)
            }
        }
        readSource = source
        source.resume()

        guard sendInitializeKeyboard() else {
            closeSocket()
            return false
        }

        return true
    }

    private func closeSocket() {
        if let source = readSource {
            readSource = nil
            source.cancel()
        } else if socketFD >= 0 {
            close(socketFD)
            socketFD = -1
        }
        if let clientPath = clientSocketPath {
            unlink(clientPath)
        }
        clientSocketPath = nil
    }

    private func prepareDirectories() -> Bool {
        let fileManager = FileManager.default
        do {
            try fileManager.createDirectory(
                atPath: Self.clientSocketDirectory,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            return true
        } catch {
            lastError = "Failed to prepare socket directory"
            return false
        }
    }

    private func resolveServerSocketPath() -> String? {
        let fileManager = FileManager.default
        guard let entries = try? fileManager.contentsOfDirectory(atPath: Self.serverSocketDirectory) else {
            return nil
        }
        let sockets = entries.filter { $0.hasSuffix(".sock") }.sorted()
        guard let last = sockets.last else { return nil }
        return (Self.serverSocketDirectory as NSString).appendingPathComponent(last)
    }

    private func makeClientSocketPath() -> String {
        let pid = getpid()
        let timestamp = UInt64(Date().timeIntervalSince1970 * 1_000_000_000)
        let filename = String(format: "gtok.%d.%llx.sock", pid, timestamp)
        return (Self.clientSocketDirectory as NSString).appendingPathComponent(filename)
    }

    private func fillSockAddr(_ addr: inout sockaddr_un, path: String) -> socklen_t {
        addr.sun_family = sa_family_t(AF_UNIX)
        let maxLength = MemoryLayout.size(ofValue: addr.sun_path)
        var buffer = [UInt8](path.utf8)
        buffer.append(0)
        let count = min(buffer.count, maxLength)
        withUnsafeMutablePointer(to: &addr.sun_path) { pathPtr in
            pathPtr.withMemoryRebound(to: UInt8.self, capacity: maxLength) { bytes in
                bytes.initialize(repeating: 0, count: maxLength)
                bytes.assign(from: buffer, count: count)
            }
        }
        let length = socklen_t(MemoryLayout<sockaddr_un>.offset(of: \sockaddr_un.sun_path)!)
        return length + socklen_t(count)
    }

    private func sendInitializeKeyboard() -> Bool {
        let parameters = KeyboardParameters(
            vendorID: 0x16c0,
            productID: 0x27db,
            countryCode: 0
        )
        return sendRequest(
            request: .virtualHIDKeyboardInitialize,
            payload: withUnsafeBytes(of: parameters) { Array($0) }
        )
    }

    private func sendReport() -> Bool {
        updateReportBuffer()
        return sendRequest(
            request: .postKeyboardInputReport,
            payload: reportBuffer
        )
    }

    private func sendRequest(request: Request, payload: [UInt8]) -> Bool {
        guard let serverPath = serverSocketPath else {
            lastError = "VirtualHID daemon socket missing"
            return false
        }
        var serverAddr = sockaddr_un()
        let serverLen = fillSockAddr(&serverAddr, path: serverPath)
        if sendBuffer.count < 5 + payload.count {
            sendBuffer = [UInt8](repeating: 0, count: 5 + payload.count)
        }
        sendBuffer[0] = 0x63
        sendBuffer[1] = 0x70
        var version = Self.protocolVersion
        withUnsafeBytes(of: &version) { bytes in
            sendBuffer[2] = bytes[0]
            sendBuffer[3] = bytes[1]
        }
        sendBuffer[4] = request.rawValue
        if !payload.isEmpty {
            payload.withUnsafeBytes { bytes in
                if let base = bytes.baseAddress {
                    sendBuffer.withUnsafeMutableBytes { dest in
                        guard let destBase = dest.baseAddress else { return }
                        memcpy(destBase.advanced(by: 5), base, payload.count)
                    }
                }
            }
        }
        let result = sendBuffer.withUnsafeBytes { rawBuffer in
            withUnsafePointer(to: &serverAddr) { addrPtr in
                addrPtr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPtr in
                    sendto(
                        socketFD,
                        rawBuffer.baseAddress,
                        5 + payload.count,
                        0,
                        sockaddrPtr,
                        serverLen
                    )
                }
            }
        }
        if result < 0 {
            lastError = "VirtualHID sendto failed"
            return false
        }
        return true
    }

    private func readResponses() {
        var buffer = [UInt8](repeating: 0, count: 64)
        let result = buffer.withUnsafeMutableBytes { rawBuffer -> ssize_t in
            recv(socketFD, rawBuffer.baseAddress, rawBuffer.count, 0)
        }
        if result <= 0 {
            return
        }
        let count = Int(result)
        if count < 2 {
            return
        }
        guard let response = Response(rawValue: buffer[0]) else { return }
        let flag = buffer[1] != 0
        switch response {
        case .driverActivated:
            driverActivated = flag
        case .driverConnected:
            driverConnected = flag
        case .driverVersionMismatched:
            if flag {
                lastError = "VirtualHID protocol version mismatch"
            }
        case .virtualHIDKeyboardReady:
            keyboardReady = flag
        case .virtualHIDPointingReady:
            break
        case .none:
            break
        }
    }

    private func updateModifiers(flags: CGEventFlags, keyCode: CGKeyCode, keyDown: Bool) {
        if let modifier = Self.modifierMask(for: keyCode) {
            if keyDown {
                modifiers |= modifier
            } else {
                modifiers &= ~modifier
            }
        } else {
            modifiers = Self.modifiers(from: flags)
        }
    }

    private func updateReportBuffer() {
        reportBuffer[0] = 1
        reportBuffer[1] = modifiers
        reportBuffer[2] = 0
        for index in 0..<keySlots.count {
            let value = keySlots[index]
            let offset = 3 + index * 2
            reportBuffer[offset] = UInt8(value & 0xFF)
            reportBuffer[offset + 1] = UInt8((value >> 8) & 0xFF)
        }
    }

    private func insertKey(_ usage: UInt16) {
        if keySlots.contains(usage) {
            return
        }
        for index in 0..<keySlots.count where keySlots[index] == 0 {
            keySlots[index] = usage
            return
        }
    }

    private func removeKey(_ usage: UInt16) {
        for index in 0..<keySlots.count where keySlots[index] == usage {
            keySlots[index] = 0
        }
    }

    private static func modifiers(from flags: CGEventFlags) -> UInt8 {
        var result: UInt8 = 0
        if flags.contains(.maskControl) { result |= 0x01 }
        if flags.contains(.maskShift) { result |= 0x02 }
        if flags.contains(.maskAlternate) { result |= 0x04 }
        if flags.contains(.maskCommand) { result |= 0x08 }
        return result
    }

    private static func modifierMask(for keyCode: CGKeyCode) -> UInt8? {
        switch keyCode {
        case CGKeyCode(kVK_Control): return 0x01
        case CGKeyCode(kVK_Shift): return 0x02
        case CGKeyCode(kVK_Option): return 0x04
        case CGKeyCode(kVK_Command): return 0x08
        case CGKeyCode(kVK_RightControl): return 0x10
        case CGKeyCode(kVK_RightShift): return 0x20
        case CGKeyCode(kVK_RightOption): return 0x40
        case CGKeyCode(kVK_RightCommand): return 0x80
        default: return nil
        }
    }

    private static func hidUsage(for keyCode: CGKeyCode) -> UInt16? {
        let index = Int(keyCode)
        guard index >= 0, index < keyCodeToUsage.count else {
            return nil
        }
        let usage = keyCodeToUsage[index]
        return usage == 0 ? nil : usage
    }

    private static let keyCodeToUsage: [UInt16] = {
        var map = [UInt16](repeating: 0, count: 128)
        map[Int(kVK_ANSI_A)] = 0x04
        map[Int(kVK_ANSI_B)] = 0x05
        map[Int(kVK_ANSI_C)] = 0x06
        map[Int(kVK_ANSI_D)] = 0x07
        map[Int(kVK_ANSI_E)] = 0x08
        map[Int(kVK_ANSI_F)] = 0x09
        map[Int(kVK_ANSI_G)] = 0x0A
        map[Int(kVK_ANSI_H)] = 0x0B
        map[Int(kVK_ANSI_I)] = 0x0C
        map[Int(kVK_ANSI_J)] = 0x0D
        map[Int(kVK_ANSI_K)] = 0x0E
        map[Int(kVK_ANSI_L)] = 0x0F
        map[Int(kVK_ANSI_M)] = 0x10
        map[Int(kVK_ANSI_N)] = 0x11
        map[Int(kVK_ANSI_O)] = 0x12
        map[Int(kVK_ANSI_P)] = 0x13
        map[Int(kVK_ANSI_Q)] = 0x14
        map[Int(kVK_ANSI_R)] = 0x15
        map[Int(kVK_ANSI_S)] = 0x16
        map[Int(kVK_ANSI_T)] = 0x17
        map[Int(kVK_ANSI_U)] = 0x18
        map[Int(kVK_ANSI_V)] = 0x19
        map[Int(kVK_ANSI_W)] = 0x1A
        map[Int(kVK_ANSI_X)] = 0x1B
        map[Int(kVK_ANSI_Y)] = 0x1C
        map[Int(kVK_ANSI_Z)] = 0x1D
        map[Int(kVK_ANSI_1)] = 0x1E
        map[Int(kVK_ANSI_2)] = 0x1F
        map[Int(kVK_ANSI_3)] = 0x20
        map[Int(kVK_ANSI_4)] = 0x21
        map[Int(kVK_ANSI_5)] = 0x22
        map[Int(kVK_ANSI_6)] = 0x23
        map[Int(kVK_ANSI_7)] = 0x24
        map[Int(kVK_ANSI_8)] = 0x25
        map[Int(kVK_ANSI_9)] = 0x26
        map[Int(kVK_ANSI_0)] = 0x27
        map[Int(kVK_Return)] = 0x28
        map[Int(kVK_Escape)] = 0x29
        map[Int(kVK_Delete)] = 0x2A
        map[Int(kVK_Tab)] = 0x2B
        map[Int(kVK_Space)] = 0x2C
        map[Int(kVK_ANSI_Minus)] = 0x2D
        map[Int(kVK_ANSI_Equal)] = 0x2E
        map[Int(kVK_ANSI_LeftBracket)] = 0x2F
        map[Int(kVK_ANSI_RightBracket)] = 0x30
        map[Int(kVK_ANSI_Backslash)] = 0x31
        map[Int(kVK_ANSI_Semicolon)] = 0x33
        map[Int(kVK_ANSI_Quote)] = 0x34
        map[Int(kVK_ANSI_Grave)] = 0x35
        map[Int(kVK_ANSI_Comma)] = 0x36
        map[Int(kVK_ANSI_Period)] = 0x37
        map[Int(kVK_ANSI_Slash)] = 0x38
        map[Int(kVK_CapsLock)] = 0x39
        map[Int(kVK_F1)] = 0x3A
        map[Int(kVK_F2)] = 0x3B
        map[Int(kVK_F3)] = 0x3C
        map[Int(kVK_F4)] = 0x3D
        map[Int(kVK_F5)] = 0x3E
        map[Int(kVK_F6)] = 0x3F
        map[Int(kVK_F7)] = 0x40
        map[Int(kVK_F8)] = 0x41
        map[Int(kVK_F9)] = 0x42
        map[Int(kVK_F10)] = 0x43
        map[Int(kVK_F11)] = 0x44
        map[Int(kVK_F12)] = 0x45
        map[Int(kVK_Home)] = 0x4A
        map[Int(kVK_PageUp)] = 0x4B
        map[Int(kVK_ForwardDelete)] = 0x4C
        map[Int(kVK_End)] = 0x4D
        map[Int(kVK_PageDown)] = 0x4E
        map[Int(kVK_RightArrow)] = 0x4F
        map[Int(kVK_LeftArrow)] = 0x50
        map[Int(kVK_DownArrow)] = 0x51
        map[Int(kVK_UpArrow)] = 0x52
        map[Int(kVK_ANSI_KeypadClear)] = 0x53
        map[Int(kVK_ANSI_KeypadDivide)] = 0x54
        map[Int(kVK_ANSI_KeypadMultiply)] = 0x55
        map[Int(kVK_ANSI_KeypadMinus)] = 0x56
        map[Int(kVK_ANSI_KeypadPlus)] = 0x57
        map[Int(kVK_ANSI_KeypadEnter)] = 0x58
        map[Int(kVK_ANSI_Keypad1)] = 0x59
        map[Int(kVK_ANSI_Keypad2)] = 0x5A
        map[Int(kVK_ANSI_Keypad3)] = 0x5B
        map[Int(kVK_ANSI_Keypad4)] = 0x5C
        map[Int(kVK_ANSI_Keypad5)] = 0x5D
        map[Int(kVK_ANSI_Keypad6)] = 0x5E
        map[Int(kVK_ANSI_Keypad7)] = 0x5F
        map[Int(kVK_ANSI_Keypad8)] = 0x60
        map[Int(kVK_ANSI_Keypad9)] = 0x61
        map[Int(kVK_ANSI_Keypad0)] = 0x62
        map[Int(kVK_ANSI_KeypadDecimal)] = 0x63
        map[Int(kVK_F13)] = 0x68
        map[Int(kVK_F14)] = 0x69
        map[Int(kVK_F15)] = 0x6A
        map[Int(kVK_F16)] = 0x6B
        map[Int(kVK_F17)] = 0x6C
        map[Int(kVK_F18)] = 0x6D
        map[Int(kVK_F19)] = 0x6E
        return map
    }()
}
