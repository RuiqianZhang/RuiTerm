import SwiftUI

enum SettingsTab: Hashable {
    case general
    case shortcuts
    case appearance
    case sync
}

struct SettingsView: View {
    @State private var selectedTab: SettingsTab? = .general
    @State private var searchText = ""
    @ObservedObject private var appearance = AppearanceSettings.shared
    
    private var filteredTabs: [SettingsTab] {
        let allTabs: [SettingsTab] = [.general, .shortcuts, .appearance, .sync]
        guard !searchText.isEmpty else { return allTabs }
        return allTabs.filter { tab in
            switch tab {
            case .general: return "General 通用".localizedCaseInsensitiveContains(searchText)
            case .shortcuts: return "Keyboard Shortcuts 快捷键 Terminal".localizedCaseInsensitiveContains(searchText)
            case .appearance: return "Appearance 外观 Color Theme".localizedCaseInsensitiveContains(searchText)
            case .sync: return "Sync 同步 Cloud".localizedCaseInsensitiveContains(searchText)
            }
        }
    }
    
    var body: some View {
        NavigationSplitView(columnVisibility: .constant(.all)) {
            List(selection: $selectedTab) {
                if filteredTabs.contains(.general) {
                    Label("通用", systemImage: "gearshape")
                        .tag(SettingsTab.general)
                }

                if filteredTabs.contains(.shortcuts) {
                    Label("快捷键", systemImage: "keyboard")
                        .tag(SettingsTab.shortcuts)
                }
                
                if filteredTabs.contains(.appearance) {
                    Label("外观", systemImage: "paintpalette")
                        .tag(SettingsTab.appearance)
                }
                
                if filteredTabs.contains(.sync) {
                    Label("同步", systemImage: "icloud")
                        .tag(SettingsTab.sync)
                }
            }
            .scrollContentBackground(.hidden)
            .searchable(text: $searchText, placement: .sidebar)
            .navigationTitle("设置")
            .navigationSplitViewColumnWidth(220)
            .toolbar(removing: .sidebarToggle)
        } detail: {
            Group {
                switch selectedTab {
                case .general:
                    GeneralSettingsView()
                case .shortcuts:
                    KeyboardShortcutsSettingsView()
                case .appearance:
                    AppearanceSettingsView()
                case .sync:
                    SyncSettingsView()
                case .none:
                    Text("从侧边栏选择一个类别")
                        .foregroundColor(.secondary)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(maxHeight: .infinity)
        }
        // Force exact window size to emulate macOS System Settings and prevent UserDefaults wide frame restoration
        .frame(width: 680, height: 580)
        .background {
            if appearance.usesLiquidGlassEffects {
                LiquidGlassBackdrop()
                    .ignoresSafeArea()
            }
        }
        .onAppear {
            selectedTab = .general
        }
    }
}

private struct SettingsControlRow<Control: View>: View {
    let title: LocalizedStringKey
    let control: Control
    var height: CGFloat = 42

    init(_ title: LocalizedStringKey, height: CGFloat = 42, @ViewBuilder control: () -> Control) {
        self.title = title
        self.height = height
        self.control = control()
    }

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            Text(title)
                .frame(maxWidth: .infinity, alignment: .leading)
            control
                .frame(alignment: .trailing)
        }
        .frame(height: height, alignment: .center)
    }
}

private struct SettingsCard<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        VStack(spacing: 0) {
            content
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.45))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct SettingsDivider: View {
    var body: some View {
        Divider()
            .padding(.leading, 0)
    }
}

private struct SettingsSection<Content: View, Footer: View>: View {
    let title: LocalizedStringKey
    let content: Content
    let footer: Footer?

    init(
        _ title: LocalizedStringKey,
        @ViewBuilder content: () -> Content,
        @ViewBuilder footer: () -> Footer
    ) {
        self.title = title
        self.content = content()
        self.footer = footer()
    }

    init(_ title: LocalizedStringKey, @ViewBuilder content: () -> Content) where Footer == EmptyView {
        self.title = title
        self.content = content()
        self.footer = nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
                .foregroundStyle(.primary)
            SettingsCard { content }
            if let footer {
                footer
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 14)
            }
        }
    }
}

// MARK: - Appearance Settings

struct AppearanceSettingsView: View {
    @ObservedObject private var appearance = AppearanceSettings.shared
    @State private var selectedPreset: TerminalThemePreset = .ruiTerm
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                SettingsSection("界面") {
                    SettingsControlRow("主题模式:") {
                        Picker("", selection: $appearance.appMode) {
                            ForEach(AppThemeMode.allCases) { mode in
                                Text(LocalizedStringKey(mode.rawValue)).tag(mode)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.segmented)
                        .fixedSize()
                    }
                    SettingsDivider()
                    SettingsControlRow("减少毛玻璃特效") {
                        Toggle("", isOn: $appearance.reduceLiquidGlassEffects)
                            .labelsHidden()
                            .toggleStyle(.switch)
                    }
                }
                footer: {
                    Text("禁用 RuiTerm 的自定义毛玻璃背景并使用简单的不透明材质以减少 GPU 负荷。这不会影响 macOS 的系统设置。")
                }
            
                SettingsSection("终端颜色") {
                    SettingsControlRow("加载预设:") {
                        Picker("", selection: $selectedPreset) {
                            ForEach(TerminalThemePreset.allCases) { preset in
                                Text(preset.rawValue).tag(preset)
                            }
                        }
                        .labelsHidden()
                        .fixedSize()
                    }
                    .onChange(of: selectedPreset) { _, preset in
                        appearance.applyPreset(preset)
                    }
                
                    SettingsDivider()
                    SettingsControlRow("背景:") {
                        ColorPicker("", selection: colorBinding(for: $appearance.backgroundHex))
                            .labelsHidden()
                    }
                    SettingsDivider()
                    SettingsControlRow("前景:") {
                        ColorPicker("", selection: colorBinding(for: $appearance.foregroundHex))
                            .labelsHidden()
                    }
                    SettingsDivider()
                    SettingsControlRow("光标颜色:") {
                        ColorPicker("", selection: colorBinding(for: $appearance.cursorHex))
                            .labelsHidden()
                    }
                }
            
                SettingsSection("排版与样式") {
                    SettingsControlRow("字体:") {
                        Picker("", selection: $appearance.fontName) {
                            Text("System Mono").tag("")
                            Text("Menlo").tag("Menlo")
                            Text("Monaco").tag("Monaco")
                            Text("Courier New").tag("Courier New")
                            Text("SF Mono").tag("SF Mono")
                            Text("Fira Code").tag("Fira Code")
                            Text("JetBrains Mono").tag("JetBrains Mono")
                            Text("Hack").tag("Hack")
                        }
                        .labelsHidden()
                        .fixedSize()
                    }
                
                    SettingsDivider()
                    SettingsControlRow("字号:") {
                        HStack(alignment: .center) {
                            Text("\(appearance.fontSize, specifier: "%.1f")")
                                .frame(width: 30, alignment: .trailing)
                            Stepper("", value: $appearance.fontSize, in: 9...36, step: 0.5)
                                .labelsHidden()
                                .padding(.trailing, 2)
                        }
                    }
                
                    SettingsDivider()
                    SettingsControlRow("光标形状:") {
                        Picker("", selection: $appearance.cursorStyle) {
                            ForEach(CursorStyle.allCases) { style in
                                Text(LocalizedStringKey(style.rawValue)).tag(style)
                            }
                        }
                        .labelsHidden()
                        .fixedSize()
                    }
                
                    SettingsDivider()
                    SettingsControlRow("回滚行数:") {
                        HStack(alignment: .center) {
                            Text("\(appearance.effectiveScrollbackLines)")
                                .frame(width: 60, alignment: .trailing)
                                .monospacedDigit()
                            Stepper(
                                "",
                                value: $appearance.scrollbackLines,
                                in: TerminalScrollbackLimits.minimum...TerminalScrollbackLimits.maximum,
                                step: 1000
                            )
                                .labelsHidden()
                                .padding(.trailing, 2)
                        }
                    }
                }
            
                SettingsSection("预览") {
                    themePreview
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 22)
        }
        .background(Color.clear)
        .navigationTitle("外观")
    }
    
    private func colorBinding(for hexString: Binding<String>) -> Binding<Color> {
        Binding(
            get: { Color(hex: hexString.wrappedValue) },
            set: { newColor in
                let nsColor = NSColor(newColor)
                hexString.wrappedValue = nsColor.hexString
            }
        )
    }
    
    private var themePreview: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Circle().fill(Color.red).frame(width: 10, height: 10)
                Circle().fill(Color.yellow).frame(width: 10, height: 10)
                Circle().fill(Color.green).frame(width: 10, height: 10)
                Spacer()
            }
            .padding(.bottom, 4)
            
            Text("user@localhost:~$ echo 'Hello RuiTerm'")
                .font(Font(appearance.font))
                .foregroundColor(Color(nsColor: appearance.foregroundColor))
            Text("Hello RuiTerm")
                .font(Font(appearance.font))
                .foregroundColor(Color(nsColor: appearance.foregroundColor))
            HStack(spacing: 2) {
                Text("user@localhost:~$ ")
                    .font(Font(appearance.font))
                    .foregroundColor(Color(nsColor: appearance.foregroundColor))
                
                cursorPreview
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            Color(nsColor: appearance.backgroundColor)
                .opacity(appearance.usesLiquidGlassEffects ? appearance.translucentThemePreviewOpacity : 1)
        )
        .liquidGlassPanel(enabled: appearance.usesLiquidGlassEffects, cornerRadius: 8)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
        )
    }
    
    @ViewBuilder
    private var cursorPreview: some View {
        let color = Color(nsColor: appearance.cursorColor)
        switch appearance.cursorStyle {
        case .block:
            Rectangle()
                .fill(color)
                .frame(width: 8, height: 14)
        case .bar:
            Rectangle()
                .fill(color)
                .frame(width: 2, height: 14)
        case .underline:
            VStack {
                Spacer()
                Rectangle()
                    .fill(color)
                    .frame(width: 8, height: 2)
            }
            .frame(width: 8, height: 14)
        }
    }
}

// MARK: - Sync Settings

struct SyncSettingsView: View {
    @ObservedObject private var syncSettings = SyncSettings.shared
    @EnvironmentObject var hostStore: HostStore
    @State private var isSyncing = false
    
    var body: some View {
        Form {
            Section {
                Picker("方式:", selection: $syncSettings.provider) {
                    ForEach(SyncProviderType.allCases) { provider in
                        Text(provider.rawValue).tag(provider)
                    }
                }
            } header: {
                Text("同步服务商")
            }
            
            if syncSettings.provider == .local {
                Section {
                    Text("选择 iCloud Drive、Dropbox 或 Google Drive 中的文件夹以自动同步设置。")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .padding(.bottom, 4)
                    
                    LabeledContent("本地路径:") {
                        HStack {
                            TextField("", text: .constant(syncSettings.localDirectoryPath.isEmpty ? "默认 (Application Support)" : syncSettings.localDirectoryPath))
                                .disabled(true)
                            
                            Button("选择...") {
                                let panel = NSOpenPanel()
                                panel.canChooseFiles = false
                                panel.canChooseDirectories = true
                                panel.canCreateDirectories = true
                                panel.prompt = "选择同步文件夹"
                                if panel.runModal() == .OK, let url = panel.url {
                                    syncSettings.localDirectoryPath = url.path
                                    Task { await hostStore.load() }
                                }
                            }
                        }
                    }
                    
                    if !syncSettings.localDirectoryPath.isEmpty {
                        LabeledContent("") {
                            Button("恢复默认") {
                                syncSettings.localDirectoryPath = ""
                                Task { await hostStore.load() }
                            }
                        }
                    }
                } header: {
                    Text("本地目录设置")
                }
            } else if syncSettings.provider == .s3 {
                Section {
                    TextField("服务端点:", text: $syncSettings.s3Endpoint)
                    TextField("区域:", text: $syncSettings.s3Region)
                    TextField("存储桶名称:", text: $syncSettings.s3Bucket)
                    SecureField("Access Key ID:", text: $syncSettings.s3AccessKey)
                    SecureField("Secret Access Key:", text: $syncSettings.s3SecretKey)
                } header: {
                    Text("Amazon S3 凭证")
                }
            }
            
            Section {
                Button {
                    Task {
                        isSyncing = true
                        await hostStore.load()
                        isSyncing = false
                    }
                } label: {
                    if isSyncing {
                        ProgressView().controlSize(.small)
                            .padding(.trailing, 4)
                    }
                    Text("立即同步")
                }
                .disabled(isSyncing)
                .buttonStyle(.borderedProminent)
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .navigationTitle("同步")
    }
    
// Cleaned up subviews since they are now embedded in the Form
}

struct GeneralSettingsView: View {
    @AppStorage("showHostStatus") private var showHostStatus = false
    @AppStorage("autoOpenLocalTerminal") private var autoOpenLocalTerminal = false
    @ObservedObject private var appearance = AppearanceSettings.shared
    @State private var showingRestartAlert = false
    
    var body: some View {
        Form {
            Section {
                Picker("语言", selection: $appearance.appLanguage) {
                    ForEach(AppLanguage.allCases) { language in
                        Text(language.displayName).tag(language)
                    }
                }
                .onChange(of: appearance.appLanguage) { _, newValue in
                    newValue.applyToUserDefaults()
                    showingRestartAlert = true
                }
            } header: {
                Text("语言")
            } footer: {
                Text("更改语言需要重启应用才能完全生效。")
            }
            .alert("需要重启", isPresented: $showingRestartAlert) {
                Button("确定", role: .cancel) { }
            } message: {
                Text("语言设置已更新，请重启 RuiTerm 以应用新的语言界面。")
            }

            Section {
                Toggle("显示主机状态监视器", isOn: $showHostStatus)
            } header: {
                Text("主机状态")
            } footer: {
                Text("连接成功后自动显示 CPU、内存和磁盘监控。")
            }
            
            Section {
                Toggle("启动时自动打开本地终端", isOn: $autoOpenLocalTerminal)
            } header: {
                Text("启动")
            } footer: {
                Text("应用启动时自动打开本地终端会话。")
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .navigationTitle("通用")
    }
}

struct KeyboardShortcutsSettingsView: View {
    @ObservedObject private var shortcuts = TerminalShortcutSettings.shared
    @State private var conflictMessage: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                ForEach(TerminalShortcutCategory.allCases) { category in
                    let actions = TerminalShortcutAction.allCases.filter { $0.category == category }
                    if !actions.isEmpty {
                        SettingsSection(LocalizedStringKey(category.rawValue)) {
                            ForEach(Array(actions.enumerated()), id: \.element) { index, action in
                                SettingsControlRow(LocalizedStringKey(action.title)) {
                                    TerminalShortcutRecorder(binding: shortcuts.binding(for: action)) { binding in
                                        if let conflict = shortcuts.setBinding(binding, for: action) {
                                            conflictMessage = String(
                                                format: NSLocalizedString("%@ 已分配给 %@。", comment: "Shortcut conflict"),
                                                binding.displayName,
                                                NSLocalizedString(conflict.title, comment: "Terminal shortcut action")
                                            )
                                        }
                                    }
                                    .frame(width: 110, height: 24)
                                }
                                if index < actions.count - 1 {
                                    SettingsDivider()
                                }
                            }
                        }
                    }
                }

                HStack {
                    Text("提示：点击任意快捷键按钮即可录制自定义组合键，按 Esc 取消。这些快捷键在终端获得焦点时有效。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("恢复默认快捷键") {
                        shortcuts.restoreDefaults()
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 22)
        }
        .navigationTitle("快捷键")
        .alert("快捷键冲突", isPresented: Binding(
            get: { conflictMessage != nil },
            set: { if !$0 { conflictMessage = nil } }
        )) {
            Button("确定", role: .cancel) { conflictMessage = nil }
        } message: {
            Text(conflictMessage ?? "")
        }
    }
}
