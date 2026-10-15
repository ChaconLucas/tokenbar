import Foundation
import Security

/// Segunda fonte do Claude, opcional: o login que o próprio Claude Code guardou nas Chaves.
/// Serve para quem usa o painel do VS Code, onde a statusline não roda.
/// Só lê a chave (nunca grava nem renova) e ela só vai para a Anthropic: não sai deste Mac de outro jeito.
enum ClaudeAccount {
    enum Failure: LocalizedError {
        case noLogin, expired, http(Int), format
        var errorDescription: String? {
            switch self {
            case .noLogin: Lang.t("Não achei o login do Claude Code neste Mac (ou o acesso às Chaves foi negado).")
            case .expired: Lang.t("Login do Claude expirado: abra o Claude Code uma vez.")
            case .http(let c): Lang.f("A Anthropic respondeu %d.", c)
            case .format: Lang.t("Resposta inesperada da Anthropic.")
            }
        }
    }

    /// Lê o token. O macOS pergunta uma vez se o TokenBar pode usar o item; "Permitir sempre" resolve.
    private static func readToken() throws -> String {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "Claude Code-credentials",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var out: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &out) == errSecSuccess,
              let data = out as? Data,
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let oauth = root["claudeAiOauth"] as? [String: Any],
              let token = oauth["accessToken"] as? String
        else { throw Failure.noLogin }
        if let ms = oauth["expiresAt"] as? Double, ms / 1000 < Date.now.timeIntervalSince1970 { throw Failure.expired }
        return token
    }

    /// Pergunta à Anthropic quanto dos limites desta conta já foi usado.
    static func fetch() async throws -> ProviderUsage {
        let token = try await Task.detached { try readToken() }.value
        var req = URLRequest(url: URL(string: "https://api.anthropic.com/api/oauth/usage")!, timeoutInterval: 15)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        let (data, response) = try await URLSession.shared.data(for: req)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        if code == 401 { throw Failure.expired }
        guard code == 200, let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw code == 200 ? Failure.format : Failure.http(code)
        }
        var windows: [UsageWindow] = []
        for (key, label, minutes) in [("five_hour", "5h", 300), ("seven_day", "7d", 10080)] {
            guard let w = root[key] as? [String: Any], let pct = w["utilization"] as? Double else { continue }
            windows.append(UsageWindow(id: key, label: label, usedPercent: pct,
                                       resetsAt: (w["resets_at"] as? String).flatMap(date), windowMinutes: minutes))
        }
        guard !windows.isEmpty else { throw Failure.format }
        return ProviderUsage(id: "claude", name: "Claude Code", windows: windows, observedAt: .now)
    }

    private static func date(_ s: String) -> Date? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: s) { return d }
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: s)
    }
}
