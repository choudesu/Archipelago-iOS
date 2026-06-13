import SwiftUI

/// Archipelago text colors from `data/client.kv` / `NetUtils.JSONtoTextParser.color_codes`.
enum APArchipelagoColors {
    static let black = Color(hex: 0x000000)
    static let red = Color(hex: 0xEE0000)
    static let green = Color(hex: 0x00FF7F)
    static let yellow = Color(hex: 0xFAFAD2)
    static let blue = Color(hex: 0x6495ED)
    static let magenta = Color(hex: 0xEE00EE)
    static let cyan = Color(hex: 0x00EEEE)
    static let slateblue = Color(hex: 0x6D8BE8)
    static let plum = Color(hex: 0xAF99EF)
    static let salmon = Color(hex: 0xFA8072)
    static let white = Color(hex: 0xFFFFFF)
    static let orange = Color(hex: 0xFF7700)

    private static let namedColors: [String: Color] = [
        "black": black,
        "red": red,
        "green": green,
        "yellow": yellow,
        "blue": blue,
        "magenta": magenta,
        "cyan": cyan,
        "slateblue": slateblue,
        "plum": plum,
        "salmon": salmon,
        "white": white,
        "orange": orange,
    ]

    static func color(named name: String) -> Color? {
        namedColors[name]
    }

    /// First recognized name from a `;`-separated color list (matches Python `_handle_color`).
    static func color(fromSemicolonList list: String) -> Color? {
        for name in list.split(separator: ";").map({ String($0) }) {
            if let color = color(named: name) {
                return color
            }
        }
        return nil
    }

    static func itemColor(flags: Int) -> Color {
        if flags == 0 {
            return cyan
        }
        if flags & 0b001 != 0 {
            return plum
        }
        if flags & 0b010 != 0 {
            return slateblue
        }
        if flags & 0b100 != 0 {
            return salmon
        }
        return cyan
    }

    static func playerColor(slot: Int, isSelf: Bool) -> Color {
        isSelf ? magenta : yellow
    }

    static func hintStatusColor(_ status: HintStatus) -> Color {
        switch status {
        case .found: return green
        case .unspecified: return white
        case .noPriority: return slateblue
        case .avoid: return salmon
        case .priority: return plum
        }
    }
}

private extension Color {
    init(hex: UInt32) {
        let red = Double((hex >> 16) & 0xFF) / 255
        let green = Double((hex >> 8) & 0xFF) / 255
        let blue = Double(hex & 0xFF) / 255
        self.init(red: red, green: green, blue: blue)
    }
}

#if DEBUG
import UIKit

extension APArchipelagoColors {
    static func rgbHex(_ color: Color) -> String? {
        #if canImport(UIKit)
        let uiColor = UIColor(color)
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        guard uiColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha) else {
            return nil
        }
        return String(
            format: "%02X%02X%02X",
            Int(red * 255),
            Int(green * 255),
            Int(blue * 255)
        )
        #else
        return nil
        #endif
    }
}
#endif
