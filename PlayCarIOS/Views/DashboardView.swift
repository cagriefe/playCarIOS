import SwiftUI

/// CarPlay Dashboard split düzeni (yatay, katı bölme):
/// - Sol %65: tam boy harita + navigasyon (yuvarlak köşeli).
/// - Sağ %35: durum satırı + hız (üst) + favori kişiler + müzik/arama (alt, esnek).
/// Global üst bar yok — harita üst kenara kadar uzar.
/// Sağdaki hiçbir widget sol panele taşmaz.
struct DashboardView: View {
    @StateObject private var locationManager = LocationManager()
    @StateObject private var musicManager = MusicPlayerManager()
    @StateObject private var telemetry = TelemetryStore()
    @StateObject private var callStore = CallStore()
    @StateObject private var contacts = FavoriteContactsStore()
    @StateObject private var speedLimits = SpeedLimitStore()
    @StateObject private var dnd = DoNotDisturbController()
    @StateObject private var trip = TripStore()
    @Environment(\.scenePhase) private var scenePhase
    /// Çentik (notch / Dynamic Island) solda mı? Yatayda iOS iki yana da
    /// aynı güvenli alanı verir; hangi tarafta olduğunu yönelim söyler.
    @State private var notchOnLeft = false
    /// Pencereden okunan çentik payı (iPhone 13 Pro yatay: 47 pt).
    /// ignoresSafeArea uygulanmış GeometryReader bunu 0 bildirir, o yüzden
    /// doğrudan UIWindow'dan okunur.
    @State private var notchInset: CGFloat = 0

    private let gap: CGFloat = 8

    var body: some View {
        GeometryReader { geo in
            // Yatayda çentik payı (iPhone 13 Pro: 47 pt). Sadece çentik tarafında
            // uygulanır; diğer kenarlar ekranın sonuna kadar kullanılır.
            let notch = notchInset
            // Harita çentiğin altına uzayabilir (Apple Haritalar gibi); sadece
            // haritanın üstündeki butonlar çentikten kaçar.
            let mapLeadingInset = notchOnLeft ? notch : 0
            // Sağ sütun metin/buton içerir: çentik sağdaysa ondan kaçar.
            let trailingPad = notchOnLeft ? gap : max(notch - 12, gap)
            let contentW = geo.size.width - gap - trailingPad
            HStack(spacing: gap) {
                MapPanelView(locationManager: locationManager, leadingInset: mapLeadingInset)
                    .frame(width: contentW * 0.65)
                    .clipShape(UnevenRoundedRectangle(
                        topLeadingRadius: 0,
                        bottomLeadingRadius: 0,
                        bottomTrailingRadius: 16,
                        topTrailingRadius: 16
                    ))

                // Sağ sütun sabit: kaydırma yok. Kaydırmalar sadece
                // medya içindeki liste görünümlerinde (ScrollView + LazyVStack).
                rightColumn
                    .frame(width: contentW * 0.35)
                    .padding(.vertical, gap)
            }
            .padding(.trailing, trailingPad)
            .frame(width: geo.size.width, height: geo.size.height)
            .onChange(of: geo.size) { updateNotchSide() }
        }
        .background(Color.black)
        .ignoresSafeArea()
        // Araç ekranı: ana ekran çizgisi kendiliğinden gizlensin, alt kenardan
        // yanlışlıkla uygulamadan çıkılmasın (ilk kaydırma çizgiyi gösterir).
        .persistentSystemOverlays(.hidden)
        .defersSystemGestures(on: .bottom)
        .preferredColorScheme(.dark)
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .onAppear {
            UIDevice.current.beginGeneratingDeviceOrientationNotifications()
            updateNotchSide()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIDevice.orientationDidChangeNotification)) { _ in
            // Arayüz dönüşü bildirimden biraz sonra tamamlanır.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { updateNotchSide() }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { updateNotchSide() }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            updateNotchSide()
        }
        .onChange(of: locationManager.lastLocation) { _, loc in
            guard let loc else { return }
            speedLimits.update(loc)
            trip.update(loc)
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            UIApplication.shared.isIdleTimerDisabled = true
            // Kestirmeler'den dönüş (Rahatsız Etme kurulumu).
            dnd.appDidBecomeActive()
        }
        .onOpenURL { url in
            dnd.handle(url)
        }
        .sheet(isPresented: $dnd.showSetup) {
            DNDSetupView(dnd: dnd)
        }
    }

    /// landscapeRight = telefonun üstü (çentik) solda.
    private func updateNotchSide() {
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive } ??
            UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        guard let scene else { return }
        let left = scene.interfaceOrientation == .landscapeRight
        let insets = scene.windows.first(where: \.isKeyWindow)?.safeAreaInsets
            ?? scene.windows.first?.safeAreaInsets ?? .zero
        let inset = max(insets.left, insets.right)
        if left != notchOnLeft || inset != notchInset {
            withAnimation(.easeInOut(duration: 0.2)) {
                notchOnLeft = left
                notchInset = inset
            }
        }
    }

    private var rightColumn: some View {
        VStack(spacing: 8) {
            miniStatus
            SpeedometerView(location: locationManager, limits: speedLimits, trip: trip)
            FavoriteContactsRow(contacts: contacts, calls: callStore)
            MediaControlView(player: musicManager, calls: callStore)
        }
    }

    /// Sağ panele sığan tek satırlık durum: saat + tarih + pusula + pil + Rahatsız Etme.
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
                Text(locationManager.cardinalDirection)
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
            dndButton
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    /// Rahatsız Etme: dokun → aç/kapat (Kestirmeler üzerinden),
    /// uzun bas → durumu doğrudan seç (iOS'ta başka yerden değiştirildiyse).
    private var dndButton: some View {
        Button {
            dnd.toggle()
        } label: {
            Image(systemName: dnd.isOn ? "moon.fill" : "moon")
                .font(.caption.bold())
                .foregroundStyle(dnd.isOn ? Color.indigo : Color.secondary)
                .frame(width: 32, height: 24)
                .background(dnd.isOn ? Color.indigo.opacity(0.25) : Color.clear, in: Capsule())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button { dnd.set(true) } label: {
                Label("Turn On Do Not Disturb", systemImage: "moon.fill")
            }
            Button { dnd.set(false) } label: {
                Label("Turn Off Do Not Disturb", systemImage: "moon")
            }
            Button { dnd.showSetup = true } label: {
                Label("Add Shortcut Again", systemImage: "square.and.arrow.down")
            }
        }
        .accessibilityLabel("Do Not Disturb")
        .accessibilityValue(dnd.isOn ? Text("On") : Text("Off"))
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
