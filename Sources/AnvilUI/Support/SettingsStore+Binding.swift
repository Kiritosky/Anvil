import AnvilKit
import SwiftUI

extension SettingsStore {
    /// A SwiftUI binding straight onto a setting.
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
