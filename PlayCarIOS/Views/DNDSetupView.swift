import SwiftUI

/// Rahatsız Etme butonu için bir kerelik kurulum: hazır kestirmeyi
/// Kestirmeler'e ekletir. Dönüşte istenen durum kendiliğinden uygulanır.
struct DNDSetupView: View {
    @ObservedObject var dnd: DoNotDisturbController

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "moon.fill")
                .font(.system(size: 34))
                .foregroundStyle(.indigo)
            Text(dnd.shortcutMissing ? "Shortcut Not Found" : "One-Time Setup")
                .font(.headline)
            Text("iOS doesn't let apps switch Do Not Disturb directly. PlayCar comes with a ready-made shortcut that does it — add it once and the button works with a single tap.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 460)
            VStack(alignment: .leading, spacing: 8) {
                Label("Tap Add Shortcut and choose Shortcuts.", systemImage: "1.circle.fill")
                Label("Tap “Add Shortcut”.", systemImage: "2.circle.fill")
                Label("Come back to PlayCar — Do Not Disturb switches automatically.", systemImage: "3.circle.fill")
            }
            .font(.subheadline)
            .frame(maxWidth: 460, alignment: .leading)
            HStack(spacing: 12) {
                Button("Cancel") { dnd.showSetup = false }
                    .controlSize(.large)
                Button {
                    dnd.installShortcut()
                } label: {
                    Text("Add Shortcut").bold().frame(minWidth: 160)
                }
                .buttonStyle(.borderedProminent)
                .tint(.indigo)
                .controlSize(.large)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .presentationDetents([.large])
    }
}
