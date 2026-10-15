#if os(iOS)
import ActivityKit
import Foundation

/// Atividade ao Vivo do iPhone (tela bloqueada + Dynamic Island): o uso de até 3 IAs.
/// Compilado no app (que inicia/atualiza) e no widget (que desenha); os dois precisam do mesmo tipo.
struct UsageActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        /// Uma IA: nome curto, % e reset da janela de 5h, % e reset da de 7 dias.
        struct Row: Codable, Hashable, Identifiable {
            var id: String
            var name: String
            var used: Double
            var resetsAt: Date?
            var week: Double?
            var weekResetsAt: Date?

            // Chaves curtas: o pacote da Atividade ao Vivo tem limite de 4 KB.
            enum CodingKeys: String, CodingKey {
                case id = "i", name = "n", used = "u", resetsAt = "r", week = "w", weekResetsAt = "x"
            }

            /// A % da janela pedida ("long" = 7d; sem 7d, cai na de 5h).
            func percent(_ window: String) -> Double { window == "long" ? (week ?? used) : used }
            func resets(_ window: String) -> Date? { window == "long" ? (week == nil ? resetsAt : weekResetsAt) : resetsAt }
        }

        /// Já filtradas no app: todas as visíveis (até 3) ou só a IA escolhida.
        var rows: [Row]
        var updatedAt: Date
        /// "short" (5h) | "long" (7d) | "both".
        var window: String = "short"
        /// true = "TODAS"; false = uma IA escolhida (a única em `rows`).
        var all: Bool = true

        enum CodingKeys: String, CodingKey { case rows = "r", updatedAt = "t", window = "m", all = "a" }

        init(rows: [Row], updatedAt: Date, window: String = "short", all: Bool = true) {
            self.rows = rows
            self.updatedAt = updatedAt
            self.window = window
            self.all = all
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            rows = try c.decode([Row].self, forKey: .rows)
            updatedAt = try c.decode(Date.self, forKey: .updatedAt)
            window = try c.decodeIfPresent(String.self, forKey: .window) ?? "short"
            all = try c.decodeIfPresent(Bool.self, forKey: .all) ?? true
        }

        /// A janela das % da ilha compacta: "both" usa a de 5h.
        var compactWindow: String { window == "long" ? "long" : "short" }

        /// A IA mais gasta (na janela da ilha): é ela que aparece na Dynamic Island mínima.
        var top: Row? { rows.max { $0.percent(compactWindow) < $1.percent(compactWindow) } }
    }
}

/// O que a Atividade ao Vivo mostra: qual IA ("all" ou o id) e qual janela. Mora no App Group,
/// para o app, o widget e os botões da ilha lerem a mesma escolha.
enum LiveChoice {
    static let agentKey = "liveAgent"
    static let windowKey = "liveWindow"
    static let windows = ["short", "long", "both"]

    static var agent: String {
        get { TB.defaults.string(forKey: agentKey) ?? "all" }
        set { TB.defaults.set(newValue, forKey: agentKey) }
    }

    static var window: String {
        get { windows.contains(TB.defaults.string(forKey: windowKey) ?? "") ? TB.defaults.string(forKey: windowKey)! : "short" }
        set { TB.defaults.set(newValue, forKey: windowKey) }
    }

    /// "all" e depois cada IA com dados, na ordem do aparelho (Claude, Codex, as outras).
    static func agents(in snapshot: UsageSnapshot?) -> [String] {
        let ids = snapshot?.providers.map(\.id) ?? []
        let known = ["claude", "codex"].filter { ids.contains($0) }
        return ["all"] + known + ids.filter { !known.contains($0) }
    }

    static func cycleAgent() {
        let list = agents(in: SharedStore.loadSnapshot())
        agent = list[((list.firstIndex(of: agent) ?? 0) + 1) % list.count]
    }

    static func cycleWindow() {
        window = windows[((windows.firstIndex(of: window) ?? 0) + 1) % windows.count]
    }

    /// Rótulo curto das janelas, igual à tecla do aparelho.
    static func windowLabel(_ w: String) -> String { w == "long" ? "7D" : w == "both" ? "5H 7D" : "5H" }
}

extension UsageActivityAttributes.ContentState {
    /// Filtra no app: só vai no pacote o que a ilha desenha.
    init(snapshot: UsageSnapshot, visible: [String], agent: String = LiveChoice.agent,
         window: String = LiveChoice.window, now: Date = .now) {
        var ps: [ProviderUsage]
        if agent != "all", let one = snapshot.provider(agent) {
            ps = [one]
            all = false
        } else {
            ps = visible.compactMap { snapshot.provider($0) }
            if ps.isEmpty { ps = snapshot.providers }
            all = true
        }
        rows = ps.prefix(3).map { p in
            let short = p.windows.first
            let long = p.windows.count > 1 ? p.windows[1] : nil
            return Row(id: p.id, name: UsageStyle.shortName(p.id), used: short?.used(at: now) ?? 0,
                       resetsAt: short?.didReset(at: now) == true ? nil : short?.resetsAt,
                       week: long?.used(at: now),
                       weekResetsAt: long?.didReset(at: now) == true ? nil : long?.resetsAt)
        }
        updatedAt = snapshot.updatedAt
        self.window = window
    }
}

/// Atualiza a Atividade que está no ar com a escolha atual (os botões da ilha e os ajustes).
/// Não cria uma nova: isso é com o app (LiveUsage), que sabe se está ligada e pareada.
enum LiveActivityRefresher {
    static func apply() async {
        guard let snapshot = SharedStore.loadSnapshot(), !snapshot.providers.isEmpty else { return }
        let state = UsageActivityAttributes.ContentState(snapshot: snapshot, visible: Prefs.visible)
        for a in Activity<UsageActivityAttributes>.activities where a.activityState == .active || a.activityState == .stale {
            // Mantém o prazo de "velho": trocar a vista não deixa o número mais novo.
            await a.update(ActivityContent(state: state, staleDate: a.content.staleDate))
        }
    }
}
#endif
