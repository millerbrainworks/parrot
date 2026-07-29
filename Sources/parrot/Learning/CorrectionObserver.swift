import ApplicationServices
import Foundation

@MainActor
final class CorrectionObserver {
    private struct PendingObservation {
        let element: AXUIElement
        let original: String
        let insertionStart: Int
        let startedAt: Date
        let secure: Bool
    }

    private let policy = CorrectionObservationPolicy(timeout: 30)
    private var pending: PendingObservation?
    private var timer: Timer?
    private var onProposal: ((CorrectionProposal) -> Void)?

    func prepare(text: String) {
        cancel()
        guard !text.isEmpty else { return }
        guard let element = Self.focusedElement() else { return }
        let secure = Self.isSecure(element)
        guard !secure, let selection = Self.selectedRange(of: element) else {
            return
        }
        pending = PendingObservation(
            element: element,
            original: text,
            insertionStart: selection.location,
            startedAt: Date(),
            secure: secure
        )
    }

    func begin(onProposal: @escaping (CorrectionProposal) -> Void) {
        guard pending != nil else { return }
        self.onProposal = onProposal
        timer?.invalidate()
        timer = Timer.scheduledTimer(
            withTimeInterval: 0.4,
            repeats: true
        ) { [weak self] _ in
            Task { @MainActor in
                self?.poll()
            }
        }
    }

    func cancel() {
        timer?.invalidate()
        timer = nil
        pending = nil
        onProposal = nil
    }

    private func poll() {
        guard let pending else {
            cancel()
            return
        }
        guard let focused = Self.focusedElement() else {
            cancel()
            return
        }
        let sameElement = CFEqual(focused, pending.element)
        let elapsed = Date().timeIntervalSince(pending.startedAt)
        guard policy.canObserve(
            elapsed: elapsed,
            sameElement: sameElement,
            secure: pending.secure
        ) else {
            cancel()
            return
        }
        guard let selection = Self.selectedRange(of: pending.element) else {
            cancel()
            return
        }
        let caret = selection.location + selection.length
        guard caret >= pending.insertionStart else { return }
        let length = caret - pending.insertionStart
        guard length <= pending.original.utf16.count + 64 else {
            cancel()
            return
        }
        guard let observed = Self.string(
            from: pending.element,
            range: CFRange(location: pending.insertionStart, length: length)
        ) else {
            cancel()
            return
        }
        guard let proposal = CorrectionPrefixResolver.proposal(
            original: pending.original,
            observedPrefix: observed
        ) else {
            return
        }

        let callback = onProposal
        cancel()
        callback?(proposal)
    }

    private static func focusedElement() -> AXUIElement? {
        let systemWide = AXUIElementCreateSystemWide()
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            systemWide,
            kAXFocusedUIElementAttribute as CFString,
            &value
        ) == .success,
        let value,
        CFGetTypeID(value) == AXUIElementGetTypeID()
        else {
            return nil
        }
        return (value as! AXUIElement)
    }

    private static func selectedRange(of element: AXUIElement) -> CFRange? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element,
            kAXSelectedTextRangeAttribute as CFString,
            &value
        ) == .success,
        let value,
        CFGetTypeID(value) == AXValueGetTypeID()
        else {
            return nil
        }
        var range = CFRange()
        guard AXValueGetValue(value as! AXValue, .cfRange, &range) else {
            return nil
        }
        return range
    }

    private static func string(
        from element: AXUIElement,
        range: CFRange
    ) -> String? {
        var mutableRange = range
        guard let rangeValue = AXValueCreate(.cfRange, &mutableRange) else {
            return nil
        }
        var value: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(
            element,
            kAXStringForRangeParameterizedAttribute as CFString,
            rangeValue,
            &value
        ) == .success else {
            return nil
        }
        return value as? String
    }

    private static func isSecure(_ element: AXUIElement) -> Bool {
        let role = stringAttribute(element, kAXRoleAttribute as CFString)
        let subrole = stringAttribute(element, kAXSubroleAttribute as CFString)
        let securityDescription = "\(role ?? "") \(subrole ?? "")".lowercased()
        return securityDescription.contains("secure")
            || securityDescription.contains("password")
    }

    private static func stringAttribute(
        _ element: AXUIElement,
        _ attribute: CFString
    ) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element,
            attribute,
            &value
        ) == .success else {
            return nil
        }
        return value as? String
    }
}
