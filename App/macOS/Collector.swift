import Foundation

/// Lê os limites direto do disco: o Claude Code pela cópia da statusline, o Codex pelos arquivos de sessão.
enum Collector {
    static var home: URL { FileManager.default.homeDirectoryForCurrentUser }
    static var tokenbarDir: URL { home.appending(path: ".tokenbar") }
    static var claudeFile: URL { tokenbarDir.appending(path: "claude.json") }

    static func collect() -> UsageSnapshot {
        let providers = [readClaude(), readCodex()].compactMap { $0 }
        return UsageSnapshot(providers: providers, updatedAt: .now)
    }

    // MARK: Claude Code

    /// O JSON é o que o Claude Code entrega à statusline; o `claude-tee.sh` guarda uma cópia.
    static func readClaude() -> ProviderUsage? {
        guard let data = try? Data(contentsOf: claudeFile),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let limits = root["rate_limits"] as? [String: Any]
        else { return nil }

        var windows: [UsageWindow] = []
        for (key, label, minutes) in [("five_hour", "5h", 300), ("seven_day", "7d", 10080)] {
            guard let w = limits[key] as? [String: Any], let pct = number(w["used_percentage"]) else { continue }
            windows.append(UsageWindow(id: key, label: label, usedPercent: pct,
                                       resetsAt: number(w["resets_at"]).map { Date(timeIntervalSince1970: $0) },
                                       windowMinutes: minutes))
        }
        guard !windows.isEmpty else { return nil }
        return ProviderUsage(id: "claude", name: "Claude Code", windows: windows, observedAt: modified(claudeFile))
    }

    // MARK: Codex

    /// Cada sessão em ~/.codex/sessions/AAAA/MM/DD/*.jsonl tem eventos `token_count` com `rate_limits`.
    /// Vale o mais recente entre as sessões mais novas.
    static func readCodex() -> ProviderUsage? {
        let root = home.appending(path: ".codex/sessions")
        let files = recentFiles(in: root, ext: "jsonl", limit: 5)

        for file in files {
            guard let line = lastLine(containing: "\"rate_limits\"", in: file),
                  let obj = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
                  let payload = obj["payload"] as? [String: Any],
                  let limits = payload["rate_limits"] as? [String: Any]
            else { continue }

            var windows: [UsageWindow] = []
            for key in ["primary", "secondary"] {
                guard let w = limits[key] as? [String: Any], let pct = number(w["used_percent"]) else { continue }
                let minutes = number(w["window_minutes"]).map(Int.init)
                windows.append(UsageWindow(id: key, label: label(minutes) ?? key, usedPercent: pct,
                                           resetsAt: resetDate(w, file: file),
                                           windowMinutes: minutes))
            }
            guard !windows.isEmpty else { continue }
            return ProviderUsage(id: "codex", name: "Codex", windows: windows, observedAt: modified(file))
        }
        return nil
    }

    /// Versões novas mandam `resets_at` (epoch); antigas, `resets_in_seconds` relativo à escrita do arquivo.
    private static func resetDate(_ w: [String: Any], file: URL) -> Date? {
        if let at = number(w["resets_at"]) { return Date(timeIntervalSince1970: at) }
        if let secs = number(w["resets_in_seconds"]) { return modified(file).addingTimeInterval(secs) }
        return nil
    }

    private static func label(_ minutes: Int?) -> String? {
        guard let m = minutes else { return nil }
        if m % 1440 == 0 { return "\(m / 1440)d" }
        if m % 60 == 0 { return "\(m / 60)h" }
        return "\(m)m"
    }

    // MARK: Arquivos

    private static func number(_ v: Any?) -> Double? {
        if let n = v as? NSNumber { return n.doubleValue }
        if let s = v as? String { return Double(s) }
        return nil
    }

    private static func modified(_ url: URL) -> Date {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .now
    }

    /// Desce pelas pastas de data mais novas primeiro, sem varrer o histórico inteiro.
    static func recentFiles(in root: URL, ext: String, limit: Int) -> [URL] {
        let fm = FileManager.default
        func children(_ dir: URL) -> [URL] {
            ((try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.isDirectoryKey])) ?? [])
                .sorted { $0.lastPathComponent > $1.lastPathComponent }
        }
        var found: [URL] = []
        outer: for year in children(root) {
            for month in children(year) {
                for day in children(month) {
                    found += children(day).filter { $0.pathExtension == ext }
                    if found.count >= limit * 3 { break outer }
                }
            }
        }
        return Array(found.sorted { modified($0) > modified($1) }.prefix(limit))
    }

    /// Lê só o fim do arquivo (sessões longas passam de dezenas de MB).
    static func lastLine(containing needle: String, in url: URL) -> String? {
        guard let h = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? h.close() }
        let size = (try? h.seekToEnd()) ?? 0
        var chunk: UInt64 = 256 * 1024
        while true {
            let start = size > chunk ? size - chunk : 0
            try? h.seek(toOffset: start)
            let data = (try? h.readToEnd()) ?? Data()
            let text = String(decoding: data, as: UTF8.self)
            var lines = text.split(separator: "\n", omittingEmptySubsequences: true)
            if start > 0 { lines = Array(lines.dropFirst()) }   // primeira linha pode estar cortada
            if let hit = lines.last(where: { $0.contains(needle) }) { return String(hit) }
            if start == 0 || chunk >= 8 * 1024 * 1024 { return nil }
            chunk *= 4
        }
    }
}
