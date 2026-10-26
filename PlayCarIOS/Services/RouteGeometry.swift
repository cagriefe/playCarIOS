import Foundation
import MapKit

/// Bir rota adımının çizgisi: noktalar + başlangıçtan itibaren birikimli
/// uzunluk (m). Navigasyonda konumu rotaya izdüşürmek ve dönüş açısını
/// bulmak için kullanılır (kuş uçuşu değil, çizgi üzerinden ölçüm).
struct StepGeometry {
    let points: [MKMapPoint]
    let cumulative: [Double]
    var length: Double { cumulative.last ?? 0 }

    init(points: [MKMapPoint]) {
        var cum: [Double] = []
        cum.reserveCapacity(points.count)
        var total = 0.0
        for (i, pt) in points.enumerated() {
            if i > 0 { total += points[i - 1].distance(to: pt) }
            cum.append(total)
        }
        self.points = points
        self.cumulative = cum
    }

    init(polyline: MKPolyline) {
        self.init(points: Array(UnsafeBufferPointer(start: polyline.points(), count: polyline.pointCount)))
    }

    /// Çizgi boyunca `distance` metredeki nokta (doğrusal ara değer).
    func point(at distance: Double) -> MKMapPoint {
        guard let first = points.first else { return MKMapPoint() }
        guard distance > 0 else { return first }
        for i in 1..<points.count where cumulative[i] >= distance {
            let segment = cumulative[i] - cumulative[i - 1]
            let t = segment > 0 ? (distance - cumulative[i - 1]) / segment : 0
            let a = points[i - 1], b = points[i]
            return MKMapPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
        }
        return points[points.count - 1]
    }

    /// Konumun çizgiye dik uzaklığı ve çizgi boyunca kalan uzunluk (m).
    func project(_ p: MKMapPoint) -> (offset: Double, remaining: Double)? {
        guard points.count > 1 else { return nil }
        var bestOffset = Double.greatestFiniteMagnitude
        var bestAlong = 0.0
        for i in 0..<(points.count - 1) {
            let a = points[i], b = points[i + 1]
            let dx = b.x - a.x, dy = b.y - a.y
            let len2 = dx * dx + dy * dy
            var t = len2 > 0 ? ((p.x - a.x) * dx + (p.y - a.y) * dy) / len2 : 0
            t = min(max(t, 0), 1)
            let proj = MKMapPoint(x: a.x + t * dx, y: a.y + t * dy)
            let d = p.distance(to: proj)
            if d < bestOffset {
                bestOffset = d
                bestAlong = cumulative[i] + a.distance(to: proj)
            }
        }
        return (bestOffset, max(length - bestAlong, 0))
    }

    /// Bir adımdan sonrakine geçişteki dönüş açısı (+ sağ, − sol): gelen adımın
    /// son ~30 m'lik yönü ile giden adımın ilk ~30 m'lik yönü arasındaki fark.
    static func turnAngle(from incoming: StepGeometry, to outgoing: StepGeometry) -> Double? {
        guard incoming.length >= 1, outgoing.length >= 1,
              let inBearing = ManeuverClassifier.bearing(
                from: incoming.point(at: max(incoming.length - 30, 0)),
                to: incoming.point(at: incoming.length)),
              let outBearing = ManeuverClassifier.bearing(
                from: outgoing.point(at: 0),
                to: outgoing.point(at: min(30, outgoing.length)))
        else { return nil }
        return ManeuverClassifier.turnAngle(inBearing: inBearing, outBearing: outBearing)
    }
}
