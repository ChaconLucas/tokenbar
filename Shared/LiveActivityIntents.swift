#if os(iOS)
import AppIntents
import Foundation

// Botões da Dynamic Island aberta e da tela bloqueada. LiveActivityIntent roda no processo do app
// (este arquivo entra no app e no widget): grava a escolha no App Group e redesenha a Atividade no ar.

/// "IA >": TODAS → cada IA → TODAS.
struct LiveNextAgentIntent: LiveActivityIntent {
    // Metadados de App Intents são lidos na compilação (texto fixo): ficam nos dois idiomas.
    static var title: LocalizedStringResource = "Trocar a IA / Switch AI"
    static var isDiscoverable = false

    func perform() async throws -> some IntentResult {
        LiveChoice.cycleAgent()
        await LiveActivityRefresher.apply()
        return .result()
    }
}

/// "5H/7D": 5H → 7D → AMBAS → 5H.
struct LiveNextWindowIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Trocar a janela / Switch window"
    static var isDiscoverable = false

    func perform() async throws -> some IntentResult {
        LiveChoice.cycleWindow()
        await LiveActivityRefresher.apply()
        return .result()
    }
}
#endif
