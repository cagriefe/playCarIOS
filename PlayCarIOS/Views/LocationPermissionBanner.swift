import SwiftUI

struct LocationPermissionBanner: View {
    var state: LocationManager.AuthState
    var onRequest: () -> Void

    var body: some View {
        HStack {
            Image(systemName: "location.slash.fill").foregroundStyle(.orange)
            Text(message)
                .font(.caption)
                .foregroundStyle(.primary)
            Spacer()
            Button("Allow", action: onRequest)
                .font(.caption.bold())
            Button("Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            .font(.caption)
        }
        .padding(10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private var message: String {
        switch state {
        case .denied: return String(localized: "Location is off. Speed and map won't work.")
        case .restricted: return String(localized: "Location is restricted.")
        case .notDetermined: return String(localized: "Location access is needed for the map.")
        case .authorized: return ""
        }
    }
}
