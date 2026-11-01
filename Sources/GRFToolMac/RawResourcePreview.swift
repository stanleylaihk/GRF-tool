import SwiftUI
import GRFCore
import GRFDesktop

struct RawResourcePreview: View {
    let document: ResourceInspection
    let reason: String?
    @State private var tab = "Info"
    var body: some View {
        VStack(spacing: 0) {
            Picker("Resource view", selection: $tab) {
                Text("Info").tag("Info"); Text("Strings").tag("Strings"); Text("Hex").tag("Hex")
            }.pickerStyle(.segmented).padding(10)
            if let reason { Text(reason).font(.caption).foregroundStyle(.secondary).padding(10).textSelection(.enabled) }
            PlainTextPreview(text: tab == "Info" ? document.summary : tab == "Strings" ? document.strings : document.hex)
        }
    }
}
