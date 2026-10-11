import SwiftUI

/// Hız göstergesi — km/h (proposal'daki "km/s" hatası düzeltildi).
/// CLLocation.speed m/s'tir; negatif = geçersiz -> 0 gösterilir.
struct SpeedometerView: View {
    @ObservedObject var location: LocationManager

    /// Kullanıcı ayarlı hız limiti (iOS'ta public hız-limiti API'si yok).
    @AppStorage("speedLimitKmh") private var speedLimit: Double = 90

    var body: some View {
        VStack(spacing: 6) {
            HStack {
                Text("HIZ")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                Spacer()
                Stepper("Limit \(Int(speedLimit))", value: $speedLimit, in: 30...140, step: 5)
                    .font(.caption)
                    .labelsHidden()
                Text("\(Int(speedLimit))")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
            }

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("\(Int(location.speedKmh.rounded()))")
                    .font(.system(size: 64, weight: .heavy, design: .rounded))
                    .foregroundStyle(speedColor)
                    .monospacedDigit()
                    .minimumScaleFactor(0.6)
                Text("km/h")
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }

            // Minimalist gauge
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.white.opacity(0.12))
                    RoundedRectangle(cornerRadius: 4)
                        .fill(speedColor)
                        .frame(width: geo.size.width * gaugeProgress)
                }
            }
            .frame(height: 8)

            Text(statusText)
                .font(.caption)
                .foregroundStyle(speedColor)
        }
        .padding(14)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 16))
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
