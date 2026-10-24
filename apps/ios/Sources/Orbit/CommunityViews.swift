import SwiftUI

@MainActor
final class ProfileEditorViewModel: ObservableObject {
    @Published var profile: StudentProfileData?
    @Published var error: String?
    @Published var saving = false
    @Published var colleges: [StudentCollege] = []
    private let api = CommunityAPI()
    func load() async { do { async let profileLoad = api.profile(); async let collegeLoad = api.colleges(); profile = try await profileLoad; colleges = try await collegeLoad; error = nil } catch { self.error = error.localizedDescription } }
    func save(name: String, course: String, year: String, bio: String, skills: String, interests: String, portfolio: String, achievements: String, visibility: String, collegeId: String) async {
        saving = true; defer { saving = false }
        do {
            profile = try await api.updateProfile([
                "displayName": name, "course": course, "year": Int(year) as Any? ?? NSNull(), "bio": bio,
                "skills": skills.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) },
                "interests": interests.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) },
                "portfolioUrl": portfolio, "achievements": achievements.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) },
                "visibility": visibility, "collegeId": collegeId,
            ]); error = "Profile saved."
        } catch { self.error = error.localizedDescription }
    }
    func addProject(title: String, description: String, url: String) async {
        do { _ = try await api.addProject(title: title, description: description, url: url); await load(); error = "Project added." }
        catch { self.error = error.localizedDescription }
    }
    func deleteProject(_ project: StudentProject) async { do { try await api.deleteProject(id: project.id); await load(); error = "Project removed." } catch { self.error = error.localizedDescription } }
    func updateProject(_ project: StudentProject, title: String, description: String, url: String) async { do { try await api.updateProject(id: project.id, title: title, description: description, url: url); await load(); error = "Project updated." } catch { self.error = error.localizedDescription } }
}

struct StudentProfileView: View {
    @EnvironmentObject private var auth: AuthState
    @StateObject private var model = ProfileEditorViewModel()
    @State private var name = ""; @State private var course = ""; @State private var year = ""; @State private var bio = ""
    @State private var skills = ""; @State private var interests = ""
    @State private var portfolio = ""; @State private var achievements = ""; @State private var visibility = "campus"; @State private var collegeId = ""
    @State private var showProjectForm = false
    @State private var editingProject: StudentProject?
    var body: some View {
        NavigationStack {
            Form {
                Section("Appearance") {
                    OrbitAppearancePicker()
                    Text("System follows your iPhone setting. Choose Light or Dark to override it across Orbit.").font(.caption).foregroundStyle(.secondary)
                }
                Section("About you") {
                    TextField("Display name", text: $name)
                    TextField("Course or major", text: $course)
                    TextField("Year of study", text: $year).keyboardType(.numberPad)
                    TextField("A short bio", text: $bio, axis: .vertical).lineLimit(2...5)
                }
                Section("Skills and interests") {
                    TextField("Skills, comma separated", text: $skills, axis: .vertical).lineLimit(2...4)
                    TextField("Interests, comma separated", text: $interests, axis: .vertical).lineLimit(2...4)
                }
                Section("College and portfolio") {
                    Picker("College", selection: $collegeId) {
                        Text("Not selected").tag("")
                        ForEach(model.colleges) { college in Text(college.name).tag(college.id) }
                    }
                    TextField("Portfolio URL", text: $portfolio).keyboardType(.URL).textInputAutocapitalization(.never)
                    TextField("Achievements, comma separated", text: $achievements, axis: .vertical).lineLimit(2...4)
                    Picker("Profile visibility", selection: $visibility) {
                        Text("My campus").tag("campus"); Text("Public").tag("public"); Text("Private").tag("private")
                    }
                }
                Section("Projects") {
                    if let projects = model.profile?.projects, !projects.isEmpty {
                        ForEach(projects) { project in
                            VStack(alignment: .leading, spacing: 5) { Text(project.title).font(.headline); Text(project.description).font(.caption).foregroundStyle(.secondary); if let url = project.url, !url.isEmpty, let link = URL(string: url) { Link("Open project", destination: link).font(.caption) } }
                                .swipeActions { Button("Delete", role: .destructive) { Task { await model.deleteProject(project) } } }
                                .contextMenu { Button("Edit project", systemImage: "pencil") { editingProject = project }; Button("Delete project", systemImage: "trash", role: .destructive) { Task { await model.deleteProject(project) } } }
                        }
                    } else { Text("Add a project to show what you are working on.").font(.subheadline).foregroundStyle(.secondary) }
                    Button("Add project") { showProjectForm = true }
                }
                Section {
                    Button(model.saving ? "Saving…" : "Save profile") {
                        Task { await model.save(name: name, course: course, year: year, bio: bio, skills: skills, interests: interests, portfolio: portfolio, achievements: achievements, visibility: visibility, collegeId: collegeId); if let profile = model.profile { auth.displayName = profile.displayName } }
                    }.disabled(model.saving || name.trimmingCharacters(in: .whitespaces).isEmpty)
                    if let error = model.error {
                        Text(error).font(.footnote).foregroundColor(error.contains("saved") || error.contains("added") ? Color.secondary : Color.red)
                    }
                    Button("Switch to Organizer mode") { auth.organizerMode = true }
                    Button("Sign out", role: .destructive) { auth.signOut() }
                }
            }.navigationTitle("Profile").task {
                await model.load()
                if let profile = model.profile {
                    name = profile.displayName; course = profile.course ?? ""; year = profile.year.map(String.init) ?? ""
                    bio = profile.bio; skills = profile.skills.joined(separator: ", "); interests = profile.interests.joined(separator: ", ")
                    portfolio = profile.portfolioUrl ?? ""; achievements = (profile.achievements ?? []).joined(separator: ", "); visibility = profile.visibility ?? "campus"; collegeId = profile.college?.id ?? ""
                } else { name = auth.displayName }
            }.sheet(isPresented: $showProjectForm) { AddProjectSheet { title, description, url in Task { await model.addProject(title: title, description: description, url: url) } } }
                .sheet(item: $editingProject) { project in EditProjectSheet(project: project) { title, description, url in Task { await model.updateProject(project, title: title, description: description, url: url) } } }
        }
    }
}

private struct EditProjectSheet: View {
    @Environment(\.dismiss) private var dismiss
    let project: StudentProject
    let save: (String, String, String) -> Void
    @State private var title: String
    @State private var description: String
    @State private var url: String
    init(project: StudentProject, save: @escaping (String, String, String) -> Void) {
        self.project = project; self.save = save
        _title = State(initialValue: project.title); _description = State(initialValue: project.description); _url = State(initialValue: project.url ?? "")
    }
    var body: some View {
        NavigationStack {
            Form { TextField("Project name", text: $title); TextField("Description", text: $description, axis: .vertical).lineLimit(3...5); TextField("Link (optional)", text: $url).keyboardType(.URL).textInputAutocapitalization(.never) }
                .navigationTitle("Edit project").toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) { Button("Save") { save(title, description, url); dismiss() }.disabled(title.isEmpty) }
                }
        }
    }
}

private struct AddProjectSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""; @State private var description = ""; @State private var url = ""
    let save: (String, String, String) -> Void
    var body: some View {
        NavigationStack {
            Form {
                TextField("Project name", text: $title)
                TextField("Description", text: $description, axis: .vertical).lineLimit(3...5)
                TextField("Link (optional)", text: $url).keyboardType(.URL).textInputAutocapitalization(.never)
            }.navigationTitle("Add project").toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { save(title, description, url); dismiss() }.disabled(title.isEmpty) }
            }
        }
    }
}

@MainActor
final class TeamsViewModel: ObservableObject {
    @Published var teams: [CommunityTeam] = []
    @Published var requests: [JoinRequest] = []
    @Published var events: [TeamEventOption] = []
    @Published var profileSkills: [String] = []
    @Published var search = ""
    @Published var selectedEventId = ""
    @Published var matchSkillsOnly = false
    @Published var message: String?
    @Published var busy = false
    private let api = CommunityAPI()
    func load() async {
        guard !busy else { return }
        busy = true; defer { busy = false }
        do {
            events = try await api.teamEvents().filter { !($0.minStudentsPerTeam == 1 && $0.maxStudentsPerTeam == 1) }
            profileSkills = try await api.profile().skills
            teams = try await api.teams(search: search, eventId: selectedEventId.isEmpty ? nil : selectedEventId, matchSkills: matchSkillsOnly)
            requests = try await api.requests()
            message = nil
        } catch { message = error.localizedDescription }
    }
    func join(_ team: CommunityTeam, role: TeamRole) async -> Bool {
        do {
            try await api.requestJoin(teamId: team.id, roleId: role.id, message: "I'd like to join as \(role.title).")
            await load(); message = "Request sent to \(team.owner) for the \(role.title) role."
            return true
        } catch { message = error.localizedDescription; return false }
    }
    func decide(_ request: JoinRequest, accept: Bool) async { do { try await api.decide(requestId: request.id, accept: accept); await load() } catch { message = error.localizedDescription } }
    func block(_ team: CommunityTeam) async { do { try await api.block(userId: team.ownerId); await load(); message = "Organizer blocked. Their teams are hidden from Find Team." } catch { message = error.localizedDescription } }
    func report(_ team: CommunityTeam) async { do { try await api.reportTeam(teamId: team.id); message = "Report submitted for review." } catch { message = error.localizedDescription } }
    func connect(_ team: CommunityTeam) async { do { try await api.requestConnection(userId: team.ownerId); message = "Connection request sent to \(team.owner)." } catch { message = error.localizedDescription } }
    func create(eventId: String, name: String, goal: String, details: String, roles: [TeamRoleDraft], limit: Int) async {
        do {
            let roleValues = roles.map { role in
                ["title": role.title, "description": role.description, "requiredSkills": role.skills.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }, "openings": role.openings] as [String: Any]
            }
            try await api.createTeam(eventId: eventId, name: name, goal: goal, description: details, roles: roleValues, maxMembers: limit)
            await load(); message = "Team created. You are the team leader, and your roles are open for applications."
        } catch { message = error.localizedDescription }
    }
}

struct TeamRoleDraft: Identifiable {
    let id = UUID()
    var title = ""
    var description = ""
    var skills = ""
    var openings = 1
}

struct FindTeamView: View {
    @StateObject private var model = TeamsViewModel()
    @State private var showCreate = false
    @State private var selectedTeam: CommunityTeam?
    var body: some View {
        NavigationStack {
            List {
                if let message = model.message { Section { Text(message).font(.footnote).foregroundColor(message.contains("created") || message.contains("sent") ? .secondary : .red) } }
                Section("Find a team") {
                    Picker("Event", selection: $model.selectedEventId) {
                        Text("All events").tag("")
                        ForEach(model.events) { event in Text(event.title).tag(event.id) }
                    }
                    Toggle("Match my skills", isOn: $model.matchSkillsOnly).disabled(model.profileSkills.isEmpty)
                    if model.matchSkillsOnly && !model.profileSkills.isEmpty {
                        Text("Matching your profile: \(model.profileSkills.joined(separator: " · "))").font(.caption).foregroundStyle(.secondary)
                    }
                    if model.events.isEmpty { Text("No upcoming published events are available for team listings yet.").font(.caption).foregroundStyle(.secondary) }
                }
                if !model.requests.isEmpty {
                    Section("Applicants for your teams") {
                        ForEach(model.requests.filter { $0.status == "pending" }) { request in
                            VStack(alignment: .leading, spacing: 5) {
                                Text(request.student.studentProfile?.displayName ?? "Student").font(.headline)
                                Text("\(request.team.name) · \(request.role?.title ?? "Team member")").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                                if let profile = request.student.studentProfile {
                                    if let course = profile.course { Text([course, profile.year.map { "Year \($0)" }].compactMap { $0 }.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary) }
                                    if let bio = profile.bio, !bio.isEmpty { Text(bio).font(.caption).lineLimit(3) }
                                    if let skills = profile.skills, !skills.isEmpty { Text("Skills: \(skills.joined(separator: " · "))").font(.caption).foregroundStyle(OrbitStyle.ink) }
                                    if let interests = profile.interests, !interests.isEmpty { Text("Interests: \(interests.joined(separator: " · "))").font(.caption).foregroundStyle(.secondary) }
                                    if let portfolio = profile.portfolioUrl, let url = URL(string: portfolio) { Link("Open portfolio", destination: url).font(.caption) }
                                    ForEach(profile.projects ?? []) { project in
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(project.title).font(.caption.weight(.semibold))
                                            if !project.description.isEmpty { Text(project.description).font(.caption).foregroundStyle(.secondary).lineLimit(2) }
                                            if let raw = project.url, let url = URL(string: raw) { Link("View project", destination: url).font(.caption) }
                                        }
                                    }
                                }
                                HStack { Button("Accept") { Task { await model.decide(request, accept: true) } }; Button("Decline", role: .destructive) { Task { await model.decide(request, accept: false) } } }.font(.caption)
                            }.padding(.vertical, 3)
                        }
                    }
                }
                let ownTeams = model.teams.filter(\.isOwner)
                let otherTeams = model.teams.filter { !$0.isOwner }
                if !ownTeams.isEmpty {
                    Section("Your teams · leader") { ForEach(ownTeams) { team in teamRow(team) } }
                }
                Section("Open team roles") {
                    if otherTeams.isEmpty { Text(model.busy ? "Loading teams…" : "No open roles match those filters yet.").foregroundStyle(.secondary) }
                    ForEach(otherTeams) { team in teamRow(team) }
                }
            }.searchable(text: $model.search).onSubmit(of: .search) { Task { await model.load() } }.refreshable { await model.load() }.navigationTitle("Find Team")
                .onChange(of: model.selectedEventId) { _, _ in Task { await model.load() } }
                .onChange(of: model.matchSkillsOnly) { _, _ in Task { await model.load() } }
                .toolbar { ToolbarItem(placement: .primaryAction) { Button { showCreate = true } label: { Image(systemName: "plus") }.accessibilityLabel("Create team").disabled(model.events.isEmpty) } }
                .task { await model.load() }
                .sheet(isPresented: $showCreate) { CreateTeamSheet(events: model.events) { eventId, name, goal, details, roles, limit in Task { await model.create(eventId: eventId, name: name, goal: goal, details: details, roles: roles, limit: limit) } } }
                .sheet(item: $selectedTeam) { team in TeamProfileSheet(team: team, profileSkills: model.profileSkills) { role in await model.join(team, role: role) } }
        }
    }

    @ViewBuilder private func teamRow(_ team: CommunityTeam) -> some View {
        let matchesProfile = team.roles.contains { role in
            role.requiredSkills.contains { needed in model.profileSkills.contains { $0.localizedCaseInsensitiveCompare(needed) == .orderedSame } }
        }
        VStack(alignment: .leading, spacing: 8) {
            HStack { Text(team.name).font(.headline); Spacer(); Text("\(team._count.memberships)/\(team.maxMembers)").font(.caption).foregroundStyle(.secondary) }
            Text(team.event.map { "\($0.title) · \($0.startsAt.prefix(10))" } ?? team.goal).font(.subheadline.weight(.medium))
            Text("Led by \(team.owner)").font(.caption).foregroundStyle(.secondary)
            if matchesProfile {
                Label("Matches your skills", systemImage: "sparkles").font(.caption.weight(.semibold)).foregroundStyle(.green)
            }
            HStack {
                Button("Team profile") { selectedTeam = team }.font(.caption.weight(.bold))
                Spacer()
                if !team.isOwner { Button { Task { await model.connect(team) } } label: { Image(systemName: "person.badge.plus") }.accessibilityLabel("Connect with team leader") }
                Menu {
                    Button("Report team", systemImage: "flag") { Task { await model.report(team) } }
                    Button("Block team leader", systemImage: "hand.raised", role: .destructive) { Task { await model.block(team) } }
                } label: { Image(systemName: "ellipsis.circle") }.accessibilityLabel("Team safety options")
            }
        }.padding(.vertical, 4)
    }
}

private struct TeamProfileSheet: View {
    @Environment(\.dismiss) private var dismiss
    let team: CommunityTeam
    let profileSkills: [String]
    let join: (TeamRole) async -> Bool
    @State private var applyingRoleId: String?
    @State private var requestedRoleIds: Set<String> = []
    @State private var candidates: [JoinRequest.Applicant] = []
    @State private var candidateQuery = ""
    @State private var selectedRoleId = ""
    @State private var teamActionMessage: String?
    @State private var actionBusy = false
    private let api = CommunityAPI()
    var body: some View {
        NavigationStack {
            List {
                Section("Team") {
                    Text(team.name).font(.title3.weight(.bold))
                    if let event = team.event { Label("\(event.title) · \(event.startsAt.prefix(10))", systemImage: "calendar") }
                    Text(team.description.isEmpty ? team.goal : team.description).foregroundStyle(.secondary)
                    Text("Led by \(team.owner) · \(team._count.memberships) of \(team.maxMembers) members").font(.caption).foregroundStyle(.secondary)
                    if let profile = team.ownerProfile {
                        if let bio = profile.bio, !bio.isEmpty { Text(bio).font(.subheadline) }
                        if let skills = profile.skills, !skills.isEmpty { Text("Leader skills: \(skills.joined(separator: " · "))").font(.caption).foregroundStyle(.secondary) }
                    }
                }
                Section("Active skill gaps") {
                    if team.roles.isEmpty { Text("No open roles at the moment.").foregroundStyle(.secondary) }
                    ForEach(team.roles) { role in
                        VStack(alignment: .leading, spacing: 7) {
                            HStack { Text(role.title).font(.headline); Spacer(); Text("\(max(0, role.openings - role.filled)) open").font(.caption.weight(.semibold)).foregroundStyle(OrbitStyle.coral) }
                            if !role.description.isEmpty { Text(role.description).font(.caption).foregroundStyle(.secondary) }
                            Text("Expertise: \(role.requiredSkills.joined(separator: " · "))").font(.caption.weight(.semibold))
                            if !profileSkills.isEmpty {
                                let overlap = role.requiredSkills.filter { need in profileSkills.contains { $0.localizedCaseInsensitiveCompare(need) == .orderedSame } }
                                if !overlap.isEmpty { Label("Your skills match: \(overlap.joined(separator: ", "))", systemImage: "checkmark.circle.fill").font(.caption).foregroundStyle(.green) }
                            }
                            if !team.isOwner {
                                if team.myRequestStatus == "pending" || requestedRoleIds.contains(role.id) { Label("Application pending", systemImage: "clock").font(.caption).foregroundStyle(.secondary) }
                                else if team.myRequestStatus == "accepted" { Label("You’re on this team", systemImage: "checkmark.circle.fill").font(.caption).foregroundStyle(.green) }
                                else {
                                    Button {
                                        Task {
                                            applyingRoleId = role.id
                                            let succeeded = await join(role)
                                            applyingRoleId = nil
                                            if succeeded { requestedRoleIds.insert(role.id) }
                                        }
                                    } label: {
                                        if applyingRoleId == role.id { ProgressView() }
                                        else { Text("Apply for \(role.title)").font(.caption.weight(.bold)) }
                                    }.disabled(applyingRoleId != nil)
                                }
                            }
                        }.padding(.vertical, 4)
                    }
                }
                if team.isOwner {
                    Section("Invite a student") {
                        Picker("Role", selection: $selectedRoleId) { ForEach(team.roles) { Text($0.title).tag($0.id) } }
                        TextField("Name, skill, or Gmail address", text: $candidateQuery)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .onSubmit { Task { await loadCandidates() } }
                        Button("Search students") { Task { await loadCandidates() } }.disabled(selectedRoleId.isEmpty || actionBusy)
                        if candidates.isEmpty && !candidateQuery.isEmpty && teamActionMessage == nil {
                            Text("No eligible visible student found. Check the address or try another search.").font(.caption).foregroundStyle(.secondary)
                        }
                        ForEach(candidates) { candidate in
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(candidate.studentProfile?.displayName ?? "Student").font(.subheadline.weight(.semibold))
                                    Text(candidate.studentProfile?.skills?.joined(separator: " · ") ?? "Skills not listed").font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Button("Invite") { Task { await invite(candidate) } }.disabled(actionBusy)
                            }
                        }
                        if let teamActionMessage { Text(teamActionMessage).font(.caption).foregroundColor(teamActionMessage.contains("sent") || teamActionMessage.contains("locked") ? Color.secondary : Color.red) }
                    }
                    Section("Registration") {
                        let minimum = team.event?.minStudentsPerTeam ?? 1
                        let maximum = team.event?.maxStudentsPerTeam ?? team.maxMembers
                        Text("Team must have \(minimum)–\(maximum) students. Current: \(team._count.memberships)")
                        if team.status == "locked" { Label("Team locked and registered", systemImage: "checkmark.circle.fill").foregroundStyle(.green) }
                        else { Button(actionBusy ? "Working…" : "Lock team and register") { Task { await lockTeam() } }.disabled(actionBusy || team._count.memberships < minimum || team._count.memberships > maximum) }
                    }
                }
                Section("Current members") {
                    ForEach(team.memberships) { member in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(member.student.studentProfile?.displayName ?? "Student").font(.subheadline.weight(.semibold))
                            if let skills = member.student.studentProfile?.skills, !skills.isEmpty { Text(skills.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary) }
                        }
                    }
                }
            }.navigationTitle("Team profile").toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
                .onAppear { if selectedRoleId.isEmpty { selectedRoleId = team.roles.first?.id ?? "" } }
                .onChange(of: selectedRoleId) { _, _ in Task { await loadCandidates() } }
        }
    }
    private func loadCandidates() async {
        guard !selectedRoleId.isEmpty else { return }
        actionBusy = true; defer { actionBusy = false }
        do { candidates = try await api.candidates(teamId: team.id, roleId: selectedRoleId, query: candidateQuery); teamActionMessage = nil }
        catch { teamActionMessage = error.localizedDescription }
    }
    private func invite(_ candidate: JoinRequest.Applicant) async {
        actionBusy = true; defer { actionBusy = false }
        do { try await api.inviteStudent(teamId: team.id, studentId: candidate.id, roleId: selectedRoleId); candidates.removeAll { $0.id == candidate.id }; teamActionMessage = "Invitation sent to \(candidate.studentProfile?.displayName ?? "student")." }
        catch { teamActionMessage = error.localizedDescription }
    }
    private func lockTeam() async {
        actionBusy = true; defer { actionBusy = false }
        do { try await api.lockTeam(teamId: team.id); teamActionMessage = "Team locked and all members registered." }
        catch { teamActionMessage = error.localizedDescription }
    }
}

private struct CreateTeamSheet: View {
    @Environment(\.dismiss) private var dismiss
    let events: [TeamEventOption]
    @State private var selectedEventId = ""
    @State private var name = ""
    @State private var goal = ""
    @State private var details = ""
    @State private var roles = [TeamRoleDraft()]
    private var selectedEvent: TeamEventOption? { events.first { $0.id == selectedEventId } }
    let create: (String, String, String, String, [TeamRoleDraft], Int) -> Void
    var body: some View {
        NavigationStack {
            Form {
                Section("Event") {
                    Picker("Build for", selection: $selectedEventId) {
                        Text("Choose an event").tag("")
                        ForEach(events) { event in Text("\(event.title) · \(event.startsAt.prefix(10))").tag(event.id) }
                    }
                }
                Section("Team profile") {
                TextField("Team name", text: $name)
                TextField("Goal", text: $goal)
                TextField("What are you building?", text: $details, axis: .vertical).lineLimit(2...5)
                }
                ForEach($roles) { $role in
                    Section("Open role") {
                        TextField("Role title (e.g. Frontend developer)", text: $role.title)
                        TextField("What will they do?", text: $role.description, axis: .vertical).lineLimit(2...4)
                        TextField("Exact skills (e.g. SwiftUI, API integration)", text: $role.skills)
                        Stepper("People needed: \(role.openings)", value: $role.openings, in: 1...20)
                        Button("Remove role", role: .destructive) { roles.removeAll { $0.id == role.id } }.disabled(roles.count == 1)
                    }
                }
                Button { roles.append(TeamRoleDraft()) } label: { Label("Add another role", systemImage: "plus.circle") }
                if let event = selectedEvent { Text("This event requires \(event.minStudentsPerTeam)–\(event.maxStudentsPerTeam) students per team. You’ll be added as the team leader.").font(.caption).foregroundStyle(.secondary) }
            }.navigationTitle("Start a team").toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") { create(selectedEventId, name, goal, details, roles, selectedEvent?.maxStudentsPerTeam ?? 1); dismiss() }
                        .disabled(selectedEventId.isEmpty || name.trimmingCharacters(in: .whitespaces).isEmpty || roles.contains { $0.title.trimmingCharacters(in: .whitespaces).isEmpty || $0.skills.split(separator: ",").isEmpty } || roles.reduce(0) { $0 + $1.openings } > (selectedEvent?.maxStudentsPerTeam ?? 1) - 1)
                }
            }
            .onAppear { if selectedEventId.isEmpty { selectedEventId = events.first?.id ?? "" } }
        }
    }
}
