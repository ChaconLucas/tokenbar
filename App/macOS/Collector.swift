import Foundation
import SQLite3

/// Lê os limites direto do disco: o Claude Code pela cópia da statusline, o Codex pelos arquivos de sessão.
enum Collector {
    static var home: URL { FileManager.default.homeDirectoryForCurrentUser }
    static var tokenbarDir: URL { home.appending(path: ".tokenbar") }
    static var claudeFile: URL { tokenbarDir.appending(path: "claude.json") }

    static func collect() -> UsageSnapshot {
        let providers = [readClaude(), readCodex(), readWindsurf()].compactMap { $0 } + readExtra()
        return UsageSnapshot(providers: providers, updatedAt: .now)
    }

    /// Cópia em `~/.tokenbar/snapshot.json` (datas em segundos Unix): a extensão do VS Code e scripts leem daqui.
    static func writeSnapshotFile(_ s: UsageSnapshot) {
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .secondsSince1970
        guard let data = try? enc.encode(s) else { return }
        try? FileManager.default.createDirectory(at: tokenbarDir, withIntermediateDirectories: true)
        try? data.write(to: tokenbarDir.appending(path: "snapshot.json"), options: .atomic)
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

    // MARK: Outras IAs

    /// Qualquer IA: um JSON por arquivo em ~/.tokenbar/providers/ (formato em docs/providers.md).
    ///   { "id": "gemini", "name": "Gemini CLI", "color": "#4285F4",
    ///     "windows": [ { "id": "day", "label": "1d", "usedPercent": 42, "resetsAt": 1792000000 } ] }
    static var providersDir: URL { tokenbarDir.appending(path: "providers") }
    /// Ids que o próprio TokenBar lê; um arquivo com eles seria repetido.
    static let builtIn: Set<String> = ["claude", "codex", "copilot", "windsurf"]

    static func readExtra() -> [ProviderUsage] {
        let files = (try? FileManager.default.contentsOfDirectory(at: providersDir, includingPropertiesForKeys: nil)) ?? []
        return files.filter { $0.pathExtension == "json" }.sorted { $0.lastPathComponent < $1.lastPathComponent }.compactMap { url in
            guard let data = try? Data(contentsOf: url),
                  let o = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let id = o["id"] as? String, !id.isEmpty, !builtIn.contains(id),
                  let ws = o["windows"] as? [[String: Any]] else { return nil }
            let windows = ws.enumerated().compactMap { i, w -> UsageWindow? in
                guard let pct = number(w["usedPercent"]) else { return nil }
                return UsageWindow(id: (w["id"] as? String) ?? "w\(i)", label: (w["label"] as? String) ?? "",
                                   usedPercent: pct, resetsAt: number(w["resetsAt"]).map { Date(timeIntervalSince1970: $0) },
                                   windowMinutes: number(w["windowMinutes"]).map(Int.init))
            }
            guard !windows.isEmpty else { return nil }
            let observed = number(o["observedAt"]).map { Date(timeIntervalSince1970: $0) } ?? modified(url)
            return ProviderUsage(id: id, name: (o["name"] as? String) ?? id, windows: Array(windows.prefix(2)),
                                 observedAt: observed, color: o["color"] as? String)
        }
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

    // MARK: Windsurf

    /// O Windsurf guarda o plano (com a cota) no banco de estado do editor. Só leitura, sem rede.
    static var windsurfDB: URL {
        home.appending(path: "Library/Application Support/Windsurf/User/globalStorage/state.vscdb")
    }

    static func readWindsurf() -> ProviderUsage? {
        let file = windsurfDB
        guard FileManager.default.fileExists(atPath: file.path),
              let json = sqliteValue(file, key: "windsurf.settings.cachedPlanInfo"),
              let root = try? JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any]
        else { return nil }
        let wal = file.deletingLastPathComponent().appending(path: "state.vscdb-wal")
        let observed = FileManager.default.fileExists(atPath: wal.path) ? max(modified(file), modified(wal)) : modified(file)
        return parseWindsurf(root, observedAt: observed)
    }

    /// Formato novo: `quotaUsage` com % restante do dia e da semana. Antigo: `usage` com mensagens do mês.
    static func parseWindsurf(_ root: [String: Any], observedAt: Date) -> ProviderUsage? {
        var windows: [UsageWindow] = []
        if let q = root["quotaUsage"] as? [String: Any] {
            for (key, label, minutes) in [("daily", "1d", 1440), ("weekly", "7d", 10080)] {
                guard let left = number(q["\(key)RemainingPercent"]) else { continue }
                windows.append(UsageWindow(id: key, label: label, usedPercent: max(0, 100 - left),
                                           resetsAt: number(q["\(key)ResetAtUnix"]).map(epoch),
                                           windowMinutes: minutes))
            }
        }
        if windows.isEmpty, let u = root["usage"] as? [String: Any],
           let total = number(u["messages"]), total > 0, let used = number(u["usedMessages"]) {
            let end = number(u["endTimestamp"]) ?? number(root["endTimestamp"])
            windows.append(UsageWindow(id: "month", label: "1M", usedPercent: used / total * 100,
                                       resetsAt: end.map(epoch), windowMinutes: nil))
        }
        guard !windows.isEmpty else { return nil }
        return ProviderUsage(id: "windsurf", name: "Windsurf", windows: windows, observedAt: observedAt, color: "#14b8a6")
    }

    /// Segundos ou milissegundos desde 1970.
    private static func epoch(_ v: Double) -> Date { Date(timeIntervalSince1970: v > 1e11 ? v / 1000 : v) }

    /// Abre o SQLite como imutável (sem trava, sem gravar nada) e lê um valor do `ItemTable`.
    static func sqliteValue(_ file: URL, key: String) -> String? {
        var db: OpaquePointer?
        let uri = file.absoluteString + "?mode=ro&immutable=1"
        defer { sqlite3_close(db) }
        guard sqlite3_open_v2(uri, &db, SQLITE_OPEN_READONLY | SQLITE_OPEN_URI, nil) == SQLITE_OK else { return nil }
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT value FROM ItemTable WHERE key = ?1", -1, &stmt, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(stmt) }
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        sqlite3_bind_text(stmt, 1, key, -1, transient)
        guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
        if sqlite3_column_type(stmt, 0) == SQLITE_BLOB, let p = sqlite3_column_blob(stmt, 0) {
            return String(decoding: Data(bytes: p, count: Int(sqlite3_column_bytes(stmt, 0))), as: UTF8.self)
        }
        return sqlite3_column_text(stmt, 0).map { String(cString: $0) }
    }

    // MARK: Arquivos

    static func number(_ v: Any?) -> Double? {
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

/// GitHub Copilot, opcional: a cota mensal pela API do GitHub com o login do `gh` (ou do plugin do Copilot).
/// Só lê o token, que vai apenas no cabeçalho para api.github.com e nunca aparece em erro ou log.
enum Copilot {
    enum Failure: LocalizedError {
        case noLogin, expired, http(Int), format
        var errorDescription: String? {
            switch self {
            case .noLogin: Lang.t("Não achei o login do GitHub (gh auth login) nem do Copilot neste computador.")
            case .expired: Lang.t("Login do GitHub expirado: rode gh auth login.")
            case .http(let c): Lang.f("O GitHub respondeu %d.", c)
            case .format: Lang.t("Resposta inesperada do GitHub.")
            }
        }
    }

    /// `gh auth token`; sem ele, o `oauth_token` que o plugin do Copilot guardou.
    static func readToken() throws -> String {
        let fm = FileManager.default
        for path in ["/opt/homebrew/bin/gh", "/usr/local/bin/gh", "/usr/bin/gh"] where fm.isExecutableFile(atPath: path) {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: path)
            p.arguments = ["auth", "token", "--hostname", "github.com"]
            let out = Pipe()
            p.standardOutput = out
            p.standardError = FileHandle.nullDevice
            p.standardInput = FileHandle.nullDevice
            guard (try? p.run()) != nil else { continue }
            let data = out.fileHandleForReading.readDataToEndOfFile()
            p.waitUntilExit()
            let token = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            if p.terminationStatus == 0, !token.isEmpty, !token.contains(" ") { return token }
        }
        let dir = Collector.home.appending(path: ".config/github-copilot")
        for name in ["apps.json", "hosts.json"] {
            guard let data = try? Data(contentsOf: dir.appending(path: name)),
                  let root = try? JSONSerialization.jsonObject(with: data) as? [String: [String: Any]] else { continue }
            let keys = root.keys.sorted { ($0.hasPrefix("github.com") ? 0 : 1, $0) < ($1.hasPrefix("github.com") ? 0 : 1, $1) }
            if let token = keys.lazy.compactMap({ root[$0]?["oauth_token"] as? String }).first(where: { !$0.isEmpty }) { return token }
        }
        throw Failure.noLogin
    }

    /// nil = conta sem limite (nada a mostrar).
    static func fetch() async throws -> ProviderUsage? {
        let token = try await Task.detached { try readToken() }.value
        var req = URLRequest(url: URL(string: "https://api.github.com/copilot_internal/user")!, timeoutInterval: 15)
        req.setValue("token \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue("2025-04-01", forHTTPHeaderField: "X-Github-Api-Version")
        req.setValue("TokenBar", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: req)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        if code == 401 { throw Failure.expired }
        guard code == 200, let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw code == 200 ? Failure.format : Failure.http(code)
        }
        guard root["quota_snapshots"] is [String: Any] else { throw Failure.format }
        return parse(root, observedAt: .now)
    }

    /// Premium requests quando o plano tem; senão o chat (plano grátis). Ilimitado = nil.
    static func parse(_ root: [String: Any], observedAt: Date) -> ProviderUsage? {
        guard let snaps = root["quota_snapshots"] as? [String: Any] else { return nil }
        for key in ["premium_interactions", "chat"] {
            guard let q = snaps[key] as? [String: Any], (q["unlimited"] as? Bool) != true,
                  let total = Collector.number(q["entitlement"]), total > 0,
                  let left = Collector.number(q["percent_remaining"]) else { continue }
            let reset = (root["quota_reset_date_utc"] as? String).flatMap(date)
            return ProviderUsage(id: "copilot", name: "Copilot",
                                 windows: [UsageWindow(id: key, label: "1M", usedPercent: max(0, 100 - left),
                                                       resetsAt: reset, windowMinutes: nil)],
                                 observedAt: observedAt, color: "#3fb950")
        }
        return nil
    }

    private static func date(_ s: String) -> Date? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: s) { return d }
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: s)
    }
}
