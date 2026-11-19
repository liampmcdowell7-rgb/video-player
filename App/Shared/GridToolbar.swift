import SwiftUI

/// The row above the Movies and Shows grids (#15 4.5): the controls, then the count ("6 movies", "2 shows"), in one place
/// and one size on both screens, so both grids start at the same height. Each screen passes the controls it has.
struct GridToolbar<Controls: View>: View {
    let count: String?
    @ViewBuilder var controls: Controls

    var body: some View {
        HStack {
            controls
            if let count {
                Text(count)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
