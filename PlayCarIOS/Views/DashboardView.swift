import SwiftUI

/// Ana split-screen: sol %60 harita, sağ %40 widget'lar.
/// Landscape-only (Info.plist + AppDelegate kilidi).
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

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 12) {
                        TelemetryBarView(telemetry: telemetry, location: locationManager)
                        SpeedometerView(location: locationManager)
                        MediaControlView(player: musicManager)
                    }
                    .padding(12)
                }
                .frame(width: geo.size.width * 0.4)
                .background(Color.black)
            }
        }
        .background(Color.black)
        .preferredColorScheme(.dark)
    }
}

#Preview {
    DashboardView()
}
