import Foundation
import Combine

@MainActor
final class DiscoverViewModel: ObservableObject {
    @Published var events: [OrbitEvent] = []
    @Published var scope: CampusScope = .myCampus
    @Published var category: String?
    @Published var search = ""
    @Published var interests: [String] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    private let repository: any EventsRepository

    init(repository: any EventsRepository = APIEventsRepository()) { self.repository = repository }

    func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let serverEvents = try await repository.events(scope: scope, category: category, search: search)
            if serverEvents.isEmpty {
                events = personalize(try await DemoEventsRepository().events(scope: scope, category: category, search: search))
            } else {
                events = personalize(serverEvents)
            }
        }
        catch {
            if events.isEmpty {
                if let demoEvents = try? await DemoEventsRepository().events(scope: scope, category: category, search: search) {
                    events = personalize(demoEvents)
                    errorMessage = nil
                } else {
                    errorMessage = "We couldn't load events. Check your connection and try again."
                }
            } else {
                errorMessage = "We couldn't refresh events. Showing the latest events already loaded."
            }
        }
    }

    private func personalize(_ events: [OrbitEvent]) -> [OrbitEvent] {
        guard !interests.isEmpty else { return events }
        return events.enumerated().sorted { lhs, rhs in
            let left = relevance(lhs.element)
            let right = relevance(rhs.element)
            return left == right ? lhs.offset < rhs.offset : left > right
        }.map(\.element)
    }

    private func relevance(_ event: OrbitEvent) -> Int {
        let keywords: [String: [String]] = [
            "technology": ["technology", "tech", "coding", "software", "programming", "developer", "open source"],
            "hackathons": ["hackathon", "build sprint", "prototype"],
            "design & ui/ux": ["design", "ui", "ux", "figma", "visual", "product"],
            "entrepreneurship": ["entrepreneur", "startup", "business", "pitch", "founder"],
            "ai & data science": ["artificial intelligence", "machine learning", "data science", "analytics", "robotics"],
            "arts & culture": ["art", "culture", "creative", "exhibition", "theatre"],
            "music": ["music", "concert", "singing", "band", "sound"],
            "sports": ["sport", "fitness", "athletic", "tournament", "football", "cricket"],
            "gaming": ["gaming", "game", "esports", "game jam"],
            "career & networking": ["career", "networking", "interview", "internship", "industry"],
            "wellness": ["wellness", "mental health", "mindfulness", "health", "yoga"],
            "volunteering": ["volunteer", "community service", "social impact", "outreach"],
            "photography": ["photography", "photo", "camera", "visual storytelling"],
            "finance": ["finance", "financial", "investing", "economics", "fintech"],
            "environment": ["environment", "sustainability", "climate", "conservation", "green"],
            "writing & literature": ["writing", "literature", "poetry", "reading", "storytelling"],
            "workshops & learning": ["workshop", "learning", "masterclass", "training"]
        ]
        let category = event.category.lowercased()
        let title = event.title.lowercased()
        let description = event.description.lowercased()
        return interests.reduce(0) { total, interest in
            (keywords[interest.lowercased()] ?? [interest.lowercased()]).reduce(total) { score, word in
                score + (category.contains(word) ? 5 : 0) + (title.contains(word) ? 3 : 0) + (description.contains(word) ? 1 : 0)
            }
        }
    }
}
