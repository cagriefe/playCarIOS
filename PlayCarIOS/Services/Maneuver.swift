import Foundation
import MapKit

/// Navigasyon manevrası. MKRoute.Step manevra tipi vermez; tip
/// Türkçe talimat metninden, bulunamazsa yol geometrisinden çıkarılır.
enum Maneuver: Equatable {
    case depart
    case straight
    case slightLeft, left, sharpLeft
    case slightRight, right, sharpRight
    case keepLeft, keepRight
    case uTurn
    case roundabout(exit: Int?)
    case merge
    case arrive

    var symbol: String {
        switch self {
        case .depart: return "location.north.fill"
        case .straight: return "arrow.up"
        case .slightLeft, .keepLeft: return "arrow.up.left"
        case .slightRight, .keepRight: return "arrow.up.right"
        case .left: return "arrow.turn.up.left"
        case .right: return "arrow.turn.up.right"
        case .sharpLeft: return "arrow.turn.down.left"
        case .sharpRight: return "arrow.turn.down.right"
        case .uTurn: return "arrow.uturn.down"
        case .roundabout: return "arrow.counterclockwise.circle"
        case .merge: return "arrow.merge"
        case .arrive: return "flag.checkered"
        }
    }

    var exitNumber: Int? {
        if case .roundabout(let exit) = self { return exit }
        return nil
    }
}

enum ManeuverClassifier {
    private static let tr = Locale(identifier: "tr_TR")

    /// Metin önceliklidir (Apple'ın kendi tarifi); metin yön içermiyorsa açı kullanılır.
    static func classify(instruction: String, turnAngle: Double?, isLast: Bool) -> Maneuver {
        if isLast { return .arrive }
        if let fromText = fromText(instruction) { return fromText }
        if let turnAngle { return fromAngle(turnAngle) }
        return .straight
    }

    static func fromText(_ instruction: String) -> Maneuver? {
        let t = instruction.lowercased(with: tr)
        guard !t.isEmpty else { return nil }
        if t.contains("varış") || t.contains("hedefe ulaş") || t.contains("hedefe var") { return .arrive }
        if t.contains("u dönüşü") || t.contains("u-dönüşü") || t.contains("geri dönün") { return .uTurn }

        let exit = roundaboutExit(in: t)
        if exit != nil || t.contains("döner kavşak") || t.contains("dönel kavşak") || t.contains("göbek") {
            return .roundabout(exit: exit)
        }

        let right = t.contains("sağa") || t.contains("sağ ")
        let left = t.contains("sola") || t.contains("sol ")
        // Apple: "… istikametine doğru sağdan gidin" = sağdan devam (şerit/yol ayrımı).
        if t.contains("sağdan gid") || t.contains("sağda kal") || t.contains("sağdan devam") || t.contains("sağ şerit") { return .keepRight }
        if t.contains("soldan gid") || t.contains("solda kal") || t.contains("soldan devam") || t.contains("sol şerit") { return .keepLeft }
        if t.contains("hafif") {
            if right { return .slightRight }
            if left { return .slightLeft }
        }
        if t.contains("keskin") {
            if right { return .sharpRight }
            if left { return .sharpLeft }
        }
        if right && !left { return .right }
        if left && !right { return .left }
        if t.contains("katılın") || t.contains("birleş") { return .merge }
        if t.contains("devam") || t.contains("düz") { return .straight }
        return fromEnglishText(t)
    }

    /// Cihaz dili İngilizceyse MapKit talimatları İngilizce gelir (yedek).
    private static func fromEnglishText(_ t: String) -> Maneuver? {
        if t.contains("arrive") || t.contains("destination") { return .arrive }
        if t.contains("u-turn") || t.contains("make a u") { return .uTurn }
        if t.contains("roundabout") {
            let ordinals = ["first": 1, "second": 2, "third": 3, "fourth": 4, "fifth": 5, "sixth": 6]
            let exit = ordinals.first { t.contains("\($0.key) exit") }?.value
            return .roundabout(exit: exit)
        }
        let right = t.contains("right"), left = t.contains("left")
        if t.contains("keep") {
            if right { return .keepRight }
            if left { return .keepLeft }
        }
        if t.contains("bear") || t.contains("slight") {
            if right { return .slightRight }
            if left { return .slightLeft }
        }
        if t.contains("sharp") {
            if right { return .sharpRight }
            if left { return .sharpLeft }
        }
        if t.contains("merge") { return .merge }
        if right && !left { return .right }
        if left && !right { return .left }
        if t.contains("continue") || t.contains("straight") { return .straight }
        return nil
    }

    /// "2. çıkış", "ikinci çıkış" → 2
    static func roundaboutExit(in lowercased: String) -> Int? {
        if let range = lowercased.range(of: #"(\d+)\.\s*çıkış"#, options: .regularExpression) {
            let digits = lowercased[range].prefix { $0.isNumber }
            return Int(digits)
        }
        let words = ["birinci": 1, "ilk": 1, "ikinci": 2, "üçüncü": 3, "dördüncü": 4, "beşinci": 5, "altıncı": 6]
        for (word, n) in words where lowercased.contains("\(word) çıkış") { return n }
        return nil
    }

    /// Açı: + sağ, − sol (derece, −180…180).
    static func fromAngle(_ angle: Double) -> Maneuver {
        let a = abs(angle)
        let right = angle > 0
        switch a {
        case ..<20: return .straight
        case ..<45: return right ? .slightRight : .slightLeft
        case ..<135: return right ? .right : .left
        case ..<165: return right ? .sharpRight : .sharpLeft
        default: return .uTurn
        }
    }

    /// Kuzeyden saat yönünde yön (MKMapPoint: x doğu, y güney).
    static func bearing(from a: MKMapPoint, to b: MKMapPoint) -> Double? {
        let dx = b.x - a.x, dy = b.y - a.y
        guard dx != 0 || dy != 0 else { return nil }
        let deg = atan2(dx, -dy) * 180 / .pi
        return deg < 0 ? deg + 360 : deg
    }

    /// Gelen ve giden yön arasındaki dönüş (−180…180).
    static func turnAngle(inBearing: Double, outBearing: Double) -> Double {
        var d = outBearing - inBearing
        while d > 180 { d -= 360 }
        while d <= -180 { d += 360 }
        return d
    }
}
