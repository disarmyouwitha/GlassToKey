import ApplicationServices
import AppKit
import Dispatch
import Foundation

final class AccessibilityTextReplacer: @unchecked Sendable {
    private let maxDurationNs: UInt64 = 20_000_000
    private static let axBlockedBundleIDs: Set<String> = [
        "com.googlecode.iterm2"
    ]

    func replaceLastWord(
        wordLength: Int,
        boundaryLength: Int,
        replacement: String
    ) -> Bool {
        guard wordLength > 0 else { return false }
        guard AXIsProcessTrusted() else { return false }
        let startTime = DispatchTime.now().uptimeNanoseconds

        let system = AXUIElementCreateSystemWide()
        var focusedValue: CFTypeRef?
        let focusedResult = AXUIElementCopyAttributeValue(
            system,
            kAXFocusedUIElementAttribute as CFString,
            &focusedValue
        )
        guard focusedResult == .success, let focused = focusedValue else { return false }
        guard CFGetTypeID(focused) == AXUIElementGetTypeID() else { return false }
        let element = unsafeDowncast(focused as AnyObject, to: AXUIElement.self)

        var pid: pid_t = 0
        let pidResult = AXUIElementGetPid(element, &pid)
        if pidResult == .success, pid == getpid() {
            return false
        }
        if pidResult == .success,
           let app = NSRunningApplication(processIdentifier: pid),
           let bundleID = app.bundleIdentifier,
           Self.axBlockedBundleIDs.contains(bundleID) {
            return false
        }

        var isSettable = DarwinBoolean(false)
        let settableResult = AXUIElementIsAttributeSettable(
            element,
            kAXSelectedTextRangeAttribute as CFString,
            &isSettable
        )
        guard settableResult == .success, isSettable.boolValue else { return false }

        var rangeValue: CFTypeRef?
        let rangeResult = AXUIElementCopyAttributeValue(
            element,
            kAXSelectedTextRangeAttribute as CFString,
            &rangeValue
        )
        guard rangeResult == .success, let rangeValue else { return false }
        guard CFGetTypeID(rangeValue) == AXValueGetTypeID() else { return false }
        let axRange = (rangeValue as! AXValue)
        guard AXValueGetType(axRange) == .cfRange else {
            return false
        }

        var selectedRange = CFRange()
        guard AXValueGetValue(axRange, .cfRange, &selectedRange) else { return false }
        guard selectedRange.length == 0 else { return false }
        let originalCaret = selectedRange

        let caretLocation = selectedRange.location
        let targetStart = caretLocation - boundaryLength - wordLength
        guard targetStart >= 0 else { return false }
        let replaceRange = CFRange(location: targetStart, length: wordLength)

        if elapsedNs(since: startTime) > maxDurationNs {
            restoreCaret(element: element, caret: originalCaret)
            return false
        }

        var replaceRangeForSet = replaceRange
        guard let rangeValueForSet = AXValueCreate(.cfRange, &replaceRangeForSet) else {
            return false
        }
        let setRangeResult = AXUIElementSetAttributeValue(
            element,
            kAXSelectedTextRangeAttribute as CFString,
            rangeValueForSet
        )
        guard setRangeResult == .success else { return false }

        if elapsedNs(since: startTime) > maxDurationNs { return false }

        let setTextResult = AXUIElementSetAttributeValue(
            element,
            kAXSelectedTextAttribute as CFString,
            replacement as CFString
        )
        guard setTextResult == .success else {
            restoreCaret(element: element, caret: originalCaret)
            return false
        }

        if !verifyReplacement(
            element: element,
            targetStart: targetStart,
            replacement: replacement,
            originalCaret: originalCaret,
            startTime: startTime
        ) {
            return false
        }

        if boundaryLength > 0 {
            var caretRange = CFRange(
                location: targetStart + replacement.utf16.count + boundaryLength,
                length: 0
            )
            if let caretValue = AXValueCreate(.cfRange, &caretRange) {
                _ = AXUIElementSetAttributeValue(
                    element,
                    kAXSelectedTextRangeAttribute as CFString,
                    caretValue
                )
            }
        }

        return true
    }

    private func verifyReplacement(
        element: AXUIElement,
        targetStart: Int,
        replacement: String,
        originalCaret: CFRange,
        startTime: UInt64
    ) -> Bool {
        if elapsedNs(since: startTime) > maxDurationNs {
            restoreCaret(element: element, caret: originalCaret)
            return false
        }

        if let selectedText = copySelectedText(element: element) {
            if selectedText == replacement {
                return true
            }
        }

        if let selectedRange = copySelectedRange(element: element),
           selectedRange.length == 0 {
            var replaceRange = CFRange(location: targetStart, length: replacement.utf16.count)
            if let rangeValue = AXValueCreate(.cfRange, &replaceRange) {
                let setRangeResult = AXUIElementSetAttributeValue(
                    element,
                    kAXSelectedTextRangeAttribute as CFString,
                    rangeValue
                )
                if setRangeResult == .success {
                    if let reselectedText = copySelectedText(element: element),
                       reselectedText == replacement {
                        restoreCaret(element: element, caret: originalCaret)
                        return true
                    }
                }
            }
        }

        restoreCaret(element: element, caret: originalCaret)
        return false
    }

    private func copySelectedText(element: AXUIElement) -> String? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(
            element,
            kAXSelectedTextAttribute as CFString,
            &value
        )
        guard result == .success, let value else { return nil }
        if CFGetTypeID(value) != CFStringGetTypeID() {
            return nil
        }
        return value as? String
    }

    private func copySelectedRange(element: AXUIElement) -> CFRange? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(
            element,
            kAXSelectedTextRangeAttribute as CFString,
            &value
        )
        guard result == .success, let value else { return nil }
        guard CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        let axRange = value as! AXValue
        guard AXValueGetType(axRange) == .cfRange else { return nil }
        var range = CFRange()
        guard AXValueGetValue(axRange, .cfRange, &range) else { return nil }
        return range
    }

    private func elapsedNs(since start: UInt64) -> UInt64 {
        DispatchTime.now().uptimeNanoseconds - start
    }

    private func restoreCaret(element: AXUIElement, caret: CFRange) {
        var caretValue = caret
        if let value = AXValueCreate(.cfRange, &caretValue) {
            _ = AXUIElementSetAttributeValue(
                element,
                kAXSelectedTextRangeAttribute as CFString,
                value
            )
        }
    }
}
