import SwiftUI
import AppKit

extension NSColor {
    var hexString: String {
        guard let rgbColor = usingColorSpace(.sRGB) else {
            return "#000000"
        }
        let red = Int(round(rgbColor.redComponent * 255))
        let green = Int(round(rgbColor.greenComponent * 255))
        let blue = Int(round(rgbColor.blueComponent * 255))
        return String(format: "#%02X%02X%02X", red, green, blue)
    }

    convenience init?(hex: String) {
        let hexString = hex.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "#", with: "")
        var rgbValue: UInt64 = 0
        
        guard Scanner(string: hexString).scanHexInt64(&rgbValue) else { return nil }
        
        let r, g, b: CGFloat
        if hexString.count == 6 {
            r = CGFloat((rgbValue & 0xFF0000) >> 16) / 255.0
            g = CGFloat((rgbValue & 0x00FF00) >> 8) / 255.0
            b = CGFloat(rgbValue & 0x0000FF) / 255.0
        } else {
            return nil
        }
        
        self.init(srgbRed: r, green: g, blue: b, alpha: 1.0)
    }
}

extension Color {
    init(hex: String) {
        if let nsColor = NSColor(hex: hex) {
            self.init(nsColor: nsColor)
        } else {
            self.init(.black)
        }
    }
}
