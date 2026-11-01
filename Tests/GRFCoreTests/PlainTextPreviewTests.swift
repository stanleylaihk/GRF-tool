import AppKit
import Testing
import GRFDesktop

@MainActor
struct PlainTextPreviewTests {
    @Test func switchingLongListingToShortSourceUpdatesNativeDocument() throws {
        let view = PreviewTextScrollView()
        let listing = String(repeating: "LOADK A=0 Bx=1 ; constant\n", count: 10000)
        view.display(listing)
        let editor = try #require(view.documentView as? NSTextView)
        #expect(editor.string == listing)
        view.display("answer = 42\n")
        #expect(editor.string == "answer = 42\n")
        #expect(!editor.isEditable && editor.isSelectable)
        #expect(view.hasVerticalScroller && view.hasHorizontalScroller)
    }

    @Test func contentMatchesHighlightNavigateAndPreserveText() throws {
        let view = PreviewTextScrollView()
        let text = "中文 first\nmatch here\nMATCH again"
        view.display(text); view.highlight("match", occurrence: 0)
        let editor = try #require(view.documentView as? NSTextView)
        #expect(editor.selectedRange() == (text as NSString).range(of: "match"))
        view.highlight("match", occurrence: 1)
        #expect(editor.selectedRange() == (text as NSString).range(of: "MATCH"))
        view.highlight("match", occurrence: -1)
        #expect(editor.selectedRange() == (text as NSString).range(of: "MATCH"))
        #expect(editor.string == text)
    }

    @Test func unrelatedViewUpdatesPreserveTextSelection() throws {
        let view = PreviewTextScrollView()
        view.display("answer = 42\n")
        let editor = try #require(view.documentView as? NSTextView)
        editor.setSelectedRange(NSRange(location: 0, length: 6))
        view.display("answer = 42\n")
        #expect(editor.selectedRange() == NSRange(location: 0, length: 6))
    }
}
