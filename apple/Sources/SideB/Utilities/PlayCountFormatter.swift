import Foundation

/// Presents the provider's abbreviated play count ("53M", "1.2B", "1,234") with the app language's
/// separators and suffixes ("53 M", "1,2 mil M"). Unrecognised or empty values yield nil, never raw text.
enum PlayCountFormatter {
    private static let pattern = try! NSRegularExpression(pattern: #"^(\d[\d.,]*)\s*([KMB])?$"#, options: [.caseInsensitive])

    static func display(_ raw: String?, language: AppLanguage? = nil) -> String? {
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return nil }
        let range = NSRange(raw.startIndex..., in: raw)
        guard let match = pattern.firstMatch(in: raw, range: range),
              let numberRange = Range(match.range(at: 1), in: raw) else { return nil }
        let language = language ?? L10n.language
        let number = String(raw[numberRange])
        let formatter = NumberFormatter()
        formatter.locale = language.locale
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 1
        formatter.minimumFractionDigits = 0
        let suffix = Range(match.range(at: 2), in: raw).map { raw[$0].uppercased() }
        if let suffix {
            // "1.2" always uses a dot in the provider's pinned English locale.
            guard let value = Double(number) else { return nil }
            let key = ["K": "detail.track.plays.thousand", "M": "detail.track.plays.million", "B": "detail.track.plays.billion"][suffix]!
            return L10n.text(key, args: [formatter.string(from: NSNumber(value: value)) ?? number], language: language)
        }
        guard let value = Int(number.filter(\.isNumber)) else { return nil }
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: value))
    }
}
