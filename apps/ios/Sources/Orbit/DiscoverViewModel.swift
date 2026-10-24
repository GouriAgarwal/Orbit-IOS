import Foundation
import Combine

@MainActor
final class DiscoverViewModel: ObservableObject {
    @Published var events: [OrbitEvent] = []
    @Published var scope: CampusScope = .myCampus
    @Published var category: String?
    @Published var search = ""
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
                events = try await DemoEventsRepository().events(scope: scope, category: category, search: search)
            } else {
                events = serverEvents
            }
        }
        catch {
            if events.isEmpty {
                if let demoEvents = try? await DemoEventsRepository().events(scope: scope, category: category, search: search) {
                    events = demoEvents
                    errorMessage = nil
                } else {
                    errorMessage = "We couldn't load events. Check your connection and try again."
                }
            } else {
                errorMessage = "We couldn't refresh events. Showing the latest events already loaded."
            }
        }
    }
}
