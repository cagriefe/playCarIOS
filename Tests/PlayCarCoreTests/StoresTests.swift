import XCTest
import CoreLocation
@testable import PlayCarCore

final class StoresTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName = ""

    override func setUp() {
        super.setUp()
        suiteName = "PlayCarCoreTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    private func coordinate(_ lat: Double, _ lon: Double) -> CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }

    // MARK: Son hedefler

    func testRecentsMoveSamePlaceToTopAndPersist() {
        let store = RecentDestinationsStore(defaults: defaults)
        store.add(name: "A", address: "", coordinate: coordinate(41.0, 29.0))
        store.add(name: "B", address: "", coordinate: coordinate(41.1, 29.1))
        store.add(name: "A again", address: "", coordinate: coordinate(41.0003, 29.0))  // ~33 m
        XCTAssertEqual(store.items.map(\.name), ["A again", "B"])

        let reloaded = RecentDestinationsStore(defaults: defaults)
        XCTAssertEqual(reloaded.items.map(\.name), ["A again", "B"])
    }

    func testRecentsKeepAtMostEight() {
        let store = RecentDestinationsStore(defaults: defaults)
        for i in 0..<12 {
            store.add(name: "P\(i)", address: "", coordinate: coordinate(40 + Double(i) * 0.1, 29))
        }
        XCTAssertEqual(store.items.count, RecentDestinationsStore.limit)
        XCTAssertEqual(store.items.first?.name, "P11")
        store.clear()
        XCTAssertTrue(RecentDestinationsStore(defaults: defaults).items.isEmpty)
    }

    // MARK: Favoriler, Ev / İş

    func testMultipleHomesAndWork() throws {
        let store = FavoritesStore(defaults: defaults)
        store.add(name: "Ev 1", address: "", coordinate: coordinate(41.0, 29.0))
        store.add(name: "Ev 2", address: "", coordinate: coordinate(40.9, 29.2))
        store.add(name: "Ofis", address: "", coordinate: coordinate(41.05, 28.99))
        store.add(name: "Ev 1 tekrar", address: "", coordinate: coordinate(41.0, 29.0))  // aynı yer eklenmez
        XCTAssertEqual(store.favorites.count, 3)

        store.setKind(.home, for: store.favorites[0])
        store.setKind(.home, for: store.favorites[1])
        store.setKind(.work, for: store.favorites[2])
        XCTAssertEqual(store.homes.map(\.name), ["Ev 1", "Ev 2"], "iki ev olabilir")
        XCTAssertEqual(store.works.map(\.name), ["Ofis"])
        XCTAssertEqual(store.shortcuts.count, 3)

        store.setKind(nil, for: store.favorites[0])
        XCTAssertEqual(FavoritesStore(defaults: defaults).homes.map(\.name), ["Ev 2"])
    }

    /// Ev/İş eklenmeden önce kaydedilmiş favoriler bozulmadan okunur.
    func testDecodesFavoritesSavedBeforeKindExisted() throws {
        let legacy = """
        [{"id":"\(UUID().uuidString)","name":"Eski","address":"Kadıköy","latitude":40.99,"longitude":29.02,"createdAt":0}]
        """
        defaults.set(Data(legacy.utf8), forKey: "favoritePlaces.v1")
        let store = FavoritesStore(defaults: defaults)
        XCTAssertEqual(store.favorites.first?.name, "Eski")
        XCTAssertNil(store.favorites.first?.kind)
    }
}
