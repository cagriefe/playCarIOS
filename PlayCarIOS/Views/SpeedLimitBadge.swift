import SwiftUI

/// Hız limiti göstergesi: tipografik, kapsız (levha görünümü değil).
/// İnce ayraç + küçük "LİMİT" başlığı + ince rakam; büyük, kalın hız
/// rakamıyla zıtlık kurar. Limit aşılınca rakam kırmızıya döner.
struct SpeedLimitBadge: View {
    let value: Int
    var over = false

    var body: some View {
        HStack(spacing: 10) {
            Rectangle()
                .fill(Color.white.opacity(0.18))
                .frame(width: 1, height: 34)
            VStack(alignment: .leading, spacing: 0) {
                Text("LIMIT")
                    .font(.system(size: 9, weight: .semibold))
                    .tracking(1.6)
                    .foregroundStyle(.secondary)
                Text("\(value)")
                    .font(.system(size: 26, weight: .light, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(over ? Color.red : Color.primary)
                    .contentTransition(.numericText())
                    .lineLimit(1)
            }
        }
        .frame(minHeight: 44)
        .animation(.snappy, value: value)
        .animation(.easeInOut(duration: 0.2), value: over)
    }
}
