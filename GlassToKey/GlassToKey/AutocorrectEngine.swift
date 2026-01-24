import AppKit
import Carbon
import Dispatch
import Foundation
import Darwin

// Autocorrect enable flow:
// 1) Toggle "Autocorrect" in the app.
// 2) Type a misspelled word followed by space/punctuation/return.
// 3) The engine replaces the last word using AX when available, or backspace-retype as fallback.
//    AX may be unsupported in secure fields or some apps, which triggers the fallback path.
final class AutocorrectEngine: @unchecked Sendable {
    static let shared = AutocorrectEngine()

    private static let capacity = 2048
    private static let mask = capacity - 1

    nonisolated(unsafe) private static var enabledFlag: Int32 = 0
    nonisolated(unsafe) private static var suppressionCount: Int64 = 0

    private let queue: DispatchQueue
    private let wakeSource: DispatchSourceUserDataAdd
    private let spellChecker: NSSpellChecker
    private let spellDocumentTag: Int
    private let textReplacer = AccessibilityTextReplacer()

    nonisolated(unsafe) private var writeIndex: Int64 = 0
    private var readIndex: Int64 = 0
    private let storage: UnsafeMutableBufferPointer<KeySemanticEvent>

    private var wordBuffer: [UInt8] = []
    private var wordHadBackspaceEdit = false
    private let minWordLength = 3
    private let maxWordLength = 64

    private init() {
        precondition(Self.capacity > 0 && (Self.capacity & Self.mask) == 0)
        let pointer = UnsafeMutablePointer<KeySemanticEvent>.allocate(capacity: Self.capacity)
        pointer.initialize(repeating: KeySemanticEvent.empty, count: Self.capacity)
        storage = UnsafeMutableBufferPointer(start: pointer, count: Self.capacity)

        spellChecker = NSSpellChecker.shared
        spellDocumentTag = NSSpellChecker.uniqueSpellDocumentTag()

        queue = DispatchQueue(label: "com.kyome.GlassToKey.Autocorrect", qos: .utility)
        wakeSource = DispatchSource.makeUserDataAddSource(queue: queue)
        wakeSource.setEventHandler { [weak self] in
            self?.drain()
        }
        wakeSource.resume()

        wordBuffer.reserveCapacity(maxWordLength)
    }

    func setEnabled(_ enabled: Bool) {
        let value: Int32 = enabled ? 1 : 0
        var current = OSAtomicAdd32Barrier(0, &Self.enabledFlag)
        while !OSAtomicCompareAndSwap32Barrier(current, value, &Self.enabledFlag) {
            current = OSAtomicAdd32Barrier(0, &Self.enabledFlag)
        }
        if !enabled {
            queue.async { [weak self] in
                self?.wordBuffer.removeAll(keepingCapacity: true)
            }
        }
    }

    func recordDispatchedKey(code: CGKeyCode, flags: CGEventFlags, keyDown: Bool) {
        guard keyDown else { return }
        guard isEnabled else { return }
        guard !isSuppressed else { return }
        guard let event = KeySemanticMapper.semanticEvent(
            code: code,
            flags: flags,
            timestampNs: DispatchTime.now().uptimeNanoseconds
        ) else {
            return
        }
        enqueue(event)
    }

    private var isEnabled: Bool {
        OSAtomicAdd32Barrier(0, &Self.enabledFlag) != 0
    }

    private var isSuppressed: Bool {
        OSAtomicAdd64Barrier(0, &Self.suppressionCount) > 0
    }

    private func enqueue(_ event: KeySemanticEvent) {
        let index = OSAtomicIncrement64Barrier(&writeIndex) - 1
        let slot = Int(index) & Self.mask
        storage[slot] = event
        wakeSource.add(data: 1)
    }

    private func drain() {
        let end = OSAtomicAdd64Barrier(0, &writeIndex)
        guard end > readIndex else { return }
        if !isEnabled {
            readIndex = end
            wordBuffer.removeAll(keepingCapacity: true)
            wordHadBackspaceEdit = false
            return
        }
        let pending = end - readIndex
        if pending > Int64(Self.capacity) {
            readIndex = end - Int64(Self.capacity)
        }
        while readIndex < end {
            let event = storage[Int(readIndex) & Self.mask]
            readIndex += 1
            process(event)
        }
    }

    private func process(_ event: KeySemanticEvent) {
        switch event.kind {
        case .text:
            guard wordBuffer.count < maxWordLength else { return }
            wordBuffer.append(event.ascii)
        case .backspace:
            if !wordBuffer.isEmpty {
                wordBuffer.removeLast()
            }
            wordHadBackspaceEdit = true
        case .boundary:
            if !wordBuffer.isEmpty && !wordHadBackspaceEdit {
                attemptCorrection(boundaryEvent: event)
            }
            wordBuffer.removeAll(keepingCapacity: true)
            wordHadBackspaceEdit = false
        case .nonText:
            wordBuffer.removeAll(keepingCapacity: true)
            wordHadBackspaceEdit = false
        }
    }

    private func attemptCorrection(boundaryEvent: KeySemanticEvent) {
        guard shouldConsiderWord(wordBuffer) else { return }
        guard let word = String(bytes: wordBuffer, encoding: .ascii) else { return }
        let wordRange = NSRange(location: 0, length: word.utf16.count)
        let language = spellChecker.language(
            forWordRange: wordRange,
            in: word,
            orthography: nil
        ) ?? "en_US"
        guard let correction = spellChecker.correction(
            forWordRange: wordRange,
            in: word,
            language: language,
            inSpellDocumentWithTag: spellDocumentTag
        ) else {
            return
        }
        guard correction != word else { return }
        guard KeySemanticMapper.canTypeASCII(correction) else { return }

        let boundaryLength = boundaryEvent.boundaryLength
        if textReplacer.replaceLastWord(
            wordLength: wordBuffer.count,
            boundaryLength: boundaryLength,
            replacement: correction
        ) {
            return
        }

        fallbackBackspaceRetype(
            originalWordLength: wordBuffer.count,
            boundaryEvent: boundaryEvent,
            replacement: correction
        )
    }

    private func shouldConsiderWord(_ bytes: [UInt8]) -> Bool {
        guard bytes.count >= minWordLength else { return false }
        var hasLetter = false
        var allCaps = true
        for byte in bytes {
            if byte >= 65 && byte <= 90 {
                hasLetter = true
                continue
            }
            if byte >= 97 && byte <= 122 {
                hasLetter = true
                allCaps = false
                continue
            }
            if byte >= 48 && byte <= 57 { return false }
            if byte == UInt8(ascii: "_") { return false }
            if byte == UInt8(ascii: "/") { return false }
            if byte == UInt8(ascii: ".") { return false }
            allCaps = false
        }
        guard hasLetter else { return false }
        if allCaps { return false }
        return true
    }

    private func fallbackBackspaceRetype(
        originalWordLength: Int,
        boundaryEvent: KeySemanticEvent,
        replacement: String
    ) {
        guard let strokes = KeySemanticMapper.keyStrokes(for: replacement) else { return }
        let boundaryLength = boundaryEvent.boundaryLength
        let totalDeletes = originalWordLength + boundaryLength

        OSAtomicIncrement64Barrier(&Self.suppressionCount)
        defer { OSAtomicDecrement64Barrier(&Self.suppressionCount) }

        if totalDeletes > 0 {
            for _ in 0..<totalDeletes {
                KeyEventDispatcher.shared.postKeyStroke(code: CGKeyCode(kVK_Delete), flags: [])
            }
        }
        for stroke in strokes {
            KeyEventDispatcher.shared.postKeyStroke(code: stroke.code, flags: stroke.flags)
        }
        if boundaryLength > 0 {
            KeyEventDispatcher.shared.postKeyStroke(code: boundaryEvent.code, flags: boundaryEvent.flags)
        }
    }
}
