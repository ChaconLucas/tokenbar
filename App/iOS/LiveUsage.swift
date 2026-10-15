import ActivityKit
import Foundation

/// Liga, atualiza e encerra a Atividade ao Vivo (tela bloqueada + Dynamic Island).
@MainActor
enum LiveUsage {
    static let enabledKey = "liveActivityEnabled"

    static var enabled: Bool {
        // Ligada por padrão: pareou, a ilha já aparece. A chave nos ajustes serve para desligar.
        get { UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: enabledKey) }
    }

    /// A pessoa desligou as Atividades ao Vivo nos Ajustes do iPhone.
    static var allowed: Bool { ActivityAuthorizationInfo().areActivitiesEnabled }

    /// Some sozinha ~15 min depois do último número: o sistema apaga um pouco para dizer "velho".
    static let staleAfter: TimeInterval = 15 * 60

    private static var running: [Activity<UsageActivityAttributes>] {
        Activity<UsageActivityAttributes>.activities.filter { $0.activityState == .active || $0.activityState == .stale }
    }

    /// Chamado depois de cada leitura boa. Ligada e pareada: atualiza a que está no ar ou pede uma nova
    /// (a do sistema acaba em 8 h; pedir só dá certo com o app aberto, em segundo plano só atualiza).
    static func sync(_ snapshot: UsageSnapshot, paired: Bool) async {
        guard enabled, paired, !snapshot.providers.isEmpty else { await endAll(); return }
        await show(.init(snapshot: snapshot, visible: Prefs.visible))
    }

    static func show(_ state: UsageActivityAttributes.ContentState) async {
        let content = ActivityContent(state: state, staleDate: .now.addingTimeInterval(staleAfter))
        let live = running
        if let a = live.first {
            await a.update(content)
            for extra in live.dropFirst() { await extra.end(nil, dismissalPolicy: .immediate) }
            return
        }
        guard allowed else { return }
        _ = try? Activity.request(attributes: UsageActivityAttributes(), content: content, pushType: nil)
    }

    static func endAll() async {
        for a in Activity<UsageActivityAttributes>.activities {
            await a.end(nil, dismissalPolicy: .immediate)
        }
    }

    #if DEBUG
    /// -TBLiveActivityDemo YES: números de mentira, para ver a tela bloqueada e a ilha no simulador.
    static var demo: Bool { UserDefaults.standard.bool(forKey: "TBLiveActivityDemo") }

    static func startDemo() async { await show(demoState()) }

    /// Os números de mentira, já filtrados pela escolha (IA e janela) como os de verdade.
    static func demoState(agent: String = LiveChoice.agent, window: String = LiveChoice.window) -> UsageActivityAttributes.ContentState {
        let now = Date.now
        let rows: [UsageActivityAttributes.ContentState.Row] = [
            .init(id: "claude", name: "CLAUDE", used: 32, resetsAt: now.addingTimeInterval(2 * 3600 + 14 * 60), week: 61,
                  weekResetsAt: now.addingTimeInterval(3 * 86400 + 5 * 3600)),
            .init(id: "codex", name: "CODEX", used: 87, resetsAt: now.addingTimeInterval(41 * 60), week: 23,
                  weekResetsAt: now.addingTimeInterval(5 * 86400 + 2 * 3600)),
            .init(id: "gemini", name: "GEMINI", used: 54, resetsAt: now.addingTimeInterval(3 * 3600 + 5 * 60), week: 40,
                  weekResetsAt: now.addingTimeInterval(20 * 3600)),
        ]
        let one = rows.filter { $0.id == agent }
        return .init(rows: one.isEmpty ? rows : one, updatedAt: now, window: window, all: one.isEmpty)
    }
    #endif
}
