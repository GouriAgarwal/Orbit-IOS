import SwiftUI

@MainActor
final class MyEventsViewModel: ObservableObject {
    @Published var registrations: [StudentRegistration] = []
    @Published var savedEvents: [SavedEventItem] = []
    @Published var error: String?
    @Published var busy = false
    private let api = StudentActivityAPI()
    func load() async {
        guard !busy else { return }
        busy = true; defer { busy = false }
        do {
            // Each authenticated request rotates the single-use refresh token.
            // Run these sequentially so the two loads cannot invalidate each other.
            registrations = try await api.myEvents()
            savedEvents = try await api.savedEvents()
            error = nil
        }
        catch { self.error = error.localizedDescription }
    }
    func cancel(_ registration: StudentRegistration) async {
        do { try await api.cancel(eventId: registration.event.id); await load() }
        catch { self.error = error.localizedDescription }
    }
    func unsave(_ saved: SavedEventItem) async { do { try await api.unsave(eventId: saved.event.id); await load() } catch { self.error = error.localizedDescription } }
}

struct MyEventsView: View {
    @StateObject private var model = MyEventsViewModel()
    var body: some View {
        NavigationStack {
            List {
                if let error = model.error { Section { Text(error).foregroundStyle(.red) } }
                if model.registrations.isEmpty && model.savedEvents.isEmpty && !model.busy {
                    ContentUnavailableView("No events yet", systemImage: "calendar", description: Text("Events you register for will appear here."))
                        .listRowBackground(Color.clear)
                }
                Section("Saved") {
                    if model.savedEvents.isEmpty { Text("Events you save will appear here.").foregroundStyle(.secondary) }
                    ForEach(model.savedEvents) { saved in
                        HStack {
                            NavigationLink {
                                EventDetailView(event: saved.event, isSaved: true) { Task { await model.unsave(saved) } }
                            } label: {
                                VStack(alignment: .leading, spacing: 4) { Text(saved.event.title).font(.headline); Text("\(saved.event.dateLabel) · \(saved.event.club.name)").font(.caption).foregroundStyle(.secondary) }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            Spacer()
                            Button { Task { await model.unsave(saved) } } label: { Image(systemName: "bookmark.fill") }.accessibilityLabel("Remove saved event")
                        }
                    }
                }
                Section("Upcoming") {
                    let upcoming = model.registrations.filter { $0.event.endsAt >= Date() }
                    if upcoming.isEmpty { Text("No upcoming registrations.").foregroundStyle(.secondary) }
                    ForEach(upcoming) { registration in registrationRow(registration) }
                }
                Section("Past") {
                    let past = model.registrations.filter { $0.event.endsAt < Date() }
                    if past.isEmpty { Text("Past events will appear here after they finish.").foregroundStyle(.secondary) }
                    ForEach(past) { registration in registrationRow(registration) }
                }
            }.refreshable { await model.load() }.overlay { if model.busy && model.registrations.isEmpty && model.savedEvents.isEmpty { ProgressView() } }.navigationTitle("My Events").onAppear { Task { await model.load() } }
        }
    }

    @ViewBuilder private func registrationRow(_ registration: StudentRegistration) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(registration.event.title).font(.headline)
            Text("\(registration.event.dateLabel) · \(registration.event.timeLabel) · \(registration.event.club.name)").font(.caption).foregroundStyle(.secondary)
            HStack {
                Text(registration.status.capitalized).font(.caption.weight(.semibold)).foregroundStyle(registration.status == "waitlisted" ? OrbitStyle.coral : OrbitStyle.ink)
                Spacer()
                if registration.event.endsAt >= Date() && (registration.status == "registered" || registration.status == "waitlisted") {
                    Button("Cancel", role: .destructive) { Task { await model.cancel(registration) } }.font(.caption)
                }
            }
        }.padding(.vertical, 5)
    }
}
