import SwiftUI

private enum RuiChromeRadii {
    static let outer: CGFloat = 14
    static let inner: CGFloat = 12
}

@MainActor
private final class WorkspaceTab: Identifiable, ObservableObject {
    let id = UUID()
    let host: SSHHost
    let session: SSHSession
    let workspace: TerminalWorkspace

    init(host: SSHHost) {
        self.host = host
        self.session = SSHSession(host: host)
        self.workspace = TerminalWorkspace(primaryHost: host, tabSession: session)
    }

    func disconnect() {
        workspace.disconnect()
    }
}

struct ContentView: View {
    @EnvironmentObject private var hostStore: HostStore
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var appearance = AppearanceSettings.shared
    @State private var tabs: [WorkspaceTab] = []
    @State private var activeTabID: WorkspaceTab.ID?
    @State private var selectedSidebarHostID: SSHHost.ID?
    @State private var searchText = ""
    @State private var editingHost: SSHHost?
    @State private var hostPendingDeletion: SSHHost?
    @State private var groupPendingDeletion: SSHGroup?
    @State private var groupPendingRename: SSHGroup?
    @State private var isCreatingGroup = false
    @State private var newGroupName = ""
    @State private var renamedGroupName = ""
    @State private var collapsedSections: Set<String> = []
    @State private var newHostTemplate = SSHHost()
    @State private var isShowingHostPicker = false
    @State private var isShowingTabOverview = false
    @AppStorage("showHostStatus") private var showHostStatus = false
    @State private var windowWidth: CGFloat = 1000
    @State private var hostStatusVisible = UserDefaults.standard.bool(forKey: "showHostStatus")
    @State private var hostStatusOccupiesSpace = UserDefaults.standard.bool(forKey: "showHostStatus")
    @AppStorage("autoOpenLocalTerminal") private var autoOpenLocalTerminal = false
    @State private var isWindowKey = true

    @State private var hostToOptimize: SSHHost?
    @State private var optimizationError: String?

    private var filteredHosts: [SSHHost] {
        guard !searchText.isEmpty else { return hostStore.hosts }
        return hostStore.hosts.filter {
            $0.name.localizedCaseInsensitiveContains(searchText)
                || $0.hostname.localizedCaseInsensitiveContains(searchText)
                || $0.username.localizedCaseInsensitiveContains(searchText)
        }
    }

    private var allSectionIDs: Set<String> {
        var ids = Set(["favorites", "ungrouped"])
        for group in hostStore.groups {
            ids.insert(group.id.uuidString)
        }
        return ids
    }

    private var allSectionsCollapsed: Bool {
        allSectionIDs.allSatisfy { collapsedSections.contains($0) }
    }

    private func toggleAllSections() {
        let allIDs = allSectionIDs
        if allSectionsCollapsed {
            withAnimation(.easeInOut(duration: 0.2)) {
                collapsedSections.removeAll()
            }
        } else {
            withAnimation(.easeInOut(duration: 0.2)) {
                collapsedSections = allIDs
            }
        }
    }

    private var toolbarTabBarWidth: CGFloat {
        // Compact windows leave more room for controls; wide windows devote
        // progressively more of the title bar to tabs.
        let expansion = min(max((windowWidth - 1_350) / 650, 0), 1)
        let widthRatio = 0.48 + expansion * 0.24
        return max(240, windowWidth * widthRatio)
    }

    @State private var showSidebar = true
    @State private var sidebarOccupiesSpace = true

    private var appBackground: Color {
        guard !appearance.usesLiquidGlassEffects else { return .clear }
        return colorScheme == .dark ? Color(white: 0.08) : .white
    }

    private var toolbarBackgroundStyle: AnyShapeStyle {
        appearance.usesLiquidGlassEffects ? AnyShapeStyle(.clear) : AnyShapeStyle(appBackground)
    }

    private var allowsTerminalOutputInteractivity: Bool {
        isWindowKey && !isShowingHostPicker && !isShowingTabOverview
    }

    private func toggleSidebar() {
        if showSidebar {
            withTransaction(Transaction(animation: nil)) {
                sidebarOccupiesSpace = false
            }
            withAnimation(.easeInOut(duration: 0.22)) {
                showSidebar = false
            }
        } else {
            withTransaction(Transaction(animation: nil)) {
                sidebarOccupiesSpace = true
            }
            withAnimation(.easeInOut(duration: 0.22)) {
                showSidebar = true
            }
        }
    }

    private func setHostStatusVisible(_ visible: Bool) {
        guard visible != hostStatusVisible else { return }
        if visible {
            withTransaction(Transaction(animation: nil)) {
                hostStatusOccupiesSpace = true
            }
            withAnimation(.easeInOut(duration: 0.22)) {
                hostStatusVisible = true
            }
        } else {
            withTransaction(Transaction(animation: nil)) {
                hostStatusOccupiesSpace = false
            }
            withAnimation(.easeInOut(duration: 0.22)) {
                hostStatusVisible = false
            }
        }
    }

    private func toggleHostStatus() {
        showHostStatus.toggle()
        setHostStatusVisible(showHostStatus)
    }

    private var activeTab: WorkspaceTab? {
        tabs.first { $0.id == activeTabID }
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .leading) {
                HStack(spacing: 8) {
                    if sidebarOccupiesSpace {
                        Color.clear
                            .frame(width: 230)
                            .allowsHitTesting(false)
                    }

                    VStack(spacing: 4) {
                        customTabStrip

                        mainContent
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }

                if showSidebar {
                    sidebar
                        .frame(width: 230)
                        .transition(.move(edge: .leading).combined(with: .opacity))
                        .zIndex(1)
                }
            }
            .padding(8)
            .toolbar {
                // 左侧：侧边栏切换 + 配置与导入导出菜单
                ToolbarItemGroup(placement: .navigation) {
                    Button(action: toggleSidebar) {
                        Image(systemName: "sidebar.left")
                    }
                    .help(showSidebar ? "隐藏侧边栏" : "显示侧边栏")

                    importExportMenu
                }

                ToolbarItem(placement: .primaryAction) {
                    titlebarMonitorContent
                }

                ToolbarSpacer(.fixed, placement: .primaryAction)

                ToolbarItem(placement: .primaryAction) {
                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            isShowingTabOverview.toggle()
                        }
                    } label: {
                        ToolbarIconLabel(systemName: isShowingTabOverview ? "square.on.square.fill" : "square.on.square")
                    }
                    .help(Text("显示所有标签页"))
                    .disabled(tabs.isEmpty)
                }

                ToolbarItem(placement: .primaryAction) {
                    Button(action: toggleHostStatus) {
                        ToolbarIconLabel(systemName: "display")
                    }
                    .help(Text("切换主机状态显示"))
                    .disabled(tabs.isEmpty)
                }

                ToolbarItem(placement: .primaryAction) {
                    TransferButtonView()
                }

                ToolbarItem(placement: .primaryAction) {
                    Button {
                        prepareForNewTabInteraction()
                        setAllTerminalOutputInteractive(false)
                        isShowingHostPicker = true
                    } label: {
                        ToolbarIconLabel(systemName: "plus")
                    }
                    .help(Text("新建标签页"))
                }
            }
            .navigationTitle("")
            .toolbarBackground(toolbarBackgroundStyle, for: .windowToolbar)
            .toolbarBackground(.visible, for: .windowToolbar)
            .sheet(item: $hostToOptimize) { host in
                OptimizationWizardView(
                    isPresented: Binding(
                        get: { hostToOptimize != nil },
                        set: { if !$0 { hostToOptimize = nil } }
                    ),
                    host: host,
                    onAccept: {
                        runOptimization(host)
                    },
                    onDecline: {
                        var updated = host
                        updated.hasPromptedOptimization = true
                        hostStore.update(updated)
                    }
                )
            }
            .alert("优化失败", isPresented: Binding(
                get: { optimizationError != nil },
                set: { if !$0 { optimizationError = nil } }
            )) {
                Button("确定", role: .cancel) { }
            } message: {
                Text(optimizationError ?? "")
            }
        }
        .onChange(of: tabs.isEmpty) { _, isEmpty in
            if isEmpty {
                isShowingTabOverview = false
            }
        }
        .onChange(of: showHostStatus) { _, visible in
            setHostStatusVisible(visible)
        }
        .onChange(of: activeTabID) { _, _ in
            updateTerminalOutputInteractivity()
        }
        .onChange(of: isShowingHostPicker) { _, showing in
            showing ? setAllTerminalOutputInteractive(false) : updateTerminalOutputInteractivity()
        }
        .onChange(of: isShowingTabOverview) { _, _ in
            updateTerminalOutputInteractivity()
        }
        .onChange(of: isWindowKey) { _, _ in
            updateTerminalOutputInteractivity()
        }
        .background(
            GeometryReader { geo in
                Group {
                    if appearance.usesLiquidGlassEffects {
                        LiquidGlassBackdrop()
                    } else {
                        appBackground
                    }
                }
                    .ignoresSafeArea()
                    .onAppear {
                        if geo.size.width > 0 {
                            windowWidth = geo.size.width
                        }
                        if autoOpenLocalTerminal && tabs.isEmpty {
                            createLocalTab()
                        }
                    }
                    .onChange(of: geo.size.width) { _, newValue in
                        if newValue > 0 {
                            windowWidth = newValue
                        }
                    }
            }
        )
        .background(WindowKeyObserver(isKeyWindow: $isWindowKey))
        .background(WindowToolbarConfigurator())
        .background(
            ToolbarContextMenuInterceptor(
                tabs: tabs,
                activeTabID: activeTabID,
                tabBarWidth: toolbarTabBarWidth,
                closeTab: closeTab,
                closeTabsToLeft: closeTabsToLeft,
                closeTabsToRight: closeTabsToRight,
                closeOtherTabs: closeOtherTabs,
                closeAllTabs: closeAllTabs
            )
        )
        .sheet(isPresented: $hostStore.isPresentingNewHost, onDismiss: { newHostTemplate = SSHHost() }) {
            HostEditor(host: newHostTemplate, isNew: true)
                .environmentObject(hostStore)
        }
        .sheet(isPresented: $isShowingHostPicker) {
            HostPickerView(hosts: hostStore.hosts, showCancelButton: true) { host in
                createTab(host)
            }
            .frame(width: 440, height: 480)
        }
        .sheet(item: $editingHost) { host in
            HostEditor(host: host, isNew: false)
                .environmentObject(hostStore)
        }
        .alert("新建分组", isPresented: $isCreatingGroup) {
            TextField("分组名称", text: $newGroupName)
            Button("取消", role: .cancel) { newGroupName = "" }
            Button("创建") {
                hostStore.addGroup(named: newGroupName)
                newGroupName = ""
            }
        } message: {
            Text("为您的 SSH 主机创建一个可折叠的分组。")
        }
        .alert(
            "重命名分组",
            isPresented: Binding(
                get: { groupPendingRename != nil },
                set: { if !$0 { groupPendingRename = nil } }
            )
        ) {
            TextField("分组名称", text: $renamedGroupName)
            Button("取消", role: .cancel) { groupPendingRename = nil }
            Button("重命名") {
                if let groupPendingRename {
                    hostStore.renameGroup(groupPendingRename, to: renamedGroupName)
                }
                groupPendingRename = nil
            }
        }
        .alert(
            "删除 \(hostPendingDeletion?.name ?? "主机")？",
            isPresented: Binding(
                get: { hostPendingDeletion != nil },
                set: { if !$0 { hostPendingDeletion = nil } }
            )
        ) {
            Button("取消", role: .cancel) { hostPendingDeletion = nil }
            Button("删除", role: .destructive) {
                if let host = hostPendingDeletion {
                    tabs.filter { $0.host.id == host.id }.forEach { closeTab($0.id) }
                    hostStore.delete(host)
                }
                hostPendingDeletion = nil
            }
        } message: {
            Text("这将从本机移除该主机及其保存的密码。")
        }
        .alert(
            "删除 \(groupPendingDeletion?.name ?? "分组")？",
            isPresented: Binding(
                get: { groupPendingDeletion != nil },
                set: { if !$0 { groupPendingDeletion = nil } }
            )
        ) {
            Button("取消", role: .cancel) { groupPendingDeletion = nil }
            Button("删除", role: .destructive) {
                if let group = groupPendingDeletion { hostStore.deleteGroup(group) }
                groupPendingDeletion = nil
            }
        } message: {
            Text("该分组中的主机将被移动到未分组。")
        }
        .alert(
            "RuiTerm",
            isPresented: Binding(
                get: { hostStore.notice != nil },
                set: { if !$0 { hostStore.notice = nil } }
            )
        ) {
            Button("确定") { hostStore.notice = nil }
        } message: {
            Text(hostStore.notice ?? "")
        }
    }

    @ViewBuilder
    private var titlebarMonitorContent: some View {
        if let activeTab {
            SystemMonitorToolbarWidget(
                host: activeTab.host,
                session: activeTab.session,
                isActive: allowsTerminalOutputInteractivity
            )
            .id(activeTab.id)
        } else {
            SystemMonitorToolbarPlaceholder()
        }
    }


    private var customTabStrip: some View {
        Group {
            if tabs.isEmpty {
                EmptyView()
            } else {
                GeometryReader { geo in
                    HStack(spacing: 0) {
                        SafariStyleTabBar(
                            tabs: tabs,
                            activeTabID: $activeTabID,
                            availableWidth: max(240, geo.size.width - 6),
                            closeTab: closeTab,
                            closeTabsToLeft: closeTabsToLeft,
                            closeTabsToRight: closeTabsToRight,
                            closeOtherTabs: closeOtherTabs,
                            closeAllTabs: closeAllTabs
                        )
                        .frame(maxWidth: .infinity, alignment: .center)
                    }
                    .padding(3)
                    .frame(width: geo.size.width, height: 28)
                    .liquidGlassPanel(enabled: appearance.usesControlGlassEffects, cornerRadius: RuiChromeRadii.outer)
                }
                .frame(height: 28)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private var mainContent: some View {
        ZStack {
            if tabs.isEmpty {
                ContentUnavailableView(
                    "准备连接",
                    systemImage: "terminal.fill",
                    description: Text("从侧边栏选择一个主机或新建一个 SSH 标签页。")
                )
            } else {
                Group {
                    if let activeTab {
                        workspace(for: activeTab, isTabActive: true)
                            .id(activeTab.id)
                            .allowsHitTesting(!isShowingTabOverview)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .opacity(isShowingTabOverview ? 0.18 : 1)
                .saturation(isShowingTabOverview ? 0.35 : 1)
                .blur(radius: isShowingTabOverview ? 3 : 0)

                if isShowingTabOverview {
                    TabOverviewGrid(
                        tabs: tabs,
                        activeTabID: $activeTabID,
                        isShowingTabOverview: $isShowingTabOverview,
                        closeTab: closeTab
                    )
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
                }
            }
        }
    }

    private var sidebar: some View {
        let ungroupedHosts = filteredHosts.filter { $0.groupID == nil }

        return VStack(spacing: 0) {
            GlassEffectContainer(spacing: 6) {
                HStack(spacing: 6) {
                    SearchField(text: $searchText)

                    SidebarCollapseButton(isCollapsed: allSectionsCollapsed) {
                        toggleAllSections()
                    }
                }
            }
            .padding(.horizontal, 8)
            .padding(.top, 8)
            .padding(.bottom, 6)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 6) {
                    SidebarSection(
                        title: "收藏夹",
                        icon: "star.fill",
                        sectionID: "favorites",
                        hosts: filteredHosts.filter(\.isFavorite),
                        isCollapsed: collapsedBinding("favorites"),
                        hostRow: hostRow
                    )

                    ForEach(hostStore.groups) { group in
                        SidebarSection(
                            title: group.name,
                            icon: "folder",
                            sectionID: group.id.uuidString,
                            hosts: filteredHosts.filter { $0.groupID == group.id },
                            isCollapsed: collapsedBinding(group.id.uuidString),
                            onRename: {
                                groupPendingRename = group
                                renamedGroupName = group.name
                            },
                            onDelete: { groupPendingDeletion = group },
                            hostRow: hostRow
                        )
                    }

                    if !ungroupedHosts.isEmpty {
                        SidebarSection(
                            title: "未分组",
                            icon: "tray",
                            sectionID: "ungrouped",
                            hosts: ungroupedHosts,
                            isCollapsed: collapsedBinding("ungrouped"),
                            hostRow: hostRow
                        )
                    }
                }
                .padding(.horizontal, 8)
                .padding(.top, 10)
                .padding(.bottom, 8)
            }
        }
        .liquidGlassPanel(enabled: appearance.usesControlGlassEffects, cornerRadius: 16)
    }

    private func workspace(for tab: WorkspaceTab, isTabActive: Bool) -> some View {
        let selection = Binding<SSHHost.ID?>(
            get: { tab.host.id },
            set: { if $0 == nil { closeTab(tab.id) } }
        )

        return TerminalWorkspaceView(
            workspace: tab.workspace,
            hosts: hostStore.hosts,
            showsHostStatus: hostStatusVisible,
            hostStatusOccupiesSpace: hostStatusOccupiesSpace,
            isWindowFocused: allowsTerminalOutputInteractivity,
            isTabActive: isTabActive,
            onAuthenticated: handleAuthenticated,
            onNewTab: { host in
                createTab(host)
            },
            selectedHostID: selection
        )
        .id(tab.id)
    }


    private var importExportMenu: some View {
        Menu {
            Button("新建 SSH 主机", systemImage: "server.rack") {
                newHostTemplate = SSHHost()
                hostStore.isPresentingNewHost = true
            }
            Button("新建分组", systemImage: "folder.badge.plus") {
                isCreatingGroup = true
            }
            Divider()
            Button("导入 ~/.ssh/config", systemImage: "square.and.arrow.down") {
                hostStore.importDefaultSSHConfig()
            }
            Divider()
            Button("导入主机备份…", systemImage: "square.and.arrow.down.on.square") {
                hostStore.importBackup()
            }
            Button("导出主机备份…", systemImage: "square.and.arrow.up.on.square") {
                hostStore.exportBackup()
            }
        } label: {
            Image(systemName: "ellipsis")
        }
        .menuIndicator(.hidden)
        .help(Text("更多操作"))
    }

    @ViewBuilder
    private func hostRow(_ host: SSHHost) -> some View {
        let activeTab = tabs.first { $0.host.id == host.id }
        let isTabOpen = activeTab != nil
        let session = activeTab?.session
        let isCurrentActive = activeTabID == activeTab?.id

        SidebarHostRow(
            host: host,
            isOpen: isTabOpen && isCurrentActive,
            isSelected: selectedSidebarHostID == host.id,
            session: session,
            isTabOpen: isTabOpen
        )
            .contentShape(Rectangle())
            .onTapGesture(count: 2) { openHost(host) }
            .onTapGesture { selectedSidebarHostID = host.id }
            .contextMenu {
                Button(host.isFavorite ? "取消收藏" : "加入收藏",
                       systemImage: host.isFavorite ? "star.slash" : "star") {
                    hostStore.toggleFavorite(host)
                }
                Menu("移动到分组", systemImage: "folder") {
                    Button("未分组") { hostStore.move(host, to: nil) }
                    ForEach(hostStore.groups) { group in
                        Button(group.name) { hostStore.move(host, to: group.id) }
                    }
                }
                Menu("颜色标签", systemImage: "tag") {
                    ColorTagMenu(selection: host.colorTag) {
                        hostStore.setColorTag($0, for: host)
                    }
                }
                Button("编辑", systemImage: "pencil") { editingHost = host }
                if !host.isLocal {
                    Button("优化服务器环境", systemImage: "wand.and.stars") {
                        self.hostToOptimize = host
                    }
                }
                Divider()
                Button("删除", systemImage: "trash", role: .destructive) {
                    hostPendingDeletion = host
                }
            }
    }

    private func collapsedBinding(_ id: String) -> Binding<Bool> {
        Binding(
            get: { collapsedSections.contains(id) },
            set: { collapsed in
                if collapsed { collapsedSections.insert(id) }
                else { collapsedSections.remove(id) }
            }
        )
    }

    private func openHost(_ host: SSHHost) {
        createTab(host)
    }

    private func createTab(_ host: SSHHost) {
        prepareForNewTabInteraction()
        let tab = WorkspaceTab(host: host)
        let insertionIndex = activeTabID
            .flatMap { id in tabs.firstIndex(where: { $0.id == id }) }
            .map { $0 + 1 } ?? tabs.count
        tabs.insert(tab, at: insertionIndex)
        activeTabID = tab.id
        updateTerminalOutputInteractivity()
    }

    private func prepareForNewTabInteraction() {
        tabs.forEach { tab in
            tab.workspace.deferTerminalOutputForUserInteraction(seconds: 6.0)
        }
    }

    private func handleAuthenticated(_ session: SSHSession) {
        let host = hostStore.hosts.first(where: { $0.id == session.host.id }) ?? session.host
        guard !host.isLocal,
              !host.hasPromptedOptimization,
              host.identityFile.isEmpty,
              hostToOptimize == nil else { return }
        hostToOptimize = host
    }

    private func createLocalTab() {
        createTab(.localTerminal)
    }

    private func closeTab(_ id: WorkspaceTab.ID) {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        let tab = tabs[index]
        tab.disconnect()
        tabs.remove(at: index)
        if activeTabID == id {
            activeTabID = tabs.indices.contains(index) ? tabs[index].id : tabs.last?.id
        }
        updateTerminalOutputInteractivity()
    }

    private func closeTabsToLeft(of id: WorkspaceTab.ID) {
        guard let index = tabs.firstIndex(where: { $0.id == id }), index > 0 else { return }
        closeTabs(Array(tabs[..<index]).map(\.id), preferredActiveTabID: id)
    }

    private func closeTabsToRight(of id: WorkspaceTab.ID) {
        guard let index = tabs.firstIndex(where: { $0.id == id }), index + 1 < tabs.count else { return }
        closeTabs(Array(tabs[(index + 1)...]).map(\.id), preferredActiveTabID: id)
    }

    private func closeOtherTabs(keeping id: WorkspaceTab.ID) {
        closeTabs(tabs.filter { $0.id != id }.map(\.id), preferredActiveTabID: id)
    }

    private func closeAllTabs() {
        closeTabs(tabs.map(\.id), preferredActiveTabID: nil)
    }

    private func closeTabs(_ ids: [WorkspaceTab.ID], preferredActiveTabID: WorkspaceTab.ID?) {
        guard !ids.isEmpty else { return }
        let idSet = Set(ids)
        tabs.filter { idSet.contains($0.id) }.forEach { $0.disconnect() }
        tabs.removeAll { idSet.contains($0.id) }

        if let preferredActiveTabID, tabs.contains(where: { $0.id == preferredActiveTabID }) {
            activeTabID = preferredActiveTabID
        } else if let current = activeTabID, tabs.contains(where: { $0.id == current }) {
            activeTabID = current
        } else {
            activeTabID = tabs.last?.id
        }
        updateTerminalOutputInteractivity()
    }

    private func updateTerminalOutputInteractivity() {
        let canInteract = allowsTerminalOutputInteractivity
        tabs.forEach { tab in
            tab.workspace.setTerminalOutputInteractive(isActiveTab: canInteract && tab.id == activeTabID)
        }
    }

    private func setAllTerminalOutputInteractive(_ isInteractive: Bool) {
        tabs.forEach { tab in
            tab.workspace.setTerminalOutputInteractive(
                isActiveTab: isInteractive && allowsTerminalOutputInteractivity && tab.id == activeTabID
            )
        }
    }
    
    private func runOptimization(_ host: SSHHost) {
        var updated = host
        updated.hasPromptedOptimization = true
        hostStore.update(updated)
        
        // Reuse the password already unlocked for this authenticated session.
        let cachedPassword = tabs
            .flatMap { $0.workspace.root.panes }
            .first(where: { $0.host.id == host.id })?
            .session.cachedPassword

        Task {
            let password: String?
            if let cachedPassword {
                password = cachedPassword
            } else if host.savesPassword {
                let hostID = host.id
                password = await Task.detached(priority: .userInitiated) {
                    KeychainStore.password(for: hostID)
                }.value
            } else {
                password = nil
            }

            ServerOptimizer.shared.optimize(host: host, password: password) { success, error in
                if success {
                    // If it succeeded, update the identity file to ~/.ssh/id_rsa since it now exists
                    var finalHost = hostStore.hosts.first(where: { $0.id == host.id }) ?? updated
                    finalHost.identityFile = "~/.ssh/id_rsa"
                    finalHost.savesPassword = false
                    hostStore.update(finalHost)
                    KeychainStore.delete(for: host.id)
                } else if let error {
                    self.optimizationError = error
                }
            }
        }
    }
}



private struct SearchField: View {
    @Binding var text: String

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("搜索主机", text: $text)
                .textFieldStyle(.plain)
            if !text.isEmpty {
                Button { text = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 9)
        .frame(height: 30)
        .glassEffect(.regular.interactive(), in: Capsule())
    }
}

private struct SidebarCollapseButton: View {
    let isCollapsed: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: isCollapsed ? "rectangle.expand.vertical" : "rectangle.compress.vertical")
                .frame(width: 30, height: 30)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: Circle())
        .help(isCollapsed ? "展开所有分组" : "折叠所有分组")
    }
}



private struct SidebarSection<Row: View>: View {
    let title: String
    let icon: String
    let sectionID: String
    let hosts: [SSHHost]
    @Binding var isCollapsed: Bool
    var onRename: (() -> Void)?
    var onDelete: (() -> Void)?
    let hostRow: (SSHHost) -> Row
    @State private var isHovering = false
    @ObservedObject private var appearance = AppearanceSettings.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                    .font(.system(size: 9, weight: .bold))
                    .frame(width: 12)
                Image(systemName: icon)
                    .font(.system(size: 13))
                    .foregroundStyle(Color.secondary)
                Text(LocalizedStringKey(title))
                    .font(.system(size: 13, weight: .bold))
                    .lineLimit(1)
                Spacer(minLength: 0)
                Text("\(hosts.count)")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()
            }
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity)
            .frame(height: 36)
            .background {
                let shape = RoundedRectangle(cornerRadius: 9, style: .continuous)
                shape
                    .fill(Color.secondary.opacity(isHovering ? 0.12 : 0.035))
                    .conditionalGlassEffect(enabled: appearance.usesControlGlassEffects, shape: shape)
            }
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                    isCollapsed.toggle()
                }
            }
            .onHover { hovering in
                withAnimation(.easeInOut(duration: 0.12)) {
                    isHovering = hovering
                }
            }
            .foregroundStyle(.secondary)
            .contextMenu {
                if let onRename {
                    Button("重命名分组", systemImage: "pencil", action: onRename)
                }
                if let onDelete {
                    Button("删除分组", systemImage: "trash", role: .destructive, action: onDelete)
                }
            }

            if !isCollapsed {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(hosts) { host in
                        hostRow(host)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(.top, 3)
                .padding(.bottom, 3)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.horizontal, 4)
        .padding(.top, 4)
        .padding(.bottom, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .liquidGlassPanel(enabled: appearance.usesControlGlassEffects, cornerRadius: 12)
    }
}


private enum HostConnectionStatus {
    case unconnected
    case connected
    case connecting
    case interrupted
    case unreachable

    var color: Color {
        switch self {
        case .unconnected: return Color.secondary.opacity(0.45)
        case .connected: return Color.green
        case .connecting: return Color.yellow.opacity(0.7)
        case .interrupted: return Color.red
        case .unreachable: return Color.yellow
        }
    }
}

private extension SSHSession {
    var connectionStatus: HostConnectionStatus {
        if isConnected {
            return .connected
        }
        if isConnecting {
            return .connecting
        }
        guard exitStatus != nil || errorMessage != nil else {
            return .unconnected
        }

        let failureText = "\(output)\n\(errorMessage ?? "")".lowercased()
        let unreachableMarkers = [
            "permission denied",
            "connection refused",
            "connection timed out",
            "operation timed out",
            "no route to host",
            "could not resolve hostname",
            "host is down",
            "network is unreachable"
        ]
        return unreachableMarkers.contains(where: failureText.contains) ? .unreachable : .interrupted
    }
}

private struct ConnectionStatusDot: View {
    @ObservedObject var session: SSHSession
    let isTabOpen: Bool

    private var connectionStatus: HostConnectionStatus {
        isTabOpen ? session.connectionStatus : .unconnected
    }

    var body: some View {
        Circle()
            .fill(connectionStatus.color)
            .frame(width: 8, height: 8)
    }
}

private struct SidebarHostRow: View {
    let host: SSHHost
    let isOpen: Bool
    let isSelected: Bool
    let session: SSHSession?
    let isTabOpen: Bool
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 8) {
            if isTabOpen, let session {
                ConnectionStatusDot(session: session, isTabOpen: isTabOpen)
            } else {
                Circle()
                    .fill(HostConnectionStatus.unconnected.color)
                    .frame(width: 8, height: 8)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(host.name)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(isOpen ? Color.white : (host.colorTag != .none ? host.colorTag.color : Color.primary))
                    .lineLimit(1)
                Text(host.destination)
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(isOpen ? Color.white.opacity(0.8) : Color.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            if host.savesPassword {
                Image(systemName: "key.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(isOpen ? Color.white.opacity(0.7) : Color.secondary.opacity(0.5))
            }
        }
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: 40)
        .background {
            if isOpen {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(Color(nsColor: .selectedContentBackgroundColor))
            } else if isSelected {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(Color(nsColor: .selectedContentBackgroundColor).opacity(0.11))
            } else if isHovering {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(Color(nsColor: .selectedContentBackgroundColor).opacity(0.15))
            }
        }
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.12)) {
                isHovering = hovering
            }
        }
    }
}

// MARK: - Safari-Style Tab Bar

private struct ToolbarIconLabel: View {
    let systemName: String
    var size: CGFloat = 14
    var weight: Font.Weight = .regular

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: size, weight: weight))
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(.primary)
            .frame(width: 16, height: 16, alignment: .center)
            .contentShape(Rectangle())
    }
}

private struct SystemMonitorToolbarWidget: View {
    let host: SSHHost
    @ObservedObject var session: SSHSession
    let isActive: Bool
    @StateObject private var provider: RemoteStatsProvider
    @ObservedObject private var appearance = AppearanceSettings.shared

    init(host: SSHHost, session: SSHSession, isActive: Bool) {
        self.host = host
        self.session = session
        self.isActive = isActive
        _provider = StateObject(
            wrappedValue: RemoteStatsProvider(
                host: host,
                pollingInterval: 2.0,
                controlPath: session.auxiliaryControlPath,
                collectionMode: .toolbar
            )
        )
    }

    var body: some View {
        HStack(spacing: 6) {
            SystemMonitorMetric(
                title: "CPU",
                systemName: "cpu",
                value: provider.stats?.cpuPercent,
                color: metricColor(provider.stats?.cpuPercent)
            )
            metricDivider
            SystemMonitorMetric(
                title: "MEM",
                systemName: "memorychip",
                value: provider.stats?.memoryPercent,
                color: metricColor(provider.stats?.memoryPercent)
            )
            metricDivider
            SystemMonitorMetric(
                title: "DSK",
                systemName: "internaldrive",
                value: diskPercent,
                color: metricColor(diskPercent)
            )
        }
        .padding(.horizontal, 9)
        .frame(height: 24)
        .fixedSize()
        .onAppear(perform: updatePolling)
        .onDisappear { provider.stop() }
        .onChange(of: isActive) { _, _ in updatePolling() }
        .onChange(of: session.isAuthenticated) { _, _ in updatePolling() }
        .help("\(host.name) System Usage")
    }

    private var metricDivider: some View {
        Rectangle()
            .fill(Color.secondary.opacity(0.18))
            .frame(width: 1, height: 11)
    }

    private var diskPercent: Double? {
        guard let stats = provider.stats else { return nil }
        return stats.disks.first(where: { $0.mountPoint == "/" })?.percent
            ?? stats.disks.max(by: { $0.percent < $1.percent })?.percent
    }

    private func metricColor(_ value: Double?) -> Color {
        guard let value else { return .secondary }
        if value >= 90 { return .red }
        if value >= 70 { return .orange }
        return .green
    }

    private func updatePolling() {
        if isActive && session.isAuthenticated {
            provider.start()
        } else {
            provider.stop()
        }
    }
}

private struct SystemMonitorToolbarPlaceholder: View {
    @ObservedObject private var appearance = AppearanceSettings.shared

    var body: some View {
        HStack(spacing: 6) {
            SystemMonitorMetric(title: "CPU", systemName: "cpu", value: nil, color: .secondary)
            metricDivider
            SystemMonitorMetric(title: "MEM", systemName: "memorychip", value: nil, color: .secondary)
            metricDivider
            SystemMonitorMetric(title: "DSK", systemName: "internaldrive", value: nil, color: .secondary)
        }
        .padding(.horizontal, 9)
        .frame(height: 24)
        .fixedSize()
        .help(Text("System Usage"))
    }

    private var metricDivider: some View {
        Rectangle()
            .fill(Color.secondary.opacity(0.18))
            .frame(width: 1, height: 11)
    }
}

private struct SystemMonitorMetric: View {
    let title: String
    let systemName: String
    let value: Double?
    let color: Color

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: systemName)
                .font(.system(size: 10, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(color)
                .frame(width: 11)

            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)

            Text(valueText)
                .font(.system(size: 10.5, weight: .bold, design: .monospaced))
                .foregroundStyle(value == nil ? Color.secondary : Color.primary)
                .monospacedDigit()
                .frame(minWidth: 26, alignment: .trailing)
        }
        .accessibilityLabel("\(title) \(valueText)")
    }

    private var valueText: String {
        guard let value else { return "--%" }
        return "\(Int(value.rounded()))%"
    }
}

private struct SafariStyleTabBar: View {
    let tabs: [WorkspaceTab]
    @Binding var activeTabID: WorkspaceTab.ID?
    let availableWidth: CGFloat
    let closeTab: (WorkspaceTab.ID) -> Void
    let closeTabsToLeft: (WorkspaceTab.ID) -> Void
    let closeTabsToRight: (WorkspaceTab.ID) -> Void
    let closeOtherTabs: (WorkspaceTab.ID) -> Void
    let closeAllTabs: () -> Void

    var body: some View {
        let count = CGFloat(tabs.count)
        let minTabWidth: CGFloat = 48
        let sidePadding: CGFloat = 0
        
        // 精确平分宽度，扣除左右边距(共 4pt)和所有分割线(count - 1 个，每个 1pt)
        let calculatedTabWidth = count > 0 ? (availableWidth - 2 * sidePadding - max(0, count - 1)) / count : availableWidth
        let isOverflowing = count > 0 && calculatedTabWidth < minTabWidth
        let singleTabWidth = isOverflowing ? minTabWidth : calculatedTabWidth
        let totalTabsWidth = count * singleTabWidth + 2 * sidePadding + max(0, count - 1)
        let tabBarWidth = tabs.isEmpty ? 0 : min(availableWidth, totalTabsWidth)

        Group {
            if tabs.isEmpty {
                Spacer().frame(width: 0, height: 0)
            } else {
                ScrollViewReader { proxy in
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 0) {
                            ForEach(Array(tabs.enumerated()), id: \.element.id) { index, tab in
                                if index > 0 {
                                    Spacer(minLength: 0)
                                        .frame(width: 1)
                                        .frame(height: 10)
                                        .background(Color.secondary.opacity(0.25))
                                        .opacity(activeTabID == tab.id || activeTabID == tabs[index - 1].id ? 0 : 1)
                                }
                                SafariTabItem(
                                    tab: tab,
                                    isMultiTab: tabs.count > 1,
                                    isActive: activeTabID == tab.id,
                                    tabWidth: singleTabWidth,
                                    activate: { activeTabID = tab.id },
                                    close: { closeTab(tab.id) },
                                    closeTabsToLeft: { closeTabsToLeft(tab.id) },
                                    closeTabsToRight: { closeTabsToRight(tab.id) },
                                    closeOtherTabs: { closeOtherTabs(tab.id) },
                                    closeAllTabs: closeAllTabs
                                )
                                .id(tab.id)
                            }
                        }
                        .padding(.horizontal, sidePadding)
                        .frame(height: 22)
                    }
                    .onChange(of: activeTabID) { _, newValue in
                        if let newValue {
                            if isOverflowing {
                                proxy.scrollTo(newValue, anchor: .center)
                            } else if let firstTab = tabs.first {
                                proxy.scrollTo(firstTab.id, anchor: .leading)
                            }
                        }
                    }
                    .onChange(of: tabs.count) { _, _ in
                        if !isOverflowing, let firstTab = tabs.first {
                            proxy.scrollTo(firstTab.id, anchor: .leading)
                        }
                    }
                    .onAppear {
                        if let activeTabID {
                            if isOverflowing {
                                proxy.scrollTo(activeTabID, anchor: .center)
                            } else if let firstTab = tabs.first {
                                proxy.scrollTo(firstTab.id, anchor: .leading)
                            }
                        }
                    }
                }
            }
        }
        .frame(width: tabBarWidth, height: 22)
        .clipped()
        .opacity(tabs.isEmpty ? 0 : 1)
    }
}

private struct SafariTabItem: View {
    let tab: WorkspaceTab
    @ObservedObject private var appearance = AppearanceSettings.shared
    let isMultiTab: Bool
    let isActive: Bool
    let tabWidth: CGFloat
    let activate: () -> Void
    let close: () -> Void
    let closeTabsToLeft: () -> Void
    let closeTabsToRight: () -> Void
    let closeOtherTabs: () -> Void
    let closeAllTabs: () -> Void
    @State private var isHovering = false

    init(
        tab: WorkspaceTab,
        isMultiTab: Bool,
        isActive: Bool,
        tabWidth: CGFloat,
        activate: @escaping () -> Void,
        close: @escaping () -> Void,
        closeTabsToLeft: @escaping () -> Void,
        closeTabsToRight: @escaping () -> Void,
        closeOtherTabs: @escaping () -> Void,
        closeAllTabs: @escaping () -> Void
    ) {
        self.tab = tab
        self.isMultiTab = isMultiTab
        self.isActive = isActive
        self.tabWidth = tabWidth
        self.activate = activate
        self.close = close
        self.closeTabsToLeft = closeTabsToLeft
        self.closeTabsToRight = closeTabsToRight
        self.closeOtherTabs = closeOtherTabs
        self.closeAllTabs = closeAllTabs
    }

    var body: some View {
        let showTitle = tabWidth > 75
        let isCompact = tabWidth <= 110
        let showIcon = (tabWidth > 45 || isActive) && !(isCompact && isHovering)
        let showCloseButton = isHovering
        let buttonWidth: CGFloat = 18

        ZStack {
            TabOutputActivityHalo(
                session: tab.session,
                isEnabled: isMultiTab && !isActive
            )
            .padding(.horizontal, 1)
            .padding(.vertical, 2)

            HStack(spacing: 0) {
                if showCloseButton {
                    Button(action: close) {
                        Image(systemName: "xmark")
                            .font(.system(size: 10.5, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 17, height: 17)
                            .background(isHovering ? Color.secondary.opacity(0.15) : Color.clear, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .frame(width: buttonWidth)
                } else {
                    Spacer().frame(width: buttonWidth)
                }

                Spacer(minLength: 0)

                HStack(spacing: 6) {
                    if showIcon {
                        TabActivityIcon(
                            systemName: tab.host.isLocal ? "laptopcomputer" : "terminal",
                            session: tab.session,
                            isLocal: tab.host.isLocal
                        )
                    }

                    if showTitle {
                        Text(tab.host.name)
                            .font(.system(size: 11, weight: isActive ? .bold : .medium))
                            .foregroundStyle(isActive ? Color.primary : Color.secondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                }

                Spacer(minLength: 0)

                Spacer().frame(width: buttonWidth)
            }
        }
        .padding(.horizontal, 6)
        .frame(width: tabWidth, height: 22)
        .background {
            let shape = RoundedRectangle(cornerRadius: RuiChromeRadii.inner, style: .continuous)
            if isActive {
                shape
                    .fill(
                        Color(nsColor: .controlBackgroundColor)
                            .opacity(appearance.usesLiquidGlassEffects ? appearance.translucentActiveTabOpacity : 1)
                    )
                    .conditionalGlassEffect(enabled: appearance.usesLiquidGlassEffects, shape: shape)
                    .shadow(color: .black.opacity(0.15), radius: 2, y: 1)
            } else if isHovering {
                shape
                    .fill(Color.secondary.opacity(appearance.usesLiquidGlassEffects ? appearance.translucentHoverOpacity : 0.08))
                    .conditionalGlassEffect(enabled: appearance.usesLiquidGlassEffects, shape: shape)
            }
        }
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.12)) { isHovering = hovering }
        }
        .onTapGesture(perform: activate)
        .contextMenu {
            Button("Close Tab", systemImage: "xmark") { close() }
            Divider()
            Button("Close Tabs to the Left", systemImage: "arrow.left.to.line") { closeTabsToLeft() }
            Button("Close Tabs to the Right", systemImage: "arrow.right.to.line") { closeTabsToRight() }
            Button("Close Other Tabs", systemImage: "rectangle.stack.badge.minus") { closeOtherTabs() }
            Button("Close All Tabs", systemImage: "xmark.circle", role: .destructive) { closeAllTabs() }
        }
    }
}

private struct TabActivityIcon: View {
    let systemName: String
    let isLocal: Bool
    @ObservedObject private var session: SSHSession

    init(systemName: String, session: SSHSession, isLocal: Bool) {
        self.systemName = systemName
        self.isLocal = isLocal
        _session = ObservedObject(wrappedValue: session)
    }

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(iconColor)
    }

    private var iconColor: Color {
        if isLocal {
            return .secondary
        }
        if session.isConnected {
            return .green
        }
        if session.isConnecting {
            return Color.yellow.opacity(0.75)
        }
        if session.exitStatus != nil || session.errorMessage != nil {
            return .red
        }
        return .secondary
    }
}

private struct TabOutputActivityHalo: View {
    @ObservedObject private var session: SSHSession
    let isEnabled: Bool
    @State private var isActive = false
    @State private var breathes = false
    @State private var stopTask: Task<Void, Never>?
    @State private var lastTriggerTime: TimeInterval = 0

    init(session: SSHSession, isEnabled: Bool) {
        _session = ObservedObject(wrappedValue: session)
        self.isEnabled = isEnabled
    }

    var body: some View {
        RoundedRectangle(cornerRadius: RuiChromeRadii.inner, style: .continuous)
            .fill(Color.green.opacity(breathes ? 0.28 : 0.12))
            .overlay {
                RoundedRectangle(cornerRadius: RuiChromeRadii.inner, style: .continuous)
                    .stroke(Color.green.opacity(breathes ? 1.0 : 0.50), lineWidth: 1.5)
            }
            .shadow(color: Color.green.opacity(breathes ? 0.75 : 0.32), radius: breathes ? 12 : 3)
            .scaleEffect(breathes ? 1.03 : 0.99)
            .opacity(isActive ? 1 : 0)
            .allowsHitTesting(false)
            .onChange(of: session.outputVersion) { oldValue, newValue in
                guard newValue != oldValue else { return }
                triggerOutputActivity()
            }
            .onChange(of: isEnabled) { _, enabled in
                if !enabled {
                    stopActivity()
                }
            }
            .onDisappear {
                stopTask?.cancel()
                stopTask = nil
            }
    }

    private func triggerOutputActivity() {
        guard isEnabled else { return }

        let now = Date().timeIntervalSinceReferenceDate
        lastTriggerTime = now

        if !isActive {
            withAnimation(.easeOut(duration: 0.12)) {
                isActive = true
            }
        }

        if !breathes {
            withAnimation(.easeInOut(duration: 0.85).repeatForever(autoreverses: true)) {
                breathes = true
            }
        }

        stopTask?.cancel()
        stopTask = Task {
            try? await Task.sleep(nanoseconds: 2_800_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard Date().timeIntervalSinceReferenceDate - lastTriggerTime >= 2.65 else { return }
                stopActivity()
            }
        }
    }

    private func stopActivity() {
        stopTask?.cancel()
        stopTask = nil
        withAnimation(.easeOut(duration: 0.18)) {
            isActive = false
            breathes = false
        }
    }
}


// MARK: - Tab Overview Grid

private struct TabOverviewGrid: View {
    let tabs: [WorkspaceTab]
    @Binding var activeTabID: WorkspaceTab.ID?
    @Binding var isShowingTabOverview: Bool
    let closeTab: (WorkspaceTab.ID) -> Void

    var body: some View {
        ZStack {
            // 隐藏的 ESC 退出快捷键
            Button("") {
                withAnimation(.easeInOut(duration: 0.15)) {
                    isShowingTabOverview = false
                }
            }
            .keyboardShortcut(.cancelAction)
            .buttonStyle(.plain)
            .frame(width: 0, height: 0)
            .opacity(0)

            ScrollView {
                let columns = [
                    GridItem(.adaptive(minimum: 220, maximum: 260), spacing: 20)
                ]
                
                LazyVGrid(columns: columns, spacing: 20) {
                    ForEach(tabs) { tab in
                        TabOverviewCard(
                            session: tab.session,
                            tab: tab,
                            isActive: activeTabID == tab.id,
                            onSelect: {
                                withAnimation(.easeInOut(duration: 0.15)) {
                                    activeTabID = tab.id
                                    isShowingTabOverview = false
                                }
                            },
                            onClose: {
                                closeTab(tab.id)
                            }
                        )
                    }
                }
                .padding(8)
            }
        }
    }
}

private struct TabOverviewCard: View {
    @ObservedObject var session: SSHSession
    @ObservedObject private var appearance = AppearanceSettings.shared
    let tab: WorkspaceTab
    let isActive: Bool
    let onSelect: () -> Void
    let onClose: () -> Void
    @State private var isHovering = false
    @State private var isHoveringClose = false

    private var terminalLines: [String] {
        let text = session.output
        if text.isEmpty {
            if session.isConnecting {
                return ["Connecting to \(tab.host.name)..."]
            } else if !session.isConnected {
                return ["Disconnected", "Click to reconnect"]
            } else {
                return ["Connecting..."]
            }
        }
        let lines = text.components(separatedBy: .newlines)
        return Array(lines.suffix(12))
    }

    var body: some View {
        VStack(spacing: 0) {
            // 微型 Titlebar
            HStack(spacing: 8) {
                // 模拟 macOS 窗口控制按钮 (红绿灯)
                HStack(spacing: 4) {
                    Circle().fill(Color.red.opacity(0.7)).frame(width: 6, height: 6)
                    Circle().fill(Color.yellow.opacity(0.7)).frame(width: 6, height: 6)
                    Circle().fill(Color.green.opacity(0.7)).frame(width: 6, height: 6)
                }
                .padding(.leading, 8)
                
                Spacer()
                
                // 标题（图标与名称）
                HStack(spacing: 4) {
                    Image(systemName: tab.host.isLocal ? "laptopcomputer" : "terminal")
                        .font(.system(size: 9))
                    Text(tab.host.name)
                        .font(.system(size: 10, weight: .medium))
                        .lineLimit(1)
                }
                .foregroundStyle(.primary.opacity(0.8))
                
                Spacer()
                
                // 卡片关闭按钮
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 6, weight: .bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 12, height: 12)
                        .background(isHoveringClose ? Color.secondary.opacity(0.15) : Color.clear, in: Circle())
                }
                .buttonStyle(.plain)
                .onHover { isHoveringClose = $0 }
                .padding(.trailing, 8)
                .opacity(isHovering ? 1 : 0.2)
            }
            .frame(height: 22)

            Divider()

            // 真实控制台内容展示
            GeometryReader { proxy in
                VStack(alignment: .leading, spacing: 1) {
                    ForEach(0..<terminalLines.count, id: \.self) { index in
                        Text(terminalLines[index])
                            .font(.system(size: 7.5, weight: .regular, design: .monospaced))
                            .foregroundStyle(Color.green.opacity(0.85))
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .frame(width: proxy.size.width, alignment: .leading)
                    }
                }
            }
            .padding(8)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .background(
                Color.black.opacity(
                    appearance.usesLiquidGlassEffects ? appearance.translucentTerminalPreviewOpacity : 0.85
                )
            )
            .clipped()
        }
        .frame(height: 140)
        .liquidGlassPanel(enabled: appearance.usesLiquidGlassEffects, cornerRadius: 10)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(isActive ? Color.accentColor : Color.secondary.opacity(0.15), lineWidth: isActive ? 1.5 : 1)
        )
        .contentShape(Rectangle())
        .scaleEffect(isHovering ? 1.03 : 1.0)
        .shadow(
            color: isActive ? Color.accentColor.opacity(isHovering ? 0.2 : 0.08) : Color.black.opacity(isHovering ? 0.22 : 0.06),
            radius: isHovering ? 8 : 3,
            y: isHovering ? 4 : 1.5
        )
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) { isHovering = hovering }
        }
        .onTapGesture(perform: onSelect)
    }
}

// MARK: - Host Picker Popover

struct HostPickerView: View {
    let hosts: [SSHHost]
    let showCancelButton: Bool
    let onSelect: (SSHHost) -> Void
    @ObservedObject private var appearance = AppearanceSettings.shared
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""

    private var filteredHosts: [SSHHost] {
        if searchText.isEmpty { return hosts }
        return hosts.filter {
            $0.name.localizedCaseInsensitiveContains(searchText) ||
            $0.hostname.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Select SSH Host")
                    .font(.headline)
                Spacer()
                if showCancelButton {
                    Button("Cancel") { dismiss() }
                        .buttonStyle(.glass)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 8)

            HStack(spacing: 7) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search hosts…", text: $searchText)
                    .textFieldStyle(.plain)
                if !searchText.isEmpty {
                    Button { searchText = "" } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .frame(height: 32)
            .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 8))
            .padding(.horizontal, 16)
            .padding(.bottom, 12)

            Divider()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    HostPickerRow(
                        icon: "laptopcomputer",
                        name: "Local Terminal",
                        detail: "macOS Shell",
                        color: .blue
                    ) {
                        onSelect(.localTerminal)
                        dismiss()
                    }

                    if !filteredHosts.isEmpty {
                        Divider().padding(.vertical, 4).padding(.horizontal, 12)

                        ForEach(filteredHosts) { host in
                            HostPickerRow(
                                icon: "server.rack",
                                name: host.name,
                                detail: host.destination,
                                color: host.colorTag != .none ? host.colorTag.color : .secondary
                            ) {
                                onSelect(host)
                                dismiss()
                            }
                        }
                    }
                }
                .padding(12)
            }
        }
        .liquidGlassPanel(enabled: appearance.usesLiquidGlassEffects, cornerRadius: 18)
    }
}

#if os(macOS)
private struct WindowKeyObserver: NSViewRepresentable {
    @Binding var isKeyWindow: Bool

    fileprivate func makeNSView(context: Context) -> WindowKeyTrackingView {
        let view = WindowKeyTrackingView()
        view.onKeyStateChanged = { isKey in
            if isKeyWindow != isKey {
                isKeyWindow = isKey
            }
        }
        return view
    }

    fileprivate func updateNSView(_ nsView: WindowKeyTrackingView, context: Context) {
        nsView.onKeyStateChanged = { isKey in
            if isKeyWindow != isKey {
                isKeyWindow = isKey
            }
        }
        nsView.refreshWindowBinding()
    }

    fileprivate final class WindowKeyTrackingView: NSView {
        var onKeyStateChanged: ((Bool) -> Void)?
        private weak var observedWindow: NSWindow?
        private var observers: [NSObjectProtocol] = []

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            refreshWindowBinding()
        }

        func refreshWindowBinding() {
            guard observedWindow !== window else {
                publish()
                return
            }

            observers.forEach(NotificationCenter.default.removeObserver)
            observers.removeAll()
            observedWindow = window

            if let window {
                let center = NotificationCenter.default
                observers.append(
                    center.addObserver(forName: NSWindow.didBecomeKeyNotification, object: window, queue: .main) { [weak self] _ in
                        self?.publish()
                    }
                )
                observers.append(
                    center.addObserver(forName: NSWindow.didResignKeyNotification, object: window, queue: .main) { [weak self] _ in
                        self?.publish()
                    }
                )
            }
            publish()
        }

        private func publish() {
            onKeyStateChanged?(window?.isKeyWindow ?? false)
        }

        deinit {
            observers.forEach(NotificationCenter.default.removeObserver)
        }
    }
}
#else
private struct WindowKeyObserver: View {
    @Binding var isKeyWindow: Bool

    var body: some View {
        Color.clear
            .onAppear { isKeyWindow = true }
    }
}
#endif

#if os(macOS)
private struct WindowToolbarConfigurator: NSViewRepresentable {
    fileprivate func makeNSView(context: Context) -> ToolbarConfigView {
        ToolbarConfigView()
    }

    fileprivate func updateNSView(_ nsView: ToolbarConfigView, context: Context) {
        nsView.scheduleConfigure()
    }

    fileprivate final class ToolbarConfigView: NSView {
        private var configureAttempts = 0

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            configureAttempts = 0
            scheduleConfigure()
        }

        func scheduleConfigure() {
            DispatchQueue.main.async { [weak self] in
                self?.configureToolbar()
            }
        }

        private func configureToolbar() {
            guard let window else { return }
            guard let toolbar = window.toolbar else {
                retryConfigureIfNeeded()
                return
            }

            toolbar.displayMode = .iconOnly
            toolbar.allowsUserCustomization = false
            toolbar.autosavesConfiguration = false
            toolbar.validateVisibleItems()

            // SwiftUI may attach the NSToolbar slightly after the titlebar view
            // exists. Clear AppKit's toolbar background menu without touching
            // SwiftUI tab item context menus.
            disableSystemToolbarMenus(in: window.contentView?.superview)
        }

        private func retryConfigureIfNeeded() {
            guard configureAttempts < 8 else { return }
            configureAttempts += 1
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                self?.configureToolbar()
            }
        }

        private func disableSystemToolbarMenus(in view: NSView?) {
            guard let view else { return }
            let className = String(describing: type(of: view))
            if className.contains("Toolbar") || className.contains("Titlebar") {
                view.menu = NSMenu()
            }
            view.subviews.forEach { disableSystemToolbarMenus(in: $0) }
        }
    }
}
#else
private struct WindowToolbarConfigurator: View {
    var body: some View { Color.clear }
}
#endif

#if os(macOS)
private struct ToolbarContextMenuInterceptor: NSViewRepresentable {
    let tabs: [WorkspaceTab]
    let activeTabID: WorkspaceTab.ID?
    let tabBarWidth: CGFloat
    let closeTab: (WorkspaceTab.ID) -> Void
    let closeTabsToLeft: (WorkspaceTab.ID) -> Void
    let closeTabsToRight: (WorkspaceTab.ID) -> Void
    let closeOtherTabs: (WorkspaceTab.ID) -> Void
    let closeAllTabs: () -> Void

    func makeNSView(context: Context) -> ToolbarContextMenuView {
        let view = ToolbarContextMenuView()
        updateNSView(view, context: context)
        return view
    }

    func updateNSView(_ nsView: ToolbarContextMenuView, context: Context) {
        nsView.update(
            tabs: tabs,
            activeTabID: activeTabID,
            tabBarWidth: tabBarWidth,
            closeTab: closeTab,
            closeTabsToLeft: closeTabsToLeft,
            closeTabsToRight: closeTabsToRight,
            closeOtherTabs: closeOtherTabs,
            closeAllTabs: closeAllTabs
        )
    }

    final class ToolbarContextMenuView: NSView {
        private var eventMonitor: Any?
        private var tabIDs: [WorkspaceTab.ID] = []
        private var activeTabID: WorkspaceTab.ID?
        private var tabBarWidth: CGFloat = 0
        private var closeTab: ((WorkspaceTab.ID) -> Void)?
        private var closeTabsToLeft: ((WorkspaceTab.ID) -> Void)?
        private var closeTabsToRight: ((WorkspaceTab.ID) -> Void)?
        private var closeOtherTabs: ((WorkspaceTab.ID) -> Void)?
        private var closeAllTabs: (() -> Void)?
        private var suppressToolbarRightClickUntil: TimeInterval = 0

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            installMonitorIfNeeded()
        }

        func update(
            tabs: [WorkspaceTab],
            activeTabID: WorkspaceTab.ID?,
            tabBarWidth: CGFloat,
            closeTab: @escaping (WorkspaceTab.ID) -> Void,
            closeTabsToLeft: @escaping (WorkspaceTab.ID) -> Void,
            closeTabsToRight: @escaping (WorkspaceTab.ID) -> Void,
            closeOtherTabs: @escaping (WorkspaceTab.ID) -> Void,
            closeAllTabs: @escaping () -> Void
        ) {
            self.tabIDs = tabs.map(\.id)
            self.activeTabID = activeTabID
            self.tabBarWidth = tabBarWidth
            self.closeTab = closeTab
            self.closeTabsToLeft = closeTabsToLeft
            self.closeTabsToRight = closeTabsToRight
            self.closeOtherTabs = closeOtherTabs
            self.closeAllTabs = closeAllTabs
            installMonitorIfNeeded()
        }

        private func installMonitorIfNeeded() {
            guard eventMonitor == nil else { return }
            eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.rightMouseDown, .rightMouseUp]) { [weak self] event in
                self?.handleRightMouseEvent(event) ?? event
            }
        }

        private func handleRightMouseEvent(_ event: NSEvent) -> NSEvent? {
            guard let window, event.window === window else { return event }
            let isToolbarClick = isInToolbarArea(event.locationInWindow, window: window)
            let shouldSuppressNativeMenu = Date().timeIntervalSinceReferenceDate < suppressToolbarRightClickUntil

            guard isToolbarClick || shouldSuppressNativeMenu else { return event }

            if event.type == .rightMouseDown {
                suppressToolbarRightClickUntil = Date().timeIntervalSinceReferenceDate + 0.5
            }

            return nil
        }

        private func isInToolbarArea(_ location: NSPoint, window: NSWindow) -> Bool {
            location.y >= window.contentLayoutRect.maxY - 2
        }

        private func tabID(at location: NSPoint, window: NSWindow) -> WorkspaceTab.ID? {
            guard !tabIDs.isEmpty else { return nil }

            let count = CGFloat(tabIDs.count)
            let sidePadding: CGFloat = 4
            let minTabWidth: CGFloat = 48
            let availableWidth = max(tabBarWidth, minTabWidth)
            let calculatedTabWidth = (availableWidth - 2 * sidePadding - max(0, count - 1)) / count
            let tabWidth = calculatedTabWidth < minTabWidth ? minTabWidth : calculatedTabWidth
            let totalTabsWidth = count * tabWidth + 2 * sidePadding + max(0, count - 1)
            let effectiveBarWidth = min(availableWidth, totalTabsWidth)
            let windowWidth = window.contentView?.bounds.width ?? window.frame.width
            let startX = (windowWidth - effectiveBarWidth) / 2
            let x = location.x - startX - sidePadding
            let paddedBounds: CGFloat = 14

            guard x >= -paddedBounds, x <= count * (tabWidth + 1) + paddedBounds else { return nil }

            let clampedX = min(max(x, 0), max(0, count * (tabWidth + 1) - 1))
            let index = min(tabIDs.count - 1, max(0, Int(floor(clampedX / (tabWidth + 1)))))
            return tabIDs[index]
        }

        private func showTabMenu(for tabID: WorkspaceTab.ID, at point: NSPoint) {
            let menu = NSMenu()

            menu.addItem(menuItem("Close Tab") { [weak self] in self?.closeTab?(tabID) })
            menu.addItem(.separator())
            menu.addItem(menuItem("Close Tabs to the Left") { [weak self] in self?.closeTabsToLeft?(tabID) })
            menu.addItem(menuItem("Close Tabs to the Right") { [weak self] in self?.closeTabsToRight?(tabID) })
            menu.addItem(menuItem("Close Other Tabs") { [weak self] in self?.closeOtherTabs?(tabID) })
            menu.addItem(menuItem("Close All Tabs") { [weak self] in self?.closeAllTabs?() })

            menu.popUp(positioning: nil, at: point, in: self)
        }

        private func menuItem(_ title: String, action: @escaping () -> Void) -> NSMenuItem {
            let item = NSMenuItem(title: title, action: #selector(runMenuAction(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = MenuAction(action)
            return item
        }

        @objc private func runMenuAction(_ sender: NSMenuItem) {
            guard let action = sender.representedObject as? MenuAction else { return }
            action.run()
        }

        deinit {
            if let eventMonitor {
                NSEvent.removeMonitor(eventMonitor)
            }
        }
    }

    private final class MenuAction {
        private let action: () -> Void

        init(_ action: @escaping () -> Void) {
            self.action = action
        }

        func run() {
            action()
        }
    }
}
#else
private struct ToolbarContextMenuInterceptor: View {
    var body: some View { Color.clear }
}
#endif

struct HostPickerRow: View {
    let icon: String
    let name: String
    let detail: String
    let color: Color
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .foregroundStyle(color)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 1) {
                    Text(name)
                        .font(.system(size: 13, weight: .medium))
                        .lineLimit(1)
                    Text(detail)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isHovering ? Color.accentColor.opacity(0.1) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }
}
