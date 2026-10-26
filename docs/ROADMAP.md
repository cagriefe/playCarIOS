# PlayCar Yol Haritası

Durum: ✅ yapıldı · ⏭️ bilerek atlandı

## ✅ 7. Favori kişiler + medya panelinde arama kartı
- Hız ile medya arasında 4 favori kişi (sistem kişi seçicisi, rehber izni yok).
- Gelen / aranan / görüşmedeki arama medya kartında; favoriden aranınca ad + foto.
- iOS sınırı: GSM aramasını cevaplama / kapatma / hoparlör sistem afişinden.

## ✅ 1. Manevra okları + "Ardından"
- Manevra tipi Türkçe/İngilizce talimattan, yoksa yol geometrisinden.
- Uygulama dili cihazdan bağımsız seçilebilir (Ayarlar › PlayCar › Dil).

## ✅ 3. Ev / İş + son hedefler
- Birden fazla Ev / İş; çiplerde trafik bilgili süre. Son 8 hedef.

## ✅ 2. Hız limiti tahmini (harici servis yok)
- Apple ters coğrafi kodlama + ülke tablosu. Türkiye: KGM tablosu + İçişleri
  02.06.2022 yazısı — 50 / yerleşim içi bölünmüş 82 / 90 / 110 / otoyol 120,
  O-3·O-4·O-21·O-31·O-32·O-51·O-52 130, O-5·O-6·O-7 ve Ankara–Niğde 140.
- Belirsizlikte düşük değer; tipografik limit göstergesi, tek dokunuşla düzeltme.

## ⏭️ 4. Kilit ekranı / Dynamic Island / Siri
- Gerek görülmedi: iPhone 13 Pro'da Dynamic Island yok, ekran zaten hep açık,
  sesli yönlendirme arka planda çalışıyor. Araca binince açılma Kestirmeler
  otomasyonuyla (Bluetooth → PlayCar'ı aç) kodsuz çözüldü.

## ✅ 6. Bonus
- ✅ Alternatif rotalar: önizlemede 3'e kadar rota, kartlardan veya gri çizgiye dokunarak seçim.
- ✅ Yolculuk özeti: mesafe, sürüş süresi, ortalama / en yüksek hız (hıza dokun).
- ✅ Ses çıkışı seçici (Bluetooth / hoparlör / AirPlay) medya kartında.
- ⏭️ CoreMotion sürüş algılama: Bluetooth otomasyonu aynı işi görüyor.
- ⏭️ Sesle adres arama: klavyedeki dikte zaten var.

## ✅ Ek: Ekran ve Rahatsız Etme
- PlayCar açıkken ekran hiç kararmaz (kilit düğmesi kaldırıldı).
- Ay düğmesi Rahatsız Etme'yi uygulamayla gelen imzalı "PlayCar DND" kestirmesiyle
  açar / kapatır (iOS uygulamalara doğrudan izin vermez); ilk seferde tek onay.

## ✅ 5. Kod sağlığı
- MapPanelView bölündü: CarMapView, NavBannerView, SearchBarView, FavoritesSheetView,
  LocationPermissionBanner; NavFormat ve RouteGeometry ayrı, test edilebilir dosyalar.
- `swift test` ile 30 birim testi (Mac'te, cihaz/simülatör gerekmez) + GitHub Actions CI.
- Kullanılmayan izin metinleri (her zaman konum, hareket) kaldırıldı; README güncel.
- `Localizable.xcstrings` (kaynak en + tr), bölgeye göre km/h–mph, saat ve tarih.

## Sonraki fikirler
- Kestirme imzası ~1 yılda bir yenilenmeli: `python3 tools/make-dnd-shortcut.py`.
- Gerçek CarPlay desteği (Apple'dan CarPlay navigasyon yetkisi gerekir).
