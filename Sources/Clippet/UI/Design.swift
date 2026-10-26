import AppKit
import SwiftUI

enum Design {

    static let panelHeight: CGFloat = 332
    static let sidePadding: CGFloat = 24
    static let topBarHeight: CGFloat = 56
    static let bottomBarHeight: CGFloat = 46

    static let cardWidth: CGFloat = 235
    static let cardHeight: CGFloat = 214
    static let cardGap: CGFloat = 29
    static let cardRadius: CGFloat = 16
    static let headerHeight: CGFloat = 52
    static let headerIconSize: CGFloat = 40

    static let accent = Color(hex: "#0A84FF")
    static let cardBody = Color(hex: "#1E1E1E")
    static let tabBarPill = Color.white.opacity(0.08)
    static let tabSelected = Color.white.opacity(0.16)
    static let cardHairline = Color.white.opacity(0.10)
}

extension Color {

    init(hex: String) {
        let cleaned = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        var value: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&value)
        let r, g, b: Double
        switch cleaned.count {
        case 3:
            r = Double((value >> 8) & 0xF) / 15
            g = Double((value >> 4) & 0xF) / 15
            b = Double(value & 0xF) / 15
        default:
            r = Double((value >> 16) & 0xFF) / 255
            g = Double((value >> 8) & 0xFF) / 255
            b = Double(value & 0xFF) / 255
        }
        self.init(.sRGB, red: r, green: g, blue: b, opacity: 1)
    }

    func lightened(_ amount: Double) -> Color {
        let ns = NSColor(self).usingColorSpace(.sRGB) ?? .gray
        return Color(.sRGB,
                     red: min(1, ns.redComponent + (1 - ns.redComponent) * amount),
                     green: min(1, ns.greenComponent + (1 - ns.greenComponent) * amount),
                     blue: min(1, ns.blueComponent + (1 - ns.blueComponent) * amount),
                     opacity: 1)
    }

    var prefersDarkText: Bool {
        let ns = NSColor(self).usingColorSpace(.sRGB) ?? .gray
        let luminance = 0.299 * ns.redComponent + 0.587 * ns.greenComponent + 0.114 * ns.blueComponent
        return luminance > 0.62
    }
}

private let relativeFormatter: RelativeDateTimeFormatter = {
    let f = RelativeDateTimeFormatter()
    f.unitsStyle = .short
    return f
}()

extension Date {
    var relativeLabel: String {
        relativeFormatter.localizedString(for: self, relativeTo: Date())
    }
}
