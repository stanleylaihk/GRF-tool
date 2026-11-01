import AppKit
import SwiftUI

/// Native text scrolling avoids SwiftUI selectable-Text layout cycles when previews change.
public struct PlainTextPreview: NSViewRepresentable {
    public let text: String
    public var query: String
    public var occurrence: Int
    public init(text: String, query: String = "", occurrence: Int = 0) { self.text = text; self.query = query; self.occurrence = occurrence }
    public func makeNSView(context: Context) -> PreviewTextScrollView { PreviewTextScrollView() }
    public func updateNSView(_ view: PreviewTextScrollView, context: Context) { view.display(text); view.highlight(query, occurrence: occurrence) }
}

public final class PreviewTextScrollView: NSScrollView {
    private let editor = NSTextView(frame: NSRect(x: 0, y: 0, width: 300, height: 200))
    private var displayedText: String?

    private var highlightKey = ""

    public init() {
        super.init(frame: NSRect(x: 0, y: 0, width: 300, height: 200))
        configure()
    }
    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        configure()
    }
    private func configure() {
        hasVerticalScroller = true
        hasHorizontalScroller = true
        autohidesScrollers = true
        borderType = .noBorder
        editor.isEditable = false
        editor.isSelectable = true
        editor.isRichText = false
        editor.usesFindBar = true
        editor.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        editor.textColor = .labelColor
        editor.backgroundColor = .textBackgroundColor
        editor.textContainerInset = NSSize(width: 12, height: 12)
        editor.minSize = .zero
        editor.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        editor.isVerticallyResizable = true
        editor.isHorizontallyResizable = true
        editor.autoresizingMask = [.width]
        editor.textContainer?.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        editor.textContainer?.widthTracksTextView = false
        documentView = editor
    }
    public func display(_ text: String) {
        guard displayedText != text else { return }
        displayedText = text
        highlightKey = "\0reset"
        editor.string = text
        editor.setSelectedRange(NSRange(location: 0, length: 0))
        editor.scrollRangeToVisible(NSRange(location: 0, length: 0))
    }
    public func highlight(_ query: String, occurrence: Int) {
        let key = query + "\0" + String(occurrence)
        guard key != highlightKey else { return }
        highlightKey = key
        let ns = editor.string as NSString
        editor.layoutManager?.removeTemporaryAttribute(.backgroundColor, forCharacterRange: NSRange(location: 0, length: ns.length))
        guard !query.isEmpty else { return }
        var ranges: [NSRange] = [], remaining = NSRange(location: 0, length: ns.length)
        while remaining.length > 0 && ranges.count < 10000 {
            let found = ns.range(of: query, options: [.caseInsensitive], range: remaining)
            if found.location == NSNotFound { break }
            ranges.append(found)
            editor.layoutManager?.addTemporaryAttribute(.backgroundColor, value: NSColor.systemYellow.withAlphaComponent(0.35), forCharacterRange: found)
            let end = found.location + max(1, found.length); remaining = NSRange(location: end, length: ns.length-end)
        }
        if !ranges.isEmpty {
            let index = ((occurrence % ranges.count) + ranges.count) % ranges.count
            editor.setSelectedRange(ranges[index]); editor.scrollRangeToVisible(ranges[index])
        }
    }

}
