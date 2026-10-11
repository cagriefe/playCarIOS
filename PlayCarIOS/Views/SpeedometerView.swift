import SwiftUI

/// Kompakt hız göstergesi (km/h).
/// CLLocation.speed m/s'tir: kmh = max(0, speed * 3.6).
/// Dar sağ panele taşmadan sığması için sabit genişlik yok,
/// tüm satırlar lineLimit(1) + minimumScaleFactor ile korunur.
struct SpeedometerView: View {
    @ObservedObject var location: LocationManager

    /// Kullanıcı ayarlı hız limiti (iOS'ta public hız-limiti API'si yok).
    @AppStorage("speedLimitKmh") private var speedLimit: Double = 90

    var body: some View {
        VStack(spacing: 3) {
            HStack(spacing: 6) {
                Text("HIZ")
                    .font(.caption2.bold())
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                Text("Limit \(Int(speedLimit))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Stepper("", value: $speedLimit, in: 30...140, step: 5)
                    .labelsHidden()
                    .controlSize(.small)
            }

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("\(Int(location.speedKmh.rounded()))")
                    .font(.system(size: 52, weight: .heavy, design: .rounded))
                    .foregroundStyle(speedColor)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                Text("km/h")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 0)
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
            .frame(height: 6)

            Text(statusText)
                .font(.caption2)
                .foregroundStyle(speedColor)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(10)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
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
