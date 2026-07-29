import ApplicationServices
import Foundation

@MainActor
final class CorrectionObserver {
    private struct PendingObservation {
        let element: AXUIElement
        let original: String
        let insertionStart: Int
        let startedAt: Date
    }

    private let policy = CorrectionObservationPolicy(timeout: 30)
    private var pending: PendingObservation?
    private var timer: Timer?
    private var onProposal: ((CorrectionProposal) -> Void)?

    func prepare(text: String) {
        cancel()
        guard !text.isEmpty else { return }
        guard let element = Self.focusedElement() else { return }
        let access = AccessibilityTextAccessResolver.read(from: element)
        guard let selection = policy.selectedRangeForPreparation(
            access: access,
            readSelectedRange: {
                Self.selectedRange(of: element)
            }
        ) else {
            return
        }
        pending = PendingObservation(
            element: element,
            original: text,
            insertionStart: selection.location,
            startedAt: Date()
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
        let access = AccessibilityTextAccessResolver.read(
            from: pending.element
        )
        guard let selection = policy.selectedRangeForPoll(
            elapsed: elapsed,
            sameElement: sameElement,
            access: access,
            readSelectedRange: {
                Self.selectedRange(of: pending.element)
            }
        ) else {
            cancel()
            return
        }

        let readRange: CFRange
        switch CorrectionObservationRangePolicy.readPlan(
            selection: selection,
            insertionStart: pending.insertionStart,
            originalLength: pending.original.utf16.count
        ) {
        case .wait:
            return
        case .cancel:
            cancel()
            return
        case let .read(location, length):
            readRange = CFRange(location: location, length: length)
        }
        guard let observed = Self.string(
            from: pending.element,
            range: readRange
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
}
