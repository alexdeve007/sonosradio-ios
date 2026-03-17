# SonosRadio

A native iOS app for playing internet radio on Sonos speakers. Discovers speakers on the local network via Bonjour/SSDP and controls them over UPnP/SOAP.

## Features

- **Speaker discovery** — automatic Bonjour + SSDP discovery of Sonos speakers on the local network
- **Station search** — search TuneIn and iHeartRadio, or enter direct stream URLs
- **Playback** — uses Sonos-native `x-sonosapi-stream` URIs for TuneIn/iHeart, `x-rincon-mp3radio` for direct streams
- **Speaker groups** — view existing groups, create new ones
- **Presets** — save favorite stations, import from JSON
- **Per-speaker controls** — play/pause, volume, mute on each speaker independently

## Requirements

- Xcode 16+
- iOS 18.0+
- Swift 6
- A Sonos system on the same local network as your device

## Getting Started

1. **Clone the repo**

   ```
   git clone git@github.com:alevy-me/sonosradio-ios.git
   cd sonosradio-ios
   ```

2. **Open the Xcode project**

   ```
   open SonosRadio.xcodeproj
   ```

   No package dependencies or code generation steps — the project is self-contained.

3. **Set your development team**

   In Xcode, select the `SonosRadio` target > Signing & Capabilities > set your Team and update the Bundle Identifier if needed (e.g. `com.yourname.SonosRadio`).

4. **Run on a device**

   Speaker discovery requires local network access, which works on both the iOS Simulator and physical devices. However, **playback only works on a real device** on the same Wi-Fi network as your Sonos speakers.

   Select your device and hit Run (Cmd+R).

5. **Allow local network access**

   On first launch, iOS will prompt for local network permission. Accept it — the app uses Bonjour (`_sonos._tcp`) to find speakers and sends SOAP commands over HTTP to control them.

## Importing Station Presets

You can import a JSON file of stations via the import button on the Stations tab. The JSON should be an array of objects. The importer accepts several key formats:

```json
[
  {"name": "WWOZ", "streamUrl": "http://wwoz-sc.streamguys1.com/wwoz-hi.mp3"},
  {"Station Name": "FIP", "Stream URL": "https://icecast.radiofrance.fr/fip-hifi.aac"}
]
```

Accepted keys: `name` / `Station Name` / `station_name`, `streamUrl` / `streamURL` / `Stream URL` / `stream_url` / `url`, and optionally `artworkUrl` / `Artwork URL` etc.

## Architecture

```
SonosRadio/
  App/              — App entry point, tab layout
  Models/           — Speaker, Station, StationPreset (SwiftData)
  Services/         — TuneIn, iHeart, StreamResolver, PresetImporter
  Transport/        — SOAP client, SSDP/Bonjour discovery, UPnP events
  Utilities/        — XML parsing, debouncer, zone group parser
  ViewModels/       — SpeakersVM, NowPlayingVM (playback engine), StationsVM
  Views/            — SpeakersView, StationsView, StationRowView, SettingsView
```

- **No third-party dependencies.** All UPnP/SOAP/SSDP is implemented from scratch using BSD sockets and URLSession.
- **SwiftUI + @Observable** for the UI layer.
- **SwiftData** for persisting station presets and import sources.
