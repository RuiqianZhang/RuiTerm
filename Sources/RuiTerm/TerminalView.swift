import AppKit
import Darwin
import SwiftUI
@preconcurrency import SwiftTerm

@MainActor
protocol TerminalCommandTarget: AnyObject {
    func copySelection()
    func pasteClipboard()
    func selectAllContent()
    func clearTerminal()
    func sendClearScreen()
    func moveToBeginningOfLine()
    func moveToEndOfLine()
    func scrollPageUp()
    func scrollPageDown()
    func scrollToTop()
    func scrollToBottom()
    func increaseFontSize()
    func decreaseFontSize()
    func resetTerminalFontSize()
}

@MainActor
final class TerminalCommandCenter: NSObject, ObservableObject {
    static let shared = TerminalCommandCenter()

    @Published private var publishedKeyResponderState = false
    private weak var terminal: TerminalCommandTarget?

    var isKeyResponder: Bool {
        computeKeyResponder()
    }

    private override init() {
        super.init()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowKeyStateChanged(_:)),
            name: NSWindow.didBecomeKeyNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowKeyStateChanged(_:)),
            name: NSWindow.didResignKeyNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowKeyStateChanged(_:)),
            name: NSWindow.didUpdateNotification,
            object: nil
        )
    }

    fileprivate func focus(_ terminal: TerminalCommandTarget) {
        self.terminal = terminal
        refreshKeyResponder()
    }

    fileprivate func blur(_ terminal: TerminalCommandTarget) {
        guard self.terminal === terminal else { return }
        self.terminal = nil
        publishedKeyResponderState = false
    }

    func blur() {
        terminal = nil
        publishedKeyResponderState = false
    }

    /// Returns true only when the focused terminal is the first responder of the current key window.
    /// This prevents menu shortcuts (Cmd+C/V/A) from routing to the terminal when a sheet,
    /// popover, or other panel has keyboard focus.
    private func refreshKeyResponder() {
        let newValue = computeKeyResponder()
        if publishedKeyResponderState != newValue {
            publishedKeyResponderState = newValue
        }
    }

    private func computeKeyResponder() -> Bool {
        guard let view = terminal as? NSView else { return false }
        return view.window?.isKeyWindow == true
            && NSApp.keyWindow === view.window
            && view.window?.firstResponder === view
    }

    @objc private func windowKeyStateChanged(_ notification: Notification) {
        refreshKeyResponder()
    }

    func performCopy() {
        guard isKeyResponder else { return }
        terminal?.copySelection()
    }

    func performPaste() {
        guard isKeyResponder else { return }
        terminal?.pasteClipboard()
    }

    func performSelectAll() {
        guard isKeyResponder else { return }
        terminal?.selectAllContent()
    }

    func clearTerminal() {
        guard isKeyResponder else { return }
        terminal?.clearTerminal()
    }

    func sendClearScreen() {
        guard isKeyResponder else { return }
        terminal?.sendClearScreen()
    }

    func moveToBeginningOfLine() {
        guard isKeyResponder else { return }
        terminal?.moveToBeginningOfLine()
    }

    func moveToEndOfLine() {
        guard isKeyResponder else { return }
        terminal?.moveToEndOfLine()
    }

    func scrollPageUp() {
        guard isKeyResponder else { return }
        terminal?.scrollPageUp()
    }

    func scrollPageDown() {
        guard isKeyResponder else { return }
        terminal?.scrollPageDown()
    }

    func scrollToTop() {
        guard isKeyResponder else { return }
        terminal?.scrollToTop()
    }

    func scrollToBottom() {
        guard isKeyResponder else { return }
        terminal?.scrollToBottom()
    }

    func increaseFontSize() {
        guard isKeyResponder else { return }
        terminal?.increaseFontSize()
    }

    func decreaseFontSize() {
        guard isKeyResponder else { return }
        terminal?.decreaseFontSize()
    }

    func resetFontSize() {
        guard isKeyResponder else { return }
        terminal?.resetTerminalFontSize()
    }
}

struct TerminalView: View {
    @ObservedObject var session: SSHSession
    let surface: TerminalSurface
    let hosts: [SSHHost]
    let isActive: Bool
    let isTabActive: Bool
    let onAuthenticated: (SSHSession) -> Void
    let onActivate: () -> Void
    let onNewTab: (SSHHost) -> Void
    let onSplitRight: (SSHHost) -> Void
    let onSplitDown: (SSHHost) -> Void
    let onClose: () -> Void
    @Environment(\.titleBarDragAction) private var titleBarDragAction
    @ObservedObject private var appearance = AppearanceSettings.shared
    @State private var isShowingSFTP = false
    @State private var splitHeight: CGFloat? = nil
    @State private var isShowingTempScrollbackAlert = false
    @State private var tempScrollbackInput = "2000"

    init(
        session: SSHSession,
        surface: TerminalSurface,
        hosts: [SSHHost],
        isActive: Bool = true,
        isTabActive: Bool = true,
        onAuthenticated: @escaping (SSHSession) -> Void = { _ in },
        onActivate: @escaping () -> Void = {},
        onNewTab: @escaping (SSHHost) -> Void = { _ in },
        onSplitRight: @escaping (SSHHost) -> Void = { _ in },
        onSplitDown: @escaping (SSHHost) -> Void = { _ in },
        onClose: @escaping () -> Void = {}
    ) {
        self.session = session
        self.surface = surface
        self.hosts = hosts
        self.isActive = isActive
        self.isTabActive = isTabActive
        self.onAuthenticated = onAuthenticated
        self.onActivate = onActivate
        self.onNewTab = onNewTab
        self.onSplitRight = onSplitRight
        self.onSplitDown = onSplitDown
        self.onClose = onClose
    }

    var body: some View {
        GeometryReader { proxy in
            let panelHeight = max(120, proxy.size.height * sftpFraction)
            let paneShape = RoundedRectangle(cornerRadius: 13, style: .continuous)
            ZStack(alignment: .bottom) {
                VStack(spacing: 0) {
                    terminalPanel(size: proxy.size)

                    if sftpOccupiesSpace {
                        Color(nsColor: appearance.backgroundColor)
                            .frame(height: panelHeight)
                            .allowsHitTesting(false)
                    }
                }

                sftpOverlay(containerHeight: proxy.size.height)
                    .frame(height: panelHeight)
                    .offset(y: isShowingSFTP ? 0 : panelHeight + 16)
                    .opacity(isShowingSFTP ? 1 : 0)
                    .allowsHitTesting(isShowingSFTP)
                    .accessibilityHidden(!isShowingSFTP)
                    .animation(.easeInOut(duration: 0.22), value: isShowingSFTP)
            }
            .liquidGlassPanel(enabled: appearance.usesLiquidGlassEffects, cornerRadius: 13)
            .overlay {
                paneShape
                    .strokeBorder(isActive ? Color.accentColor.opacity(0.85) : Color.secondary.opacity(0.18), lineWidth: isActive ? 1.5 : 1)
                    .allowsHitTesting(false)
            }
        }
        .onAppear {
            session.connect()
        }
        .onChange(of: session.isAuthenticated) { _, authenticated in
            if authenticated {
                onAuthenticated(session)
            }
        }
        .alert("临时回滚行数", isPresented: $isShowingTempScrollbackAlert) {
            TextField("行数", text: $tempScrollbackInput)
            Button("取消", role: .cancel) { }
            Button("设置") {
                if let lines = Int(tempScrollbackInput), lines > 0 {
                    surface.terminal?.setTemporaryScrollback(AppearanceSettings.clampedScrollbackLines(lines))
                }
                tempScrollbackInput = ""
            }
        } message: {
            Text("输入此会话的回滚行数。")
        }
    }

    @State private var sftpFraction: CGFloat = 0.5
    @State private var sftpDragStart: CGFloat? = nil
    @State private var sftpOccupiesSpace = false
    private let sftpAnimationDuration = 0.24
    private let terminalChromeHeight: CGFloat = 28
    private var terminalBottomInset: CGFloat {
        max(14, appearance.font.pointSize * 1.15)
    }

    private func setSFTPVisible(_ visible: Bool) {
        if visible {
            guard !isShowingSFTP else { return }
            withTransaction(Transaction(animation: nil)) {
                sftpOccupiesSpace = true
            }
            DispatchQueue.main.async {
                withAnimation(.easeInOut(duration: sftpAnimationDuration)) {
                    isShowingSFTP = true
                }
            }
        } else {
            guard isShowingSFTP || sftpOccupiesSpace else { return }
            withAnimation(.easeInOut(duration: sftpAnimationDuration)) {
                isShowingSFTP = false
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + sftpAnimationDuration) {
                if !isShowingSFTP {
                    withTransaction(Transaction(animation: nil)) {
                        sftpOccupiesSpace = false
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func sftpOverlay(containerHeight: CGFloat) -> some View {
        let cornerShape = UnevenRoundedRectangle(topLeadingRadius: 14, bottomLeadingRadius: 0, bottomTrailingRadius: 0, topTrailingRadius: 14)

        VStack(spacing: 0) {
            // 拖拽手柄区域
            ZStack {
                Capsule()
                    .fill(Color.secondary.opacity(0.4))
                    .frame(width: 36, height: 4)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 14)
            .contentShape(Rectangle())
            .onHover { hovering in
                if hovering {
                    NSCursor.resizeUpDown.push()
                } else {
                    NSCursor.pop()
                }
            }
            .gesture(
                DragGesture(coordinateSpace: .global)
                    .onChanged { value in
                        if sftpDragStart == nil {
                            sftpDragStart = sftpFraction
                        }
                        let delta = -value.translation.height
                        let newFraction = sftpDragStart! + (delta / containerHeight)
                        sftpFraction = max(0.15, min(0.85, newFraction))
                    }
                    .onEnded { _ in
                        sftpDragStart = nil
                    }
            )

            SFTPBrowserView(session: session, isVisible: isShowingSFTP) {
                setSFTPVisible(false)
            }
        }
        .background(
            Color(nsColor: .windowBackgroundColor)
                .opacity(appearance.usesControlGlassEffects && sftpOccupiesSpace ? appearance.translucentOverlayOpacity : 1),
            in: cornerShape
        )
        .conditionalGlassEffect(enabled: appearance.usesControlGlassEffects && sftpOccupiesSpace, shape: cornerShape)
        .clipShape(cornerShape)
    }

    private func terminalPanel(size: CGSize) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 7, height: 7)
                    .shadow(color: statusColor.opacity(0.5), radius: 3)
                Text(session.host.name)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Text(statusText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer()
                HStack(spacing: 5) {
                    if !session.isConnected && !session.isConnecting {
                        Button { session.reconnect() } label: {
                            panelButtonIcon("arrow.clockwise")
                        }
                        .buttonStyle(TerminalPaneButtonStyle(usesGlass: appearance.usesControlGlassEffects))
                        .help(Text("重新连接"))
                    }
                    Button { session.clear() } label: {
                        panelButtonIcon("eraser")
                    }
                    .buttonStyle(TerminalPaneButtonStyle(usesGlass: appearance.usesControlGlassEffects))
                    .help(Text("清空终端"))

                    Button {
                        setSFTPVisible(!isShowingSFTP)
                    } label: {
                        panelButtonIcon(isShowingSFTP ? "externaldrive.connected.to.line.below.fill" : "externaldrive.connected.to.line.below")
                    }
                    .buttonStyle(TerminalPaneButtonStyle(usesGlass: appearance.usesControlGlassEffects))
                    .help(Text("切换 SFTP"))

                    SplitHostButton(
                        icon: "rectangle.split.2x1",
                        label: "Split Right",
                        hosts: hosts,
                        action: onSplitRight
                    )
                    .buttonStyle(TerminalPaneButtonStyle(usesGlass: appearance.usesControlGlassEffects))
                    .disabled(size.width < 508)

                    SplitHostButton(
                        icon: "rectangle.split.1x2",
                        label: "Split Down",
                        hosts: hosts,
                        action: onSplitDown
                    )
                    .buttonStyle(TerminalPaneButtonStyle(usesGlass: appearance.usesControlGlassEffects))
                    .disabled(size.height < 368)

                    Button(action: onClose) {
                        panelButtonIcon("xmark")
                    }
                    .buttonStyle(TerminalPaneButtonStyle(role: .destructive, usesGlass: appearance.usesControlGlassEffects))
                    .help(Text("关闭 SSH 窗格"))
                }
            }
            .padding(.horizontal, 12)
            .frame(height: terminalChromeHeight)
            .background {
                Rectangle()
                    .fill(
                        Color(nsColor: .windowBackgroundColor)
                            .opacity(appearance.usesLiquidGlassEffects ? appearance.translucentChromeOpacity : 1)
                    )
                    .conditionalGlassEffect(enabled: appearance.usesLiquidGlassEffects, shape: Rectangle())
                    .gesture(
                        DragGesture(coordinateSpace: .global)
                            .onChanged { value in
                                titleBarDragAction?(value.translation, false)
                            }
                            .onEnded { value in
                                titleBarDragAction?(value.translation, true)
                            }
                    )
            }
            .overlay(
                Rectangle()
                    .fill(Color.black.opacity(0.1))
                    .frame(height: 1),
                alignment: .bottom
            )

            Divider()

            ZStack(alignment: .trailing) {
                VStack(spacing: 0) {
                    SwiftTermTerminal(
                        session: session,
                        surface: surface,
                        isActive: isActive,
                        isTabActive: isTabActive,
                        backgroundColor: appearance.backgroundColor,
                        foregroundColor: appearance.foregroundColor,
                        cursorColor: appearance.cursorColor,
                        font: appearance.font,
                        cursorStyle: appearance.cursorStyle,
                        send: session.send,
                        clear: session.clear,
                        resize: session.resize,
                        connect: session.connect,
                        activate: onActivate,
                        updateDirectory: session.setCurrentDirectory,
                        onNewTab: onNewTab,
                        onSplitRight: onSplitRight,
                        onSplitDown: onSplitDown,
                        onClose: onClose
                    )
                    .contextMenu {
                        Button("设置临时回滚行数...") {
                            tempScrollbackInput = "2000"
                            isShowingTempScrollbackAlert = true
                        }
                        Button(role: .destructive) {
                            onClose()
                        } label: {
                            Label("关闭", systemImage: "xmark")
                        }
                    }
                    Color(nsColor: appearance.backgroundColor)
                        .frame(height: terminalBottomInset)
                }
                .background(Color(nsColor: appearance.backgroundColor))
                
                if surface.canScroll {
                    GeometryReader { geom in
                        TerminalScrollbar(surface: surface, containerHeight: geom.size.height)
                    }
                    .frame(width: 22)
                }
            }
            .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
        }
        .frame(minHeight: 50, maxHeight: .infinity)
        .frame(height: splitHeight)
    }

    private func panelButtonIcon(_ name: String) -> some View {
        Image(systemName: name)
            .frame(width: 12, height: 12)
    }

    private var statusText: String {
        if session.isConnected { return "[\(session.host.destination)]" }
        if session.isConnecting { return "[Connecting to \(session.host.destination)…]" }
        if let error = session.errorMessage { return "[\(error)]" }
        return "[Disconnected]"
    }

    private var statusColor: SwiftUI.Color {
        if session.isConnected { return .green }
        if session.isConnecting { return .orange }
        return .secondary
    }
}

private struct SplitHostButton: View {
    let icon: String
    let label: String
    let hosts: [SSHHost]
    let action: (SSHHost) -> Void
    @State private var isShowingPicker = false

    var body: some View {
        Button {
            isShowingPicker = true
        } label: {
            Image(systemName: icon)
                .frame(width: 12, height: 12)
        }
        .help(label)
        .popover(isPresented: $isShowingPicker, arrowEdge: .bottom) {
            HostPickerView(hosts: hosts, showCancelButton: false) { host in
                action(host)
                isShowingPicker = false
            }
            .frame(width: 300, height: 350)
        }
    }
}

private struct TerminalPaneButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.colorScheme) private var colorScheme

    enum Role {
        case normal
        case destructive
    }

    let role: Role
    let usesGlass: Bool

    init(role: Role = .normal, usesGlass: Bool = false) {
        self.role = role
        self.usesGlass = usesGlass
    }

    func makeBody(configuration: Configuration) -> some View {
        TerminalPaneButtonBody(
            label: configuration.label,
            isPressed: configuration.isPressed,
            isEnabled: isEnabled,
            colorScheme: colorScheme,
            role: role,
            usesGlass: usesGlass
        )
    }
}

private struct TerminalPaneButtonBody<Label: View>: View {
    let label: Label
    let isPressed: Bool
    let isEnabled: Bool
    let colorScheme: ColorScheme
    let role: TerminalPaneButtonStyle.Role
    let usesGlass: Bool
    @State private var isHovering = false

    var body: some View {
        label
            .foregroundStyle(foregroundColor)
            .frame(width: 20, height: 20)
            .background { buttonBackground }
            .scaleEffect(isHovering && isEnabled ? 1.06 : 1.0)
            .shadow(
                color: shadowColor,
                radius: isHovering && usesGlass ? 5 : 0,
                y: isHovering && usesGlass ? 2 : 0
            )
            .contentShape(Rectangle())
            .opacity(isEnabled ? (isPressed ? 0.85 : 1) : 0.35)
            .onHover { hovering in
                withAnimation(.easeInOut(duration: 0.12)) {
                    isHovering = hovering
                }
            }
    }

    private var foregroundColor: SwiftUI.Color {
        role == .destructive ? SwiftUI.Color.red : SwiftUI.Color.primary
    }

    @ViewBuilder
    private var buttonBackground: some View {
        let shape = RoundedRectangle(cornerRadius: 5, style: .continuous)
        if usesGlass {
            shape
                .fill(backgroundColor(isPressed: isPressed))
                .glassEffect(.regular.interactive(), in: shape)
                .overlay {
                    shape.fill(
                        SwiftUI.Color.white.opacity(colorScheme == .dark
                            ? (isHovering ? 0.08 : 0.02)
                            : (isHovering ? 0.18 : 0.06)
                        )
                    )
                }
                .overlay {
                    shape.stroke(
                        SwiftUI.Color.white.opacity(colorScheme == .dark
                            ? (isHovering ? 0.28 : 0.16)
                            : (isHovering ? 0.46 : 0.32)
                        ),
                        lineWidth: 0.75
                    )
                }
        } else {
            shape.fill(backgroundColor(isPressed: isPressed))
        }
    }

    private func backgroundColor(isPressed: Bool) -> SwiftUI.Color {
        switch role {
        case .normal:
            return SwiftUI.Color.secondary.opacity(isPressed ? 0.18 : 0.08)
        case .destructive:
            return SwiftUI.Color.red.opacity(isPressed ? 0.20 : 0.10)
        }
    }

    private var shadowColor: SwiftUI.Color {
        switch role {
        case .normal:
            return SwiftUI.Color.black.opacity(colorScheme == .dark ? 0.22 : 0.12)
        case .destructive:
            return SwiftUI.Color.red.opacity(0.18)
        }
    }
}

@MainActor
final class TerminalSurface: ObservableObject {
    var terminal: RuiTermTerminalView?
    @Published var scrollPosition: Double = 1.0
    @Published var scrollThumbsize: Double = 1.0
    @Published var canScroll: Bool = false
}

private struct SwiftTermTerminal: NSViewRepresentable {
    @ObservedObject var session: SSHSession
    let surface: TerminalSurface
    let isActive: Bool
    let isTabActive: Bool
    let backgroundColor: NSColor
    let foregroundColor: NSColor
    let cursorColor: NSColor
    let font: NSFont
    let cursorStyle: CursorStyle
    let send: (Data) -> Void
    let clear: () -> Void
    let resize: (UInt16, UInt16) -> Void
    let connect: (UInt16?, UInt16?) -> Void
    let activate: () -> Void
    let updateDirectory: (String?) -> Void
    let onNewTab: (SSHHost) -> Void
    let onSplitRight: (SSHHost) -> Void
    let onSplitDown: (SSHHost) -> Void
    let onClose: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(session: session)
    }

    func makeNSView(context: Context) -> RuiTermTerminalView {
        let isNewTerminal = surface.terminal == nil
        let terminal = surface.terminal ?? RuiTermTerminalView(frame: .zero, font: font)
        surface.terminal = terminal
        terminal.autoresizingMask = [.width, .height]
        terminal.sendData = send
        terminal.clearSession = clear
        terminal.resizeTerminal = resize
        terminal.connectTerminal = connect
        terminal.activatePane = activate
        terminal.updateDirectory = updateDirectory
        
        let onNewTabLocal = self.onNewTab
        let onSplitRightLocal = self.onSplitRight
        let onSplitDownLocal = self.onSplitDown
        let onCloseLocal = self.onClose
        let host = session.host
        
        terminal.delegateOnNewTab = { onNewTabLocal(host) }
        terminal.delegateOnSplitRight = { onSplitRightLocal(host) }
        terminal.delegateOnSplitDown = { onSplitDownLocal(host) }
        terminal.delegateOnClose = { onCloseLocal() }
        
        terminal.onScroll = { [weak surface] position, thumb, can in
            guard let surface else { return }
            if abs(surface.scrollPosition - position) > 0.002 {
                surface.scrollPosition = position
            }
            if abs(surface.scrollThumbsize - thumb) > 0.002 {
                surface.scrollThumbsize = thumb
            }
            if surface.canScroll != can {
                surface.canScroll = can
            }
        }
        terminal.applyTheme(
            backgroundColor: backgroundColor,
            foregroundColor: foregroundColor,
            cursorColor: cursorColor,
            font: font,
            cursorStyle: cursorStyle
        )
        terminal.isHidden = !isTabActive
        terminal.setRenderingActive(isTabActive)
        session.setTerminalOutputInteractive(isActive && isTabActive)
        context.coordinator.terminal = terminal
        context.coordinator.terminalHandlerID = session.attachTerminal(
            rawData: { [weak terminal] data in
                terminal?.feedSessionData(data)
            },
            clear: { [weak terminal] in
                terminal?.resetTerminalBuffer()
            },
            replay: isNewTerminal
        )
        context.coordinator.lastIsActive = isActive
        if isActive {
            DispatchQueue.main.async {
                terminal.requestFocusIfAppropriate()
            }
        }
        return terminal
    }

    func updateNSView(_ terminal: RuiTermTerminalView, context: Context) {
        terminal.sendData = send
        terminal.clearSession = clear
        terminal.resizeTerminal = resize
        terminal.connectTerminal = connect
        terminal.activatePane = activate
        terminal.updateDirectory = updateDirectory
        terminal.applyTheme(
            backgroundColor: backgroundColor,
            foregroundColor: foregroundColor,
            cursorColor: cursorColor,
            font: font,
            cursorStyle: cursorStyle
        )
        terminal.isHidden = !isTabActive
        terminal.setRenderingActive(isTabActive)
        session.setTerminalOutputInteractive(isActive && isTabActive)
        if isActive && !context.coordinator.lastIsActive {
            DispatchQueue.main.async {
                terminal.requestFocusIfAppropriate()
            }
        }
        context.coordinator.lastIsActive = isActive
    }

    static func dismantleNSView(_ terminal: RuiTermTerminalView, coordinator: Coordinator) {
        coordinator.session.setTerminalOutputInteractive(false)
        // Persistent tab surfaces keep their terminal buffer, but an off-screen
        // MTKView also keeps several full-window IOSurfaces alive. Release the
        // GPU renderer here; viewDidMoveToWindow restores it when the tab returns.
        terminal.suspendRendering()
        terminal.activatePane = nil
        TerminalCommandCenter.shared.blur(terminal)
    }

    @MainActor
    final class Coordinator {
        let session: SSHSession
        weak var terminal: RuiTermTerminalView?
        var terminalHandlerID: UUID?
        var lastIsActive = false

        init(session: SSHSession) {
            self.session = session
        }
    }
}

@MainActor
final class RuiTermTerminalView: SwiftTerm.TerminalView, @preconcurrency SwiftTerm.TerminalViewDelegate, TerminalCommandTarget {
    var sendData: ((Data) -> Void)?
    var clearSession: (() -> Void)?
    var resizeTerminal: ((UInt16, UInt16) -> Void)?
    var connectTerminal: ((UInt16?, UInt16?) -> Void)?
    var activatePane: (() -> Void)?
    var updateDirectory: ((String?) -> Void)?
    var delegateOnNewTab: (() -> Void)?
    var delegateOnSplitRight: (() -> Void)?
    var delegateOnSplitDown: (() -> Void)?
    var delegateOnClose: (() -> Void)?
    var onScroll: ((Double, Double, Bool) -> Void)?
    private let defaultFontSize: Double = 13.5
    private var pendingScrollState: (position: Double, thumb: Double, canScroll: Bool)?
    private var scrollUpdateTask: Task<Void, Never>?
    private let scrollUpdateInterval: UInt64 = 200_000_000
    private var allowsMetalRenderer = false
    private var preferredScrollbackLines = AppearanceSettings.shared.effectiveScrollbackLines
    private let logBurstScrollbackLimit = TerminalScrollbackLimits.logBurstMaximum
    private let logBurstThreshold = 256 * 1024
    private let terminalFeedChunkSize = 256 * 1024
    private var isUsingLogBurstScrollbackLimit = false
    private var restoreScrollbackTask: Task<Void, Never>?
    private var recentBytesAccumulated: Int = 0
    private var burstAccumulatorResetTime: TimeInterval = 0
    private var burstRestoreTime: TimeInterval = 0

    override init(frame: CGRect, font: NSFont?) {
        super.init(frame: frame, font: font)
        configureTerminal()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureTerminal()
    }

    private func configureTerminal() {
        terminalDelegate = self
        optionAsMetaKey = true
        contentInsetLeft = 2
        preferredScrollbackLines = AppearanceSettings.shared.effectiveScrollbackLines
        changeScrollback(preferredScrollbackLines)
        allowsMetalRenderer = ProcessInfo.processInfo.environment["RUITERM_ENABLE_METAL"] == "1"
            && ProcessInfo.processInfo.environment["RUITERM_DISABLE_METAL"] != "1"
        metalBufferingMode = .perRowPersistent
        registerForDraggedTypes([.fileURL, .URL, .string])
    }

    func suspendRendering() {
        guard isUsingMetalRenderer else { return }
        try? setUseMetal(false)
    }

    func setRenderingActive(_ isActive: Bool) {
        guard isActive, window != nil, allowsMetalRenderer else {
            suspendRendering()
            return
        }
        guard !isUsingMetalRenderer else { return }
        try? setUseMetal(true)
    }

    func setTemporaryScrollback(_ lines: Int) {
        preferredScrollbackLines = AppearanceSettings.clampedScrollbackLines(lines)
        if isUsingLogBurstScrollbackLimit {
            changeScrollback(min(preferredScrollbackLines, logBurstScrollbackLimit))
        } else {
            changeScrollback(preferredScrollbackLines)
        }
    }

    func feedSessionData(_ data: Data) {
        adaptScrollbackForIncomingData(byteCount: data.count)
        data.withUnsafeBytes { rawBuffer in
            let bytes = rawBuffer.bindMemory(to: UInt8.self)
            var offset = 0
            while offset < bytes.count {
                let end = min(bytes.count, offset + terminalFeedChunkSize)
                autoreleasepool {
                    let chunk = Array(bytes[offset..<end])
                    feed(byteArray: chunk[...])
                }
                offset = end
            }
        }
    }

    private func adaptScrollbackForIncomingData(byteCount: Int) {
        guard preferredScrollbackLines > logBurstScrollbackLimit else { return }
        let now = Date().timeIntervalSinceReferenceDate
        
        if now - burstAccumulatorResetTime >= 1.0 {
            recentBytesAccumulated = 0
            burstAccumulatorResetTime = now
        }
        recentBytesAccumulated += byteCount
        
        if recentBytesAccumulated >= logBurstThreshold {
            if !isUsingLogBurstScrollbackLimit {
                isUsingLogBurstScrollbackLimit = true
                metalBufferingMode = .perFrameAggregated
                changeScrollback(logBurstScrollbackLimit)
            }
            burstRestoreTime = now + 5.0
            
            if restoreScrollbackTask == nil {
                restoreScrollbackTask = Task { [weak self] in
                    while !Task.isCancelled {
                        try? await Task.sleep(nanoseconds: 1_000_000_000)
                        await MainActor.run {
                            guard let self = self else { return }
                            let currentNow = Date().timeIntervalSinceReferenceDate
                            if self.isUsingLogBurstScrollbackLimit, currentNow >= self.burstRestoreTime {
                                self.isUsingLogBurstScrollbackLimit = false
                                self.recentBytesAccumulated = 0
                                self.metalBufferingMode = .perRowPersistent
                                self.changeScrollback(self.preferredScrollbackLines)
                                self.restoreScrollbackTask?.cancel()
                                self.restoreScrollbackTask = nil
                            }
                        }
                        if self == nil || self?.restoreScrollbackTask == nil { break }
                    }
                }
            }
        }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil {
            TerminalCommandCenter.shared.blur(self)
        }
        setRenderingActive(window != nil && !isHidden)
    }

    override func mouseDown(with event: NSEvent) {
        activatePane?()
        window?.makeFirstResponder(self)
        SFTPCommandCenter.shared.blur()
        TerminalCommandCenter.shared.focus(self)
        super.mouseDown(with: event)
    }

    func requestFocusIfAppropriate() {
        guard window?.isKeyWindow == true, NSApp.keyWindow === window else { return }
        guard !SFTPCommandCenter.shared.isKeyResponder else { return }
        guard !(window?.firstResponder is NSText) else { return }
        window?.makeFirstResponder(self)
        TerminalCommandCenter.shared.focus(self)
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        draggedFileURLs(from: sender.draggingPasteboard).isEmpty ? [] : .copy
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let urls = draggedFileURLs(from: sender.draggingPasteboard)
        guard !urls.isEmpty else { return false }

        let text = urls
            .map { Self.shellQuotedPath($0.path) }
            .joined(separator: " ") + " "
        sendData?(Data(text.utf8))
        window?.makeFirstResponder(self)
        SFTPCommandCenter.shared.blur()
        TerminalCommandCenter.shared.focus(self)
        return true
    }

    override func keyDown(with event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if flags.contains(.command) {
            if handleConfiguredShortcut(event) {
                return
            }
            if handleTerminalCommand(event) {
                return
            }
        }
        if flags == .option {
            switch event.keyCode {
            case 123: // Option + Left
                sendData?(Data([0x1B, 0x62])) // Esc b
                return
            case 124: // Option + Right
                sendData?(Data([0x1B, 0x66])) // Esc f
                return
            case 51: // Option + Delete
                sendData?(Data([0x1B, 0x7F])) // Esc + Delete
                return
            default:
                break
            }
        }
        super.keyDown(with: event)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if handleConfiguredShortcut(event) {
            return true
        }
        if handleTerminalCommand(event) {
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    func applyTheme(
        backgroundColor: NSColor,
        foregroundColor: NSColor,
        cursorColor: NSColor,
        font: NSFont,
        cursorStyle: CursorStyle
    ) {
        if nativeBackgroundColor != backgroundColor {
            nativeBackgroundColor = backgroundColor
            layer?.backgroundColor = backgroundColor.cgColor
        }
        wantsLayer = true
        layer?.isOpaque = backgroundColor.alphaComponent >= 0.99
        if nativeForegroundColor != foregroundColor {
            nativeForegroundColor = foregroundColor
        }
        if caretColor != cursorColor {
            caretColor = cursorColor
        }
        if self.font != font {
            self.font = font
        }
        getTerminal().setCursorStyle(swiftTermCursorStyle(cursorStyle))
        if !customBlockGlyphs {
            customBlockGlyphs = true
        }
        useBrightColors = true
    }

    func resetTerminalBuffer() {
        getTerminal().resetToInitialState()
        needsDisplay = true
    }

    func copySelection() {
        copy(self)
    }

    func pasteClipboard() {
        paste(self)
    }

    func selectAllContent() {
        selectAll(self)
    }

    func clearTerminal() {
        clearSession?()
    }

    func sendClearScreen() {
        sendData?(Data([0x0C]))
    }

    func moveToBeginningOfLine() {
        if getTerminal().isCurrentBufferAlternate {
            sendData?(Data(getTerminal().applicationCursor ? EscapeSequences.moveHomeApp : EscapeSequences.moveHomeNormal))
        } else {
            sendData?(Data([0x01])) // \x01 (Ctrl-A in shell/readline)
        }
    }

    func moveToEndOfLine() {
        if getTerminal().isCurrentBufferAlternate {
            sendData?(Data(getTerminal().applicationCursor ? EscapeSequences.moveEndApp : EscapeSequences.moveEndNormal))
        } else {
            sendData?(Data([0x05])) // \x05 (Ctrl-E in shell/readline)
        }
    }

    func scrollPageUp() {
        if getTerminal().isCurrentBufferAlternate {
            sendData?(Data(EscapeSequences.cmdPageUp))
        } else {
            pageUp()
        }
    }

    func scrollPageDown() {
        if getTerminal().isCurrentBufferAlternate {
            sendData?(Data(EscapeSequences.cmdPageDown))
        } else {
            pageDown()
        }
    }

    func scrollToTop() {
        if getTerminal().isCurrentBufferAlternate {
            // In vi / vim: Ctrl-Home (\e[1;5H) jumps to top of document (line 1)
            sendData?(Data([0x1B, 0x5B, 0x31, 0x3B, 0x35, 0x48]))
        } else {
            scroll(toPosition: 0)
        }
    }

    func scrollToBottom() {
        if getTerminal().isCurrentBufferAlternate {
            // In vi / vim: Ctrl-End (\e[1;5F) jumps to bottom of document (last line)
            sendData?(Data([0x1B, 0x5B, 0x31, 0x3B, 0x35, 0x46]))
        } else {
            scroll(toPosition: 1)
        }
    }

    func increaseFontSize() {
        AppearanceSettings.shared.fontSize = min(32, AppearanceSettings.shared.fontSize + 1)
    }

    func decreaseFontSize() {
        AppearanceSettings.shared.fontSize = max(8, AppearanceSettings.shared.fontSize - 1)
    }

    func resetTerminalFontSize() {
        AppearanceSettings.shared.fontSize = defaultFontSize
    }

    private var resizeTask: Task<Void, Never>?

    func sizeChanged(source: SwiftTerm.TerminalView, newCols: Int, newRows: Int) {
        let columns = UInt16(max(1, min(Int(UInt16.max), newCols)))
        let rows = UInt16(max(1, min(Int(UInt16.max), newRows)))

        resizeTask?.cancel()
        resizeTask = Task {
            try? await Task.sleep(nanoseconds: 150_000_000) // 150ms debounce
            if !Task.isCancelled {
                resizeTerminal?(columns, rows)
            }
        }
    }

    func send(source: SwiftTerm.TerminalView, data: ArraySlice<UInt8>) {
        sendData?(Data(data))
    }

    func setTerminalTitle(source: SwiftTerm.TerminalView, title: String) {}

    func hostCurrentDirectoryUpdate(source: SwiftTerm.TerminalView, directory: String?) {
        let wasFirstResponder = window?.isKeyWindow == true
            && NSApp.keyWindow === window
            && window?.firstResponder === self
        NSLog("[SFTP] OSC 7 received: directory=%@", directory ?? "nil")
        updateDirectory?(directory)
        if wasFirstResponder {
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                guard self.window?.isKeyWindow == true, NSApp.keyWindow === self.window else { return }
                self.window?.makeFirstResponder(self)
                TerminalCommandCenter.shared.focus(self)
            }
        }
    }

    func scrolled(source: SwiftTerm.TerminalView, position: Double) {
        pendingScrollState = (position, scrollThumbsize, canScroll)
        guard scrollUpdateTask == nil else { return }
        let interval = scrollUpdateInterval
        scrollUpdateTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: interval)
            self?.flushPendingScrollState()
        }
    }

    private func flushPendingScrollState() {
        scrollUpdateTask?.cancel()
        scrollUpdateTask = nil
        guard let state = pendingScrollState else { return }
        pendingScrollState = nil
        onScroll?(state.position, state.thumb, state.canScroll)
    }

    func clipboardCopy(source: SwiftTerm.TerminalView, content: Data) {
        guard let string = String(data: content, encoding: .utf8) else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
    }

    func clipboardRead(source: SwiftTerm.TerminalView) -> Data? {
        NSPasteboard.general.string(forType: .string)?.data(using: .utf8)
    }

    func rangeChanged(source: SwiftTerm.TerminalView, startY: Int, endY: Int) {}

    private func swiftTermCursorStyle(_ style: CursorStyle) -> SwiftTerm.CursorStyle {
        switch style {
        case .block: return .blinkBlock
        case .bar: return .blinkBar
        case .underline: return .blinkUnderline
        }
    }

    private func handleTerminalCommand(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard flags.contains(.command) else { return false }
        // Only handle keyboard shortcuts when this terminal is the first responder
        // of the current key window (prevents stealing from sheets/popovers)
        guard window?.isKeyWindow == true, window?.firstResponder === self else { return false }

        switch event.keyCode {
        case 51: // Command + Delete
            sendData?(Data([0x15])) // Ctrl-U
            return true
        case 24, 69:
            increaseFontSize()
            return true
        case 27, 78:
            decreaseFontSize()
            return true
        case 29, 82:
            resetTerminalFontSize()
            return true
        default:
            break
        }

        guard let key = event.charactersIgnoringModifiers?.lowercased() else {
            return false
        }

        switch key {
        case "a":
            selectAllContent()
        case "c":
            copySelection()
        case "k":
            clearTerminal()
        case "l":
            sendClearScreen()
        case "v":
            pasteClipboard()
        default:
            return false
        }
        return true
    }

    private func handleConfiguredShortcut(_ event: NSEvent) -> Bool {
        guard window?.isKeyWindow == true, window?.firstResponder === self else { return false }
        guard let action = TerminalShortcutSettings.shared.action(matching: event) else { return false }

        switch action {
        case .beginningOfLine:
            moveToBeginningOfLine()
        case .endOfLine:
            moveToEndOfLine()
        case .wordLeft:
            if getTerminal().isCurrentBufferAlternate {
                sendData?(Data(EscapeSequences.emacsBack))
            } else {
                sendData?(Data([0x1B, 0x62]))
            }
        case .wordRight:
            if getTerminal().isCurrentBufferAlternate {
                sendData?(Data(EscapeSequences.emacsForward))
            } else {
                sendData?(Data([0x1B, 0x66]))
            }
        case .pageUp:
            scrollPageUp()
        case .pageDown:
            scrollPageDown()
        case .scrollToTop:
            scrollToTop()
        case .scrollToBottom:
            scrollToBottom()
        case .deleteToBeginningOfLine:
            sendData?(Data([0x15])) // Ctrl-U
        case .deleteWordBackward:
            sendData?(Data([0x1B, 0x7F])) // Esc + Delete
        case .clearScreen:
            clearTerminal()
        case .increaseFontSize:
            increaseFontSize()
        case .decreaseFontSize:
            decreaseFontSize()
        case .resetFontSize:
            resetTerminalFontSize()
        case .newTab:
            delegateOnNewTab?()
        case .splitRight:
            delegateOnSplitRight?()
        case .splitDown:
            delegateOnSplitDown?()
        case .closePane:
            delegateOnClose?()
        case .copy:
            copySelection()
        case .paste:
            pasteClipboard()
        case .selectAll:
            selectAllContent()
        case .find:
            showFind()
        }
        return true
    }

    private func draggedFileURLs(from pasteboard: NSPasteboard) -> [URL] {
        if let urls = pasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [URL] {
            return urls
        }
        if let paths = pasteboard.propertyList(forType: .fileURL) as? [String] {
            return paths.map { URL(fileURLWithPath: $0) }
        }
        if let string = pasteboard.string(forType: .fileURL),
           let url = URL(string: string),
           url.isFileURL {
            return [url]
        }
        return []
    }

    private static func shellQuotedPath(_ path: String) -> String {
        "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

#if DEBUG
    nonisolated private static var isDebuggerAttached: Bool {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
        let result = mib.withUnsafeMutableBufferPointer { pointer in
            sysctl(pointer.baseAddress, u_int(pointer.count), &info, &size, nil, 0)
        }
        guard result == 0 else { return false }
        return (info.kp_proc.p_flag & P_TRACED) != 0
    }
#endif
}

struct TerminalScrollbar: View {
    @ObservedObject var surface: TerminalSurface
    let containerHeight: CGFloat
    
    @State private var isHovering = false
    @State private var isDragging = false
    
    var body: some View {
        let knobHeight = max(20, containerHeight * surface.scrollThumbsize)
        let maxOffset = containerHeight - knobHeight - 8
        // scrollPosition is 0 at top, 1 at bottom
        let yOffset = 4 + surface.scrollPosition * maxOffset
        
        HStack {
            Spacer()
            ZStack(alignment: .top) {
                // Hover track
                Rectangle()
                    .fill(Color.black.opacity(isHovering || isDragging ? 0.05 : 0))
                    .frame(width: 14)
                
                // Knob
                Capsule()
                    .fill(Color.primary.opacity(isHovering || isDragging ? 0.4 : 0.2))
                    .frame(width: isHovering || isDragging ? 10 : 7, height: knobHeight)
                    .offset(y: yOffset)
                    .padding(.horizontal, isHovering || isDragging ? 3 : 4)
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                isDragging = true
                                let relativeY = value.location.y - 4 - knobHeight / 2
                                let fraction = max(0, min(1, relativeY / maxOffset))
                                surface.terminal?.scroll(toPosition: fraction)
                            }
                            .onEnded { _ in
                                isDragging = false
                            }
                    )
            }
            .frame(width: 16, height: containerHeight)
            .contentShape(Rectangle())
            .padding(.trailing, 6)
            .onHover { hovering in
                withAnimation(.easeInOut(duration: 0.15)) {
                    isHovering = hovering
                }
            }
            .opacity(surface.canScroll ? (isHovering || isDragging ? 1 : 0.3) : 0)
        }
    }
}
