import Foundation

struct APIFailure: LocalizedError {
    let status: Int          // 0 = no network / transport error, -1 = cancelled
    let message: String
    var errorDescription: String? { message }
}

// File scope on purpose: nominal types cannot be declared inside a generic function.
private struct ErrorBody: Decodable { let error: String }
private struct Ack: Decodable { let ok: Bool }

/// Thin async client for the Turnstile API (see DESIGN.md). Humans are
/// identified by the X-Player-Id header; nothing else is sent.
final class API {
    static let baseURL = URL(string: "https://turnstile.advancedfield.tech")!

    let playerId: String
    private let session: URLSession
    private let decoder = JSONDecoder()

    init(playerId: String) {
        self.playerId = playerId
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 20
        cfg.requestCachePolicy = .reloadIgnoringLocalCacheData
        session = URLSession(configuration: cfg)
    }

    // MARK: Endpoints

    func today() async throws -> TodayRound { try await get("/v1/round/today") }

    func note(machine: String, text: String) async throws {
        let _: Ack = try await send("POST", "/v1/machine/\(machine)/note", body: ["text": text])
    }

    func experiment(machine: String, seq: Seq, note: String?) async throws -> ExperimentResponse {
        var body: [String: Any] = ["seq": seq]
        if let note, !note.isEmpty { body["note"] = note }
        return try await send("POST", "/v1/machine/\(machine)/experiment", body: body)
    }

    func tests(machine: String) async throws -> TestsResponse {
        try await send("POST", "/v1/machine/\(machine)/tests", body: [:])
    }

    func answer(machine: String, answers: [Bool]) async throws -> AnswerResponse {
        try await send("POST", "/v1/machine/\(machine)/answer", body: ["answers": answers])
    }

    func star(machine: String, rule: Rule) async throws -> StarResponse {
        try await send("POST", "/v1/machine/\(machine)/star", body: ["rule": rule.json])
    }

    func reveal(machine: String) async throws -> Reveal { try await get("/v1/machine/\(machine)/reveal") }

    func results(date: String) async throws -> Results { try await get("/v1/round/\(date)/results") }

    func me() async throws -> Me { try await get("/v1/me") }

    func setNickname(_ nickname: String) async throws -> NicknameResponse {
        try await send("PUT", "/v1/me", body: ["nickname": nickname])
    }

    func leaderboard(period: String) async throws -> Leaderboard { try await get("/v1/leaderboard?period=\(period)") }

    func promos() async throws -> PromosResponse { try await get("/v1/promos") }

    func report(nickname: String) async throws {
        let _: Ack = try await send("POST", "/v1/report", body: ["nickname": nickname])
    }

    /// Privacy deletion: removes the player record, nickname, scores, notes and history server-side.
    func deleteMe() async throws {
        let _: Ack = try await send("DELETE", "/v1/me", body: nil)
    }

    // MARK: Plumbing

    private func get<T: Decodable>(_ path: String) async throws -> T {
        try await send("GET", path, body: nil)
    }

    private func send<T: Decodable>(_ method: String, _ path: String, body: [String: Any]?) async throws -> T {
        guard let url = URL(string: path, relativeTo: API.baseURL) else {
            throw APIFailure(status: 0, message: "Bad URL.")
        }
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue(playerId, forHTTPHeaderField: "X-Player-Id")
        req.setValue("Turnstile-iOS/1.0", forHTTPHeaderField: "User-Agent")
        if let body {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: req)
        } catch {
            if (error as? URLError)?.code == .cancelled || error is CancellationError {
                throw APIFailure(status: -1, message: "Cancelled.")
            }
            throw APIFailure(status: 0, message: "No connection. Check your network and try again.")
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if (200..<300).contains(status) {
            do {
                return try decoder.decode(T.self, from: data)
            } catch {
                throw APIFailure(status: status, message: "Unexpected reply from the server.")
            }
        }
        let message = (try? decoder.decode(ErrorBody.self, from: data))?.error ?? "Server error \(status)."
        throw APIFailure(status: status, message: message)
    }
}
