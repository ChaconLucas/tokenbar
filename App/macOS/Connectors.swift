import Foundation
import Security

/// IAs lidas pela rede: o Cursor pelo login que o próprio editor guardou; as outras por uma chave de API
/// colada nos Ajustes (fica no Keychain). A chave só vai para o site da própria IA, nunca para erro ou log.
/// Formatos conferidos no código aberto do CodexBar (steipete/CodexBar), que lê as mesmas fontes.
enum Connector: String, CaseIterable, Identifiable {
    case cursor, zai, minimax, kimi, openrouter, factory
    var id: String { rawValue }

    var name: String {
        switch self {
        case .cursor: "Cursor"
        case .zai: "GLM"
        case .minimax: "MiniMax"
        case .kimi: "Kimi"
        case .openrouter: "OpenRouter"
        case .factory: "Droid"
        }
    }

    /// Nome nos Ajustes (com a empresa quando o produto não diz).
    var title: String {
        switch self {
        case .zai: "Z.AI GLM"
        case .kimi: "KIMI CODE"
        case .factory: "FACTORY DROID"
        default: name.uppercased()
        }
    }

    var color: String {
        switch self {
        case .cursor: "#e5e5e5"
        case .zai: "#3b82f6"
        case .minimax: "#f43f5e"
        case .kimi: "#8b5cf6"
        case .openrouter: "#6366f1"
        case .factory: "#f97316"
        }
    }

    /// O Cursor não pede chave: usa o login do editor.
    var needsKey: Bool { self != .cursor }

    var info: String {
        switch self {
        case .cursor: Lang.t("Lê o uso do mês do plano usando o login que o Cursor já guardou neste computador. O token só vai para cursor.com.")
        case .zai: Lang.t("Coding Plan do GLM: limites de 5 horas e da semana. Crie uma chave de API em z.ai (ou open.bigmodel.cn) e cole aqui. A chave só vai para a Z.ai.")
        case .minimax: Lang.t("Coding Plan da MiniMax: janela atual e semana. Cole a chave do Coding Plan (sk-cp-…). A chave só vai para a MiniMax.")
        case .kimi: Lang.t("Kimi Code: limites de 5 horas e da semana. Crie uma chave no console do Kimi Code e cole aqui. A chave só vai para a Kimi.")
        case .openrouter: Lang.t("Quanto do limite da chave (ou dos créditos) já foi gasto. Cole uma chave de openrouter.ai/keys. A chave só vai para o OpenRouter.")
        case .factory: Lang.t("Limites de 5 horas e da semana do Droid. Cole a chave de app.factory.ai/settings/api-keys (ou deixe em ~/.factory/.env). A chave só vai para a Factory.")
        }
    }

    enum Failure: LocalizedError {
        case noLogin, expired, noKey, badKey(String), http(String, Int), format(String), offline(String)
        var errorDescription: String? {
            switch self {
            case .noLogin: Lang.t("Não achei o login do Cursor neste computador: abra o Cursor e entre na conta.")
            case .expired: Lang.t("Login do Cursor expirado: abra o Cursor uma vez.")
            case .noKey: Lang.t("Falta a chave de API.")
            case .badKey(let n): Lang.f("%@ recusou a chave.", n)
            case .http(let n, let c): Lang.f("%@ respondeu %d.", n, c)
            case .format(let n): Lang.f("Resposta inesperada de %@.", n)
            case .offline(let n): Lang.f("Sem conexão com %@.", n)
            }
        }
    }

    /// nil = conta sem limite (nada a mostrar).
    func fetch(key: String?) async throws -> ProviderUsage? {
        let key = key ?? (self == .factory ? Self.factoryEnvKey() : nil)
        if needsKey, (key ?? "").isEmpty { throw Failure.noKey }
        let k = key ?? ""
        let bearer = ["Authorization": "Bearer \(k)", "Accept": "application/json"]
        switch self {
        case .cursor:
            return try await fetchCursor()
        case .zai:
            let root = try await firstOK(["https://api.z.ai", "https://open.bigmodel.cn"].map { $0 + "/api/monitor/usage/quota/limit" }, headers: bearer)
            return Self.parseZai(root, observedAt: .now)
        case .minimax:
            let urls = ["https://api.minimax.io", "https://api.minimaxi.com"].flatMap { host in
                ["/v1/token_plan/remains", "/v1/api/openplatform/coding_plan/remains"].map { host + $0 }
            }
            let root = try await firstOK(urls, headers: bearer)
            if let base = (root["base_resp"] as? [String: Any]) ?? ((root["data"] as? [String: Any])?["base_resp"] as? [String: Any]),
               let code = Collector.number(base["status_code"]), code != 0 {
                throw code == 1004 ? Failure.badKey(name) : Failure.format(name)
            }
            return Self.parseMiniMax(root, observedAt: .now)
        case .kimi:
            let root = try await firstOK(["https://api.kimi.com", "https://api.kimi.ai"].map { $0 + "/coding/v1/usages" }, headers: bearer)
            return Self.parseKimi(root, observedAt: .now)
        case .openrouter:
            let keyInfo = try await firstOK(["https://openrouter.ai/api/v1/key"], headers: bearer)
            if let p = Self.parseOpenRouterKey(keyInfo, observedAt: .now) { return p }
            let credits = try await firstOK(["https://openrouter.ai/api/v1/credits"], headers: bearer)
            return Self.parseOpenRouterCredits(credits, observedAt: .now)
        case .factory:
            var h = bearer
            h["Origin"] = "https://app.factory.ai"
            h["x-factory-client"] = "web-app"
            let root = try await firstOK(["https://api.factory.ai/api/billing/limits"], headers: h)
            if let p = Self.parseFactory(root, now: .now) { return p }
            let legacy = try await firstOK(["https://api.factory.ai/api/organization/subscription/usage?useCache=true"], headers: h)
            return Self.parseFactoryLegacy(legacy, observedAt: .now)
        }
    }

    // MARK: Rede

    /// Tenta os endereços em ordem (região internacional, depois China): vale o primeiro 200.
    /// 401/403/404 passam para o próximo; se todos recusam, a chave é que está errada.
    private func firstOK(_ urls: [String], headers: [String: String]) async throws -> [String: Any] {
        var refused = false, lastCode = 0
        for u in urls {
            var req = URLRequest(url: URL(string: u)!, timeoutInterval: 15)
            for (k, v) in headers { req.setValue(v, forHTTPHeaderField: k) }
            req.setValue("TokenBar", forHTTPHeaderField: "User-Agent")
            let data: Data, response: URLResponse
            do { (data, response) = try await URLSession.shared.data(for: req) } catch { throw Failure.offline(name) }
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            if code == 200 {
                guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw Failure.format(name) }
                return root
            }
            if code == 401 || code == 403 { refused = true; continue }
            if code == 404 { lastCode = code; continue }
            throw Failure.http(name, code)
        }
        if refused { throw self == .cursor ? Failure.expired : Failure.badKey(name) }
        throw Failure.http(name, lastCode)
    }

    // MARK: Cursor

    static var cursorDB: URL {
        Collector.home.appending(path: "Library/Application Support/Cursor/User/globalStorage/state.vscdb")
    }

    /// O token do editor (um JWT) vira o cookie de sessão do site: `<id do usuário>::<token>`.
    private func fetchCursor() async throws -> ProviderUsage? {
        guard let token = Collector.sqliteValue(Self.cursorDB, key: "cursorAuth/accessToken", live: true)?
                .trimmingCharacters(in: CharacterSet(charactersIn: "\" \n")), !token.isEmpty,
              let claims = Self.jwtClaims(token),
              let sub = claims["sub"] as? String, let user = sub.split(separator: "|").last
        else { throw Failure.noLogin }
        if let exp = Collector.number(claims["exp"]), exp < Date.now.timeIntervalSince1970 + 60 { throw Failure.expired }
        let root = try await firstOK(["https://cursor.com/api/usage-summary"],
                                     headers: ["Accept": "application/json", "Cookie": "WorkosCursorSessionToken=\(user)%3A%3A\(token)"])
        return Self.parseCursor(root, observedAt: .now)
    }

    static func jwtClaims(_ jwt: String) -> [String: Any]? {
        let parts = jwt.split(separator: ".")
        guard parts.count >= 2 else { return nil }
        var b = parts[1].replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while b.count % 4 != 0 { b += "=" }
        guard let data = Data(base64Encoded: b) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    /// `totalPercentUsed` já vem em % (0,36 = 0,36%); sem ele, a média de auto e API, depois os valores em centavos.
    static func parseCursor(_ root: [String: Any], observedAt: Date) -> ProviderUsage? {
        let ind = root["individualUsage"] as? [String: Any]
        let plan = ind?["plan"] as? [String: Any]
        let n = Collector.number
        var pct: Double?
        if let t = n(plan?["totalPercentUsed"]) { pct = t }
        else if let a = n(plan?["autoPercentUsed"]), let b = n(plan?["apiPercentUsed"]) { pct = (a + b) / 2 }
        else if let b = n(plan?["apiPercentUsed"]) ?? n(plan?["autoPercentUsed"]) { pct = b }
        else {
            for pool in [plan, ind?["overall"] as? [String: Any], (root["teamUsage"] as? [String: Any])?["pooled"] as? [String: Any]] {
                if let used = n(pool?["used"]), let limit = n(pool?["limit"]), limit > 0 { pct = used / limit * 100; break }
            }
        }
        guard let pct else { return nil }
        let reset = (root["billingCycleEnd"] as? String).flatMap(isoDate)
        return ProviderUsage(id: "cursor", name: "Cursor",
                             windows: [UsageWindow(id: "month", label: "1M", usedPercent: max(0, pct), resetsAt: reset, windowMinutes: nil)],
                             observedAt: observedAt, color: Connector.cursor.color)
    }

    // MARK: Z.ai (GLM Coding Plan)

    /// `data.limits[]`: TOKENS_LIMIT/CREDIT_LIMIT são as janelas do plano (TIME_LIMIT é a cota de MCP, fica de fora).
    /// unit 3 = hora, 1 = dia, 6 = semana, 5 = minuto; `nextResetTime` em ms.
    static func parseZai(_ root: [String: Any], observedAt: Date) -> ProviderUsage? {
        guard let limits = (root["data"] as? [String: Any])?["limits"] as? [[String: Any]] else { return nil }
        let n = Collector.number
        let mult: [Int: Int] = [1: 1440, 3: 60, 5: 1, 6: 10080]
        var windows: [UsageWindow] = []
        for l in limits {
            guard let type = l["type"] as? String, type == "TOKENS_LIMIT" || type == "CREDIT_LIMIT",
                  var pct = n(l["percentage"]) else { continue }
            if let total = n(l["usage"]), total > 0 {
                if let left = n(l["remaining"]) { pct = max(0, min(total, total - left)) / total * 100 }
                else if let cur = n(l["currentValue"]) { pct = max(0, min(total, cur)) / total * 100 }
            }
            let minutes = n(l["unit"]).flatMap { mult[Int($0)] }.flatMap { m in n(l["number"]).map { Int($0) * m } }
            var reset = n(l["nextResetTime"]).map(epoch)
            // Reset de 5h a mais de 5h daqui é fuso trocado: melhor sem hora do que hora errada.
            if minutes == 300, let r = reset, r.timeIntervalSinceNow > 5 * 3600 + 60 { reset = nil }
            windows.append(UsageWindow(id: "w\(minutes ?? windows.count)", label: label(minutes) ?? "", usedPercent: min(100, max(0, pct)),
                                       resetsAt: reset, windowMinutes: minutes))
        }
        return provider(.zai, windows, observedAt)
    }

    // MARK: MiniMax

    /// `model_remains[]` (na raiz ou em `data`). Atenção: `current_interval_usage_count` é o que RESTA, não o usado.
    static func parseMiniMax(_ root: [String: Any], observedAt: Date) -> ProviderUsage? {
        let list = (root["model_remains"] ?? (root["data"] as? [String: Any])?["model_remains"]) as? [[String: Any]] ?? []
        let isText = { (m: [String: Any]) -> Bool in
            let s = ((m["model_name"] as? String) ?? "").lowercased()
            return s == "general" || s.contains("minimax-m") || s.hasPrefix("m2.")
        }
        guard let item = list.first(where: isText) ?? list.first else { return nil }
        let n = Collector.number
        func window(_ id: String, total: String, left: String, leftPct: String, start: String, end: String) -> UsageWindow? {
            var pct: Double?
            if let rp = n(item[leftPct]) { pct = 100 - rp }
            else if let t = n(item[total]), t > 0, let r = n(item[left]) { pct = max(0, t - r) / t * 100 }
            guard let pct else { return nil }
            let s = n(item[start]).map(epoch), e = n(item[end]).map(epoch)
            let minutes = s.flatMap { s in e.map { Int(($0.timeIntervalSince(s) / 60).rounded()) } }.flatMap { $0 > 0 ? $0 : nil }
            return UsageWindow(id: id, label: label(minutes) ?? (id == "weekly" ? "7d" : ""), usedPercent: min(100, max(0, pct)),
                               resetsAt: e, windowMinutes: minutes)
        }
        let windows = [
            window("interval", total: "current_interval_total_count", left: "current_interval_usage_count",
                   leftPct: "current_interval_remaining_percent", start: "start_time", end: "end_time"),
            window("weekly", total: "current_weekly_total_count", left: "current_weekly_usage_count",
                   leftPct: "current_weekly_remaining_percent", start: "weekly_start_time", end: "weekly_end_time"),
        ].compactMap { $0 }
        return provider(.minimax, windows, observedAt)
    }

    // MARK: Kimi Code

    /// Formato novo: `usages.limit_5h / limit_7d / limit_month_total` com `used_ratio` (0–1).
    /// Antigo: `limits[]` (janela de 5h) e `usage` (semana), com números em texto.
    static func parseKimi(_ root: [String: Any], observedAt: Date) -> ProviderUsage? {
        let n = Collector.number
        var byMinutes: [Int: UsageWindow] = [:]
        if let pools = root["usages"] as? [String: Any] {
            for (key, minutes) in [("limit_5h", 300), ("limit_7d", 10080), ("limit_month_total", 43200)] {
                guard let p = pools[key] as? [String: Any], let r = n(p["used_ratio"]), r >= 0 else { continue }
                byMinutes[minutes] = UsageWindow(id: key, label: minutes == 43200 ? "1M" : label(minutes) ?? "", usedPercent: min(1, r) * 100,
                                                 resetsAt: (p["reset_time"] as? String).flatMap(isoDate), windowMinutes: minutes == 43200 ? nil : minutes)
            }
        }
        func legacy(_ d: [String: Any]?, id: String, minutes: Int) {
            guard byMinutes[minutes] == nil, let d, let limit = n(d["limit"]), limit > 0 else { return }
            guard let used = n(d["used"]) ?? n(d["remaining"]).map({ limit - $0 }) else { return }
            let reset = (d["resetTime"] ?? d["reset_time"] ?? d["resetAt"] ?? d["reset_at"]) as? String
            byMinutes[minutes] = UsageWindow(id: id, label: label(minutes) ?? "", usedPercent: max(0, used) / limit * 100,
                                             resetsAt: reset.flatMap(isoDate), windowMinutes: minutes)
        }
        for l in root["limits"] as? [[String: Any]] ?? [] {
            guard let w = l["window"] as? [String: Any], let dur = n(w["duration"]) else { continue }
            let unit = w["timeUnit"] as? String
            let minutes = Int(dur) * (unit == "TIME_UNIT_HOUR" ? 60 : unit == "TIME_UNIT_DAY" ? 1440 : 1)
            legacy(l["detail"] as? [String: Any], id: "limit_\(minutes)m", minutes: minutes)
        }
        legacy(root["usage"] as? [String: Any], id: "limit_7d", minutes: 10080)
        let windows = byMinutes.keys.sorted().compactMap { byMinutes[$0] }
        return provider(.kimi, windows, observedAt)
    }

    // MARK: OpenRouter

    /// Limite da chave (`data.limit` em US$); chave sem limite = nil, aí vale o saldo de créditos.
    static func parseOpenRouterKey(_ root: [String: Any], observedAt: Date) -> ProviderUsage? {
        guard let d = root["data"] as? [String: Any], let limit = Collector.number(d["limit"]), limit > 0 else { return nil }
        let left = Collector.number(d["limit_remaining"]) ?? max(0, limit - (Collector.number(d["usage"]) ?? 0))
        let lbl: String = switch d["limit_reset"] as? String {
        case "daily": "1d"
        case "weekly": "7d"
        case "monthly": "1M"
        default: "$"
        }
        return provider(.openrouter, [UsageWindow(id: "key", label: lbl, usedPercent: max(0, limit - left) / limit * 100,
                                                  resetsAt: nil, windowMinutes: nil)], observedAt)
    }

    static func parseOpenRouterCredits(_ root: [String: Any], observedAt: Date) -> ProviderUsage? {
        guard let d = root["data"] as? [String: Any], let total = Collector.number(d["total_credits"]), total > 0 else { return nil }
        let used = Collector.number(d["total_usage"]) ?? 0
        return provider(.openrouter, [UsageWindow(id: "credits", label: "$", usedPercent: used / total * 100,
                                                  resetsAt: nil, windowMinutes: nil)], observedAt)
    }

    // MARK: Factory (Droid)

    /// `limits.standard.{fiveHour,weekly}` com `usedPercent` (0–100), `secondsRemaining` e `windowEnd`.
    static func parseFactory(_ root: [String: Any], now: Date) -> ProviderUsage? {
        guard (root["usesTokenRateLimitsBilling"] as? Bool) == true,
              let std = (root["limits"] as? [String: Any])?["standard"] as? [String: Any] else { return nil }
        let n = Collector.number
        var windows: [UsageWindow] = []
        for (key, lbl, minutes) in [("fiveHour", "5h", 300), ("weekly", "7d", 10080)] {
            guard let w = std[key] as? [String: Any], var pct = n(w["usedPercent"]) else { continue }
            var reset: Date?
            if let s = n(w["secondsRemaining"]), s > 0 { reset = now.addingTimeInterval(s) }
            else if let end = n(w["windowEnd"]).map(epoch) ?? (w["windowEnd"] as? String).flatMap(isoDate) {
                if end > now { reset = end } else if w["secondsRemaining"] == nil { pct = 0 }   // janela já virou
            }
            windows.append(UsageWindow(id: key, label: lbl, usedPercent: min(100, max(0, pct)), resetsAt: reset, windowMinutes: minutes))
        }
        return provider(.factory, windows, now)
    }

    /// Contas antigas: tokens do mês (`usage.standard`), fim do período em ms.
    static func parseFactoryLegacy(_ root: [String: Any], observedAt: Date) -> ProviderUsage? {
        guard let u = root["usage"] as? [String: Any], let s = u["standard"] as? [String: Any] else { return nil }
        let n = Collector.number
        var pct: Double?
        if let r = n(s["usedRatio"]) { pct = r * 100 }
        else if let used = n(s["userTokens"]), let total = n(s["totalAllowance"]), total > 0, total < 1e12 { pct = used / total * 100 }
        guard let pct else { return nil }
        return provider(.factory, [UsageWindow(id: "month", label: "1M", usedPercent: max(0, pct),
                                               resetsAt: n(u["endDate"]).map(epoch), windowMinutes: nil)], observedAt)
    }

    /// `FACTORY_API_KEY=…` (ou `export FACTORY_API_KEY=…`) em ~/.factory/.env.
    static func factoryEnvKey() -> String? {
        guard let text = try? String(contentsOf: Collector.home.appending(path: ".factory/.env"), encoding: .utf8) else { return nil }
        for line in text.split(separator: "\n") {
            var l = line.trimmingCharacters(in: .whitespaces)
            if l.hasPrefix("export ") { l = String(l.dropFirst(7)).trimmingCharacters(in: .whitespaces) }
            guard l.hasPrefix("FACTORY_API_KEY=") else { continue }
            let v = l.dropFirst("FACTORY_API_KEY=".count).trimmingCharacters(in: CharacterSet(charactersIn: "\"' "))
            if !v.isEmpty { return v }
        }
        return nil
    }

    // MARK: Comum

    /// Até 2 janelas, a mais curta primeiro (como o resto do app).
    private static func provider(_ c: Connector, _ windows: [UsageWindow], _ observedAt: Date) -> ProviderUsage? {
        guard !windows.isEmpty else { return nil }
        return ProviderUsage(id: c.id, name: c.name, windows: Array(windows.prefix(2)), observedAt: observedAt, color: c.color)
    }

    private static func label(_ minutes: Int?) -> String? {
        guard let m = minutes else { return nil }
        if m % 1440 == 0 { return "\(m / 1440)d" }
        if m % 60 == 0 { return "\(m / 60)h" }
        return "\(m)m"
    }

    /// Segundos ou milissegundos desde 1970.
    private static func epoch(_ v: Double) -> Date { Date(timeIntervalSince1970: v > 1e11 ? v / 1000 : v) }

    static func isoDate(_ s: String) -> Date? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: s) { return d }
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: s)
    }
}

/// Chaves de API no Keychain do Mac (serviço "TokenBar", conta = id da IA).
enum ConnectorKeys {
    private static func query(_ id: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "TokenBar", kSecAttrAccount as String: id]
    }

    static func get(_ id: String) -> String? {
        var q = query(id)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let d = out as? Data else { return nil }
        return String(data: d, encoding: .utf8)
    }

    static func set(_ id: String, _ key: String?) {
        SecItemDelete(query(id) as CFDictionary)
        guard let key, !key.isEmpty else { return }
        var q = query(id)
        q[kSecValueData as String] = Data(key.utf8)
        q[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(q as CFDictionary, nil)
    }
}
