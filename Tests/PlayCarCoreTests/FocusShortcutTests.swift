import XCTest
@testable import PlayCarCore

final class FocusShortcutTests: XCTestCase {
    func testRunURLUsesXCallbackAndReturnsToPlayCar() throws {
        let url = FocusShortcut.runURL(turnOn: true)
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        XCTAssertEqual(components.scheme, "shortcuts")
        XCTAssertEqual(components.host, "x-callback-url")
        XCTAssertEqual(components.path, "/run-shortcut")
        let query = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") })
        XCTAssertEqual(query["name"], "PlayCar DND")
        XCTAssertEqual(query["input"], "text")
        XCTAssertEqual(query["text"], "on")
        XCTAssertEqual(query["x-success"], "playcar://dnd/on")
        XCTAssertEqual(query["x-error"], "playcar://dnd/error")
        XCTAssertTrue(url.absoluteString.contains("PlayCar%20DND"))

        let off = try XCTUnwrap(URLComponents(url: FocusShortcut.runURL(turnOn: false), resolvingAgainstBaseURL: false))
        XCTAssertTrue(off.queryItems?.contains(URLQueryItem(name: "text", value: "off")) ?? false)
    }

    func testParsesCallbacks() throws {
        XCTAssertEqual(FocusShortcut.parse(try XCTUnwrap(URL(string: "playcar://dnd/on"))), .on)
        XCTAssertEqual(FocusShortcut.parse(try XCTUnwrap(URL(string: "playcar://dnd/off"))), .off)
        XCTAssertEqual(FocusShortcut.parse(try XCTUnwrap(URL(string: "playcar://dnd/cancel"))), .cancel)
        XCTAssertEqual(FocusShortcut.parse(try XCTUnwrap(URL(string: "playcar://dnd/error?errorMessage=Not%20found"))),
                       .error("Not found"))
        XCTAssertNil(FocusShortcut.parse(try XCTUnwrap(URL(string: "playcar://other/on"))))
        XCTAssertNil(FocusShortcut.parse(try XCTUnwrap(URL(string: "https://dnd/on"))))
    }
}
