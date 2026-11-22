import SwiftUI
import AppKit

enum Theme {
    static let window = Color(hex: 0x111216)
    static let chrome = Color(hex: 0x181A1F)
    static let chromeRaised = Color(hex: 0x22252C)
    static let editor = Color(hex: 0x15171B)
    static let editorAlt = Color(hex: 0x131519)
    static let border = Color(hex: 0x2A2D34)
    static let borderSoft = Color(hex: 0x21242A)
    static let text = Color(hex: 0xEDEFF3)
    static let secondary = Color(hex: 0x9BA1AC)
    static let tertiary = Color(hex: 0x6C7280)
    static let accent = Color(hex: 0x3B7BF6)
    static let accentAlt = Color(hex: 0x11B8C7)
    static let accentSoft = Color(hex: 0x3B7BF6).opacity(0.16)
    static let accentGradient = LinearGradient(
        colors: [Color(hex: 0x3B7BF6), Color(hex: 0x11B8C7)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    static let cardGradient = LinearGradient(
        colors: [Color(hex: 0x1B1F2A), Color(hex: 0x151922)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    static let success = Color(hex: 0x3ECF8E)
    static let warning = Color(hex: 0xE5B454)
    static let danger = Color(hex: 0xF26D6D)
    static let radius: CGFloat = 10
}

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        let r = Double((hex >> 16) & 0xFF) / 255
        let g = Double((hex >> 8) & 0xFF) / 255
        let b = Double(hex & 0xFF) / 255
        self.init(.sRGB, red: r, green: g, blue: b, opacity: opacity)
    }
}

extension NSColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha
        )
    }
}

extension View {
    func cardBackground(_ color: Color = Theme.chrome, radius: CGFloat = Theme.radius) -> some View {
        background(
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(Theme.cardGradient)
                .overlay(
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .fill(color.opacity(0.18))
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [Theme.border.opacity(0.9), Theme.borderSoft.opacity(0.45)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
        .shadow(color: .black.opacity(0.18), radius: 18, x: 0, y: 10)
    }
}

struct HoverHighlight: ViewModifier {
    @State private var hovering = false
    let enabled: Bool

    func body(content: Content) -> some View {
        content
            .background(hovering && enabled ? Theme.chromeRaised.opacity(0.55) : Color.clear)
            .onHover { hovering = $0 }
    }
}

extension View {
    func hoverHighlight(enabled: Bool = true) -> some View {
        modifier(HoverHighlight(enabled: enabled))
    }
}
