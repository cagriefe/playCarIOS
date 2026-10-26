import XCTest
@testable import PlayCarCore

final class NavFormatTests: XCTestCase {
    private let us = Locale(identifier: "en_US")
    private let tr = Locale(identifier: "tr_TR")

    func testMetricDistance() {
        XCTAssertEqual(NavFormat.distance(350, imperial: false, locale: us), "350 m")
        XCTAssertEqual(NavFormat.distance(2_345, imperial: false, locale: us), "2.3 km")
        XCTAssertEqual(NavFormat.distance(2_345, imperial: false, locale: tr), "2,3 km")
    }

    func testImperialDistance() {
        XCTAssertEqual(NavFormat.distance(30, imperial: true, locale: us), "100 ft")
        XCTAssertEqual(NavFormat.distance(1_609.344 * 2.26, imperial: true, locale: us), "2.3 mi")
        XCTAssertEqual(NavFormat.distance(1_609.344 * 12.4, imperial: true, locale: us), "12 mi")
    }

    /// Katalog olmadan anahtar (İngilizce) döner; yuvarlama kuralları sınanır.
    func testSpokenDistanceRounding() {
        XCTAssertEqual(NavFormat.spokenDistance(320, imperial: false, locale: us), "300 meters")
        XCTAssertEqual(NavFormat.spokenDistance(10, imperial: false, locale: us), "50 meters")
        XCTAssertEqual(NavFormat.spokenDistance(2_000, imperial: false, locale: us), "2 kilometers")
        XCTAssertEqual(NavFormat.spokenDistance(1_530, imperial: false, locale: us), "1.5 kilometers")
        XCTAssertEqual(NavFormat.spokenDistance(120, imperial: true, locale: us), "400 feet")
        XCTAssertEqual(NavFormat.spokenDistance(1_609.344 * 3, imperial: true, locale: us), "3 miles")
    }

    func testDurationRoundsToMinutes() {
        XCTAssertTrue(NavFormat.duration(23 * 60 + 10).contains("23"))
        XCTAssertTrue(NavFormat.duration(5).contains("1"), "en az 1 dakika")
    }

    func testTripFormat() {
        XCTAssertEqual(TripFormat.distance(12_440, imperial: false, locale: tr).value, "12,4")
        XCTAssertEqual(TripFormat.distance(128_400, imperial: false, locale: tr).value, "128")
        XCTAssertEqual(TripFormat.distance(1_609.344 * 7.7, imperial: true, locale: us).unit, "mi")
        XCTAssertEqual(TripFormat.speed(25, imperial: false), 90)
        XCTAssertEqual(TripFormat.speed(25, imperial: true), 56)
        XCTAssertEqual(TripFormat.drivingTime(23 * 60), "0:23")
        XCTAssertEqual(TripFormat.drivingTime(107 * 60 + 30), "1:47")
    }
}
