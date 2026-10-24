import Foundation

struct StudentRegistration: Decodable, Identifiable, Sendable {
    let id: String
    let status: String
    let event: OrbitEvent
}
struct StudentRegistrationReceipt: Decodable, Sendable { let id: String; let status: String }
struct SavedEventItem: Decodable, Identifiable, Sendable { let id: String; let event: OrbitEvent }

struct StudentActivityAPI: Sendable {
    let baseURL: URL
    init(baseURL: URL = URL(string: ProcessInfo.processInfo.environment["ORBIT_API_BASE_URL"] ?? "http://localhost:3000/api/v1")!) { self.baseURL = baseURL }

    func myEvents() async throws -> [StudentRegistration] { try await authorized("GET", "events/my-registrations") }
    func savedEvents() async throws -> [SavedEventItem] { try await authorized("GET", "events/my-saved") }
    func save(eventId: String) async throws { let _: SuccessResponse = try await authorized("POST", "events/\(eventId)/save") }
    func unsave(eventId: String) async throws { let _: SuccessResponse = try await authorized("DELETE", "events/\(eventId)/save") }
    func register(eventId: String) async throws -> StudentRegistrationReceipt { try await authorized("POST", "events/\(eventId)/registrations") }
    func cancel(eventId: String) async throws { let _: SuccessResponse = try await authorized("DELETE", "events/\(eventId)/registrations/me") }

    private func authorized<T: Decodable>(_ method: String, _ path: String) async throws -> T {
        guard let refreshToken = TokenVault.load() else { throw StudentActivityError.message("Sign in to continue.") }
        let tokens: AuthTokens = try await send("POST", "auth/refresh", body: ["refreshToken": refreshToken])
        try TokenVault.save(tokens.refreshToken)
        return try await send(method, path, accessToken: tokens.accessToken)
    }
    private func send<T: Decodable>(_ method: String, _ path: String, accessToken: String? = nil, body: [String: String]? = nil) async throws -> T {
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.httpMethod = method
        if let accessToken { request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization") }
        if let body { request.setValue("application/json", forHTTPHeaderField: "Content-Type"); request.httpBody = try JSONSerialization.data(withJSONObject: body) }
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw StudentActivityError.message("Unexpected server response.") }
        guard (200..<300).contains(response.statusCode) else {
            let serverError = try? JSONDecoder().decode(ActivityErrorBody.self, from: data)
            throw StudentActivityError.message(serverError?.error.message ?? "Request failed (\(response.statusCode)).")
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(T.self, from: data)
    }
}

private struct SuccessResponse: Decodable { let success: Bool?; let id: String?; let studentId: String?; let eventId: String? }
private struct ActivityErrorBody: Decodable { let error: Detail; struct Detail: Decodable { let message: String } }
enum StudentActivityError: LocalizedError { case message(String); var errorDescription: String? { if case .message(let text) = self { text } else { nil } } }
