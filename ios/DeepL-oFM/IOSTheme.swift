import SwiftUI

enum IOSTheme {
    static let window = Color(hex: 0x111216)
    static let chrome = Color(hex: 0x181A1F)
    static let raised = Color(hex: 0x22252C)
    static let border = Color(hex: 0x2A2D34)
    static let text = Color(hex: 0xEDEFF3)
    static let secondary = Color(hex: 0x9BA1AC)
    static let tertiary = Color(hex: 0x6C7280)
    static let warning = Color(hex: 0xE5B454)
    static let danger = Color(hex: 0xF26D6D)
    static let accent = Color(hex: 0x3B7BF6)
    static let accentAlt = Color(hex: 0x11B8C7)
    static let gradient = LinearGradient(
        colors: [accent, accentAlt],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        let red = Double((hex >> 16) & 0xFF) / 255
        let green = Double((hex >> 8) & 0xFF) / 255
        let blue = Double(hex & 0xFF) / 255
        self.init(.sRGB, red: red, green: green, blue: blue, opacity: opacity)
    }
}
