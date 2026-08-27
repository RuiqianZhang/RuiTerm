import SwiftUI

enum SplitDirection {
    case right
    case down
}

@MainActor
struct TerminalPane: Identifiable {
    let id = UUID()
    let host: SSHHost
    let session: SSHSession
    let surface = TerminalSurface()

    init(host: SSHHost, session: SSHSession? = nil) {
        self.host = host
        self.session = session ?? SSHSession(host: host)
    }

    func releaseResources() {
        surface.terminal?.suspendRendering()
        surface.terminal?.resetTerminalBuffer()
        surface.terminal = nil
        session.disconnect()
    }
}

@MainActor
indirect enum SplitNode {
    case pane(TerminalPane)
    case split(SplitDirection, SplitNode, SplitNode)

    var firstPane: TerminalPane {
        switch self {
        case .pane(let pane): return pane
        case .split(_, let first, _): return first.firstPane
        }
    }

    func pane(withID id: TerminalPane.ID) -> TerminalPane? {
        switch self {
        case .pane(let pane): return pane.id == id ? pane : nil
        case .split(_, let first, let second):
            return first.pane(withID: id) ?? second.pane(withID: id)
        }
    }

    var panes: [TerminalPane] {
        switch self {
        case .pane(let pane): return [pane]
        case .split(_, let first, let second): return first.panes + second.panes
        }
    }

    func splitting(_ id: TerminalPane.ID, with newPane: TerminalPane, direction: SplitDirection) -> SplitNode {
        switch self {
        case .pane(let pane):
            return pane.id == id ? .split(direction, .pane(pane), .pane(newPane)) : self
        case .split(let existingDirection, let first, let second):
            return .split(
                existingDirection,
                first.splitting(id, with: newPane, direction: direction),
                second.splitting(id, with: newPane, direction: direction)
            )
        }
    }

    func removing(_ id: TerminalPane.ID) -> SplitNode? {
        switch self {
        case .pane(let pane):
            return pane.id == id ? nil : self
        case .split(let direction, let first, let second):
            let remainingFirst = first.removing(id)
            let remainingSecond = second.removing(id)
            switch (remainingFirst, remainingSecond) {
            case (let first?, let second?): return .split(direction, first, second)
            case (let remaining?, nil), (nil, let remaining?): return remaining
            case (nil, nil): return nil
            }
        }
    }
}

@MainActor
final class TerminalWorkspace: ObservableObject {
    @Published var root: SplitNode
    @Published var activePaneID: TerminalPane.ID

    init(primaryHost: SSHHost, tabSession: SSHSession) {
        let pane = TerminalPane(host: primaryHost, session: tabSession)
        root = .pane(pane)
        activePaneID = pane.id
    }

    func disconnect() {
        root.panes.forEach { $0.releaseResources() }
    }

    func setTerminalOutputInteractive(isActiveTab: Bool) {
        root.panes.forEach { pane in
            pane.session.setTerminalOutputInteractive(isActiveTab && pane.id == activePaneID)
        }
    }

    func deferTerminalOutputForUserInteraction(seconds: TimeInterval = 6.0) {
        root.panes.forEach { pane in
            pane.session.deferTerminalOutputForUserInteraction(seconds: seconds)
        }
    }
}

struct TerminalWorkspaceView: View {
    @ObservedObject var workspace: TerminalWorkspace
    let hosts: [SSHHost]
    let showsHostStatus: Bool
    let hostStatusOccupiesSpace: Bool
    let isWindowFocused: Bool
    let isTabActive: Bool
    let onAuthenticated: (SSHSession) -> Void
    let onNewTab: (SSHHost) -> Void
    @Binding var selectedHostID: SSHHost.ID?
    @ObservedObject private var appearance = AppearanceSettings.shared

    init(
        workspace: TerminalWorkspace,
        hosts: [SSHHost],
        showsHostStatus: Bool,
        hostStatusOccupiesSpace: Bool,
        isWindowFocused: Bool,
        isTabActive: Bool,
        onAuthenticated: @escaping (SSHSession) -> Void = { _ in },
        onNewTab: @escaping (SSHHost) -> Void = { _ in },
        selectedHostID: Binding<SSHHost.ID?>
    ) {
        self.workspace = workspace
        self.hosts = hosts
        self.showsHostStatus = showsHostStatus
        self.hostStatusOccupiesSpace = hostStatusOccupiesSpace
        self.isWindowFocused = isWindowFocused
        self.isTabActive = isTabActive
        self.onAuthenticated = onAuthenticated
        self.onNewTab = onNewTab
        _selectedHostID = selectedHostID
    }

    private var activeHost: SSHHost {
        workspace.root.pane(withID: workspace.activePaneID)?.host ?? workspace.root.firstPane.host
    }

    var body: some View {
        ZStack(alignment: .trailing) {
            HStack(spacing: 8) {
                nodeView(workspace.root)
                    .frame(minWidth: 420, maxWidth: .infinity, maxHeight: .infinity)

                if hostStatusOccupiesSpace {
                    Color.clear
                        .frame(width: 240)
                        .allowsHitTesting(false)
                }
            }

            if showsHostStatus {
                let pane = workspace.root.pane(withID: workspace.activePaneID) ?? workspace.root.firstPane
                ResourceInspectorView(host: pane.host, session: pane.session, isActive: isWindowFocused && isTabActive)
                    .id(pane.host.id)
                    .frame(width: 240)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
                    .zIndex(1)
            }
        }
    }

    private func nodeView(_ node: SplitNode) -> AnyView {
        switch node {
        case .pane(let pane):
            return AnyView(
                TerminalView(
                    session: pane.session,
                    surface: pane.surface,
                    hosts: hosts,
                    isActive: isWindowFocused && isTabActive && pane.id == workspace.activePaneID,
                    isTabActive: isTabActive,
                    onAuthenticated: onAuthenticated,
                    onActivate: { workspace.activePaneID = pane.id },
                    onNewTab: onNewTab,
                    onSplitRight: { split(pane.id, with: $0, direction: .right) },
                    onSplitDown: { split(pane.id, with: $0, direction: .down) },
                    onClose: { close(pane.id) }
                )
                .id(pane.id)
                .frame(minWidth: 100, minHeight: 80)
            )
        case .split(let direction, let first, let second):
            if direction == .right {
                return AnyView(
                    ProportionalSplitView(axis: .horizontal) {
                        nodeView(first).frame(maxWidth: .infinity, maxHeight: .infinity)
                    } second: {
                        nodeView(second).frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                )
            }
            return AnyView(
                ProportionalSplitView(axis: .vertical) {
                    nodeView(first).frame(maxWidth: .infinity, maxHeight: .infinity)
                } second: {
                    nodeView(second).frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            )
        }
    }

    private func split(_ paneID: TerminalPane.ID, with host: SSHHost, direction: SplitDirection) {
        let pane = TerminalPane(host: host)
        workspace.root = workspace.root.splitting(paneID, with: pane, direction: direction)
        workspace.activePaneID = pane.id
    }

    private func close(_ paneID: TerminalPane.ID) {
        workspace.root.pane(withID: paneID)?.releaseResources()
        guard let remaining = workspace.root.removing(paneID) else {
            selectedHostID = nil
            return
        }
        workspace.root = remaining
        if workspace.root.pane(withID: workspace.activePaneID) == nil {
            workspace.activePaneID = workspace.root.firstPane.id
        }
    }
}
