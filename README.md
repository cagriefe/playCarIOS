# PlayCar — iPhone için CarPlay Benzeri Yatay Dashboard (SwiftUI, iOS 17+)

Türkçe, landscape-only, koyu-tema sürüş paneli: solda harita (%60), sağda hız + medya + telemetri (%40).

Xcode ile aç: `PlayCarIOS.xcodeproj` → iPhone simülatör/fiziksel cihaz (iOS 17+), scheme: **PlayCarIOS**.

## Proposal'dan düzeltilen kritik hatalar

Orijinal proposal çalışıyordu ama App Store / gerçek cihazda patlayacak 6 hata vardı. Hepsi düzeltildi:

### 1. `km/s` → `km/h` (kritik birim hatası)
- Proposal: *"Real-time speed display in `km/s`"*.
- Gerçek: `CLLocation.speed` **m/s** döner, negatif = geçersiz fix.
- Fix (`Services/LocationManager.swift:34` + `Views/SpeedometerView.swift`):
  ```swift
  speedKmh = rawSpeed >= 0 ? rawSpeed * 3.6 : 0
  ```
  Ekranda `km/h` yazılır. `km/s` ile kalsaydı 120 km/h = 33 km/s gibi saçma değer + limit uyarısı hiç tutmazdı.

### 2. SwiftUI `Map`'te trafik katmanı YOK
- Proposal: *"Traffic layer enabled"* + SwiftUI `Map` istiyordu.
- Gerçek: iOS 17 SwiftUI `Map`'te `showsTraffic` yok. Sadece `MKMapView`'da var.
- Fix (`Views/MapPanelView.swift: CarMapView`): `UIViewRepresentable` ile `MKMapView`, `showsTraffic = true`, `userTrackingMode = .followWithHeading`, 2D/3D pitch toggle, recenter butonu. Trafik toggle'ı kullanıcıya bırakıldı.

### 3. Ses slider'ı yasaktı
- Proposal: *"Volume slider"*.
- Gerçek: `MPMusicPlayerController.volume` deprecated; custom `Slider` sistem sesini değiştirmez, App Store review'da da sorun çıkarır.
- Fix (`Views/MediaControlView.swift: MPVolumeViewRepresentable`): sistemin kendi `MPVolumeView`'i kullanıldı (ses + AirPlay route butonu dahil). "Quick-mute" ayrıca eklenmedi çünkü sistem mute API'si yok — doğru davranış budur.

### 4. MusicKit + MPMusicPlayerController karışıklığı
- Proposal ikisini aynı anda istiyordu.
- Gerçek: kütüphane çaları yönetmek için sadece **MediaPlayer** yeter; MusicKit ayrı entitlement / token / abonelik gerektirir.
- Fix (`Services/MusicPlayerManager.swift`): sadece `MPMusicPlayerController.systemMusicPlayer` + `MPMediaLibrary.requestAuthorization()`. Yetki reddinde fallback UI + "Ayarlar" yönlendirmesi var. MusicKit'e ihtiyaç duyulursa (katalog arama, artwork yüksek çözünürlük) ayrı faz olarak eklenmeli.

### 5. Landscape kilit eksikti
- Proposal: sadece `isIdleTimerDisabled = true` diyordu.
- Gerçek: bu sadece ekran kararması. Portrait'e dönmeyi engellemez.
- Fix:
  - `Info.plist`: `UISupportedInterfaceOrientations` sadece `LandscapeLeft/Right` (iPhone + iPad), `UIRequiresFullScreen = true`.
  - `AppDelegate.swift`: `supportedInterfaceOrientationsFor → .landscape`.
  - Ekran açık tutma kullanıcı ayarına bağlandı (`TelemetryStore.keepScreenOn`, `UserDefaults`), varsayılan ON ama kapatılabilir — sürekli `true` pil + App Store politikası için riskliydi.

### 6. Hız limiti API'si iOS'ta YOK
- Proposal: *"speed limit/warning color states"* — sanki sistemden geliyormuş gibi.
- Gerçek: public hız-limiti API'si yok.
- Fix (`Views/SpeedometerView.swift`): `@AppStorage("speedLimitKmh")` ile kullanıcı ayarlı limit (30–140, Stepper). Renk: normal yeşil, limit-10 turuncu, limit üstü kırmızı + "Hız limitini aştınız!".

### Diğer küçük düzeltmeler / eklemeler
- `Info.plist` Türkçe stringler düzeltildi + eksikler eklendi: `NSLocationAlwaysAndWhenInUseUsageDescription` (opsiyonel arka-plan), `NSMotionUsageDescription`, `UIBackgroundModes (location, audio)`, `CFBundleLocalizations (tr, en)`, `UIUserInterfaceStyle = Dark`.
- Pusula Türkçe kardinal: `K, KD, D, GD, G, GB, B, KB` (`LocationManager.cardinalDirectionTR`).
- Pil: `UIDevice.isBatteryMonitoringEnabled = true` açılmadan `batteryLevel` hep -1 döner — `TelemetryStore` init'te açıldı.
- Arama: `MKLocalSearchCompleter` Türkiye bias (`39.0, 35.0`) + konum etrafında dinamik `updateRegion`, debounce 300ms.
- Dokunma hedefleri: medya butonları 56–68pt (sürüş için min 44pt üstü).
- Mimari MVVM korundu: `LocationManager` / `MusicPlayerManager` / `SearchService` / `TelemetryStore` ayrı, View'lar sadece binding.

## Proje yapısı

```
PlayCarIOS.xcodeproj
PlayCarIOS/
  PlayCarIOSApp.swift      # @main, idle-timer, dark mode
  AppDelegate.swift          # landscape kilit
  Info.plist                 # izinler (TR), landscape, background modes
  Assets.xcassets/
  Services/
    LocationManager.swift    # konum + hız (km/h) + pusula
    MusicPlayerManager.swift # MediaPlayer, izin, metadata
    SearchService.swift      # MKLocalSearchCompleter (TR bias)
    TelemetryStore.swift     # saat/tarih/pil/ekran
  Views/
    DashboardView.swift      # 60/40 split
    MapPanelView.swift       # MKMapView + arama + kontroller
    SpeedometerView.swift    # km/h gauge + limit
    MediaControlView.swift   # artwork + kontroller + MPVolumeView
    TelemetryBarView.swift   # saat/tarih/pil/pusula
```

## Kurulum

1. Xcode 15+ ile `PlayCarIOS.xcodeproj`'u aç.
2. Signing → Team seç, Bundle ID: `com.playcar.ios` (değiştirilebilir).
3. iPhone (iOS 17+) + landscape. Simülatörde konum: Features → Location → City Drive (hız testi için).
4. Müzik widget'ı için cihazda Müzik izni ver; simülatörde "Çalan parça yok" görmen normal.

## İzinler (Info.plist)

| Key | TR açıklama |
|---|---|
| `NSLocationWhenInUseUsageDescription` | Navigasyon, harita takibi ve hız göstergesi için konum erişimi gereklidir. |
| `NSLocationAlwaysAndWhenInUseUsageDescription` | Arka planda da hız ve rota takibi için konum erişimi gereklidir. (İsteğe bağlı.) |
| `NSAppleMusicUsageDescription` | Müzik kontrolü ve çalan parça bilgilerini göstermek için medya arşivi erişimi gereklidir. |
| `NSMotionUsageDescription` | Sürüş algılama ve hız doğruluğunu artırmak için hareket verisi kullanılır. (İsteğe bağlı.) |

## TestFlight yayını (hazır)

Bu repo TestFlight'e yüklenebilir durumda. Bu makinede Xcode olmadığı için son adım (Archive) sende:

### Xcode'da ilk kurulum (bir kez)
1. `PlayCarIOS.xcodeproj` → Signing & Capabilities → **Team** seç (Apple Developer hesabı).
   Bundle ID: `com.playcar.ios` (başkası almışsa örn. `com.<adın>.playcar` yap).
2. Scheme: **PlayCarIOS**, destination: **Any iOS Device (arm64)**.
3. Sürüm: `MARKETING_VERSION = 1.0.0`, build: `CURRENT_PROJECT_VERSION = 1`.
   Her yeni TestFlight yüklemesinde **build numarasını +1 artır** (aynı sürüm+build iki kez yüklenemez).

### Archive → yükleme
1. `Product → Archive` → bitince Organizer açılır → **Distribute App → App Store Connect → Upload**.
2. Signing: Automatic, "Strip Swift symbols" işaretli kalsın.
3. Upload sonrası App Store Connect → TestFlight sekmesinde 5–30 dk içinde build görünür ("Missing Compliance" uyarısı **çıkmayacak** — `ITSAppUsesNonExemptEncryption=false` eklendi, şifreleme kullanılmıyor).

### Bu repo TestFlight için neleri hazır getirdi
- **İkon:** 1024×1024 alpha'sız PNG (`Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png`). Alphasız olması şart, kontrol edildi.
- **Launch screen:** otomatik üretiliyor (`UILaunchScreen_Generation`), ek dosya gerekmez.
- **Privacy manifest** (`PrivacyInfo.xcprivacy`, bundle'a dahil): tracking yok, cihaz dışına veri gönderimi yok, `UserDefaults` için CA92.1 beyanı var. Manifest'siz yükleme 2024'ten beri reddediliyor — eklendi.
- **Background modes:** sadece `location` bırakıldı. `audio` kaldırıldı çünkü uygulama kendisi ses çalmıyor (sistem çaları yönetiyor); gereksiz mod review sorusu çıkarırdı.
- **Landscape-only:** Info.plist + AppDelegate kilidi. iPad'de de landscape.

### Test notları (Beta App Review / test kullanıcıları için)
- Uygulama **sadece yatay** çalışır; dikeyde açılmaz (tasarım gereği).
- Hız göstergesi gerçek GPS ister: test için simülatörde `Features → Location → City Drive`.
- Müzik widget'ı cihazda Apple Music / arşiv izni ister; simülatörde "Çalan parça yok" normaldir.
- Harici (public) TestFlight grubu açarsan gizlilik politikası URL'si zorunlu — dahili testte gerekmez.

### Bilinen review riskleri
- Arka-plan konum (`location` modu): incelemede "neden?" diye sorulabilir. Gerekçe: sürüş sırasında hız takibi. Gerekirse modu Info.plist'ten silip sadece ön-plan konuma düşürebilirsin (hız ibresi arka-planda durur).
- Ekranı açık tutma (`isIdleTimerDisabled`): kullanıcı tarafından kapatılabilir toggle var, varsayılan açık.

## Bilinen limitler / sonraki adımlar

- Rota çizimi + turn-by-turn yok (MapKit `MKDirections` ile eklenebilir).
- Çevrimdışı harita yok.
- Hız limiti otomatik değil (manuel). Gerçek veri için harici kaynak (örn. OpenStreetMap) gerekir.
- CarPlay entegrasyonu yok — bu uygulama iPhone'u CarPlay gibi gösterir, gerçek `CarPlay.framework` ayrı entitlement ister.
