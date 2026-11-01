import SwiftUI

// Shared by Settings and all archive-writing workflows.
enum GRFPreferences {
    static let compressionKey = "grf.compressionLevel"
    static let levels = [-1] + Array(0...9)
    static func label(_ level: Int) -> String {
        switch level {
        case -1: return "Default (balanced)"
        case 0: return "0 — No compression"
        case 1: return "1 — Fastest"
        case 9: return "9 — Maximum compression"
        default: return "\(level)"
        }
    }
}

struct GRFSettingsView: View {
    @AppStorage(GRFPreferences.compressionKey) private var level = -1
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Archive Settings").font(.title2.bold())
            Picker("Compression Level", selection: $level) {
                ForEach(GRFPreferences.levels, id: \.self) { Text(GRFPreferences.label($0)).tag($0) }
            }
            Text("Higher levels may produce smaller archives but take longer. Level 0 stores data without compression.")
                .foregroundStyle(.secondary)
            Text("Applies to the next Save or Repack, including new archives and merged or edited copies. Changing this setting does not modify existing archives.")
                .font(.caption).foregroundStyle(.secondary)
            Button("Restore Default") { level = -1 }
        }.padding(24).frame(width: 460)
        .onAppear { if !(-1...9).contains(level) { level = -1 } }
    }
}
