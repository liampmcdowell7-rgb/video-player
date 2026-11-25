import XCTest
@testable import ScreenChecks

/// R471 (32), PROVISIONAL: the About section's age card leads with the rating as a large bold figure, with no visible
/// heading; the heading stays the card's spoken name. Structure only, from the source: nothing is compiled or run on tvOS.
extension ScreenChecksTests {
    func testTheAgeCardLeadsWithTheRatingInLargeBoldType() throws {
        guard let sections = try appSource("App/Shared/ProductSectionsView.swift") else { return }
        XCTAssertTrue(sections.contains("FittingText(guidance.rating, style: .title1)\n                                .fontWeight(.bold)"))
        XCTAssertFalse(sections.contains("FittingText(AgeGuidance.heading, style: .headline)"), "no visible heading on the card")
        XCTAssertTrue(sections.contains(#".accessibilityLabel("\(AgeGuidance.heading), rated \(guidance.rating)")"#))
    }

    /// R471 (33): an Accessibility entry is drawn as its outlined badge, spoken by its full name.
    func testAccessibilityEntriesAreOutlinedBadges() throws {
        guard let sections = try appSource("App/Shared/ProductSectionsView.swift") else { return }
        XCTAssertTrue(sections.contains("if let badge = entry.badge {"))
        XCTAssertTrue(sections.contains("BadgeOutline(text: badge)\n                            .accessibilityLabel(entry.label)"))
    }
}
