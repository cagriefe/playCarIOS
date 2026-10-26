# PlayCar — CarPlay-style Landscape Dashboard for iPhone

PlayCar turns an iPhone into a CarPlay-like driving dashboard. It is a landscape-only, dark-themed SwiftUI app (iOS 17+): a full-height map with turn-by-turn navigation on the left (65%), and speed, favorite contacts and media controls on the right (35%).

The app is localized in **English** and **Turkish** and follows the device language (other languages fall back to English). Route instructions and voice guidance use the app language; distances and speeds use km/h or mph depending on the region.

## Features

- **Map** — `MKMapView` with live traffic, Apple Maps-style follow / heading modes, day/night map toggle, POI tap, long-press to drop a pin, and a compass.
- **Navigation** — driving routes via `MKDirections` with up to three **alternative routes** in the preview (pick one from the cards or tap a gray line on the map), step-by-step guidance with maneuver arrows and a "Then" hint for close maneuvers, automatic re-routing when off-route, ETA, and voice prompts in the app language that duck music instead of stopping it.
- **Search** — `MKLocalSearchCompleter` biased towards the current location, with 300 ms debounce.
- **Favorites, Home & Work** — save, list, navigate to, and delete places (stored on-device). Mark favorites as Home or Work (swipe right in Favorites; more than one of each is allowed); one-tap chips under the search bar show them with live, traffic-aware travel time.
- **Recents** — the last 8 destinations you navigated to, shown as chips and in the search list.
- **Speedometer** — GPS speed in km/h or mph with color warnings and a limit marker on the gauge. The speed limit is **estimated** from the road type (from Apple's reverse geocoding) and the country's legal defaults — no third-party service. Turkey has detailed rules (KGM table: 50 / 82 in-city divided roads / 90 / 110 / 120–140 per motorway). Tap the limit to correct it in one tap or turn estimation off.
- **Trip summary** — tap the speed to see distance, driving time, average and top speed for the current trip (resettable). It flips back to the speed after 10 seconds or as soon as you go over the limit.
- **Media** — now playing, playlists and tracks from the device music library via `MediaPlayer`, a seekable progress bar, and the system audio output picker (car Bluetooth, iPhone speaker, AirPlay).
- **Favorite contacts** — four one-tap call shortcuts between the speedometer and the media card, picked with the system contact picker (no Contacts permission needed). Long-press to call, replace or remove.
- **Call card** — when a call rings, is dialing or is active, the media card switches to a call view with status and duration (via `CallKit`'s `CXCallObserver`). Calls placed from a favorite show the contact's name and photo.
- **Do Not Disturb button** — the moon in the status row switches Do Not Disturb on and off through a bundled shortcut (see below). Long-press it to pick on/off explicitly.
- **Status row** — clock, date, compass heading, battery level and Do Not Disturb.
- **Driving mode** — the screen never dims while PlayCar is open; map controls auto-hide after 4 seconds of inactivity.

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
- Debug builds accept a `-PCDebugNavTo "lat,lon"` launch argument that starts navigation to the given coordinate on launch (debug runs are not saved to Recents).
- To open PlayCar automatically in the car: **Shortcuts › Automation › Bluetooth** → your car → **Open App: PlayCar** → **Run Immediately**.

## Tests

The platform-independent logic (maneuver detection, speed-limit rules, route geometry, distance formats, trip summary, favorites/recents storage, Do Not Disturb URLs) is covered by unit tests that run on a Mac — no simulator or device needed:

```sh
swift test
```

`Package.swift` only exists for these tests; the app is built from the Xcode project. GitHub Actions runs the tests and an iOS Simulator build on every push.

## Project structure

```
PlayCarIOS/
  PlayCarIOSApp.swift            # @main, screen always on, dark mode
  AppDelegate.swift              # landscape orientation lock
  Info.plist                     # permissions, landscape, background modes, playcar:// URL
  PrivacyInfo.xcprivacy          # privacy manifest
  Localizable.xcstrings          # UI strings (en source, tr)
  InfoPlist.xcstrings            # permission texts (tr)
  Resources/
    PlayCar DND.shortcut         # signed Do Not Disturb shortcut (tools/make-dnd-shortcut.py)
  Services/
    LocationManager.swift        # location, speed (km/h), compass
    NavigationStore.swift        # routing, alternatives, step tracking, re-routing, voice
    RouteGeometry.swift          # projection onto the route, turn angles
    Maneuver.swift               # maneuver type from instruction text / geometry
    NavFormat.swift              # distance / duration / time formats (metric & imperial)
    SearchService.swift          # place / address search
    FavoritesStore.swift         # saved places, Home / Work (UserDefaults)
    RecentDestinationsStore.swift# recents + Home/Work travel time
    SpeedLimitStore.swift        # speed-limit estimation (road type + country rules)
    TripStore.swift              # trip distance, driving time, average / top speed
    MusicPlayerManager.swift     # music library, playback, metadata
    CallStore.swift              # call state (incoming/dialing/active) + duration
    ContactsStore.swift          # 4 favorite contacts + system contact picker
    FocusShortcut.swift          # shortcut run / callback URLs
    DoNotDisturbController.swift # Do Not Disturb button, shortcut install
    TelemetryStore.swift         # clock, date, battery
  Views/
    DashboardView.swift          # 65/35 split layout + status row
    MapPanelView.swift           # map screen: search, chips, cards, rail
    CarMapView.swift             # MKMapView wrapper (camera, overlays, gestures)
    NavBannerView.swift          # route preview (alternatives) and turn-by-turn card
    SearchBarView.swift          # search field + results
    QuickDestinationsView.swift  # Home / Work / recent chips, recents list
    FavoritesSheetView.swift     # favorites list, Home / Work
    LocationPermissionBanner.swift
    ManeuverIcon.swift           # maneuver arrow
    SpeedometerView.swift        # speed, limit, gauge, trip summary
    SpeedLimitBadge.swift        # typographic limit
    MediaControlView.swift       # now playing, playlists, tracks
    AudioRoutePicker.swift       # system audio output picker
    FavoriteContactsRow.swift    # 4 favorite contact avatars
    CallPanelView.swift          # call view inside the media card
    DNDSetupView.swift           # one-time Do Not Disturb setup
Tests/PlayCarCoreTests/          # unit tests (swift test)
tools/make-dnd-shortcut.py       # regenerates and signs the shortcut
```

The app follows a simple MVVM structure: each service is an `ObservableObject` with a single responsibility, and views only bind to them.

## Do Not Disturb button

iOS doesn't let apps change Focus modes. PlayCar ships a small signed shortcut, **PlayCar DND**, which turns Do Not Disturb on or off depending on its input. The first time you tap the moon, PlayCar asks you to add it once (Shortcuts shows **Add Shortcut**). After that, each tap runs it through `shortcuts://x-callback-url/run-shortcut` — Shortcuts flashes for a moment and returns to PlayCar via `playcar://dnd/…`.

Signed shortcuts carry an Apple certificate that expires after about a year. To refresh the bundled file, run `python3 tools/make-dnd-shortcut.py` on a Mac signed in to iCloud.

## Localization

Strings live in `PlayCarIOS/Localizable.xcstrings` (source: English) and `PlayCarIOS/InfoPlist.xcstrings` (permission texts). To add a language, open the catalogs in Xcode and add it there.

To use the app in a different language than the phone (e.g. Turkish navigation on an English iPhone): **Settings › Apps › PlayCar › Language**. For voice guidance, install a voice for that language in **Settings › Accessibility › Spoken Content › Voices**.

## Permissions

| Key | Purpose |
|---|---|
| `NSLocationWhenInUseUsageDescription` | Map, navigation, speedometer, speed-limit estimate, trip summary |
| `NSAppleMusicUsageDescription` | Music controls and now-playing info |

Background modes: `location` (navigation keeps running in the background) and `audio` (voice guidance while the screen is locked). Favorite contacts use the system contact picker, so no Contacts permission is requested.

## Privacy

There are no third-party services, analytics or tracking. Maps, search, routing, travel times and road names come from Apple's MapKit, so your location is sent to Apple for those requests. Favorites, recents, contacts shortcuts and settings are stored only on the device in `UserDefaults`.

## Platform notes and limitations

- **Speed limits are estimates.** iOS has no public speed-limit API. The app estimates the limit from the road name/type and legal defaults; posted signs (school zones, roadworks) can differ, so the status line says "Estimated" and the limit can be corrected in one tap.
- **No volume slider.** Apps can't set the system volume; use the car or the iPhone buttons. The output picker chooses where audio plays.
- **Calls can't be controlled.** Third-party apps can't answer, end, or see the caller of a phone call. The app shows call state and duration; answering, ending and speaker are done from the system call banner/screen. Tip: set *Settings › Phone › Incoming Calls* to *Banner* so the dashboard stays visible.
- **Do Not Disturb goes through Shortcuts.** If you change it elsewhere (e.g. Control Center), the moon may show the old state; long-press it to set it explicitly.
- **Not real CarPlay.** The app makes the iPhone screen look like CarPlay. Real CarPlay support (`CarPlay.framework`) needs a separate entitlement from Apple.
- No offline maps.

## License

[MIT](LICENSE)
