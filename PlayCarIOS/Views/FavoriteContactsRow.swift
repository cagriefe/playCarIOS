import SwiftUI

/// Sağ sütunda hız ile medya arasında 4 favori kişi.
/// Boş slot: kişi seç. Dolu slot: dokun → ara, uzun bas → Ara / Değiştir / Kaldır.
struct FavoriteContactsRow: View {
    @ObservedObject var contacts: FavoriteContactsStore
    @ObservedObject var calls: CallStore

    var body: some View {
        HStack(spacing: 0) {
            ForEach(0..<FavoriteContactsStore.slotCount, id: \.self) { index in
                slot(index)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 4)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    @ViewBuilder
    private func slot(_ index: Int) -> some View {
        if let contact = contacts.slots[index] {
            Button {
                calls.call(contact)
            } label: {
                VStack(spacing: 2) {
                    ContactAvatar(contact: contact, size: 38)
                    Text(contact.shortName)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .contextMenu {
                Button { calls.call(contact) } label: {
                    Label("Call (\(contact.label ?? contact.phone))", systemImage: "phone.fill")
                }
                Button { contacts.pick(into: index) } label: {
                    Label("Replace", systemImage: "arrow.triangle.2.circlepath")
                }
                Button(role: .destructive) { contacts.set(nil, at: index) } label: {
                    Label("Remove", systemImage: "trash")
                }
            }
            .accessibilityLabel(Text("Call \(contact.name)"))
        } else {
            Button {
                contacts.pick(into: index)
            } label: {
                VStack(spacing: 2) {
                    Circle()
                        .strokeBorder(Color.white.opacity(0.3), style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                        .frame(width: 38, height: 38)
                        .overlay(
                            Image(systemName: "plus")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(.secondary)
                        )
                    Text("Add")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Add favorite contact")
        }
    }
}

/// Kişi fotoğrafı ya da renkli baş harf dairesi.
struct ContactAvatar: View {
    let contact: FavoriteContact?
    let size: CGFloat

    private static let palette: [Color] = [.blue, .green, .orange, .purple, .pink, .teal]

    var body: some View {
        Group {
            if let data = contact?.photo, let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else if let contact {
                ZStack {
                    Self.palette[contact.colorIndex].opacity(0.85)
                    Text(contact.initials)
                        .font(.system(size: size * 0.38, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                }
            } else {
                ZStack {
                    Color.white.opacity(0.14)
                    Image(systemName: "phone.fill")
                        .font(.system(size: size * 0.4))
                        .foregroundStyle(.white)
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }
}
