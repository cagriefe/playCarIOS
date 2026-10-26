import SwiftUI

/// Favoriler listesi: dokun → oraya git, kaydır → sil.
struct FavoritesSheetView: View {
    @ObservedObject var favorites: FavoritesStore
    var onGo: (FavoritePlace) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if favorites.favorites.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "star.fill")
                            .font(.largeTitle)
                            .foregroundStyle(.yellow)
                        Text("No Favorites Yet")
                            .font(.headline)
                        Text("Add places with ★ in search results or on the selected place card.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        Section {
                            ForEach(favorites.favorites) { place in
                                Button { onGo(place) } label: {
                                    HStack(spacing: 10) {
                                        Image(systemName: FavoritePlace.icon(for: place.kind))
                                            .foregroundStyle(Color(FavoritePlace.uiColor(for: place.kind)))
                                            .frame(width: 22)
                                        VStack(alignment: .leading, spacing: 1) {
                                            Text(place.name)
                                                .font(.subheadline.bold())
                                                .foregroundStyle(.primary)
                                                .lineLimit(1)
                                            Text(place.address)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                                .lineLimit(1)
                                        }
                                        Spacer()
                                        Image(systemName: "location.fill")
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .buttonStyle(.plain)
                                .swipeActions(edge: .leading, allowsFullSwipe: false) {
                                    kindButton(.work, for: place).tint(.brown)
                                    kindButton(.home, for: place).tint(.blue)
                                }
                                .contextMenu {
                                    kindButton(.home, for: place)
                                    kindButton(.work, for: place)
                                    Button(role: .destructive) { favorites.remove(place) } label: {
                                        Label("Remove", systemImage: "trash")
                                    }
                                }
                            }
                            .onDelete { favorites.remove(at: $0) }
                        } footer: {
                            Text("Swipe right on a place to set it as Home or Work.")
                        }
                    }
                }
            }
            .navigationTitle("Favorites")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }
}

extension FavoritesSheetView {
    /// Ev/İş yap; zaten öyleyse etiketi kaldır.
    fileprivate func kindButton(_ kind: PlaceKind, for place: FavoritePlace) -> some View {
        let isSet = place.kind == kind
        let title: LocalizedStringKey = switch (kind, isSet) {
        case (.home, false): "Set as Home"
        case (.home, true): "Remove Home"
        case (.work, false): "Set as Work"
        case (.work, true): "Remove Work"
        }
        return Button {
            favorites.setKind(isSet ? nil : kind, for: place)
        } label: {
            Label(title, systemImage: FavoritePlace.icon(for: kind))
        }
    }
}

extension FavoritePlace {
    static func icon(for kind: PlaceKind?) -> String {
        switch kind {
        case .home: return "house.fill"
        case .work: return "briefcase.fill"
        case nil: return "star.fill"
        }
    }

    static func uiColor(for kind: PlaceKind?) -> UIColor {
        switch kind {
        case .home: return .systemBlue
        case .work: return .systemBrown
        case nil: return .systemYellow
        }
    }
}
