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
            Group {
                if let speakersVM, let nowPlayingVM {
                    ContentView(
                        speakersVM: speakersVM,
                        nowPlayingVM: nowPlayingVM,
                        stationsVM: stationsVM
                    )
                } else {
                    ProgressView("Loading...")
                        .onAppear {
                            speakersVM = SpeakersViewModel(provider: provider)
                            nowPlayingVM = NowPlayingViewModel(provider: provider)
                        }
                }
            }
        }
        .modelContainer(for: [
            StationPreset.self
        ])
    }
}

struct ContentView: View {
    @Bindable var speakersVM: SpeakersViewModel
    @Bindable var nowPlayingVM: NowPlayingViewModel
    @Bindable var stationsVM: StationsViewModel

    private enum Tab: Hashable { case speakers, stations }
    @State private var selectedTab: Tab = .speakers

    var body: some View {
        TabView(selection: $selectedTab) {
            SpeakersView(viewModel: speakersVM, onSpeakerSelected: {
                selectedTab = .stations
            })
            .tabItem { Label("Speakers", systemImage: "hifispeaker.2") }
            .tag(Tab.speakers)

            StationsView(viewModel: stationsVM, nowPlayingViewModel: nowPlayingVM, speakersVM: speakersVM)
                .tabItem { Label("Stations", systemImage: "radio") }
                .tag(Tab.stations)
        }
        .task {
            await speakersVM.discover()
        }
    }
}
