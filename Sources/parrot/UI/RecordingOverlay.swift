import AppKit
import SwiftUI

/// Borderless, non-activating recording controls near the bottom of the active screen.
@MainActor
final class RecordingOverlay {
    enum Action: Equatable {
        case cancel
        case finish
    }

    enum State: Equatable {
        case hidden
        case recording
        case transcribing
    }

    enum Geometry {
        static let panelWidth: CGFloat = 192
        static let panelHeight: CGFloat = 40
        static let buttonWidth: CGFloat = 52
        static let waveformWidth: CGFloat = 88
        static let waveformHeight: CGFloat = 28
        static let iconSize: CGFloat = 16
        static let waveformBarWidth: CGFloat = 4
        static let waveformSpacing: CGFloat = 4
    }

    private var window: NSPanel?
    private let model: OverlayModel

    init(onAction: @escaping (Action) -> Void = { _ in }) {
        model = OverlayModel(onAction: onAction)
    }

    func setActionHandler(_ handler: @escaping (Action) -> Void) {
        model.setActionHandler(handler)
    }

    func show(_ state: State) {
        ensureWindow()
        if state == .recording {
            model.resetLevels()
        }
        guard let window else { return }
        let needsAppear = !window.isVisible
        if needsAppear {
            positionAtBottomCenter(window)
            window.orderFrontRegardless()
            // Defer the state change so SwiftUI lays out in the .hidden style
            // first, then animates to the visible style on the next runloop tick.
            DispatchQueue.main.async { [model] in
                model.state = state
            }
        } else {
            model.state = state
        }
    }

    func hide() {
        model.state = .hidden
        // Let the SwiftUI scale+fade animation play out before yanking the
        // window — otherwise it just pops away.
        let window = self.window
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
            window?.orderOut(nil)
        }
    }

    /// Push a new audio level (0…~1). Safe to call from any thread.
    nonisolated func pushLevel(_ level: Float) {
        Task { @MainActor in
            self.model.pushLevel(level)
        }
    }

    private func ensureWindow() {
        if window != nil { return }
        let panel = NSPanel(
            contentRect: NSRect(
                x: 0,
                y: 0,
                width: Geometry.panelWidth,
                height: Geometry.panelHeight
            ),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false

        let host = NSHostingView(rootView: OverlayPill(model: model))
        host.frame = panel.contentView?.bounds ?? .zero
        host.autoresizingMask = [.width, .height]
        panel.contentView = host

        window = panel
    }

    private func positionAtBottomCenter(_ window: NSPanel) {
        guard let screen = NSScreen.main else { return }
        let frame = window.frame
        let visible = screen.visibleFrame
        let x = visible.midX - frame.width / 2
        let y = visible.minY + 32
        window.setFrameOrigin(NSPoint(x: x, y: y))
    }
}

/// Observable state for the SwiftUI pill.
@MainActor
final class OverlayModel: ObservableObject {
    static let barCount = 6
    /// Per-bar height multiplier — center bars peak higher than edge bars.
    private static let envelope: [Float] = [0.55, 0.85, 1.0, 1.0, 0.85, 0.55]

    @Published var state: RecordingOverlay.State = .hidden
    @Published var levels: [Float] = Array(repeating: 0, count: barCount)
    private var onAction: (RecordingOverlay.Action) -> Void

    init(onAction: @escaping (RecordingOverlay.Action) -> Void = { _ in }) {
        self.onAction = onAction
    }

    func setActionHandler(_ handler: @escaping (RecordingOverlay.Action) -> Void) {
        onAction = handler
    }

    func cancel() {
        onAction(.cancel)
    }

    func finish() {
        onAction(.finish)
    }

    func pushLevel(_ level: Float) {
        let shaped = min(1.0, sqrt(max(0, level)) * 3.4)
        var next = [Float]()
        next.reserveCapacity(Self.barCount)
        for i in 0..<Self.barCount {
            // Small per-bar jitter so the bars don't all move in lockstep.
            let jitter = Float.random(in: 0.78...1.0)
            next.append(shaped * Self.envelope[i] * jitter)
        }
        levels = next
    }

    func resetLevels() {
        levels = Array(repeating: 0, count: Self.barCount)
    }
}

private struct OverlayPill: View {
    @ObservedObject var model: OverlayModel

    var body: some View {
        content
            .frame(
                width: RecordingOverlay.Geometry.panelWidth,
                height: RecordingOverlay.Geometry.panelHeight
            )
            .background(
                Capsule()
                    .fill(Color(red: 16/255, green: 18/255, blue: 18/255))
            )
            .scaleEffect(model.state == .hidden ? 0 : 1)
            .animation(
                .timingCurve(0.16, 1, 0.3, 1, duration: 0.3),
                value: model.state
            )
    }

    @ViewBuilder
    private var content: some View {
        switch model.state {
        case .hidden, .recording:
            HStack(spacing: 0) {
                Button(action: model.cancel) {
                    Image(systemName: "xmark")
                        .font(.system(size: RecordingOverlay.Geometry.iconSize, weight: .bold))
                        .foregroundStyle(.red)
                        .frame(
                            width: RecordingOverlay.Geometry.buttonWidth,
                            height: RecordingOverlay.Geometry.panelHeight
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .focusable(false)

                Waveform(levels: model.levels)
                    .frame(
                        width: RecordingOverlay.Geometry.waveformWidth,
                        height: RecordingOverlay.Geometry.waveformHeight
                    )

                Button(action: model.finish) {
                    Image(systemName: "checkmark")
                        .font(.system(size: RecordingOverlay.Geometry.iconSize, weight: .bold))
                        .foregroundStyle(.green)
                        .frame(
                            width: RecordingOverlay.Geometry.buttonWidth,
                            height: RecordingOverlay.Geometry.panelHeight
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .focusable(false)
            }
            .frame(
                width: RecordingOverlay.Geometry.panelWidth,
                height: RecordingOverlay.Geometry.panelHeight
            )
        case .transcribing:
            ProgressView()
                .controlSize(.small)
                .scaleEffect(0.65)
                .frame(
                    width: RecordingOverlay.Geometry.panelWidth,
                    height: RecordingOverlay.Geometry.panelHeight
                )
        }
    }
}

private struct Waveform: View {
    let levels: [Float]
    private let color = Color(red: 181/255.0, green: 209/255.0, blue: 255/255.0)

    var body: some View {
        HStack(alignment: .center, spacing: RecordingOverlay.Geometry.waveformSpacing) {
            ForEach(Array(levels.enumerated()), id: \.offset) { _, level in
                Capsule()
                    .fill(color)
                    .frame(width: RecordingOverlay.Geometry.waveformBarWidth)
                    .frame(maxHeight: .infinity)
                    .scaleEffect(y: max(0.10, CGFloat(level)), anchor: .center)
                    .animation(.easeOut(duration: 0.09), value: level)
            }
        }
    }
}
