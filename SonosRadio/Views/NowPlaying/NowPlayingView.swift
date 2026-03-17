import SwiftUI

struct NowPlayingView: View {
    @Bindable var viewModel: NowPlayingViewModel
    var speakers: [Speaker]

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                if let station = viewModel.currentStation {
                    AsyncImage(url: station.artworkURL) { image in
                        image.resizable().aspectRatio(contentMode: .fit)
                    } placeholder: {
                        Image(systemName: "radio")
                            .font(.system(size: 80))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: 250, maxHeight: 250)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .shadow(radius: 8)

                    Text(station.name)
                        .font(.title2).bold()
                    if let speaker = viewModel.activeSpeaker {
                        Text("Playing on \(speaker.name)")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }

                    HStack(spacing: 40) {
                        Button { Task { await viewModel.stop() } } label: {
                            Image(systemName: "stop.fill").font(.title)
                        }
                        Button { Task { await viewModel.togglePlayPause() } } label: {
                            Image(systemName: viewModel.transportState == .playing ? "pause.fill" : "play.fill")
                                .font(.system(size: 44))
                        }
                    }
                    .padding()

                    VStack {
                        HStack {
                            Button { Task { await viewModel.toggleMute() } } label: {
                                Image(systemName: viewModel.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                            }
                            Slider(value: Binding(
                                get: { Double(viewModel.volume) },
                                set: { viewModel.setVolume(Int($0)) }
                            ), in: 0...100)
                            Text("\(viewModel.volume)")
                                .frame(width: 35).monospacedDigit()
                        }
                    }
                    .padding(.horizontal)
                } else {
                    ContentUnavailableView {
                        Label("Nothing Playing", systemImage: "radio")
                    } description: {
                        Text("Select a station to start listening")
                    }
                }

                Spacer()
            }
            .padding()
            .navigationTitle("Now Playing")
            .alert("Error", isPresented: .init(
                get: { viewModel.errorMessage != nil },
                set: { if !$0 { viewModel.errorMessage = nil } }
            )) {
                Button("OK") { viewModel.errorMessage = nil }
            } message: {
                Text(viewModel.errorMessage ?? "")
            }
        }
    }
}
