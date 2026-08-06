import AnvilKit
import SwiftUI

extension SettingsStore {
    /// A SwiftUI binding straight onto a setting.
    ///
    /// Every screen that edits preferences was writing the same four-line
    /// helper. `AnvilKit` cannot supply it — it has no business importing
    /// SwiftUI — so it lives here, one level up, where the views are.
    ///
    /// - Parameter onChange: runs after the write, for the settings that have
    ///   to be applied somewhere rather than merely stored.
    public func bind<Value>(
        _ key: SettingKey<Value>,
        onChange: (@MainActor (Value) -> Void)? = nil
    ) -> Binding<Value> {
        Binding(
            get: { self[key] },
            set: { newValue in
                self[key] = newValue
                onChange?(newValue)
            }
        )
    }
}
