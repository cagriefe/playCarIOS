import XCTest
import MapKit
@testable import PlayCarCore

final class ManeuverClassifierTests: XCTestCase {
    /// Apple Haritalar'ın gerçek Türkçe talimatları (Kadıköy → Taksim rotası).
    func testTurkishInstructions() {
        let cases: [(String, Maneuver)] = [
            ("Şahin Cd. istikametine doğru sağa dönün", .right),
            ("Şenol Güneş Blv. istikametine doğru sola dönün", .left),
            ("Turgut Özal Blv. istikametine doğru sağdan gidin", .keepRight),
            ("Çamlıca Girişi-K13 otoyolunda soldan gidin", .keepLeft),
            ("Ataşehir Kavşağı istikametine doğru hafif sola dönün", .slightLeft),
            ("O1-O2 Çamlıca Bağlantısı otoyolu için hafif sağa dönün", .slightRight),
            ("Dönel kavşakta Barbaros Blv. istikametine doğru birinci çıkıştan çıkın", .roundabout(exit: 1)),
            ("Kavşakta 2. çıkıştan çıkın", .roundabout(exit: 2)),
            ("U dönüşü yapın", .uTurn),
            ("Hedefe varıyorsunuz", .arrive),
            ("Varış noktası", .arrive),
        ]
        for (text, expected) in cases {
            XCTAssertEqual(ManeuverClassifier.fromText(text), expected, text)
        }
    }

    /// Cihaz dili İngilizceyken MapKit talimatları İngilizce gelir.
    func testEnglishInstructions() {
        let cases: [(String, Maneuver)] = [
            ("Turn right onto Sahin Cd.", .right),
            ("Turn left onto Senol Gunes Blv.", .left),
            ("Keep left onto Turgut Ozal Blv.", .keepLeft),
            ("Bear right to merge onto O1-O2 Camlica Baglantisi", .slightRight),
            ("At the roundabout, take the first exit onto Barbaros Blv.", .roundabout(exit: 1)),
            ("Make a U-turn", .uTurn),
            ("Arrive at the destination", .arrive),
        ]
        for (text, expected) in cases {
            XCTAssertEqual(ManeuverClassifier.fromText(text), expected, text)
        }
    }

    func testClassifyFallsBackToAngleThenStraight() {
        XCTAssertEqual(ManeuverClassifier.classify(instruction: "", turnAngle: 95, isLast: false), .right)
        XCTAssertEqual(ManeuverClassifier.classify(instruction: "Prepare to park", turnAngle: -30, isLast: false), .slightLeft)
        XCTAssertEqual(ManeuverClassifier.classify(instruction: "", turnAngle: nil, isLast: false), .straight)
        XCTAssertEqual(ManeuverClassifier.classify(instruction: "Sağa dönün", turnAngle: nil, isLast: true), .arrive)
    }

    func testAngleThresholds() {
        XCTAssertEqual(ManeuverClassifier.fromAngle(10), .straight)
        XCTAssertEqual(ManeuverClassifier.fromAngle(-19), .straight)
        XCTAssertEqual(ManeuverClassifier.fromAngle(30), .slightRight)
        XCTAssertEqual(ManeuverClassifier.fromAngle(-30), .slightLeft)
        XCTAssertEqual(ManeuverClassifier.fromAngle(90), .right)
        XCTAssertEqual(ManeuverClassifier.fromAngle(-90), .left)
        XCTAssertEqual(ManeuverClassifier.fromAngle(150), .sharpRight)
        XCTAssertEqual(ManeuverClassifier.fromAngle(-150), .sharpLeft)
        XCTAssertEqual(ManeuverClassifier.fromAngle(175), .uTurn)
    }

    func testBearingIsClockwiseFromNorth() throws {
        let o = MKMapPoint(x: 0, y: 0)
        // MKMapPoint: x doğuya, y güneye artar.
        XCTAssertEqual(try XCTUnwrap(ManeuverClassifier.bearing(from: o, to: MKMapPoint(x: 0, y: -1))), 0, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(ManeuverClassifier.bearing(from: o, to: MKMapPoint(x: 1, y: 0))), 90, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(ManeuverClassifier.bearing(from: o, to: MKMapPoint(x: 0, y: 1))), 180, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(ManeuverClassifier.bearing(from: o, to: MKMapPoint(x: -1, y: 0))), 270, accuracy: 0.001)
        XCTAssertNil(ManeuverClassifier.bearing(from: o, to: o))
    }

    func testTurnAngleWrapsAroundNorth() {
        XCTAssertEqual(ManeuverClassifier.turnAngle(inBearing: 350, outBearing: 10), 20, accuracy: 0.001)
        XCTAssertEqual(ManeuverClassifier.turnAngle(inBearing: 10, outBearing: 350), -20, accuracy: 0.001)
        XCTAssertEqual(ManeuverClassifier.turnAngle(inBearing: 90, outBearing: 0), -90, accuracy: 0.001)
    }

    func testSymbolsAndExitNumber() {
        XCTAssertEqual(Maneuver.right.symbol, "arrow.turn.up.right")
        XCTAssertEqual(Maneuver.roundabout(exit: 3).exitNumber, 3)
        XCTAssertNil(Maneuver.left.exitNumber)
    }
}
