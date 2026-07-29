import ApplicationServices
import AppKit
import Foundation

enum AccessibilityOptionalAttribute<Value: Equatable>: Equatable {
    case value(Value)
    case absent
    case failure
}

struct AccessibilityTextAccess: Equatable {
    let role: String?
    let subrole: AccessibilityOptionalAttribute<String>
    let protectedContent: AccessibilityOptionalAttribute<Bool>
}

enum AccessibilityTextAccessResolver {
    static func read(from element: AXUIElement) -> AccessibilityTextAccess {
        AccessibilityTextAccess(
            role: requiredStringAttribute(
                kAXRoleAttribute,
                from: element
            ),
            subrole: optionalStringAttribute(
                kAXSubroleAttribute,
                from: element
            ),
            protectedContent: optionalBooleanAttribute(
                NSAccessibility.Attribute.containsProtectedContent.rawValue,
                from: element
            )
        )
    }

    static func allowsTextAccess(_ access: AccessibilityTextAccess) -> Bool {
        guard let role = access.role else {
            return false
        }

        let subrole: String?
        switch access.subrole {
        case let .value(value):
            subrole = value
        case .absent:
            subrole = nil
        case .failure:
            return false
        }
        guard !isSensitive(role: role, subrole: subrole) else {
            return false
        }

        switch access.protectedContent {
        case .value(true), .failure:
            return false
        case .value(false), .absent:
            return true
        }
    }

    static func isSensitive(role: String, subrole: String?) -> Bool {
        [role, subrole].compactMap(\.self).contains { value in
            let normalized = value.lowercased()
            return normalized.contains("secure")
                || normalized.contains("password")
        }
    }

    static func parseOptionalBoolean(
        result: AXError,
        value: CFTypeRef?
    ) -> AccessibilityOptionalAttribute<Bool> {
        switch result {
        case .success:
            guard
                let value,
                CFGetTypeID(value) == CFBooleanGetTypeID()
            else {
                return .failure
            }
            return .value(CFBooleanGetValue((value as! CFBoolean)))
        case .noValue, .attributeUnsupported:
            return .absent
        default:
            return .failure
        }
    }

    private static func requiredStringAttribute(
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

    private static func optionalStringAttribute(
        _ attribute: String,
        from element: AXUIElement
    ) -> AccessibilityOptionalAttribute<String> {
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

    private static func optionalBooleanAttribute(
        _ attribute: String,
        from element: AXUIElement
    ) -> AccessibilityOptionalAttribute<Bool> {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(
            element,
            attribute as CFString,
            &value
        )
        return parseOptionalBoolean(result: result, value: value)
    }
}
