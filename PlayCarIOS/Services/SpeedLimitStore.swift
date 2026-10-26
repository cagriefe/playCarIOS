import Foundation
import CoreLocation
import Combine

/// Yol sınıfı: limit tablosundaki sütun. Sıra = yükseltme sırası.
enum RoadClass: Int, Comparable, CaseIterable {
    case urban
    case rural
    case expressway
    case motorway

    static func < (a: RoadClass, b: RoadClass) -> Bool { a.rawValue < b.rawValue }

    var title: String {
        switch self {
        case .urban: return String(localized: "Urban road")
        case .rural: return String(localized: "Rural road")
        case .expressway: return String(localized: "Divided highway")
        case .motorway: return String(localized: "Motorway")
        }
    }
}

/// Yol adından sınıf: "O-4", "… otoyolu", "M25", "I-95" → otoyol;
/// "D-100", "E-5", "çevre yolu" → bölünmüş yol; "Cd.", "Sk.", "Street" → şehir içi.
/// Ad tanınmazsa nil (hıza göre karar verilir).
enum RoadClassifier {
    static func classify(_ name: String?) -> RoadClass? {
        guard let raw = name?.trimmingCharacters(in: .whitespaces), !raw.isEmpty else { return nil }
        let n = raw.lowercased(with: Locale(identifier: "tr_TR"))
        // Yol kodları büyük harfle kontrol edilir (Türkçe küçük harfte "I" → "ı" olur).
        let code = raw.uppercased(with: Locale(identifier: "en_US_POSIX"))

        if code.range(of: #"^(O|A|M|I)[- ]?\d+"#, options: .regularExpression) != nil { return .motorway }
        let motorway = ["otoyol", "otoban", "motorway", "autobahn", "autoroute", "autostrada",
                        "autopista", "autoestrada", "freeway", "interstate", "snelweg", "motorväg", "motorvej"]
        if motorway.contains(where: n.contains) { return .motorway }

        if code.range(of: #"^(D|E|N|B|US|SR)[- ]?\d+"#, options: .regularExpression) != nil { return .expressway }
        let expressway = ["çevre yolu", "çevreyolu", "devlet yolu", "bağlantı yolu", "expressway",
                          "highway", "schnellstraße", "voie rapide", "superstrada", "autovía"]
        if expressway.contains(where: n.contains) { return .expressway }

        let urban = ["cadde", "cd.", "sokak", "sokağı", "sk.", "bulvar", "blv", "meydan",
                     "street", "st.", "avenue", "ave", "lane", "boulevard", "drive", "place", "square",
                     "straße", "strasse", "gasse", "platz", "rue ", "via ", "viale", "piazza",
                     "calle", "plaza", "rua ", "straat", "laan", "gatan", "vej"]
        if urban.contains(where: n.contains) { return .urban }
        return nil
    }
}

/// Ülkelere göre yasal genel limitler (km/h): şehir içi, şehir dışı,
/// bölünmüş yol, otoyol. Tabela farklı olabilir — sadece tahmin.
enum CountrySpeedLimits {
    private static let mph = 1.609344

    private static let table: [String: [Double]] = [
        "TR": [50, 90, 110, 120],     // ayrıntı: TurkeySpeedLimits
        "DE": [50, 100, 120, 130],   // otoyolda tavsiye edilen hız
        "AT": [50, 100, 100, 130],
        "CH": [50, 80, 100, 120],
        "FR": [50, 80, 110, 130],
        "IT": [50, 90, 110, 130],
        "ES": [50, 90, 100, 120],
        "PT": [50, 90, 100, 120],
        "NL": [50, 80, 100, 100],
        "BE": [50, 70, 120, 120],
        "PL": [50, 90, 120, 140],
        "GR": [50, 90, 110, 130],
        "BG": [50, 90, 120, 140],
        "RO": [50, 90, 100, 130],
        "SE": [50, 70, 100, 110],
        "NO": [50, 80, 90, 110],
        "DK": [50, 80, 90, 130],
        "IE": [50, 80, 100, 120],
        "GB": [30 * mph, 60 * mph, 70 * mph, 70 * mph],
        "US": [25 * mph, 55 * mph, 65 * mph, 65 * mph],
    ]
    private static let fallback: [Double] = [50, 90, 100, 120]

    static func limit(country: String?, road: RoadClass, roadName: String? = nil, inSettlement: Bool = false) -> Double {
        if country?.uppercased() == "TR" {
            return TurkeySpeedLimits.limit(road: road, roadName: roadName, inSettlement: inSettlement)
        }
        let row = country.flatMap { table[$0.uppercased()] } ?? fallback
        return row[road.rawValue]
    }

    /// Hızlı seçim butonları (görüntü biriminde).
    static func presets(country: String?, imperial: Bool) -> [Int] {
        if imperial { return [20, 25, 30, 35, 40, 45, 50, 55, 60, 65, 70, 75] }
        switch country?.uppercased() {
        case "TR": return [20, 30, 50, 70, 82, 90, 100, 110, 120, 130, 140]
        default: return [30, 50, 60, 70, 80, 90, 100, 110, 120, 130]
        }
    }
}

/// Türkiye, otomobil (M1). Kaynak: KGM "Yasal Hız Sınırları" tablosu ve
/// İçişleri Bakanlığı'nın 02.06.2022 tarihli yazısı (otoyol limit artışı).
/// - Yerleşim yeri içi 50; il trafik komisyonu bölünmüş yollarda 82'ye kadar
///   artırabilir (İstanbul E-5/D-100 gibi) → yerleşim içindeki bölünmüş yolda 82.
/// - Şehirlerarası çift yönlü 90, bölünmüş yol 110.
/// - Otoyol genel 120; listelenen KGM otoyolları 130, YİD otoyolları 140.
/// Emin olunamayan durumda düşük değer seçilir (yanlış güven vermemek için).
enum TurkeySpeedLimits {
    /// 140: Gebze–İzmir (O-5), Malkara–Çanakkale (O-6), Kuzey Marmara (O-7).
    private static let codes140: Set<Int> = [5, 6, 7]
    /// 130: Edirne–İstanbul (O-3), İstanbul–Ankara (O-4), Niğde–Tarsus (O-21; aynı
    /// koddaki Ankara–Niğde YİD 140 ama ayırt edilemez → düşük olan), İzmir–Aydın
    /// (O-31), İzmir–Çeşme (O-32), Tarsus–Adana–Gaziantep–Şanlıurfa (O-51, O-52).
    private static let codes130: Set<Int> = [3, 4, 21, 31, 32, 51, 52]
    private static let names140 = ["kuzey marmara", "istanbul-izmir", "istanbul–izmir", "gebze-orhangazi",
                                   "gebze-izmir", "malkara", "ankara-niğde", "ankara–niğde"]
    private static let names130 = ["anadolu otoyolu", "avrupa otoyolu", "edirne-istanbul", "istanbul-ankara",
                                   "izmir-aydın", "izmir-çeşme", "çeşme otoyolu", "niğde-mersin", "tarsus-adana",
                                   "adana-gaziantep", "gaziantep-şanlıurfa"]

    static func limit(road: RoadClass, roadName: String?, inSettlement: Bool) -> Double {
        switch road {
        case .urban: return 50
        case .rural: return 90
        case .expressway: return inSettlement ? 82 : 110
        case .motorway: return motorwayLimit(roadName)
        }
    }

    static func motorwayLimit(_ name: String?) -> Double {
        guard let name else { return 120 }
        let n = name.lowercased(with: Locale(identifier: "tr_TR"))
        if names140.contains(where: n.contains) { return 140 }
        if names130.contains(where: n.contains) { return 130 }
        let code = name.uppercased(with: Locale(identifier: "en_US_POSIX"))
        if let r = code.range(of: #"^O[- ]?\d+"#, options: .regularExpression),
           let number = Int(code[r].filter(\.isNumber)) {
            if codes140.contains(number) { return 140 }
            if codes130.contains(number) { return 130 }
        }
        // O-1, O-2 (İstanbul şehir içi), O-20, O-30… ve tanınmayan otoyollar.
        return 120
    }
}

/// Bulunulan yolun hız limiti tahmini (harici servis yok: Apple ters
/// coğrafi kodlama + ülke tablosu) ve kullanıcının elle düzeltmesi.
final class SpeedLimitStore: ObservableObject {
    enum Source: Equatable {
        case estimated
        /// Kullanıcı bu yol için seçti (yol değişince tahmine döner).
        case override
        /// Otomatik kapalı: kalıcı elle limit.
        case manual
    }

    /// Kapalıyken eski davranış: kalıcı elle limit.
    @Published var autoEnabled: Bool {
        didSet {
            UserDefaults.standard.set(autoEnabled, forKey: "speedLimitAuto")
            if !autoEnabled { overrideKmh = nil }
        }
    }
    @Published private(set) var estimateKmh: Double?
    @Published private(set) var overrideKmh: Double?
    @Published private(set) var roadClass: RoadClass?
    @Published private(set) var roadName: String?
    @Published private(set) var countryCode: String?

    private let geocoder = CLGeocoder()
    private var geocoding = false
    private var lastGeocode: (at: Date, location: CLLocation)?
    private var backoffUntil = Date.distantPast
    /// Adres servisi otoyolda yan sokağı döndürebilir: tahminin çok üstünde
    /// sürekli gidiliyorsa sınıf bir üst seviyeye çıkarılır.
    private var baseClass: RoadClass?
    /// Adres servisi mahalle / bina numarası döndürdüyse yerleşim yeri içi.
    private var inSettlement = false
    private var baseInSettlement = false
    private var upgrades = 0
    private var overSpeedFixes = 0

    init() {
        autoEnabled = UserDefaults.standard.object(forKey: "speedLimitAuto") as? Bool ?? true
    }

    func setOverride(kmh: Double) { overrideKmh = kmh }
    func clearOverride() { overrideKmh = nil }

    func update(_ location: CLLocation) {
        guard autoEnabled else { return }
        checkSustainedSpeed(location)

        guard !geocoding, location.horizontalAccuracy >= 0, location.horizontalAccuracy < 65,
              Date() >= backoffUntil else { return }
        if let last = lastGeocode,
           Date().timeIntervalSince(last.at) < 15 || location.distance(from: last.location) < 250 {
            return
        }
        geocoding = true
        lastGeocode = (Date(), location)
        geocoder.reverseGeocodeLocation(location) { [weak self] placemarks, error in
            DispatchQueue.main.async {
                guard let self else { return }
                self.geocoding = false
                if error != nil {
                    // Kota / ağ hatası: bir dakika bekle, son tahmin kalsın.
                    self.backoffUntil = Date().addingTimeInterval(60)
                    return
                }
                guard let pm = placemarks?.first else { return }
                self.apply(pm, speed: location.speed)
            }
        }
    }

    private func apply(_ pm: CLPlacemark, speed: CLLocationSpeed) {
        let name = pm.thoroughfare
        countryCode = pm.isoCountryCode ?? countryCode
        if name != roadName {
            roadName = name
            overrideKmh = nil
            upgrades = 0
            overSpeedFixes = 0
        }
        baseInSettlement = pm.subLocality != nil || pm.subThoroughfare != nil
        let fromName = RoadClassifier.classify(name)
        let base: RoadClass
        if let fromName {
            base = fromName
        } else if baseInSettlement {
            base = .urban
        } else if name == nil {
            base = .rural // yerleşim dışında genelde yol adı yok
        } else {
            // Ad tanınmadı: şehir içi limitin belirgin üstündeysek şehir dışı.
            let urban = CountrySpeedLimits.limit(country: countryCode, road: .urban)
            base = speed * 3.6 > urban + 15 ? .rural : .urban
        }
        baseClass = base
        recompute()
    }

    /// Yükseltme: önce "yerleşim yeri dışı" varsayılır (82 → 110), sonra sınıf artar.
    private func recompute() {
        guard let baseClass else { return }
        var steps = upgrades
        inSettlement = baseInSettlement
        if inSettlement, steps > 0 {
            inSettlement = false
            steps -= 1
        }
        let cls = RoadClass(rawValue: min(baseClass.rawValue + steps, RoadClass.motorway.rawValue)) ?? baseClass
        roadClass = cls
        estimateKmh = CountrySpeedLimits.limit(country: countryCode, road: cls,
                                               roadName: roadName, inSettlement: inSettlement)
        #if DEBUG
        print("PCDBG LIMIT country=\(countryCode ?? "-") road='\(roadName ?? "-")' class=\(cls) settlement=\(inSettlement) upgrades=\(upgrades) est=\(Int(estimateKmh ?? 0))")
        #endif
    }

    private func checkSustainedSpeed(_ location: CLLocation) {
        guard overrideKmh == nil, let estimateKmh, let roadClass, roadClass < .motorway || inSettlement,
              location.speed >= 0 else { overSpeedFixes = 0; return }
        if location.speed * 3.6 > estimateKmh * 1.35 + 5 {
            overSpeedFixes += 1
        } else {
            overSpeedFixes = 0
        }
        if overSpeedFixes >= 8 {
            overSpeedFixes = 0
            upgrades += 1
            recompute()
        }
    }
}
