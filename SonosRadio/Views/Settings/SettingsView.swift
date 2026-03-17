import SwiftUI
import SwiftData

struct SettingsView: View {
    @Query private var importSources: [ImportSource]
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    var speakers: [Speaker]

    @State private var newSourceName = ""
    @State private var newSourceURL = ""

    var body: some View {
        NavigationStack {
            List {
                Section("Import Presets") {
                    TextField("Source Name", text: $newSourceName)
                    TextField("JSON URL", text: $newSourceURL)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                    Button("Add Import Source") {
                        guard !newSourceName.isEmpty, !newSourceURL.isEmpty else { return }
                        let source = ImportSource(name: newSourceName, urlString: newSourceURL)
                        modelContext.insert(source)
                        newSourceName = ""
                        newSourceURL = ""
                    }
                    .disabled(newSourceName.isEmpty || newSourceURL.isEmpty)

                    ForEach(importSources) { source in
                        VStack(alignment: .leading) {
                            Text(source.name).font(.body)
                            Text(source.urlString).font(.caption).foregroundStyle(.secondary)
                            if let date = source.lastImported {
                                Text("Last imported: \(date.formatted())").font(.caption2).foregroundStyle(.tertiary)
                            }
                        }
                    }
                    .onDelete { offsets in
                        for i in offsets { modelContext.delete(importSources[i]) }
                    }
                }

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
