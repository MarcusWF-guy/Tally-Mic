import Foundation

/// Any JSON value. Lets the config keep keys this version of Tally Mic doesn't know about.
enum JSONValue: Codable, Equatable, Sendable {
    case object([String: JSONValue])
    case array([JSONValue])
    case string(String)
    case number(Double)
    case bool(Bool)
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else {
            self = .object(try container.decode([String: JSONValue].self))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .object(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .string(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .bool(let value): try container.encode(value)
        case .null: try container.encodeNil()
        }
    }

    var object: [String: JSONValue]? {
        if case .object(let value) = self { return value }
        return nil
    }

    var string: String? {
        if case .string(let value) = self { return value }
        return nil
    }
}

/// A device Tally Mic has seen, as config.json stores it (SPEC 5.5, 10).
struct KnownDevice: Equatable, Sendable, Identifiable {
    var uid: String
    /// The name macOS reports.
    var name: String
    var transport: String
    /// The user's name for it in the panel (Devices tab), or nil to use `name`.
    var displayName: String? = nil
    /// Whether it appears in the panel (Devices tab).
    var visible: Bool = true

    var id: String { uid }
    var shownName: String { displayName ?? name }
}

/// Reads and writes ~/Library/Application Support/Tally Mic/config.json (SPEC 10).
/// Writes are atomic, and keys Tally Mic doesn't know about are kept.
@MainActor
final class ConfigStore {
    static let currentVersion = 1

    nonisolated static let defaultURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/Tally Mic/config.json")

    let url: URL
    private var root: [String: JSONValue]

    init(url: URL = ConfigStore.defaultURL) {
        self.url = url
        root = Self.load(from: url)
    }

    /// Every input Tally Mic has seen, in the order it first saw them.
    var devices: [KnownDevice] {
        storedDevices.compactMap { entry in
            guard let object = entry.object, let uid = object["uid"]?.string else { return nil }
            var visible = true
            if case .bool(let value)? = object["visible"] { visible = value }
            return KnownDevice(
                uid: uid, name: object["name"]?.string ?? uid, transport: object["transport"]?.string ?? "unknown",
                displayName: object["displayName"]?.string.flatMap { $0.isEmpty ? nil : $0 }, visible: visible)
        }
    }

    // MARK: Devices tab (SPEC 5.5)

    func setVisible(_ visible: Bool, uid: String) {
        update(uid) { $0["visible"] = .bool(visible) }
    }

    /// Blank or whitespace-only clears the name, so the panel uses the one macOS reports.
    func setDisplayName(_ name: String?, uid: String) {
        let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        update(uid) { $0["displayName"] = trimmed.isEmpty ? .null : .string(trimmed) }
    }

    /// Removes a device from the list. If it connects again it's added back as new.
    func forget(uid: String) {
        root["devices"] = .array(storedDevices.filter { $0.object?["uid"]?.string != uid })
    }

    private func update(_ uid: String, _ change: (inout [String: JSONValue]) -> Void) {
        root["devices"] = .array(storedDevices.map { entry in
            guard var object = entry.object, object["uid"]?.string == uid else { return entry }
            change(&object)
            return .object(object)
        })
    }

    /// Adds devices Tally Mic hasn't seen before to the end of the list and refreshes names.
    /// Returns whether anything changed.
    ///
    /// SPEC 7.1: a USB device without a serial number gets a new UID on another USB port. A new UID
    /// with the same name and transport as a known device that isn't connected is that device, so
    /// its stored UID is updated instead of adding a second entry.
    @discardableResult
    func recordSeen(_ connected: [InputDevice]) -> Bool {
        var entries = storedDevices
        let connectedUIDs = Set(connected.map(\.uid))
        var changed = false

        func uid(_ entry: JSONValue) -> String? { entry.object?["uid"]?.string }

        for device in connected {
            if let index = entries.firstIndex(where: { uid($0) == device.uid }) {
                if entries[index].object?["name"]?.string != device.name {
                    entries[index] = merging(entries[index], ["name": .string(device.name)])
                    changed = true
                }
                continue
            }

            let moved = entries.firstIndex { entry in
                guard let object = entry.object, let old = object["uid"]?.string else { return false }
                return !connectedUIDs.contains(old)
                    && object["name"]?.string == device.name
                    && object["transport"]?.string == device.transport.rawValue
            }
            if let moved {
                Log.info("\(device.name) has a new UID, probably from another USB port. "
                    + "Updated \(uid(entries[moved]) ?? "?") to \(device.uid).")
                entries[moved] = merging(entries[moved], ["uid": .string(device.uid)])
            } else {
                entries.append(.object([
                    "uid": .string(device.uid),
                    "name": .string(device.name),
                    "transport": .string(device.transport.rawValue),
                    "displayName": .null,
                    "visible": .bool(true),
                ]))
            }
            changed = true
        }

        if changed { root["devices"] = .array(entries) }
        return changed
    }

    // MARK: Setups (SPEC 6.1, 10)

    /// The setups, in the order they're checked. One "Laptop" fallback until the user adds more.
    var setups: [Setup] {
        guard case .array(let entries)? = root["setups"] else { return [Setup.firstRun] }
        let setups = entries.compactMap { entry -> Setup? in
            guard let object = entry.object, let id = object["id"]?.string else { return nil }
            var order: [String] = []
            if case .array(let uids)? = object["order"] { order = uids.compactMap(\.string) }
            return Setup(id: id, name: object["name"]?.string ?? "Setup",
                         trigger: object["trigger"].flatMap(Self.display), order: order)
        }
        return SetupResolver.normalized(setups)
    }

    /// Replaces the setups, keeping keys a later version of Tally Mic might have added to each.
    func setSetups(_ setups: [Setup]) {
        var existing: [String: [String: JSONValue]] = [:]
        if case .array(let entries)? = root["setups"] {
            for entry in entries {
                if let object = entry.object, let id = object["id"]?.string { existing[id] = object }
            }
        }
        root["setups"] = .array(SetupResolver.normalized(setups).map { setup in
            var object = existing[setup.id] ?? [:]
            object["id"] = .string(setup.id)
            object["name"] = .string(setup.name)
            object["trigger"] = setup.trigger.map(Self.json) ?? .null
            object["order"] = .array(setup.order.map(JSONValue.string))
            return .object(object)
        })
    }

    /// Every external display Tally Mic has seen, for the Setups tab's "Active when" picker.
    var displays: [DisplayID] {
        guard case .array(let entries)? = root["displays"] else { return [] }
        return entries.compactMap(Self.display)
    }

    /// Adds displays not seen before. Returns whether anything changed.
    @discardableResult
    func recordDisplays(_ connected: [DisplayID]) -> Bool {
        var known = displays
        let new = connected.filter { display in !known.contains { $0.matches(display) } }
        guard !new.isEmpty else { return false }
        known += new
        root["displays"] = .array(known.map(Self.json))
        return true
    }

    private static func display(_ json: JSONValue) -> DisplayID? {
        guard let object = json.object, let name = object["name"]?.string else { return nil }
        func number(_ key: String) -> UInt32 {
            if case .number(let value)? = object[key], value >= 0, value <= Double(UInt32.max) { return UInt32(value) }
            return 0
        }
        return DisplayID(name: name, vendorID: number("vendorId"), modelID: number("modelId"), serial: number("serial"))
    }

    private static func json(_ display: DisplayID) -> JSONValue {
        .object([
            "type": .string("display"),
            "name": .string(display.name),
            "vendorId": .number(Double(display.vendorID)),
            "modelId": .number(Double(display.modelID)),
            "serial": .number(Double(display.serial)),
        ])
    }

    // MARK: Shortcuts (SPEC 7.6)

    /// The keyboard shortcuts set in the Shortcuts tab. None until the user sets them.
    var shortcuts: [ShortcutAction: Shortcut] {
        guard let stored = root["shortcuts"]?.object else { return [:] }
        var shortcuts: [ShortcutAction: Shortcut] = [:]
        for (key, value) in stored {
            guard let action = ShortcutAction(key: key), let object = value.object,
                  case .number(let keyCode)? = object["keyCode"], case .number(let modifiers)? = object["modifiers"],
                  keyCode >= 0, modifiers >= 0 else { continue }
            shortcuts[action] = Shortcut(keyCode: UInt32(keyCode), modifiers: UInt32(modifiers))
        }
        return shortcuts
    }

    func setShortcuts(_ shortcuts: [ShortcutAction: Shortcut]) {
        root["shortcuts"] = .object(Dictionary(uniqueKeysWithValues: shortcuts.map { action, shortcut in
            (action.key, JSONValue.object([
                "keyCode": .number(Double(shortcut.keyCode)),
                "modifiers": .number(Double(shortcut.modifiers)),
            ]))
        }))
    }

    /// SPEC 6.2: automatic switching. Off until the user turns it on in General.
    var preferredOrderEnabled: Bool {
        get {
            if case .bool(let value)? = root["preferredOrderEnabled"] { return value }
            return false
        }
        set { root["preferredOrderEnabled"] = .bool(newValue) }
    }

    /// Whether the user wants Tally Mic to launch at login. Nil until it's been set once (SPEC 9).
    var launchAtLogin: Bool? {
        get {
            if case .bool(let value)? = root["general"]?.object?["launchAtLogin"] { return value }
            return nil
        }
        set {
            var general = root["general"]?.object ?? [:]
            general["launchAtLogin"] = newValue.map(JSONValue.bool) ?? .null
            root["general"] = .object(general)
        }
    }

    /// SPEC 7.7: the volume keys change an external monitor's volume. Off until turned on in General.
    var controlMonitorVolume: Bool {
        get {
            if case .bool(let value)? = root["general"]?.object?["controlMonitorVolume"] { return value }
            return false
        }
        set {
            var general = root["general"]?.object ?? [:]
            general["controlMonitorVolume"] = .bool(newValue)
            root["general"] = .object(general)
        }
    }

    func save() throws {
        if root["version"] == nil {
            root["version"] = .number(Double(Self.currentVersion))
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(root)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }

    /// Saves, logging instead of throwing. For changes the user didn't make by hand.
    func saveOrLog() {
        do { try save() } catch { Log.error("Couldn't save config.json: \(error.localizedDescription)") }
    }

    private var storedDevices: [JSONValue] {
        if case .array(let entries)? = root["devices"] { return entries }
        return []
    }

    private func merging(_ entry: JSONValue, _ changes: [String: JSONValue]) -> JSONValue {
        .object((entry.object ?? [:]).merging(changes) { _, new in new })
    }

    private static func load(from url: URL) -> [String: JSONValue] {
        guard let data = try? Data(contentsOf: url) else {
            return ["version": .number(Double(currentVersion))]
        }
        if let root = (try? JSONDecoder().decode(JSONValue.self, from: data))?.object {
            return root
        }

        // Never overwrite a file Tally Mic can't read. Set it aside, so nothing is lost.
        let stamp = Date().formatted(.iso8601).replacingOccurrences(of: ":", with: "-")
        let aside = url.deletingLastPathComponent().appendingPathComponent("config.unreadable-\(stamp).json")
        try? FileManager.default.moveItem(at: url, to: aside)
        Log.error("config.json couldn't be read. It was moved to \(aside.lastPathComponent) and a new one started.")
        return ["version": .number(Double(currentVersion))]
    }
}
