// MARK: - Imports
import SwiftUI
import AppKit

// MARK: - Claudacity Colors
extension Color {
    static let claudacity = ClaudacityColors()
}

struct ClaudacityColors {
    // Status Colors
    let safe = Color(hex: "#22C55E")      // 50-100%
    let caution = Color(hex: "#F59E0B")   // 30-50%
    let warning = Color(hex: "#EF4444")   // 10-30%
    let danger = Color(hex: "#DC2626")    // 0-10%

    // Background - 라이트/다크 모드 적응형
    var background: Color {
        Color(nsColor: .windowBackgroundColor)
    }
    
    var secondaryBackground: Color {
        // 시스템 색상을 사용하여 라이트/다크 모드에 자동 적응
        // controlBackgroundColor는 라이트/다크 모드에서 적절한 대비를 제공
        Color(nsColor: .controlBackgroundColor)
    }
    
    var tertiaryBackground: Color {
        Color(nsColor: .unemphasizedSelectedContentBackgroundColor)
    }

    // Text
    let primaryText = Color(nsColor: .labelColor)
    let secondaryText = Color(nsColor: .secondaryLabelColor)
}

// MARK: - Status Color Helper
func statusColor(for percentage: Double) -> Color {
    switch percentage {
    case 50...: return Color.claudacity.safe
    case 30..<50: return Color.claudacity.caution
    case 10..<30: return Color.claudacity.warning
    default: return Color.claudacity.danger
    }
}

// MARK: - Hex Color Extension
extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}
