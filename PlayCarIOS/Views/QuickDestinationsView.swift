import SwiftUI
import MapKit

/// Tek dokunuşla rota: hedef adı, adres, koordinat.
struct QuickDestination {
    let name: String
    let address: String
    let coordinate: CLLocationCoordinate2D
}

/// Arama çubuğu altındaki kısayol çipleri: Ev · İş · son 3 hedef.
/// Klavye açmadan, sürüş sırasında tek dokunuşla rota önizlemesi.
struct QuickChipsRow: View {
    @ObservedObject var favorites: FavoritesStore
    @ObservedObject var recents: RecentDestinationsStore
    @ObservedObject var eta: ShortcutETAService
    var onGo: (QuickDestination) -> Void
    /// Ev/İş henüz yoksa favoriler sayfası açılır.
    var onSetUp: () -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                shortcutChips(kind: .home, places: favorites.homes)
                shortcutChips(kind: .work, places: favorites.works)
                ForEach(recentChips) { item in
                    chip(icon: "clock.arrow.circlepath", title: item.name, detail: nil, tint: .secondary) {
                        onGo(QuickDestination(name: item.name, address: item.address, coordinate: item.coordinate))
                    }
                }
            }
        }
        .scrollClipDisabled()
    }

    /// Ev/İş ile aynı yerdeki son hedefler tekrar gösterilmez.
    private var recentChips: [RecentDestination] {
        let shortcuts = favorites.shortcuts
        return recents.items.filter { item in
            !shortcuts.contains {
                abs($0.latitude - item.latitude) < 1e-3 && abs($0.longitude - item.longitude) < 1e-3
            }
        }
        .prefix(3)
        .map { $0 }
    }

    /// Tek Ev varsa çipte "Ev", birden fazlaysa (iki ev) yerin adı yazar.
    @ViewBuilder
    private func shortcutChips(kind: PlaceKind, places: [FavoritePlace]) -> some View {
        let icon = kind == .home ? "house.fill" : "briefcase.fill"
        let genericTitle = kind == .home ? String(localized: "Home") : String(localized: "Work")
        if !places.isEmpty {
            ForEach(places) { place in
                chip(icon: icon,
                     title: places.count > 1 ? place.name : genericTitle,
                     detail: eta.text(for: place),
                     tint: kind == .home ? .blue : .brown) {
                    onGo(QuickDestination(name: place.name, address: place.address, coordinate: place.coordinate))
                }
            }
        } else {
            chip(icon: icon, title: kind == .home ? String(localized: "Add Home") : String(localized: "Add Work"),
                 detail: nil, tint: .secondary, action: onSetUp)
                .opacity(0.8)
        }
    }

    private func chip(icon: String, title: String, detail: String?, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.caption.bold())
                    .foregroundStyle(tint)
                Text(title)
                    .font(.caption.bold())
                    .lineLimit(1)
                if let detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 12)
            .frame(height: 36)
            .frame(maxWidth: 170)
            .background(.ultraThinMaterial, in: Capsule())
        }
        .buttonStyle(.plain)
    }
}

/// Arama çubuğu odaklı ve boşken: son hedefler listesi.
struct RecentDestinationsList: View {
    @ObservedObject var recents: RecentDestinationsStore
    var onGo: (QuickDestination) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Recents")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Clear") { recents.clear() }
                    .font(.caption.bold())
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)

            ScrollView(.vertical, showsIndicators: true) {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(recents.items) { item in
                        HStack(spacing: 0) {
                            Button {
                                onGo(QuickDestination(name: item.name, address: item.address, coordinate: item.coordinate))
                            } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: "clock.arrow.circlepath")
                                        .foregroundStyle(.secondary)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(item.name).font(.subheadline).foregroundStyle(.primary).lineLimit(1)
                                        if !item.address.isEmpty {
                                            Text(item.address).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                        }
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.vertical, 8)
                                .padding(.horizontal, 12)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            Button { recents.remove(item) } label: {
                                Image(systemName: "xmark")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .frame(width: 44, height: 44)
                            }
                            .accessibilityLabel(Text("Remove \(item.name)"))
                        }
                        if item.id != recents.items.last?.id {
                            Divider().padding(.leading, 12)
                        }
                    }
                }
            }
        }
        // ScrollView boş alanı da kaplar: yükseklik kayıt sayısına göre (en fazla 220).
        .frame(height: min(32 + CGFloat(recents.items.count) * 52, 220))
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        .padding(.top, 6)
    }
}
