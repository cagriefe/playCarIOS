import SwiftUI

/// Ana split-screen: sol %60 harita, sağ %40 widget'lar.
/// Landscape-only (Info.plist + AppDelegate kilidi).
/// Sağ panel ViewThatFits ile önce sığdırmayı dener, küçük ekranda kaydırır.
/// Büyük erişilebilirlik puntoları düzeni bozmasın diye üst sınır var.
struct DashboardView: View {
    @StateObject private var locationManager = LocationManager()
    @StateObject private var musicManager = MusicPlayerManager()
    @StateObject private var telemetry = TelemetryStore()

    var body: some View {
        GeometryReader { geo in
            HStack(spacing: 0) {
                MapPanelView(locationManager: locationManager)
                    .frame(width: geo.size.width * 0.6)

                Divider()

                ViewThatFits(in: .vertical) {
                    rightColumn
                    ScrollView(.vertical, showsIndicators: false) {
                        rightColumn
                    }
                }
                .frame(width: geo.size.width * 0.4)
                .background(Color.black)
            }
        }
        .background(Color.black)
        .preferredColorScheme(.dark)
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
    }

    private var rightColumn: some View {
        VStack(spacing: 8) {
            TelemetryBarView(telemetry: telemetry, location: locationManager)
            SpeedometerView(location: locationManager)
            MediaControlView(player: musicManager)
        }
        .padding(8)
    }
}

#Preview {
    DashboardView()
}
