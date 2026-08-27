import SwiftUI

struct TitleBarDragActionKey: EnvironmentKey {
    static let defaultValue: ((CGSize, Bool) -> Void)? = nil
}

extension EnvironmentValues {
    var titleBarDragAction: ((CGSize, Bool) -> Void)? {
        get { self[TitleBarDragActionKey.self] }
        set { self[TitleBarDragActionKey.self] = newValue }
    }
}
