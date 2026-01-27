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
    private static let historyCapacity = 3
    private static let maxContextCharacters = 280
    private static let contextBoundaryCharacterSet: CharacterSet =
        CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters)

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
    private var autocorrectBuffer: [UInt8] = []
    private var contextBuffer: [UInt8] = []
    private var historyBuffers: [[UInt8]] = []
    private var historyHead = 0
    private var historyCount = 0
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
        autocorrectBuffer.reserveCapacity(maxWordLength)
        historyBuffers = Array(repeating: [], count: Self.historyCapacity)
        for index in 0..<historyBuffers.count {
            historyBuffers[index].reserveCapacity(maxWordLength)
        }
        contextBuffer.reserveCapacity(Self.maxContextCharacters)
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
                self?.autocorrectBuffer.removeAll(keepingCapacity: true)
                self?.contextBuffer.removeAll(keepingCapacity: true)
                self?.resetHistory()
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
            autocorrectBuffer.removeAll(keepingCapacity: true)
            resetHistory()
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
            if autocorrectBuffer.count < maxWordLength {
                autocorrectBuffer.append(event.ascii)
            }
        case .backspace:
            if !wordBuffer.isEmpty {
                wordBuffer.removeLast()
                if !autocorrectBuffer.isEmpty {
                    autocorrectBuffer.removeLast()
                }
            } else {
                _ = resurrectPreviousWord()
                autocorrectBuffer.removeAll(keepingCapacity: true)
            }
        case .boundary:
            if !wordBuffer.isEmpty {
                let originalBytes = wordBuffer
                var committedBytes = originalBytes
                if autocorrectBuffer.count == wordBuffer.count,
                   let correctedBytes = attemptCorrection(bytes: autocorrectBuffer, boundaryEvent: event) {
                    committedBytes = correctedBytes
                    pushHistory(bytes: correctedBytes)
                } else {
                    pushHistoryFromCurrent()
                }
                commitWordToContext(committedBytes, boundaryEvent: event)
                wordBuffer.removeAll(keepingCapacity: true)
                autocorrectBuffer.removeAll(keepingCapacity: true)
            }
        case .nonText:
            wordBuffer.removeAll(keepingCapacity: true)
            autocorrectBuffer.removeAll(keepingCapacity: true)
            resetHistory()
            contextBuffer.removeAll(keepingCapacity: true)
        }
    }

    private func attemptCorrection(bytes: [UInt8], boundaryEvent: KeySemanticEvent) -> [UInt8]? {
        guard shouldConsiderWord(bytes) else { return nil }
        guard let word = String(bytes: bytes, encoding: .ascii) else { return nil }
        let fallbackRange = NSRange(location: 0, length: word.utf16.count)
        let (contextString, wordRange) =
            contextStringForCorrection(currentWordBytes: bytes) ?? (word, fallbackRange)
        let language = spellChecker.language(
            forWordRange: wordRange,
            in: contextString,
            orthography: nil
        ) ?? "en_US"
        guard let correction = spellChecker.correction(
            forWordRange: wordRange,
            in: contextString,
            language: language,
            inSpellDocumentWithTag: spellDocumentTag
        ) else {
            return nil
        }
        guard correction != word else { return nil }
        guard KeySemanticMapper.canTypeASCII(correction) else { return nil }

        let correctionBytes = [UInt8](correction.utf8)
        let boundaryLength = boundaryEvent.boundaryLength
        if textReplacer.replaceLastWord(
            wordLength: bytes.count,
            boundaryLength: boundaryLength,
            replacement: correction
        ) {
            return correctionBytes
        }

        fallbackBackspaceRetype(
            originalWordLength: bytes.count,
            boundaryEvent: boundaryEvent,
            replacement: correction
        )
        return correctionBytes
    }

    private func commitWordToContext(_ wordBytes: [UInt8], boundaryEvent: KeySemanticEvent) {
        guard !wordBytes.isEmpty else { return }
        contextBuffer.append(contentsOf: wordBytes)
        appendBoundaryByte(for: boundaryEvent)
        trimContextIfNeeded()
    }

    private func appendBoundaryByte(for boundaryEvent: KeySemanticEvent) {
        let ascii = boundaryEvent.ascii
        if ascii != 0 {
            contextBuffer.append(ascii)
            return
        }
        contextBuffer.append(UInt8(ascii: " "))
    }

    private func trimContextIfNeeded() {
        let excess = contextBuffer.count - Self.maxContextCharacters
        if excess > 0 {
            contextBuffer.removeFirst(excess)
        }
    }

    private func contextStringForCorrection(currentWordBytes: [UInt8]) -> (String, NSRange)? {
        guard let currentWord = String(bytes: currentWordBytes, encoding: .ascii) else { return nil }
        let prefix: String
        if contextBuffer.isEmpty {
            prefix = ""
        } else {
            guard let decoded = String(bytes: contextBuffer, encoding: .ascii) else { return nil }
            prefix = decoded
        }
        var context = prefix
        if !context.isEmpty, needsSeparatorBeforeAppending(to: context) {
            context.append(" ")
        }
        let wordStart = context.utf16.count
        context.append(currentWord)
        let wordRange = NSRange(location: wordStart, length: currentWord.utf16.count)
        return (context, wordRange)
    }

    private func needsSeparatorBeforeAppending(to prefix: String) -> Bool {
        guard let lastScalar = prefix.unicodeScalars.last else { return false }
        return !Self.contextBoundaryCharacterSet.contains(lastScalar)
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

    @inline(__always)
    private func resetHistory() {
        historyHead = 0
        historyCount = 0
    }

    @inline(__always)
    private func pushHistoryFromCurrent() {
        guard !wordBuffer.isEmpty else { return }
        let slot = historyHead
        if !historyBuffers.isEmpty {
            swap(&wordBuffer, &historyBuffers[slot])
        }
        historyHead = (historyHead + 1) % Self.historyCapacity
        if historyCount < Self.historyCapacity {
            historyCount += 1
        }
    }

    @inline(__always)
    private func pushHistory(bytes: [UInt8]) {
        guard !bytes.isEmpty else { return }
        let slot = historyHead
        historyBuffers[slot].removeAll(keepingCapacity: true)
        historyBuffers[slot].append(contentsOf: bytes)
        historyHead = (historyHead + 1) % Self.historyCapacity
        if historyCount < Self.historyCapacity {
            historyCount += 1
        }
    }

    @inline(__always)
    private func resurrectPreviousWord() -> Bool {
        guard historyCount > 0 else { return false }
        let lastIndex = (historyHead - 1 + Self.historyCapacity) % Self.historyCapacity
        if !historyBuffers.isEmpty {
            swap(&wordBuffer, &historyBuffers[lastIndex])
        }
        historyHead = lastIndex
        historyCount -= 1
        return true
    }
}
