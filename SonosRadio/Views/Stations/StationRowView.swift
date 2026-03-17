import SwiftUI

struct StationRowView: View {
    let station: Station
    var onPlay: () -> Void
    var onSave: () -> Void

    var body: some View {
        Button(action: onPlay) {
            HStack {
                AsyncImage(url: station.artworkURL) { image in
                    image.resizable().aspectRatio(contentMode: .fill)
                } placeholder: {
                    Image(systemName: "radio").foregroundStyle(.secondary)
                }
                .frame(width: 44, height: 44)
                .clipShape(RoundedRectangle(cornerRadius: 6))

                VStack(alignment: .leading, spacing: 2) {
                    Text(station.name).font(.body).lineLimit(1)
                    if let genre = station.genre ?? station.description {
                        Text(genre).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                }

                Spacer()

                if let bitrate = station.bitrate {
                    Text("\(bitrate)k").font(.caption2).foregroundStyle(.tertiary)
                }
            }
        }
        .contextMenu {
            Button { onSave() } label: {
                Label("Save to Presets", systemImage: "plus.circle")
            }
        }
    }
}
