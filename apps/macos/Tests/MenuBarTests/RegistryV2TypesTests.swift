// RegistryV2TypesTests.swift — round-trip encode/decode the new Track B
// contract types so a future schema drift fails fast.
//
// swiftlint:disable force_unwrapping non_optional_string_data_conversion
import XCTest

@testable import Myna

final class RegistryV2TypesTests: XCTestCase {

    func test_registry_item_round_trip_uses_snake_case_keys() throws {
        let item = RegistryV2Item(
            id: "id1",
            source: "claude-code",
            projectId: "myna",
            title: "tests passing",
            announcedAtMs: 1_700_000_000_000,
            ttlS: 600
        )
        let data = try JSONEncoder().encode(item)
        let json = String(data: data, encoding: .utf8) ?? ""
        XCTAssertTrue(json.contains("\"project_id\""))
        XCTAssertTrue(json.contains("\"announced_at_ms\""))
        XCTAssertTrue(json.contains("\"ttl_s\""))

        let decoded = try JSONDecoder().decode(RegistryV2Item.self, from: data)
        XCTAssertEqual(decoded, item)
    }

    func test_registry_list_response_decodes_empty_pending() throws {
        let json = #"{"pending":[]}"#.data(using: .utf8)!
        let resp = try JSONDecoder().decode(RegistryListResponse.self, from: json)
        XCTAssertTrue(resp.pending.isEmpty)
    }

    func test_announce_request_uses_snake_case() throws {
        let req = RegistryAnnounceRequest(
            source: "claude-code", projectId: "myna", title: "done", ttlS: 600
        )
        let data = try JSONEncoder().encode(req)
        let json = String(data: data, encoding: .utf8) ?? ""
        XCTAssertTrue(json.contains("\"project_id\""))
        XCTAssertTrue(json.contains("\"ttl_s\""))
    }

    func test_age_seconds_zero_at_announce_time() {
        let now = Int(Date().timeIntervalSince1970 * 1000)
        let item = RegistryV2Item(
            id: "x", source: "s", projectId: "p", title: "t", announcedAtMs: now, ttlS: 600
        )
        XCTAssertLessThan(item.ageSeconds(), 2)  // sub-2-second slop
    }

    func test_preview_truncates_long_titles() {
        let item = RegistryV2Item(
            id: "x", source: "s", projectId: "p",
            title: String(repeating: "z", count: 200),
            announcedAtMs: 0, ttlS: 0
        )
        let preview = item.preview(maxLength: 10)
        XCTAssertEqual(preview.count, 11)
        XCTAssertTrue(preview.hasSuffix("…"))
    }
}

// swiftlint:enable force_unwrapping non_optional_string_data_conversion
