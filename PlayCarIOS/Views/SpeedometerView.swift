import SwiftUI

/// CarPlay tarzı hız kartı: yatay düzen, solda büyük rakam,
/// sağda tipografik limit + limit çizgili ince gauge + durum. Yuvarlak yüzen kart.
/// Hız rakamına dokununca kart yolculuk özetine döner (10 sn sonra / limit
/// aşılınca kendiliğinden hıza geri gelir).
struct SpeedometerView: View {
    @ObservedObject var location: LocationManager
    @ObservedObject var limits: SpeedLimitStore
    @ObservedObject var trip: TripStore

    /// Otomatik tahmin kapalıyken kalıcı elle limit (iOS'ta public hız-limiti API'si yok).
    /// Birim bölgeye göre: km/h veya mph (ayrı saklanır, dönüşüm yuvarlaması olmasın).
    @AppStorage("speedLimitKmh") private var speedLimitKmh: Double = 90
    @AppStorage("speedLimitMph") private var speedLimitMph: Double = 55
    @State private var showPicker = false
    @State private var showTrip = false

    private let imperial = NavFormat.usesImperial
    private var unitLabel: String { imperial ? "mph" : "km/h" }
    private var speed: Double { imperial ? location.speedKmh / 1.609344 : location.speedKmh }
    /// "Limite yaklaşıyor" eşiği: 10 km/h ≈ 5 mph.
    private var warnMargin: Double { imperial ? 5 : 10 }

    private var source: SpeedLimitStore.Source {
        guard limits.autoEnabled else { return .manual }
        if limits.overrideKmh != nil { return .override }
        return limits.estimateKmh != nil ? .estimated : .manual
    }

    /// Görüntü biriminde limit.
    private var speedLimit: Double {
        let kmh: Double?
        switch source {
        case .override: kmh = limits.overrideKmh
        case .estimated: kmh = limits.estimateKmh
        case .manual: kmh = nil
        }
        guard let kmh else { return imperial ? speedLimitMph : speedLimitKmh }
        return (imperial ? kmh / 1.609344 : kmh).rounded()
    }

    var body: some View {
        // Hız içeriği yerinde kalır (kart yüksekliği değişmesin), yolculuk üstüne biner.
        ZStack {
            speedContent
                .opacity(showTrip ? 0 : 1)
                .allowsHitTesting(!showTrip)
            if showTrip {
                tripContent
                    .transition(.opacity)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
        .animation(.easeInOut(duration: 0.2), value: showTrip)
        .task(id: showTrip) {
            guard showTrip else { return }
            try? await Task.sleep(for: .seconds(10))
            showTrip = false
        }
        .onChange(of: speed > speedLimit) { _, over in
            if over { showTrip = false }
        }
    }

    private var speedContent: some View {
        VStack(spacing: 3) {
            HStack(spacing: 10) {
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text("\(Int(speed.rounded()))")
                        .font(.system(size: 40, weight: .heavy, design: .rounded))
                        .foregroundStyle(speedColor)
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                    Text(unitLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .contentShape(Rectangle())
                .onTapGesture { showTrip = true }
                .accessibilityAddTraits(.isButton)
                .accessibilityHint(Text("Shows the trip summary"))
                Spacer(minLength: 0)
                Button { showPicker = true } label: {
                    SpeedLimitBadge(value: Int(speedLimit), over: speed > speedLimit)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Speed limit \(Int(speedLimit)) \(unitLabel)"))
                .popover(isPresented: $showPicker, arrowEdge: .leading) {
                    limitPicker
                        .presentationCompactAdaptation(.popover)
                }
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.white.opacity(0.12))
                    RoundedRectangle(cornerRadius: 3)
                        .fill(speedColor)
                        .frame(width: geo.size.width * gaugeProgress)
                }
                // Limit çizgisi: çubuk 0…1,5×limit, yani limit hep üçte iki noktasında.
                .overlay(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.85))
                        .frame(width: 2, height: 9)
                        .offset(x: geo.size.width * (2.0 / 3.0) - 1)
                }
            }
            .frame(height: 5)

            Text(statusText)
                .font(.caption2)
                .foregroundStyle(speedColor)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// Yolculuk özeti: mesafe, sürüş süresi, ortalama ve en yüksek hız.
    private var tripContent: some View {
        let distance = TripFormat.distance(trip.distance, imperial: imperial)
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("TRIP")
                    .font(.system(size: 9, weight: .semibold))
                    .tracking(1.6)
                    .foregroundStyle(.secondary)
                Spacer()
                Button { trip.reset() } label: {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.caption.bold())
                        .frame(width: 36, height: 26)
                }
                .accessibilityLabel("Reset trip")
            }
            HStack(alignment: .top, spacing: 6) {
                tripStat(distance.value, unit: distance.unit, label: "Distance")
                tripStat(TripFormat.drivingTime(trip.drivingTime), unit: nil, label: "Driving")
                tripStat("\(TripFormat.speed(trip.averageSpeed, imperial: imperial))", unit: unitLabel, label: "Average")
                tripStat("\(TripFormat.speed(trip.maxSpeed, imperial: imperial))", unit: unitLabel, label: "Top speed")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .contentShape(Rectangle())
        .onTapGesture { showTrip = false }
    }

    private func tripStat(_ value: String, unit: String?, label: LocalizedStringKey) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(verbatim: value)
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                if let unit {
                    Text(verbatim: unit)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Hızlı seçim: ülkenin standart limitleri büyük butonlarla.
    private var limitPicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle("Estimate automatically", isOn: $limits.autoEnabled)
                .font(.subheadline.bold())
            if limits.autoEnabled, let cls = limits.roadClass, let est = limits.estimateKmh {
                let shown = Int((imperial ? est / 1.609344 : est).rounded())
                Text("Estimate: \(cls.title) → \(shown) \(unitLabel)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(56), spacing: 8), count: 4), spacing: 8) {
                ForEach(CountrySpeedLimits.presets(country: limits.countryCode ?? Locale.current.region?.identifier,
                                                   imperial: imperial), id: \.self) { value in
                    Button { pick(value) } label: {
                        Text("\(value)")
                            .font(.title3.bold())
                            .monospacedDigit()
                            .frame(width: 56, height: 44)
                            .background(Int(speedLimit) == value ? Color.accentColor : Color.white.opacity(0.12),
                                        in: RoundedRectangle(cornerRadius: 10))
                            .foregroundStyle(.white)
                    }
                    .buttonStyle(.plain)
                }
            }
            if source == .override {
                Button("Use estimate") {
                    limits.clearOverride()
                    showPicker = false
                }
                .font(.subheadline.bold())
            }
            Text("Estimates come from the road type and the country's default limits. Signs may differ.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(width: 280)
    }

    /// Otomatik açıkken bu yol için geçici seçim; kapalıyken kalıcı limit.
    private func pick(_ value: Int) {
        let v = Double(value)
        if limits.autoEnabled {
            limits.setOverride(kmh: imperial ? v * 1.609344 : v)
        } else if imperial {
            speedLimitMph = v
        } else {
            speedLimitKmh = v
        }
        showPicker = false
    }

    private var gaugeProgress: Double {
        min(max(speed / max(speedLimit * 1.5, 1), 0), 1)
    }

    private var speedColor: Color {
        if speed > speedLimit { return .red }
        if speed > speedLimit - warnMargin { return .orange }
        return .green
    }

    private var statusText: String {
        if location.authState != .authorized { return String(localized: "Waiting for location…") }
        if speed > speedLimit { return String(localized: "Over the speed limit!") }
        if speed > speedLimit - warnMargin { return String(localized: "Approaching the limit") }
        if speed < 1 { return String(localized: "Stopped") }
        // Normal sürüşte limitin kaynağı yazılır: tahmin mi, elle mi.
        switch source {
        case .estimated:
            return ([String(localized: "Estimated")] + [limits.roadClass?.title, limits.roadName].compactMap { $0 })
                .joined(separator: " · ")
        case .override:
            return ([String(localized: "Manual")] + [limits.roadName].compactMap { $0 }).joined(separator: " · ")
        case .manual:
            break
        }
        return String(localized: "Limit: \(Int(speedLimit)) \(unitLabel)")
    }
}
