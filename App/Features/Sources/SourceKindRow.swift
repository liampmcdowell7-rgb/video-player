import SwiftUI
import AppLogic

/// One source type in the list (#15 2.1, rule L9): its name and ONE short line (#25 B1, `SourceSetupText.rowLine`). The
/// status, any caveat, and the reason a type cannot be set up are on "About Source Types" (the list's Learn More page) and,
/// for an available type, on its form's Learn More page: nothing disappears, it is one press away.
struct SourceKindRow: View {
    let info: SourceKindInfo

    var body: some View {
        VStack(alignment: .leading) {
            FittingText(info.title)
            FittingText(SourceSetupText.rowLine(info.kind), style: .caption)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}
