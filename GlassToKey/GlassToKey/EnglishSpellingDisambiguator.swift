import AppKit
import Foundation
import os

struct KeyCandidate: Sendable {
    let ascii: UInt8
    let geometricWeight: Double
}

enum KeyResolution: Sendable {
    case certain(UInt8)
    case ambiguous([KeyCandidate])
}

final class EnglishSpellingDisambiguator: @unchecked Sendable {
    private struct BeamPath {
        var bytes: [UInt8]
        var score: Double
    }

    private struct PrefixKey: Hashable {
        private let low: UInt64
        private let high: UInt64
        private let length: UInt8

        init(bytes: [UInt8]) {
            var lowValue: UInt64 = 0
            var highValue: UInt64 = 0
            var shift: UInt64 = 0
            for (index, byte) in bytes.enumerated() {
                let value = UInt64(byte)
                if index < 8 {
                    lowValue |= value << shift
                    shift += 8
                } else {
                    highValue |= value << ((UInt64(index - 8)) * 8)
                }
            }
            self.low = lowValue
            self.high = highValue
            self.length = UInt8(bytes.count)
        }
    }

    private final class PrefixCompletionCache {
        private final class Node {
            let key: PrefixKey
            var value: Int
            var prev: Node?
            var next: Node?

            init(key: PrefixKey, value: Int) {
                self.key = key
                self.value = value
            }
        }

        private let capacity: Int
        private var map: [PrefixKey: Node] = [:]
        private var head: Node?
        private var tail: Node?
        private let lock = OSAllocatedUnfairLock<()> (uncheckedState: ())

        init(capacity: Int) {
            self.capacity = max(8, capacity)
        }

        func get(_ key: PrefixKey) -> Int? {
            lock.withLockUnchecked {
                guard let node = map[key] else { return nil }
                moveToHead(node)
                return node.value
            }
        }

        func put(_ key: PrefixKey, value: Int) {
            lock.withLockUnchecked {
                if let node = map[key] {
                    node.value = value
                    moveToHead(node)
                    return
                }
                let node = Node(key: key, value: value)
                map[key] = node
                insertAtHead(node)
                if map.count > capacity {
                    removeTail()
                }
            }
        }

        private func moveToHead(_ node: Node) {
            guard head !== node else { return }
            let prev = node.prev
            let next = node.next
            prev?.next = next
            next?.prev = prev
            if tail === node {
                tail = prev
            }
            node.prev = nil
            node.next = head
            head?.prev = node
            head = node
            if tail == nil {
                tail = node
            }
        }

        private func insertAtHead(_ node: Node) {
            node.prev = nil
            node.next = head
            head?.prev = node
            head = node
            if tail == nil {
                tail = node
            }
        }

        private func removeTail() {
            guard let node = tail else { return }
            map[node.key] = nil
            let prev = node.prev
            prev?.next = nil
            tail = prev
            if tail == nil {
                head = nil
            }
        }
    }

    private let spellChecker: NSSpellChecker
    private let spellDocumentTag: Int
    private let cache = PrefixCompletionCache(capacity: 2048)
    private let pendingLock = OSAllocatedUnfairLock<()> (uncheckedState: ())
    private var pendingPrefixes = Set<PrefixKey>()

    private var beam: [BeamPath] = [BeamPath(bytes: [], score: 0)]
    private var nextBeam: [BeamPath] = []
    private var pendingBeam: [BeamPath]?
    private var pendingCommitAscii: UInt8 = 0

    private let beamWidthK = 5
    private let maxPrefixLen = 32
    private let minCompletionPrefixLen = 2
    private let maxCompletionPrefixLen = 12
    private let alpha = 0.35
    private let beta = 0.55

    init(spellChecker: NSSpellChecker, spellDocumentTag: Int) {
        self.spellChecker = spellChecker
        self.spellDocumentTag = spellDocumentTag
        nextBeam.reserveCapacity(beamWidthK * 5)
        if beam.isEmpty {
            beam = [BeamPath(bytes: [], score: 0)]
        }
        beam[0].bytes.reserveCapacity(maxPrefixLen)
    }

    func resolve(resolution: KeyResolution, currentToken: [UInt8]) -> UInt8 {
        if !currentToken.isEmpty {
            syncBeamIfNeeded(with: currentToken)
        }
        switch resolution {
        case let .certain(ascii):
            pendingBeam = nil
            pendingCommitAscii = 0
            return ascii
        case let .ambiguous(candidates):
            guard !candidates.isEmpty else { return 0 }
            if beam.isEmpty {
                beam = [BeamPath(bytes: [], score: 0)]
            }
            nextBeam.removeAll(keepingCapacity: true)
            for path in beam {
                for candidate in candidates {
                    guard candidate.ascii > 0 else { continue }
                    let weight = max(candidate.geometricWeight, 1e-6)
                    var bytes = path.bytes
                    if bytes.count >= maxPrefixLen {
                        continue
                    }
                    bytes.append(candidate.ascii)
                    bytes.reserveCapacity(maxPrefixLen)
                    let bonus = spellingBonus(for: bytes)
                    let score = path.score + log(weight) + bonus
                    nextBeam.append(BeamPath(bytes: bytes, score: score))
                }
            }
            guard !nextBeam.isEmpty else {
                pendingBeam = nil
                pendingCommitAscii = candidates[0].ascii
                return pendingCommitAscii
            }
            nextBeam.sort { $0.score > $1.score }
            if nextBeam.count > beamWidthK {
                nextBeam.removeSubrange(beamWidthK..<nextBeam.count)
            }
            pendingBeam = nextBeam
            pendingCommitAscii = nextBeam[0].bytes.last ?? candidates[0].ascii
            return pendingCommitAscii
        }
    }

    func onCommittedChar(_ ascii: UInt8) {
        if let pendingBeam, ascii == pendingCommitAscii {
            beam = pendingBeam
        } else {
            appendToBeam(ascii)
        }
        pendingBeam = nil
        pendingCommitAscii = 0
    }

    func onBoundary() {
        beam = [BeamPath(bytes: [], score: 0)]
        pendingBeam = nil
        pendingCommitAscii = 0
    }

    func onBackspace() {
        if beam.isEmpty {
            beam = [BeamPath(bytes: [], score: 0)]
            return
        }
        for index in beam.indices {
            if !beam[index].bytes.isEmpty {
                beam[index].bytes.removeLast()
            }
        }
        pendingBeam = nil
        pendingCommitAscii = 0
    }

    private func syncBeamIfNeeded(with token: [UInt8]) {
        guard beam.count == 1 else { return }
        if beam[0].bytes.count == token.count {
            return
        }
        var clamped = token
        if clamped.count > maxPrefixLen {
            clamped = Array(clamped.suffix(maxPrefixLen))
        }
        beam = [BeamPath(bytes: clamped, score: 0)]
    }

    private func appendToBeam(_ ascii: UInt8) {
        if beam.isEmpty {
            beam = [BeamPath(bytes: [ascii], score: 0)]
            return
        }
        for index in beam.indices {
            if beam[index].bytes.count >= maxPrefixLen {
                beam[index].bytes.removeFirst()
            }
            beam[index].bytes.append(ascii)
        }
    }

    private func spellingBonus(for prefixBytes: [UInt8]) -> Double {
        guard spellingModelEnabled(for: prefixBytes) else { return 0 }
        let length = prefixBytes.count
        guard length >= minCompletionPrefixLen,
              length <= maxCompletionPrefixLen else {
            return 0
        }
        let key = PrefixKey(bytes: prefixBytes)
        if let count = cache.get(key) {
            if count == 0 {
                return -beta
            }
            return alpha * log(1.0 + Double(count))
        }
        enqueuePrefixLookup(key: key, bytes: prefixBytes)
        return -beta
    }

    private func spellingModelEnabled(for bytes: [UInt8]) -> Bool {
        guard !bytes.isEmpty else { return false }
        if bytes.count > maxPrefixLen { return false }
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
            return false
        }
        if !hasLetter { return false }
        if allCaps && bytes.count >= 2 { return false }
        return true
    }

    private func enqueuePrefixLookup(key: PrefixKey, bytes: [UInt8]) {
        let shouldEnqueue = pendingLock.withLockUnchecked { () -> Bool in
            if pendingPrefixes.contains(key) {
                return false
            }
            pendingPrefixes.insert(key)
            return true
        }
        guard shouldEnqueue else { return }
        let prefixBytes = bytes
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let count = self.fetchCompletionCount(bytes: prefixBytes)
            self.cache.put(key, value: count)
            self.pendingLock.withLockUnchecked {
                self.pendingPrefixes.remove(key)
            }
        }
    }

    private func fetchCompletionCount(bytes: [UInt8]) -> Int {
        guard let prefix = String(bytes: bytes, encoding: .ascii) else { return 0 }
        let range = NSRange(location: 0, length: prefix.utf16.count)
        let results = spellChecker.completions(
            forPartialWordRange: range,
            in: prefix,
            language: "en_US",
            inSpellDocumentWithTag: spellDocumentTag
        )
        return results?.count ?? 0
    }
}
