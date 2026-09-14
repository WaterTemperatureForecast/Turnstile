import Foundation

/// Why a request to the Turnstile server did not produce what we asked for.
enum GateError: LocalizedError, Equatable {
    case offline
    case cancelled
    case refused(status: Int, reason: String)
    case garbled

    var errorDescription: String? {
        switch self {
        case .offline: return "You seem to be offline. Pull down to try again."
        case .cancelled: return nil
        case .refused(_, let reason): return reason
        case .garbled: return "The server sent something unexpected. Try again in a moment."
        }
    }

    var status: Int? {
        if case .refused(let status, _) = self { return status }
        return nil
    }
}

/// Talks to turnstile.advancedfield.tech. A plain value: it holds nothing but the
/// device identifier and a session, so it can be recreated freely.
struct GateClient {
    static let host = URL(string: "https://turnstile.advancedfield.tech")!

    let device: String
    private let session: URLSession

    init(device: String) {
        self.device = device
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 25
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        session = URLSession(configuration: config)
    }

    // MARK: The day

    func gate() async throws -> DailyGate { try await fetch("/v1/gate") }

    func day(_ key: String) async throws -> DaySummary { try await fetch("/v1/day/\(key)") }

    // MARK: A machine

    func tryRow(_ machine: String, row: TileRow3, hunch: String) async throws -> TryReply {
        var body: [String: Any] = ["seq": row]
        let trimmed = hunch.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { body["note"] = trimmed }
        return try await fetch("/v1/gate/\(machine)/try", method: "POST", body: body)
    }

    func lock(_ machine: String) async throws -> LockReply {
        try await fetch("/v1/gate/\(machine)/lock", method: "POST", body: [:])
    }

    func call(_ machine: String, answers: [Bool]) async throws -> CallReply {
        try await fetch("/v1/gate/\(machine)/call", method: "POST", body: ["answers": answers])
    }

    func name(_ machine: String, rule: RuleNode) async throws -> NameReply {
        try await fetch("/v1/gate/\(machine)/name", method: "POST", body: ["rule": rule.payload])
    }

    func verdict(_ machine: String) async throws -> Verdict { try await fetch("/v1/gate/\(machine)/verdict") }

    // MARK: Around the game

    func standings(_ period: String) async throws -> Standings { try await fetch("/v1/standings?period=\(period)") }

    func profile() async throws -> PlayerProfile { try await fetch("/v1/profile") }

    func rename(_ nickname: String) async throws -> NameChange {
        try await fetch("/v1/profile", method: "PUT", body: ["nickname": nickname])
    }

    func forget() async throws {
        let _: Done = try await fetch("/v1/profile", method: "DELETE")
    }

    func flag(nickname: String) async throws {
        let _: Done = try await fetch("/v1/flag", method: "POST", body: ["nickname": nickname])
    }

    func links() async throws -> CrossLinks { try await fetch("/v1/links") }

    // MARK: Transport

    private struct Refusal: Decodable { let error: String }

    private func fetch<T: Decodable>(_ path: String, method: String = "GET", body: [String: Any]? = nil) async throws -> T {
        guard let url = URL(string: path, relativeTo: Self.host) else { throw GateError.garbled }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(device, forHTTPHeaderField: "X-Turnstile-Device")
        request.setValue("TurnstileAI-iOS/1.0", forHTTPHeaderField: "User-Agent")
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            if error is CancellationError || (error as? URLError)?.code == .cancelled { throw GateError.cancelled }
            throw GateError.offline
        }

        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            let reason = (try? Wire.decoder.decode(Refusal.self, from: data))?.error ?? "The server could not do that (\(status))."
            throw GateError.refused(status: status, reason: reason)
        }
        do {
            return try Wire.decoder.decode(T.self, from: data)
        } catch {
            throw GateError.garbled
        }
    }
}
