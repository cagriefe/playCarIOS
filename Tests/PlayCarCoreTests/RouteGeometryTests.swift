import XCTest
import MapKit
@testable import PlayCarCore

final class RouteGeometryTests: XCTestCase {
    private let start = CLLocationCoordinate2D(latitude: 41.0, longitude: 29.0)

    /// ~1 km kuzeye düz çizgi.
    private var northLine: StepGeometry {
        StepGeometry(points: [
            MKMapPoint(start),
            MKMapPoint(CLLocationCoordinate2D(latitude: 41.0045, longitude: 29.0)),
            MKMapPoint(CLLocationCoordinate2D(latitude: 41.009, longitude: 29.0)),
        ])
    }

    func testLengthAndPointAlongLine() {
        let line = northLine
        XCTAssertEqual(line.length, 1000, accuracy: 5)
        XCTAssertEqual(line.cumulative.first, 0)
        let mid = line.point(at: line.length / 2).coordinate
        XCTAssertEqual(mid.latitude, 41.0045, accuracy: 0.0001)
        XCTAssertEqual(line.point(at: -10).coordinate.latitude, 41.0, accuracy: 1e-9)
        XCTAssertEqual(line.point(at: 99_999).coordinate.latitude, 41.009, accuracy: 1e-9)
    }

    func testProjectionGivesOffsetAndRemainingAlongRoad() throws {
        let line = northLine
        // Orta noktanın ~20 m doğusu (41° enlemde 1° boylam ≈ 84 km).
        let off = MKMapPoint(CLLocationCoordinate2D(latitude: 41.0045, longitude: 29.0 + 20 / 84_000))
        let result = try XCTUnwrap(line.project(off))
        XCTAssertEqual(result.offset, 20, accuracy: 2)
        XCTAssertEqual(result.remaining, line.length / 2, accuracy: 5)
        XCTAssertNil(StepGeometry(points: [MKMapPoint(start)]).project(off))
    }

    func testTurnAngleRightAndLeft() throws {
        let end = CLLocationCoordinate2D(latitude: 41.009, longitude: 29.0)
        let east = StepGeometry(points: [MKMapPoint(end), MKMapPoint(CLLocationCoordinate2D(latitude: 41.009, longitude: 29.005))])
        let west = StepGeometry(points: [MKMapPoint(end), MKMapPoint(CLLocationCoordinate2D(latitude: 41.009, longitude: 28.995))])
        let right = try XCTUnwrap(StepGeometry.turnAngle(from: northLine, to: east))
        let left = try XCTUnwrap(StepGeometry.turnAngle(from: northLine, to: west))
        XCTAssertEqual(right, 90, accuracy: 2)
        XCTAssertEqual(left, -90, accuracy: 2)
        XCTAssertEqual(ManeuverClassifier.fromAngle(right), .right)
        XCTAssertEqual(ManeuverClassifier.fromAngle(left), .left)
    }
}
