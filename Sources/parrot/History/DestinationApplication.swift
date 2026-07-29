import AppKit

enum DestinationApplication {
    static func currentName() -> String {
        NSWorkspace.shared.frontmostApplication?.localizedName ?? "Unknown Application"
    }
}
