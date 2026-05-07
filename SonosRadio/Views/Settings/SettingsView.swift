import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss

    var speakers: [Speaker]

    var body: some View {
        NavigationStack {
            List {
                Section("Network") {
                    ForEach(speakers) { speaker in
                        VStack(alignment: .leading) {
                            Text(speaker.name).font(.body)
                            Text("\(speaker.ipAddress):\(speaker.port)").font(.caption).monospacedDigit()
                            Text(speaker.modelName).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    if speakers.isEmpty {
                        Text("No speakers discovered").foregroundStyle(.secondary)
                    }
                }

                Section("About") {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text("1.0.0").foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
