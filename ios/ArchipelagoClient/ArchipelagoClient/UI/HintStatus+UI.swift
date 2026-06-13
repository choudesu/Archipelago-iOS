import SwiftUI

extension HintStatus {
    /// Short label for the hints list and status menu (web-tracker style).
    var menuTitle: String {
        switch self {
        case .unspecified: return "Unset"
        case .noPriority: return "QoL"
        case .avoid: return "Trash"
        case .priority: return "Critical"
        case .found: return "Found"
        }
    }

    var systemImage: String {
        switch self {
        case .unspecified: return "envelope.badge"
        case .noPriority: return "figure.wave"
        case .avoid: return "trash"
        case .priority: return "exclamationmark.triangle.fill"
        case .found: return "checkmark.circle.fill"
        }
    }

    func uiColor(for colorScheme: ColorScheme) -> Color {
        let palette = APArchipelagoColors.palette(for: colorScheme)
        switch self {
        case .unspecified: return palette.white.opacity(colorScheme == .dark ? 0.9 : 0.55)
        case .noPriority: return palette.blue
        case .avoid: return Color.secondary
        case .priority: return palette.red
        case .found: return palette.green
        }
    }

    /// Statuses the user can pick for an active hint.
    static var selectableCases: [HintStatus] {
        [.unspecified, .noPriority, .avoid, .priority]
    }
}
