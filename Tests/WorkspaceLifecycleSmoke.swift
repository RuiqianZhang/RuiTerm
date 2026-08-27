import Foundation

@main
enum WorkspaceLifecycleSmoke {
    @MainActor
    static func main() {
        let host = SSHHost(name: "Primary", hostname: "primary.example")
        let originalPane = TerminalPane(host: host)
        let originalSession = originalPane.session
        var root = SplitNode.pane(originalPane)

        let copiedPane = TerminalPane(host: host)
        root = root.splitting(originalPane.id, with: copiedPane, direction: .right)

        precondition(root.panes.count == 2)
        precondition(root.pane(withID: originalPane.id)?.session === originalSession)
        precondition(root.pane(withID: copiedPane.id)?.session === copiedPane.session)

        guard let remaining = root.removing(copiedPane.id) else {
            fatalError("Removing a copied pane removed the entire workspace.")
        }
        precondition(remaining.panes.count == 1)
        precondition(remaining.firstPane.session === originalSession)
    }
}
