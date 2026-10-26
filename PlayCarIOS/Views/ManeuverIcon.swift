import SwiftUI

/// Manevra oku; döner kavşakta çıkış numarası rozetle gösterilir.
struct ManeuverIcon: View {
    let maneuver: Maneuver
    var size: CGFloat = 34
    var color: Color = .white

    var body: some View {
        Image(systemName: maneuver.symbol)
            .font(.system(size: size, weight: .bold))
            .foregroundStyle(color)
            .frame(width: size * 1.25, height: size * 1.25)
            .overlay(alignment: .bottomTrailing) {
                if let exit = maneuver.exitNumber {
                    Text("\(exit)")
                        .font(.system(size: size * 0.38, weight: .heavy, design: .rounded))
                        .foregroundStyle(.black)
                        .padding(.horizontal, size * 0.12)
                        .background(Color.white, in: Capsule())
                        .offset(x: size * 0.12, y: size * 0.08)
                }
            }
            .accessibilityHidden(true)
    }
}
