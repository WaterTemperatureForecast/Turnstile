import Foundation

// What the Turnstile server sends and receives. Swift names are camelCase; the
// server's snake_case keys are converted by `Wire.decoder`.

typealias TileRow3 = [Int]

enum Wire {
    /// Decodes server JSON (snake_case keys).
    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }()

    /// Round-trips values we keep on the device (camelCase keys, no conversion).
    static let store = JSONEncoder()
    static let restore = JSONDecoder()
}

// MARK: - Rules

/// A rule as the server describes it. Only `op` is always present.
struct RuleNode: Codable, Hashable {
    let op: String
    let attr: String?
    let value: String?
    let i: Int?
    let j: Int?
    let n: Int?
    let a: RuleLink?
    let b: RuleLink?

    init(op: String, attr: String? = nil, value: String? = nil, i: Int? = nil, j: Int? = nil, n: Int? = nil,
         a: RuleNode? = nil, b: RuleNode? = nil) {
        self.op = op; self.attr = attr; self.value = value; self.i = i; self.j = j; self.n = n
        self.a = a.map(RuleLink.init)
        self.b = b.map(RuleLink.init)
    }

    /// Plain dictionary for a request body; absent fields are left out.
    var payload: [String: Any] {
        var d: [String: Any] = ["op": op]
        if let attr { d["attr"] = attr }
        if let value { d["value"] = value }
        if let i { d["i"] = i }
        if let j { d["j"] = j }
        if let n { d["n"] = n }
        if let a { d["a"] = a.node.payload }
        if let b { d["b"] = b.node.payload }
        return d
    }
}

/// Boxes a child rule so `RuleNode` can contain itself.
final class RuleLink: Codable, Hashable {
    let node: RuleNode
    init(_ node: RuleNode) { self.node = node }
    required init(from decoder: Decoder) throws { node = try RuleNode(from: decoder) }
    func encode(to encoder: Encoder) throws { try node.encode(to: encoder) }
    static func == (l: RuleLink, r: RuleLink) -> Bool { l.node == r.node }
    func hash(into hasher: inout Hasher) { hasher.combine(node) }
}

// MARK: - Today's machines

struct JudgedRow: Codable, Hashable {
    let seq: TileRow3
    let accepted: Bool
    let note: String?

    init(seq: TileRow3, accepted: Bool, note: String? = nil) {
        self.seq = seq; self.accepted = accepted; self.note = note
    }
}

struct NamedRule: Codable, Hashable {
    let rule: RuleNode?
    let hit: Bool
}

struct PlayState: Codable, Hashable {
    var phase: String                 // experiments | tests | answered
    var queries: [JudgedRow]
    var tests: [TileRow3]?
    var answers: [Bool]?
    var score: Int?
    var star: NamedRule?

    var isFinished: Bool { phase == "answered" }
    var isCalling: Bool { phase == "tests" }
}

struct Builder: Codable, Hashable {
    let name: String
    let kind: String                  // agent | house
    var isAI: Bool { kind == "agent" }
}

struct Machine: Codable, Identifiable, Hashable {
    let id: String
    let slot: String?
    let tier: Int
    let setter: Builder
    let examples: [JudgedRow]
    let exampleCount: Int
    let maxExperiments: Int
    var play: PlayState

    var triesLeft: Int { max(0, maxExperiments - play.queries.count) }
    var title: String { setter.isAI ? "\(setter.name)\u{2019}s machine" : "Bonus machine" }
}

struct Sponsor: Codable, Hashable {
    let name: String
    let tagline: String
    let url: String
}

struct DailyGate: Codable {
    let date: String
    let closesAt: String
    let tier: Int
    let tierText: String
    let vocabulary: [String]
    var machines: [Machine]
    var finished: Bool
    let playerCount: Int
    let sponsor: Sponsor?
}

// MARK: - Playing

struct TryReply: Codable {
    let accepted: Bool
    let queries: [JudgedRow]
    let remaining: Int
}

struct LockReply: Codable {
    let tests: [TileRow3]
    let queries: [JudgedRow]
}

struct CrowdStats: Codable, Hashable {
    let finished: Int
    let solvedPct: Double?
    let meanScore: Double?
    let starPct: Double?
    let meanExperiments: Double?
}

struct RivalName: Codable, Hashable {
    let ruleText: String
    let hit: Bool
}

struct RivalRun: Codable, Hashable, Identifiable {
    let name: String
    let model: String?
    let queries: [JudgedRow]
    let answers: [Bool]
    let score: Int
    let star: RivalName?
    var id: String { name }
}

struct Verdict: Codable {
    let machineId: String
    let tier: Int
    let setter: Builder
    let rule: RuleNode
    let ruleText: String
    let setterNote: String?
    let tests: [TileRow3]
    let truth: [Bool]
    let stats: CrowdStats
    let agents: [RivalRun]
    let you: PlayState?
}

struct CallReply: Codable {
    let score: Int
    let truth: [Bool]
    let answers: [Bool]
    let reveal: Verdict
}

struct Disagreement: Codable, Hashable {
    let seq: TileRow3
    let machine: Bool
    let yours: Bool
}

struct NameReply: Codable {
    let hit: Bool
    let yourRuleText: String
    let ruleText: String
    let counterexample: Disagreement?
}

// MARK: - Days, standings, profile

struct MachineOutcome: Codable, Hashable {
    let phase: String
    let score: Int?
    let experiments: Int
    let star: Bool
}

struct DayMachine: Codable, Identifiable, Hashable {
    let id: String
    let tier: Int
    let setter: Builder
    let stats: CrowdStats
    let ruleText: String?
    let you: MachineOutcome?
}

struct DayResult: Codable, Hashable {
    let score: Int
    let stars: Int
    let experiments: Int
    let rank: Int
}

struct StandingRow: Codable, Identifiable, Hashable {
    let name: String
    let kind: String
    let score: Double
    let stars: Int?
    let experiments: Int?
    let rounds: Int?
    let rank: Int
    var id: String { kind + "|" + name }
    var isAI: Bool { kind == "agent" }
}

struct DaySummary: Codable {
    let date: String
    let final: Bool
    let closed: Bool
    let tier: Int
    let playerCount: Int
    let you: DayResult?
    let machines: [DayMachine]
    let leaderboard: [StandingRow]
}

struct SetterDay: Codable, Hashable, Identifiable {
    let machineId: String
    let date: String
    let tier: Int
    let finished: Int
    let solvedPct: Double?
    let rivalScore: Int?
    let points: Int
    var id: String { machineId }
}

struct SetterLine: Codable, Hashable, Identifiable {
    let name: String
    let machines: Int
    let points: Int
    let recent: [SetterDay]
    var id: String { name }
}

struct Standings: Codable {
    let period: String
    let players: [StandingRow]?
    let setters: [SetterLine]?
}

struct PastDay: Codable, Identifiable, Hashable {
    let date: String
    let score: Int
    let stars: Int
    let rank: Int
    let playerCount: Int
    let final: Bool
    var id: String { date }
}

struct PlayerProfile: Codable {
    let name: String
    let nickname: String?
    let lifetimeScore: Double?
    let roundsPlayed: Int
    let streak: Int
    let stars: Int
    let rounds: [PastDay]
}

struct NameChange: Codable {
    let name: String
    let nickname: String?
}

struct CrossLink: Codable, Identifiable, Hashable {
    let id: Int
    let title: String
    let subtitle: String?
    let url: String
}

struct CrossLinks: Codable {
    let promos: [CrossLink]
}

struct Done: Codable {
    let ok: Bool
}

// MARK: - Tiles and the game calendar

enum Tiles {
    static let shapes = ["circle", "square", "triangle"]
    static let colours = ["red", "blue", "yellow"]
    static func shape(_ t: Int) -> String { shapes[max(0, min(2, t / 3))] }
    static func colour(_ t: Int) -> String { colours[max(0, min(2, t % 3))] }
    static func make(shape: Int, colour: Int) -> Int { shape * 3 + colour }
    static func spoken(_ t: Int) -> String { "\(colour(t)) \(shape(t))" }
    static func spoken(_ row: TileRow3) -> String { row.map(spoken).joined(separator: ", ") }
}

/// A new day starts at 08:00 UTC on the server; everything here follows that.
enum GameCalendar {
    private static let ymd: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    static var todayKey: String { ymd.string(from: Date(timeIntervalSinceNow: -8 * 3600)) }

    static func key(daysAgo n: Int) -> String {
        ymd.string(from: Date(timeIntervalSinceNow: -8 * 3600 - Double(n) * 86_400))
    }

    static func pretty(_ key: String) -> String {
        guard let d = ymd.date(from: key) else { return key }
        let f = DateFormatter()
        f.timeZone = TimeZone(identifier: "UTC")
        f.setLocalizedDateFormatFromTemplate("EEEE d MMMM")
        return f.string(from: d)
    }

    static func short(_ key: String) -> String {
        guard let d = ymd.date(from: key) else { return key }
        let f = DateFormatter()
        f.timeZone = TimeZone(identifier: "UTC")
        f.setLocalizedDateFormatFromTemplate("EEE d")
        return f.string(from: d)
    }

    static func instant(_ iso: String) -> Date? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        if let d = f.date(from: iso) { return d }
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.date(from: iso)
    }
}
