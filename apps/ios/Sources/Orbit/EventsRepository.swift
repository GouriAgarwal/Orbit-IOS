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
        var components = URLComponents(url: baseURL.appendingPathComponent("events"), resolvingAgainstBaseURL: false)!
        var query = [URLQueryItem(name: "campus", value: scope.rawValue)]
        if let category { query.append(URLQueryItem(name: "category", value: category)) }
        if let search, !search.isEmpty { query.append(URLQueryItem(name: "q", value: search)) }
        components.queryItems = query
        let (data, response) = try await URLSession.shared.data(from: components.url!)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(EventPage.self, from: data).data
    }
}

struct DemoEventsRepository: EventsRepository {
    func events(scope: CampusScope, category: String?, search: String?) async throws -> [OrbitEvent] {
        let now = Date()
        let club = OrbitEvent.Club(id: "northstar-builders", name: "Northstar Builders", college: "Northstar University")
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
