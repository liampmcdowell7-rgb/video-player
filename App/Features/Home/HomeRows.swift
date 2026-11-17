import SwiftUI
import AppLogic

/// The shelves of Home, one under the other.
struct HomeRows: View {
    let rows: [HomeRow]

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading) {
                ForEach(rows) { row in
                    CardRow(row: row)
                }
            }
        }
    }
}
