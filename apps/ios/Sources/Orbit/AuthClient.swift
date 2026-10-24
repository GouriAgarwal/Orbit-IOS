import Foundation
import Security

struct AuthTokens: Decodable, Sendable {
    let accessToken: String
    let refreshToken: String
    let tokenType: String
    let expiresIn: Int
}

struct CurrentUser: Decodable, Sendable {
    struct Profile: Decodable, Sendable {
        let displayName: String
        let bio: String
        let interests: [String]?
    }
    let id: String
    let profile: Profile?
}

enum AuthError: LocalizedError {
    case badResponse
    case server(String)
    var errorDescription: String? {
        switch self {
        case .badResponse: "The server returned an unexpected response. Is the API running?"
        case .server(let message): message
        }
    }
}

struct AuthClient: Sendable {
    let baseURL: URL
    init(baseURL: URL = URL(string: ProcessInfo.processInfo.environment["ORBIT_API_BASE_URL"] ?? "http://localhost:3000/api/v1")!) { self.baseURL = baseURL }

    func register(email: String, password: String, displayName: String) async throws -> AuthTokens {
        try await post("auth/register", body: ["email": email, "password": password, "displayName": displayName])
    }
    func login(email: String, password: String) async throws -> AuthTokens {
        try await post("auth/login", body: ["email": email, "password": password])
    }
    func refresh(refreshToken: String) async throws -> AuthTokens {
        try await post("auth/refresh", body: ["refreshToken": refreshToken])
    }
    func logout(refreshToken: String) async throws {
        let _: Success = try await post("auth/logout", body: ["refreshToken": refreshToken])
    }
    func currentUser(accessToken: String) async throws -> CurrentUser {
        var request = URLRequest(url: baseURL.appendingPathComponent("auth/me"))
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(data, response)
        return try JSONDecoder().decode(CurrentUser.self, from: data)
    }
    func saveInterests(_ interests: [String], accessToken: String) async throws {
        var request = URLRequest(url: baseURL.appendingPathComponent("me/profile"))
        request.httpMethod = "PATCH"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["interests": interests])
        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(data, response)
    }
    private func post<T: Decodable>( _ path: String, body: [String: String]) async throws -> T {
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(data, response)
        return try JSONDecoder().decode(T.self, from: data)
    }
    private func validate(_ data: Data, _ response: URLResponse) throws {
        guard let response = response as? HTTPURLResponse else { throw AuthError.badResponse }
        guard (200..<300).contains(response.statusCode) else {
            let payload = try? JSONDecoder().decode(ServerError.self, from: data)
            throw AuthError.server(payload?.error.message ?? "Request failed (\(response.statusCode)).")
        }
    }
}

private struct ServerError: Decodable { let error: Detail; struct Detail: Decodable { let message: String } }
private struct Success: Decodable { let success: Bool }

enum TokenVault {
    private static let service = "com.orbit.campus"
    private static let account = "refresh-token"
    static func save(_ token: String) throws {
        let data = Data(token.utf8)
        SecItemDelete([kSecClass: kSecClassGenericPassword, kSecAttrService: service, kSecAttrAccount: account] as CFDictionary)
        let status = SecItemAdd([kSecClass: kSecClassGenericPassword, kSecAttrService: service, kSecAttrAccount: account, kSecValueData: data, kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly] as CFDictionary, nil)
        guard status == errSecSuccess else { throw AuthError.server("Could not securely save this session.") }
    }
    static func delete() {
        SecItemDelete([kSecClass: kSecClassGenericPassword, kSecAttrService: service, kSecAttrAccount: account] as CFDictionary)
    }
    static func load() -> String? {
        var result: CFTypeRef?
        let status = SecItemCopyMatching([kSecClass: kSecClassGenericPassword, kSecAttrService: service, kSecAttrAccount: account, kSecReturnData: true, kSecMatchLimit: kSecMatchLimitOne] as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
