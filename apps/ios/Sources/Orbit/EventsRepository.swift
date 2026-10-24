import Foundation

protocol EventsRepository: Sendable {
    func events(scope: CampusScope, category: String?, search: String?) async throws -> [OrbitEvent]
}

struct APIEventsRepository: EventsRepository {
    private let baseURL: URL

    init(baseURL: URL? = nil) {
        self.baseURL = baseURL ?? URL(string: ProcessInfo.processInfo.environment["ORBIT_API_BASE_URL"] ?? "http://localhost:3000/api/v1")!
    }

    func events(scope: CampusScope, category: String?, search: String?) async throws -> [OrbitEvent] {
        let components = makeComponents(path: TokenVault.load() == nil ? "events" : "events/recommended", scope: scope, category: category, search: search)
        if let stored = TokenVault.load(), let tokens = try? await AuthClient(baseURL: baseURL).refresh(refreshToken: stored) {
            try? TokenVault.save(tokens.refreshToken)
            if let personalized = try? await fetch(components, accessToken: tokens.accessToken) { return personalized }
        }
        let standard = makeComponents(path: "events", scope: scope, category: category, search: search)
        return try await fetch(standard, accessToken: nil)
    }

    private func makeComponents(path: String, scope: CampusScope, category: String?, search: String?) -> URLComponents {
        var url = baseURL.appendingPathComponent("events")
        if path == "events/recommended" { url.appendPathComponent("recommended") }
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        var query = [URLQueryItem(name: "campus", value: scope.rawValue)]
        if let category { query.append(URLQueryItem(name: "category", value: category)) }
        if let search, !search.isEmpty { query.append(URLQueryItem(name: "q", value: search)) }
        components.queryItems = query
        return components
    }

    private func fetch(_ components: URLComponents, accessToken: String?) async throws -> [OrbitEvent] {
        guard let url = components.url else { throw URLError(.badURL) }
        var request = URLRequest(url: url)
        if let accessToken { request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization") }
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(EventPage.self, from: data).data
    }
}

struct DemoEventsRepository: EventsRepository {
    func events(scope: CampusScope, category: String?, search: String?) async throws -> [OrbitEvent] {
        let now = Date()
        let club = OrbitEvent.Club(id: "northstar-builders", name: "Northstar Builders", college: "Northstar University", organizerName: nil)
        let source: [OrbitEvent] = [
            OrbitEvent(id: "build-night", title: "Orbit Build Night", description: "An evening to prototype campus ideas with a team. Bring a rough idea or join a crew on arrival.", category: "Hackathon", format: "in_person", venue: "Innovation Lab", startsAt: now.addingTimeInterval(72 * 3600), endsAt: now.addingTimeInterval(76 * 3600), registrationDeadline: now.addingTimeInterval(71 * 3600), capacity: 80, minStudentsPerTeam: 1, maxStudentsPerTeam: 1, registrationMode: "native", externalUrl: nil, posterUrl: nil, club: club),
            OrbitEvent(id: "design-studio", title: "Design Systems Studio", description: "Build accessible interfaces, explore reusable components, and share your design process.", category: "Workshop", format: "hybrid", venue: "Design Hall 2", startsAt: now.addingTimeInterval(120 * 3600), endsAt: now.addingTimeInterval(124 * 3600), registrationDeadline: now.addingTimeInterval(116 * 3600), capacity: 40, minStudentsPerTeam: 1, maxStudentsPerTeam: 1, registrationMode: "native", externalUrl: nil, posterUrl: nil, club: club),
            OrbitEvent(id: "oss-sprint", title: "Open Source Sprint", description: "Pair with maintainers, find a good first issue, and make your first contribution.", category: "Technology", format: "online", venue: nil, startsAt: now.addingTimeInterval(168 * 3600), endsAt: now.addingTimeInterval(172 * 3600), registrationDeadline: nil, capacity: nil, minStudentsPerTeam: 1, maxStudentsPerTeam: 1, registrationMode: "native", externalUrl: nil, posterUrl: nil, club: club),
        ]
        return source.filter { event in
            (category == nil || event.category == category) && (search == nil || search!.isEmpty || event.title.localizedCaseInsensitiveContains(search!) || event.description.localizedCaseInsensitiveContains(search!))
        }
    }
}
