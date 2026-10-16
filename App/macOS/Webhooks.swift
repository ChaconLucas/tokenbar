import Foundation

/// Webhook: avisa um endereço quando uma janela passa de 80% / 95% e quando ela reseta.
/// Mesma regra dos avisos do iPhone (UsageAlerts): uma vez por limite em cada ciclo de reset,
/// guardado no UserDefaults para não repetir depois de reabrir o app.
/// Slack recebe `{"text"}`, Discord `{"content"}`; qualquer outro endereço, o JSON completo.
@MainActor
final class Webhooks: ObservableObject {
    static let shared = Webhooks()

    @Published var lastOK: Date?
    @Published var lastError: String?

    static let urlKey = "webhookURL"
    private let sentKey = "webhookSent"     // "prov.janela.80" → ciclo (resetsAt em segundos)
    private let armedKey = "webhookArmed"   // "prov.janela" → resetsAt de uma janela bem usada (≥ 50%)

    private var defaults: UserDefaults { .standard }

    private func flag(_ key: String) -> Bool { defaults.object(forKey: key) as? Bool ?? true }

    var url: URL? {
        let s = (defaults.string(forKey: Self.urlKey) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard let u = URL(string: s), let scheme = u.scheme?.lowercased(), scheme == "http" || scheme == "https",
              u.host?.isEmpty == false else { return nil }
        return u
    }

    /// Chamado a cada leitura (30 s).
    func check(_ snapshot: UsageSnapshot, now: Date = .now) {
        guard url != nil else { return }
        var sent = defaults.dictionary(forKey: sentKey) as? [String: Double] ?? [:]
        var armed = defaults.dictionary(forKey: armedKey) as? [String: Double] ?? [:]
        let nowS = now.timeIntervalSince1970

        for p in snapshot.providers {
            for w in p.windows {
                let key = "\(p.id).\(w.id)"
                let cycle = w.resetsAt?.timeIntervalSince1970 ?? 0
                let used = w.used(at: now)

                // Limites cruzados neste ciclo: manda só o mais alto (95 já cobre o 80) e marca todos.
                let crossed = [95.0, 80.0].filter { used >= $0 && sent["\(key).\(Int($0))"] != cycle }
                for t in crossed { sent["\(key).\(Int(t))"] = cycle }
                if let t = crossed.first(where: { flag("webhook\(Int($0))") }) {
                    send(event: "threshold", threshold: Int(t), provider: p, window: w, now: now,
                         text: thresholdText(p, w, t, used, now))
                }

                // Reset: a janela estava bem usada e o horário passou (até 6 h atrás; mais velho é só limpeza).
                if let r = armed[key], r <= nowS {
                    armed[key] = nil
                    if nowS - r < 6 * 3600, flag("webhookReset") {
                        var after = w
                        if w.resetsAt.map({ $0.timeIntervalSince1970 > nowS }) != true { after.resetsAt = Date(timeIntervalSince1970: r) }
                        send(event: "reset", threshold: nil, provider: p, window: after, now: now,
                             text: Lang.f("%@ %@ resetou: voltou a 0%%.", p.name, w.label))
                    }
                }
                if let r = w.resetsAt, r.timeIntervalSince1970 > nowS, used >= 50 {
                    armed[key] = r.timeIntervalSince1970
                }
            }
        }
        armed = armed.filter { nowS - $0.value < 6 * 3600 }
        defaults.set(sent, forKey: sentKey)
        defaults.set(armed, forKey: armedKey)
    }

    /// Tecla TESTAR: manda já um evento "test" (com a primeira janela que houver, se houver).
    func sendTest(snapshot: UsageSnapshot) {
        guard url != nil else { lastError = Lang.t("Endereço inválido"); lastOK = nil; return }
        let p = snapshot.providers.first { !$0.windows.isEmpty }
        send(event: "test", threshold: nil, provider: p, window: p?.windows.first, now: .now,
             text: Lang.t("Teste do TokenBar: o webhook está funcionando."))
    }

    private func thresholdText(_ p: ProviderUsage, _ w: UsageWindow, _ t: Double, _ used: Double, _ now: Date) -> String {
        let pct = Int(used.rounded())
        if let r = w.resetsAt, r > now {
            return Lang.f("%@ %@ passou de %d%% (%d%%). Reseta em %@.", p.name, w.label, Int(t), pct, Self.countdown(r, now))
        }
        return Lang.f("%@ %@ passou de %d%% (%d%%).", p.name, w.label, Int(t), pct)
    }

    /// "1:12" até 1 dia; "2d 3h" depois.
    static func countdown(_ date: Date, _ now: Date) -> String {
        let s = max(0, Int(date.timeIntervalSince(now)))
        let d = s / 86400, h = (s % 86400) / 3600, m = (s % 3600) / 60
        return d > 0 ? "\(d)d \(h)h" : String(format: "%d:%02d", h, m)
    }

    private func send(event: String, threshold: Int?, provider p: ProviderUsage?, window w: UsageWindow?,
                      now: Date, text: String) {
        guard let url else { return }
        let host = url.host?.lowercased() ?? ""
        let body: [String: Any]
        if host == "hooks.slack.com" {
            body = ["text": text]
        } else if ["discord.com", "discordapp.com"].contains(where: { host == $0 || host.hasSuffix("." + $0) }) {
            body = ["content": text]
        } else {
            body = [
                "event": event,
                "threshold": threshold.map { $0 as Any } ?? NSNull(),
                "provider": p.map { ["id": $0.id, "name": $0.name] as Any } ?? NSNull(),
                "window": w.map { UsageJSON.window($0, now: now) as Any } ?? NSNull(),
                "at": UsageJSON.seconds(now),
                "text": text,
            ]
        }
        var req = URLRequest(url: url, timeoutInterval: 10)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("TokenBar/\(LocalAPI.version)", forHTTPHeaderField: "User-Agent")
        req.httpBody = try? JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])
        Task {
            do {
                let (_, response) = try await URLSession.shared.data(for: req)
                let code = (response as? HTTPURLResponse)?.statusCode ?? 0
                if (200..<300).contains(code) {
                    lastOK = .now; lastError = nil
                } else {
                    lastError = "HTTP \(code)"
                }
            } catch {
                lastError = error.localizedDescription
            }
        }
    }
}
