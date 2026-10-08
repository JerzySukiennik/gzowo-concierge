// Gzowo Concierge for macOS - reply text for the notch: markdown-lite, chemical formulas and sub/superscripts as Unicode.
import Foundation

enum NotchText {
    private static let sub: [Character: Character] = ["0": "₀", "1": "₁", "2": "₂", "3": "₃", "4": "₄", "5": "₅", "6": "₆", "7": "₇", "8": "₈", "9": "₉", "+": "₊", "-": "₋", "(": "₍", ")": "₎", "=": "₌", "a": "ₐ", "e": "ₑ", "o": "ₒ", "x": "ₓ", "n": "ₙ", "i": "ᵢ"]
    private static let sup: [Character: Character] = ["0": "⁰", "1": "¹", "2": "²", "3": "³", "4": "⁴", "5": "⁵", "6": "⁶", "7": "⁷", "8": "⁸", "9": "⁹", "+": "⁺", "-": "⁻", "−": "⁻", "(": "⁽", ")": "⁾", "=": "⁼", "n": "ⁿ", "i": "ⁱ"]

    private static func map(_ s: String, _ table: [Character: Character]) -> String? {
        var out = ""
        for c in s { guard let m = table[c] else { return nil }; out.append(m) }
        return out
    }

    private static func replace(_ s: String, _ pattern: String, _ f: (NSTextCheckingResult, NSString) -> String?) -> String {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return s }
        let ns = s as NSString
        var out = "", last = 0
        for m in re.matches(in: s, range: NSRange(location: 0, length: ns.length)) {
            out += ns.substring(with: NSRange(location: last, length: m.range.location - last))
            out += f(m, ns) ?? ns.substring(with: m.range)
            last = m.range.location + m.range.length
        }
        return out + ns.substring(from: last)
    }

    private static func scripts(_ input: String) -> String {
        var s = input
        s = replace(s, "<sub>(.*?)</sub>") { m, ns in map(ns.substring(with: m.range(at: 1)), sub) }
        s = replace(s, "<sup>(.*?)</sup>") { m, ns in map(ns.substring(with: m.range(at: 1)), sup) }
        s = replace(s, "_\\{([^}]{1,8})\\}") { m, ns in map(ns.substring(with: m.range(at: 1)), sub) }
        s = replace(s, "\\^\\{([^}]{1,8})\\}") { m, ns in map(ns.substring(with: m.range(at: 1)), sup) }
        s = replace(s, "(?<=[A-Z\\)])_([0-9]{1,3})") { m, ns in map(ns.substring(with: m.range(at: 1)), sub) }
        s = replace(s, "(?<=[A-Za-z0-9\\)])\\^([0-9+\\-−]{1,4})") { m, ns in map(ns.substring(with: m.range(at: 1)), sup) }
        s = s.replacingOccurrences(of: "$", with: "")
        return s
    }

    private static func formulas(_ input: String) -> String {
        replace(input, "(?<![A-Za-zĄĆĘŁŃÓŚŹŻąćęłńóśźż0-9_])((?:[A-Z][a-z]?\\d*|\\([A-Za-z0-9]+\\)\\d*){1,8})((?:\\d?[+−-])?)(?![A-Za-zĄĆĘŁŃÓŚŹŻąćęłńóśźż0-9_])") { m, ns in
            let tok = ns.substring(with: m.range(at: 1))
            let charge = ns.substring(with: m.range(at: 2))
            guard tok.contains(where: { $0.isNumber }) || !charge.isEmpty else { return nil }
            let groups = tok.filter { $0.isUppercase }.count
            if groups < 2 && !["H2", "O2", "N2", "F2"].contains(tok) && charge.isEmpty { return nil }
            if groups < 2 && tok.count <= 2 && charge.isEmpty && !["H2", "O2", "N2", "F2"].contains(tok) { return nil }
            var out = ""
            var prev: Character = " "
            if groups == 1 && !charge.isEmpty, let last = tok.last, last.isNumber, let sp = map(String(last), sup), let sc = map(charge.replacingOccurrences(of: "-", with: "−"), sup) {
                return String(tok.dropLast()) + sp + sc
            }
            for c in tok {
                if c.isNumber, prev.isLetter || prev == ")" { out.append(sub[c] ?? c) } else { out.append(c) }
                prev = c
            }
            if !charge.isEmpty, let sp = map(charge.replacingOccurrences(of: "-", with: "−"), sup) { out += sp }
            return out
        }
    }

    static func display(_ raw: String) -> String {
        var lines: [String] = []
        for line in raw.components(separatedBy: "\n") {
            var l = line
            let t = l.trimmingCharacters(in: .whitespaces)
            if let r = t.range(of: "^#{1,4}\\s+", options: .regularExpression) {
                let h = String(t[r.upperBound...]).trimmingCharacters(in: .whitespaces)
                l = h.hasPrefix("**") ? h : "**\(h)**"
            } else if t.hasPrefix("- ") || t.hasPrefix("* ") || t.hasPrefix("• ") {
                l = "•  " + t.dropFirst(2)
            } else if t == "---" || t == "***" {
                l = ""
            }
            lines.append(l)
        }
        var s = lines.joined(separator: "\n")
        s = scripts(s)
        s = formulas(s)
        while s.contains("\n\n\n") { s = s.replacingOccurrences(of: "\n\n\n", with: "\n\n") }
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func attributed(_ raw: String) -> AttributedString {
        let s = display(raw)
        let opts = AttributedString.MarkdownParsingOptions(allowsExtendedAttributes: false, interpretedSyntax: .inlineOnlyPreservingWhitespace, failurePolicy: .returnPartiallyParsedIfPossible)
        return (try? AttributedString(markdown: s, options: opts)) ?? AttributedString(s)
    }

    static func plain(_ raw: String) -> String {
        display(raw).replacingOccurrences(of: "**", with: "").replacingOccurrences(of: "`", with: "")
    }
}
