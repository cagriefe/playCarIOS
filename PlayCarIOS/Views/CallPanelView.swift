import SwiftUI

/// Medya kartının içinde arama görünümü (gelen / aranıyor / görüşmede).
/// Cevaplama, kapatma ve hoparlör iOS'ta yalnızca sistem arama
/// afişinden/ekranından yapılabilir; kart durumu ve süreyi gösterir,
/// kullanıcıyı doğru yere yönlendirir.
struct CallPanelView: View {
    @ObservedObject var calls: CallStore
    @State private var pulse = false

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                ContactAvatar(contact: calls.contact, size: 44)
                    .overlay(
                        Circle()
                            .stroke(statusColor, lineWidth: 2)
                            .scaleEffect(pulse ? 1.25 : 1)
                            .opacity(calls.phase == .incoming && pulse ? 0 : 1)
                    )
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.subheadline.bold())
                        .lineLimit(1)
                    Text(statusText)
                        .font(.caption.bold())
                        .foregroundStyle(statusColor)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                Button { calls.hide() } label: {
                    Image(systemName: "chevron.down.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("Hide call card")
            }

            Spacer(minLength: 0)

            Group {
                if calls.phase == .active || calls.phase == .onHold {
                    Text(calls.elapsedText)
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                        .monospacedDigit()
                } else {
                    Image(systemName: calls.phase == .incoming ? "phone.arrow.down.left.fill" : "phone.arrow.up.right.fill")
                        .font(.system(size: 30, weight: .semibold))
                        .foregroundStyle(statusColor)
                        .symbolEffect(.pulse, isActive: true)
                }
            }
            .frame(maxWidth: .infinity)
            .lineLimit(1)
            .minimumScaleFactor(0.6)

            Spacer(minLength: 0)

            HStack(alignment: .top, spacing: 6) {
                Image(systemName: "info.circle")
                    .font(.caption2)
                Text(hint)
                    .font(.caption2)
                    .fixedSize(horizontal: false, vertical: true)
                    .lineLimit(3)
                Spacer(minLength: 0)
            }
            .foregroundStyle(.secondary)
        }
        .frame(maxHeight: .infinity)
        .onAppear { startPulse() }
        .onChange(of: calls.phase) { startPulse() }
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private func startPulse() {
        pulse = false
        guard calls.phase == .incoming else { return }
        withAnimation(.easeOut(duration: 1.2).repeatForever(autoreverses: false)) { pulse = true }
    }

    private var title: String {
        if let contact = calls.contact { return contact.name }
        switch calls.phase {
        case .incoming: return String(localized: "Incoming Call")
        case .dialing: return String(localized: "Calling")
        default: return String(localized: "Phone Call")
        }
    }

    private var statusText: String {
        switch calls.phase {
        case .incoming: return String(localized: "Ringing…")
        case .dialing: return String(localized: "Calling…")
        case .active: return String(localized: "Connected")
        case .onHold: return String(localized: "On Hold")
        case .idle: return ""
        }
    }

    private var statusColor: Color {
        switch calls.phase {
        case .incoming, .dialing: return .orange
        case .onHold: return .yellow
        default: return .green
        }
    }

    private var hint: String {
        switch calls.phase {
        case .incoming:
            return String(localized: "Answer from the call banner at the top of the screen. No banner? Settings › Apps › Phone › Incoming Calls › Banner.")
        default:
            return String(localized: "Use the iPhone call screen to hang up or switch to speaker (iOS doesn't allow apps to).")
        }
    }
}
