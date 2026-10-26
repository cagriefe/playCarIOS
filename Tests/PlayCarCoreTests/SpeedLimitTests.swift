import XCTest
@testable import PlayCarCore

final class SpeedLimitTests: XCTestCase {
    func testRoadClassifier() {
        let cases: [(String?, RoadClass?)] = [
            ("Şekip Sk.", .urban),
            ("Bağdat Caddesi", .urban),
            ("Barbaros Blv.", .urban),
            ("Main Street", .urban),
            ("D-100", .expressway),
            ("E-5", .expressway),
            ("D400", .expressway),
            ("Kuzey Çevre Yolu", .expressway),
            ("O-4", .motorway),
            ("TEM Otoyolu", .motorway),
            ("O1-O2 Çamlıca Bağlantısı", .motorway),
            ("I-95", .motorway),   // Türkçe küçük harfte "I" → "ı" tuzağı
            ("M25", .motorway),
            ("A 7", .motorway),
            ("Ataşehir Kavşağı", nil),
            (nil, nil),
            ("", nil),
        ]
        for (name, expected) in cases {
            XCTAssertEqual(RoadClassifier.classify(name), expected, name ?? "nil")
        }
    }

    /// KGM tablosu + İçişleri 02.06.2022 yazısı (otomobil).
    func testTurkeyLimits() {
        let cases: [(RoadClass, String?, Bool, Double)] = [
            (.urban, "Şekip Sk.", true, 50),
            (.rural, nil, false, 90),
            (.expressway, "D-100", true, 82),
            (.expressway, "D-100", false, 110),
            (.motorway, "O-1", true, 120),
            (.motorway, "O-2", true, 120),
            (.motorway, "TEM Otoyolu", false, 120),
            (.motorway, "O-20", false, 120),
            (.motorway, "O-3", false, 130),
            (.motorway, "Avrupa Otoyolu", false, 130),
            (.motorway, "O-4", false, 130),
            (.motorway, "Anadolu Otoyolu", false, 130),
            (.motorway, "O-21", false, 130),   // Niğde–Tarsus; Ankara–Niğde adıyla gelirse 140
            (.motorway, "O-31", false, 130),
            (.motorway, "O-32", false, 130),
            (.motorway, "O-52", false, 130),
            (.motorway, "O-5", false, 140),
            (.motorway, "İstanbul-İzmir Otoyolu", false, 140),
            (.motorway, "O-6", false, 140),
            (.motorway, "O-7", false, 140),
            (.motorway, "Kuzey Marmara Otoyolu", false, 140),
            (.motorway, "Ankara-Niğde Otoyolu", false, 140),
        ]
        for (road, name, settled, expected) in cases {
            XCTAssertEqual(CountrySpeedLimits.limit(country: "TR", road: road, roadName: name, inSettlement: settled),
                           expected, "\(name ?? "nil") settled=\(settled)")
        }
    }

    func testOtherCountries() {
        XCTAssertEqual(CountrySpeedLimits.limit(country: "DE", road: .motorway), 130)
        XCTAssertEqual(CountrySpeedLimits.limit(country: "fr", road: .rural), 80)
        XCTAssertEqual(CountrySpeedLimits.limit(country: "GB", road: .motorway) / 1.609344, 70, accuracy: 0.001)
        XCTAssertEqual(CountrySpeedLimits.limit(country: "US", road: .urban) / 1.609344, 25, accuracy: 0.001)
        XCTAssertEqual(CountrySpeedLimits.limit(country: "XX", road: .urban), 50)
        XCTAssertEqual(CountrySpeedLimits.limit(country: nil, road: .motorway), 120)
    }

    func testPresets() {
        XCTAssertTrue(CountrySpeedLimits.presets(country: "TR", imperial: false).contains(82))
        XCTAssertTrue(CountrySpeedLimits.presets(country: "TR", imperial: false).contains(140))
        XCTAssertTrue(CountrySpeedLimits.presets(country: "US", imperial: true).contains(55))
        XCTAssertFalse(CountrySpeedLimits.presets(country: "DE", imperial: false).contains(82))
    }
}
