import SwiftUI

/// Navigasyon durum kartları (arama çubuğunun altında): hata, hesaplanıyor,
/// rota önizlemesi, sürüş (manevra + "Ardından") ve varış.
struct NavBannerView: View {
    @ObservedObject var nav: NavigationStore
    /// Rota kapatılınca haritadaki önizleme kadrajı da temizlenir.
    var onClose: () -> Void

    var body: some View {
        switch nav.phase {
        case .idle:
            if let err = nav.lastError {
                Button { nav.lastError = nil } label: {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                        Text(err).font(.caption).foregroundStyle(.primary)
                        Spacer()
                        Image(systemName: "xmark").font(.caption).foregroundStyle(.secondary)
                    }
                    .padding(10)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                }
            }
        case .calculating:
            HStack {
                ProgressView().scaleEffect(0.8)
                Text("Calculating route…").font(.caption).foregroundStyle(.primary)
                Spacer()
                Button("Cancel") { nav.stop() }.font(.caption.bold())
            }
            .padding(10)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        case .preview:
            HStack(spacing: 8) {
                Image(systemName: "car.fill").foregroundStyle(.blue)
                VStack(alignment: .leading, spacing: 0) {
                    Text(nav.destinationName).font(.subheadline.bold()).lineLimit(1)
                    Text("\(NavFormat.distance(nav.distanceRemaining)) • Arrive \(nav.eta.map(NavFormat.time) ?? "—")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                Button("Go") {
                    nav.start()
                }
                .font(.subheadline.bold())
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Color.green)
                .foregroundStyle(.white)
                .clipShape(Capsule())
                Button("Close") { nav.stop(); onClose() }
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(10)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        case .navigating:
            VStack(alignment: .leading, spacing: 6) {
                // Apple Haritalar düzeni: solda büyük ok + mesafe, sağda talimat.
                HStack(alignment: .center, spacing: 10) {
                    VStack(spacing: 2) {
                        ManeuverIcon(maneuver: nav.nextManeuver, size: 30)
                        Text(NavFormat.distance(nav.nextDistance))
                            .font(.headline.bold())
                            .foregroundStyle(.green)
                            .monospacedDigit()
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    .frame(width: 76)
                    .accessibilityElement(children: .combine)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(nav.nextInstruction.isEmpty ? String(localized: "Continue") : nav.nextInstruction)
                            .font(.headline)
                            .lineLimit(2)
                            .minimumScaleFactor(0.8)
                        Text("\(NavFormat.distance(nav.distanceRemaining)) left • Arrive \(nav.eta.map(NavFormat.time) ?? "—")")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .accessibilityElement(children: .combine)
                    Spacer(minLength: 0)
                    VStack(spacing: 6) {
                        Button {
                            nav.muted.toggle()
                        } label: {
                            Image(systemName: nav.muted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                                .font(.subheadline)
                                .frame(width: 44, height: 30)
                        }
                        .accessibilityLabel(nav.muted ? String(localized: "Unmute voice guidance") : String(localized: "Mute voice guidance"))
                        Button("End") { nav.stop(); onClose() }
                            .font(.caption.bold())
                            .frame(width: 52, height: 30)
                            .background(Color.red)
                            .foregroundStyle(.white)
                            .clipShape(Capsule())
                    }
                }

                if let then = nav.thenInstruction {
                    HStack(spacing: 6) {
                        Text("Then")
                            .font(.caption.bold())
                            .foregroundStyle(.secondary)
                        if let thenManeuver = nav.thenManeuver {
                            ManeuverIcon(maneuver: thenManeuver, size: 14)
                        }
                        Text(then)
                            .font(.caption.bold())
                            .lineLimit(1)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(Color.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
                    .transition(.opacity)
                }

                // Uygulama dilinde ses yüklü değilse konuşma yabancı aksanla olur.
                if nav.voiceMissing {
                    Button { nav.dismissVoiceWarning() } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                            Text("No \(nav.voiceLanguageName) voice installed. Settings › Accessibility › Spoken Content › Voices")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                            Spacer(minLength: 0)
                            Image(systemName: "xmark")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(10)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        case .arrived:
            HStack {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                Text("Arrived: \(nav.destinationName)")
                    .font(.subheadline.bold())
                    .lineLimit(1)
                Spacer()
                Button("Close") { nav.stop(); onClose() }
                    .font(.caption.bold())
            }
            .padding(10)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        }
    }
}
