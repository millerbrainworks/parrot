import CoreGraphics
import Foundation

/// Posts a string of text at the current cursor location by synthesizing
/// keyboard events with `CGEventKeyboardSetUnicodeString`. Works in nearly
/// every text field on macOS; some Electron apps and secure password fields
/// can drop characters (platform constraint).
enum TextInjector {
    /// Inject the given text at the current cursor location.
    /// Splits long strings into chunks because the underlying API has a
    /// per-event character limit (~20 chars).
    static func inject(_ text: String) {
        guard !text.isEmpty else { return }

        for var chunk in utf16Chunks(for: text) {
            postChunk(&chunk)
        }
    }

    static func utf16Chunks(for text: String) -> [[UniChar]] {
        let units = Array(text.utf16)
        var chunks: [[UniChar]] = []
        var start = 0

        while start < units.count {
            var end = min(start + 20, units.count)
            if
                end < units.count,
                isHighSurrogate(units[end - 1]),
                isLowSurrogate(units[end])
            {
                end -= 1
            }

            chunks.append(Array(units[start..<end]))
            start = end
        }
        return chunks
    }

    private static func isHighSurrogate(_ unit: UniChar) -> Bool {
        (0xD800...0xDBFF).contains(unit)
    }

    private static func isLowSurrogate(_ unit: UniChar) -> Bool {
        (0xDC00...0xDFFF).contains(unit)
    }

    private static func postChunk(_ chunk: inout [UniChar]) {
        let length = chunk.count
        guard length > 0 else { return }

        let down = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: true)
        down?.keyboardSetUnicodeString(stringLength: length, unicodeString: &chunk)
        down?.post(tap: .cgSessionEventTap)

        let up = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: false)
        up?.keyboardSetUnicodeString(stringLength: length, unicodeString: &chunk)
        up?.post(tap: .cgSessionEventTap)
    }
}
