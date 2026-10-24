import SwiftUI

struct EventDetailView: View {
    let event: OrbitEvent
    let isSaved: Bool
    let onSave: () -> Void
    @State private var registrationStatus: String?
    @State private var isRegistering = false
    @State private var alertMessage = ""
    @State private var showingAlert = false
    @State private var showingTeamFinder = false

    private var posterImageURL: URL? {
        guard let raw = event.posterUrl else { return nil }
        if let absolute = URL(string: raw), absolute.scheme != nil { return absolute }
        let apiBase = URL(string: ProcessInfo.processInfo.environment["ORBIT_API_BASE_URL"] ?? "http://localhost:3000/api/v1")!
        return URL(string: raw, relativeTo: apiBase)?.absoluteURL
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                ZStack(alignment: .bottomLeading) {
                    if let posterImageURL {
                        AsyncImage(url: posterImageURL) { phase in
                            if let image = phase.image {
                                image.resizable().scaledToFill()
                            } else {
                                OrbitStyle.mint
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 230)
                        .clipped()
                        LinearGradient(colors: [.clear, .black.opacity(0.58)], startPoint: .center, endPoint: .bottom)
                    } else {
                        OrbitStyle.mint
                        Circle().fill(OrbitStyle.yellow).frame(width: 180).offset(x: 240, y: -110)
                    }
                    VStack(alignment: .leading, spacing: 9) {
                        Text(event.category.uppercased()).font(.system(size: 10, weight: .black, design: .rounded)).tracking(1.5)
                        Text(event.title).font(.system(size: 33, weight: .bold, design: .rounded)).tracking(-1).lineLimit(3)
                    }.foregroundColor(posterImageURL == nil ? OrbitStyle.ink : .white).padding(22)
                }.frame(height: 230).clipShape(RoundedRectangle(cornerRadius: 24))
                HStack(spacing: 10) {
                    Label(event.dateLabel, systemImage: "calendar").font(.system(.subheadline, design: .rounded, weight: .semibold))
                    Spacer()
                    Label(event.timeLabel, systemImage: "clock").font(.system(.subheadline, design: .rounded, weight: .semibold))
                }.foregroundStyle(OrbitStyle.ink)
                VStack(alignment: .leading, spacing: 8) {
                    Text("Hosted by").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    Text(event.club.name).font(.system(.title3, design: .rounded, weight: .bold)).foregroundStyle(OrbitStyle.ink)
                    Text(event.club.college).font(.subheadline).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity, alignment: .leading).padding(17).background(OrbitStyle.card, in: RoundedRectangle(cornerRadius: 18))
                VStack(alignment: .leading, spacing: 9) {
                    Text("The plan").font(.system(.title3, design: .rounded, weight: .bold)).foregroundStyle(OrbitStyle.ink)
                    Text(event.description).font(.system(.body, design: .rounded)).foregroundStyle(OrbitStyle.ink.opacity(0.8)).lineSpacing(4)
                }
                Label(event.locationLabel, systemImage: event.format == "online" ? "video" : "mappin.and.ellipse").font(.system(.subheadline, design: .rounded, weight: .semibold)).foregroundStyle(OrbitStyle.ink)
                if let capacity = event.capacity { Label("Up to \(capacity) people", systemImage: "person.2").font(.system(.subheadline, design: .rounded)).foregroundStyle(.secondary) }
                if event.minStudentsPerTeam != 1 || event.maxStudentsPerTeam != 1 {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Team registration · \(event.minStudentsPerTeam)–\(event.maxStudentsPerTeam) students", systemImage: "person.3")
                            .font(.system(.subheadline, design: .rounded, weight: .semibold))
                        Text("Create or join a team in Find Teams. The leader registers everyone once the team meets the required size.").font(.caption).foregroundStyle(.secondary)
                        Button("Find or create a team") { showingTeamFinder = true }.buttonStyle(.borderedProminent).tint(OrbitStyle.ink)
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(16).background(OrbitStyle.card, in: RoundedRectangle(cornerRadius: 18))
                } else { HStack(spacing: 12) {
                    Button(action: onSave) { Label(isSaved ? "Saved" : "Save", systemImage: isSaved ? "bookmark.fill" : "bookmark").font(.system(.subheadline, design: .rounded, weight: .bold)).frame(maxWidth: .infinity).padding(15).background(OrbitStyle.mint, in: Capsule()).foregroundStyle(OrbitStyle.ink) }
                    Button {
                        Task {
                            isRegistering = true
                            defer { isRegistering = false }
                            do {
                                let registration = try await StudentActivityAPI().register(eventId: event.id)
                                registrationStatus = registration.status
                                alertMessage = registration.status == "waitlisted"
                                    ? "You're on the waitlist. Check My Events for your status."
                                    : "You're registered for \(event.title). Find it in My Events."
                            } catch { alertMessage = error.localizedDescription }
                            showingAlert = true
                        }
                    } label: {
                        Group {
                            if isRegistering { ProgressView().tint(.white) }
                            else { Text(registrationStatus.map { $0 == "waitlisted" ? "Waitlisted" : "Registered" } ?? (UUID(uuidString: event.id) == nil ? "Demo event" : "Register")) }
                        }.font(.system(.subheadline, design: .rounded, weight: .bold)).frame(maxWidth: .infinity).padding(15).background(OrbitStyle.ink, in: Capsule()).foregroundStyle(OrbitStyle.onInk)
                    }.disabled(isRegistering || registrationStatus != nil || UUID(uuidString: event.id) == nil)
                }.padding(.top, 4) }
                if UUID(uuidString: event.id) == nil { Text("This preview event is not connected to registration.").font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .center) }
            }.padding(20)
        }.background(OrbitStyle.paper.ignoresSafeArea()).navigationTitle("Event details").navigationBarTitleDisplayMode(.inline)
            .alert("Event registration", isPresented: $showingAlert) { Button("OK", role: .cancel) {} } message: { Text(alertMessage) }
            .sheet(isPresented: $showingTeamFinder) { FindTeamView() }
    }
}
