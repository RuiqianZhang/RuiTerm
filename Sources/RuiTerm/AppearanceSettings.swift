import SwiftUI

enum AppLanguage: String, CaseIterable, Identifiable {
    case system
    case simplifiedChinese
    case english

    var id: String { rawValue }

    var locale: Locale {
        switch self {
        case .system:
            return .autoupdatingCurrent
        case .simplifiedChinese:
            return Locale(identifier: "zh-Hans")
        case .english:
            return Locale(identifier: "en")
        }
    }

    var displayName: String {
        switch self {
        case .system: return "跟随系统 / System"
        case .simplifiedChinese: return "简体中文"
        case .english: return "English"
        }
    }

    func applyToUserDefaults() {
        switch self {
        case .system:
            UserDefaults.standard.removeObject(forKey: "AppleLanguages")
        case .simplifiedChinese:
            UserDefaults.standard.set(["zh-Hans"], forKey: "AppleLanguages")
        case .english:
            UserDefaults.standard.set(["en"], forKey: "AppleLanguages")
        }
        UserDefaults.standard.synchronize()
    }
}

enum AppThemeMode: String, CaseIterable, Identifiable {
    case system = "System"
    case light = "Light"
    case dark = "Dark"
    case glass = "Glass"
    
    var id: String { rawValue }
    
    var colorScheme: ColorScheme? {
        switch self {
        case .system, .glass: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }

    var usesGlass: Bool { self == .glass }
}

enum CursorStyle: String, CaseIterable, Identifiable {
    case block = "Block"
    case underline = "Underline"
    case bar = "Vertical Bar"
    
    var id: String { rawValue }
}

enum TerminalThemePreset: String, CaseIterable, Identifiable {
    case ruiTerm = "RuiTerm Default"
    case homebrew = "Homebrew"
    case solarizedDark = "Solarized Dark"
    case solarizedLight = "Solarized Light"
    case dracula = "Dracula"
    case cyberpunk = "Cyberpunk"
    
    var id: String { rawValue }
    
    var background: String {
        switch self {
        case .ruiTerm: return "#090B0E"
        case .homebrew: return "#000000"
        case .solarizedDark: return "#002B36"
        case .solarizedLight: return "#FDF6E3"
        case .dracula: return "#282A36"
        case .cyberpunk: return "#0B0426"
        }
    }
    
    var foreground: String {
        switch self {
        case .ruiTerm: return "#EAEAEA"
        case .homebrew: return "#26E326"
        case .solarizedDark: return "#839496"
        case .solarizedLight: return "#657B83"
        case .dracula: return "#F8F8F2"
        case .cyberpunk: return "#00FFD1"
        }
    }
    
    var cursor: String {
        switch self {
        case .ruiTerm: return "#FF9F0A"
        case .homebrew: return "#26E326"
        case .solarizedDark: return "#93A1A1"
        case .solarizedLight: return "#657B83"
        case .dracula: return "#535F7A"
        case .cyberpunk: return "#FF0056"
        }
    }
}

enum TerminalScrollbackLimits {
    static let minimum = 1_000
    static let defaultLines = 10_000
    static let maximum = 50_000
    static let logBurstMaximum = 5_000
}

final class AppearanceSettings: ObservableObject {
    @AppStorage("appLanguage") var appLanguage: AppLanguage = .system
    @AppStorage("appThemeMode") var appMode: AppThemeMode = .system
    @AppStorage("reduceLiquidGlassEffects") var reduceLiquidGlassEffects: Bool = false
    
    // Terminal Colors
    @AppStorage("terminalBackgroundHex") var backgroundHex: String = TerminalThemePreset.ruiTerm.background
    @AppStorage("terminalForegroundHex") var foregroundHex: String = TerminalThemePreset.ruiTerm.foreground
    @AppStorage("terminalCursorHex") var cursorHex: String = TerminalThemePreset.ruiTerm.cursor
    
    // Terminal Typography & Shape
    @AppStorage("terminalFontName") var fontName: String = "" // Empty string means system mono font
    @AppStorage("terminalFontSize") var fontSize: Double = 13.5
    @AppStorage("terminalCursorStyle") var cursorStyle: CursorStyle = .block
    @AppStorage("terminalScrollbackLines") var scrollbackLines: Int = TerminalScrollbackLimits.defaultLines {
        didSet {
            let clamped = Self.clampedScrollbackLines(scrollbackLines)
            if scrollbackLines != clamped {
                scrollbackLines = clamped
            }
        }
    }
    
    static let shared = AppearanceSettings()

    private init() {
        scrollbackLines = Self.clampedScrollbackLines(scrollbackLines)
        if cursorHex == "#FFFFFF" {
            cursorHex = TerminalThemePreset.ruiTerm.cursor
        }
    }

    static func clampedScrollbackLines(_ lines: Int) -> Int {
        min(max(lines, TerminalScrollbackLimits.minimum), TerminalScrollbackLimits.maximum)
    }

    var effectiveScrollbackLines: Int {
        Self.clampedScrollbackLines(scrollbackLines)
    }

    var usesLiquidGlassEffects: Bool {
        appMode.usesGlass && !reduceLiquidGlassEffects
    }

    var usesControlGlassEffects: Bool {
        !reduceLiquidGlassEffects
    }

    var isFullGlassMode: Bool {
        appMode.usesGlass && !reduceLiquidGlassEffects
    }

    var translucentChromeOpacity: Double {
        isFullGlassMode ? 0.18 : 0.38
    }

    var translucentOverlayOpacity: Double {
        isFullGlassMode ? 0.22 : 0.52
    }

    var translucentActiveTabOpacity: Double {
        isFullGlassMode ? 0.30 : 0.58
    }

    var translucentHoverOpacity: Double {
        isFullGlassMode ? 0.08 : 0.18
    }

    var translucentResourceCardOpacity: Double {
        isFullGlassMode ? 0.16 : 0.32
    }

    var translucentTerminalPreviewOpacity: Double {
        isFullGlassMode ? 0.66 : 0.78
    }

    var translucentThemePreviewOpacity: Double {
        isFullGlassMode ? 0.82 : 0.94
    }
    
    func applyPreset(_ preset: TerminalThemePreset) {
        self.backgroundHex = preset.background
        self.foregroundHex = preset.foreground
        self.cursorHex = preset.cursor
    }
    
    // Helpers
    var backgroundColor: NSColor { NSColor(hex: backgroundHex) ?? .black }
    var foregroundColor: NSColor { NSColor(hex: foregroundHex) ?? .white }
    var cursorColor: NSColor { NSColor(hex: cursorHex) ?? .white }
    
    var font: NSFont {
        if fontName.isEmpty {
            return NSFont.monospacedSystemFont(ofSize: CGFloat(fontSize), weight: .regular)
        } else {
            return NSFont(name: fontName, size: CGFloat(fontSize)) ?? NSFont.monospacedSystemFont(ofSize: CGFloat(fontSize), weight: .regular)
        }
    }
}
