import SwiftUI

@MainActor
final class InboxViewModel: ObservableObject {
    @Published var inbox: InboxData?
    @Published var error: String?
    @Published var selectedEvent: OrbitEvent?
    @Published var busy = false
    private let api = CommunityAPI()
    func load() async { busy = true; defer { busy = false }; do { inbox = try await api.inbox(); error = nil } catch { self.error = error.localizedDescription } }
    func decideTeam(_ request: JoinRequest, accept: Bool) async { do { try await api.decide(requestId: request.id, accept: accept); await load() } catch { self.error = error.localizedDescription } }
    func decideTeamInvitation(_ invitation: TeamInvitation, accept: Bool) async { do { try await api.decide(requestId: invitation.id, accept: accept); await load() } catch { self.error = error.localizedDescription } }
    func decideConnection(_ request: ConnectionRequestItem, accept: Bool) async { do { try await api.decideConnection(id: request.id, accept: accept); await load() } catch { self.error = error.localizedDescription } }
    func decideClub(_ invitation: ClubInvitation, accept: Bool) async { do { try await api.decideClubInvitation(id: invitation.id, accept: accept); await load() } catch { self.error = error.localizedDescription } }
    func read(_ notification: OrbitNotification) async { do { try await api.markNotificationRead(notification.id); await load() } catch { self.error = error.localizedDescription } }
    func saveEvent(_ event: OrbitEvent) async {
        do { try await StudentActivityAPI().save(eventId: event.id) }
        catch { self.error = error.localizedDescription }
    }
    func openEventUpdate(_ notification: OrbitNotification) async {
        do {
            if notification.readAt == nil { try await api.markNotificationRead(notification.id) }
            guard let eventId = notification.payload?.eventId else { throw URLError(.badURL) }
            selectedEvent = try await api.event(id: eventId)
            await load()
        } catch { self.error = error.localizedDescription }
    }
}

struct InboxView: View {
    @StateObject private var model = InboxViewModel()
    var body: some View {
        NavigationStack {
            List {
                if let error = model.error { Section { Text(error).foregroundStyle(.red) } }
                if let inbox = model.inbox {
                    eventConversationSection(inbox.notifications)
                    Section("Club invitations") {
                        if inbox.clubInvitations.isEmpty { Text("Club invitations will appear here.").foregroundStyle(.secondary) }
                        ForEach(inbox.clubInvitations) { invitation in
                            VStack(alignment: .leading, spacing: 7) {
                                Text(invitation.club.name).font(.headline)
                                Text("\(invitation.role.capitalized) · \(invitation.club.college.name)").font(.caption).foregroundStyle(.secondary)
                                HStack { Button("Accept") { Task { await model.decideClub(invitation, accept: true) } }; Button("Decline", role: .destructive) { Task { await model.decideClub(invitation, accept: false) } } }.font(.caption)
                            }.padding(.vertical, 3)
                        }
                    }
                    Section("Connection requests") {
                        let pending = inbox.connectionRequests.filter { $0.status == "pending" }
                        if pending.isEmpty { Text("No pending connection requests.").foregroundStyle(.secondary) }
                        ForEach(pending) { request in
                            let incoming = request.incoming
                            let person = request.person
                            VStack(alignment: .leading, spacing: 7) {
                                Text(person.studentProfile?.displayName ?? "Orbit student").font(.headline)
                                Text(incoming ? "Would like to connect with you." : "Connection request sent.").font(.caption).foregroundStyle(.secondary)
                                if incoming { HStack { Button("Accept") { Task { await model.decideConnection(request, accept: true) } }; Button("Decline", role: .destructive) { Task { await model.decideConnection(request, accept: false) } } }.font(.caption) }
                            }.padding(.vertical, 3)
                        }
                    }
                    Section("Team requests") {
                        let requests = inbox.incomingTeamRequests
                        if requests.isEmpty && inbox.outgoingTeamRequests.isEmpty && inbox.incomingTeamInvitations.isEmpty { Text("Team invitations and join request updates will show here.").foregroundStyle(.secondary) }
                        ForEach(inbox.incomingTeamInvitations) { invitation in
                            VStack(alignment: .leading, spacing: 6) {
                                Text(invitation.team.name).font(.headline)
                                Text("\(invitation.team.owner.studentProfile?.displayName ?? "Team leader") invited you for \(invitation.role.title).").font(.caption).foregroundStyle(.secondary)
                                if !invitation.message.isEmpty { Text(invitation.message).font(.caption) }
                                HStack { Button("Accept") { Task { await model.decideTeamInvitation(invitation, accept: true) } }; Button("Decline", role: .destructive) { Task { await model.decideTeamInvitation(invitation, accept: false) } } }.font(.caption)
                            }.padding(.vertical, 3)
                        }
                        ForEach(requests) { request in
                            VStack(alignment: .leading, spacing: 6) {
                                Text(request.student.studentProfile?.displayName ?? "Student").font(.headline)
                                Text("\(request.team.name) · \(request.role?.title ?? "Team member")").font(.caption).foregroundStyle(.secondary)
                                if let skills = request.student.studentProfile?.skills, !skills.isEmpty { Text("Skills: \(skills.joined(separator: " · "))").font(.caption).foregroundStyle(OrbitStyle.ink) }
                                if let bio = request.student.studentProfile?.bio, !bio.isEmpty { Text(bio).font(.caption).lineLimit(3) }
                                HStack { Button("Accept") { Task { await model.decideTeam(request, accept: true) } }; Button("Decline", role: .destructive) { Task { await model.decideTeam(request, accept: false) } } }.font(.caption)
                            }
                        }
                        ForEach(inbox.outgoingTeamRequests) { request in
                            HStack { VStack(alignment: .leading) { Text(request.team.name).font(.headline); Text("Request to join · \(request.status)").font(.caption).foregroundStyle(.secondary) }; Spacer(); Text(request.status.capitalized).font(.caption.weight(.semibold)) }
                        }
                    }
                    Section("Connections") {
                        let accepted = inbox.connectionRequests.filter { $0.status == "accepted" }
                        if accepted.isEmpty { Text("Accepted connections will appear here.").foregroundStyle(.secondary) }
                        ForEach(accepted) { request in
                            Label(request.person.studentProfile?.displayName ?? "Orbit student", systemImage: "person.crop.circle")
                        }
                    }
                    Section("Notifications") {
                        let otherNotifications = inbox.notifications.filter { !Self.eventConversationTypes.contains($0.type) }
                        if otherNotifications.isEmpty { Text("You’re all caught up.").foregroundStyle(.secondary) }
                        ForEach(otherNotifications) { notification in
                            Button { if notification.readAt == nil { Task { await model.read(notification) } } } label: {
                                HStack(alignment: .top, spacing: 10) {
                                    Circle().fill(notification.readAt == nil ? OrbitStyle.coral : .clear).frame(width: 8, height: 8).padding(.top, 5)
                                    VStack(alignment: .leading, spacing: 4) { Text(notification.title).font(.subheadline.weight(.semibold)); Text(notification.body).font(.caption).foregroundStyle(.secondary) }
                                }
                            }.buttonStyle(.plain)
                        }
                    }
                }
            }.refreshable { await model.load() }.overlay { if model.busy && model.inbox == nil { ProgressView() } }.navigationTitle("Inbox").task { await model.load() }
                .sheet(item: $model.selectedEvent) { event in
                    EventDetailView(event: event, isSaved: false) {
                        Task { await model.saveEvent(event) }
                    }
                }
        }
    }

    private static let eventConversationTypes: Set<String> = ["event_review_reply", "event_review_received", "event_thread_message"]

    @ViewBuilder
    private func eventConversationSection(_ notifications: [OrbitNotification]) -> some View {
        let updates = notifications.filter { Self.eventConversationTypes.contains($0.type) }
        if !updates.isEmpty {
            Section {
                ForEach(updates) { notification in
                    EventConversationNotificationRow(notification: notification) {
                        Task { await model.openEventUpdate(notification) }
                    }
                    .listRowInsets(EdgeInsets(top: 5, leading: 12, bottom: 5, trailing: 12))
                    .listRowBackground(Color.clear)
                }
            } header: {
                Label("Event conversations", systemImage: "sparkles")
            }
        }
    }
}

private struct EventConversationNotificationRow: View {
    let notification: OrbitNotification
    let action: () -> Void

    private var symbol: String {
        switch notification.type {
        case "event_review_reply": "bubble.left.and.text.bubble.right.fill"
        case "event_thread_message": "bubble.left.and.bubble.right.fill"
        default: "star.bubble.fill"
        }
    }

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: symbol)
                    .font(.title3)
                    .foregroundStyle(OrbitStyle.ink)
                    .frame(width: 42, height: 42)
                    .background(OrbitStyle.mint, in: RoundedRectangle(cornerRadius: 13))
                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Text(notification.title).font(.subheadline.weight(.bold)).foregroundStyle(OrbitStyle.ink)
                        if notification.readAt == nil {
                            Text("NEW")
                                .font(.system(size: 9, weight: .black))
                                .padding(.horizontal, 7).padding(.vertical, 4)
                                .background(OrbitStyle.coral.opacity(0.18), in: Capsule())
                                .foregroundStyle(OrbitStyle.coral)
                        }
                    }
                    Text(notification.body).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.leading)
                    Label("Open event conversation", systemImage: "arrow.up.right")
                        .font(.caption2.weight(.bold)).foregroundStyle(OrbitStyle.ink).padding(.top, 2)
                }
                Spacer(minLength: 0)
            }
            .padding(12).frame(maxWidth: .infinity, alignment: .leading)
            .background(OrbitStyle.card, in: RoundedRectangle(cornerRadius: 17, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}
