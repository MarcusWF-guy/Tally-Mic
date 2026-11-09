import Foundation

/// An external display, as a setup's trigger or as one Tally Mic has seen (SPEC 6.1).
struct DisplayID: Equatable, Hashable, Sendable {
    var name: String
    var vendorID: UInt32
    var modelID: UInt32
    var serial: UInt32

    /// SPEC 6.1: the same display if vendor, model and serial number match. When either side has no
    /// numbers (all zero), the display's name decides instead.
    func matches(_ other: DisplayID) -> Bool {
        if hasNumbers && other.hasNumbers {
            return vendorID == other.vendorID && modelID == other.modelID && serial == other.serial
        }
        return name == other.name
    }

    var hasNumbers: Bool { vendorID != 0 || modelID != 0 || serial != 0 }
}

/// A setup (SPEC 6.1): a name, a trigger, and a preferred order of inputs by UID. The last setup has
/// no trigger and is the fallback ("Otherwise").
struct Setup: Identifiable, Equatable, Sendable {
    var id: String
    var name: String
    /// The display whose connection makes this setup active. Nil for the fallback.
    var trigger: DisplayID?
    /// Input UIDs, most preferred first. Inputs not listed come after, in the order first seen.
    var order: [String]

    var isFallback: Bool { trigger == nil }

    /// What a Mac starts with: one setup, used whatever is connected.
    static let firstRun = Setup(id: "laptop", name: "Laptop", trigger: nil, order: [])
}

/// Which setup is active, and each setup's full order (SPEC 6.1). Pure, for testing.
enum SetupResolver {
    /// The first setup whose display is connected, else the fallback.
    static func active(_ setups: [Setup], connected: [DisplayID]) -> Setup {
        let normal = normalized(setups)
        return normal.first { setup in
            guard let trigger = setup.trigger else { return false }
            return connected.contains(where: trigger.matches)
        } ?? normal.last!
    }

    /// Setups as Tally Mic keeps them: never empty, exactly one fallback, and the fallback last.
    /// Anything else (an edited config.json, say) is repaired this way.
    static func normalized(_ setups: [Setup]) -> [Setup] {
        var triggered = setups.filter { !$0.isFallback }
        let fallback = setups.first(where: \.isFallback) ?? Setup.firstRun
        triggered.removeAll { $0.id == fallback.id }
        return triggered + [fallback]
    }

    /// Every known input in a setup's order: the ones it lists first, then the rest in the order
    /// Tally Mic first saw them. UIDs of inputs Tally Mic has forgotten are dropped.
    static func fullOrder(_ setup: Setup, known: [KnownDevice]) -> [KnownDevice] {
        let byUID = Dictionary(known.map { ($0.uid, $0) }, uniquingKeysWith: { first, _ in first })
        var seen = Set<String>()
        let listed = setup.order.compactMap { uid -> KnownDevice? in
            guard seen.insert(uid).inserted else { return nil }
            return byUID[uid]
        }
        return listed + known.filter { !seen.contains($0.uid) }
    }

    /// External displays that are connected but that no setup uses, for "Add a Setup for …".
    static func unusedDisplays(_ setups: [Setup], connected: [DisplayID]) -> [DisplayID] {
        connected.filter { display in !setups.contains { $0.trigger?.matches(display) ?? false } }
    }
}
