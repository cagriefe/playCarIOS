import SwiftUI

/// CarPlay tarzı hız kartı: yatay düzen, solda büyük rakam,
/// sağda limit + ince gauge + durum. Yuvarlak yüzen kart.
struct SpeedometerView: View {
    @ObservedObject var location: LocationManager

    /// Kullanıcı ayarlı hız limiti (iOS'ta public hız-limiti API'si yok).
    /// Birim bölgeye göre: km/h veya mph (ayrı saklanır, dönüşüm yuvarlaması olmasın).
    @AppStorage("speedLimitKmh") private var speedLimitKmh: Double = 90
    @AppStorage("speedLimitMph") private var speedLimitMph: Double = 55

    private let imperial = NavFormat.usesImperial
    private var unitLabel: String { imperial ? "mph" : "km/h" }
    private var speed: Double { imperial ? location.speedKmh / 1.609344 : location.speedKmh }
    private var speedLimit: Double { imperial ? speedLimitMph : speedLimitKmh }
    private var limitBinding: Binding<Double> { imperial ? $speedLimitMph : $speedLimitKmh }
    private var limitRange: ClosedRange<Double> { imperial ? 20...85 : 30...140 }
    /// "Limite yaklaşıyor" eşiği: 10 km/h ≈ 5 mph.
    private var warnMargin: Double { imperial ? 5 : 10 }

    var body: some View {
        VStack(spacing: 3) {
            HStack(spacing: 10) {
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text("\(Int(speed.rounded()))")
                        .font(.system(size: 40, weight: .heavy, design: .rounded))
                        .foregroundStyle(speedColor)
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                    Text(unitLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                VStack(alignment: .trailing, spacing: 2) {
                    Text("LIMIT \(Int(speedLimit))")
                        .font(.caption2.bold())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Stepper("", value: limitBinding, in: limitRange, step: 5)
                        .labelsHidden()
                        .controlSize(.mini)
                }
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.white.opacity(0.12))
                    RoundedRectangle(cornerRadius: 3)
                        .fill(speedColor)
                        .frame(width: geo.size.width * gaugeProgress)
                }
            }
            .frame(height: 5)

            Text(statusText)
                .font(.caption2)
                .foregroundStyle(speedColor)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private var gaugeProgress: Double {
        min(max(speed / max(speedLimit * 1.5, 1), 0), 1)
    }

    private var speedColor: Color {
        if speed > speedLimit { return .red }
        if speed > speedLimit - warnMargin { return .orange }
        return .green
    }

    private var statusText: String {
        if location.authState != .authorized { return String(localized: "Waiting for location…") }
        if speed > speedLimit { return String(localized: "Over the speed limit!") }
        if speed > speedLimit - warnMargin { return String(localized: "Approaching the limit") }
        if speed < 1 { return String(localized: "Stopped") }
        return String(localized: "Limit: \(Int(speedLimit)) \(unitLabel)")
    }
}
