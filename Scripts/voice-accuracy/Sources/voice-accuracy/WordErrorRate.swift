import Foundation

/// Word error rate: (substitutions + deletions + insertions) / words in the reference.
/// Accuracy is reported as 1 − WER, floored at zero.
struct WordScore {
    var referenceWords: Int
    var errors: Int

    var wer: Double { referenceWords == 0 ? 0 : Double(errors) / Double(referenceWords) }
    var accuracy: Double { max(0, 1 - wer) }

    static func + (lhs: WordScore, rhs: WordScore) -> WordScore {
        WordScore(referenceWords: lhs.referenceWords + rhs.referenceWords, errors: lhs.errors + rhs.errors)
    }
}

enum WordErrorRate {
    static func score(reference: String, hypothesis: String) -> WordScore {
        let ref = words(reference)
        let hyp = words(hypothesis)
        return WordScore(referenceWords: ref.count, errors: editDistance(ref, hyp))
    }

    /// Lowercased words with punctuation dropped, so "Swift?" and "swift" match.
    /// Number words become digits so "four" and "4" count as the same word.
    static func words(_ text: String) -> [String] {
        let cleaned = text.lowercased()
            .replacingOccurrences(of: "’", with: "'")
            .map { $0.isLetter || $0.isNumber || $0 == "'" ? $0 : " " }
        return String(cleaned)
            .split(separator: " ")
            .map { token in
                let word = String(token).trimmingCharacters(in: CharacterSet(charactersIn: "'"))
                return numberWords[word] ?? word
            }
            .filter { !$0.isEmpty }
    }

    private static let numberWords: [String: String] = [
        "zero": "0", "one": "1", "two": "2", "three": "3", "four": "4", "five": "5",
        "six": "6", "seven": "7", "eight": "8", "nine": "9", "ten": "10",
        "eleven": "11", "twelve": "12", "thirteen": "13", "fourteen": "14", "fifteen": "15",
        "sixteen": "16", "seventeen": "17", "eighteen": "18", "nineteen": "19", "twenty": "20",
    ]

    private static func editDistance(_ a: [String], _ b: [String]) -> Int {
        if a.isEmpty { return b.count }
        if b.isEmpty { return a.count }
        var previous = Array(0...b.count)
        var current = Array(repeating: 0, count: b.count + 1)
        for i in 1...a.count {
            current[0] = i
            for j in 1...b.count {
                let substitution = previous[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1)
                current[j] = min(substitution, previous[j] + 1, current[j - 1] + 1)
            }
            swap(&previous, &current)
        }
        return previous[b.count]
    }
}
