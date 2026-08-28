import SwiftUI

#if os(macOS)
private final class RuiTermAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        DispatchQueue.main.async {
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    func applicationShouldHandleReopen(
        _ sender: NSApplication,
        hasVisibleWindows flag: Bool
    ) -> Bool {
        if !flag {
            sender.windows.first?.makeKeyAndOrderFront(nil)
        }
        return true
    }
}
#endif

@main
struct RuiTermApp: App {
    #if os(macOS)
    @NSApplicationDelegateAdaptor(RuiTermAppDelegate.self) private var appDelegate
    #endif
    @StateObject private var hostStore = HostStore()
    @StateObject private var terminalCommands = TerminalCommandCenter.shared
    @StateObject private var sftpCommands = SFTPCommandCenter.shared
    @ObservedObject private var appearance = AppearanceSettings.shared

    init() {
        UserDefaults.standard.set("WhenScrolling", forKey: "AppleShowScrollBars")

    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(hostStore)
                .environment(\.locale, appearance.appLanguage.locale)
                .preferredColorScheme(appearance.appMode.colorScheme)
                .frame(minWidth: 1_050, minHeight: 620)
                .onAppear {
                    updateAppAppearance(appearance.appMode)
                }
                .onChange(of: appearance.appMode) { _, mode in updateAppAppearance(mode) }
                .onChange(of: appearance.reduceLiquidGlassEffects) { _, _ in
                    updateAppAppearance(appearance.appMode)
                }
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unifiedCompact)
        .commands {
            // Enable standard Find & Replace menu items (Cmd+F, Cmd+G, etc.)
            TextEditingCommands()
            
            CommandGroup(replacing: .newItem) {
                Button("新建主机") {
                    hostStore.isPresentingNewHost = true
                }
                .keyboardShortcut("n")
            }
            // Use standard Edit menu pasteboard group so Cmd+C/V/A follows responder chain
            // When terminal is focused → terminal handles it; when TextField is focused → TextField handles it
            CommandGroup(replacing: .pasteboard) {
                Button("复制") {
                    routePasteboardCommand(
                        #selector(NSText.copy(_:)),
                        terminal: terminalCommands.performCopy,
                        sftp: sftpCommands.performCopy
                    )
                }
                .keyboardShortcut("c")

                Button("剪切") {
                    routePasteboardCommand(
                        #selector(NSText.cut(_:)),
                        sftp: sftpCommands.performCut
                    )
                }
                .keyboardShortcut("x")
                
                Button("粘贴") {
                    routePasteboardCommand(
                        #selector(NSText.paste(_:)),
                        terminal: terminalCommands.performPaste,
                        sftp: sftpCommands.performPaste
                    )
                }
                .keyboardShortcut("v")
                
                Button("全选") {
                    routePasteboardCommand(
                        #selector(NSText.selectAll(_:)),
                        terminal: terminalCommands.performSelectAll,
                        sftp: sftpCommands.performSelectAll
                    )
                }
                .keyboardShortcut("a")
            }
            CommandMenu("终端") {
                Button("清空终端") {
                    terminalCommands.clearTerminal()
                }
                .keyboardShortcut("k")
                .disabled(!terminalCommands.isKeyResponder)

                Button("清屏") {
                    terminalCommands.sendClearScreen()
                }
                .keyboardShortcut("l")
                .disabled(!terminalCommands.isKeyResponder)

                Divider()

                Button("行首") {
                    terminalCommands.moveToBeginningOfLine()
                }
                .disabled(!terminalCommands.isKeyResponder)

                Button("行尾") {
                    terminalCommands.moveToEndOfLine()
                }
                .disabled(!terminalCommands.isKeyResponder)

                Button("向上翻页") {
                    terminalCommands.scrollPageUp()
                }
                .disabled(!terminalCommands.isKeyResponder)

                Button("向下翻页") {
                    terminalCommands.scrollPageDown()
                }
                .disabled(!terminalCommands.isKeyResponder)

                Divider()

                Button("滚动到顶部") {
                    terminalCommands.scrollToTop()
                }
                .keyboardShortcut(.upArrow, modifiers: .command)
                .disabled(!terminalCommands.isKeyResponder)

                Button("滚动到底部") {
                    terminalCommands.scrollToBottom()
                }
                .keyboardShortcut(.downArrow, modifiers: .command)
                .disabled(!terminalCommands.isKeyResponder)

                Divider()

                Button("增大字体") {
                    terminalCommands.increaseFontSize()
                }
                .keyboardShortcut("+")
                .disabled(!terminalCommands.isKeyResponder)

                Button("减小字体") {
                    terminalCommands.decreaseFontSize()
                }
                .keyboardShortcut("-")
                .disabled(!terminalCommands.isKeyResponder)

                Button("重置字体") {
                    terminalCommands.resetFontSize()
                }
                .keyboardShortcut("0")
                .disabled(!terminalCommands.isKeyResponder)
            }
        }
        
        #if os(macOS)
        Settings {
            SettingsView()
                .environmentObject(hostStore)
                .environment(\.locale, appearance.appLanguage.locale)
                .preferredColorScheme(appearance.appMode.colorScheme)
                .onAppear { updateAppAppearance(appearance.appMode) }
                .onChange(of: appearance.appMode) { _, mode in updateAppAppearance(mode) }
                .onChange(of: appearance.reduceLiquidGlassEffects) { _, _ in
                    updateAppAppearance(appearance.appMode)
                }
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unifiedCompact)
        .windowResizability(.contentSize)
        #endif
    }

    #if os(macOS)
    private func routePasteboardCommand(
        _ standardAction: Selector,
        terminal terminalAction: (() -> Void)? = nil,
        sftp sftpAction: (() -> Void)? = nil
    ) {
        // Native text controls (including the built-in file editor) always get
        // the first chance through the current key window's responder chain.
        if NSApp.sendAction(standardAction, to: nil, from: nil) {
            return
        }

        // Custom surfaces only receive the command when they are the active
        // command target inside the current key window.
        if terminalCommands.isKeyResponder {
            terminalAction?()
        } else if sftpCommands.isKeyResponder {
            sftpAction?()
        }
    }
    #endif
    
    private func updateAppAppearance(_ mode: AppThemeMode) {
        #if os(macOS)
        let windowAppearance: NSAppearance?
        let windowBackground: NSColor
        let usesTranslucency = appearance.isFullGlassMode

        switch mode {
        case .system, .glass:
            windowAppearance = nil
            windowBackground = usesTranslucency ? .clear : .windowBackgroundColor
        case .light:
            windowAppearance = NSAppearance(named: .aqua)
            windowBackground = usesTranslucency ? .clear : .white
        case .dark:
            windowAppearance = NSAppearance(named: .darkAqua)
            windowBackground = usesTranslucency ? .clear : NSColor(white: 0.08, alpha: 1.0)
        }

        NSApp.appearance = windowAppearance

        func applyAppearanceToWindows() {
            for window in NSApp.windows {
                window.appearance = windowAppearance
                window.isOpaque = !usesTranslucency
                window.backgroundColor = windowBackground
                window.titlebarAppearsTransparent = usesTranslucency
                window.contentView?.wantsLayer = true
                window.contentView?.layer?.backgroundColor = usesTranslucency
                    ? NSColor.clear.cgColor
                    : windowBackground.cgColor
                if let toolbar = window.toolbar {
                    toolbar.displayMode = .iconOnly
                    toolbar.allowsUserCustomization = false
                    toolbar.autosavesConfiguration = false
                    toolbar.validateVisibleItems()
                }
                window.contentView?.needsDisplay = true
            }
        }

        applyAppearanceToWindows()

        // Clearing an explicit app appearance takes effect after AppKit resolves
        // the inherited system appearance. Refresh SwiftUI once that has happened.
        if windowAppearance == nil {
            DispatchQueue.main.async {
                applyAppearanceToWindows()
                appearance.objectWillChange.send()
            }
        }
        #endif
    }
}
