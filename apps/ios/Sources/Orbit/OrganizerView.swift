import SwiftUI
import Combine
import PhotosUI
import UIKit

@MainActor
final class OrganizerViewModel: ObservableObject {
    @Published var colleges: [OrganizerCollege] = []
    @Published var clubs: [OrganizerClub] = []
    @Published var verificationRequests: [ClubVerificationRequest] = []
    @Published var verificationQueue: [ClubVerificationRequest] = []
    @Published var events: [OrganizerEvent] = []
    @Published var message: String?
    @Published var busy = false
    private let api = OrganizerAPI()

    func load() async {
        busy = true; defer { busy = false }
        do {
            // OrganizerAPI rotates refresh tokens for authenticated requests. Keep
            // these requests sequential so they never race on the same token.
            colleges = try await api.colleges()
            clubs = try await api.clubs()
            verificationRequests = try await api.verificationRequests()
            verificationQueue = (try? await api.verificationQueue()) ?? []
            events = try await api.events()
            message = nil
        } catch { message = error.localizedDescription }
    }
    func createClub(collegeId: String, name: String, description: String, proofUrl: String, proofNotes: String) async {
        busy = true; defer { busy = false }
        do { _ = try await api.createClub(collegeId: collegeId, name: name, description: description, proofUrl: proofUrl, proofNotes: proofNotes); await load(); message = "Club submitted for verification. Organizer tools unlock after verifier approval and the 48-hour holding period." }
        catch { message = error.localizedDescription }
    }
    func resubmitVerification(_ claim: ClubVerificationRequest, proofUrl: String, proofNotes: String) async {
        busy = true; defer { busy = false }
        do { try await api.resubmitClubVerification(clubId: claim.clubId, proofUrl: proofUrl, proofNotes: proofNotes); await load(); message = "Updated proof submitted. The 48-hour holding period has restarted." }
        catch { message = error.localizedDescription }
    }
    func decideVerification(_ claim: ClubVerificationRequest, decision: String, note: String = "") async {
        busy = true; defer { busy = false }
        do { try await api.decideVerification(id: claim.id, decision: decision, note: note); await load(); message = decision == "approve" ? "Club verified; organizer access granted." : "Verification request rejected. The applicant can resubmit proof." }
        catch { message = error.localizedDescription }
    }
    func createEvent(clubId: String, title: String, description: String, category: String, format: String, venue: String, startsAt: Date, endsAt: Date, deadline: Date?, capacity: Int?, minStudentsPerTeam: Int, maxStudentsPerTeam: Int, registrationMode: String, externalUrl: String?, posterData: Data?) async {
        busy = true; defer { busy = false }
        do {
            let posterUrl: String?
            if let posterData { posterUrl = try await api.uploadEventPoster(clubId: clubId, jpegData: posterData) }
            else { posterUrl = nil }
            _ = try await api.createEvent(clubId: clubId, title: title, description: description, category: category, format: format, venue: venue, startsAt: startsAt, endsAt: endsAt, deadline: deadline, capacity: capacity, minStudentsPerTeam: minStudentsPerTeam, maxStudentsPerTeam: maxStudentsPerTeam, registrationMode: registrationMode, externalUrl: externalUrl, posterUrl: posterUrl)
            await load(); message = "Event created and published."
        }
        catch { message = error.localizedDescription }
    }
    func submit(_ event: OrganizerEvent) async {
        busy = true; defer { busy = false }
        do { _ = try await api.submit(eventId: event.id); await load(); message = "Event submitted for review." }
        catch { message = error.localizedDescription }
    }
    func publish(_ event: OrganizerEvent) async {
        busy = true; defer { busy = false }
        do { _ = try await api.publish(eventId: event.id); await load(); message = "Event published." }
        catch { message = error.localizedDescription }
    }
    func delete(_ event: OrganizerEvent) async {
        busy = true; defer { busy = false }
        do { try await api.deleteEvent(id: event.id); await load(); showTransientMessage("Event deleted.") }
        catch { message = error.localizedDescription }
    }
    private func showTransientMessage(_ text: String) {
        message = text
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            guard self?.message == text else { return }
            self?.message = nil
        }
    }
    func update(_ event: OrganizerEvent, title: String, description: String, category: String, format: String, venue: String, startsAt: Date, endsAt: Date, deadline: Date?, capacity: Int?, minStudentsPerTeam: Int, maxStudentsPerTeam: Int, registrationMode: String, externalUrl: String?) async {
        busy = true; defer { busy = false }
        do { _ = try await api.updateEvent(event, title: title, description: description, category: category, format: format, venue: venue, startsAt: startsAt, endsAt: endsAt, deadline: deadline, capacity: capacity, minStudentsPerTeam: minStudentsPerTeam, maxStudentsPerTeam: maxStudentsPerTeam, registrationMode: registrationMode, externalUrl: externalUrl); await load(); message = "Draft updated." }
        catch { message = error.localizedDescription }
    }
    func attendees(_ event: OrganizerEvent) async throws -> [OrganizerAttendee] { try await api.attendees(eventId: event.id) }
    func reviews(_ event: OrganizerEvent) async throws -> EventReviewPage { try await api.reviews(eventId: event.id) }
    func replyToReview(_ review: EventReview, event: OrganizerEvent, reply: String) async throws { try await api.replyToReview(eventId: event.id, reviewId: review.id, reply: reply) }
    func markAttendance(_ attendee: OrganizerAttendee, event: OrganizerEvent, status: String) async throws { try await api.markAttendance(eventId: event.id, registrationId: attendee.id, status: status) }
}

struct OrganizerTabView: View {
    @EnvironmentObject private var auth: AuthState
    @StateObject private var model = OrganizerViewModel()
    @State private var selectedTab = 0
    var body: some View {
        TabView(selection: $selectedTab) {
            OrganizerOverviewView(model: model).tabItem { Label("Overview", systemImage: "square.grid.2x2") }.tag(0)
            OrganizerCreateView(model: model).tabItem { Label("Create", systemImage: "plus.square") }.tag(1)
            OrganizerClubView(model: model).tabItem { Label("Club", systemImage: "person.3") }.tag(2)
            OrganizerStudentSwitchView().tabItem { Label("Student", systemImage: "person.crop.circle") }.tag(3)
        }.tint(OrbitStyle.ink).task { await model.load() }
    }
}

private struct OrganizerStudentSwitchView: View {
    @EnvironmentObject private var auth: AuthState

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    VStack(alignment: .leading, spacing: 7) {
                        Text("YOUR ORBIT ACCOUNT").font(.system(size: 10, weight: .bold, design: .rounded)).tracking(1.6).foregroundStyle(OrbitStyle.coral)
                        Text("Student space").font(.system(.largeTitle, design: .rounded, weight: .bold)).tracking(-1).foregroundStyle(OrbitStyle.ink)
                        Text("Switch back to your student experience whenever you’re ready.").font(.subheadline).foregroundStyle(.secondary)
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Label("App appearance", systemImage: "circle.lefthalf.filled").font(.system(.headline, design: .rounded, weight: .bold)).foregroundStyle(OrbitStyle.ink)
                        OrbitAppearancePicker()
                        Text("System follows your iPhone setting.").font(.caption).foregroundStyle(.secondary)
                    }.padding(16).background(OrbitStyle.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))

                    VStack(alignment: .leading, spacing: 18) {
                        HStack(spacing: 14) {
                            Image(systemName: "person.crop.circle.fill").font(.system(size: 48)).symbolRenderingMode(.palette).foregroundStyle(OrbitStyle.coral, OrbitStyle.mint)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(auth.displayName.isEmpty ? "Your profile" : auth.displayName).font(.system(.title3, design: .rounded, weight: .bold)).foregroundStyle(OrbitStyle.ink)
                                Text("Student profile").font(.subheadline).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green).font(.title3)
                        }
                        Divider()
                        VStack(alignment: .leading, spacing: 13) {
                            studentFeature("Discover campus events", icon: "sparkle.magnifyingglass")
                            studentFeature("View registrations and saved events", icon: "calendar")
                            studentFeature("Find teammates and check your inbox", icon: "person.3")
                        }
                    }.padding(20).background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(Color.primary.opacity(0.06)))
                        .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 4)

                    Button { auth.organizerMode = false } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "arrow.left.arrow.right")
                            Text("Switch to Student Profile")
                            Spacer()
                            Image(systemName: "arrow.right")
                        }.font(.system(.headline, design: .rounded, weight: .bold)).foregroundStyle(OrbitStyle.onInk).padding(18).background(OrbitStyle.ink, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    }.buttonStyle(.plain)
                    Text("Your organizer tools and club access will still be available when you switch back.").font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: .infinity)
                }.padding(20).padding(.top, 12)
            }.background(OrbitStyle.paper.ignoresSafeArea()).navigationTitle("Student profile").navigationBarTitleDisplayMode(.inline)
        }
    }

    private func studentFeature(_ title: String, icon: String) -> some View {
        Label(title, systemImage: icon).font(.system(.subheadline, design: .rounded, weight: .medium)).foregroundStyle(OrbitStyle.ink)
    }
}

private struct OrganizerOverviewView: View {
    @ObservedObject var model: OrganizerViewModel
    @State private var selectedEvent: OrganizerEvent?
    @State private var eventToDelete: OrganizerEvent?
    private var publishedCount: Int { model.events.filter { $0.status == "published" }.count }
    private var draftCount: Int { model.events.filter { $0.status == "draft" || $0.status == "rejected" }.count }
    private var dashboardClubHeading: String {
        let eventClubNames = Set(model.events.compactMap { $0.club?.name })
        if eventClubNames.count == 1, let name = eventClubNames.first { return name }
        if model.clubs.count == 1, let club = model.clubs.first { return club.name }
        return model.clubs.isEmpty ? "Your club" : "Your clubs"
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(dashboardClubHeading.uppercased()).font(.system(size: 10, weight: .black, design: .rounded)).tracking(1.6).foregroundStyle(OrbitStyle.coral).lineLimit(1).minimumScaleFactor(0.75)
                            Text("Make campus\nmoments happen.").font(.system(size: 32, weight: .bold, design: .rounded)).tracking(-1).lineSpacing(-3).foregroundStyle(OrbitStyle.ink)
                            Text("Track your events and keep your campus community in the loop.").font(.subheadline).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "sparkles").font(.system(size: 22, weight: .semibold)).foregroundStyle(OrbitStyle.ink).frame(width: 52, height: 52).background(OrbitStyle.yellow, in: RoundedRectangle(cornerRadius: 17, style: .continuous))
                    }

                    HStack(spacing: 10) {
                        metricCard(value: "\(model.events.count)", title: "Total events", icon: "calendar", color: OrbitStyle.mint)
                        metricCard(value: "\(publishedCount)", title: "Live now", icon: "dot.radiowaves.left.and.right", color: OrbitStyle.yellow)
                        metricCard(value: "\(draftCount)", title: "Needs action", icon: "pencil.line", color: Color(red: 1, green: 0.88, blue: 0.84))
                    }

                    HStack(alignment: .firstTextBaseline) {
                        Text("Your events").font(.system(.title2, design: .rounded, weight: .bold)).foregroundStyle(OrbitStyle.ink)
                        Spacer()
                        Text("\(model.events.count) TOTAL").font(.system(size: 9, weight: .bold, design: .rounded)).tracking(1).foregroundStyle(.secondary)
                    }.padding(.top, 2)

                    if let message = model.message {
                        Label(message, systemImage: message.lowercased().contains("error") ? "exclamationmark.circle" : "checkmark.circle")
                            .font(.system(.footnote, design: .rounded, weight: .medium)).foregroundStyle(message.lowercased().contains("error") ? OrbitStyle.coral : OrbitStyle.ink)
                            .padding(13).frame(maxWidth: .infinity, alignment: .leading).background(OrbitStyle.card, in: RoundedRectangle(cornerRadius: 14))
                    }
                    if model.events.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "calendar").font(.system(size: 30)).foregroundStyle(OrbitStyle.coral)
                            Text("No events yet").font(.system(.headline, design: .rounded, weight: .bold)).foregroundStyle(OrbitStyle.ink)
                            Text("Events you publish for your club will appear here, along with their status and management controls.").font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                        }.frame(maxWidth: .infinity).padding(24).background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    } else {
                        VStack(spacing: 12) {
                            ForEach(model.events) { event in eventCard(event) }
                        }
                    }
                }
                .padding(.horizontal, 18).padding(.top, 18).padding(.bottom, 28)
            }.background(OrbitStyle.paper.ignoresSafeArea()).refreshable { await model.load() }.navigationTitle("Organizer").navigationBarTitleDisplayMode(.inline).overlay { if model.busy { ProgressView() } }
                .sheet(item: $selectedEvent) { event in OrganizerEventManagementView(model: model, event: event) }
                .confirmationDialog("Delete this event?", isPresented: Binding(get: { eventToDelete != nil }, set: { if !$0 { eventToDelete = nil } }), titleVisibility: .visible) {
                    Button("Delete Event", role: .destructive) {
                        guard let event = eventToDelete else { return }
                        eventToDelete = nil
                        Task { await model.delete(event) }
                    }
                    Button("Keep Event", role: .cancel) { eventToDelete = nil }
                } message: {
                    Text("This permanently deletes the event and removes its registrations and saved-event entries. Team posts will remain but won’t be linked to the event.")
                }
        }
    }

    private func metricCard(value: String, title: String, icon: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 11) {
            Image(systemName: icon).font(.system(size: 14, weight: .bold)).foregroundStyle(OrbitStyle.ink).frame(width: 30, height: 30).background(color, in: RoundedRectangle(cornerRadius: 10))
            Text(value).font(.system(size: 25, weight: .bold, design: .rounded)).tracking(-0.7).foregroundStyle(OrbitStyle.ink)
            Text(title).font(.system(size: 10, weight: .semibold, design: .rounded)).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.75)
        }.frame(maxWidth: .infinity, alignment: .leading).padding(12).background(OrbitStyle.card, in: RoundedRectangle(cornerRadius: 17, style: .continuous))
    }

    private func eventCard(_ event: OrganizerEvent) -> some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: event.format == "online" ? "video.fill" : "calendar").font(.system(size: 17, weight: .semibold)).foregroundStyle(OrbitStyle.ink).frame(width: 42, height: 42).background(OrbitStyle.mint, in: RoundedRectangle(cornerRadius: 13))
                VStack(alignment: .leading, spacing: 4) {
                    Text(event.title).font(.system(.headline, design: .rounded, weight: .bold)).foregroundStyle(OrbitStyle.ink).lineLimit(2)
                    Text(event.club?.name ?? "Your club").font(.system(.caption, design: .rounded, weight: .medium)).foregroundStyle(.secondary)
                }
                Spacer(minLength: 4)
                Text(event.status.replacingOccurrences(of: "_", with: " ").capitalized).font(.system(size: 9, weight: .bold, design: .rounded)).padding(.horizontal, 9).padding(.vertical, 6).foregroundStyle(statusColor(event.status)).background(statusColor(event.status).opacity(0.12), in: Capsule())
            }
            HStack(spacing: 12) {
                Label(String(event.startsAt.prefix(10)), systemImage: "calendar").lineLimit(1)
                Label(event.category, systemImage: "tag").lineLimit(1)
            }.font(.system(size: 11, weight: .medium, design: .rounded)).foregroundStyle(.secondary)
            HStack(spacing: 10) {
                Button { selectedEvent = event } label: { Label("Manage event", systemImage: "slider.horizontal.3").font(.system(.caption, design: .rounded, weight: .bold)).foregroundStyle(OrbitStyle.onInk).padding(.horizontal, 13).padding(.vertical, 10).background(OrbitStyle.ink, in: Capsule()) }
                if event.status == "draft" || event.status == "rejected" {
                    Button { Task { await model.publish(event) } } label: { Label("Publish", systemImage: "arrow.up.right").font(.system(.caption, design: .rounded, weight: .bold)).foregroundStyle(OrbitStyle.ink).padding(.horizontal, 13).padding(.vertical, 10).background(OrbitStyle.mint, in: Capsule()) }
                }
                Spacer()
                Button(role: .destructive) { eventToDelete = event } label: {
                    Image(systemName: "trash").font(.system(size: 13, weight: .bold)).foregroundStyle(.red).frame(width: 38, height: 38).background(Color.red.opacity(0.08), in: Circle())
                }.accessibilityLabel("Delete \(event.title)")
            }
        }.padding(15).background(OrbitStyle.card, in: RoundedRectangle(cornerRadius: 19, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 19, style: .continuous).stroke(OrbitStyle.ink.opacity(0.05)))
            .shadow(color: .black.opacity(0.04), radius: 7, x: 0, y: 3)
    }

    private func statusColor(_ status: String) -> Color { switch status { case "published": .green; case "rejected": OrbitStyle.coral; case "pending_review": .orange; default: OrbitStyle.ink } }
}

private struct OrganizerCreateView: View {
    @ObservedObject var model: OrganizerViewModel
    @State private var title = ""
    @State private var description = ""
    @State private var category = "Hackathon"
    @State private var format = "in_person"
    @State private var venue = ""
    @State private var startsAt = Calendar.current.date(byAdding: .day, value: 7, to: .now) ?? .now
    @State private var endsAt = Calendar.current.date(byAdding: .hour, value: 3, to: Calendar.current.date(byAdding: .day, value: 7, to: .now) ?? .now) ?? .now
    @State private var selectedClub = ""
    @State private var capacity = ""
    @State private var minStudentsPerTeam = 1
    @State private var maxStudentsPerTeam = 1
    @State private var registrationMode = "native"
    @State private var externalUrl = ""
    @State private var hasDeadline = true
    @State private var deadline = Calendar.current.date(byAdding: .day, value: 6, to: .now) ?? .now
    @State private var eventPrompt = ""
    @State private var promptAssistantMessage: String?
    @State private var planningPrompt = ""
    @State private var eventIdeas: [OrganizerEventIdea] = []
    @State private var eventIdeasEvidence: OrganizerIdeasResponse.Evidence?
    @State private var eventIdeasMessage: String?
    @State private var isLoadingIdeas = false
    @State private var posterSelection: PhotosPickerItem?
    @State private var posterData: Data?
    @State private var posterPreview: UIImage?
    private let categories = ["Hackathon", "Workshop", "Technology", "Competition", "Social"]
    private var deadlineRangeIsValid: Bool { startsAt > Date() && deadline >= Date() && deadline < startsAt }
    private var deadlinePickerRange: ClosedRange<Date> {
        let now = Date()
        let lower = min(now, startsAt.addingTimeInterval(-1))
        let upper = max(lower, startsAt.addingTimeInterval(-1))
        return lower...upper
    }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Create an event").font(.title2.bold()).foregroundStyle(.primary)
                        Text("Bring your campus community together.").font(.subheadline).foregroundStyle(.secondary)
                    }.padding(.horizontal, 4)
                    if model.clubs.isEmpty {
                        card("Organizer club required", icon: "person.3") {
                            Text("Create or join a club first in the Club tab.").font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                    card("Draft with prompt assistant", icon: "sparkles") {
                        Text("Describe your event and we’ll fill in the title, venue, and team size for you to review.").font(.subheadline).foregroundStyle(.secondary)
                        TextField("e.g. Create a robotics hackathon at Main Hall for teams of 2–5", text: $eventPrompt, axis: .vertical)
                            .lineLimit(2...4).keyboardType(.asciiCapable).textInputAutocapitalization(.never).autocorrectionDisabled().textFieldStyle(.roundedBorder)
                        Button { applyEventPrompt() } label: {
                            Label("Fill event details", systemImage: "wand.and.stars")
                                .font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity).padding(.vertical, 12)
                                .background(Color.accentColor.opacity(eventPrompt.isEmpty ? 0.1 : 0.16), in: RoundedRectangle(cornerRadius: 12))
                        }.buttonStyle(.plain).disabled(eventPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        if let promptAssistantMessage { Text(promptAssistantMessage).font(.caption).foregroundStyle(.secondary) }
                    }
                    card("Plan around student interests", icon: "chart.bar.xaxis") {
                        Text("Get event ideas from this club’s past registrations and students’ chosen interests. Only aggregated interest groups with at least 3 registrations are shared with Gemini.").font(.subheadline).foregroundStyle(.secondary)
                        TextField("What kind of event are you planning?", text: $planningPrompt, axis: .vertical)
                            .lineLimit(2...4).textFieldStyle(.roundedBorder)
                        Button {
                            Task { await loadEventIdeas() }
                        } label: {
                            HStack { if isLoadingIdeas { ProgressView() } else { Image(systemName: "sparkles"); Text("Suggest event ideas") } }
                                .font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity).padding(.vertical, 12)
                                .background(Color.accentColor.opacity(0.14), in: RoundedRectangle(cornerRadius: 12))
                        }.buttonStyle(.plain).disabled(isLoadingIdeas || selectedClub.isEmpty || planningPrompt.trimmingCharacters(in: .whitespacesAndNewlines).count < 8)
                        if let eventIdeasEvidence {
                            Text("Based on \(eventIdeasEvidence.registeredAttendeesCount) registrations. Interest labels are suppressed below 3 people.").font(.caption).foregroundStyle(.secondary)
                            if !eventIdeasEvidence.popularInterests.isEmpty {
                                Text("Top interests: " + eventIdeasEvidence.popularInterests.prefix(5).map { "\($0.label) (\($0.count))" }.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        if let eventIdeasMessage { Text(eventIdeasMessage).font(.caption).foregroundColor(eventIdeas.isEmpty ? Color.red : Color.secondary) }
                        ForEach(eventIdeas) { idea in
                            VStack(alignment: .leading, spacing: 7) {
                                HStack(alignment: .top) {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(idea.title).font(.subheadline.weight(.bold))
                                        Text("\(idea.category) · \(idea.minStudentsPerTeam)–\(idea.maxStudentsPerTeam) students").font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Button("Use idea") { applyIdea(idea) }.font(.caption.weight(.bold))
                                }
                                Text(idea.description).font(.caption)
                                Text(idea.rationale).font(.caption).foregroundStyle(.secondary)
                            }.padding(12).background(OrbitStyle.paper, in: RoundedRectangle(cornerRadius: 14))
                        }
                    }
                    card("Event details", icon: "sparkle.magnifyingglass") {
                        Picker("Host club", selection: $selectedClub) { ForEach(model.clubs) { Text($0.name).tag($0.id) } }
                        TextField("Event title", text: $title).textFieldStyle(.roundedBorder)
                        Picker("Category", selection: $category) { ForEach(Array(Set(categories + [category])).sorted(), id: \.self) { Text($0) } }
                        TextField("What will happen?", text: $description, axis: .vertical).lineLimit(3...6).textFieldStyle(.roundedBorder)
                    }
                    card("When and where", icon: "calendar") {
                        DatePicker("Starts", selection: $startsAt, in: Date()...)
                        DatePicker("Ends", selection: $endsAt, in: startsAt...)
                        Picker("Format", selection: $format) { Text("In person").tag("in_person"); Text("Online").tag("online"); Text("Hybrid").tag("hybrid") }
                        if format != "online" { TextField("Venue", text: $venue).textFieldStyle(.roundedBorder) }
                    }
                    card("Event photo", icon: "photo") {
                        if let posterPreview {
                            Image(uiImage: posterPreview).resizable().scaledToFill().frame(height: 170).frame(maxWidth: .infinity).clipped().clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                        PhotosPicker(selection: $posterSelection, matching: .images) {
                            Label(posterPreview == nil ? "Choose a club photo" : "Change event photo", systemImage: "photo.on.rectangle.angled")
                                .font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity).padding(.vertical, 12)
                                .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
                        }.buttonStyle(.plain)
                        if posterPreview != nil { Button("Remove photo", role: .destructive) { posterPreview = nil; posterData = nil; posterSelection = nil }.font(.subheadline.weight(.medium)) }
                        Text("Optional JPEG, up to 5 MB. It appears on the event card.").font(.caption).foregroundStyle(.secondary)
                    }
                    card("Registration", icon: "person.2") {
                        Stepper("Minimum team size · \(minStudentsPerTeam)", value: $minStudentsPerTeam, in: 1...100)
                        Stepper("Maximum team size · \(maxStudentsPerTeam)", value: $maxStudentsPerTeam, in: minStudentsPerTeam...100)
                        Text(minStudentsPerTeam == 1 && maxStudentsPerTeam == 1 ? "Individual registration; no team is needed." : "Leaders register the whole team after it reaches this size.").font(.caption).foregroundStyle(.secondary)
                        Picker("Registration", selection: $registrationMode) { Text("Register in Orbit").tag("native"); Text("External link").tag("external") }
                        if registrationMode == "external" { TextField("Registration URL", text: $externalUrl).keyboardType(.URL).textInputAutocapitalization(.never).textFieldStyle(.roundedBorder) }
                        TextField("Capacity (blank for unlimited)", text: $capacity).keyboardType(.numberPad).textFieldStyle(.roundedBorder)
                        Toggle("Set registration deadline", isOn: $hasDeadline)
                        if hasDeadline {
                            DatePicker("Deadline", selection: $deadline, in: deadlinePickerRange)
                            if !deadlineRangeIsValid { Label("Choose a future deadline before the event starts.", systemImage: "exclamationmark.triangle.fill").font(.footnote).foregroundStyle(.red) }
                        }
                    }
                    if let message = model.message {
                        Text(message).font(.subheadline).foregroundColor(isSuccessMessage(message) ? Color.green : Color.red)
                            .frame(maxWidth: .infinity, alignment: .leading).padding(14).background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
                    }
                    Button(action: createEvent) {
                        HStack { if model.busy { ProgressView().tint(.white) }; Text(model.busy ? "Creating event…" : "Create event"); Spacer(); Image(systemName: "arrow.right") }
                            .font(.headline).foregroundStyle(.white).padding(16).background(Color.accentColor, in: RoundedRectangle(cornerRadius: 14))
                    }.buttonStyle(.plain).disabled(!canCreateEvent).opacity(canCreateEvent ? 1 : 0.55)
                    if !canCreateEvent, let reason = createDisabledReason {
                        Text(reason).font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
                    }
                }.padding(16)
            }
            .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
            .navigationTitle("Create event").navigationBarTitleDisplayMode(.inline)
                .onAppear { if selectedClub.isEmpty { selectedClub = model.clubs.first?.id ?? "" } }
                .onChange(of: startsAt) { _, newStart in
                    if endsAt <= newStart { endsAt = newStart.addingTimeInterval(3600) }
                    let latestDeadline = newStart.addingTimeInterval(-1)
                    if deadline >= newStart { deadline = latestDeadline }
                }
                .onChange(of: minStudentsPerTeam) { _, newMinimum in
                    if maxStudentsPerTeam < newMinimum { maxStudentsPerTeam = newMinimum }
                }
                .onChange(of: posterSelection) { _, selection in
                    guard let selection else { return }
                    Task {
                        guard let raw = try? await selection.loadTransferable(type: Data.self), let image = UIImage(data: raw) else {
                            promptAssistantMessage = "That photo could not be loaded. Please choose another image."
                            return
                        }
                        let largestDimension = max(image.size.width, image.size.height)
                        let resizeFactor = min(1, 1800 / max(largestDimension, 1))
                        let targetSize = CGSize(width: image.size.width * resizeFactor, height: image.size.height * resizeFactor)
                        let renderer = UIGraphicsImageRenderer(size: targetSize)
                        let resizedImage = resizeFactor < 1 ? renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: targetSize)) } : image
                        guard let jpeg = resizedImage.jpegData(compressionQuality: 0.72), jpeg.count <= 5 * 1024 * 1024 else {
                            promptAssistantMessage = "That photo is too large to upload. Choose a smaller image."
                            return
                        }
                        posterPreview = resizedImage
                        posterData = jpeg
                    }
                }
        }
    }

    private var canCreateEvent: Bool {
        !model.busy && !model.clubs.isEmpty && !title.trimmingCharacters(in: .whitespaces).isEmpty &&
        !description.trimmingCharacters(in: .whitespaces).isEmpty && endsAt > startsAt &&
        (capacity.isEmpty || (Int(capacity).map { $0 >= 1 } ?? false)) &&
        (registrationMode != "external" || !externalUrl.trimmingCharacters(in: .whitespaces).isEmpty) &&
        (!hasDeadline || deadlineRangeIsValid)
    }

    private var createDisabledReason: String? {
        if model.busy { return "Please wait for the current request to finish." }
        if model.clubs.isEmpty { return "Create or join a club before creating an event." }
        if title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "Add an event title to continue." }
        if description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "Add an event description to continue." }
        if startsAt <= Date() { return "Choose a future event start time." }
        if endsAt <= startsAt { return "The event end time must be after its start time." }
        if !capacity.isEmpty && (Int(capacity).map { $0 >= 1 } ?? false) == false { return "Capacity must be a positive whole number, or left blank." }
        if registrationMode == "external" && externalUrl.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "Add the external registration URL." }
        if hasDeadline && !deadlineRangeIsValid { return "Choose a future registration deadline before the event starts." }
        return nil
    }

    private func isSuccessMessage(_ message: String) -> Bool {
        ["created", "deleted", "published", "saved", "updated", "sent"].contains { message.localizedCaseInsensitiveContains($0) }
    }

    private func createEvent() {
        guard canCreateEvent, let club = model.clubs.first(where: { $0.id == selectedClub }) ?? model.clubs.first else { return }
        Task { await model.createEvent(clubId: club.id, title: title, description: description, category: category, format: format, venue: venue, startsAt: startsAt, endsAt: endsAt, deadline: hasDeadline ? deadline : nil, capacity: Int(capacity), minStudentsPerTeam: minStudentsPerTeam, maxStudentsPerTeam: maxStudentsPerTeam, registrationMode: registrationMode, externalUrl: externalUrl.isEmpty ? nil : externalUrl, posterData: posterData) }
    }

    private func loadEventIdeas() async {
        guard !selectedClub.isEmpty else { return }
        isLoadingIdeas = true
        eventIdeasMessage = nil
        defer { isLoadingIdeas = false }
        do {
            let response = try await CommunityAPI().organizerEventIdeas(clubId: selectedClub, prompt: planningPrompt)
            eventIdeas = response.ideas
            eventIdeasEvidence = response.evidence
            eventIdeasMessage = response.ideas.isEmpty ? "No event ideas came back. Try a more specific prompt." : nil
        } catch { eventIdeasMessage = error.localizedDescription }
    }

    private func applyIdea(_ idea: OrganizerEventIdea) {
        title = idea.title
        description = idea.description
        category = idea.category
        format = idea.format
        minStudentsPerTeam = idea.minStudentsPerTeam
        maxStudentsPerTeam = idea.maxStudentsPerTeam
        if format == "online" { venue = "" }
        promptAssistantMessage = "Idea added to the event form. Review the details and choose the date and venue."
    }

    private func card<Content: View>(_ title: String, icon: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(title, systemImage: icon).font(.headline).foregroundStyle(.primary)
            content()
        }.frame(maxWidth: .infinity, alignment: .leading).padding(16)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 4)
    }

    private func applyEventPrompt() {
        let extracted = EventPromptParser.parse(eventPrompt)
        if let extractedTitle = extracted.title { title = extractedTitle }
        if let extractedVenue = extracted.venue { venue = extractedVenue }
        if let minimum = extracted.minimumTeamSize { minStudentsPerTeam = minimum }
        if let maximum = extracted.maximumTeamSize { maxStudentsPerTeam = max(maximum, minStudentsPerTeam) }
        if description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { description = eventPrompt.trimmingCharacters(in: .whitespacesAndNewlines) }
        let missing: [String] = [extracted.title == nil ? "event name" : nil, extracted.venue == nil ? "venue" : nil, extracted.minimumTeamSize == nil || extracted.maximumTeamSize == nil ? "team size" : nil].compactMap { $0 }
        promptAssistantMessage = missing.isEmpty
            ? "Details filled in. Review the event form, then tap Create event when ready."
            : "Filled what I could. Add or correct: \(missing.joined(separator: ", "))."
    }
}

private struct EventPromptParser {
    let title: String?
    let venue: String?
    let minimumTeamSize: Int?
    let maximumTeamSize: Int?

    static func parse(_ prompt: String) -> EventPromptParser {
        let rangeMinimum = capture(#"\bteams?\s*(?:of\s*)?(\d{1,3})\s*(?:-|–|to)\s*(\d{1,3})\b"#, in: prompt, group: 1).flatMap(Int.init)
        let rangeMaximum = capture(#"\bteams?\s*(?:of\s*)?(\d{1,3})\s*(?:-|–|to)\s*(\d{1,3})\b"#, in: prompt, group: 2).flatMap(Int.init)
        let explicitMinimum = capture(#"\bmin(?:imum)?(?:\s+team\s+size)?\s*(?:of|:|=)?\s*(\d{1,3})\b"#, in: prompt).flatMap(Int.init)
        let explicitMaximum = capture(#"\bmax(?:imum)?(?:\s+team\s+size|\s+registrations?)?\s*(?:of|:|=)?\s*(\d{1,3})\b"#, in: prompt).flatMap(Int.init)
        let minimum = bounded(explicitMinimum ?? rangeMinimum)
        let maximum = bounded(explicitMaximum ?? rangeMaximum)
        let title = capture(#"\b(?:event(?:\s+name)?|name)\s*(?:is|:)\s*[\"“]?(.+?)[\"”]?(?=,|;|\s+at\b|\s+for teams?\b|$)"#, in: prompt)
            ?? capture(#"^(?:please\s+)?(?:create|plan|organize|organise|schedule|make)\s+(.+?)(?=\s+at\b|\s+for teams?\b|,|;|$)"#, in: prompt)
        let venue = capture(#"\b(?:at|venue(?:\s+is)?|location(?:\s+is)?)\s+(.+?)(?=,|;|\s+for teams?\b|\s+with teams?\b|\s+min(?:imum)?\b|\s+max(?:imum)?\b|$)"#, in: prompt)
        return EventPromptParser(title: cleaned(title), venue: cleaned(venue), minimumTeamSize: minimum, maximumTeamSize: maximum ?? minimum)
    }

    private static func bounded(_ value: Int?) -> Int? { value.map { min(max($0, 1), 100) } }
    private static func cleaned(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: "\"“”'"))), !value.isEmpty else { return nil }
        return value
    }
    private static func capture(_ pattern: String, in text: String, group: Int = 1) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              group < match.numberOfRanges,
              let range = Range(match.range(at: group), in: text) else { return nil }
        return String(text[range])
    }
}

private struct OrganizerClubView: View {
    @ObservedObject var model: OrganizerViewModel
    @State private var name = ""
    @State private var description = ""
    @State private var proofUrl = ""
    @State private var proofNotes = ""
    @State private var reviewerNote = ""
    @State private var selectedCollege = ""
    @State private var managedClub: OrganizerClub?
    var body: some View {
        NavigationStack {
            Form {
                Section("Your clubs") {
                    if model.clubs.isEmpty { Text("No clubs yet. Create one below.").foregroundStyle(.secondary) }
                    ForEach(model.clubs) { club in
                        VStack(alignment: .leading) {
                            HStack { Text(club.name).font(.headline); Spacer(); Text("Organizer access").font(.caption.weight(.semibold)).foregroundColor(.green) }
                            Text("\(club.college.name) · Your role: \((club.currentRole ?? "editor").capitalized)").font(.caption).foregroundStyle(.secondary)
                            if club.currentRole == "owner" || club.currentRole == "manager" {
                                Button("Manage members") { managedClub = club }.font(.caption.weight(.semibold)).padding(.top, 2)
                            }
                        }
                    }
                }
                Section("Create a club") {
                    Picker("College", selection: $selectedCollege) { ForEach(model.colleges) { Text($0.name).tag($0.id) } }
                    TextField("Club name", text: $name)
                    TextField("What is the club about?", text: $description, axis: .vertical).lineLimit(2...4)
                    TextField("Official club or college page (HTTPS)", text: $proofUrl).keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                    TextField("How does this page prove the club is official?", text: $proofNotes, axis: .vertical).lineLimit(2...4)
                    Text("A verifier checks the proof. For safety, new club organizer access cannot be approved before 48 hours have passed.").font(.caption).foregroundStyle(.secondary)
                    Button("Create club") {
                        guard let college = model.colleges.first(where: { $0.id == selectedCollege }) ?? model.colleges.first else { return }
                        Task { await model.createClub(collegeId: college.id, name: name, description: description, proofUrl: proofUrl, proofNotes: proofNotes); name = "" }
                    }.disabled(model.busy || model.colleges.isEmpty || name.trimmingCharacters(in: .whitespaces).isEmpty || proofUrl.isEmpty || proofNotes.trimmingCharacters(in: .whitespacesAndNewlines).count < 10)
                }
                if !model.verificationRequests.isEmpty {
                    Section("Verification status") {
                        ForEach(model.verificationRequests) { claim in
                            VStack(alignment: .leading, spacing: 7) {
                                HStack { Text(claim.club.name).font(.headline); Spacer(); Text(claim.status.capitalized).font(.caption.bold()).foregroundStyle(claim.status == "approved" ? .green : claim.status == "rejected" ? .red : .orange) }
                                Text(claim.club.college.name).font(.caption).foregroundStyle(.secondary)
                                if claim.status == "pending" { Text("A verifier is checking your proof. Organizer access can begin after the 48-hour hold and approval.").font(.caption).foregroundStyle(.secondary) }
                                if let note = claim.reviewNote, !note.isEmpty { Text("Verifier note: \(note)").font(.caption).foregroundStyle(.secondary) }
                                if claim.status == "rejected" {
                                    Button("Resubmit using the proof fields above") { Task { await model.resubmitVerification(claim, proofUrl: proofUrl, proofNotes: proofNotes) } }
                                        .disabled(model.busy || proofUrl.isEmpty || proofNotes.count < 10)
                                }
                            }.padding(.vertical, 4)
                        }
                    }
                }
                if !model.verificationQueue.isEmpty {
                    Section("Club verification queue") {
                        ForEach(model.verificationQueue) { claim in
                            VStack(alignment: .leading, spacing: 8) {
                                Text(claim.club.name).font(.headline)
                                Text("\(claim.club.college.name) · Applicant: \(claim.applicant?.studentProfile?.displayName ?? claim.applicant?.emailNormalized ?? "Student")").font(.caption).foregroundStyle(.secondary)
                                Link(claim.proofUrl, destination: URL(string: claim.proofUrl) ?? URL(string: "https://example.com")!).font(.caption)
                                Text(claim.proofNotes).font(.caption)
                                Text("Eligible after: \(claim.eligibleAt)").font(.caption2).foregroundStyle(.secondary)
                                TextField("Reviewer note (optional)", text: $reviewerNote, axis: .vertical).lineLimit(1...3).textFieldStyle(.roundedBorder)
                                HStack {
                                    Button("Approve and grant organizer access") { Task { await model.decideVerification(claim, decision: "approve") } }
                                        .disabled(model.busy || !ClubVerificationRequest.isEligible(claim.eligibleAt))
                                    Button("Reject", role: .destructive) { Task { await model.decideVerification(claim, decision: "reject", note: reviewerNote); reviewerNote = "" } }.disabled(model.busy)
                                }.font(.caption.weight(.semibold))
                            }.padding(.vertical, 5)
                        }
                    }
                }
                if let message = model.message { Section { Text(message).font(.footnote).foregroundStyle(.secondary) } }
            }.navigationTitle("Club").onAppear { if selectedCollege.isEmpty { selectedCollege = model.colleges.first?.id ?? "" } }
                .sheet(item: $managedClub) { club in ManageClubMembersView(club: club) }
        }
    }
}

@MainActor
private final class ClubMembersViewModel: ObservableObject {
    @Published var members: [OrganizerClubMember] = []
    @Published var email = ""
    @Published var role = "editor"
    @Published var message: String?
    @Published var busy = false
    let club: OrganizerClub
    private let api = OrganizerAPI()
    init(club: OrganizerClub) { self.club = club }
    func load() async { do { members = try await api.members(clubId: club.id); message = nil } catch { message = error.localizedDescription } }
    func invite() async {
        busy = true; defer { busy = false }
        do { try await api.invite(clubId: club.id, email: email, role: role); email = ""; await load(); message = "Invitation sent." }
        catch { message = error.localizedDescription }
    }
    func changeRole(_ member: OrganizerClubMember, role: String) async {
        do { try await api.updateMember(clubId: club.id, userId: member.userId, role: role); await load(); message = "Member role updated." }
        catch { message = error.localizedDescription }
    }
    func remove(_ member: OrganizerClubMember) async {
        do { try await api.removeMember(clubId: club.id, userId: member.userId); await load(); message = "Member removed." }
        catch { message = error.localizedDescription }
    }
}

private struct ManageClubMembersView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var model: ClubMembersViewModel
    private let isOwner: Bool
    init(club: OrganizerClub) { _model = StateObject(wrappedValue: ClubMembersViewModel(club: club)); isOwner = club.currentRole == "owner" }
    var body: some View {
        NavigationStack {
            List {
                Section("Invite a student") {
                    TextField("Orbit student email", text: $model.email).keyboardType(.emailAddress).textInputAutocapitalization(.never).autocorrectionDisabled()
                    if isOwner { Picker("Role", selection: $model.role) { Text("Event editor").tag("editor"); Text("Manager").tag("manager") } }
                    Text("Invite an existing Orbit student whose profile college is \(model.club.college.name). They’ll accept in their Inbox.").font(.caption).foregroundStyle(.secondary)
                    Button(model.busy ? "Sending…" : "Send invitation") { Task { await model.invite() } }.disabled(model.busy || model.email.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                Section("Members and invitations") {
                    if model.members.isEmpty { Text("No club members found.").foregroundStyle(.secondary) }
                    ForEach(model.members) { member in
                        HStack(spacing: 10) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(member.user.studentProfile?.displayName ?? "Orbit student").font(.headline)
                Text("\(member.role.capitalized) · \(member.status.capitalized)").font(.caption).foregroundColor(member.status == "invited" ? .orange : .secondary)
                            }
                            Spacer()
                            if member.role != "owner" {
                                Menu {
                                    if isOwner {
                                        Button("Make event editor") { Task { await model.changeRole(member, role: "editor") } }
                                        Button("Make manager") { Task { await model.changeRole(member, role: "manager") } }
                                    }
                                    if isOwner || member.role == "editor" { Button("Remove from club", role: .destructive) { Task { await model.remove(member) } } }
                                } label: { Image(systemName: "ellipsis.circle") }.accessibilityLabel("Member actions")
                            }
                        }.padding(.vertical, 3)
                    }
                }
                if let message = model.message { Section { Text(message).font(.footnote).foregroundColor(message.contains("sent") || message.contains("updated") || message.contains("removed") ? .secondary : .red) } }
            }.navigationTitle(model.club.name).toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
                .task { await model.load() }.refreshable { await model.load() }
        }
    }
}

private struct OrganizerEventManagementView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var model: OrganizerViewModel
    let event: OrganizerEvent
    @State private var attendees: [OrganizerAttendee] = []
    @State private var reviews: [EventReview] = []
    @State private var reviewAverage: Double?
    @State private var reviewCount = 0
    @State private var replyDrafts: [String: String] = [:]
    @State private var error: String?
    @State private var isLoading = false
    @State private var showEditor = false

    var body: some View {
        NavigationStack {
            List {
                Section("Event") {
                    LabeledContent("Status", value: event.status.replacingOccurrences(of: "_", with: " ").capitalized)
                    LabeledContent("When", value: "\(event.startsAt.prefix(16).replacingOccurrences(of: "T", with: " "))")
                    LabeledContent("Registration", value: event.registrationMode == "external" ? "External link" : "In Orbit")
                    LabeledContent("Team size", value: "\(event.minStudentsPerTeam)–\(event.maxStudentsPerTeam) students")
                    LabeledContent("Capacity", value: event.capacity.map(String.init) ?? "Unlimited")
                    if let url = event.externalUrl, let destination = URL(string: url) { Link("Open registration link", destination: destination) }
                    if event.status != "cancelled" && event.status != "completed" { Button("Edit event") { showEditor = true } }
                }
                Section("Attendees · \(attendees.count)") {
                    if !attendees.isEmpty {
                        HStack {
                            Label("\(attendees.filter { $0.status == "registered" }.count) registered", systemImage: "checkmark.circle.fill").foregroundColor(.green)
                            Spacer()
                            Label("\(attendees.filter { $0.status == "waitlisted" }.count) waitlisted", systemImage: "clock.fill").foregroundColor(.orange)
                        }.font(.caption.weight(.medium))
                    }
                    if isLoading { ProgressView() }
                    else if attendees.isEmpty { Text("No registrations yet.").foregroundStyle(.secondary) }
                    ForEach(attendees) { attendee in
                        VStack(alignment: .leading, spacing: 7) {
                            HStack { Text(attendee.student.studentProfile?.displayName ?? "Student").font(.headline); Spacer(); Text(attendee.status.replacingOccurrences(of: "_", with: " ").capitalized).font(.caption.weight(.semibold)).foregroundColor(attendee.status == "attended" ? .green : .secondary) }
                            if let profile = attendee.student.studentProfile {
                                Text([profile.course, profile.year.map { "Year \($0)" }].compactMap { $0 }.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary)
                            }
                            if ["registered", "attended", "no_show"].contains(attendee.status) {
                                HStack {
                                    Button("Mark attended") { Task { await setAttendance(attendee, status: "attended") } }.font(.caption)
                                    Button("Mark no-show", role: .destructive) { Task { await setAttendance(attendee, status: "no_show") } }.font(.caption)
                                }
                            }
                        }.padding(.vertical, 4)
                    }
                }
                Section("Reviews · \(reviewCount)") {
                    if let reviewAverage { Label(String(format: "%.1f average rating", reviewAverage), systemImage: "star.fill").font(.caption.weight(.semibold)).foregroundStyle(OrbitStyle.coral) }
                    if reviews.isEmpty && !isLoading { Text("Attendee reviews will appear here after the event.").foregroundStyle(.secondary) }
                    ForEach(reviews) { review in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack { Text(review.authorName).font(.subheadline.weight(.semibold)); Spacer(); Label("\(review.rating)/5", systemImage: "star.fill").font(.caption.weight(.semibold)).foregroundStyle(OrbitStyle.coral) }
                            Text(review.body).font(.subheadline)
                            if let currentReply = review.organizerReply, !currentReply.isEmpty { Text("Your reply: \(currentReply)").font(.caption).foregroundStyle(.secondary) }
                            TextField("Reply as the organizer…", text: Binding(get: { replyDrafts[review.id] ?? "" }, set: { replyDrafts[review.id] = $0 }), axis: .vertical).lineLimit(2...4).textFieldStyle(.roundedBorder)
                            Button("Send reply") { Task { await sendReply(to: review) } }
                                .font(.caption.weight(.semibold)).disabled((replyDrafts[review.id] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }.padding(.vertical, 5)
                    }
                }
                if let error { Section { Text(error).font(.footnote).foregroundStyle(.red) } }
            }.navigationTitle(event.title).toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
                .task { await loadAttendees() }
                .refreshable { await loadAttendees() }
                .sheet(isPresented: $showEditor) { EditOrganizerEventSheet(event: event) { values in Task { await model.update(event, title: values.title, description: values.description, category: values.category, format: values.format, venue: values.venue, startsAt: values.startsAt, endsAt: values.endsAt, deadline: values.deadline, capacity: values.capacity, minStudentsPerTeam: values.minStudentsPerTeam, maxStudentsPerTeam: values.maxStudentsPerTeam, registrationMode: values.registrationMode, externalUrl: values.externalUrl); await loadAttendees() } } }
        }
    }

    private func loadAttendees() async {
        isLoading = true; defer { isLoading = false }
        do {
            attendees = try await model.attendees(event)
            let page = try await model.reviews(event)
            reviews = page.data; reviewAverage = page.averageRating; reviewCount = page.reviewCount
            error = nil
        }
        catch { self.error = error.localizedDescription }
    }
    private func sendReply(to review: EventReview) async {
        do {
            try await model.replyToReview(review, event: event, reply: replyDrafts[review.id] ?? "")
            replyDrafts[review.id] = ""
            await loadAttendees()
        } catch { self.error = error.localizedDescription }
    }
    private func setAttendance(_ attendee: OrganizerAttendee, status: String) async {
        do { try await model.markAttendance(attendee, event: event, status: status); await loadAttendees() }
        catch { self.error = error.localizedDescription }
    }
}

private struct OrganizerEventEditValues {
    let title: String; let description: String; let category: String; let format: String; let venue: String
    let startsAt: Date; let endsAt: Date; let deadline: Date?; let capacity: Int?; let minStudentsPerTeam: Int; let maxStudentsPerTeam: Int; let registrationMode: String; let externalUrl: String?
}

private struct EditOrganizerEventSheet: View {
    @Environment(\.dismiss) private var dismiss
    let event: OrganizerEvent
    let save: (OrganizerEventEditValues) -> Void
    @State private var title: String
    @State private var details: String
    @State private var category: String
    @State private var format: String
    @State private var venue: String
    @State private var startsAt: Date
    @State private var endsAt: Date
    @State private var deadline: Date
    @State private var hasDeadline: Bool
    @State private var capacity: String
    @State private var minStudentsPerTeam: Int
    @State private var maxStudentsPerTeam: Int
    @State private var registrationMode: String
    @State private var externalUrl: String
    private let categories = ["Hackathon", "Workshop", "Technology", "Competition", "Social"]
    private var deadlineRangeIsValid: Bool { startsAt > Date() && deadline >= Date() && deadline < startsAt }
    private var deadlinePickerRange: ClosedRange<Date> {
        let now = Date()
        let lower = min(now, startsAt.addingTimeInterval(-1))
        let upper = max(lower, startsAt.addingTimeInterval(-1))
        return lower...upper
    }

    init(event: OrganizerEvent, save: @escaping (OrganizerEventEditValues) -> Void) {
        self.event = event; self.save = save
        _title = State(initialValue: event.title); _details = State(initialValue: event.description); _category = State(initialValue: event.category)
        _format = State(initialValue: event.format); _venue = State(initialValue: event.venue ?? "")
        _startsAt = State(initialValue: dateFromISO(event.startsAt) ?? .now); _endsAt = State(initialValue: dateFromISO(event.endsAt) ?? .now.addingTimeInterval(3600))
        let parsedDeadline = event.registrationDeadline.flatMap(dateFromISO)
        _deadline = State(initialValue: parsedDeadline ?? .now); _hasDeadline = State(initialValue: parsedDeadline != nil)
        _capacity = State(initialValue: event.capacity.map(String.init) ?? ""); _minStudentsPerTeam = State(initialValue: event.minStudentsPerTeam); _maxStudentsPerTeam = State(initialValue: event.maxStudentsPerTeam); _registrationMode = State(initialValue: event.registrationMode); _externalUrl = State(initialValue: event.externalUrl ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Event details") {
                    TextField("Title", text: $title)
                    Picker("Category", selection: $category) { ForEach(categories, id: \.self) { Text($0) } }
                    TextField("Description", text: $details, axis: .vertical).lineLimit(3...6)
                }
                Section("Schedule and location") {
                    DatePicker("Starts", selection: $startsAt, in: Date()...)
                    DatePicker("Ends", selection: $endsAt, in: startsAt...)
                    Picker("Format", selection: $format) { Text("In person").tag("in_person"); Text("Online").tag("online"); Text("Hybrid").tag("hybrid") }
                    if format != "online" { TextField("Venue", text: $venue) }
                }
                Section("Registration") {
                    Stepper("Minimum team size: \(minStudentsPerTeam)", value: $minStudentsPerTeam, in: 1...100)
                    Stepper("Maximum team size: \(maxStudentsPerTeam)", value: $maxStudentsPerTeam, in: minStudentsPerTeam...100)
                    Text(minStudentsPerTeam == 1 && maxStudentsPerTeam == 1 ? "Individual registration." : "Team leaders can register a team when it meets this size.").font(.caption).foregroundStyle(.secondary)
                    Picker("Registration", selection: $registrationMode) { Text("In Orbit").tag("native"); Text("External link").tag("external") }
                    if registrationMode == "external" { TextField("Registration URL", text: $externalUrl).keyboardType(.URL).textInputAutocapitalization(.never) }
                    TextField("Capacity (blank for unlimited)", text: $capacity).keyboardType(.numberPad)
                    Toggle("Set registration deadline", isOn: $hasDeadline)
                    if hasDeadline {
                        DatePicker("Deadline", selection: $deadline, in: deadlinePickerRange)
                        if !deadlineRangeIsValid {
                            Label("Invalid date: choose a deadline before the event starts and in the future.", systemImage: "exclamationmark.triangle.fill")
                                .font(.footnote).foregroundStyle(.red)
                        }
                    }
                }
            }.navigationTitle("Edit draft").toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        guard !hasDeadline || deadlineRangeIsValid else { return }
                        save(OrganizerEventEditValues(title: title, description: details, category: category, format: format, venue: venue, startsAt: startsAt, endsAt: endsAt, deadline: hasDeadline ? deadline : nil, capacity: Int(capacity), minStudentsPerTeam: minStudentsPerTeam, maxStudentsPerTeam: maxStudentsPerTeam, registrationMode: registrationMode, externalUrl: externalUrl.isEmpty ? nil : externalUrl))
                        dismiss()
                    }.disabled(title.trimmingCharacters(in: .whitespaces).isEmpty || details.trimmingCharacters(in: .whitespaces).isEmpty || (hasDeadline && !deadlineRangeIsValid))
                }
            }
            .onChange(of: startsAt) { _, newStart in
                if endsAt <= newStart { endsAt = newStart.addingTimeInterval(3600) }
                let latestDeadline = newStart.addingTimeInterval(-1)
                if deadline >= newStart { deadline = latestDeadline }
            }
            .onChange(of: minStudentsPerTeam) { _, newMinimum in
                if maxStudentsPerTeam < newMinimum { maxStudentsPerTeam = newMinimum }
            }
        }
    }
}

private func dateFromISO(_ value: String) -> Date? {
    let formatter = ISO8601DateFormatter()
    if let date = formatter.date(from: value) { return date }
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter.date(from: value)
}
