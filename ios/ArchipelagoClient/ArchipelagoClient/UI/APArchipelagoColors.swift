import SwiftUI

/// Archipelago text colors from `data/client.kv` / `NetUtils.JSONtoTextParser.color_codes`.
/// Dark palette matches the desktop client; light palette uses darker variants for white backgrounds.
enum APArchipelagoColors {
    struct Palette {
        let black: Color
        let red: Color
        let green: Color
        let yellow: Color
        let blue: Color
        let magenta: Color
        let cyan: Color
        let slateblue: Color
        let plum: Color
        let salmon: Color
        let white: Color
        let orange: Color

        private var namedColors: [String: Color] {
            [
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
        }

        func color(named name: String) -> Color? {
            namedColors[name]
        }

        /// First recognized name from a `;`-separated color list (matches Python `_handle_color`).
        func color(fromSemicolonList list: String) -> Color? {
            for name in list.split(separator: ";").map({ String($0) }) {
                if let color = color(named: name) {
                    return color
                }
            }
            return nil
        }

        func itemColor(flags: Int) -> Color {
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

        func playerColor(isSelf: Bool) -> Color {
            isSelf ? magenta : yellow
        }

        func hintStatusColor(_ status: HintStatus) -> Color {
            switch status {
            case .found: return green
            case .unspecified: return white
            case .noPriority: return slateblue
            case .avoid: return salmon
            case .priority: return plum
            }
        }
    }

    /// Desktop client palette (dark backgrounds).
    static let dark = Palette(
        black: Color(hex: 0x000000),
        red: Color(hex: 0xEE0000),
        green: Color(hex: 0x00FF7F),
        yellow: Color(hex: 0xFAFAD2),
        blue: Color(hex: 0x6495ED),
        magenta: Color(hex: 0xEE00EE),
        cyan: Color(hex: 0x00EEEE),
        slateblue: Color(hex: 0x6D8BE8),
        plum: Color(hex: 0xAF99EF),
        salmon: Color(hex: 0xFA8072),
        white: Color(hex: 0xFFFFFF),
        orange: Color(hex: 0xFF7700)
    )

    /// Readable variants for light backgrounds while preserving semantic hues.
    static let light = Palette(
        black: Color(hex: 0x000000),
        red: Color(hex: 0xCC0000),
        green: Color(hex: 0x007A4D),
        yellow: Color(hex: 0x8B7500),
        blue: Color(hex: 0x2563B8),
        magenta: Color(hex: 0x9B009B),
        cyan: Color(hex: 0x007A7A),
        slateblue: Color(hex: 0x2E4FA8),
        plum: Color(hex: 0x5B3FB5),
        salmon: Color(hex: 0xC43C30),
        white: Color(hex: 0x555555),
        orange: Color(hex: 0xC75A00)
    )

    static func palette(for colorScheme: ColorScheme) -> Palette {
        colorScheme == .light ? light : dark
    }

    // Desktop palette accessors (used by unit tests and plain-text fallbacks).
    static var black: Color { dark.black }
    static var red: Color { dark.red }
    static var green: Color { dark.green }
    static var yellow: Color { dark.yellow }
    static var blue: Color { dark.blue }
    static var magenta: Color { dark.magenta }
    static var cyan: Color { dark.cyan }
    static var slateblue: Color { dark.slateblue }
    static var plum: Color { dark.plum }
    static var salmon: Color { dark.salmon }
    static var white: Color { dark.white }
    static var orange: Color { dark.orange }

    static func color(named name: String) -> Color? {
        dark.color(named: name)
    }

    static func color(fromSemicolonList list: String) -> Color? {
        dark.color(fromSemicolonList: list)
    }

    static func itemColor(flags: Int) -> Color {
        dark.itemColor(flags: flags)
    }

    static func playerColor(slot: Int, isSelf: Bool) -> Color {
        dark.playerColor(isSelf: isSelf)
    }

    static func hintStatusColor(_ status: HintStatus) -> Color {
        dark.hintStatusColor(status)
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
