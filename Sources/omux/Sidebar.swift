import SwiftUI
import UniformTypeIdentifiers

/// One row of the flat sidebar list: a project header or a session.
enum SidebarRow: Identifiable, Hashable {
    case group(TabGroup)
    case tab(TabItem, groupID: UUID)

    var id: UUID {
        switch self {
        case .group(let g): return g.id
        case .tab(let t, _): return t.id
        }
    }
}

struct Sidebar: View {
    @EnvironmentObject var store: Store
    let theme: Theme

    /// Projects followed by their sessions (hidden while collapsed). A flat list lets
    /// native drag reorder projects and move sessions between them.
    private var rows: [SidebarRow] {
        store.groups.flatMap { group in
            [SidebarRow.group(group)] + (group.isCollapsed ? [] : group.tabs.map { .tab($0, groupID: group.id) })
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Traffic lights occupy the top-left; actions sit on the right.
            HStack(spacing: 14) {
                Spacer()
                Button { store.newTab() } label: { Image(systemName: "terminal") }
                    .help("New terminal in current project (⌘T)")
                Button { store.openFolderPanel() } label: { Image(systemName: "folder.badge.plus") }
                    .help("Open folder as a project (⌘O)")
                Button { store.showRecentSessions = true } label: { Image(systemName: "clock.arrow.circlepath") }
                    .help("Open recent conversation (⇧⌘O)")
                SettingsLink { Image(systemName: "gearshape") }
                    .help("Settings (⌘,)")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .padding(.trailing, 12)
            .frame(height: 28)
            // The list grows into the title bar's safe area when it touches it, which would put it
            // over the buttons and take their clicks. A 1pt gap keeps it below them.
            Spacer(minLength: 0).frame(height: 1)

            List(selection: $store.selectedTabID) {
                ForEach(rows) { row in
                    switch row {
                    case .group(let group):
                        GroupHeader(group: group)
                            .selectionDisabled()
                            .listRowSeparator(.hidden)
                    case .tab(let tab, let groupID):
                        TabRow(tab: tab)
                            .tag(tab.id)
                            .listRowInsets(EdgeInsets(top: 3, leading: 10, bottom: 3, trailing: 8))
                            .contextMenu { TabMenu(tab: tab, groupID: groupID) }
                    }
                }
                .onMove { from, to in store.moveRows(rows, from: from, to: to) }
            }
            .listStyle(.sidebar)
            .environment(\.defaultMinListRowHeight, 28)
            .tint(Color(red: 0.35, green: 0.48, blue: 0.64))
            .scrollContentBackground(.hidden)

            Rectangle().fill(.primary.opacity(0.08)).frame(height: 1)
            UsageView()
        }
        .background(Color(nsColor: theme.chrome))
        .contextMenu {
            // Empty-space menu; rows and project headers override it with their own.
            Button("New Project") { store.newGroup() }
            Button("Open Folder as Project…") { store.openFolderPanel() }
            Button("Open Recent Conversation…") { store.showRecentSessions = true }
            Button("New Codex Session") { store.newTab(command: "codex") }
            Button("New Gemini Session") { store.newTab(command: "agy") }
            Divider()
            Button("New Terminal") { store.newTab() }
        }
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            for provider in providers {
                provider.loadDataRepresentation(forTypeIdentifier: UTType.fileURL.identifier) { data, _ in
                    guard let data, let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
                    DispatchQueue.main.async { store.openFolder(url.path) }
                }
            }
            return true
        }
    }
}

struct TabRow: View {
    @EnvironmentObject var store: Store
    @ObservedObject private var monitor = AgentMonitor.shared
    @ObservedObject private var pulls = PullRequestMonitor.shared
    @ObservedObject private var diffStats = DiffStatMonitor.shared
    let tab: TabItem
    @State private var hovering = false
    @AppStorage(Prefs.showFolderPath) private var showFolderPath = true

    /// "2 agents" while subagents run; the selected session lists them instead.
    private var agentCount: String? {
        guard store.selectedTabID != tab.id else { return nil }
        let running = (monitor.agents[tab.id] ?? []).filter { !$0.finished }.count
        return running > 0 ? "\(running) agent\(running == 1 ? "" : "s")" : nil
    }

    private func statusText(_ runtime: TabRuntime) -> String? {
        if runtime.exited { return "Stopped" }
        if let state = runtime.statusState, state != .idle {
            return runtime.statusLine(showFolder: false)
        }
        if runtime.needsAttention { return "Needs you" }
        if runtime.busy { return "Running" }
        return runtime.statusLine(showFolder: false)
    }

    var body: some View {
        let rt = store.runtime[tab.id] ?? TabRuntime()
        let provider = store.provider(of: tab)
        let folder = rt.cwd ?? store.directory(of: tab)
        let status = statusText(rt)
        let subtitle = [status ?? (showFolderPath ? folder.map { ($0 as NSString).abbreviatingWithTildeInPath } : nil), agentCount]
            .compactMap { $0 }.joined(separator: " · ").nilIfEmpty
        // Top-aligned so the dot stays beside the name when agent rows or buttons follow.
        HStack(alignment: .top, spacing: 8) {
            // The status dot turns into a close button on hover, as in Safari's tabs.
            ZStack {
                if hovering {
                    Button { store.requestClose(tab.id) } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(.secondary)
                            .frame(width: 20, height: 22)
                            .contentShape(Rectangle())
                    }
                    .help("Close session")
                } else {
                    Circle()
                        .fill(rt.statusColor ?? tab.color.color ?? Color.secondary.opacity(0.35))
                        .frame(width: 8, height: 8)
                }
            }
            .frame(width: 20, height: 22)
            .help(status ?? "Idle")
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    ProviderIcon(provider: provider)
                        .frame(width: 13, height: 13)
                        .help(provider.label)
                if store.renamingID == tab.id {
                    RenameField(initial: tab.name) { store.rename(tab.id, to: $0) }
                } else {
                    Text(tab.name)
                        .lineLimit(1)
                        .help(tab.name)
                }
                }
                .frame(height: 22)
                if let worktree = tab.worktree {
                    HStack(spacing: 3) {
                        Image(systemName: "arrow.triangle.branch").imageScale(.small)
                        Text(([worktree.branch, status, agentCount].compactMap { $0 })
                            .joined(separator: " · "))
                        if let stat = diffStats.stats[tab.id], !stat.isEmpty {
                            Stat(added: stat.added, removed: stat.removed).layoutPriority(1)
                        }
                        if let pr = pulls.requests[tab.id] {
                            PullRequestBadge(pr: pr).layoutPriority(1)
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .help([worktree.branch, status, folder].compactMap { $0 }.joined(separator: "\n"))
                } else if let line = subtitle {
                    Text(line)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .help([status, folder].compactMap { $0 }.joined(separator: "\n"))
                }
                if rt.awaitsPermission {
                    PermissionButtons(tabID: tab.id).padding(.top, 3)
                }
                if pulls.requests[tab.id]?.state == .merged {
                    Button("Delete Worktree") { store.cleanUpMergedWorktree(tab.id) }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .help("The pull request was merged. Close this session and delete its worktree and branch.")
                        .padding(.top, 3)
                }
                if store.provider(of: tab) == .codex {
                    CodexAgents(tabID: tab.id)
                } else {
                    AgentRows(tabID: tab.id, selected: store.selectedTabID == tab.id)
                }
            }
            Spacer(minLength: 4)
            ZStack {
            if hovering {
                if rt.busy || (store.provider(of: tab) == .codex && rt.agentConnected) {
                    Button { store.stop(tab.id) } label: { Image(systemName: "stop.fill") }
                        .help(store.provider(of: tab) == .codex ? "Interrupt Codex" : "Interrupt (Ctrl-C)")
                } else if !rt.agentConnected {
                    Button { store.start(tab.id) } label: { Image(systemName: "play.fill") }
                        .help("Start or continue this session")
                }
            } else if rt.needsAttention {
                Image(systemName: "bell.fill").font(.caption).foregroundStyle(.orange)
            } else if rt.hasActivity {
                Circle().fill(.blue).frame(width: 6, height: 6)
            }
            }
            .frame(width: 22, height: 22)
        }
        .buttonStyle(.plain)
        .onHover { over in
            hovering = over
            if over { store.refreshBusy(tab.id) }
        }
    }
}

struct GroupHeader: View {
    @EnvironmentObject var store: Store
    let group: TabGroup

    var body: some View {
        HStack(spacing: 4) {
            if store.renamingID == group.id {
                RenameField(initial: group.name) { store.rename(group.id, to: $0) }
            } else {
                Text(group.name)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .layoutPriority(1)
                    .help(group.name)
            }
            Button { store.updateGroup(group.id) { $0.isCollapsed.toggle() } } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .bold))
                    .rotationEffect(.degrees(group.isCollapsed ? 0 : 90))
                    .frame(width: 14, height: 24)
            }
            .help(group.isCollapsed ? "Show sessions" : "Hide sessions")
            Spacer(minLength: 4)
            GroupProviderButton(provider: .claude, group: group)
            GroupProviderButton(provider: .gemini, group: group)
            GroupProviderButton(provider: .codex, group: group)
            Button { store.newTab(in: group.id) } label: {
                Image(systemName: "terminal")
                    .font(.system(size: 12, weight: .medium))
                    .frame(width: 26, height: 26)
            }
            .help("New terminal in \(group.name)")
            Button { store.editingGroupID = group.id } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 12, weight: .medium))
                    .frame(width: 26, height: 26)
            }
            .help("Project settings")
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .padding(.top, 6)
        .contentShape(Rectangle())
        .contextMenu { GroupMenu(group: group) }
    }
}

private struct GroupProviderButton: View {
    @EnvironmentObject var store: Store
    let provider: SessionProvider
    let group: TabGroup

    var body: some View {
        Button { store.newTab(in: group.id, command: provider.command) } label: {
            ProviderIcon(provider: provider)
                .frame(width: 16, height: 16)
                .frame(width: 26, height: 26)
                .contentShape(Rectangle())
        }
        .help("New \(provider.label) session in \(group.name)")
    }
}

struct ProviderIcon: View {
    let provider: SessionProvider

    private var resourceName: String? {
        switch provider {
        case .claude: return "claude"
        case .codex: return "codex"
        case .gemini: return "antigravity"
        case .shell, .custom: return nil
        }
    }

    var body: some View {
        if let resourceName,
           let url = Bundle.main.url(forResource: resourceName, withExtension: "svg"),
           let image = NSImage(contentsOf: url) {
            Image(nsImage: image)
                .renderingMode(provider == .gemini ? .original : .template)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .foregroundStyle(providerColor)
        } else {
            Image(systemName: provider == .gemini ? "sparkles" : "terminal")
                .imageScale(.small)
                .foregroundStyle(providerColor)
        }
    }

    private var providerColor: Color {
        switch provider {
        case .claude: return Color(red: 0.84, green: 0.47, blue: 0.34)
        case .codex: return .primary
        case .gemini: return .accentColor
        case .shell, .custom: return .secondary
        }
    }
}

/// Inline rename editor; commits on Enter or focus loss, cancels on Escape.
struct RenameField: View {
    @EnvironmentObject var store: Store
    let initial: String
    let commit: (String) -> Void
    @State private var draft = ""
    @FocusState private var focused: Bool

    var body: some View {
        TextField("Name", text: $draft)
            .textFieldStyle(.plain)
            .focused($focused)
            .onAppear { draft = initial; focused = true }
            .onSubmit { finish(save: true) }
            .onExitCommand { finish(save: false) }
            .onChange(of: focused) { _, isFocused in
                if !isFocused { finish(save: true) }
            }
    }

    private func finish(save: Bool) {
        guard store.renamingID != nil else { return }
        if save { commit(draft) }
        store.renamingID = nil
    }
}

struct TabMenu: View {
    @EnvironmentObject var store: Store
    @ObservedObject private var pulls = PullRequestMonitor.shared
    let tab: TabItem
    let groupID: UUID

    var body: some View {
        Button("Rename") { store.renamingID = tab.id }
        Button("Edit Session…") { store.editingTabID = tab.id }
        Menu("Color") {
            ForEach(TabColor.allCases) { color in
                Button(color.label) { store.updateTab(tab.id) { $0.color = color } }
            }
        }
        if store.groups.count > 1 {
            Menu("Move to") {
                ForEach(store.groups.filter { $0.id != groupID }) { group in
                    Button(group.name) { store.moveTab(tab.id, toGroup: group.id) }
                }
            }
        }
        if let worktree = tab.worktree {
            Divider()
            if let pr = pulls.requests[tab.id], pr.state == .open {
                Button("Open Pull Request #\(pr.number)") { NSWorkspace.shared.open(pr.url) }
                if pr.checksResult == .failed {
                    Button("Send Failing Checks to Session") { store.sendFailingChecks(tab.id) }
                }
            } else if let pr = pulls.requests[tab.id], pr.state == .merged {
                Button("Delete Merged Worktree…") { store.cleanUpMergedWorktree(tab.id) }
                    .help("#\(pr.number) was merged")
            } else {
                Button("Create Pull Request…") { store.createPullRequest(tab.id) }
            }
            Button("Merge into \(worktree.base)") { store.mergeWorktree(tab.id) }
            Button("Open Worktree in Finder") {
                if let dir = store.directory(of: tab) { NSWorkspace.shared.open(URL(fileURLWithPath: dir)) }
            }
        }
        Divider()
        Button("Interrupt (Ctrl-C)") { store.stop(tab.id) }
        Button("Restart Session") { store.restart(tab.id) }
        Button("Kill Session") { store.kill(tab.id) }
        Button("Close Session", role: .destructive) { store.requestClose(tab.id) }
    }
}

struct GroupMenu: View {
    @EnvironmentObject var store: Store
    let group: TabGroup

    var body: some View {
        Button("New Terminal") { store.newTab(in: group.id) }
        Button("New Session in Worktree…") { store.newWorktreeGroupID = group.id }
        Divider()
        Button("Rename") { store.renamingID = group.id }
        Button("Edit Project…") { store.editingGroupID = group.id }
        Divider()
        Button("Move Up") { store.moveGroup(group.id, by: -1) }
            .disabled(store.groups.first?.id == group.id)
        Button("Move Down") { store.moveGroup(group.id, by: 1) }
            .disabled(store.groups.last?.id == group.id)
        Divider()
        Button("Delete Project", role: .destructive) { store.deleteGroup(group.id) }
    }
}

extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
