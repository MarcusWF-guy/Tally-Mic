import SwiftUI

/// The panel's bottom section (SPEC 5.3), always shown: one line saying which setup Tally Mic
/// detected, whether or not it's switching, and one switch for automatic switching. Laid out like
/// Control Center's rows: label on the left, value or switch at the trailing edge.
struct SetupSection: View {
    let setupName: String
    let autoSwitching: Bool
    let setAutoSwitching: (Bool) -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Setup")
                Spacer(minLength: 8)
                Text(setupName)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .padding(.horizontal, PanelMetrics.inset)
            .frame(height: 28)
            .accessibilityElement(children: .combine)
            .help("Tally Mic picks the setup from the displays connected (Tally Mic Settings > Setups)")

            HStack {
                Text("Automatic Switching")
                Spacer(minLength: 8)
                Toggle("Automatic Switching", isOn: Binding(get: { autoSwitching }, set: { setAutoSwitching($0) }))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
            }
            .padding(.horizontal, PanelMetrics.inset)
            .frame(height: 32)
            .help(autoSwitching
                ? "Picking a microphone yourself turns this off"
                : "Switch to the first available microphone in the \(setupName) setup's order")
        }
        .font(.system(size: 13))
    }
}
