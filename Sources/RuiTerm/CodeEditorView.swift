import SwiftUI
import AppKit
import CodeEditorView
import LanguageSupport

struct RuiTermCodeEditor: View {
    @Binding var text: String
    var language: LanguageConfiguration = .none
    var onSave: (() -> Void)?
    
    @Environment(\.colorScheme) private var colorScheme
    @State private var position = CodeEditor.Position()
    
    /// Determine the appropriate indentation configuration based on the language
    private var indentationConfig: CodeEditor.IndentationConfiguration {
        let name = language.name
        switch name {
        case "YAML":
            return CodeEditor.IndentationConfiguration(
                preference: .preferSpaces,
                tabWidth: 2,
                indentWidth: 2,
                tabKey: .indentsAlways,
                indentOnReturn: true
            )
        default:
            return .standard
        }
    }
    
    var body: some View {
        CodeEditor(
            text: $text,
            position: $position,
            messages: .constant([]),
            language: language
        )
        .environment(\.codeEditorTheme, colorScheme == .dark ? Theme.defaultDark : Theme.defaultLight)
        .environment(\.codeEditorIndentationConfiguration, indentationConfig)
        .background(EditorCaretVisibilityObserver(position: $position))
    }
}

private struct EditorCaretVisibilityObserver: NSViewRepresentable {
    @Binding var position: CodeEditor.Position

    func makeNSView(context: Context) -> CaretTrackingView {
        let view = CaretTrackingView()
        configure(view)
        return view
    }

    func updateNSView(_ nsView: CaretTrackingView, context: Context) {
        configure(nsView)
    }

    private func configure(_ view: CaretTrackingView) {
        view.updateScrollPosition = { newPosition in
            if abs(position.verticalScrollPosition - newPosition) > 0.5 {
                position.verticalScrollPosition = newPosition
            }
        }
    }

    final class CaretTrackingView: NSView {
        var updateScrollPosition: ((CGFloat) -> Void)?
        private var observers: [NSObjectProtocol] = []

        override init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            let center = NotificationCenter.default
            observers.append(
                center.addObserver(
                    forName: NSText.didChangeNotification,
                    object: nil,
                    queue: .main
                ) { [weak self] notification in
                    self?.scheduleCaretReveal(from: notification)
                }
            )
            observers.append(
                center.addObserver(
                    forName: NSTextView.didChangeSelectionNotification,
                    object: nil,
                    queue: .main
                ) { [weak self] notification in
                    self?.scheduleCaretReveal(from: notification)
                }
            )
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        private func scheduleCaretReveal(from notification: Notification) {
            guard let textView = notification.object as? NSTextView,
                  textView.isEditable,
                  textView.window === window,
                  window?.firstResponder === textView else {
                return
            }

            DispatchQueue.main.async { [weak self, weak textView] in
                guard let self, let textView, textView.window === self.window else { return }
                self.revealCaret(in: textView)
            }
        }

        private func revealCaret(in textView: NSTextView) {
            textView.scrollRangeToVisible(textView.selectedRange())
            guard let scrollView = textView.enclosingScrollView else { return }
            updateScrollPosition?(scrollView.documentVisibleRect.origin.y)
        }

        deinit {
            observers.forEach(NotificationCenter.default.removeObserver)
        }
    }
}

// Map file extension to CodeEditor language
extension LanguageConfiguration {
    static func fromPath(_ path: String) -> LanguageConfiguration {
        let ext = (path as NSString).pathExtension.lowercased()
        switch ext {
        case "swift": return .swift()
        case "sql", "sqlite": return .sqlite()
        case "sh", "bash", "zsh", "command": return .bash()
        case "json": return .json()
        case "yaml", "yml": return .yaml()
        case "xml", "plist", "html", "htm", "svg": return .xml()
        default:
            let filename = (path as NSString).lastPathComponent.lowercased()
            switch filename {
            case ".bashrc", ".zshrc", ".profile", ".bash_profile", ".bash_logout",
                 ".zprofile", ".zshenv", ".zlogout":
                return .bash()
            default:
                return .none
            }
        }
    }
}
