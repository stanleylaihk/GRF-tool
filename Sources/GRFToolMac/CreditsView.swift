import SwiftUI
import GRFDesktop

private struct Credit: Identifiable {
    let name: String
    let author: String
    let purpose: String
    let url: String?
    let license: String
    var id: String { name }
}
struct CreditsView: View {
    @State private var tab = "Credits"
    private let sources: [Credit] = [
        .init(name: "OpenKore / grftool", author: "Faithful, Hongli Lai, Rasqual and contributors", purpose: "GRF cryptography implementation; archive and sprite format reference.", url: "https://github.com/OpenKore/grftool", license: "GPL-2.0-or-later · code included with preserved notices"),
        .init(name: "Ragnarok Research Lab", author: "Ragnarok Research Lab authors and contributors", purpose: "SPR, ACT, PAL, GAT, GND, RSW, RSM, IMF and GR2 format research.", url: "https://ragnarokresearchlab.github.io/", license: "Documentation reference; site retains its own copyright"),
        .init(name: "RagnarokFileFormats", author: "rdw / Ragnarok Research Lab contributors", purpose: "Historical format specifications and coordinate research.", url: "https://github.com/rdw-archive/RagnarokFileFormats", license: "Reference only"),
        .init(name: "roBrowser", author: "Vincent Thibault and contributors", purpose: "RSM / RSW binary layout and scene transform cross-check.", url: "https://github.com/vthibault/roBrowser", license: "Reference only; no JavaScript renderer bundled"),
        .init(name: "roBrowserLegacy", author: "MrAntares and contributors", purpose: "ACT format behavior reference.", url: "https://github.com/MrAntares/roBrowserLegacy", license: "Reference only"),
        .init(name: "GRFEditor", author: "Tokeiburu and contributors", purpose: "FNA length-prefixed resource-name layout reference.", url: "https://github.com/Tokeiburu/GRFEditor", license: "Reference only; no application code bundled"),
        .init(name: "granny-ro-js", author: "Stitchuuuu", purpose: "Native Swift Oodle-0 port and bundled GR2 object, mesh, pose and embedded-texture reader.", url: "https://github.com/Stitchuuuu/granny-ro-js", license: "MIT · adapted decoder and bundled reader; full notices included"),
        .init(name: "blendergranny", author: "ciupix and contributors / Rasetsuu", purpose: "Clean-room Python Oodle-0 implementation credited by granny-ro-js.", url: "https://github.com/Rasetsuu/blendergranny", license: "MIT · full notices included"),
        .init(name: "noclip.website", author: "noclip.website contributors", purpose: "Historical Granny DLL API reference used during decompressor research.", url: "https://github.com/magcius/noclip.website", license: "MIT · research reference only"),
        .init(name: "OpenGR2", author: "arves100 and contributors", purpose: "GR2 physical format reference and compatibility research.", url: "https://github.com/arves100/opengr2", license: "Reference only"),
        .init(name: "zlib", author: "Jean-loup Gailly and Mark Adler", purpose: "System compression / decompression library.", url: "https://zlib.net", license: "zlib license · system library"),
        .init(name: "Apple frameworks", author: "Apple Inc.", purpose: "SwiftUI, AppKit, SceneKit, JavaScriptCore, AVFoundation and system image decoding.", url: "https://developer.apple.com/documentation/", license: "System frameworks"),
        .init(name: "REA", author: "REA contributors", purpose: "Static inspection of the supplied Windows reference tools and Granny runtime.", url: "https://github.com/morluto/rea", license: "Development tool; not bundled"),
        .init(name: "Unicorn", author: "Unicorn Engine contributors", purpose: "Isolated x86 replay for original-DLL / Swift decompressor parity tests.", url: "https://github.com/unicorn-engine/unicorn", license: "Development tool; not bundled")
    ]
    private let originals: [Credit] = [
        .init(name: "grftool.exe · GRF Tool 1.2.0", author: "OpenKore / GRF Tool contributors", purpose: "Original supplied reference for archive browsing, extraction and previews.", url: "https://github.com/OpenKore/grftool", license: "Reference executable only · not redistributed"),
        .init(name: "grfbuilder.exe · GRFBuilder 0.1.30", author: "MagicalTux (identified in supplied README)", purpose: "Original supplied reference for merging, deletion, compression and repacking.", url: "http://www.grfbuilder.com/", license: "Reference only; supplied library README states it is not open source"),
        .init(name: "SPRViewer.exe", author: "Author not confirmed in supplied records", purpose: "Original supplied reference for sprite decoding and bitmap frame export.", url: nil, license: "Reference executable only · not redistributed")
    ]
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text("GRF Tool").font(.largeTitle.weight(.semibold))
                Text("Credits, original tools & open-source acknowledgements").foregroundStyle(.secondary)
            }.padding(22)
            Picker("Credits view", selection: $tab) {
                Text("Credits").tag("Credits"); Text("Original Tools").tag("Tools"); Text("Licenses").tag("Licenses")
            }.pickerStyle(.segmented).padding(.horizontal, 22).padding(.bottom, 14)
            Divider()
            if tab == "Licenses" {
                PlainTextPreview(text: notices)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 18) {
                        ForEach(tab == "Tools" ? originals : sources) { credit in
                            VStack(alignment: .leading, spacing: 5) {
                                Text(credit.name).font(.headline)
                                Text(credit.author).font(.callout)
                                Text(credit.purpose).font(.callout).foregroundStyle(.secondary)
                                Text(credit.license).font(.caption).foregroundStyle(.secondary)
                                if let url = credit.url, let target = URL(string: url) { Link(url, destination: target).font(.caption) }
                            }.textSelection(.enabled)
                            Divider()
                        }
                    }.padding(22)
                }
            }
        }.frame(idealWidth: 740, idealHeight: 650)
    }
    private var notices: String {
        guard let url = Bundle.main.url(forResource: "THIRD_PARTY_NOTICES", withExtension: "md"), let text = try? String(contentsOf: url, encoding: .utf8) else {
            return "Full license notices are included in the release app's Resources/THIRD_PARTY_NOTICES.md and the project THIRD_PARTY_NOTICES.md."
        }
        return text
    }
}
