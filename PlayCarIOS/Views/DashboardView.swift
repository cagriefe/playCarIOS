import SwiftUI

/// CarPlay Dashboard düzeni:
/// - Tam ekran harita (arka plan),
/// - Üstte ince durum çubuğu (tarih • saat • pusula • pil),
/// - Sağda harita üstünde yüzen kartlar (hız + müzik).
/// Siyah paneller yok, bölme çizgisi yok — her şey haritanın üstünde yüzer.
struct DashboardView: View {
    @StateObject private var locationManager = LocationManager()
    @StateObject private var musicManager = MusicPlayerManager()
    @StateObject private var telemetry = TelemetryStore()

    var body: some View {
        ZStack {
            MapPanelView(locationManager: locationManager)
                .ignoresSafeArea()

            // Üst durum çubuğu (CarPlay status bar)
            VStack {
                statusBar
                Spacer(minLength: 0)
            }
            .ignoresSafeArea(edges: .top)

            // Sağda yüzen kartlar
            HStack {
                Spacer(minLength: 0)
                ViewThatFits(in: .vertical) {
                    rightCards
                    ScrollView(.vertical, showsIndicators: false) {
                        rightCards
                    }
                }
                .frame(width: 300)
                .padding(.trailing, 12)
                .padding(.top, 46)
                .padding(.bottom, 12)
            }
        }
        .background(Color.black)
        .preferredColorScheme(.dark)
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
    }

    private var rightCards: some View {
        VStack(spacing: 10) {
            SpeedometerView(location: locationManager)
            MediaControlView(player: musicManager)
            Spacer(minLength: 0)
        }
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
            Toggle(isOn: $telemetry.keepScreenOn) {
                Image(systemName: telemetry.keepScreenOn ? "lock.open.fill" : "lock.fill")
                    .font(.caption2)
            }
            .labelsHidden()
            .controlSize(.mini)
            .tint(.accentColor)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .background(.ultraThinMaterial)
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
