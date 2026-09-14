import Foundation
import SwiftUI

/// Everything the screens show, and every move the player makes.
@MainActor
final class GameStore: ObservableObject {
    @Published private(set) var gate: DailyGate?
    @Published private(set) var verdicts: [String: Verdict] = [:]      // by machine id
    @Published private(set) var profile: PlayerProfile?
    @Published private(set) var links: [CrossLink] = []
    @Published private(set) var loading = false
    @Published var notice: String?

    /// Players this device has chosen not to see on the standings.
    @Published private(set) var hiddenPlayers: Set<String>

    private var client: GateClient
    private let defaults = UserDefaults.standard
    private var inFlight: Task<Void, Never>?

    init() {
        client = GateClient(device: DeviceIdentity.current())
        // Not `defaults`: self cannot be read until every stored property is set.
        hiddenPlayers = Set(UserDefaults.standard.stringArray(forKey: "hidden-players") ?? [])
        let key = GameCalendar.todayKey
        if let saved = defaults.data(forKey: "gate"),
           let g = try? Wire.restore.decode(DailyGate.self, from: saved), g.date == key {
            gate = g
        }
        if let saved = defaults.data(forKey: "verdicts-\(key)"),
           let v = try? Wire.restore.decode([String: Verdict].self, from: saved) {
            verdicts = v
        }
    }

    // MARK: Reading

    func machine(_ id: String) -> Machine? { gate?.machines.first { $0.id == id } }

    var dayTotal: Int { gate?.machines.compactMap { $0.play.score }.reduce(0, +) ?? 0 }
    var dayStars: Int { gate?.machines.filter { $0.play.star?.hit == true }.count ?? 0 }

    var brag: String {
        guard let gate, gate.finished else { return "Turnstile AI: work out the secret rule. turnstile.advancedfield.tech" }
        let stars = String(repeating: "\u{2605}", count: dayStars)
        let lines = gate.machines.map { m in "\(m.setter.name): \(m.play.score ?? 0)/4 in \(m.play.queries.count) tries" }
        return (["Turnstile AI \u{00b7} \(GameCalendar.short(gate.date)) \u{00b7} \(dayTotal)/8 \(stars)"] + lines)
            .joined(separator: "\n") + "\nturnstile.advancedfield.tech"
    }

    func loadDay() async {
        if let running = inFlight { await running.value; return }
        let task = Task { await self.pullDay() }
        inFlight = task
        await task.value
        inFlight = nil
    }

    private func pullDay() async {
        loading = true
        defer { loading = false }
        do {
            let fresh = try await client.gate()
            if gate?.date != fresh.date { verdicts = [:] }
            gate = fresh
            save(fresh, as: "gate")
            for m in fresh.machines where m.play.isFinished && verdicts[m.id] == nil {
                if let v = try? await client.verdict(m.id) { verdicts[m.id] = v }
            }
            save(verdicts, as: "verdicts-\(fresh.date)")
            notice = nil
        } catch {
            show(error)
        }
    }

    func loadProfile() async {
        if let p = try? await client.profile() { profile = p }
    }

    func loadLinks() async {
        if let l = try? await client.links() { links = l.promos }
    }

    func standings(_ period: String) async throws -> Standings { try await client.standings(period) }

    func day(_ key: String) async throws -> DaySummary { try await client.day(key) }

    func loadVerdict(_ id: String) async {
        if let v = try? await client.verdict(id) {
            verdicts[id] = v
            if let date = gate?.date { save(verdicts, as: "verdicts-\(date)") }
        }
    }

    // MARK: Playing a machine

    /// Feed the machine one row. Returns whether it accepted it.
    func tryRow(_ id: String, row: TileRow3, hunch: String) async throws -> Bool {
        let reply = try await client.tryRow(id, row: row, hunch: hunch)
        edit(id) { $0.queries = reply.queries }
        Feedback.tick()
        return reply.accepted
    }

    func lock(_ id: String) async throws {
        let reply = try await client.lock(id)
        edit(id) { state in
            state.phase = "tests"
            state.queries = reply.queries
            state.tests = reply.tests
        }
    }

    func call(_ id: String, answers: [Bool]) async throws -> CallReply {
        let reply = try await client.call(id, answers: answers)
        verdicts[id] = reply.reveal
        edit(id) { state in
            if let you = reply.reveal.you { state = you } else {
                state.phase = "answered"
                state.answers = answers
                state.score = reply.score
            }
        }
        if let date = gate?.date { save(verdicts, as: "verdicts-\(date)") }
        if reply.score == 4 { Feedback.good() } else { Feedback.tick() }
        await loadProfile()
        return reply
    }

    func name(_ id: String, rule: RuleNode) async throws -> NameReply {
        let reply = try await client.name(id, rule: rule)
        edit(id) { $0.star = NamedRule(rule: rule, hit: reply.hit) }
        if reply.hit { Feedback.good() } else { Feedback.bad() }
        return reply
    }

    private func edit(_ id: String, _ change: (inout PlayState) -> Void) {
        guard var g = gate, let index = g.machines.firstIndex(where: { $0.id == id }) else { return }
        change(&g.machines[index].play)
        g.finished = g.machines.allSatisfy { $0.play.isFinished }
        gate = g
        save(g, as: "gate")
    }

    // MARK: The player

    func rename(_ nickname: String) async -> String {
        do {
            let change = try await client.rename(nickname.trimmingCharacters(in: .whitespacesAndNewlines))
            await loadProfile()
            return change.nickname == nil ? "You are \(change.name) again." : "Saved."
        } catch {
            return (error as? GateError)?.errorDescription ?? "Could not save that name."
        }
    }

    func flag(_ nickname: String) async -> Bool {
        do { try await client.flag(nickname: nickname); return true } catch { show(error); return false }
    }

    func hide(_ name: String) {
        hiddenPlayers.insert(name)
        defaults.set(Array(hiddenPlayers), forKey: "hidden-players")
    }

    func unhideAll() {
        hiddenPlayers = []
        defaults.removeObject(forKey: "hidden-players")
    }

    /// Delete this player on the server, then start over as someone new.
    func forget() async -> Bool {
        do { try await client.forget() } catch { show(error); return false }
        for key in ["gate", "hidden-players"] { defaults.removeObject(forKey: key) }
        if let date = gate?.date { defaults.removeObject(forKey: "verdicts-\(date)") }
        client = GateClient(device: DeviceIdentity.renew())
        gate = nil; verdicts = [:]; profile = nil; hiddenPlayers = []
        await loadDay()
        return true
    }

    // MARK: Helpers

    private func save<T: Encodable>(_ value: T, as key: String) {
        if let data = try? Wire.store.encode(value) { defaults.set(data, forKey: key) }
    }

    private func show(_ error: Error) {
        if let e = error as? GateError, e == .cancelled { return }
        notice = (error as? GateError)?.errorDescription ?? "Something went wrong. Pull down to try again."
    }
}
