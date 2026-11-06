import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage(ResultsWindow.storageKey) private var storedWindow = ResultsWindow.defaultValue.rawValue

    private var defaultWindow: Binding<ResultsWindow> {
        Binding(
            get: { ResultsWindow(storedValue: storedWindow) },
            set: { storedWindow = $0.rawValue }
        )
    }

    var body: some View {
        Form {
            Section {
                HStack {
                    Text("Storage")
                    Spacer()
                    Text("On This Device")
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Data")
            } footer: {
                Text("Workouts and history are stored locally. iCloud sync is not available in this version.")
            }

            Section("History Preferences") {
                Picker("Default Time Window", selection: defaultWindow) {
                    ForEach(ResultsWindow.allCases) { window in
                        Text(window.settingsLabel).tag(window)
                    }
                }
            }

            Section("About") {
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
