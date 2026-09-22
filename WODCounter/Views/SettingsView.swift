import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("cloudKitEnabled") private var cloudKitEnabled = false
    @AppStorage("defaultWindow") private var defaultWindow = "30d"

    var body: some View {
        Form {
            Section {
                Toggle(isOn: $cloudKitEnabled) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("iCloud Sync")
                        Text("Sync workouts and history across your Apple devices using private CloudKit storage.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("Sync & Storage")
            } footer: {
                Text("Changes to sync settings will take effect on next app launch.")
            }

            Section("History Preferences") {
                Picker("Default Time Window", selection: $defaultWindow) {
                    Text("Past 7 Days").tag("7d")
                    Text("Past 30 Days").tag("30d")
                    Text("Past 90 Days").tag("90d")
                    Text("All Time").tag("all")
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
