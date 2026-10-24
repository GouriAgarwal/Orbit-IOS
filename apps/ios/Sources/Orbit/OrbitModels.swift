import Foundation

struct OrbitEvent: Identifiable, Decodable, Hashable, Sendable {
    struct Club: Decodable, Hashable, Sendable {
        let id: String
        let name: String
        let college: String
    }

    let id: String
    let title: String
    let description: String
    let category: String
    let format: String
    let venue: String?
    let startsAt: Date
    let endsAt: Date
    let registrationDeadline: Date?
    let capacity: Int?
    let minStudentsPerTeam: Int
    let maxStudentsPerTeam: Int
    let registrationMode: String
    let externalUrl: URL?
    let posterUrl: String?
    let club: Club

    var locationLabel: String { format == "online" ? "Online" : (venue ?? "Location to be announced") }
    var dateLabel: String { startsAt.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()) }
    var timeLabel: String { startsAt.formatted(.dateTime.hour().minute()) }
}

struct EventPage: Decodable {
    let data: [OrbitEvent]
    let nextCursor: String?
}

enum CampusScope: String, CaseIterable, Identifiable, Sendable {
    case myCampus = "my_campus"
    case allCampuses = "all_campuses"
    var id: String { rawValue }
    var title: String { self == .myCampus ? "Your Campus" : "All Campuses" }
}
