import SwiftUI

/// Kompakt üst şerit: saat + tarih + pusula + pil + ekran kilidi.
/// Yatay iPhone'da (~350pt kullanılabilir yükseklik) tek blok ~60pt hedefler,
/// taşmayı önlemek için tüm metinler lineLimit(1) + esnek Spacer kullanır.
struct TelemetryBarView: View {
    @ObservedObject var telemetry: TelemetryStore
    @ObservedObject var location: LocationManager

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 0) {
                Text(telemetry.timeString)
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(telemetry.dateString)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(minWidth: 60)

            Spacer(minLength: 2)

            HStack(spacing: 4) {
                Image(systemName: "location.north.fill")
                    .rotationEffect(.degrees(location.headingDegrees))
                    .font(.subheadline)
                Text(location.cardinalDirectionTR)
                    .font(.subheadline.bold())
                    .lineLimit(1)
            }
            .accessibilityLabel("Pusula \(location.cardinalDirectionTR)")

            HStack(spacing: 3) {
                Image(systemName: batteryIcon)
                    .foregroundStyle(batteryColor)
                    .font(.caption)
                Text(telemetry.batteryText)
                    .font(.caption.bold())
                    .monospacedDigit()
                    .lineLimit(1)
            }

            Toggle(isOn: $telemetry.keepScreenOn) {
                Image(systemName: telemetry.keepScreenOn ? "lock.open.fill" : "lock.fill")
            }
            .labelsHidden()
            .controlSize(.small)
            .tint(.accentColor)
        }
        .padding(8)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
    }

    private var batteryIcon: String {
        let lvl = telemetry.batteryLevel
        if lvl < 0 { return "battery.0" }
        if lvl >= 0.9 { return "battery.100" }
        if lvl >= 0.65 { return "battery.75" }
        if lvl >= 0.35 { return "battery.50" }
        return "battery.25"
    }

    private var batteryColor: Color {
        telemetry.batteryLevel < 0.2 ? .red : .green
    }
}
