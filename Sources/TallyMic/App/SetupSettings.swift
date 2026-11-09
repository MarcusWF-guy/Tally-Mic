import Foundation

/// The Setups tab's changes (SPEC 5.5, 6.1). Each is saved at once. The fallback setup
/// ("Otherwise") always stays, and stays last.
@MainActor
final class SetupSettings {
    private let config: ConfigStore
    private let model: AppModel

    init(config: ConfigStore, model: AppModel) {
        self.config = config
        self.model = model
    }

    /// The display a new setup should use: one that's connected but in no setup, else one seen
    /// before that's in no setup, else nil (then there's nothing to add a setup for).
    var displayForNewSetup: DisplayID? {
        SetupResolver.unusedDisplays(model.setups, connected: model.displays).first
            ?? SetupResolver.unusedDisplays(model.setups, connected: model.knownDisplays).first
    }

    /// Adds a setup for `display`, checked before the fallback, named after the display.
    /// Returns its ID, or nil if there's no display to use.
    @discardableResult
    func add(for display: DisplayID? = nil) -> String? {
        guard let display = display ?? displayForNewSetup else { return nil }
        let setup = Setup(id: UUID().uuidString, name: display.name, trigger: display, order: [])
        var setups = model.setups
        setups.insert(setup, at: max(setups.count - 1, 0))
        Log.info("Setups: added \(setup.name)")
        commit(setups)
        return setup.id
    }

    /// Called as the name is typed, so it's stored as typed: trimming here would eat the space
    /// before the next word. A blank name shows as "Untitled".
    func rename(_ id: String, to name: String) {
        change(id) { $0.name = name }
    }

    /// The fallback can't be deleted.
    func delete(_ id: String) {
        guard let setup = model.setups.first(where: { $0.id == id }), !setup.isFallback else { return }
        Log.info("Setups: deleted \(setup.name)")
        commit(model.setups.filter { $0.id != id })
    }

    /// Reorders the setups that have a display; the fallback stays last whatever happens.
    func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        var setups = model.setups
        setups.move(fromOffsets: source, toOffset: destination)
        commit(setups)
    }

    func setTrigger(_ id: String, to display: DisplayID) {
        guard model.setups.first(where: { $0.id == id })?.isFallback == false else { return }
        Log.info("Setups: \(name(id)) is now active when \(display.name) is connected")
        change(id) { $0.trigger = display }
    }

    /// Reorders a setup's inputs, as shown in the tab: its full order (SPEC 6.1).
    func moveDevices(in id: String, fromOffsets source: IndexSet, toOffset destination: Int) {
        guard let setup = model.setups.first(where: { $0.id == id }) else { return }
        var uids = SetupResolver.fullOrder(setup, known: model.knownDevices).map(\.uid)
        uids.move(fromOffsets: source, toOffset: destination)
        Log.info("Setups: \(setup.name) order is now " + uids.compactMap { uid in
            model.knownDevices.first { $0.uid == uid }?.shownName }.joined(separator: ", "))
        change(id) { $0.order = uids }
    }

    private func name(_ id: String) -> String { model.setups.first { $0.id == id }?.name ?? id }

    private func change(_ id: String, _ edit: (inout Setup) -> Void) {
        var setups = model.setups
        guard let index = setups.firstIndex(where: { $0.id == id }) else { return }
        edit(&setups[index])
        commit(setups)
    }

    private func commit(_ setups: [Setup]) {
        config.setSetups(setups)
        config.saveOrLog()
        model.setups = config.setups
    }
}
