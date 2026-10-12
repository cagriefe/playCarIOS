import SwiftUI

/// CarPlay Dashboard split düzeni (yatay, katı bölme):
/// - Sol %65: harita + navigasyon (adeta kendi ekranı, yuvarlak köşeli).
/// - Sağ %35: hız (üst) + müzik (alt) kartları.
/// Sağdaki hiçbir widget sol panele taşmaz. Üstte ince global durum çubuğu.
struct DashboardView: View {
    @StateObject private var locationManager = LocationManager()
    @StateObject private var musicManager = MusicPlayerManager()
    @StateObject private var telemetry = TelemetryStore()

    var body: some View {
        GeometryReader { geo in
            let contentW = geo.size.width - 36 // 12 padding + 12 spacing
            VStack(spacing: 0) {
                statusBar

                HStack(spacing: 12) {
                    MapPanelView(locationManager: locationManager)
                        .frame(width: contentW * 0.65)
                        .clipShape(RoundedRectangle(cornerRadius: 16))

                    VStack(spacing: 10) {
                        SpeedometerView(location: locationManager)
                        MediaControlView(player: musicManager)
                    }
                    .frame(width: contentW * 0.35, alignment: .top)
                }
                .padding(12)
            }
        }
        .background(Color.black)
        .ignoresSafeArea()
        .preferredColorScheme(.dark)
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
    }

    private var statusBar: some View {
        HStack(spacing: 8) {
            Text(telemetry.dateString)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer(minLength: 0)
            HStack(spacing: 4) {
                Image(systemName: "location.north.fill")
                    .rotationEffect(.degrees(locationManager.headingDegrees))
                    .font(.caption)
                Text(locationManager.cardinalDirectionTR)
                    .font(.caption.bold())
                    .lineLimit(1)
            }
            Text(telemetry.timeString)
                .font(.subheadline.bold())
                .monospacedDigit()
                .lineLimit(1)
            HStack(spacing: 3) {
                Image(systemName: batteryIcon)
                    .font(.caption2)
                    .foregroundStyle(telemetry.batteryLevel < 0.2 ? .red : .green)
                Text(telemetry.batteryText)
                    .font(.caption.bold())
                    .monospacedDigit()
                    .lineLimit(1)
            }
            Button {
                telemetry.keepScreenOn.toggle()
            } label: {
                Image(systemName: telemetry.keepScreenOn ? "lock.open.fill" : "lock.fill")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(width: 30, height: 24)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 4)
        .background(Color.black.opacity(0.6))
    }

    private var batteryIcon: String {
        let lvl = telemetry.batteryLevel
        if lvl < 0 { return "battery.0" }
        if lvl >= 0.9 { return "battery.100" }
        if lvl >= 0.65 { return "battery.75" }
        if lvl >= 0.35 { return "battery.50" }
        return "battery.25"
    }
}

#Preview {
    DashboardView()
}
