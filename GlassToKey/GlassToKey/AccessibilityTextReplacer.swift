import ApplicationServices
import Dispatch
import Foundation

final class AccessibilityTextReplacer: @unchecked Sendable {
    private let maxDurationNs: UInt64 = 20_000_000

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
        let element = unsafeBitCast(focused, to: AXUIElement.self)

        var pid: pid_t = 0
        let pidResult = AXUIElementGetPid(element, &pid)
        if pidResult == .success, pid == getpid() {
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
