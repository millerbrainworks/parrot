import ApplicationServices
import Foundation

struct AccessibilityInsertionContextReader {
    enum Plan: Equatable {
        case unavailable
        case selection
        case documentStart
        case precedingText(location: Int, length: Int)
    }

    static func plan(for selectedRange: CFRange) -> Plan {
        guard selectedRange.location >= 0, selectedRange.length >= 0 else {
            return .unavailable
        }
        guard selectedRange.length == 0 else {
            return .selection
        }
        guard selectedRange.location > 0 else {
            return .documentStart
        }

        let length = min(selectedRange.location, 2)
        return .precedingText(
            location: selectedRange.location - length,
            length: length
        )
    }

    func read() -> InsertionContext {
        guard let element = focusedElement() else {
            return .unavailable
        }

        return Self.resolve(
            access: AccessibilityTextAccessResolver.read(from: element),
            selectedRange: {
                selectedRange(from: element)
            },
            precedingCharacter: { location, length in
                precedingCharacter(
                    from: element,
                    location: location,
                    length: length
                )
            }
        )
    }

    static func resolve(
        role: String,
        subrole: String?,
        protectedContent: AccessibilityOptionalAttribute<Bool>,
        selectedRange: () -> CFRange?,
        precedingCharacter: (Int, Int) -> Character?
    ) -> InsertionContext {
        resolve(
            access: AccessibilityTextAccess(
                role: role,
                subrole: subrole.map {
                    AccessibilityOptionalAttribute.value($0)
                } ?? .absent,
                protectedContent: protectedContent
            ),
            selectedRange: selectedRange,
            precedingCharacter: precedingCharacter
        )
    }

    private static func resolve(
        access: AccessibilityTextAccess,
        selectedRange: () -> CFRange?,
        precedingCharacter: (Int, Int) -> Character?
    ) -> InsertionContext {
        guard AccessibilityTextAccessResolver.allowsTextAccess(access) else {
            return .unavailable
        }
        guard let selectedRange = selectedRange() else {
            return .unavailable
        }
        switch plan(for: selectedRange) {
        case .unavailable:
            return .unavailable
        case .selection:
            return .selection
        case .documentStart:
            return .documentStart
        case let .precedingText(location, length):
            guard let previous = precedingCharacter(location, length) else {
                return .unavailable
            }
            return .caret(previous: previous)
        }
    }

    private func focusedElement() -> AXUIElement? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(
            AXUIElementCreateSystemWide(),
            kAXFocusedUIElementAttribute as CFString,
            &value
        )
        guard
            result == .success,
            let value,
            CFGetTypeID(value) == AXUIElementGetTypeID()
        else {
            return nil
        }
        return (value as! AXUIElement)
    }

    private func selectedRange(from element: AXUIElement) -> CFRange? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(
            element,
            kAXSelectedTextRangeAttribute as CFString,
            &value
        )
        guard
            result == .success,
            let value,
            CFGetTypeID(value) == AXValueGetTypeID()
        else {
            return nil
        }

        let rangeValue = value as! AXValue
        guard AXValueGetType(rangeValue) == .cfRange else {
            return nil
        }

        var range = CFRange()
        guard AXValueGetValue(rangeValue, .cfRange, &range) else {
            return nil
        }
        return range
    }

    private func precedingCharacter(
        from element: AXUIElement,
        location: Int,
        length: Int
    ) -> Character? {
        var range = CFRange(location: location, length: length)
        guard let rangeValue = AXValueCreate(.cfRange, &range) else {
            return nil
        }

        var value: CFTypeRef?
        let result = AXUIElementCopyParameterizedAttributeValue(
            element,
            kAXStringForRangeParameterizedAttribute as CFString,
            rangeValue,
            &value
        )
        guard result == .success, let text = value as? String else {
            return nil
        }
        return text.last
    }
}
