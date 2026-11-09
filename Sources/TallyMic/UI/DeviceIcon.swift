import Foundation

/// The SF Symbol in each device row's circle (SPEC 5.4): from how the device is connected, and
/// for USB and Bluetooth devices, from its name.
enum DeviceIcon {
    /// Name matches, checked top to bottom, ignoring case. Add a line to teach Tally Mic a device.
    static let nameRules: [(match: NameMatch, symbol: String)] = [
        (.contains("airpods max"), "airpodsmax"),
        (.contains("airpods pro"), "airpodspro"),
        (.contains("airpods"), "airpods"),
        (.contains("iphone"), "iphone"),
        (.contains("headset"), "headphones"),
        (.wordStarting("hs"), "headphones"),  // Gaming headsets named like "HS70". At a word's start, so "hs" inside words doesn't count.
        (.contains("receiver"), "headphones"),
        (.contains("brio"), "web.camera"),
        (.contains("insta360"), "web.camera"),
        (.word("link"), "web.camera"),  // Insta360 Link. As a whole word, so "LinkBuds" doesn't count.
        (.contains("cam"), "web.camera"),
    ]

    /// Headsets and earbuds: the icons for things you wear. Their mics are only picked automatically
    /// while they're the sound output (SPEC 6.2).
    static func isHeadset(_ symbol: String) -> Bool {
        ["headphones", "airpods", "airpodspro", "airpodsmax"].contains(symbol)
    }

    static func symbol(name: String, transport: Transport) -> String {
        switch transport {
        case .builtIn: return "laptopcomputer"
        case .virtual, .aggregate, .autoAggregate: return "waveform"
        case .displayPort, .hdmi, .thunderbolt: return "display"
        case .continuityWired, .continuityWireless: return "iphone"
        default: break
        }
        if let rule = nameRules.first(where: { $0.match.matches(name) }) {
            return rule.symbol
        }
        return switch transport {
        case .bluetooth, .bluetoothLE: "headphones"
        default: "mic"
        }
    }

    enum NameMatch: Sendable {
        case contains(String)
        /// A word that starts with this, such as "HS70" for "hs".
        case wordStarting(String)
        case word(String)

        func matches(_ name: String) -> Bool {
            let name = name.lowercased()
            let words = name.split { !$0.isLetter && !$0.isNumber }
            return switch self {
            case .contains(let text): name.contains(text)
            case .wordStarting(let text): words.contains { $0.hasPrefix(text) }
            case .word(let text): words.contains { $0 == text }
            }
        }
    }
}
