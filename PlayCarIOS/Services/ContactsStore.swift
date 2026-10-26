import Foundation
import Contacts
import ContactsUI
import UIKit
import Combine

/// Hızlı arama için favori kişi. Rehber izni istenmez: kişi sistem
/// seçicisinden (CNContactPickerViewController) alınır ve kopyası saklanır.
struct FavoriteContact: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var name: String
    /// Dar slot etiketi için (genelde ilk ad).
    var shortName: String
    var phone: String
    /// "cep", "iş" vb. (yerelleştirilmiş).
    var label: String?
    /// 96 px JPEG.
    var photo: Data?

    var initials: String {
        let letters = name
            .split(separator: " ")
            .prefix(2)
            .compactMap { $0.first.map(String.init) }
            .joined()
        return letters.uppercased(with: Locale(identifier: "tr_TR"))
    }

    /// Fotoğrafsız avatar rengi: isimden sabit (hashValue her açılışta değişir).
    var colorIndex: Int {
        name.unicodeScalars.reduce(0) { $0 &+ Int($1.value) } % 6
    }

    var callURL: URL? {
        let digits = phone.filter { $0.isNumber || $0 == "+" }
        guard !digits.isEmpty else { return nil }
        return URL(string: "tel://\(digits)")
    }
}

/// 4 sabit slotlu favori kişi deposu (UserDefaults + JSON).
final class FavoriteContactsStore: ObservableObject {
    static let slotCount = 4

    @Published private(set) var slots: [FavoriteContact?]

    private let storageKey = "favoriteContacts.v1"

    init() {
        slots = Array(repeating: nil, count: Self.slotCount)
        load()
    }

    func set(_ contact: FavoriteContact?, at index: Int) {
        guard slots.indices.contains(index) else { return }
        slots[index] = contact
        save()
    }

    /// Kişiyi seçici ile seçip slota yazar.
    func pick(into index: Int) {
        ContactPicker.present { [weak self] contact in
            guard let self, let contact else { return }
            self.set(contact, at: index)
        }
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([FavoriteContact?].self, from: data)
        else { return }
        var result = Array(decoded.prefix(Self.slotCount))
        while result.count < Self.slotCount { result.append(nil) }
        slots = result
    }

    private func save() {
        if let data = try? JSONEncoder().encode(slots) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }
}

// MARK: - Kişi seçici

/// Sistem kişi seçicisi. SwiftUI sheet içinde CNContactPickerViewController
/// kendini kapatınca boş sayfa bırakır; bu yüzden doğrudan en üstteki
/// view controller'dan sunulur.
enum ContactPicker {
    private static var active: Coordinator?

    static func present(completion: @escaping (FavoriteContact?) -> Void) {
        guard let presenter = topViewController() else { completion(nil); return }
        let coordinator = Coordinator { contact in
            completion(contact)
            active = nil
        }
        active = coordinator
        let picker = CNContactPickerViewController()
        picker.delegate = coordinator
        picker.displayedPropertyKeys = [CNContactPhoneNumbersKey]
        picker.predicateForEnablingContact = NSPredicate(format: "phoneNumbers.@count > 0")
        // Tek numaralı kişi doğrudan seçilir; çok numaralıda numara sorulur.
        picker.predicateForSelectionOfContact = NSPredicate(format: "phoneNumbers.@count == 1")
        presenter.present(picker, animated: true)
    }

    private static func topViewController() -> UIViewController? {
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
        let window = scene?.windows.first(where: \.isKeyWindow) ?? scene?.windows.first
        var top = window?.rootViewController
        while let presented = top?.presentedViewController { top = presented }
        return top
    }

    final class Coordinator: NSObject, CNContactPickerDelegate {
        private let completion: (FavoriteContact?) -> Void

        init(completion: @escaping (FavoriteContact?) -> Void) {
            self.completion = completion
        }

        func contactPicker(_ picker: CNContactPickerViewController, didSelect contact: CNContact) {
            guard let number = contact.phoneNumbers.first else { completion(nil); return }
            completion(Self.make(contact, number))
        }

        func contactPicker(_ picker: CNContactPickerViewController, didSelect contactProperty: CNContactProperty) {
            guard let phone = contactProperty.value as? CNPhoneNumber else { completion(nil); return }
            let labeled = contactProperty.contact.phoneNumbers.first { $0.identifier == contactProperty.identifier }
                ?? CNLabeledValue(label: contactProperty.label, value: phone)
            completion(Self.make(contactProperty.contact, labeled))
        }

        func contactPickerDidCancel(_ picker: CNContactPickerViewController) {
            completion(nil)
        }

        /// Seçicinin döndürdüğü kişide her anahtar dolu olmayabilir:
        /// erişmeden önce isKeyAvailable ile kontrol et (yoksa çöker).
        private static func make(_ contact: CNContact, _ number: CNLabeledValue<CNPhoneNumber>) -> FavoriteContact {
            func value(_ key: String, _ get: (CNContact) -> String) -> String {
                contact.isKeyAvailable(key) ? get(contact) : ""
            }
            let given = value(CNContactGivenNameKey) { $0.givenName }
            let family = value(CNContactFamilyNameKey) { $0.familyName }
            let org = value(CNContactOrganizationNameKey) { $0.organizationName }
            let phone = number.value.stringValue
            var name = [given, family].filter { !$0.isEmpty }.joined(separator: " ")
            if name.isEmpty { name = org.isEmpty ? phone : org }
            let shortName = given.isEmpty ? (name.split(separator: " ").first.map(String.init) ?? name) : given

            var photo: Data?
            if contact.isKeyAvailable(CNContactThumbnailImageDataKey),
               let data = contact.thumbnailImageData,
               let image = UIImage(data: data) {
                photo = downscaled(image, side: 96)
            }
            let label = number.label.map { CNLabeledValue<NSString>.localizedString(forLabel: $0) }
            return FavoriteContact(name: name, shortName: shortName, phone: phone, label: label, photo: photo)
        }

        private static func downscaled(_ image: UIImage, side: CGFloat) -> Data? {
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            let renderer = UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format)
            let scaled = renderer.image { _ in
                let s = image.size
                let ratio = max(side / max(s.width, 1), side / max(s.height, 1))
                let w = s.width * ratio, h = s.height * ratio
                image.draw(in: CGRect(x: (side - w) / 2, y: (side - h) / 2, width: w, height: h))
            }
            return scaled.jpegData(compressionQuality: 0.8)
        }
    }
}
