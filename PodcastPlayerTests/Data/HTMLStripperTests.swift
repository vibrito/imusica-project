import Testing
import Foundation
@testable import PodcastPlayer

@Suite("HTMLStripper")
struct HTMLStripperTests {
    @Test("Removes tags and keeps the text")
    func removesTagsAndKeepsText() {
        #expect(HTMLStripper.plainText(from: "<p>Hello <b>world</b></p>") == "Hello world")
    }

    @Test("Turns paragraphs into blank-line separated text")
    func preservesParagraphBreaks() {
        #expect(HTMLStripper.plainText(from: "<p>One</p><p>Two</p>") == "One\n\nTwo")
    }

    @Test("Converts line break tags in every spelling", arguments: ["<br>", "<br/>", "<br />", "<BR/>"])
    func convertsLineBreakTags(tag: String) {
        #expect(HTMLStripper.plainText(from: "A\(tag)B") == "A\nB")
    }

    @Test("Turns list items into lines")
    func convertsListItemsToLines() {
        #expect(HTMLStripper.plainText(from: "<ul><li>One</li><li>Two</li></ul>") == "One\nTwo")
    }

    @Test("Decodes the entities feeds actually use")
    func decodesCommonEntities() {
        #expect(HTMLStripper.plainText(from: "Tom &amp; Jerry") == "Tom & Jerry")
        #expect(HTMLStripper.plainText(from: "&lt;tag&gt;") == "<tag>")
        #expect(HTMLStripper.plainText(from: "&quot;quoted&quot;") == "\"quoted\"")
        #expect(HTMLStripper.plainText(from: "it&#39;s") == "it's")
        #expect(HTMLStripper.plainText(from: "caf&#233;") == "café")
        #expect(HTMLStripper.plainText(from: "a&nbsp;b") == "a b")
        #expect(HTMLStripper.plainText(from: "&#x2014;") == "—")
    }

    @Test("Leaves an unknown entity alone rather than mangling it")
    func leavesUnknownEntitiesIntact() {
        #expect(HTMLStripper.plainText(from: "100 &percnt; sure") == "100 &percnt; sure")
    }

    @Test("Collapses the whitespace that tag removal leaves behind")
    func collapsesExcessiveWhitespace() {
        #expect(HTMLStripper.plainText(from: "<p>A</p>\n\n\n\n<p>B</p>") == "A\n\nB")
        #expect(HTMLStripper.plainText(from: "A     B") == "A B")
    }

    @Test("Passes plain text through untouched")
    func passesPlainTextThrough() {
        #expect(HTMLStripper.plainText(from: "Just a description.") == "Just a description.")
    }

    @Test("Handles empty and whitespace-only input")
    func handlesEmptyInput() {
        #expect(HTMLStripper.plainText(from: "") == "")
        #expect(HTMLStripper.plainText(from: "   \n  ") == "")
    }

    @Test("Drops script and style contents entirely")
    func dropsScriptAndStyleContent() {
        #expect(HTMLStripper.plainText(from: "A<script>var x = 1;</script>B") == "AB")
        #expect(HTMLStripper.plainText(from: "A<style>.x { color: red }</style>B") == "AB")
    }
}
