import Foundation

/// Uma janela de limite (ex.: 5 horas, 7 dias) de um provedor.
struct UsageWindow: Codable, Hashable, Identifiable {
    var id: String            // "five_hour", "seven_day", "primary", "secondary"
    var label: String         // "5h", "7d"
    var usedPercent: Double   // 0–100 (pode passar de 100)
    var resetsAt: Date?
    var windowMinutes: Int?

    /// Depois do reset a janela começa do zero, mesmo que ninguém tenha mandado número novo.
    func used(at now: Date = .now) -> Double {
        // Compara em segundos: o operador de Date quebrou na combinação Xcode-beta + iOS beta.
        if let r = resetsAt, r.timeIntervalSince1970 <= now.timeIntervalSince1970 { return 0 }
        return usedPercent
    }

    func didReset(at now: Date = .now) -> Bool {
        if let r = resetsAt { return r.timeIntervalSince1970 <= now.timeIntervalSince1970 }
        return false
    }
}

struct ProviderUsage: Codable, Hashable, Identifiable {
    var id: String            // "claude", "codex" ou qualquer outra IA (~/.tokenbar/providers/*.json)
    var name: String
    var windows: [UsageWindow]
    var observedAt: Date      // quando o número foi lido na fonte
    /// Cor da IA ("#RRGGBB"), opcional; Claude e Codex usam a do tema.
    var color: String? = nil

    /// A janela curta (5h) é a que mais importa no dia a dia.
    var primary: UsageWindow? { windows.first }
}

struct UsageSnapshot: Codable, Hashable {
    var providers: [ProviderUsage]
    var updatedAt: Date

    func provider(_ id: String) -> ProviderUsage? { providers.first { $0.id == id } }

    /// Datas futuras em que algum número muda sozinho (reset), para a timeline do widget.
    func upcomingResets(after now: Date = .now) -> [Date] {
        providers.flatMap(\.windows).compactMap(\.resetsAt).filter { $0 > now }.sorted()
    }

    static let empty = UsageSnapshot(providers: [], updatedAt: .distantPast)

    static let preview = UsageSnapshot(providers: [
        ProviderUsage(id: "claude", name: "Claude Code", windows: [
            UsageWindow(id: "five_hour", label: "5h", usedPercent: 32, resetsAt: .now.addingTimeInterval(2 * 3600), windowMinutes: 300),
            UsageWindow(id: "seven_day", label: "7d", usedPercent: 61, resetsAt: .now.addingTimeInterval(3 * 86400), windowMinutes: 10080),
        ], observedAt: .now),
        ProviderUsage(id: "codex", name: "Codex", windows: [
            UsageWindow(id: "primary", label: "5h", usedPercent: 54, resetsAt: .now.addingTimeInterval(4000), windowMinutes: 300),
            UsageWindow(id: "secondary", label: "7d", usedPercent: 8, resetsAt: .now.addingTimeInterval(5 * 86400), windowMinutes: 10080),
        ], observedAt: .now),
    ], updatedAt: .now)
}

enum JSONCoding {
    static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .secondsSince1970
        e.outputFormatting = [.sortedKeys]
        return e
    }()
    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .secondsSince1970
        return d
    }()
}
