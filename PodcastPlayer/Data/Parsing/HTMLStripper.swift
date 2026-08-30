import Foundation

/// Converts the HTML that feeds put in `<description>` into display text.
///
/// Hand-rolled rather than using `NSAttributedString(html:)`, which must run on
/// the main thread and takes milliseconds per call — unusable when parsing a
/// feed with hundreds of episodes off the main actor.
enum HTMLStripper {
    static func plainText(from html: String) -> String {
        guard !html.isEmpty else { return "" }

        var output = ""
        output.reserveCapacity(html.count)

        var index = html.startIndex
        var skippingUntilCloseOf: String?

        while index < html.endIndex {
            let character = html[index]

            guard character == "<" else {
                if skippingUntilCloseOf == nil { output.append(character) }
                index = html.index(after: index)
                continue
            }

            guard let tagEnd = html[index...].firstIndex(of: ">") else {
                // An unclosed '<' is literal text, not a tag.
                if skippingUntilCloseOf == nil { output.append(contentsOf: html[index...]) }
                break
            }

            let tagBody = html[html.index(after: index)..<tagEnd]
            let name = tagName(of: tagBody)

            if let skipping = skippingUntilCloseOf {
                if name == skipping, tagBody.hasPrefix("/") { skippingUntilCloseOf = nil }
            } else if name == "script" || name == "style", !tagBody.hasPrefix("/") {
                // Drop the contents wholesale — it is never display text.
                skippingUntilCloseOf = name
            } else {
                output.append(replacement(for: name, isClosing: tagBody.hasPrefix("/")))
            }

            index = html.index(after: tagEnd)
        }

        return normalizeWhitespace(decodeEntities(output))
    }

    /// The lowercased element name, ignoring any leading slash and attributes.
    private static func tagName(of body: Substring) -> String {
        let withoutSlash = body.hasPrefix("/") ? body.dropFirst() : body
        let name = withoutSlash.prefix { !$0.isWhitespace && $0 != "/" }
        return name.lowercased()
    }

    /// Block-level elements become breaks so paragraphs survive; everything
    /// else vanishes without joining words together.
    ///
    /// Line-level elements break on their opening tag only. Breaking on both
    /// would turn every list item into its own paragraph.
    private static func replacement(for name: String, isClosing: Bool) -> String {
        switch name {
        case "br": "\n"
        case "p", "div", "section", "article", "h1", "h2", "h3", "h4", "h5", "h6", "blockquote": "\n\n"
        case "li", "tr": isClosing ? "" : "\n"
        default: ""
        }
    }

    private static let namedEntities: [String: String] = [
        "amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'",
        "nbsp": "\u{00A0}", "hellip": "…", "mdash": "—", "ndash": "–",
        "rsquo": "\u{2019}", "lsquo": "\u{2018}", "ldquo": "\u{201C}", "rdquo": "\u{201D}",
    ]

    private static func decodeEntities(_ text: String) -> String {
        guard text.contains("&") else { return text }

        var output = ""
        output.reserveCapacity(text.count)
        var index = text.startIndex

        while index < text.endIndex {
            guard text[index] == "&",
                  let semicolon = text[index...].firstIndex(of: ";"),
                  text.distance(from: index, to: semicolon) <= 10 else {
                output.append(text[index])
                index = text.index(after: index)
                continue
            }

            let body = text[text.index(after: index)..<semicolon]

            if let decoded = decode(entityBody: body) {
                output.append(decoded)
                index = text.index(after: semicolon)
            } else {
                // Unknown entity: leave it exactly as the publisher wrote it.
                output.append(text[index])
                index = text.index(after: index)
            }
        }

        return output
    }

    private static func decode(entityBody body: Substring) -> String? {
        if let named = namedEntities[body.lowercased()] { return named }

        guard body.hasPrefix("#") else { return nil }

        let digits = body.dropFirst()
        let scalarValue: UInt32?
        if digits.first == "x" || digits.first == "X" {
            scalarValue = UInt32(digits.dropFirst(), radix: 16)
        } else {
            scalarValue = UInt32(digits, radix: 10)
        }

        guard let value = scalarValue, let scalar = Unicode.Scalar(value) else { return nil }
        return String(Character(scalar))
    }

    /// Removes the runs of blank space that tag removal leaves behind, without
    /// destroying the paragraph structure we just preserved.
    private static func normalizeWhitespace(_ text: String) -> String {
        let unified = text.replacingOccurrences(of: "\u{00A0}", with: " ")

        let paragraphs = unified
            .components(separatedBy: "\n")
            .map { line in
                line.split(separator: " ", omittingEmptySubsequences: true)
                    .joined(separator: " ")
                    .trimmingCharacters(in: .whitespaces)
            }

        // Collapse any run of blank lines down to a single blank line.
        var lines: [String] = []
        for paragraph in paragraphs {
            if paragraph.isEmpty, lines.last?.isEmpty ?? true { continue }
            lines.append(paragraph)
        }
        while lines.last?.isEmpty == true { lines.removeLast() }

        return lines.joined(separator: "\n")
            .replacingOccurrences(of: "\n\n", with: "\u{0000}")
            .replacingOccurrences(of: "\n", with: "\n")
            .replacingOccurrences(of: "\u{0000}", with: "\n\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
