import XCTest
import CoreLocation
@testable import PlayCarCore

final class TripStoreTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    /// Kuzeye `metersNorth` metre, `seconds` saniyede, verilen hızda bir konum.
    private func fix(_ metersNorth: Double, at seconds: TimeInterval, speed: Double,
                     accuracy: Double = 5, speedAccuracy: Double = 1) -> CLLocation {
        CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: 41.0 + metersNorth / 111_195, longitude: 29.0),
            altitude: 0, horizontalAccuracy: accuracy, verticalAccuracy: 5,
            course: 0, courseAccuracy: 5, speed: speed, speedAccuracy: speedAccuracy,
            timestamp: t0.addingTimeInterval(seconds)
        )
    }

    func testAccumulatesDistanceTimeAndSpeeds() {
        let trip = TripStore(now: { self.t0 })
        for i in 0..<10 {
            trip.update(fix(Double(i) * 15, at: Double(i), speed: 15))
        }
        XCTAssertEqual(trip.distance, 135, accuracy: 1)
        XCTAssertEqual(trip.drivingTime, 9, accuracy: 0.001)
        XCTAssertEqual(trip.averageSpeed, 15, accuracy: 0.2)
        XCTAssertEqual(trip.maxSpeed, 15)
    }

    func testIgnoresJitterWhileStopped() {
        let trip = TripStore()
        trip.update(fix(0, at: 0, speed: 0))
        trip.update(fix(5, at: 1, speed: 0.3))
        trip.update(fix(-4, at: 2, speed: 0.2))
        XCTAssertEqual(trip.distance, 0)
        XCTAssertEqual(trip.drivingTime, 0)
    }

    func testSkipsLongGapsJumpsAndBadFixes() {
        let trip = TripStore()
        trip.update(fix(0, at: 0, speed: 15))
        trip.update(fix(300, at: 20, speed: 15))           // 20 sn boşluk (tünel)
        trip.update(fix(1_300, at: 21, speed: 15))         // 1 km / 1 sn sıçrama
        trip.update(fix(1_315, at: 22, speed: 15, accuracy: 120))  // kötü fix
        XCTAssertEqual(trip.distance, 0)
        trip.update(fix(1_330, at: 23, speed: 15))
        XCTAssertEqual(trip.distance, 30, accuracy: 1, "kötü fix atlanır, bir önceki iyi fix'ten ölçülür")
    }

    func testMaxSpeedIgnoresSpikesAndInaccurateSpeeds() {
        let trip = TripStore()
        trip.update(fix(0, at: 0, speed: 20))
        trip.update(fix(20, at: 1, speed: 120))                     // GPS hatası
        trip.update(fix(40, at: 2, speed: 30, speedAccuracy: 10))   // belirsiz hız
        XCTAssertEqual(trip.maxSpeed, 20)
    }

    func testReset() {
        var clock = t0
        let trip = TripStore(now: { clock })
        trip.update(fix(0, at: 0, speed: 15))
        trip.update(fix(15, at: 1, speed: 15))
        clock = t0.addingTimeInterval(600)
        trip.reset()
        XCTAssertEqual(trip.distance, 0)
        XCTAssertEqual(trip.maxSpeed, 0)
        XCTAssertEqual(trip.startDate, clock)
        trip.update(fix(1_000, at: 2, speed: 15))
        XCTAssertEqual(trip.distance, 0, "sıfırlamadan sonra ilk konum yeni başlangıçtır")
    }
}
