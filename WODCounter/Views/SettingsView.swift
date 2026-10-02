import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    // Same key and same tag values as the History screen, via ResultsWindow.
    @AppStorage(ResultsWindow.defaultsKey) private var storedWindow: String = ResultsWindow.fallback.rawValue

    var body: some View {
        Form {
            Section("History Preferences") {
                Picker("Default Time Window", selection: $storedWindow) {
                    ForEach(ResultsWindow.allCases) { window in
                        Text(window.label).tag(window.rawValue)
                    }
                }
            }

            Section {
                HStack {
                    Text("Version")
                    Spacer()
                    Text("1.0.0")
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Text("Mode")
                    Spacer()
                    Text("Offline-First")
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("About")
            } footer: {
                Text("Workouts and history are stored on this device only.")
            }
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") {
                    dismiss()
                }
            }
        }
    }
}
