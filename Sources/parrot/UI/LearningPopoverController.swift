import AppKit
import SwiftUI

@MainActor
final class LearningPopoverController {
    private var popover: NSPopover?
    private var timeout: DispatchWorkItem?

    func present(
        _ proposal: CorrectionProposal,
        relativeTo anchor: NSView,
        onLearn: @escaping () -> Void
    ) {
        dismiss()

        let popover = NSPopover()
        popover.behavior = .transient
        popover.animates = true
        popover.contentSize = NSSize(width: 360, height: 112)
        popover.contentViewController = NSHostingController(
            rootView: LearningPromptView(
                proposal: proposal,
                onIgnore: { [weak self] in self?.dismiss() },
                onLearn: { [weak self] in
                    onLearn()
                    self?.dismiss()
                }
            )
        )
        self.popover = popover
        popover.show(
            relativeTo: anchor.bounds,
            of: anchor,
            preferredEdge: .minY
        )

        let timeout = DispatchWorkItem { [weak self, weak popover] in
            guard self?.popover === popover else { return }
            self?.dismiss()
        }
        self.timeout = timeout
        DispatchQueue.main.asyncAfter(deadline: .now() + 30, execute: timeout)
    }

    func dismiss() {
        timeout?.cancel()
        timeout = nil
        popover?.performClose(nil)
        popover = nil
    }
}

private struct LearningPromptView: View {
    let proposal: CorrectionProposal
    let onIgnore: () -> Void
    let onLearn: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Learn this correction?")
                .font(.headline)
            Text("“\(proposal.original)” → “\(proposal.corrected)”")
                .font(.body)
                .lineLimit(2)
                .textSelection(.disabled)
            HStack {
                Spacer()
                Button("Ignore", action: onIgnore)
                Button("Learn", action: onLearn)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(14)
        .frame(width: 360, height: 112)
    }
}
