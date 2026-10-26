import Foundation

/// Mesafe / süre / saat biçimleri: bölgeye göre metrik (km, m) veya
/// İngiliz-Amerikan (mi, ft); konuşma metinleri uygulama dilinde.
/// `imperial` ve `locale` parametreleri testler içindir.
enum NavFormat {
    /// ABD ve İngiltere'de yol mesafeleri mil, hızlar mph.
    static var usesImperial: Bool {
        let system = Locale.current.measurementSystem
        return system == .us || system == .uk
    }

    private static func decimal(_ value: Double, _ locale: Locale) -> String {
        value.formatted(.number.precision(.fractionLength(1)).locale(locale))
    }

    /// Ekran: "350 m" / "2,3 km" — "500 ft" / "0.3 mi" (yerel ondalık ayırıcı).
    static func distance(_ meters: Double, imperial: Bool = usesImperial, locale: Locale = .current) -> String {
        if imperial {
            let miles = meters / 1609.344
            if miles < 0.1 {
                let feet = max(50, Int((meters * 3.28084 / 50).rounded()) * 50)
                return "\(feet) ft"
            }
            return miles < 10 ? "\(decimal(miles, locale)) mi" : "\(Int(miles.rounded())) mi"
        }
        if meters < 950 {
            return "\(Int(meters.rounded())) m"
        }
        return "\(decimal(meters / 1000, locale)) km"
    }

    /// Sesli okunuş: "300 metre" / "300 meters", "1,5 kilometre", "500 feet", "2 miles".
    static func spokenDistance(_ meters: Double, imperial: Bool = usesImperial, locale: Locale = .current) -> String {
        if imperial {
            let miles = meters / 1609.344
            if miles < 0.1 {
                let feet = max(50, Int((meters * 3.28084 / 50).rounded()) * 50)
                return String(localized: "\(feet) feet", comment: "Spoken distance")
            }
            let rounded = (miles * 10).rounded() / 10
            if rounded == rounded.rounded() {
                return String(localized: "\(Int(rounded)) miles", comment: "Spoken distance, whole miles")
            }
            return String(localized: "\(decimal(rounded, locale)) miles", comment: "Spoken distance, decimal miles")
        }
        if meters < 950 {
            let rounded = max(50, Int((meters / 50).rounded()) * 50)
            return String(localized: "\(rounded) meters", comment: "Spoken distance")
        }
        let km = (meters / 100).rounded() / 10
        if km == km.rounded() {
            return String(localized: "\(Int(km)) kilometers", comment: "Spoken distance, whole kilometers")
        }
        return String(localized: "\(decimal(km, locale)) kilometers", comment: "Spoken distance, decimal kilometers")
    }

    /// "In 300 meters, turn right" / "300 metre sonra, sağa dönün".
    static func spokenIn(_ meters: Double, _ instruction: String) -> String {
        String(localized: "In \(spokenDistance(meters)), \(instruction)", comment: "Spoken: distance, then maneuver")
    }

    /// Bölgeye göre 24 saat ya da 12 saat (AM/PM).
    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("jmm")
        return f
    }()

    static func time(_ date: Date) -> String {
        timeFormatter.string(from: date)
    }

    private static let durationFormatter: DateComponentsFormatter = {
        let f = DateComponentsFormatter()
        f.unitsStyle = .abbreviated
        f.allowedUnits = [.hour, .minute]
        f.maximumUnitCount = 2
        return f
    }()

    /// Yolculuk süresi, dakikaya yuvarlanmış: "23 dk" / "23 min", "1 sa 5 dk" / "1 hr, 5 min".
    static func duration(_ seconds: TimeInterval) -> String {
        durationFormatter.string(from: max(60, (seconds / 60).rounded() * 60)) ?? ""
    }
}
