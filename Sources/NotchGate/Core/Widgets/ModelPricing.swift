import Foundation

/// The Claude model line a reply came from, for the Insights card's split.
enum ModelFamily: String, CaseIterable, Sendable {
    case fable, opus, sonnet, haiku, other

    var title: String {
        switch self {
        case .fable: return "Fable"
        case .opus: return "Opus"
        case .sonnet: return "Sonnet"
        case .haiku: return "Haiku"
        case .other: return "Other"
        }
    }

    init(model: String) {
        let id = model.lowercased()
        if id.contains("fable") || id.contains("mythos") {
            self = .fable
        } else if id.contains("opus") {
            self = .opus
        } else if id.contains("sonnet") {
            self = .sonnet
        } else if id.contains("haiku") {
            self = .haiku
        } else {
            self = .other
        }
    }
}

/// Tokens one reply used, as Claude Code records them in its transcript.
struct TokenUsage: Equatable, Sendable {
    var input = 0
    var output = 0
    var cacheRead = 0
    /// Cache writes kept 5 minutes (billed 1.25× input) and 1 hour (2× input).
    var cacheWrite5m = 0
    var cacheWrite1h = 0
    var webSearches = 0

    var cacheWrite: Int { cacheWrite5m + cacheWrite1h }
    /// Everything the model read: fresh input plus cached prompt.
    var prompt: Int { input + cacheRead + cacheWrite }
    var total: Int { prompt + output }

    static func + (lhs: TokenUsage, rhs: TokenUsage) -> TokenUsage {
        TokenUsage(
            input: lhs.input + rhs.input,
            output: lhs.output + rhs.output,
            cacheRead: lhs.cacheRead + rhs.cacheRead,
            cacheWrite5m: lhs.cacheWrite5m + rhs.cacheWrite5m,
            cacheWrite1h: lhs.cacheWrite1h + rhs.cacheWrite1h,
            webSearches: lhs.webSearches + rhs.webSearches
        )
    }

    static func += (lhs: inout TokenUsage, rhs: TokenUsage) { lhs = lhs + rhs }
}

/// Anthropic API list prices, to show what Claude Code's tokens would cost.
/// On a Pro or Max plan this is an equivalent, not a bill.
///
/// Prices are US dollars per million tokens (first-party API, standard tier).
enum ModelPricing {
    struct Rates: Equatable, Sendable {
        let input: Double
        let output: Double
        /// Cache reads are 0.1× input on most models; newer ones list their own.
        let cacheRead: Double

        init(input: Double, output: Double, cacheRead: Double? = nil) {
            self.input = input
            self.output = output
            self.cacheRead = cacheRead ?? input * 0.1
        }

        var cacheWrite5m: Double { input * 1.25 }
        var cacheWrite1h: Double { input * 2 }
    }

    /// Most specific id first: `claude-opus-4-5` must match before `claude-opus-4`.
    static let table: [(prefix: String, rates: Rates)] = [
        ("claude-fable-5-1", Rates(input: 10, output: 50, cacheRead: 0.25)),
        ("claude-mythos-5-1", Rates(input: 10, output: 50, cacheRead: 0.25)),
        ("claude-fable-5", Rates(input: 10, output: 50)),
        ("claude-mythos-5", Rates(input: 10, output: 50)),
        ("claude-opus-5-5", Rates(input: 4, output: 20, cacheRead: 0.20)),
        ("claude-opus-5", Rates(input: 5, output: 25)),
        ("claude-opus-4-8", Rates(input: 5, output: 25)),
        ("claude-opus-4-7", Rates(input: 5, output: 25)),
        ("claude-opus-4-6", Rates(input: 5, output: 25)),
        ("claude-opus-4-5", Rates(input: 5, output: 25)),
        ("claude-opus-4", Rates(input: 15, output: 75)),
        ("claude-sonnet-5-5", Rates(input: 2, output: 10, cacheRead: 0.20)),
        ("claude-sonnet-5", Rates(input: 2, output: 10)),
        ("claude-sonnet-4", Rates(input: 3, output: 15)),
        ("claude-3-7-sonnet", Rates(input: 3, output: 15)),
        ("claude-haiku-5-5", Rates(input: 0.10, output: 0.50)),
        ("claude-haiku-4-5", Rates(input: 1, output: 5)),
        ("claude-3-5-haiku", Rates(input: 0.80, output: 4)),
    ]

    /// Claude Haiku 5.5 charges more once a prompt passes 100K tokens.
    static let haikuLongPromptThreshold = 100_000
    static let haikuLongPrompt = Rates(input: 0.50, output: 2.50)
    /// Fast mode runs the same model at double the price (Opus 5 and 5.5).
    static let fastModeMultiplier = 2.0
    static let webSearchPrice = 0.01

    static func rates(for model: String) -> Rates? {
        let id = model.lowercased()
        return table.first { id.hasPrefix($0.prefix) }?.rates
    }

    /// What one reply would cost at API prices; `nil` for a model with no list price.
    static func cost(of usage: TokenUsage, model: String, isFast: Bool = false) -> Double? {
        guard var rates = rates(for: model) else { return nil }
        let id = model.lowercased()
        if id.hasPrefix("claude-haiku-5-5"), usage.prompt > haikuLongPromptThreshold {
            rates = haikuLongPrompt
        }
        let perMillion = Double(usage.input) * rates.input
            + Double(usage.output) * rates.output
            + Double(usage.cacheRead) * rates.cacheRead
            + Double(usage.cacheWrite5m) * rates.cacheWrite5m
            + Double(usage.cacheWrite1h) * rates.cacheWrite1h
        let fast = isFast && (id.hasPrefix("claude-opus-5")) ? fastModeMultiplier : 1
        return perMillion / 1_000_000 * fast + Double(usage.webSearches) * webSearchPrice
    }
}
