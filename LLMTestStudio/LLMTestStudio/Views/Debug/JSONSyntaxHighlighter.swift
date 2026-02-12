import SwiftUI

enum JSONSyntaxHighlighter {

    static func highlight(_ text: String) -> AttributedString {
        guard let data = text.data(using: .utf8),
              (try? JSONSerialization.jsonObject(with: data)) != nil else {
            return plainAttributed(text)
        }
        return colorize(text)
    }

    // MARK: - Private

    private static let monoFont = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)

    private static func plainAttributed(_ text: String) -> AttributedString {
        var result = AttributedString(text)
        result.font = .system(size: 11, design: .monospaced)
        return result
    }

    private static func colorize(_ json: String) -> AttributedString {
        var result = AttributedString()
        let scalars = Array(json.unicodeScalars)
        var i = 0

        while i < scalars.count {
            let c = scalars[i]

            if c == "\"" {
                let (str, end) = consumeString(scalars, from: i)
                // Determine if this string is a key (followed by ':')
                let isKey = isObjectKey(scalars, afterStringEndingAt: end)
                var attr = AttributedString(str)
                attr.font = .init(monoFont)
                attr.foregroundColor = isKey ? .blue : .systemGreen
                result.append(attr)
                i = end
            } else if c == "-" || c.isDigit {
                let (num, end) = consumeNumber(scalars, from: i)
                var attr = AttributedString(num)
                attr.font = .init(monoFont)
                attr.foregroundColor = .purple
                result.append(attr)
                i = end
            } else if matchesLiteral(scalars, at: i, literal: "true") {
                result.append(styledLiteral("true"))
                i += 4
            } else if matchesLiteral(scalars, at: i, literal: "false") {
                result.append(styledLiteral("false"))
                i += 5
            } else if matchesLiteral(scalars, at: i, literal: "null") {
                result.append(styledLiteral("null"))
                i += 4
            } else if "{}[]:,".unicodeScalars.contains(c) {
                var attr = AttributedString(String(c))
                attr.font = .init(monoFont)
                attr.foregroundColor = .secondary
                result.append(attr)
                i += 1
            } else {
                // Whitespace or other characters
                var attr = AttributedString(String(c))
                attr.font = .init(monoFont)
                result.append(attr)
                i += 1
            }
        }

        return result
    }

    private static func consumeString(_ scalars: [Unicode.Scalar], from start: Int) -> (String, Int) {
        var i = start + 1 // skip opening quote
        var chars: [Unicode.Scalar] = [scalars[start]]

        while i < scalars.count {
            let c = scalars[i]
            chars.append(c)
            if c == "\\" && i + 1 < scalars.count {
                i += 1
                chars.append(scalars[i])
            } else if c == "\"" {
                i += 1
                break
            }
            i += 1
        }

        return (String(String.UnicodeScalarView(chars)), i)
    }

    private static func consumeNumber(_ scalars: [Unicode.Scalar], from start: Int) -> (String, Int) {
        var i = start
        var chars: [Unicode.Scalar] = []
        let numberChars: Set<Unicode.Scalar> = [
            "0", "1", "2", "3", "4", "5", "6", "7", "8", "9",
            ".", "-", "+", "e", "E",
        ]

        while i < scalars.count, numberChars.contains(scalars[i]) {
            chars.append(scalars[i])
            i += 1
        }

        return (String(String.UnicodeScalarView(chars)), i)
    }

    private static func isObjectKey(_ scalars: [Unicode.Scalar], afterStringEndingAt end: Int) -> Bool {
        var i = end
        while i < scalars.count, scalars[i] == " " || scalars[i] == "\t" || scalars[i] == "\n" || scalars[i] == "\r" {
            i += 1
        }
        return i < scalars.count && scalars[i] == ":"
    }

    private static func matchesLiteral(_ scalars: [Unicode.Scalar], at start: Int, literal: String) -> Bool {
        let litScalars = Array(literal.unicodeScalars)
        guard start + litScalars.count <= scalars.count else { return false }
        for j in 0..<litScalars.count {
            if scalars[start + j] != litScalars[j] { return false }
        }
        // Ensure literal isn't part of a larger token
        let afterEnd = start + litScalars.count
        if afterEnd < scalars.count {
            let next = scalars[afterEnd]
            if next.isAlpha || next.isDigit { return false }
        }
        return true
    }

    private static func styledLiteral(_ text: String) -> AttributedString {
        var attr = AttributedString(text)
        attr.font = .init(monoFont)
        attr.foregroundColor = .orange
        return attr
    }
}

// MARK: - Unicode.Scalar Helpers

private extension Unicode.Scalar {
    var isDigit: Bool { ("0"..."9").contains(self) }
    var isAlpha: Bool { ("a"..."z").contains(self) || ("A"..."Z").contains(self) }
}
