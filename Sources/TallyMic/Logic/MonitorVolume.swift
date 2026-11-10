import Foundation

/// A monitor's volume as the volume keys change it (SPEC 7.7), with macOS's rules but finer:
/// 64 steps rather than 16 (Marcus found 16, then 32, too coarse for his monitor), and with ⇧⌥ held,
/// steps as small as the monitor's own; volume up or down also unmutes; the mute key toggles.
struct MonitorVolume: Equatable, Sendable {
    /// 0 to 1.
    var level: Double
    var muted = false

    enum Key: Sendable {
        case up, down, mute
    }

    static let steps = 64.0
    /// The bubble's bar, as in macOS's.
    static let segments = 16.0

    /// One press, in `steps` steps from silent to full (snapping to the nearest step first).
    func pressing(_ key: Key, steps: Double = MonitorVolume.steps) -> MonitorVolume {
        let index = (level * steps).rounded()
        switch key {
        case .mute:
            return MonitorVolume(level: level, muted: !muted)
        case .up:
            return MonitorVolume(level: min(index + 1, steps) / steps, muted: false)
        case .down:
            return MonitorVolume(level: max(index - 1, 0) / steps, muted: false)
        }
    }

    /// What's sent to the monitor: muting sets its volume to zero.
    func ddcValue(max: UInt16) -> UInt16 {
        muted ? 0 : UInt16((level * Double(max)).rounded())
    }

    /// The speaker symbol macOS's volume bubble uses at this level.
    var symbol: String {
        if muted || level <= 0 { return "speaker.slash.fill" }
        if level <= 1.0 / 3 { return "speaker.wave.1.fill" }
        if level <= 2.0 / 3 { return "speaker.wave.2.fill" }
        return "speaker.wave.3.fill"
    }

    /// How many of the bubble's 16 segments are lit; between steps, one is partly lit.
    var litSegments: Double {
        muted ? 0 : level * Self.segments
    }
}

/// DDC/CI, the standard monitors use to take commands over their video cable (SPEC 7.7).
/// Only the bytes, so they can be tested; MonitorDDC sends them.
enum DDC {
    /// The monitor's DDC/CI I2C address (7-bit).
    static let address: UInt32 = 0x37
    /// Where host messages go, and the first byte every checksum covers.
    static let hostAddress: UInt8 = 0x51
    /// VCP code for the speaker volume.
    static let volume: UInt8 = 0x62

    /// "Set VCP feature": length, opcode 0x03, code, value high, value low, checksum.
    static func setRequest(_ code: UInt8, _ value: UInt16) -> [UInt8] {
        let body: [UInt8] = [0x84, 0x03, code, UInt8(value >> 8), UInt8(value & 0xFF)]
        return body + [checksum(0x6E ^ hostAddress, body)]
    }

    /// "Get VCP feature": length, opcode 0x01, code, checksum. MonitorControl and m1ddc leave the
    /// host address out of this one's checksum, unlike the standard; `standard` puts it in, so a
    /// read can try both.
    static func getRequest(_ code: UInt8, standard: Bool = false) -> [UInt8] {
        let body: [UInt8] = [0x82, 0x01, code]
        return body + [checksum(standard ? 0x6E ^ hostAddress : 0x6E, body)]
    }

    /// The monitor's reply to "get VCP feature": source 0x6E, length 0x88, opcode 0x02, result,
    /// code, type, max (2 bytes), current (2 bytes), checksum.
    static func parseReply(_ reply: [UInt8], code: UInt8) -> (current: UInt16, max: UInt16)? {
        guard reply.count >= 11, reply[0] == 0x6E, reply[2] == 0x02, reply[3] == 0x00, reply[4] == code,
              checksum(0x50, Array(reply[0..<10])) == reply[10] else { return nil }
        let max = UInt16(reply[6]) << 8 | UInt16(reply[7])
        let current = UInt16(reply[8]) << 8 | UInt16(reply[9])
        return max > 0 ? (current, max) : nil
    }

    static func checksum(_ seed: UInt8, _ bytes: [UInt8]) -> UInt8 {
        bytes.reduce(seed, ^)
    }
}

/// Which display a display's sound output belongs to. Its Core Audio UID starts with bytes from
/// the display's EDID: the vendor ID, then the product ID low byte first. For example
/// `ABCD3412-…` is vendor 0xABCD, product 0x1234.
enum DisplayAudio {
    static func displayIDs(fromOutputUID uid: String) -> (vendor: UInt32, product: UInt32)? {
        let hex = uid.prefix(8)
        guard hex.count == 8, uid.dropFirst(8).first == "-",
              let vendor = UInt32(hex.prefix(4), radix: 16),
              let product = UInt16(hex.suffix(4), radix: 16) else { return nil }
        return (vendor, UInt32(product.byteSwapped))
    }
}
