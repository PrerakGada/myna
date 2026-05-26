// ProjectPaletteTests.swift — exercises the FNV-1a hash + palette
// lookup (S08). Two non-negotiables:
//   1. Hex values in the table match Caravaggio's spec exactly
//   2. Same project_id always lands on the same hue (the determinism IS
//      the feature)
import XCTest

@testable import Myna

final class ProjectPaletteTests: XCTestCase {

    // MARK: - palette table

    func test_palette_has_ten_entries() {
        XCTAssertEqual(ProjectPalette.entries.count, 10)
    }

    func test_palette_hex_values_match_spec() {
        // From docs/v0.2-plan/04-visual-direction.md § 2.
        let expected: [(String, String)] = [
            ("Coral", "#FF6B6B"),
            ("Marigold", "#F2A93B"),
            ("Olive", "#A8B545"),
            ("Emerald", "#3FB46C"),
            ("Teal", "#2BB4B0"),
            ("Sky", "#4DA6FF"),
            ("Iris", "#7B5BFF"),
            ("Orchid", "#C964D4"),
            ("Rose", "#FF7AA8"),
            ("Slate", "#9098A6"),
        ]
        for (idx, (name, hex)) in expected.enumerated() {
            XCTAssertEqual(ProjectPalette.entries[idx].name, name, "slot \(idx) name")
            XCTAssertEqual(ProjectPalette.entries[idx].hex, hex, "slot \(idx) hex")
        }
    }

    func test_parseHex_decodes_to_known_values() {
        let coral = ProjectPalette.parseHex("#FF6B6B")
        XCTAssertEqual(coral.red, 1.0, accuracy: 1e-3)
        XCTAssertEqual(coral.green, Double(0x6B) / 255.0, accuracy: 1e-3)
        XCTAssertEqual(coral.blue, Double(0x6B) / 255.0, accuracy: 1e-3)

        let withoutHash = ProjectPalette.parseHex("FF6B6B")
        XCTAssertEqual(withoutHash.red, 1.0, accuracy: 1e-3)
    }

    func test_parseHex_garbage_returns_black() {
        let bad = ProjectPalette.parseHex("not-a-hex")
        XCTAssertEqual(bad, ProjectPalette.RGB(red: 0, green: 0, blue: 0))
    }

    // MARK: - FNV-1a hash

    func test_fnv1a_known_vectors() {
        // FNV-1a 32-bit known test vectors from the FNV reference impl.
        XCTAssertEqual(ProjectPalette.fnv1a32(""), 0x811c_9dc5)
        XCTAssertEqual(ProjectPalette.fnv1a32("a"), 0xe40c_292c)
        XCTAssertEqual(ProjectPalette.fnv1a32("foobar"), 0xbf9c_f968)
    }

    // MARK: - determinism

    func test_same_project_id_always_maps_to_same_color() {
        let first = ProjectPalette.color(for: "myna-repo")
        let second = ProjectPalette.color(for: "myna-repo")
        XCTAssertEqual(first.index, second.index)
        XCTAssertEqual(first.hex, second.hex)
    }

    func test_different_project_ids_can_collide_but_some_distinct() {
        // Sanity: at least 5 distinct hues across 50 sample ids.
        let ids = (0..<50).map { "project-\($0)" }
        let hues = Set(ids.map { ProjectPalette.color(for: $0).index })
        XCTAssertGreaterThanOrEqual(hues.count, 5, "FNV-1a distribution should hit ≥5 palette slots over 50 inputs")
    }

    func test_index_always_in_range() {
        for id in ["", "x", "a-very-long-project-id-with-dashes-and-numbers-123"] {
            let entry = ProjectPalette.color(for: id)
            XCTAssertTrue(entry.index >= 0 && entry.index < 10)
        }
    }
}
