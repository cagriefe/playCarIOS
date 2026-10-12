import SwiftUI

/// CarPlay tarzı hız kartı: yatay düzen, solda büyük rakam,
/// sağda limit + ince gauge + durum. Yuvarlak yüzen kart.
struct SpeedometerView: View {
    @ObservedObject var location: LocationManager

    /// Kullanıcı ayarlı hız limiti (iOS'ta public hız-limiti API'si yok).
    @AppStorage("speedLimitKmh") private var speedLimit: Double = 90

    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 10) {
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text("\(Int(location.speedKmh.rounded()))")
                        .font(.system(size: 46, weight: .heavy, design: .rounded))
                        .foregroundStyle(speedColor)
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                    Text("km/h")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                VStack(alignment: .trailing, spacing: 2) {
                    Text("LİMİT \(Int(speedLimit))")
                        .font(.caption2.bold())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Stepper("", value: $speedLimit, in: 30...140, step: 5)
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
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private var gaugeProgress: Double {
        min(max(location.speedKmh / max(speedLimit * 1.5, 1), 0), 1)
    }

    private var speedColor: Color {
        if location.speedKmh > speedLimit { return .red }
        if location.speedKmh > speedLimit - 10 { return .orange }
        return .green
    }

    private var statusText: String {
        if location.authState != .authorized { return "Konum bekleniyor…" }
        if location.speedKmh > speedLimit { return "Hız limitini aştınız!" }
        if location.speedKmh > speedLimit - 10 { return "Limite yaklaşıyorsunuz" }
        if location.speedKmh < 1 { return "Duruyor" }
        return "Limit: \(Int(speedLimit)) km/h"
    }
}
