import AppKit
import Foundation
import SwiftUI

/// Categories for grouping terminal shortcuts in Settings
enum TerminalShortcutCategory: String, CaseIterable, Identifiable {
    case navigation = "光标与导航"
    case editing = "命令行编辑"
    case screen = "屏幕与排版"
    case tabAndSplit = "标签页与分屏"
    case clipboard = "剪贴板与选择"

    var id: String { rawValue }
}

/// Terminal navigation actions that can be assigned to application-level shortcuts.
/// Custom bindings are evaluated only while the terminal view is the active responder.
enum TerminalShortcutAction: String, CaseIterable, Identifiable {
    // 光标与导航
    case beginningOfLine
    case endOfLine
    case wordLeft
    case wordRight
    case pageUp
    case pageDown
    case scrollToTop
    case scrollToBottom

    // 命令行编辑
    case deleteToBeginningOfLine
    case deleteWordBackward
    case clearScreen

    // 屏幕与排版
    case increaseFontSize
    case decreaseFontSize
    case resetFontSize

    // 标签页与分屏
    case newTab
    case splitRight
    case splitDown
    case closePane

    // 剪贴板与选择
    case copy
    case paste
    case selectAll
    case find

    var id: String { rawValue }

    var category: TerminalShortcutCategory {
        switch self {
        case .beginningOfLine, .endOfLine, .wordLeft, .wordRight, .pageUp, .pageDown, .scrollToTop, .scrollToBottom:
            return .navigation
        case .deleteToBeginningOfLine, .deleteWordBackward, .clearScreen:
            return .editing
        case .increaseFontSize, .decreaseFontSize, .resetFontSize:
            return .screen
        case .newTab, .splitRight, .splitDown, .closePane:
            return .tabAndSplit
        case .copy, .paste, .selectAll, .find:
            return .clipboard
        }
    }

    var title: String {
        switch self {
        case .beginningOfLine: return "跳转至行首"
        case .endOfLine: return "跳转至行尾"
        case .wordLeft: return "向前跳跃一个单词"
        case .wordRight: return "向后跳跃一个单词"
        case .pageUp: return "向上翻一页"
        case .pageDown: return "向下翻一页"
        case .scrollToTop: return "滚动到最顶部（页首）"
        case .scrollToBottom: return "滚动到最底部（页尾）"
        case .deleteToBeginningOfLine: return "删除至行首 / 清空行"
        case .deleteWordBackward: return "向左删除一个单词"
        case .clearScreen: return "清屏"
        case .increaseFontSize: return "放大终端字号"
        case .decreaseFontSize: return "缩小终端字号"
        case .resetFontSize: return "重置终端字号"
        case .newTab: return "新建标签页并复制会话"
        case .splitRight: return "向右分屏并复制会话"
        case .splitDown: return "向下分屏并复制会话"
        case .closePane: return "关闭当前分屏或标签页"
        case .copy: return "复制选中内容"
        case .paste: return "粘贴剪贴板"
        case .selectAll: return "全选终端内容"
        case .find: return "在终端中查找"
        }
    }

    fileprivate var storageKey: String {
        "terminalShortcut.v5.\(rawValue)"
    }

    fileprivate var defaultBinding: TerminalKeyBinding {
        switch self {
        case .beginningOfLine:
            return TerminalKeyBinding(keyCode: 123, modifiers: [.command]) // ⌘←
        case .endOfLine:
            return TerminalKeyBinding(keyCode: 124, modifiers: [.command]) // ⌘→
        case .wordLeft:
            return TerminalKeyBinding(keyCode: 123, modifiers: [.option]) // ⌥←
        case .wordRight:
            return TerminalKeyBinding(keyCode: 124, modifiers: [.option]) // ⌥→
        case .pageUp:
            return TerminalKeyBinding(keyCode: 116, modifiers: []) // Page Up
        case .pageDown:
            return TerminalKeyBinding(keyCode: 121, modifiers: []) // Page Down
        case .scrollToTop:
            return TerminalKeyBinding(keyCode: 126, modifiers: [.command]) // ⌘↑
        case .scrollToBottom:
            return TerminalKeyBinding(keyCode: 125, modifiers: [.command]) // ⌘↓
        case .deleteToBeginningOfLine:
            return TerminalKeyBinding(keyCode: 51, modifiers: [.command]) // ⌘⌫
        case .deleteWordBackward:
            return TerminalKeyBinding(keyCode: 51, modifiers: [.option]) // ⌥⌫
        case .clearScreen:
            return TerminalKeyBinding(keyCode: 40, modifiers: [.command]) // ⌘K
        case .increaseFontSize:
            return TerminalKeyBinding(keyCode: 24, modifiers: [.command]) // ⌘+
        case .decreaseFontSize:
            return TerminalKeyBinding(keyCode: 27, modifiers: [.command]) // ⌘-
        case .resetFontSize:
            return TerminalKeyBinding(keyCode: 29, modifiers: [.command]) // ⌘0
        case .newTab:
            return TerminalKeyBinding(keyCode: 17, modifiers: [.command]) // ⌘T
        case .splitRight:
            return TerminalKeyBinding(keyCode: 2, modifiers: [.command]) // ⌘D
        case .splitDown:
            return TerminalKeyBinding(keyCode: 2, modifiers: [.command, .shift]) // ⌘⇧D
        case .closePane:
            return TerminalKeyBinding(keyCode: 13, modifiers: [.command]) // ⌘W
        case .copy:
            return TerminalKeyBinding(keyCode: 8, modifiers: [.command]) // ⌘C
        case .paste:
            return TerminalKeyBinding(keyCode: 9, modifiers: [.command]) // ⌘V
        case .selectAll:
            return TerminalKeyBinding(keyCode: 0, modifiers: [.command]) // ⌘A
        case .find:
            return TerminalKeyBinding(keyCode: 3, modifiers: [.command]) // ⌘F
        }
    }
}

/// A persisted hardware-key shortcut. Using key codes keeps bindings stable when
/// the user changes keyboard layout, which matches how macOS application shortcuts work.
struct TerminalKeyBinding: Hashable {
    let keyCode: UInt16
    private let modifiersRawValue: UInt

    private static let supportedModifiers: NSEvent.ModifierFlags = [
        .command, .option, .control, .shift
    ]

    init(keyCode: UInt16, modifiers: NSEvent.ModifierFlags) {
        self.keyCode = keyCode
        self.modifiersRawValue = Self.normalizedModifiers(modifiers)
    }

    init?(serializedValue: String) {
        let parts = serializedValue.split(separator: ":", maxSplits: 1)
        guard parts.count == 2,
              let keyCode = UInt16(parts[0]),
              let modifiers = UInt(parts[1]) else {
            return nil
        }
        self.keyCode = keyCode
        self.modifiersRawValue = modifiers
    }

    static func capture(from event: NSEvent) -> TerminalKeyBinding? {
        let modifiers = normalizedModifiers(event.modifierFlags)
        let flags = NSEvent.ModifierFlags(rawValue: modifiers)
        let isSpecialNavKey = event.keyCode == 116 || event.keyCode == 121 ||
                              event.keyCode == 115 || event.keyCode == 119
        guard flags.contains(.command) || flags.contains(.option) || flags.contains(.control) || isSpecialNavKey else {
            return nil
        }
        return TerminalKeyBinding(
            keyCode: event.keyCode,
            modifiers: flags
        )
    }

    var serializedValue: String {
        "\(keyCode):\(modifiersRawValue)"
    }

    func matches(_ event: NSEvent) -> Bool {
        let eventMods = Self.normalizedModifiers(event.modifierFlags)
        return keyCode == event.keyCode && modifiersRawValue == eventMods
    }

    var displayName: String {
        var modifiers = ""
        let flags = NSEvent.ModifierFlags(rawValue: modifiersRawValue)
        if flags.contains(.control) { modifiers += "⌃" }
        if flags.contains(.option) { modifiers += "⌥" }
        if flags.contains(.shift) { modifiers += "⇧" }
        if flags.contains(.command) { modifiers += "⌘" }
        return modifiers + Self.keyName(for: keyCode)
    }

    private static func normalizedModifiers(_ flags: NSEvent.ModifierFlags) -> UInt {
        flags.intersection(supportedModifiers).rawValue
    }

    private static func keyName(for keyCode: UInt16) -> String {
        switch keyCode {
        case 123: return "←"
        case 124: return "→"
        case 125: return "↓"
        case 126: return "↑"
        case 115: return "Home"
        case 119: return "End"
        case 116: return "Page Up"
        case 121: return "Page Down"
        case 36: return "↩"
        case 48: return "⇥"
        case 51: return "⌫"
        case 117: return "⌦"
        case 53: return "⎋"
        default:
            return ansiKeyNames[keyCode] ?? "Key \(keyCode)"
        }
    }

    private static let ansiKeyNames: [UInt16: String] = [
        0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X",
        8: "C", 9: "V", 11: "B", 12: "Q", 13: "W", 14: "E", 15: "R",
        16: "Y", 17: "T", 18: "1", 19: "2", 20: "3", 21: "4", 22: "6",
        23: "5", 24: "=", 25: "9", 26: "7", 27: "-", 28: "8", 29: "0",
        30: "]", 31: "O", 32: "U", 33: "[", 34: "I", 35: "P", 37: "L",
        38: "J", 39: "'", 40: "K", 41: ";", 42: "\\", 43: ",", 44: "/",
        45: "N", 46: "M", 47: ".", 49: "Space", 50: "`"
    ]
}

@MainActor
final class TerminalShortcutSettings: ObservableObject {
    static let shared = TerminalShortcutSettings()

    /// Forces SwiftUI shortcut controls to refresh after UserDefaults changes.
    @Published private(set) var revision = 0

    private init() {}

    func binding(for action: TerminalShortcutAction) -> TerminalKeyBinding {
        guard let rawValue = UserDefaults.standard.string(forKey: action.storageKey),
              let binding = TerminalKeyBinding(serializedValue: rawValue) else {
            return action.defaultBinding
        }
        return binding
    }

    func action(matching event: NSEvent) -> TerminalShortcutAction? {
        TerminalShortcutAction.allCases.first { binding(for: $0).matches(event) }
    }

    /// Returns the conflicting action when an assignment would be ambiguous.
    @discardableResult
    func setBinding(_ binding: TerminalKeyBinding, for action: TerminalShortcutAction) -> TerminalShortcutAction? {
        if let conflict = TerminalShortcutAction.allCases.first(where: {
            $0 != action && self.binding(for: $0) == binding
        }) {
            return conflict
        }

        UserDefaults.standard.set(binding.serializedValue, forKey: action.storageKey)
        revision &+= 1
        return nil
    }

    func restoreDefaults() {
        for action in TerminalShortcutAction.allCases {
            UserDefaults.standard.removeObject(forKey: action.storageKey)
        }
        revision &+= 1
    }
}

struct TerminalShortcutRecorder: NSViewRepresentable {
    let binding: TerminalKeyBinding
    let onRecord: (TerminalKeyBinding) -> Void

    func makeNSView(context: Context) -> TerminalShortcutRecorderButton {
        let button = TerminalShortcutRecorderButton(frame: .zero)
        button.shortcut = binding
        button.onRecord = onRecord
        return button
    }

    func updateNSView(_ button: TerminalShortcutRecorderButton, context: Context) {
        button.shortcut = binding
        button.onRecord = onRecord
    }
}

final class TerminalShortcutRecorderButton: NSButton {
    var shortcut = TerminalKeyBinding(keyCode: 123, modifiers: [.command]) {
        didSet { updateTitle() }
    }
    var onRecord: ((TerminalKeyBinding) -> Void)?

    private var isRecording = false {
        didSet { updateTitle() }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        bezelStyle = .rounded
        controlSize = .small
        focusRingType = .default
        setButtonType(.momentaryPushIn)
        target = self
        action = #selector(beginRecording)
        updateTitle()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        bezelStyle = .rounded
        controlSize = .small
        focusRingType = .default
        setButtonType(.momentaryPushIn)
        target = self
        action = #selector(beginRecording)
        updateTitle()
    }

    override var acceptsFirstResponder: Bool { true }

    @objc private func beginRecording() {
        isRecording = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.window?.makeFirstResponder(self)
        }
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard isRecording else { return super.performKeyEquivalent(with: event) }
        return capture(event)
    }

    override func keyDown(with event: NSEvent) {
        guard isRecording else {
            super.keyDown(with: event)
            return
        }
        _ = capture(event)
    }

    private func capture(_ event: NSEvent) -> Bool {
        if event.keyCode == 53 { // Escape cancels recording.
            isRecording = false
            return true
        }
        guard let binding = TerminalKeyBinding.capture(from: event) else {
            NSSound.beep()
            return true
        }
        isRecording = false
        onRecord?(binding)
        return true
    }

    private func updateTitle() {
        title = isRecording
            ? NSLocalizedString("按下快捷键", comment: "Shortcut recorder prompt")
            : shortcut.displayName
        toolTip = isRecording
            ? NSLocalizedString("按下包含 Command 的快捷组合键，或按 Esc 取消", comment: "Shortcut recorder help")
            : NSLocalizedString("点击以录制新的快捷键", comment: "Shortcut recorder help")
    }
}
