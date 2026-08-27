import Cocoa

func createIcon(isDark: Bool) -> NSImage {
    let size = NSSize(width: 1024, height: 1024)
    let image = NSImage(size: size)
    image.lockFocus()

    guard let ctx = NSGraphicsContext.current?.cgContext else { return image }
    
    // Clear background
    ctx.clear(CGRect(origin: .zero, size: size))
    
    // Draw rounded rect
    let rect = CGRect(origin: .zero, size: size).insetBy(dx: 64, dy: 64)
    let path = NSBezierPath(roundedRect: rect, xRadius: 224, yRadius: 224)
    
    if isDark {
        NSColor(white: 0.15, alpha: 1.0).setFill()
    } else {
        NSColor(white: 0.95, alpha: 1.0).setFill()
    }
    path.fill()
    
    // Draw text
    let text = ">_"
    let textColor = isDark ? NSColor.cyan : NSColor(white: 0.2, alpha: 1.0)
    let font = NSFont.monospacedSystemFont(ofSize: 360, weight: .bold)
    
    let attributes: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: textColor
    ]
    
    let string = NSAttributedString(string: text, attributes: attributes)
    let stringSize = string.size()
    let textRect = CGRect(
        x: (size.width - stringSize.width) / 2,
        y: (size.height - stringSize.height) / 2 - 20, // slight vertical adjustment
        width: stringSize.width,
        height: stringSize.height
    )
    
    string.draw(in: textRect)
    
    image.unlockFocus()
    return image
}

func save(image: NSImage, to path: String) {
    guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }
    let bitmapRep = NSBitmapImageRep(cgImage: cgImage)
    guard let pngData = bitmapRep.representation(using: .png, properties: [:]) else { return }
    try? pngData.write(to: URL(fileURLWithPath: path))
}

save(image: createIcon(isDark: true), to: "Resources/RuiTerm-AppIcon-Dark.png")
save(image: createIcon(isDark: false), to: "Resources/RuiTerm-AppIcon-Light.png")
print("Icons generated successfully.")
