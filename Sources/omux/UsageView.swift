import SwiftUI

/// Limits stay within the sidebar; reset details appear in tooltips without resizing it.
struct UsageView: View {
    @EnvironmentObject var store: Store
    @StateObject private var monitor = UsageMonitor()
    @StateObject private var antigravity = AntigravityUsage()
    @ObservedObject private var codex = CodexManager.shared
    @AppStorage(Prefs.usageInterval) private var usageInterval = 300.0

    /// Codex sessions show Codex's limits. Gemini CLI does not expose a supported
    /// usage endpoint here, so it doesn't show Claude's limits by accident.
    private var isCodex: Bool { store.selectedProvider == .codex }
    private var isGemini: Bool { store.selectedProvider == .gemini }
    private var limits: [UsageMonitor.Limit] { isCodex ? codex.limits : (isGemini ? antigravity.limits : monitor.limits) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if isCodex {
                Text(codex.plan.map { "Codex \($0.replacingOccurrences(of: "_", with: " ").capitalized)" } ?? "Codex")
                    .font(.caption2).foregroundStyle(.tertiary)
            }
            if isGemini {
                Text("Gemini CLI")
                    .font(.caption2).foregroundStyle(.tertiary)
            }
            if !isCodex && !isGemini {
                Text("Claude Code").font(.caption2).foregroundStyle(.secondary)
            }
            if limits.isEmpty {
                if isGemini {
                    Text("Waiting for Gemini usage data…")
                        .font(.caption2).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                Button {
                    if isCodex { Task { await codex.refreshUsage() } } else { monitor.refresh() }
                } label: {
                    Text(isCodex ? codex.usageError ?? "Codex usage…" : monitor.error ?? "Claude usage…")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                .buttonStyle(.plain)
                .help(isCodex ? codex.usageError ?? "" : monitor.detail ?? "")
                }
            }
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 8) {
            ForEach(limits) { limit in
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(limit.label) \(limit.percent)%")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(.quaternary)
                            Capsule().fill(limit.tint)
                                .frame(width: max(0, geo.size.width) * CGFloat(max(0, min(limit.percent, 100))) / 100)
                        }
                    }
                    .frame(height: 3)
                }
                .help("\(limit.label): \(limit.percent)% used. \(limit.resetText)")
            }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .onAppear { monitor.start() }
        .onAppear { if isGemini { antigravity.start() } }
        .onDisappear { monitor.stop(); antigravity.stop() }
        .onChange(of: usageInterval) { _, seconds in monitor.schedule(every: seconds) }
        .task(id: isCodex) {
            guard isCodex else { return }
            while !Task.isCancelled {
                await codex.refreshUsage()
                try? await Task.sleep(for: .seconds(max(usageInterval, 30)))
            }
        }
        .task(id: isGemini) {
            guard isGemini else { antigravity.stop(); return }
            antigravity.start()
        }
    }
}
