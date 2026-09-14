import Foundation

// How a rule behaves and how it is said out loud. The server words rules the
// same way; tools/check_rule_text_parity.py proves the two agree on every rule.

/// Decides whether a rule lets a row of three tiles through.
enum RuleCheck {
    static func passes(_ rule: RuleNode, _ row: TileRow3) -> Bool {
        let left = rule.a.map { passes($0.node, row) } ?? false
        let right = rule.b.map { passes($0.node, row) } ?? false
        switch rule.op {
        case "not": return !left
        case "and": return left && right
        case "or": return left || right
        case "xor": return left != right
        default: break
        }
        let traits = row.map { rule.attr == "shape" ? Tiles.shape($0) : Tiles.colour($0) }
        guard traits.count == 3 else { return false }
        let value = rule.value ?? ""
        switch rule.op {
        case "pos": return traits[clampIndex(rule.i)] == value
        case "count": return traits.filter { $0 == value }.count == (rule.n ?? 0)
        case "same": return traits[clampIndex(rule.i)] == traits[clampIndex(rule.j, fallback: 2)]
        case "allsame": return Set(traits).count == 1
        case "alldiff": return Set(traits).count == 3
        default: return false
        }
    }

    /// Every row the machine could ever be shown.
    static let everyRow: [TileRow3] = (0..<9).flatMap { a in (0..<9).flatMap { b in (0..<9).map { c in [a, b, c] } } }

    private static func clampIndex(_ oneBased: Int?, fallback: Int = 1) -> Int {
        max(0, min(2, (oneBased ?? fallback) - 1))
    }
}

/// Plain-English wording of a rule.
enum RulePhrasing {
    private static let places = ["", "first", "second", "third"]
    private static let counts = ["no", "one", "two", "three"]

    static func say(_ rule: RuleNode) -> String {
        switch rule.op {
        case "not":
            return rule.a.map { part($0.node, negated: true) } ?? "…"
        case "and":
            return side(rule.a) + " and " + side(rule.b)
        case "or":
            let bothPossible: Bool = {
                guard let x = rule.a?.node, let y = rule.b?.node else { return true }
                return RuleCheck.everyRow.contains { RuleCheck.passes(x, $0) && RuleCheck.passes(y, $0) }
            }()
            return side(rule.a) + ", or " + side(rule.b) + (bothPossible ? ", or both" : "")
        case "xor":
            return side(rule.a) + ", or " + side(rule.b) + ", but not both"
        default:
            return part(rule, negated: false)
        }
    }

    private static func side(_ link: RuleLink?) -> String {
        link.map { part($0.node, negated: false) } ?? "…"
    }

    private static func noun(_ attr: String, _ value: String, many: Bool) -> String {
        let single = attr == "colour" ? "\(value) tile" : value
        return many ? single + "s" : single
    }

    private static func part(_ rule: RuleNode, negated: Bool) -> String {
        let attr = rule.attr ?? "colour"
        let value = rule.value ?? ""
        switch rule.op {
        case "pos":
            let spot = "the \(places[max(1, min(3, rule.i ?? 1))]) tile is\(negated ? " not" : "")"
            return attr == "colour" ? "\(spot) \(value)" : "\(spot) a \(value)"
        case "count":
            let n = max(0, min(3, rule.n ?? 0))
            if !negated {
                if n == 0 { return "there are no \(noun(attr, value, many: true))" }
                if n == 3 { return attr == "colour" ? "all three tiles are \(value)" : "all three tiles are \(value)s" }
                return "there \(n == 1 ? "is" : "are") exactly \(counts[n]) \(noun(attr, value, many: n != 1))"
            }
            if n == 0 { return "there is at least one \(noun(attr, value, many: false))" }
            if n == 3 { return "the three tiles are not all \(noun(attr, value, many: true))" }
            return "there \(n == 1 ? "is" : "are") not exactly \(counts[n]) \(noun(attr, value, many: n != 1))"
        case "same":
            let pair = "the \(places[max(1, min(3, rule.i ?? 1))]) and \(places[max(1, min(3, rule.j ?? 2))]) tiles are"
            return negated ? "\(pair) different \(attr)s" : "\(pair) the same \(attr)"
        case "allsame":
            return negated ? "the three tiles are not all the same \(attr)" : "all three tiles are the same \(attr)"
        case "alldiff":
            return negated ? "at least two tiles share a \(attr)" : "all three \(attr)s are different"
        default:
            return say(rule)
        }
    }
}

extension String {
    /// "the first tile is red" -> "The first tile is red"
    var sentenceCased: String {
        guard let first = first else { return self }
        return first.uppercased() + dropFirst()
    }
}
