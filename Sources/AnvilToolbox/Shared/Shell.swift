import Foundation

/// Text, den man in ein Terminal einfügen kann.
enum Shell {
    /// Ein Argument, das die Shell unverändert durchreicht.
    static func quoted(_ text: String) -> String {
        "'" + text.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
