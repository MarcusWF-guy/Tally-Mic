import Foundation

/// The Devices tab's changes (SPEC 5.5): show or hide an input in the panel, give it a name, or
/// forget one that's gone. Each change is saved at once and shows in the panel straight away.
@MainActor
final class DeviceSettings {
    private let config: ConfigStore
    private let model: AppModel

    init(config: ConfigStore, model: AppModel) {
        self.config = config
        self.model = model
    }

    func setVisible(_ visible: Bool, for device: KnownDevice) {
        config.setVisible(visible, uid: device.uid)
        Log.info("Devices: \(visible ? "showing" : "hiding") \(device.name)")
        commit()
    }

    /// Called as the name is typed. Blank goes back to the name macOS reports.
    func setDisplayName(_ name: String, for device: KnownDevice) {
        config.setDisplayName(name, uid: device.uid)
        commit()
    }

    func nameEditingEnded(for device: KnownDevice) {
        let name = model.knownDevices.first { $0.uid == device.uid }?.displayName
        Log.info("Devices: \(device.name) is " + (name.map { "named \"\($0)\"" } ?? "using its own name"))
    }

    /// Only for inputs that aren't connected; a connected one would be added straight back.
    func forget(_ device: KnownDevice) {
        guard !model.inputs.contains(where: { $0.uid == device.uid }) else { return }
        config.forget(uid: device.uid)
        Log.info("Devices: forgot \(device.name)")
        commit()
    }

    private func commit() {
        config.saveOrLog()
        model.knownDevices = config.devices
    }
}
