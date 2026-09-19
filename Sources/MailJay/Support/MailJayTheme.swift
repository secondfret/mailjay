import AppKit
import SwiftUI

/// Flat dark surfaces inspired by Spark — opaque fills, no glass/materials.
enum MailJayTheme {
    static let canvas = Color(hex: 0x121212)
    static let sidebar = Color(hex: 0x161616)
    static let pane = Color(hex: 0x1A1A1A)
    static let card = Color(hex: 0x222222)
    static let cardElevated = Color(hex: 0x2A2A2A)
    static let hairline = Color.white.opacity(0.06)
    static let accent = Color(hex: 0x3B82F6)
    static let accentSoft = Color(hex: 0x3B82F6).opacity(0.18)
    static let textPrimary = Color.white.opacity(0.92)
    static let textSecondary = Color.white.opacity(0.45)
    static let textTertiary = Color.white.opacity(0.28)

    static let radiusSm: CGFloat = 8
    static let radiusMd: CGFloat = 12
    static let radiusLg: CGFloat = 16

    static let sidebarWidth: CGFloat = 228
    static let listMinWidth: CGFloat = 300

    static var nsCanvas: NSColor { NSColor(srgbRed: 0x12 / 255, green: 0x12 / 255, blue: 0x12 / 255, alpha: 1) }
    static var nsSidebar: NSColor { NSColor(srgbRed: 0x16 / 255, green: 0x16 / 255, blue: 0x16 / 255, alpha: 1) }
}

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        let r = Double((hex >> 16) & 0xFF) / 255
        let g = Double((hex >> 8) & 0xFF) / 255
        let b = Double(hex & 0xFF) / 255
        self.init(.sRGB, red: r, green: g, blue: b, opacity: opacity)
    }
}

enum MailAvatar {
    static func initials(from sender: String) -> String {
        let name = displayName(from: sender)
        let parts = name.split(whereSeparator: { $0.isWhitespace || $0 == "." }).filter { !$0.isEmpty }
        if parts.count >= 2 {
            return String(parts[0].prefix(1) + parts[1].prefix(1)).uppercased()
        }
        if let first = parts.first, !first.isEmpty {
            return String(first.prefix(2)).uppercased()
        }
        return "?"
    }

    static func displayName(from sender: String) -> String {
        let trimmed = sender.trimmingCharacters(in: .whitespacesAndNewlines)
        if let angle = trimmed.firstIndex(of: "<") {
            let name = trimmed[..<angle].trimmingCharacters(in: .whitespacesAndNewlines)
            if !name.isEmpty { return name.trimmingCharacters(in: CharacterSet(charactersIn: "\"")) }
        }
        if let at = trimmed.firstIndex(of: "@") {
            return String(trimmed[..<at])
        }
        return trimmed.isEmpty ? "Unknown" : trimmed
    }

    static func color(for sender: String) -> Color {
        var hash: UInt64 = 5381
        for byte in displayName(from: sender).utf8 {
            hash = ((hash << 5) &+ hash) &+ UInt64(byte)
        }
        let hues: [UInt32] = [0x3B82F6, 0x8B5CF6, 0x06B6D4, 0x10B981, 0xF59E0B, 0xEF4444, 0xEC4899, 0x6366F1]
        return Color(hex: hues[Int(hash % UInt64(hues.count))])
    }
}
