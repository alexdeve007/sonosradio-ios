import SwiftUI
import SwiftData

@main
struct SonosRadioApp: App {
    @State private var provider = LocalUPnPProvider()
    @State private var speakersVM: SpeakersViewModel?
    @State private var nowPlayingVM: NowPlayingViewModel?
    @State private var stationsVM = StationsViewModel()

    var body: some Scene {
        WindowGroup {
            ContentView(
                speakersVM: speakersVM ?? SpeakersViewModel(provider: provider),
                nowPlayingVM: nowPlayingVM ?? NowPlayingViewModel(provider: provider),
                stationsVM: stationsVM
            )
            .onAppear {
                if speakersVM == nil {
                    speakersVM = SpeakersViewModel(provider: provider)
                    nowPlayingVM = NowPlayingViewModel(provider: provider)
                }
            }
        }
        .modelContainer(for: [
            StationPreset.self,
            GroupPreset.self,
            ImportSource.self
        ])
    }
}

struct ContentView: View {
    @Bindable var speakersVM: SpeakersViewModel
    @Bindable var nowPlayingVM: NowPlayingViewModel
    @Bindable var stationsVM: StationsViewModel

    @State private var showSettings = false

    var body: some View {
        TabView {
            NowPlayingView(viewModel: nowPlayingVM, speakers: speakersVM.speakers)
                .tabItem { Label("Now Playing", systemImage: "play.circle") }

            StationsView(viewModel: stationsVM, nowPlayingViewModel: nowPlayingVM, speakers: speakersVM.speakers)
                .tabItem { Label("Stations", systemImage: "radio") }

            SpeakersView(viewModel: speakersVM)
                .tabItem { Label("Speakers", systemImage: "hifispeaker.2") }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showSettings = true } label: {
                    Image(systemName: "gear")
                }
            }
        }
        .sheet(isPresented: $showSettings) {
            SettingsView(speakers: speakersVM.speakers)
        }
        .task {
            await speakersVM.discover()
        }
    }
}
