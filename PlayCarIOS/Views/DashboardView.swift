import SwiftUI

/// CarPlay Dashboard split düzeni (yatay, katı bölme):
/// - Sol %65: tam boy harita + navigasyon (yuvarlak köşeli).
/// - Sağ %35: durum satırı + hız (üst) + müzik (alt, esnek).
/// Global üst bar yok — harita üst kenara kadar uzar.
/// Sağdaki hiçbir widget sol panele taşmaz.
struct DashboardView: View {
    @StateObject private var locationManager = LocationManager()
    @StateObject private var musicManager = MusicPlayerManager()
    @StateObject private var telemetry = TelemetryStore()

    var body: some View {
        GeometryReader { geo in
            let contentW = geo.size.width - 24 // 8 padding + 8 spacing
            HStack(spacing: 8) {
                MapPanelView(locationManager: locationManager)
                    .frame(width: contentW * 0.65)
                    .clipShape(RoundedRectangle(cornerRadius: 16))

                // Sağ sütun sabit: kaydırma yok. Kaydırmalar sadece
                // medya içindeki liste görünümlerinde (ScrollView + LazyVStack).
                rightColumn
                    .frame(width: contentW * 0.35)
            }
            .padding(8)
        }
        .background(Color.black)
        .ignoresSafeArea()
        .preferredColorScheme(.dark)
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
    }

    private var rightColumn: some View {
        VStack(spacing: 8) {
            miniStatus
            SpeedometerView(location: locationManager)
            MediaControlView(player: musicManager)
        }
    }

    /// Sağ panele sığan tek satırlık durum: saat + tarih + pusula + pil + kilit.
    private var miniStatus: some View {
        HStack(spacing: 6) {
            Text(telemetry.timeString)
                .font(.subheadline.bold())
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(telemetry.dateString)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer(minLength: 2)
            HStack(spacing: 3) {
                Image(systemName: "location.north.fill")
                    .rotationEffect(.degrees(locationManager.headingDegrees))
                    .font(.caption2)
                Text(locationManager.cardinalDirectionTR)
                    .font(.caption2.bold())
                    .lineLimit(1)
            }
            HStack(spacing: 2) {
                Image(systemName: batteryIcon)
                    .font(.caption2)
                    .foregroundStyle(batteryColor)
                Text(telemetry.batteryText)
                    .font(.caption2.bold())
                    .monospacedDigit()
                    .lineLimit(1)
            }
            Button {
                telemetry.keepScreenOn.toggle()
            } label: {
                Image(systemName: telemetry.keepScreenOn ? "lock.open.fill" : "lock.fill")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 22)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private var batteryIcon: String {
        let lvl = telemetry.batteryLevel
        if lvl < 0 { return "battery.0" }
        if lvl >= 0.9 { return "battery.100" }
        if lvl >= 0.65 { return "battery.75" }
        if lvl >= 0.35 { return "battery.50" }
        return "battery.25"
    }

    /// Bilinmeyen seviye (-1) gri, %20 altı kırmızı, üstü yeşil.
    /// Eskiden bilinmeyen değer de kırmızıya düşüyordu (yanlış alarm).
    private var batteryColor: Color {
        let lvl = telemetry.batteryLevel
        if lvl < 0 { return .gray }
        if lvl < 0.2 { return .red }
        return .green
    }
}

#Preview {
    DashboardView()
}
