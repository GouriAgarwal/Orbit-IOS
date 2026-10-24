import SwiftUI

struct DiscoverView: View {
    @EnvironmentObject private var auth: AuthState
    @StateObject private var model = DiscoverViewModel()
    @State private var selectedEvent: OrbitEvent?
    @State private var savedIDs: Set<String> = []
    @State private var saveError: String?
    private let activityAPI = StudentActivityAPI()
    private let categories = ["All", "Hackathon", "Workshop", "Technology"]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    header
                    if let saveError { Text(saveError).font(.caption).foregroundStyle(.red) }
                    searchField
                    scopePicker
                    categoryPicker
                    sectionHeader
                    if model.isLoading && model.events.isEmpty { ProgressView().frame(maxWidth: .infinity).padding(.top, 28) }
                    else if let message = model.errorMessage, model.events.isEmpty { emptyState(message, action: "Try again") { Task { await model.load() } } }
                    else if model.events.isEmpty { emptyState("No events match those filters yet.", action: "Clear filters") { model.category = nil; model.search = ""; Task { await model.load() } } }
                    else { eventList }
                }.padding(.horizontal, 20).padding(.top, 14).padding(.bottom, 28)
            }
            .background(OrbitStyle.paper.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .refreshable { await model.load() }
            .task { model.interests = auth.interests; await model.load(); await loadSavedEvents() }
            .onChange(of: model.scope) { Task { await model.load() } }
            .onChange(of: model.category) { Task { await model.load() } }
            .onChange(of: model.search) { Task { await model.load() } }
            .navigationDestination(isPresented: Binding(
                get: { selectedEvent != nil },
                set: { if !$0 { selectedEvent = nil } }
            )) {
                if let event = selectedEvent {
                    EventDetailView(event: event, isSaved: savedIDs.contains(event.id)) { toggleSaved(event) }
                } else {
                    EmptyView()
                }
            }
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 5) {
                Text("FRIDAY, CAMPUS LIFE").font(.system(size: 10, weight: .bold, design: .rounded)).tracking(1.7).foregroundStyle(OrbitStyle.coral)
                Text("Find your\nnext thing.").font(.system(size: 35, weight: .bold, design: .rounded)).tracking(-1.2).lineSpacing(-5).foregroundStyle(OrbitStyle.ink)
            }
            Spacer()
            Text("O").font(.system(size: 24, weight: .black, design: .rounded)).foregroundStyle(OrbitStyle.onInk).frame(width: 48, height: 48).background(OrbitStyle.ink, in: Circle())
                .accessibilityLabel("Orbit")
        }
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").foregroundStyle(OrbitStyle.ink.opacity(0.6))
            TextField("Try “hackathon” or “design”", text: $model.search).font(.system(.subheadline, design: .rounded))
            if !model.search.isEmpty { Button { model.search = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }.accessibilityLabel("Clear search") }
        }.padding(15).background(OrbitStyle.card, in: RoundedRectangle(cornerRadius: 16)).overlay(RoundedRectangle(cornerRadius: 16).stroke(OrbitStyle.ink.opacity(0.07)))
    }

    private var scopePicker: some View {
        HStack(spacing: 4) {
            ForEach(CampusScope.allCases) { scope in
                Button { model.scope = scope } label: {
                    Text(scope.title).font(.system(.subheadline, design: .rounded, weight: .semibold)).foregroundStyle(model.scope == scope ? OrbitStyle.onInk : OrbitStyle.ink.opacity(0.68))
                        .frame(maxWidth: .infinity).padding(.vertical, 12).background { if model.scope == scope { Capsule().fill(OrbitStyle.ink) } }
                }.buttonStyle(.plain)
            }
        }.padding(4).background(OrbitStyle.ink.opacity(0.06), in: Capsule())
    }

    private var categoryPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(categories, id: \.self) { category in
                    let selected = category == (model.category ?? "All")
                    Button { model.category = category == "All" ? nil : category } label: {
                        Text(category).font(.system(.caption, design: .rounded, weight: .semibold)).padding(.horizontal, 14).padding(.vertical, 9)
                            .foregroundStyle(selected ? OrbitStyle.ink : OrbitStyle.ink.opacity(0.7))
                            .background(selected ? OrbitStyle.yellow : OrbitStyle.card, in: Capsule())
                    }.buttonStyle(.plain)
                }
            }
        }.contentMargins(.trailing, 4)
    }

    private var sectionHeader: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(auth.interests.isEmpty ? "Happening soon" : "Picked for you").font(.system(.title3, design: .rounded, weight: .bold)).foregroundStyle(OrbitStyle.ink)
            Spacer()
            Text(auth.interests.isEmpty ? "\(model.events.count) EVENTS" : "BASED ON YOUR INTERESTS").font(.system(size: 9, weight: .bold, design: .rounded)).tracking(1).foregroundStyle(OrbitStyle.ink.opacity(0.5))
        }.padding(.top, 2)
    }

    private var eventList: some View {
        LazyVStack(spacing: 14) {
            ForEach(Array(model.events.enumerated()), id: \.element.id) { index, event in
                Button { selectedEvent = event } label: { EventCardView(event: event, styleIndex: index, isSaved: savedIDs.contains(event.id)) }
                    .buttonStyle(.plain).accessibilityHint("Opens event details")
            }
        }
    }

    private func emptyState(_ message: String, action: String, onTap: @escaping () -> Void) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "sparkles.rectangle.stack").font(.system(size: 32)).foregroundStyle(OrbitStyle.coral)
            Text(message).font(.system(.subheadline, design: .rounded)).foregroundStyle(.secondary).multilineTextAlignment(.center)
            Button(action, action: onTap).font(.system(.subheadline, design: .rounded, weight: .bold)).foregroundStyle(OrbitStyle.ink)
        }.frame(maxWidth: .infinity).padding(30).background(OrbitStyle.card, in: RoundedRectangle(cornerRadius: 20))
    }

    private func loadSavedEvents() async {
        do { savedIDs = Set(try await activityAPI.savedEvents().map { $0.event.id }); saveError = nil }
        catch { saveError = error.localizedDescription }
    }
    private func toggleSaved(_ event: OrbitEvent) {
        Task {
            do {
                if savedIDs.contains(event.id) { try await activityAPI.unsave(eventId: event.id); savedIDs.remove(event.id) }
                else { try await activityAPI.save(eventId: event.id); savedIDs.insert(event.id) }
                saveError = nil
            } catch { saveError = error.localizedDescription }
        }
    }
}

private struct EventCardView: View {
    let event: OrbitEvent
    let styleIndex: Int
    let isSaved: Bool
    private var accent: Color { [OrbitStyle.coral, OrbitStyle.mint, OrbitStyle.yellow][styleIndex % 3] }
    private var posterImageURL: URL? {
        guard let raw = event.posterUrl else { return nil }
        if let absolute = URL(string: raw), absolute.scheme != nil { return absolute }
        let apiBase = URL(string: ProcessInfo.processInfo.environment["ORBIT_API_BASE_URL"] ?? "http://localhost:3000/api/v1")!
        return URL(string: raw, relativeTo: apiBase)?.absoluteURL
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .topLeading) {
                if let posterImageURL {
                    AsyncImage(url: posterImageURL) { phase in
                        if let image = phase.image { image.resizable().scaledToFill() }
                        else { Rectangle().fill(accent) }
                    }.frame(maxWidth: .infinity).frame(height: 184).clipped()
                    LinearGradient(colors: [.clear, .black.opacity(0.55)], startPoint: .center, endPoint: .bottom)
                } else {
                    Rectangle().fill(accent)
                    Circle().fill(.white.opacity(0.18)).frame(width: 170).offset(x: 205, y: -72)
                }
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 5) { Image(systemName: event.format == "online" ? "video" : "mappin.and.ellipse"); Text(event.locationLabel) }
                        .font(.system(.caption, design: .rounded, weight: .semibold)).padding(.horizontal, 10).padding(.vertical, 7).background(.white.opacity(0.88), in: Capsule())
                    Spacer(minLength: 10)
                    Text(event.category.uppercased()).font(.system(size: 9, weight: .black, design: .rounded)).tracking(1.3)
                    Text(event.title).font(.title2.bold()).tracking(-0.5).lineLimit(2).fixedSize(horizontal: false, vertical: true)
                }.foregroundColor(posterImageURL == nil ? OrbitStyle.ink : Color.white).padding(16).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                Image(systemName: isSaved ? "bookmark.fill" : "bookmark").font(.system(size: 13, weight: .semibold)).foregroundStyle(OrbitStyle.ink).padding(10).background(.white.opacity(0.88), in: Circle()).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing).padding(14)
            }.frame(height: 184)
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(event.club.name).font(.system(.subheadline, design: .rounded, weight: .bold)).foregroundStyle(.primary)
                    Text("\(event.dateLabel) · \(event.timeLabel)  /  \(event.club.college)").font(.system(size: 11, weight: .medium, design: .rounded)).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 4)
                Image(systemName: "arrow.up.right").font(.system(size: 13, weight: .bold)).foregroundStyle(Color(uiColor: .systemBackground)).frame(width: 34, height: 34).background(Color.primary, in: Circle())
            }.padding(15).background(.ultraThinMaterial)
        }.clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(Color.primary.opacity(0.06)))
            .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 4)
    }
}
