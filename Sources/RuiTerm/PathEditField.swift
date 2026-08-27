import SwiftUI
import AppKit

/// A text field that auto-focuses when it appears.
/// Uses NSTextField under the hood to guarantee immediate focus.
struct PathEditField: NSViewRepresentable {
    @Binding var text: String
    let onCommit: (String) -> Void
    let onCancel: () -> Void
    
    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField()
        field.font = .monospacedSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular)
        field.textColor = .secondaryLabelColor
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.lineBreakMode = .byTruncatingTail
        field.delegate = context.coordinator
        field.target = context.coordinator
        field.action = #selector(Coordinator.commit(_:))
        field.stringValue = text
        
        // Auto-focus on appear
        DispatchQueue.main.async {
            guard field.window?.isKeyWindow == true, NSApp.keyWindow === field.window else { return }
            field.window?.makeFirstResponder(field)
            field.selectText(nil) // Select all text
        }
        
        return field
    }
    
    func updateNSView(_ nsView: NSTextField, context: Context) {
        // Only update if not currently editing to avoid cursor jumps
        if !context.coordinator.isEditing {
            nsView.stringValue = text
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }
    
    class Coordinator: NSObject, NSTextFieldDelegate {
        let parent: PathEditField
        var isEditing = false
        
        init(parent: PathEditField) {
            self.parent = parent
        }
        
        func controlTextDidChange(_ obj: Notification) {
            guard let field = obj.object as? NSTextField else { return }
            isEditing = true
            parent.text = field.stringValue
        }
        
        func controlTextDidEndEditing(_ obj: Notification) {
            isEditing = false
        }

        @objc func commit(_ sender: NSTextField) {
            parent.text = sender.stringValue
            parent.onCommit(sender.stringValue)
        }
        
        // Handle Enter and Escape keys natively
        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.insertNewline(_:))
                || commandSelector == #selector(NSResponder.insertNewlineIgnoringFieldEditor(_:))
                || commandSelector == #selector(NSResponder.insertLineBreak(_:)) {
                guard let field = control as? NSTextField else { return false }
                commit(field)
                return true
            }
            if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
                parent.onCancel()
                return true
            }
            return false
        }
    }
}
