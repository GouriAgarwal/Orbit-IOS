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
                    Label("Event organizer", systemImage: "person.crop.circle.badge.checkmark").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    Text(event.club.organizerName ?? "Club organizer").font(.system(.title3, design: .rounded, weight: .bold)).foregroundStyle(OrbitStyle.ink)
                    Text("Hosted by \(event.club.name)").font(.subheadline.weight(.semibold)).foregroundStyle(OrbitStyle.ink.opacity(0.8))
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
                if UUID(uuidString: event.id) != nil { EventFeedbackView(event: event) }
                if UUID(uuidString: event.id) == nil { Text("This preview event is not connected to registration.").font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .center) }
            }.padding(20)
        }.background(OrbitStyle.paper.ignoresSafeArea()).navigationTitle("Event details").navigationBarTitleDisplayMode(.inline)
            .alert("Event registration", isPresented: $showingAlert) { Button("OK", role: .cancel) {} } message: { Text(alertMessage) }
            .sheet(isPresented: $showingTeamFinder) { FindTeamView() }
    }
}

private struct EventFeedbackView: View {
    @EnvironmentObject private var auth: AuthState
    let event: OrbitEvent
    @State private var reviews = [EventReview]()
    @State private var messages = [EventThreadMessage]()
    @State private var averageRating: Double?
    @State private var reviewCount = 0
    @State private var rating = 5
    @State private var reviewText = ""
    @State private var messageText = ""
    @State private var reviewMessage: String?
    @State private var threadMessage: String?
    @State private var isLoading = false
    @State private var isSending = false
    private let api = StudentActivityAPI()

    private var eventHasEnded: Bool { event.endsAt <= Date() }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Attendee reviews").font(.system(.title3, design: .rounded, weight: .bold)).foregroundStyle(OrbitStyle.ink)
                    Spacer()
                    if let averageRating { Label(String(format: "%.1f", averageRating), systemImage: "star.fill").font(.subheadline.weight(.bold)).foregroundStyle(OrbitStyle.coral) }
                }
                Text(reviewCount == 1 ? "1 review" : "\(reviewCount) reviews").font(.caption).foregroundStyle(.secondary)
                if reviews.isEmpty && !isLoading { Text("No attendee reviews yet.").font(.subheadline).foregroundStyle(.secondary) }
                ForEach(reviews) { review in
                    VStack(alignment: .leading, spacing: 7) {
                        HStack {
                            Text(review.authorName).font(.subheadline.weight(.semibold))
                            Spacer()
                            HStack(spacing: 2) { ForEach(1...5, id: \.self) { star in Image(systemName: star <= review.rating ? "star.fill" : "star").font(.system(size: 10)) } }.foregroundStyle(OrbitStyle.coral)
                        }
                        Text(review.body).font(.subheadline).fixedSize(horizontal: false, vertical: true)
                        if let reply = review.organizerReply, !reply.isEmpty {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Reply from \(event.club.name)").font(.caption.weight(.bold))
                                Text(reply).font(.caption)
                            }.padding(10).frame(maxWidth: .infinity, alignment: .leading).background(OrbitStyle.mint.opacity(0.55), in: RoundedRectangle(cornerRadius: 12))
                        }
                    }.padding(13).frame(maxWidth: .infinity, alignment: .leading).background(OrbitStyle.paper, in: RoundedRectangle(cornerRadius: 15))
                }
                if eventHasEnded {
                    Divider()
                    Text("How was it?").font(.headline)
                    HStack(spacing: 12) {
                        ForEach(1...5, id: \.self) { value in
                            Button { rating = value } label: { Image(systemName: value <= rating ? "star.fill" : "star").font(.title3).foregroundStyle(OrbitStyle.coral) }.buttonStyle(.plain).accessibilityLabel("\(value) stars")
                        }
                    }
                    TextField("Share a helpful review (5–1,500 characters)", text: $reviewText, axis: .vertical).lineLimit(3...6).padding(12).background(OrbitStyle.paper, in: RoundedRectangle(cornerRadius: 13))
                    if let reviewMessage { Text(reviewMessage).font(.caption).foregroundColor(reviewMessage.contains("posted") || reviewMessage.contains("updated") ? Color.secondary : Color.red) }
                    Button(isSending ? "Saving…" : "Post review") { Task { await submitReview() } }
                        .font(.subheadline.weight(.bold)).padding(.horizontal, 16).padding(.vertical, 11).background(OrbitStyle.ink, in: Capsule()).foregroundStyle(OrbitStyle.onInk)
                        .disabled(isSending || reviewText.trimmingCharacters(in: .whitespacesAndNewlines).count < 5)
                } else {
                    Text("Attendee reviews open after the event ends.").font(.caption).foregroundStyle(.secondary)
                }
            }.padding(16).background(OrbitStyle.card, in: RoundedRectangle(cornerRadius: 19, style: .continuous))

            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label("Event thread", systemImage: "bubble.left.and.bubble.right.fill").font(.system(.title3, design: .rounded, weight: .bold)).foregroundStyle(OrbitStyle.ink)
                    Spacer()
                    Button { Task { await loadThread() } } label: { Image(systemName: "arrow.clockwise") }.accessibilityLabel("Refresh event thread")
                }
                if let threadMessage {
                    Text(threadMessage).font(.caption).foregroundStyle(.secondary)
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 8) {
                            if messages.isEmpty { Text("Start a conversation with the event attendees and club organizers.").font(.caption).foregroundStyle(.secondary).padding(.vertical, 12) }
                            ForEach(messages) { message in
                                let isOwn = message.senderName == auth.displayName
                                VStack(alignment: isOwn ? .trailing : .leading, spacing: 3) {
                                    Text(isOwn ? "You" : message.senderName).font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                                    Text(message.body).font(.subheadline).padding(10).background(isOwn ? OrbitStyle.mint : OrbitStyle.paper, in: RoundedRectangle(cornerRadius: 13))
                                }.frame(maxWidth: .infinity, alignment: isOwn ? .trailing : .leading)
                            }
                        }
                    }.frame(maxHeight: 220)
                    HStack(spacing: 8) {
                        TextField("Message event attendees…", text: $messageText, axis: .vertical).lineLimit(1...3).padding(11).background(OrbitStyle.paper, in: RoundedRectangle(cornerRadius: 13))
                        Button { Task { await sendMessage() } } label: { Image(systemName: "arrow.up.circle.fill").font(.system(size: 30)).foregroundStyle(OrbitStyle.ink) }
                            .disabled(isSending || messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty).accessibilityLabel("Send message")
                    }
                }
            }.padding(16).background(OrbitStyle.card, in: RoundedRectangle(cornerRadius: 19, style: .continuous))
        }
        .task { await load() }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let page = try await api.reviews(eventId: event.id)
            reviews = page.data
            averageRating = page.averageRating
            reviewCount = page.reviewCount
        } catch { reviewMessage = error.localizedDescription }
        await loadThread()
    }

    private func loadThread() async {
        do { messages = try await api.eventMessages(eventId: event.id); threadMessage = nil }
        catch { messages = []; threadMessage = error.localizedDescription }
    }

    private func submitReview() async {
        isSending = true
        defer { isSending = false }
        do {
            try await api.submitReview(eventId: event.id, rating: rating, body: reviewText)
            reviewText = ""
            reviewMessage = "Your review was posted."
            let page = try await api.reviews(eventId: event.id)
            reviews = page.data; averageRating = page.averageRating; reviewCount = page.reviewCount
        } catch { reviewMessage = error.localizedDescription }
    }

    private func sendMessage() async {
        let text = messageText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        isSending = true
        defer { isSending = false }
        do { try await api.postEventMessage(eventId: event.id, body: text); messageText = ""; await loadThread() }
        catch { threadMessage = error.localizedDescription }
    }
}
