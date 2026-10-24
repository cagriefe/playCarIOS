# PlayCar — CarPlay-style Landscape Dashboard for iPhone

PlayCar turns an iPhone into a CarPlay-like driving dashboard. It is a landscape-only, dark-themed SwiftUI app (iOS 17+): a full-height map with turn-by-turn navigation on the left (65%), and speed, status and media controls on the right (35%).

The app UI and voice guidance are in Turkish.

## Features

- **Map** — `MKMapView` with live traffic, Apple Maps-style follow / heading modes, day/night map toggle, POI tap, long-press to drop a pin, and a compass.
- **Navigation** — driving routes via `MKDirections`, step-by-step guidance, automatic re-routing when off-route, ETA, and Turkish voice prompts that duck music instead of stopping it.
- **Search** — `MKLocalSearchCompleter` biased towards Turkey and the current location, with 300 ms debounce.
- **Favorites** — save, list, navigate to, and delete places (stored on-device).
- **Speedometer** — GPS speed in km/h with a user-configurable speed limit (30–140 km/h) and color warnings.
- **Media** — now playing, playlists and tracks from the device music library via `MediaPlayer`, a seekable progress bar, and the system `MPVolumeView` (volume + AirPlay).
- **Call card** — shows the duration of an ongoing phone call (via `CallKit`'s `CXCallObserver`).
- **Status row** — clock, date, compass heading and battery level.
- **Driving mode** — map controls auto-hide after 4 seconds of inactivity; the screen can be kept awake (toggleable).

## Requirements

- Xcode 15 or later
- iOS 17.0+ (iPhone; iPad is supported in landscape)
- An Apple Developer account to run on a physical device

## Getting started

1. Clone the repo and open `PlayCarIOS.xcodeproj`.
2. In **Signing & Capabilities**, select your own **Team**. Change the bundle identifier (`com.playcar.ios`) to something unique, e.g. `com.<yourname>.playcar`.
3. Select the **PlayCarIOS** scheme and run on a device or simulator.

Tips:

- To test the speedometer and navigation in the simulator, use **Features → Location → City Drive**.
- The media panel needs music library permission on a real device. In the simulator, "no track playing" is expected.
- Debug builds accept a `-PCDebugNavTo "lat,lon"` launch argument that starts navigation to the given coordinate on launch.

## Project structure

```
PlayCarIOS/
  PlayCarIOSApp.swift          # @main, idle timer, dark mode
  AppDelegate.swift            # landscape orientation lock
  Info.plist                   # permissions, landscape, background modes
  PrivacyInfo.xcprivacy        # privacy manifest
  Services/
    LocationManager.swift      # location, speed (km/h), compass
    NavigationStore.swift      # routing, step tracking, re-routing, voice
    SearchService.swift        # place / address search
    FavoritesStore.swift       # saved places (UserDefaults)
    MusicPlayerManager.swift   # music library, playback, metadata
    CallStore.swift            # ongoing call duration
    TelemetryStore.swift       # clock, date, battery, keep-screen-on
  Views/
    DashboardView.swift        # 65/35 split layout + status row
    MapPanelView.swift         # map, search, navigation cards, favorites
    SpeedometerView.swift      # speed gauge + limit
    MediaControlView.swift     # now playing, playlists, tracks, volume
```

The app follows a simple MVVM structure: each service is an `ObservableObject` with a single responsibility, and views only bind to them.

## Permissions

| Key | Purpose |
|---|---|
| `NSLocationWhenInUseUsageDescription` | Map, navigation and speedometer |
| `NSLocationAlwaysAndWhenInUseUsageDescription` | Optional background speed / route tracking |
| `NSAppleMusicUsageDescription` | Music controls and now-playing info |
| `NSMotionUsageDescription` | Optional, improves driving detection |

Background modes: `location` (speed and navigation while in the background) and `audio` (voice guidance while the screen is locked).

## Privacy

Everything runs on-device. The app does no tracking and sends no data off the device. Favorites and settings are stored in `UserDefaults`.

## Platform notes and limitations

- **Speed limits are manual.** iOS has no public speed-limit API, so the limit is set by the user.
- **No volume slider or mute.** Setting the system volume from a custom slider is not allowed on iOS, so the system `MPVolumeView` is used instead.
- **Calls can't be controlled.** Third-party apps can't answer, end, or see the caller of a phone call. The app only shows the call duration.
- **Not real CarPlay.** The app makes the iPhone screen look like CarPlay. Real CarPlay support (`CarPlay.framework`) needs a separate entitlement from Apple.
- No offline maps.

## License

[MIT](LICENSE)
