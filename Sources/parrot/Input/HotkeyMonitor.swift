import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

/// Watches Fn double-taps and Escape globally.
final class HotkeyMonitor {
    enum Event {
        case toggleRecording
        case cancelRecording
    }

    enum HotkeyError: Error { case tapCreateFailed }

    private static let escapeKeyCode: Int64 = 53

    private let mask: CGEventFlags
    private let debug: Bool
    private var onEvent: ((Event) -> Void)?
    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var isPressed = false
    private var doubleTap = DoubleTapRecognizer(maxInterval: 0.35)
    private var eventPolicy = HotkeyEventPolicy()
    private let policyLock = NSLock()

    init(mask: CGEventFlags = .maskSecondaryFn, debug: Bool = false) {
        self.mask = mask
        self.debug = debug
    }

    func start(onEvent: @escaping (Event) -> Void) throws {
        self.onEvent = onEvent

        let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let trusted = AXIsProcessTrustedWithOptions([promptKey: true] as CFDictionary)
        if !trusted {
            FileHandle.standardError.write(Data(
                "accessibility not granted — system prompt opened. Grant access, then quit and relaunch parrot.\n".utf8
            ))
            throw HotkeyError.tapCreateFailed
        }

        let mask: CGEventMask =
            (1 << CGEventType.flagsChanged.rawValue)
            | (1 << CGEventType.keyDown.rawValue)
            | (1 << CGEventType.keyUp.rawValue)
        let userInfo = Unmanaged.passUnretained(self).toOpaque()

        // .cgSessionEventTap is the right level for an accessibility-granted
        // user process (.cghidEventTap requires root).
        guard
            let tap = CGEvent.tapCreate(
                tap: .cgSessionEventTap,
                place: .headInsertEventTap,
                options: .defaultTap,
                eventsOfInterest: mask,
                callback: hotkeyCallback,
                userInfo: userInfo
            )
        else {
            throw HotkeyError.tapCreateFailed
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        self.tap = tap
        self.runLoopSource = source
    }

    func stop() {
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        tap = nil
        runLoopSource = nil
        onEvent = nil
    }

    func setCancellationEnabled(_ enabled: Bool) {
        policyLock.lock()
        eventPolicy.cancellationEnabled = enabled
        policyLock.unlock()
    }

    fileprivate func handle(type: CGEventType, event: CGEvent) -> Bool {
        if debug {
            let flags = event.flags
            let keycode = event.getIntegerValueField(.keyboardEventKeycode)
            FileHandle.standardError.write(
                Data(
                    "  [debug] type=\(type.rawValue) keycode=\(keycode) flags=\(String(flags.rawValue, radix: 16))\n"
                        .utf8
                ))
        }

        let keycode = event.getIntegerValueField(.keyboardEventKeycode)
        if keycode == Self.escapeKeyCode {
            let disposition: EscapeDisposition
            policyLock.lock()
            switch type {
            case .keyDown:
                disposition = eventPolicy.escapeKeyDown()
            case .keyUp:
                disposition = eventPolicy.escapeKeyUp()
            default:
                disposition = .passThrough
            }
            policyLock.unlock()

            if disposition == .cancelAndConsume {
                emit(.cancelRecording)
            }
            return disposition != .passThrough
        }

        guard type == .flagsChanged else { return false }
        let pressed = event.flags.contains(mask)
        guard pressed != isPressed else { return false }
        isPressed = pressed
        if !pressed {
            let timestamp = TimeInterval(event.timestamp) / 1_000_000_000
            if doubleTap.registerTap(at: timestamp) {
                emit(.toggleRecording)
            }
        }
        return false
    }

    fileprivate func reenableTap() {
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: true)
        }
    }

    private func emit(_ event: Event) {
        DispatchQueue.main.async { [weak self] in
            self?.onEvent?(event)
        }
    }
}

private func hotkeyCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    let monitor = Unmanaged<HotkeyMonitor>.fromOpaque(userInfo).takeUnretainedValue()

    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        monitor.reenableTap()
        return Unmanaged.passUnretained(event)
    }

    if monitor.handle(type: type, event: event) {
        return nil
    }
    return Unmanaged.passUnretained(event)
}
