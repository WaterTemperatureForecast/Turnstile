import Foundation

// Wire models. Property names mirror the API's snake_case keys on purpose so
// no key-decoding strategy is needed and the JSON in DESIGN.md reads 1:1.

typealias Seq = [Int]

struct Example: Codable, Hashable {
    let seq: Seq
    let accepted: Bool
}

struct Query: Codable, Hashable {
    let seq: Seq
    let accepted: Bool
    let note: String?
}

/// Rule AST as loosely-typed JSON (the picker builds it, the server evaluates it).
struct Rule: Codable, Hashable {
    let op: String
    let attr: String?
    let value: String?
    let i: Int?
    let j: Int?
    let n: Int?
    let a: RuleBox?
    let b: RuleBox?

    init(op: String, attr: String? = nil, value: String? = nil, i: Int? = nil, j: Int? = nil, n: Int? = nil, a: Rule? = nil, b: Rule? = nil) {
        self.op = op; self.attr = attr; self.value = value; self.i = i; self.j = j; self.n = n
        self.a = a.map(RuleBox.init); self.b = b.map(RuleBox.init)
    }

    /// Dictionary form for the request body (nil fields omitted).
    var json: [String: Any] {
        var d: [String: Any] = ["op": op]
        if let attr { d["attr"] = attr }
        if let value { d["value"] = value }
        if let i { d["i"] = i }
        if let j { d["j"] = j }
        if let n { d["n"] = n }
        if let a { d["a"] = a.rule.json }
        if let b { d["b"] = b.rule.json }
        return d
    }
}

final class RuleBox: Codable, Hashable {
    let rule: Rule
    init(_ rule: Rule) { self.rule = rule }
    required init(from decoder: Decoder) throws { rule = try Rule(from: decoder) }
    func encode(to encoder: Encoder) throws { try rule.encode(to: encoder) }
    static func == (l: RuleBox, r: RuleBox) -> Bool { l.rule == r.rule }
    func hash(into hasher: inout Hasher) { hasher.combine(rule) }
}

struct Star: Codable, Hashable {
    let rule: Rule?
    let hit: Bool
}

struct Play: Codable, Hashable {
    let phase: String            // experiments | tests | answered
    let queries: [Query]
    let tests: [Seq]?
    let answers: [Bool]?
    let score: Int?
    let star: Star?
}

struct Setter: Codable, Hashable {
    let name: String
    let kind: String             // agent | house
}

struct Machine: Codable, Identifiable, Hashable {
    let id: String
    let slot: String?
    let tier: Int
    let setter: Setter
    let examples: [Example]
    let example_count: Int
    let max_experiments: Int
    var play: Play
}

struct SponsorLine: Codable, Hashable {
    let name: String
    let tagline: String
    let url: String
}

struct TodayRound: Codable {
    let date: String
    let closes_at: String
    let tier: Int
    let tier_text: String
    let vocabulary: [String]
    var machines: [Machine]
    var finished: Bool
    let player_count: Int
    let sponsor: SponsorLine?
}

struct ExperimentResponse: Codable {
    let accepted: Bool
    let queries: [Query]
    let remaining: Int
}

struct TestsResponse: Codable {
    let tests: [Seq]
    let queries: [Query]
}

struct MachineStats: Codable, Hashable {
    let finished: Int
    let solved_pct: Double?
    let mean_score: Double?
    let star_pct: Double?
    let mean_experiments: Double?
}

struct AgentStar: Codable, Hashable {
    let rule_text: String
    let hit: Bool
}

struct AgentTranscript: Codable, Hashable, Identifiable {
    let name: String
    let model: String?
    let queries: [Query]
    let answers: [Bool]
    let score: Int
    let star: AgentStar?
    var id: String { name }
}

struct Reveal: Codable {
    let machine_id: String
    let slot: String?
    let tier: Int
    let setter: Setter
    let rule: Rule
    let rule_text: String
    let setter_note: String?
    let tests: [Seq]
    let truth: [Bool]
    let stats: MachineStats
    let agents: [AgentTranscript]
    let you: Play?
}

struct AnswerResponse: Codable {
    let score: Int
    let truth: [Bool]
    let answers: [Bool]
    let reveal: Reveal
}

struct Counterexample: Codable, Hashable {
    let seq: Seq
    let machine: Bool
    let yours: Bool
}

struct StarResponse: Codable {
    let hit: Bool
    let your_rule_text: String
    let rule_text: String
    let counterexample: Counterexample?
}

struct YouSummary: Codable, Hashable {
    let phase: String
    let score: Int?
    let experiments: Int
    let star: Bool
}

struct MachineResult: Codable, Identifiable, Hashable {
    let id: String
    let slot: String?
    let tier: Int
    let setter: Setter
    let stats: MachineStats
    let rule_text: String?
    let you: YouSummary?
}

struct YouScore: Codable, Hashable {
    let score: Int
    let stars: Int
    let experiments: Int
    let rank: Int
}

struct BoardEntry: Codable, Identifiable, Hashable {
    let name: String
    let kind: String
    let score: Double
    let stars: Int?
    let experiments: Int?
    let rounds: Int?
    let rank: Int
    var id: String { kind + ":" + name }
    var isAgent: Bool { kind == "agent" }
}

struct Results: Codable {
    let date: String
    let final: Bool
    let closed: Bool
    let closes_at: String?
    let tier: Int
    let player_count: Int
    let you: YouScore?
    let machines: [MachineResult]
    let leaderboard: [BoardEntry]
    let sponsor: SponsorLine?
}

struct Leaderboard: Codable {
    let period: String
    let date: String?
    let final: Bool?
    let player_count: Int?
    let players: [BoardEntry]?
    let setters: [SetterEntry]?
}

struct SetterMachine: Codable, Hashable, Identifiable {
    let machine_id: String
    let date: String
    let slot: String?
    let tier: Int
    let finished: Int
    let solved_pct: Double?
    let mean_score: Double?
    let rival_score: Int?
    let points: Int
    var id: String { machine_id }
}

struct SetterEntry: Codable, Hashable, Identifiable {
    let name: String
    let model: String?
    let machines: Int
    let points: Int
    let recent: [SetterMachine]
    var id: String { name }
}

struct RoundHistory: Codable, Identifiable, Hashable {
    let date: String
    let score: Int
    let stars: Int
    let experiments: Int
    let rank: Int
    let player_count: Int
    let final: Bool
    var id: String { date }
}

struct Me: Codable {
    let id: String
    let kind: String
    let name: String
    let nickname: String?
    let lifetime_score: Double?
    let rounds_played: Int
    let streak: Int
    let stars: Int
    let rounds: [RoundHistory]
}

struct NicknameResponse: Codable {
    let id: String
    let name: String
    let nickname: String?
}

struct Promo: Codable, Identifiable, Hashable {
    let id: Int
    let title: String
    let subtitle: String?
    let url: String
}

struct PromosResponse: Codable {
    let promos: [Promo]
}

// MARK: - Tiles

enum Tile {
    static let shapes = ["circle", "square", "triangle"]
    static let colours = ["red", "blue", "yellow"]
    static func shape(_ t: Int) -> String { shapes[max(0, min(2, t / 3))] }
    static func colour(_ t: Int) -> String { colours[max(0, min(2, t % 3))] }
    static func id(shape: Int, colour: Int) -> Int { shape * 3 + colour }
    static func label(_ t: Int) -> String { "\(colour(t)) \(shape(t))" }
    static func label(_ seq: Seq) -> String { seq.map(label).joined(separator: ", ") }
}

// MARK: - Dates

enum UTCDay {
    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    /// Round date currently open: the UTC date of (now - 8h), matching the server's rollover.
    static var today: String { formatter.string(from: Date(timeIntervalSinceNow: -8 * 3600)) }
    static var yesterday: String { formatter.string(from: Date(timeIntervalSinceNow: -8 * 3600 - 86_400)) }

    static func date(from ymd: String) -> Date? { formatter.date(from: ymd) }

    /// "Sep 13" style label for a YYYY-MM-DD string.
    static func label(_ ymd: String) -> String {
        guard let d = date(from: ymd) else { return ymd }
        let f = DateFormatter()
        f.timeZone = TimeZone(identifier: "UTC")
        f.setLocalizedDateFormatFromTemplate("MMM d")
        return f.string(from: d)
    }

    static func iso(_ s: String) -> Date? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        if let d = f.date(from: s) { return d }
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.date(from: s)
    }
}
