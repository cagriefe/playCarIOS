import SwiftUI

/// Üst bilgi şeridi: saat, tarih, pil, pusula, ekran-kilit toggle.
struct TelemetryBarView: View {
    @ObservedObject var telemetry: TelemetryStore
    @ObservedObject var location: LocationManager

    var body: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 0) {
                Text(telemetry.timeString)
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .monospacedDigit()
                Text(telemetry.dateString)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            HStack(spacing: 6) {
                Image(systemName: "location.north.fill")
                    .rotationEffect(.degrees(location.headingDegrees))
                    .font(.headline)
                Text(location.cardinalDirectionTR)
                    .font(.headline.bold())
                    .frame(minWidth: 32)
            }
            .foregroundStyle(.primary)
            .accessibilityLabel("Pusula \(location.cardinalDirectionTR)")

            HStack(spacing: 4) {
                Image(systemName: batteryIcon)
                    .foregroundStyle(batteryColor)
                Text(telemetry.batteryText)
                    .font(.subheadline.bold())
                    .monospacedDigit()
            }

            Toggle(isOn: $telemetry.keepScreenOn) {
                Image(systemName: telemetry.keepScreenOn ? "lock.open.fill" : "lock.fill")
            }
            .labelsHidden()
            .tint(.accentColor)
        }
        .padding(12)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 16))
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
