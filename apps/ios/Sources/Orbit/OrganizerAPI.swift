import Foundation

struct OrganizerCollege: Decodable, Identifiable, Sendable { let id: String; let name: String; let city: String? }
struct OrganizerClub: Decodable, Identifiable, Sendable {
    let id: String; let name: String; let description: String; let verificationStatus: String
    let college: OrganizerCollege
    let currentRole: String?
}
struct ClubVerificationRequest: Decodable, Identifiable, Sendable {
    struct Club: Decodable, Sendable { let id: String; let name: String; let college: OrganizerCollege }
    struct Applicant: Decodable, Sendable { let emailNormalized: String; let studentProfile: Profile? }
    struct Profile: Decodable, Sendable { let displayName: String }
    let id: String; let clubId: String; let proofUrl: String; let proofNotes: String; let status: String
    let submittedAt: String; let eligibleAt: String; let reviewNote: String?; let club: Club; let applicant: Applicant?
    static func isEligible(_ value: String) -> Bool {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: value) { return date <= Date() }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value).map { $0 <= Date() } ?? false
    }
}
struct OrganizerClubMember: Decodable, Identifiable, Sendable {
    let id: String; let userId: String; let role: String; let status: String; let user: User
    struct User: Decodable, Sendable { let id: String; let studentProfile: Profile? }
    struct Profile: Decodable, Sendable { let displayName: String; let course: String?; let year: Int? }
}
struct OrganizerEvent: Decodable, Identifiable, Sendable {
    let id: String; let title: String; let description: String; let category: String; let format: String
    let venue: String?; let startsAt: String; let endsAt: String; let registrationDeadline: String?
    let capacity: Int?; let minStudentsPerTeam: Int; let maxStudentsPerTeam: Int; let registrationMode: String; let externalUrl: String?; let posterUrl: String?; let status: String; let club: OrganizerClub?
}
private struct PosterUploadResponse: Decodable { let posterUrl: String }
struct OrganizerAttendee: Decodable, Identifiable, Sendable {
    let id: String; let status: String; let registeredAt: String; let student: Student
    struct Student: Decodable, Sendable { let id: String; let studentProfile: Profile? }
    struct Profile: Decodable, Sendable { let displayName: String; let course: String?; let year: Int? }
}

struct OrganizerAPI: Sendable {
    let baseURL: URL
    init(baseURL: URL = URL(string: ProcessInfo.processInfo.environment["ORBIT_API_BASE_URL"] ?? "http://localhost:3000/api/v1")!) { self.baseURL = baseURL }

    func colleges() async throws -> [OrganizerCollege] { try await request("clubs/colleges") }
    func clubs() async throws -> [OrganizerClub] { try await authorized("GET", "clubs/me") }
    func verificationRequests() async throws -> [ClubVerificationRequest] { try await authorized("GET", "clubs/verification/me") }
    func verificationQueue() async throws -> [ClubVerificationRequest] { try await authorized("GET", "clubs/verification/queue") }
    func decideVerification(id: String, decision: String, note: String) async throws { let _: StatusResponse = try await authorized("PATCH", "clubs/verification/\(id)", body: ["decision": decision, "note": note]) }
    func members(clubId: String) async throws -> [OrganizerClubMember] { try await authorized("GET", "clubs/\(clubId)/members") }
    func invite(clubId: String, email: String, role: String) async throws { let _: OrganizerClubMember = try await authorized("POST", "clubs/\(clubId)/invitations", body: ["email": email, "role": role]) }
    func updateMember(clubId: String, userId: String, role: String) async throws { let _: StatusResponse = try await authorized("PATCH", "clubs/\(clubId)/members/\(userId)", body: ["role": role]) }
    func removeMember(clubId: String, userId: String) async throws { let _: StatusResponse = try await authorized("DELETE", "clubs/\(clubId)/members/\(userId)") }
    func events() async throws -> [OrganizerEvent] { try await authorized("GET", "events/mine") }
    func deleteEvent(id: String) async throws { let _: StatusResponse = try await authorized("DELETE", "events/\(id)") }
    func uploadEventPoster(clubId: String, jpegData: Data) async throws -> String {
        let response: PosterUploadResponse = try await authorized("POST", "events/posters", body: ["clubId": clubId, "imageBase64": jpegData.base64EncodedString()])
        return response.posterUrl
    }
    func createClub(collegeId: String, name: String, description: String, proofUrl: String, proofNotes: String) async throws -> OrganizerClub {
        try await authorized("POST", "clubs", body: ["collegeId": collegeId, "name": name, "description": description, "proofUrl": proofUrl, "proofNotes": proofNotes])
    }
    func resubmitClubVerification(clubId: String, proofUrl: String, proofNotes: String) async throws {
        let _: ClubVerificationRequest = try await authorized("POST", "clubs/\(clubId)/verification", body: ["proofUrl": proofUrl, "proofNotes": proofNotes])
    }
    func createEvent(clubId: String, title: String, description: String, category: String, format: String, venue: String, startsAt: Date, endsAt: Date, deadline: Date?, capacity: Int?, minStudentsPerTeam: Int, maxStudentsPerTeam: Int, registrationMode: String, externalUrl: String?, posterUrl: String?) async throws -> OrganizerEvent {
        let encoder = ISO8601DateFormatter()
        return try await authorized("POST", "events", body: [
            "clubId": clubId, "title": title, "description": description, "category": category,
            "format": format, "venue": venue, "startsAt": encoder.string(from: startsAt), "endsAt": encoder.string(from: endsAt),
            "registrationDeadline": deadline.map { encoder.string(from: $0) } as Any? ?? NSNull(),
            "capacity": capacity as Any? ?? NSNull(), "minStudentsPerTeam": minStudentsPerTeam, "maxStudentsPerTeam": maxStudentsPerTeam, "registrationMode": registrationMode, "externalUrl": externalUrl as Any? ?? NSNull(), "posterUrl": posterUrl as Any? ?? NSNull(),
        ])
    }
    func updateEvent(_ event: OrganizerEvent, title: String, description: String, category: String, format: String, venue: String, startsAt: Date, endsAt: Date, deadline: Date?, capacity: Int?, minStudentsPerTeam: Int, maxStudentsPerTeam: Int, registrationMode: String, externalUrl: String?) async throws -> OrganizerEvent {
        let encoder = ISO8601DateFormatter()
        return try await authorized("PATCH", "events/\(event.id)", body: ["title": title, "description": description, "category": category, "format": format, "venue": venue, "startsAt": encoder.string(from: startsAt), "endsAt": encoder.string(from: endsAt), "registrationDeadline": deadline.map { encoder.string(from: $0) } as Any? ?? NSNull(), "capacity": capacity as Any? ?? NSNull(), "minStudentsPerTeam": minStudentsPerTeam, "maxStudentsPerTeam": maxStudentsPerTeam, "registrationMode": registrationMode, "externalUrl": externalUrl as Any? ?? NSNull()])
    }
    func submit(eventId: String) async throws -> OrganizerEvent { try await authorized("POST", "events/\(eventId)/submit") }
    func publish(eventId: String) async throws -> OrganizerEvent { try await authorized("POST", "events/\(eventId)/publish") }
    func attendees(eventId: String) async throws -> [OrganizerAttendee] { try await authorized("GET", "events/\(eventId)/registrations") }
    func markAttendance(eventId: String, registrationId: String, status: String) async throws { let _: StatusResponse = try await authorized("PATCH", "events/\(eventId)/registrations/\(registrationId)", body: ["status": status]) }
    func reviews(eventId: String) async throws -> EventReviewPage { try await authorized("GET", "events/\(eventId)/reviews") }
    func replyToReview(eventId: String, reviewId: String, reply: String) async throws { let _: StatusResponse = try await authorized("PATCH", "events/\(eventId)/reviews/\(reviewId)/reply", body: ["reply": reply]) }

    private func authorized<T: Decodable>(_ method: String, _ path: String, body: [String: Any]? = nil) async throws -> T {
        guard let stored = TokenVault.load() else { throw OrganizerAPIError.message("Your session expired. Sign in again.") }
        let tokens: AuthTokens = try await send("POST", "auth/refresh", body: ["refreshToken": stored])
        try TokenVault.save(tokens.refreshToken)
        return try await send(method, path, token: tokens.accessToken, body: body)
    }
    private func request<T: Decodable>(_ path: String) async throws -> T { try await send("GET", path) }
    private func send<T: Decodable>(_ method: String, _ path: String, token: String? = nil, body: [String: Any]? = nil) async throws -> T {
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.httpMethod = method
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        if let body { request.setValue("application/json", forHTTPHeaderField: "Content-Type"); request.httpBody = try JSONSerialization.data(withJSONObject: body) }
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw OrganizerAPIError.message("Unexpected server response.") }
        guard (200..<300).contains(http.statusCode) else {
            let payload = try? JSONDecoder().decode(APIErrorBody.self, from: data)
            throw OrganizerAPIError.message(payload?.error.message ?? "Request failed (\(http.statusCode)).")
        }
        return try JSONDecoder().decode(T.self, from: data)
    }
}

private struct APIErrorBody: Decodable { let error: Detail; struct Detail: Decodable { let message: String } }
private struct StatusResponse: Decodable { let success: Bool; let status: String? }
enum OrganizerAPIError: LocalizedError { case message(String); var errorDescription: String? { if case .message(let text) = self { text } else { nil } } }
