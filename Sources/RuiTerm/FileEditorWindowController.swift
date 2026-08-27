import SwiftUI
import AppKit

class FileEditorWindowController: NSWindowController {
    
    let hostID: UUID
    let remotePath: String
    
    init(hostID: UUID, remotePath: String, content: String, onSave: @escaping (String) -> Void) {
        self.hostID = hostID
        self.remotePath = remotePath
        
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = URL(fileURLWithPath: remotePath).lastPathComponent
        window.center()
        window.setFrameAutosaveName("FileEditor_\(remotePath)")
        
        super.init(window: window)
        
        let editorView = FileEditorRootView(content: content, remotePath: remotePath, onSave: onSave)
        window.contentView = NSHostingView(rootView: editorView)
    }

    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        window?.makeKeyAndOrderFront(sender)

        DispatchQueue.main.async { [weak self] in
            self?.focusEditorIfAvailable()
        }
    }

    private func focusEditorIfAvailable() {
        guard let window,
              window.isKeyWindow,
              NSApp.keyWindow === window,
              let contentView = window.contentView,
              let editor = firstEditableTextView(in: contentView) else {
            return
        }
        window.initialFirstResponder = editor
        window.makeFirstResponder(editor)
    }

    private func firstEditableTextView(in view: NSView) -> NSTextView? {
        if let textView = view as? NSTextView, textView.isEditable {
            return textView
        }
        for subview in view.subviews {
            if let textView = firstEditableTextView(in: subview) {
                return textView
            }
        }
        return nil
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

struct FileEditorRootView: View {
    @State var content: String
    let remotePath: String
    let onSave: (String) -> Void
    
    @State private var isSaving = false
    @State private var showSaveSuccess = false
    
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(remotePath)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                if isSaving {
                    ProgressView()
                        .controlSize(.small)
                } else if showSaveSuccess {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                        .transition(.opacity)
                }
                Button("保存") {
                    save()
                }
                .keyboardShortcut("s", modifiers: .command)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color(NSColor.controlBackgroundColor))
            
            Divider()
            
            RuiTermCodeEditor(
                text: $content,
                language: .fromPath(remotePath),
                onSave: save
            )
        }
    }
    
    private func save() {
        guard !isSaving else { return }
        isSaving = true
        onSave(content)
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            isSaving = false
            withAnimation {
                showSaveSuccess = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                withAnimation {
                    showSaveSuccess = false
                }
            }
        }
    }
}
