import Foundation
import SwiftUI

/// All app state. One instance, injected as an EnvironmentObject.
@MainActor
final class AppModel: ObservableObject {
    @Published var round: TodayRound?
    @Published var reveals: [String: Reveal] = [:]      // by machine id
    @Published var me: Me?
    @Published var board: Leaderboard?
    @Published var boardPeriod = "today"
    @Published var yesterday: Results?
    @Published var promos: [Promo] = []
    @Published var yesterdayError: String?
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var nicknameDraft = ""
    @Published var nicknameStatus: String?

    private(set) var api: API
    @Published private(set) var playerId: String
    private let defaults = UserDefaults.standard

    init() {
        let id: String
        if let saved = Keychain.string(for: "player_id") {
            id = saved
        } else {
            id = UUID().uuidString.lowercased()
            Keychain.set(id, for: "player_id")
        }
        playerId = id
        api = API(playerId: id)
        nicknameDraft = defaults.string(forKey: "nickname") ?? ""

        // Restore today's cached round and reveals so the app opens instantly.
        let today = UTCDay.today
        if let data = defaults.data(forKey: "round"),
           let r = try? JSONDecoder().decode(TodayRound.self, from: data), r.date == today {
            round = r
            if let rd = defaults.data(forKey: "reveals-\(today)"),
               let rv = try? JSONDecoder().decode([String: Reveal].self, from: rd) {
                reveals = rv
            }
        }
    }

    // MARK: Derived

    var hasFinishedToday: Bool { round?.finished ?? false }

    func machine(_ id: String) -> Machine? { round?.machines.first { $0.id == id } }

    var shareText: String {
        guard let round else { return "Turnstile – a daily rule-induction game. https://turnstile.advancedfield.tech" }
        var parts = ["Turnstile \(UTCDay.label(round.date))"]
        let scores = round.machines.compactMap { $0.play.score }
        if scores.count == round.machines.count {
            let stars = round.machines.filter { $0.play.star?.hit == true }.count
            parts.append("\(scores.reduce(0, +))/\(round.machines.count * 4)" + String(repeating: "★", count: stars))
        }
        for m in round.machines {
            if let s = m.play.score {
                parts.append("\(m.setter.name)'s machine \(s)/4 in \(m.play.queries.count) exp")
            }
        }
        return parts.joined(separator: " · ") + "\nhttps://turnstile.advancedfield.tech"
    }

    // MARK: Loading

    private var refreshTask: Task<Void, Never>?

    func refresh() async {
        if let running = refreshTask {
            await running.value
            return
        }
        let task = Task { await self.performRefresh() }
        refreshTask = task
        await task.value
        refreshTask = nil
    }

    private func performRefresh() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let r = try await api.today()
            if round?.date != r.date { reveals = [:] }
            round = r
            cache(r, key: "round")
            // Reveals for machines already answered (e.g. another device, or a cache miss).
            for m in r.machines where m.play.phase == "answered" && reveals[m.id] == nil {
                if let rv = try? await api.reveal(machine: m.id) { reveals[m.id] = rv }
            }
            cache(reveals, key: "reveals-\(r.date)")
            errorMessage = nil
        } catch {
            handle(error, offline: round != nil ? "Offline. Showing what was loaded; pull down to retry." : nil)
        }
    }

    func loadMe() async {
        if let m = try? await api.me() {
            me = m
            if let nick = m.nickname, nicknameDraft.isEmpty { nicknameDraft = nick }
        }
    }

    func loadPromos() async {
        if let response = try? await api.promos() { promos = response.promos }
    }

    func loadBoard() async {
        do {
            board = try await api.leaderboard(period: boardPeriod)
            errorMessage = nil
        } catch {
            handle(error)
        }
    }

    func loadYesterday() async {
        let date = UTCDay.yesterday
        if yesterday?.date == date, yesterday?.final == true { return }
        do {
            yesterday = try await api.results(date: date)
            yesterdayError = nil
        } catch {
            yesterdayError = describe(error)
        }
    }

    // MARK: Playing

    private func updatePlay(_ id: String, _ transform: (inout Play) -> Void) {
        guard var r = round, let i = r.machines.firstIndex(where: { $0.id == id }) else { return }
        var p = r.machines[i].play
        transform(&p)
        r.machines[i].play = p
        r.finished = r.machines.allSatisfy { $0.play.phase == "answered" }
        round = r
        cache(r, key: "round")
    }

    /// Run one experiment. Returns whether the machine accepted it.
    func experiment(_ id: String, seq: Seq, note: String) async throws -> Bool {
        let res = try await api.experiment(machine: id, seq: seq, note: note)
        updatePlay(id) { $0 = Play(phase: "experiments", queries: res.queries, tests: nil, answers: nil, score: nil, star: nil) }
        Haptics.tap()
        return res.accepted
    }

    func showTests(_ id: String) async throws {
        let res = try await api.tests(machine: id)
        updatePlay(id) { $0 = Play(phase: "tests", queries: res.queries, tests: res.tests, answers: nil, score: nil, star: nil) }
    }

    func answer(_ id: String, answers: [Bool]) async throws -> AnswerResponse {
        let res = try await api.answer(machine: id, answers: answers)
        reveals[id] = res.reveal
        if let you = res.reveal.you {
            updatePlay(id) { $0 = you }
        } else {
            updatePlay(id) { $0 = Play(phase: "answered", queries: $0.queries, tests: $0.tests, answers: answers, score: res.score, star: nil) }
        }
        if let date = round?.date { cache(reveals, key: "reveals-\(date)") }
        if res.score == 4 { Haptics.success() } else { Haptics.tap() }
        await loadMe()
        return res
    }

    func star(_ id: String, rule: Rule) async throws -> StarResponse {
        let res = try await api.star(machine: id, rule: rule)
        updatePlay(id) { $0 = Play(phase: $0.phase, queries: $0.queries, tests: $0.tests, answers: $0.answers, score: $0.score, star: Star(rule: rule, hit: res.hit)) }
        if res.hit { Haptics.success() } else { Haptics.error() }
        return res
    }

    func loadReveal(_ id: String) async {
        if let rv = try? await api.reveal(machine: id) {
            reveals[id] = rv
            if let date = round?.date { cache(reveals, key: "reveals-\(date)") }
        }
    }

    // MARK: You

    func saveNickname() async {
        let nick = nicknameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            let r = try await api.setNickname(nick)
            defaults.set(nick, forKey: "nickname")
            nicknameStatus = nick.isEmpty ? "Back to \(r.name)." : "Saved."
            await loadMe()
        } catch {
            nicknameStatus = describe(error)
        }
    }

    @discardableResult
    func report(nickname: String) async -> Bool {
        do {
            try await api.report(nickname: nickname)
            return true
        } catch {
            handle(error)
            return false
        }
    }

    /// Delete everything server-side, forget the local caches, and start over with a fresh id.
    func deleteMyData() async -> Bool {
        do {
            try await api.deleteMe()
        } catch {
            handle(error)
            return false
        }
        for key in ["round", "nickname"] { defaults.removeObject(forKey: key) }
        if let date = round?.date { defaults.removeObject(forKey: "reveals-\(date)") }
        let newId = UUID().uuidString.lowercased()
        Keychain.set(newId, for: "player_id")
        playerId = newId
        api = API(playerId: newId)
        round = nil; reveals = [:]; me = nil; board = nil; yesterday = nil
        nicknameDraft = ""; nicknameStatus = "Deleted. You are now a brand-new player."
        await refresh()
        return true
    }

    // MARK: Helpers

    private func cache<T: Encodable>(_ value: T, key: String) {
        if let data = try? JSONEncoder().encode(value) { defaults.set(data, forKey: key) }
    }

    private func handle(_ error: Error, offline: String? = nil) {
        if let f = error as? APIFailure, f.status == -1 { return }
        if let offline, (error as? APIFailure)?.status == 0 {
            errorMessage = offline
            return
        }
        errorMessage = describe(error)
    }

    func describe(_ error: Error) -> String {
        if let f = error as? APIFailure { return f.message }
        return "No connection. Check your network and try again."
    }
}
