import SwiftUI
import AppLogic

/// R471 (19), PROVISIONAL: Analyze File in a cover. It starts as the cover opens: the step under way is named in the status
/// lines with the system progress indicator beside the button; when it is done the status lines say what was found (L3:
/// status is text, never rows). Analyze Again runs it once more. Menu closes the cover. Layout: `SettingsPane`, system rows.
struct AnalyzeFileView: View {
    let itemID: Int64
    let title: String
    @Environment(AppServices.self) private var services
    @State private var step: FileAnalysis.Step?
    @State private var report: FileAnalysis.Report?
    @State private var missing = false
    @State private var run = 0

    var body: some View {
        SettingsPane(title: FileAnalysis.title, summary: title, status: status) {
            Section {
                Button {
                    run += 1
                } label: {
                    LabeledContent("Analyze Again") {
                        if step != nil { ProgressView() }
                    }
                }
                .disabled(step != nil)
            }
        }
        .task(id: run) {
            report = nil
            missing = false
            let analyzer = services.fileAnalyzer
            let found = await analyzer.run(itemID: itemID) { next in await MainActor.run { step = next } }
            step = nil
            report = found
            missing = found == nil
        }
    }

    private var status: [String] {
        if missing { return [FileAnalysis.noFile] }
        if let step { return [step.title + "…"] }
        guard let report else { return [] }
        return [FileAnalysis.done] + FileAnalysis.lines(report)
    }
}
