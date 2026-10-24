import Foundation

struct StudentProject: Decodable, Identifiable, Sendable { let id: String; let title: String; let description: String; let url: String? }
struct StudentCollege: Decodable, Identifiable, Sendable { let id: String; let name: String }
struct StudentProfileData: Decodable, Sendable {
    let displayName: String; let course: String?; let year: Int?; let bio: String; let skills: [String]; let interests: [String]; let projects: [StudentProject]
    let portfolioUrl: String?; let achievements: [String]?; let visibility: String?; let college: StudentCollege?
}
struct CommunityTeam: Decodable, Identifiable, Sendable {
    let id: String; let ownerId: String; let eventId: String?; let name: String; let goal: String; let description: String; let skillsNeeded: [String]; let maxMembers: Int; let owner: String
    let ownerProfile: TeamPersonProfile?; let event: TeamEventOption?; let roles: [TeamRole]; let memberships: [TeamMembershipItem]
    let isOwner: Bool; let myRequestStatus: String?; let status: String
    let _count: MemberCount
    struct MemberCount: Decodable, Sendable { let memberships: Int }
}
struct TeamRole: Decodable, Identifiable, Sendable {
    let id: String; let title: String; let description: String; let requiredSkills: [String]; let openings: Int; let filled: Int; let isOpen: Bool
}
struct TeamEventOption: Decodable, Identifiable, Sendable {
    struct Club: Decodable, Sendable { let name: String }
    let id: String; let title: String; let startsAt: String; let minStudentsPerTeam: Int; let maxStudentsPerTeam: Int; let club: Club?
}
struct TeamEventPage: Decodable, Sendable { let data: [TeamEventOption]; let nextCursor: String? }
struct TeamPersonProfile: Decodable, Sendable {
    let displayName: String; let bio: String?; let skills: [String]?; let course: String?; let year: Int?
    let interests: [String]?; let portfolioUrl: String?; let projects: [StudentProject]?
}
struct TeamMembershipItem: Decodable, Identifiable, Sendable {
    struct Student: Decodable, Sendable { let id: String; let studentProfile: TeamPersonProfile? }
    let id: String; let studentId: String; let student: Student
}
struct JoinRequest: Decodable, Identifiable, Sendable {
    let id: String; let message: String; let status: String; let team: TeamName; let role: TeamRole?; let student: Applicant
    struct TeamName: Decodable, Sendable { let id: String; let name: String }
    struct Applicant: Decodable, Identifiable, Sendable { let id: String; let studentProfile: TeamPersonProfile? }
}
struct InboxData: Decodable, Sendable {
    let incomingTeamRequests: [JoinRequest]; let outgoingTeamRequests: [OutgoingTeamRequest]; let incomingTeamInvitations: [TeamInvitation]
    let connectionRequests: [ConnectionRequestItem]; let notifications: [OrbitNotification]; let clubInvitations: [ClubInvitation]
}
struct TeamInvitation: Decodable, Identifiable, Sendable {
    let id: String; let message: String; let status: String; let team: Team; let role: Role
    struct Team: Decodable, Sendable { let id: String; let name: String; let owner: Owner }
    struct Owner: Decodable, Sendable { let studentProfile: Profile? }
    struct Profile: Decodable, Sendable { let displayName: String }
    struct Role: Decodable, Sendable { let id: String; let title: String }
}
struct ClubInvitation: Decodable, Identifiable, Sendable { let id: String; let role: String; let club: Club; struct Club: Decodable, Sendable { let id: String; let name: String; let college: College }; struct College: Decodable, Sendable { let name: String } }
struct OutgoingTeamRequest: Decodable, Identifiable, Sendable {
    let id: String; let message: String; let status: String; let team: Team
    struct Team: Decodable, Sendable { let id: String; let name: String; let owner: Owner? }
    struct Owner: Decodable, Sendable { let studentProfile: Profile? }
    struct Profile: Decodable, Sendable { let displayName: String }
}
struct ConnectionRequestItem: Decodable, Identifiable, Sendable {
    let id: String; let status: String; let senderId: String; let recipientId: String; let sender: Person; let recipient: Person; let incoming: Bool; let person: Person
    struct Person: Decodable, Sendable { let id: String; let studentProfile: Profile? }
    struct Profile: Decodable, Sendable { let displayName: String }
}
struct OrbitNotification: Decodable, Identifiable, Sendable { let id: String; let type: String; let title: String; let body: String; let readAt: String?; let createdAt: String }

struct CommunityAPI: Sendable {
    let baseURL: URL
    init(baseURL: URL = URL(string: ProcessInfo.processInfo.environment["ORBIT_API_BASE_URL"] ?? "http://localhost:3000/api/v1")!) { self.baseURL = baseURL }

    func profile() async throws -> StudentProfileData { try await authorized("GET", "me/profile") }
    func updateProfile(_ values: [String: Any]) async throws -> StudentProfileData { try await authorized("PATCH", "me/profile", body: values) }
    func addProject(title: String, description: String, url: String) async throws -> StudentProject { try await authorized("POST", "me/projects", body: ["title": title, "description": description, "url": url]) }
    func updateProject(id: String, title: String, description: String, url: String) async throws { let _: EmptyResponse = try await authorized("PATCH", "me/projects/\(id)", body: ["title": title, "description": description, "url": url]) }
    func deleteProject(id: String) async throws { let _: EmptyResponse = try await authorized("DELETE", "me/projects/\(id)") }
    func colleges() async throws -> [StudentCollege] { try await send("GET", "clubs/colleges") }
    func inbox() async throws -> InboxData { try await authorized("GET", "me/inbox") }
    func markNotificationRead(_ id: String) async throws { let _: EmptyResponse = try await authorized("POST", "me/notifications/\(id)/read") }
    func decideConnection(id: String, accept: Bool) async throws { let _: EmptyResponse = try await authorized("POST", "connections/requests/\(id)/\(accept ? "accept" : "decline")") }
    func decideClubInvitation(id: String, accept: Bool) async throws { let _: EmptyResponse = try await authorized("POST", "me/club-invitations/\(id)/\(accept ? "accept" : "decline")") }
    func requestConnection(userId: String) async throws { let _: EmptyResponse = try await authorized("POST", "connections/requests", body: ["recipientId": userId]) }
    func teamEvents() async throws -> [TeamEventOption] {
        let formatter = ISO8601DateFormatter()
        let from = formatter.string(from: Date())
        let page: TeamEventPage = try await send("GET", "events?from=\(from.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? from)")
        return page.data
    }
    func teams(search: String, eventId: String?, matchSkills: Bool) async throws -> [CommunityTeam] {
        var items = [URLQueryItem]()
        if !search.trimmingCharacters(in: .whitespaces).isEmpty { items.append(URLQueryItem(name: "q", value: search)) }
        if let eventId { items.append(URLQueryItem(name: "eventId", value: eventId)) }
        if matchSkills { items.append(URLQueryItem(name: "matchSkills", value: "true")) }
        var components = URLComponents(); components.queryItems = items
        let suffix = components.percentEncodedQuery.map { "?\($0)" } ?? ""
        return try await authorized("GET", "teams\(suffix)")
    }
    func createTeam(eventId: String, name: String, goal: String, description: String, roles: [[String: Any]], maxMembers: Int) async throws {
        let _: EmptyResponse = try await authorized("POST", "teams", body: ["eventId": eventId, "name": name, "goal": goal, "description": description, "roles": roles, "maxMembers": maxMembers])
    }
    func candidates(teamId: String, roleId: String, query: String) async throws -> [JoinRequest.Applicant] {
        var components = URLComponents(); components.queryItems = [URLQueryItem(name: "roleId", value: roleId)]
        if !query.isEmpty { components.queryItems?.append(URLQueryItem(name: "q", value: query)) }
        return try await authorized("GET", "teams/\(teamId)/candidates?\(components.percentEncodedQuery ?? "")")
    }
    func inviteStudent(teamId: String, studentId: String, roleId: String) async throws {
        let _: JoinRequest = try await authorized("POST", "teams/\(teamId)/invitations", body: ["studentId": studentId, "roleId": roleId])
    }
    func lockTeam(teamId: String) async throws { let _: EmptyResponse = try await authorized("POST", "teams/\(teamId)/lock") }
    func requestJoin(teamId: String, roleId: String, message: String) async throws { let _: JoinRequest = try await authorized("POST", "teams/\(teamId)/requests", body: ["roleId": roleId, "message": message]) }
    func requests() async throws -> [JoinRequest] { try await authorized("GET", "me/team-requests") }
    func decide(requestId: String, accept: Bool) async throws { let _: EmptyResponse = try await authorized("POST", "team-requests/\(requestId)/\(accept ? "accept" : "decline")") }
    func block(userId: String) async throws { let _: EmptyResponse = try await authorized("POST", "me/blocks", body: ["userId": userId]) }
    func reportTeam(teamId: String) async throws { let _: EmptyResponse = try await authorized("POST", "reports", body: ["targetType": "team", "targetId": teamId, "reason": "Inappropriate team post"]) }

    private func authorized<T: Decodable>(_ method: String, _ path: String, body: [String: Any]? = nil) async throws -> T {
        guard let stored = TokenVault.load() else { throw CommunityAPIError.message("Sign in to continue.") }
        let tokens: AuthTokens = try await send("POST", "auth/refresh", body: ["refreshToken": stored])
        try TokenVault.save(tokens.refreshToken)
        return try await send(method, path, accessToken: tokens.accessToken, body: body)
    }
    private func send<T: Decodable>(_ method: String, _ path: String, accessToken: String? = nil, body: [String: Any]? = nil) async throws -> T {
        let pieces = path.split(separator: "?", maxSplits: 1).map(String.init)
        guard let route = pieces.first, !route.isEmpty else { throw CommunityAPIError.message("Invalid API route.") }
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)!
        components.path = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        components.path = "/\(components.path)/\(route)"
        if let query = pieces.dropFirst().first { components.queryItems = URLComponents(string: "?\(query)")?.queryItems }
        guard let url = components.url else { throw CommunityAPIError.message("Invalid API URL.") }
        var request = URLRequest(url: url)
        request.httpMethod = method
        if let accessToken { request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization") }
        if let body { request.setValue("application/json", forHTTPHeaderField: "Content-Type"); request.httpBody = try JSONSerialization.data(withJSONObject: body) }
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw CommunityAPIError.message("Unexpected server response.") }
        guard (200..<300).contains(http.statusCode) else {
            let payload = try? JSONDecoder().decode(CommunityErrorBody.self, from: data)
            throw CommunityAPIError.message(payload?.error.message ?? "Request failed (\(http.statusCode)).")
        }
        return try JSONDecoder().decode(T.self, from: data)
    }
}

private struct CommunityErrorBody: Decodable { let error: Detail; struct Detail: Decodable { let message: String } }
private struct EmptyResponse: Decodable { let id: String?; let success: Bool? }
enum CommunityAPIError: LocalizedError { case message(String); var errorDescription: String? { if case .message(let text) = self { text } else { nil } } }
