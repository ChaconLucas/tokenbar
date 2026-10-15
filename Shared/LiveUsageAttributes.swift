#if os(iOS)
import ActivityKit
import Foundation

/// Atividade ao Vivo do iPhone (tela bloqueada + Dynamic Island): o uso de até 3 IAs.
/// Compilado no app (que inicia/atualiza) e no widget (que desenha); os dois precisam do mesmo tipo.
struct UsageActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        /// Uma IA: nome curto, % da janela de 5h, quando ela zera e a % de 7 dias.
        struct Row: Codable, Hashable, Identifiable {
            var id: String
            var name: String
            var used: Double
            var resetsAt: Date?
            var week: Double?

            // Chaves curtas: o pacote da Atividade ao Vivo tem limite de 4 KB.
            enum CodingKeys: String, CodingKey { case id = "i", name = "n", used = "u", resetsAt = "r", week = "w" }
        }

        var rows: [Row]
        var updatedAt: Date

        enum CodingKeys: String, CodingKey { case rows = "r", updatedAt = "t" }

        /// A IA mais gasta: é ela que aparece na Dynamic Island compacta.
        var top: Row? { rows.max { $0.used < $1.used } }
    }
}

extension UsageActivityAttributes.ContentState {
    /// As IAs visíveis (no máximo 3), sempre a janela curta para a % e a contagem.
    init(snapshot: UsageSnapshot, visible: [String], now: Date = .now) {
        var ps = visible.compactMap { snapshot.provider($0) }
        if ps.isEmpty { ps = snapshot.providers }
        rows = ps.prefix(3).map { p in
            let short = p.windows.first
            let long = p.windows.count > 1 ? p.windows[1] : nil
            return Row(id: p.id, name: UsageStyle.shortName(p.id), used: short?.used(at: now) ?? 0,
                       resetsAt: short?.didReset(at: now) == true ? nil : short?.resetsAt,
                       week: long?.used(at: now))
        }
        updatedAt = snapshot.updatedAt
    }
}
#endif
