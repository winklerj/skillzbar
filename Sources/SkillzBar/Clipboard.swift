import AppKit
import SkillzBarCore

/// Disambiguate from SwiftUI.Visibility inside the app target.
typealias Visibility = SkillzBarCore.Visibility

enum Clipboard {
    static func set(_ text: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
    }
}
