import SwiftUI
import SwiftData

@main
struct SonosRadioApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(for: [
            StationPreset.self,
            GroupPreset.self,
            ImportSource.self
        ])
    }
}

struct ContentView: View {
    var body: some View {
        TabView {
            Text("Now Playing")
                .tabItem {
                    Label("Now Playing", systemImage: "play.circle")
                }

            Text("Stations")
                .tabItem {
                    Label("Stations", systemImage: "radio")
                }

            Text("Speakers")
                .tabItem {
                    Label("Speakers", systemImage: "hifispeaker.2")
                }
        }
    }
}
