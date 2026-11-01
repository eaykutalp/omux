import Foundation
import SwiftUI

/// Reads Antigravity's documented statusline quota payload written by the omux collector.
@MainActor
final class AntigravityUsage: ObservableObject {
    @Published private(set) var limits: [UsageMonitor.Limit] = []

    private var timer: Timer?

    func start() {
        refresh()
        let interval: TimeInterval = 2
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func refresh() {
        let url = URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Library/Application Support/omux/antigravity-conversations/usage.json")
        guard let data = try? Data(contentsOf: url),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let quota = root["quota"] as? [String: [String: Any]] else {
            limits = []
            return
        }
        let iso = ISO8601DateFormatter()
        limits = quota.compactMap { key, value in
            guard let remaining = value["remaining_fraction"] as? Double else { return nil }
            let percent = max(0, min(100, Int((1 - remaining) * 100)))
            let label = key.replacingOccurrences(of: "-", with: " ").capitalized
            let resetsAt = (value["reset_time"] as? String).flatMap(iso.date(from:))
            return UsageMonitor.Limit(id: key, label: label, percent: percent, resetsAt: resetsAt)
        }
        .sorted { $0.label < $1.label }
    }
}
