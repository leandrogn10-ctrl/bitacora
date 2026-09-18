/*  Vault.swift — the durable copy of the logbook, and the rule that decides what may replace it.

    WHY THIS FILE EXISTS. Bitácora's entire dataset — every rating, note and take, years of it —
    lives in ONE localStorage key inside a WKWebView. That is a fine place to read from and a
    terrible place to be the only copy: the app is REINSTALLED every night by the free-signing
    cron, WebKit has rewritten its own storage layout across iOS majors before, and the quota is
    ~5MB against a library that grows takes forever. So the webview holds the working copy and
    this file holds the record.

    THE RULE, and the mistake it was written against. The obvious design — "restore when
    localStorage is empty, otherwise just record whatever the app saves" — has a hole that
    destroys the backup along with the original: the app boots, the key is missing or won't
    parse, the app does the correct thing for a first run and initializes an EMPTY library,
    saves it, and the vault dutifully records the empty state over the full one. Two components
    behaving correctly, one irreversible loss, nothing anywhere reading as broken.

    So the vault is APPEND-ONLY and MONOTONIC:
      · every accepted OR held state is written to a generation file — history never refuses,
        so no state is ever lost in either direction;
      · the PRIMARY (what a restore reads) is replaced only by a state that is newer and has
        not collapsed. A stale or sharply-shrunken state is HELD: primary untouched, the
        state parked as pending, and the page told out loud.
    A held write is not a silent refusal — a silent refusal is just the same fake pass one
    layer down. It toasts, every time, until a human resolves it. */
import Foundation

struct StateSummary: Equatable {
    let lastModified: Double     // epoch MILLISECONDS — index.html writes Date.now()
    let itemCount: Int
}

enum VaultVerdict: Equatable {
    case accepted                // newer (or first) and intact — primary replaced
    case heldStale               // older than what we hold — a late/duplicate write
    case heldShrink(was: Int, now: Int)   // lost a meaningful share of the library
    case rejectedInvalid(String) // not a Bitácora state at all — never touches anything
}

enum VaultRule {
    /// A drop this large stops being an edit and starts being an accident.
    /// Two arms on purpose: an absolute one for a big library (losing 6+ titles at once is
    /// never a normal save) and a proportional one for a small one, where an absolute
    /// threshold would wave through a 6→1 collapse.
    static func isCollapse(was: Int, now: Int) -> Bool {
        let drop = was - now
        if drop <= 0 { return false }
        if drop > 5 { return true }
        return was >= 3 && Double(now) < 0.5 * Double(was)
    }

    /// nil when the payload is not a plausible Bitácora state. Deliberately strict: `items`
    /// must be an ARRAY. A state object missing it is either a different schema or a
    /// half-written file, and neither may be allowed to become the record.
    static func summarize(_ data: Data) -> StateSummary? {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let items = obj["items"] as? [Any] else { return nil }
        // A state that has never been saved carries no lastModified; treat it as epoch 0 so
        // ANY real save outranks it, rather than defaulting it to "now" and letting a blank
        // outrank the library. A default that satisfies every comparison is not a default.
        let lm = (obj["lastModified"] as? Double) ?? 0
        return StateSummary(lastModified: lm, itemCount: items.count)
    }

    static func decide(incoming: Data, current: StateSummary?) -> VaultVerdict {
        guard let inc = summarize(incoming) else {
            return .rejectedInvalid("payload is not a Bitácora state (no items array)")
        }
        guard let cur = current else { return .accepted }
        if inc.lastModified < cur.lastModified { return .heldStale }
        if isCollapse(was: cur.itemCount, now: inc.itemCount) {
            return .heldShrink(was: cur.itemCount, now: inc.itemCount)
        }
        return .accepted
    }
}

/// On-disk side. Kept apart from the rule above so the rule stays pure Foundation and the
/// harness can falsify it without a filesystem, a webview or a phone.
final class Vault {
    static let shared = Vault()

    private let fm = FileManager.default
    private var docs: URL { fm.urls(for: .documentDirectory, in: .userDomainMask)[0] }
    var primaryURL: URL { docs.appendingPathComponent("bitacora-vault.json") }
    var pendingURL: URL { docs.appendingPathComponent("bitacora-vault-pending.json") }
    var historyDir: URL { docs.appendingPathComponent("vault-history", isDirectory: true) }
    var logURL: URL { docs.appendingPathComponent("vault.log") }

    private let q = DispatchQueue(label: "com.leandro.bitacora.vault")

    func log(_ m: String) {
        let line = "\(ISO8601DateFormatter().string(from: Date())) \(m)\n"
        guard let d = line.data(using: .utf8) else { return }
        if let h = try? FileHandle(forWritingTo: logURL) {
            h.seekToEndOfFile(); h.write(d); try? h.close()
        } else { try? d.write(to: logURL) }
    }

    func currentSummary() -> StateSummary? {
        guard let d = try? Data(contentsOf: primaryURL) else { return nil }
        return VaultRule.summarize(d)
    }

    /// What a cold boot restores from. nil when we hold nothing readable.
    func primaryJSON() -> String? {
        guard let d = try? Data(contentsOf: primaryURL),
              VaultRule.summarize(d) != nil,
              let s = String(data: d, encoding: .utf8) else { return nil }
        return s
    }

    /// Generations are time-stamped, never a rolling count. N rolling saves is zero
    /// protection: the autosaves that follow a bad boot roll the good copy off the end.
    private func archive(_ data: Data, tag: String) {
        try? fm.createDirectory(at: historyDir, withIntermediateDirectories: true)
        let f = DateFormatter(); f.dateFormat = "yyyyMMdd-HHmmss"; f.timeZone = .current
        let name = "\(f.string(from: Date()))-\(tag).json"
        try? data.write(to: historyDir.appendingPathComponent(name), options: .atomic)
        prune()
    }

    /// Hourly for a day, daily for a month, then gone. Bounded without being forgetful.
    private func prune() {
        guard let names = try? fm.contentsOfDirectory(atPath: historyDir.path) else { return }
        let f = DateFormatter(); f.dateFormat = "yyyyMMdd-HHmmss"; f.timeZone = .current
        let now = Date()
        var keptHour = Set<String>(), keptDay = Set<String>()
        for name in names.sorted(by: >) {                       // newest first
            let stamp = String(name.prefix(15))
            guard let d = f.date(from: stamp) else { continue }
            let age = now.timeIntervalSince(d)
            let hourKey = String(name.prefix(11)), dayKey = String(name.prefix(8))
            var keep = false
            if age < 86_400 { keep = keptHour.insert(hourKey).inserted }
            else if age < 30 * 86_400 { keep = keptDay.insert(dayKey).inserted }
            if !keep { try? fm.removeItem(at: historyDir.appendingPathComponent(name)) }
        }
    }

    /// Returns the verdict so the caller can tell the page. Runs serialized: two saves racing
    /// must not both read the same "current" and both decide they are newer.
    @discardableResult
    func offer(_ data: Data) -> VaultVerdict {
        q.sync {
            let verdict = VaultRule.decide(incoming: data, current: currentSummary())
            switch verdict {
            case .rejectedInvalid(let why):
                log("REJECT \(why) (\(data.count) bytes)")
            case .accepted:
                try? data.write(to: primaryURL, options: .atomic)
                archive(data, tag: "ok")
                try? fm.removeItem(at: pendingURL)      // a good save clears an old dispute
                if let s = VaultRule.summarize(data) {
                    log("accept items=\(s.itemCount) lastModified=\(Int(s.lastModified))")
                }
            case .heldStale:
                archive(data, tag: "stale")
                log("HOLD stale — primary kept")
            case .heldShrink(let was, let now):
                // The state is NOT thrown away: it is parked and archived. Nothing is lost
                // whichever way this turns out to be resolved.
                try? data.write(to: pendingURL, options: .atomic)
                archive(data, tag: "shrink")
                log("HOLD shrink \(was)→\(now) items — primary kept, pending written")
            }
            return verdict
        }
    }

    /// The human's answer to a held shrink: promote what we parked. Only ever called from an
    /// explicit tap in the page, never automatically.
    @discardableResult
    func promotePending() -> Bool {
        q.sync {
            guard let d = try? Data(contentsOf: pendingURL), VaultRule.summarize(d) != nil
            else { return false }
            try? d.write(to: primaryURL, options: .atomic)
            archive(d, tag: "promoted")
            try? fm.removeItem(at: pendingURL)
            log("promote pending → primary (confirmed in app)")
            return true
        }
    }
}
