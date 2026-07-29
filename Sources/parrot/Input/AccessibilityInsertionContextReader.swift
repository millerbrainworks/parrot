import ApplicationServices
import Foundation

struct AccessibilityInsertionContextReader {
    enum Plan: Equatable {
        case unavailable
        case selection
        case documentStart
        case precedingText(location: Int, length: Int)
    }

    private enum OptionalStringAttribute {
        case value(String)
        case absent
        case failure
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
        guard
            let element = focusedElement(),
            let role = stringAttribute(kAXRoleAttribute, from: element)
        else {
            return .unavailable
        }

        let subrole: String?
        switch optionalStringAttribute(kAXSubroleAttribute, from: element) {
        case let .value(value):
            subrole = value
        case .absent:
            subrole = nil
        case .failure:
            return .unavailable
        }

        guard
            !Self.isSensitive(role: role, subrole: subrole),
            let selectedRange = selectedRange(from: element)
        else {
            return .unavailable
        }

        switch Self.plan(for: selectedRange) {
        case .unavailable:
            return .unavailable
        case .selection:
            return .selection
        case .documentStart:
            return .documentStart
        case let .precedingText(location, length):
            guard let previous = precedingCharacter(
                from: element,
                location: location,
                length: length
            ) else {
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

    private func stringAttribute(
        _ attribute: String,
        from element: AXUIElement
    ) -> String? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(
            element,
            attribute as CFString,
            &value
        )
        guard result == .success else {
            return nil
        }
        return value as? String
    }

    private func optionalStringAttribute(
        _ attribute: String,
        from element: AXUIElement
    ) -> OptionalStringAttribute {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(
            element,
            attribute as CFString,
            &value
        )
        switch result {
        case .success:
            guard let string = value as? String else {
                return .failure
            }
            return .value(string)
        case .noValue, .attributeUnsupported:
            return .absent
        default:
            return .failure
        }
    }

    static func isSensitive(role: String, subrole: String?) -> Bool {
        [role, subrole].compactMap(\.self).contains { value in
            let normalized = value.lowercased()
            return normalized.contains("secure")
                || normalized.contains("password")
        }
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
