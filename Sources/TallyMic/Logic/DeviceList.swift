import CoreAudio

/// One row in the panel: a connected input and the name to show for it.
struct ShownDevice: Identifiable, Equatable, Sendable {
    let device: InputDevice
    let name: String
    var id: String { device.uid }
}

/// Which inputs the panel lists, and under what names (SPEC 5.3). Pure, for testing.
enum DeviceList {
    /// Connected inputs the user hasn't hidden, plus the current input even if it's hidden, so the
    /// panel always shows what's in use. Named as the user named them in the Devices tab, and listed
    /// in `order` (the active setup's full order, as UIDs). Inputs Tally Mic hasn't recorded yet
    /// count as shown and come last, by name.
    static func shown(inputs: [InputDevice], known: [KnownDevice], currentID: AudioObjectID?,
                      order: [String]) -> [ShownDevice] {
        let byUID = Dictionary(known.map { ($0.uid, $0) }, uniquingKeysWith: { first, _ in first })
        let rank = Dictionary(order.enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
        return inputs
            .filter { byUID[$0.uid]?.visible ?? true || $0.objectID == currentID }
            .map { ShownDevice(device: $0, name: byUID[$0.uid]?.displayName ?? $0.name) }
            .sorted { a, b in
                switch (rank[a.id], rank[b.id]) {
                case let (x?, y?): x < y
                case (.some, nil): true
                case (nil, .some): false
                case (nil, nil): a.name.localizedStandardCompare(b.name) == .orderedAscending
                }
            }
    }
}
