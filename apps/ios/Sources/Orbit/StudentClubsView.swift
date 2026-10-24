import SwiftUI

@MainActor
private final class StudentClubsModel: ObservableObject {
    @Published var clubs: [OrganizerClub] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            clubs = try await OrganizerAPI().clubs()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct StudentClubsView: View {
    @StateObject private var model = StudentClubsModel()
    @State private var selectedClub: OrganizerClub?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("YOUR CAMPUS COMMUNITY").font(.system(size: 10, weight: .bold, design: .rounded)).tracking(1.6).foregroundStyle(OrbitStyle.coral)
                        Text("Clubs you’re part of").font(.system(.largeTitle, design: .rounded, weight: .bold)).tracking(-1).foregroundStyle(OrbitStyle.ink)
                        Text("Meet the campus groups behind your events.").font(.subheadline).foregroundStyle(.secondary)
                    }
                    if model.isLoading && model.clubs.isEmpty {
                        ProgressView().frame(maxWidth: .infinity).padding(.vertical, 40)
                    } else if let error = model.errorMessage, model.clubs.isEmpty {
                        stateCard(title: "Couldn’t load clubs", detail: error, action: "Try again") { Task { await model.load() } }
                    } else if model.clubs.isEmpty {
                        stateCard(title: "No clubs yet", detail: "Clubs you organize or join will appear here with their campus details and events.", action: "Refresh") { Task { await model.load() } }
                    } else {
                        VStack(spacing: 12) {
                            ForEach(model.clubs) { club in
                                Button { selectedClub = club } label: { clubCard(club) }
                                    .buttonStyle(.plain)
                            }
                        }
                    }
                }.padding(.horizontal, 20).padding(.top, 18).padding(.bottom, 28)
            }
            .background(OrbitStyle.paper.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .navigationBar)
            .refreshable { await model.load() }
            .task { if model.clubs.isEmpty { await model.load() } }
            .sheet(item: $selectedClub) { club in StudentClubDetailView(club: club) }
        }
    }

    private func clubCard(_ club: OrganizerClub) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "person.3.fill").font(.system(size: 18, weight: .semibold)).foregroundStyle(OrbitStyle.ink).frame(width: 46, height: 46).background(OrbitStyle.mint, in: RoundedRectangle(cornerRadius: 14))
                VStack(alignment: .leading, spacing: 4) {
                    Text(club.name).font(.system(.title3, design: .rounded, weight: .bold)).foregroundStyle(OrbitStyle.ink)
                    Text(club.college.name + (club.college.city.map { " · \($0)" } ?? "")).font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "arrow.up.right").font(.system(size: 13, weight: .bold)).foregroundStyle(OrbitStyle.ink)
            }
            Text(club.description.isEmpty ? "A campus community hosting events and bringing students together." : club.description)
                .font(.system(.subheadline, design: .rounded)).foregroundStyle(OrbitStyle.ink.opacity(0.76)).lineLimit(3).multilineTextAlignment(.leading)
            HStack(spacing: 7) {
                Circle().fill(club.verificationStatus == "approved" ? Color.green : OrbitStyle.yellow).frame(width: 7, height: 7)
                Text(club.verificationStatus == "approved" ? "Verified club" : "Club profile")
                Spacer()
                if let role = club.currentRole { Text(role.capitalized).foregroundStyle(.secondary) }
            }.font(.system(.caption, design: .rounded, weight: .semibold)).foregroundStyle(OrbitStyle.ink)
        }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(Color.primary.opacity(0.06)))
            .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 4)
    }

    private func stateCard(title: String, detail: String, action: String, onTap: @escaping () -> Void) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "person.3").font(.system(size: 30)).foregroundStyle(OrbitStyle.coral)
            Text(title).font(.system(.title3, design: .rounded, weight: .bold)).foregroundStyle(OrbitStyle.ink)
            Text(detail).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
            Button(action, action: onTap).font(.subheadline.weight(.bold)).padding(.horizontal, 18).padding(.vertical, 10).background(OrbitStyle.mint, in: Capsule()).foregroundStyle(OrbitStyle.ink)
        }.frame(maxWidth: .infinity).padding(24).background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
    }
}

private struct StudentClubDetailView: View {
    let club: OrganizerClub
    @Environment(\.dismiss) private var dismiss
    @State private var events: [OrbitEvent] = []
    @State private var savedEventIDs: Set<String> = []
    @State private var isLoadingEvents = false
    @State private var eventError: String?

    private var upcomingEvents: [OrbitEvent] { events.filter { $0.club.id == club.id && $0.startsAt >= Date() } }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    ZStack(alignment: .bottomLeading) {
                        OrbitStyle.mint
                        Circle().fill(OrbitStyle.yellow).frame(width: 150).offset(x: 245, y: -95)
                        VStack(alignment: .leading, spacing: 10) {
                            Image(systemName: "person.3.fill").font(.system(size: 22)).padding(12).background(.white.opacity(0.75), in: Circle())
                            Text(club.name).font(.system(size: 30, weight: .bold, design: .rounded)).tracking(-0.7).lineLimit(3)
                            Text(club.college.name.uppercased()).font(.system(size: 10, weight: .black, design: .rounded)).tracking(1.4)
                        }.foregroundStyle(OrbitStyle.ink).padding(22)
                    }.frame(height: 220).clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                    VStack(alignment: .leading, spacing: 12) {
                        Label(club.college.city ?? "Campus community", systemImage: "mappin.and.ellipse").font(.system(.subheadline, design: .rounded, weight: .semibold)).foregroundStyle(OrbitStyle.ink)
                        HStack(spacing: 8) {
                            Image(systemName: club.verificationStatus == "approved" ? "checkmark.seal.fill" : "person.3.fill").foregroundStyle(club.verificationStatus == "approved" ? .green : OrbitStyle.coral)
                            Text(club.verificationStatus == "approved" ? "Verified club" : "Campus club").font(.system(.subheadline, design: .rounded, weight: .semibold)).foregroundStyle(OrbitStyle.ink)
                            Spacer()
                            if let role = club.currentRole { Text("Your role · \(role.capitalized)").font(.caption.weight(.semibold)).foregroundStyle(.secondary) }
                        }
                    }.padding(16).frame(maxWidth: .infinity, alignment: .leading).background(OrbitStyle.card, in: RoundedRectangle(cornerRadius: 18))
                    VStack(alignment: .leading, spacing: 8) {
                        Text("About the club").font(.system(.title3, design: .rounded, weight: .bold)).foregroundStyle(OrbitStyle.ink)
                        Text(club.description.isEmpty ? "This club brings students together through campus events and shared interests." : club.description).font(.system(.body, design: .rounded)).foregroundStyle(OrbitStyle.ink.opacity(0.78)).lineSpacing(4)
                    }
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Upcoming events").font(.system(.title3, design: .rounded, weight: .bold)).foregroundStyle(OrbitStyle.ink)
                            Spacer()
                            if isLoadingEvents { ProgressView().controlSize(.small) }
                        }
                        if let eventError { Text(eventError).font(.caption).foregroundStyle(.secondary) }
                        else if !isLoadingEvents && upcomingEvents.isEmpty { Text("No upcoming published events from this club yet.").font(.subheadline).foregroundStyle(.secondary) }
                        ForEach(upcomingEvents) { event in
                            NavigationLink { EventDetailView(event: event, isSaved: savedEventIDs.contains(event.id)) { toggleSaved(event) } } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: "calendar").foregroundStyle(OrbitStyle.ink).frame(width: 40, height: 40).background(OrbitStyle.mint, in: RoundedRectangle(cornerRadius: 12))
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(event.title).font(.system(.subheadline, design: .rounded, weight: .bold)).foregroundStyle(OrbitStyle.ink)
                                        Text("\(event.dateLabel) · \(event.timeLabel) · \(event.category)").font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(.secondary)
                                }.padding(12).background(OrbitStyle.card, in: RoundedRectangle(cornerRadius: 15))
                            }.buttonStyle(.plain)
                        }
                    }
                }.padding(20)
            }.background(OrbitStyle.paper.ignoresSafeArea()).navigationTitle("Club details").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
                .task { await loadEvents() }
        }
    }

    private func loadEvents() async {
        isLoadingEvents = true
        defer { isLoadingEvents = false }
        do { events = try await APIEventsRepository().events(scope: .allCampuses, category: nil, search: nil); eventError = nil }
        catch { eventError = "Couldn’t load this club’s events right now." }
    }

    private func toggleSaved(_ event: OrbitEvent) {
        Task {
            do {
                let api = StudentActivityAPI()
                if savedEventIDs.contains(event.id) {
                    try await api.unsave(eventId: event.id)
                    savedEventIDs.remove(event.id)
                } else {
                    try await api.save(eventId: event.id)
                    savedEventIDs.insert(event.id)
                }
            } catch {
                eventError = error.localizedDescription
            }
        }
    }
}
