import SwiftUI
import AppLogic

/// One source type in the list (#15 2.1, rule L9): its name and ONE short line (#25 B1, `SourceSetupText.rowLine`). The
/// status, any caveat, and the reason a type cannot be set up are on "About Source Types" (the list's Learn More page) and,
/// for an available type, on its form's Learn More page: nothing disappears, it is one press away.
/// #36 group 5 (OPEN_QUESTIONS R257, PROVISIONAL): a type that is not available yet has its NAME in the secondary level too,
/// so it looks different from the available types (run of 20 Nov, 20: all rows looked the same). The hierarchical
/// `.secondary` level of the TaskPage Form is `ReadableSecondary.style` (#36 S-A, R253; 5.28:1 or more, R240), a style the
/// system supports; the row stays a focusable system row that opens About Source Types.
struct SourceKindRow: View {
    let info: SourceKindInfo

    var body: some View {
        VStack(alignment: .leading) {
            if info.isAvailable {
                FittingText(info.title)
            } else {
                FittingText(info.title)
                    .foregroundStyle(.secondary)
            }
            FittingText(SourceSetupText.rowLine(info.kind), style: .caption)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}
