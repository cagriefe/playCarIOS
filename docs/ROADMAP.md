# PlayCar Yol Haritası

Uygulama sırası: **7 → 1 → 3 → 2 → 4 → 6 → 5** (7 kullanıcı isteğiyle önce).

---

## 7. Favori kişiler + medya panelinde arama kartı ✅ (ilk iş)

**Hedef:** Sağ sütunda 4 favori kişi tek dokunuşla aranabilsin; arama gelince/sürerken
medya kartı arama görünümüne geçsin.

**iOS kısıtı (kesin):** Üçüncü parti uygulama GSM aramasını cevaplayamaz, kapatamaz,
hoparlöre alamaz, arayanın numarasını göremez. Bu işlemler sistem arama
afişinden/ekranından yapılır. Uygulama arka planda değil, önde kalsın diye kullanıcıya
*Ayarlar › Uygulamalar › Telefon › Gelen Aramalar › Afiş* önerilir.

**Yapılacaklar**
- `Services/ContactsStore.swift`
  - `FavoriteContact` (ad, kısa ad, numara, etiket, 96 px JPEG foto, baş harfler) — Codable.
  - `FavoriteContactsStore`: 4 sabit slot, UserDefaults (`favoriteContacts.v1`).
  - `ContactPicker`: `CNContactPickerViewController` (rehber izni GEREKMEZ),
    tek numaralı kişi direkt seçilir, çok numaralıda numara seçtirilir.
  - Arama: `tel://` URL (iOS kendi onay penceresini gösterir).
- `Services/CallStore.swift` → faz modeli: `idle / incoming / dialing / active / onHold`,
  çağrı UUID'sine göre bağlanma zamanı, bekleyen arama (call waiting) önceliği.
  Bizim başlattığımız giden aramada (20 sn içinde) kişi adı + fotoğrafı eşleştirilir.
- `Views/FavoriteContactsRow.swift`: hız kartı ile medya kartı arasında 4 yuvarlak avatar.
  Boş slot `+` → kişi seç; dolu slot dokun → ara; uzun bas → Ara / Değiştir / Kaldır.
- `Views/CallPanelView.swift`: medya kartı içinde arama görünümü (avatar, ad/durum,
  büyük süre, yönlendirme metni, Gizle). Gizlenince medya kartında yeşil süre hapı.
- `MapPanelView`: harita üstündeki eski arama kartı kaldırılır.
- Yer açmak için hız kartı ve medya kartı biraz sıkılaştırılır.

---

## 1. Manevra okları + "Ardından" satırı

- `NavigationStore`: her adım için `Maneuver` (düz, hafif/normal/keskin sağ-sol, U dönüşü,
  kavşak çıkışı, varış). Kaynak: (a) Türkçe talimat metni kalıpları ("sağa", "hafif sola",
  "döner kavşak", "2. çıkış", "U dönüşü"), (b) bulunamazsa geometri — adım i son 30 m yönü
  ile adım i+1 ilk 30 m yönü arasındaki açı.
- `@Published nextManeuver`, `followingInstruction` (sonraki manevra < 150 m ise).
- `navBanner` yeniden tasarım: solda 56 pt ok ikonu + altında mesafe, sağda sokak/talimat,
  altta küçük "Ardından ↰ …" şeridi.
- Test: açı → manevra sınıflandırma birim testleri (madde 5'teki test hedefiyle).

## 3. Ev/İş kısayolları + son hedefler

- `FavoritePlace.kind: home/work/other` (Codable geriye uyumlu, varsayılan `.other`).
- `RecentDestinationsStore`: son 8 hedef (aynı koordinat tekilleştirilir), navigasyon
  başlayınca kaydedilir.
- Arama çubuğu odaklı ve boşken: üstte büyük Ev / İş butonları, altında son hedefler.
- Ev/İş butonunda `MKDirections.calculateETA` ile süre ("Ev · 23 dk"), 5 dk önbellek.
- Favoriler sayfasında "Ev olarak ayarla / İş olarak ayarla".

## 2. Otomatik hız limiti

- `SpeedLimitService`: Overpass API `way(around:25,lat,lon)[highway][maxspeed]`,
  her 300 m ya da 30 sn'de bir, 1 km yarıçaplı önbellek, ağ hatasında son değer.
- Etiket yoksa yol tipinden Türkiye varsayılanı (residential 50, primary/secondary/trunk 90,
  bölünmüş trunk 110, motorway 120).
- `SpeedometerView`: Stepper kaldırılır; yuvarlak kırmızı çerçeveli limit rozeti,
  "OTO / ELLE" göstergesi; rozete dokununca büyük butonlu limit seçici.
- Ayar: "Hız limitini internetten al" (varsayılan açık) + README gizlilik notu güncellemesi.

## 4. Live Activity / Dynamic Island + Siri (App Intents)

- Yeni Widget Extension hedefi `PlayCarWidgets` (ActivityKit). `NavActivityAttributes`:
  manevra ikonu, mesafe, talimat, varış saati. Güncelleme: adım değişince ve her 100 m'de
  (ActivityKit bütçesi için kısıtlı).
- `NavigationStore` → `LiveActivityController` (başlat/güncelle/bitir).
- App Intents: `NavigateHomeIntent`, `NavigateWorkIntent`, `NavigateToFavoriteIntent`
  (favori parametresi `AppEntity`), `StopNavigationIntent`; `AppShortcutsProvider` ile
  Türkçe Siri cümleleri. Uygulama içi işleme için paylaşılan `AppRouter` (intent → store).
- Kestirmeler otomasyonu örneği README'ye: "Araç Bluetooth'una bağlanınca PlayCar'ı aç".

## 6. Bonus paketi

- **Yolculuk bilgisayarı** (`TripStore`): mesafe, süre, ortalama/maks hız; uygulama açılınca
  ya da navigasyon başlayınca sıfırlanır. Hız kartına dokununca arka yüzde gösterilir.
- **CoreMotion sürüş algılama:** `CMMotionActivityManager` `automotive` → ekranı açık tut +
  kontrolleri gizle; durunca normal. (Info.plist'teki Motion izni böylece gerçekten kullanılır.)
- **Alternatif rotalar:** `requestsAlternateRoutes = true`; önizlemede gri alternatifler,
  dokununca seçilir, kartta süre farkı ("+4 dk").
- **Sesli arama:** arama çubuğunda mikrofon → `SFSpeechRecognizer(tr-TR)`; izin metinleri eklenir.

## 5. Kod sağlığı

- Bölme: `CarMapView.swift`, `NavBannerView.swift`, `SearchBarView` ayrı dosya;
  `NavigationStore`/`SearchService`/`FavoritesStore` `DashboardView`'a (veya `AppModel`'e) taşınır.
- `PlayCarIOSTests` hedefi: `NavFormat`, `project()`, adım ilerleme, sapma kuralı,
  manevra sınıflandırma, `CallStore` faz eşlemesi.
- README ↔ kod: `MPVolumeView` ya eklenir (AVRoutePickerView ile ses çıkışı) ya README'den
  çıkarılır; kullanılmayan "Always" konum izni metni kaldırılır.
- `Localizable.xcstrings` (tr + en) — tüm sabit metinler.
