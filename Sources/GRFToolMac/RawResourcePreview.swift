import SwiftUI
import GRFCore
import GRFDesktop

struct RawResourcePreview: View {
    let document: ResourceInspection
    let reason: String?
    @State private var tab = "Info"
    var body: some View {
        VStack(spacing: 0) {
            Picker(L10n.text("Resource view"), selection: $tab) {
                Text(L10n.text("Info")).tag("Info"); Text(L10n.text("Strings")).tag("Strings"); Text(L10n.text("Hex")).tag("Hex")
            }.pickerStyle(.segmented).padding(10)
            if let reason { Text(L10n.value(reason)).font(.caption).foregroundStyle(.secondary).padding(10).textSelection(.enabled) }
            PlainTextPreview(text: tab == "Info" ? document.summary : tab == "Strings" ? document.strings : document.hex)
        }
    }
}
