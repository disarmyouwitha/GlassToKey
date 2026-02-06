import AVFoundation
import Foundation
import Speech

final class VoiceDictationManager: NSObject, @unchecked Sendable {
    static let shared = VoiceDictationManager()

    private let queue = DispatchQueue(
        label: "com.kyome.GlassToKey.VoiceDictation",
        qos: .userInitiated
    )
    private let textReplacer = AccessibilityTextReplacer()

    private var recognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var audioEngine = AVAudioEngine()
    private var latestTranscript = ""
    private var isSessionActive = false
    private var statusHandler: (@Sendable (String?) -> Void)?

    func setStatusHandler(_ handler: (@Sendable (String?) -> Void)?) {
        queue.async { [weak self] in
            self?.statusHandler = handler
        }
    }

    func beginSession() {
        queue.async { [weak self] in
            self?.beginSessionLocked()
        }
    }

    func endSession() {
        queue.async { [weak self] in
            self?.endSessionLocked(commitTranscript: true)
        }
    }

    private func beginSessionLocked() {
        guard !isSessionActive else { return }
        emitStatus("voice: requesting permission")
        guard ensureAuthorization() else { return }
        guard configureRecognitionLocked() else {
            teardownRecognitionLocked()
            return
        }
        isSessionActive = true
        emitStatus("voice: listening")
    }

    private func ensureAuthorization() -> Bool {
        final class SpeechStatusBox: @unchecked Sendable {
            var value: SFSpeechRecognizerAuthorizationStatus = .notDetermined
        }
        final class BoolBox: @unchecked Sendable {
            var value = false
        }

        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized:
            break
        case .notDetermined:
            let semaphore = DispatchSemaphore(value: 0)
            let statusBox = SpeechStatusBox()
            SFSpeechRecognizer.requestAuthorization { status in
                statusBox.value = status
                semaphore.signal()
            }
            semaphore.wait()
            guard statusBox.value == .authorized else {
                emitStatus("voice: speech permission denied")
                return false
            }
        case .denied, .restricted:
            emitStatus("voice: speech permission denied")
            return false
        @unknown default:
            emitStatus("voice: speech permission denied")
            return false
        }

        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return true
        case .notDetermined:
            let semaphore = DispatchSemaphore(value: 0)
            let grantedBox = BoolBox()
            DispatchQueue.main.async {
                AVCaptureDevice.requestAccess(for: .audio) { allowed in
                    grantedBox.value = allowed
                    semaphore.signal()
                }
            }
            semaphore.wait()
            if !grantedBox.value {
                emitStatus("voice: microphone permission denied")
            }
            return grantedBox.value
        case .denied, .restricted:
            emitStatus("voice: microphone permission denied")
            return false
        @unknown default:
            emitStatus("voice: microphone permission denied")
            return false
        }
    }

    private func configureRecognitionLocked() -> Bool {
        latestTranscript = ""
        recognizer = makeAvailableRecognizer()
        guard let recognizer, recognizer.isAvailable else { return false }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        if #available(macOS 13.0, *) {
            request.requiresOnDeviceRecognition = false
        }
        recognitionRequest = request

        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            let transcript = result?.bestTranscription.formattedString
            let isFinal = result?.isFinal ?? false
            let hasError = error != nil
            self?.queue.async { [weak self] in
                guard let self else { return }
                if let transcript, !transcript.isEmpty {
                    self.latestTranscript = transcript
                }
                if hasError {
                    self.endSessionLocked(commitTranscript: true)
                    return
                }
                if isFinal, let transcript, !transcript.isEmpty {
                    self.latestTranscript = transcript
                }
            }
        }

        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            request.append(buffer)
        }
        engine.prepare()

        do {
            try engine.start()
        } catch {
            inputNode.removeTap(onBus: 0)
            emitStatus("voice: audio start failed")
            return false
        }

        audioEngine = engine
        return true
    }

    private func endSessionLocked(commitTranscript: Bool) {
        guard isSessionActive || recognitionTask != nil || recognitionRequest != nil else { return }
        let transcript = latestTranscript
        teardownRecognitionLocked()

        guard commitTranscript else { return }
        let text = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            emitStatus("voice: no speech detected")
            return
        }
        if textReplacer.insertTextAtCaret(text) {
            emitStatus("voice: inserted")
            return
        }
        if typeTextFallback(text) {
            emitStatus("voice: typed fallback")
            return
        }
        emitStatus("voice: insert failed")
    }

    private func teardownRecognitionLocked() {
        if audioEngine.isRunning {
            audioEngine.stop()
        }
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil
        recognizer = nil
        isSessionActive = false
    }

    private func makeAvailableRecognizer() -> SFSpeechRecognizer? {
        let preferredLocales = [
            Locale.current,
            Locale(identifier: "en_US")
        ]
        for locale in preferredLocales {
            if let recognizer = SFSpeechRecognizer(locale: locale), recognizer.isAvailable {
                return recognizer
            }
        }
        if let recognizer = SFSpeechRecognizer(), recognizer.isAvailable {
            return recognizer
        }
        emitStatus("voice: recognizer unavailable")
        return nil
    }

    private func typeTextFallback(_ text: String) -> Bool {
        let normalized = normalizeForASCIIKeyTyping(text)
        guard KeySemanticMapper.canTypeASCII(normalized),
              let strokes = KeySemanticMapper.keyStrokes(for: normalized) else {
            return false
        }
        for stroke in strokes {
            KeyEventDispatcher.shared.postKeyStroke(code: stroke.code, flags: stroke.flags)
        }
        return true
    }

    private func normalizeForASCIIKeyTyping(_ text: String) -> String {
        var normalized = text
        normalized = normalized.replacingOccurrences(of: "\u{2018}", with: "'")
        normalized = normalized.replacingOccurrences(of: "\u{2019}", with: "'")
        normalized = normalized.replacingOccurrences(of: "\u{201C}", with: "\"")
        normalized = normalized.replacingOccurrences(of: "\u{201D}", with: "\"")
        normalized = normalized.replacingOccurrences(of: "\u{2013}", with: "-")
        normalized = normalized.replacingOccurrences(of: "\u{2014}", with: "-")
        normalized = normalized.replacingOccurrences(of: "\u{2026}", with: "...")
        return normalized
    }

    private func emitStatus(_ message: String?) {
        statusHandler?(message)
    }
}
