import SwiftUI
import WidgetKit
import AppIntents

#if !os(watchOS)
/// Abre o app a partir da Central de Controle. No Mac, "mini" abre o flutuante e "main" o aparelho grande.
struct OpenTokenBarIntent: AppIntent {
    static var title: LocalizedStringResource = "Abrir TokenBar / Open TokenBar"
    static var openAppWhenRun = true

    @Parameter(title: "O que abrir / What to open") var target: String

    init() { target = "mini" }
    init(target: String) { self.target = target }

    func perform() async throws -> some IntentResult {
        TB.defaults.set(target, forKey: "openRequest")
        return .result()
    }
}

/// O que um controle mostra: título, linha de baixo (reset) e o ícone de ponteiro na posição do gasto.
struct ControlReading {
    var text: String
    var detail: String = ""
    var symbol: String

    static func make(agent: String) -> ControlReading {
        guard let s = SharedStore.loadSnapshot(), !s.providers.isEmpty else {
            return ControlReading(text: Lang.t("Sem dados"), detail: Lang.t("abra o TokenBar"), symbol: "tb.ring.0")
        }
        let window = Prefs.window == "long" ? "long" : "short"
        let ids = agent == "all" ? Prefs.allProviders : [agent]
        let parts = ids.compactMap { id -> (String, UsageWindow)? in
            guard let w = Prefs.pickFrom(s.provider(id), window) else { return nil }
            return (id, w)
        }
        guard !parts.isEmpty else { return ControlReading(text: Lang.t("Sem dados"), symbol: "tb.ring.0") }
        let label = window == "long" ? "7d" : "5h"
        func pct(_ w: UsageWindow) -> String { "\(Int(w.used().rounded()))%" }
        func left(_ w: UsageWindow) -> String {
            guard let r = w.resetsAt else { return "" }
            if w.didReset() { return "OK" }
            let sec = max(0, Int(r.timeIntervalSinceNow))
            let d = sec / 86400, h = (sec % 86400) / 3600, m = (sec % 3600) / 60
            return d > 0 ? "\(d)d \(h)h" : "\(h):" + String(format: "%02d", m)
        }
        let top = parts.map { $0.1.used() }.max() ?? 0
        if agent == "all" {
            return ControlReading(
                text: parts.map { "\(UsageStyle.abbr($0.0)) \(pct($0.1))" }.joined(separator: " · "),
                detail: parts.map { left($0.1) }.joined(separator: " · "),
                symbol: symbol(top))
        }
        let (id, w) = parts[0]
        return ControlReading(text: "\(UsageStyle.displayName(id)) \(pct(w))",
                              detail: "\(label) · \(left(w))", symbol: symbol(top))
    }

    /// Anel de 12 pontos de LED, aceso no sentido horário até o gasto (símbolos próprios tb.ring.0…12).
    static func symbol(_ pct: Double) -> String {
        "tb.ring.\(min(12, max(0, Int((pct / 100 * 12).rounded()))))"
    }
}

@available(iOS 18.0, macOS 26.0, *)
struct UsageValue: ControlValueProvider {
    var agent: String
    var previewValue: ControlReading { ControlReading(text: agent == "codex" ? "Codex 8%" : agent == "all" ? "CL 42% · CX 8%" : "Claude 42%",
                                                      detail: "2:40 · 0:19", symbol: "tb.ring.6") }
    func currentValue() async throws -> ControlReading { ControlReading.make(agent: agent) }
}

@available(iOS 18.0, macOS 26.0, *)
private func usageControl(kind: String, name: String, about: String, agent: String) -> some ControlWidgetConfiguration {
    StaticControlConfiguration(kind: kind, provider: UsageValue(agent: agent)) { r in
        ControlWidgetButton(action: OpenTokenBarIntent(target: "mini")) {
            // Duas linhas no tamanho grande: o gasto em cima, quando reseta embaixo.
            Label {
                Text(r.text)
                Text(r.detail)
            } icon: {
                Image(r.symbol)
            }
        }
    }
    .displayName(LocalizedStringResource(String.LocalizationValue(Lang.t(name))))
    .description(LocalizedStringResource(String.LocalizationValue(Lang.t(about))))
}

/// Todas as IAs: "CL 83% · CX 8%".
@available(iOS 18.0, macOS 26.0, *)
struct UsageControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        usageControl(kind: "TokenBarControl", name: "TokenBar", about: "Quanto já foi gasto de cada IA.", agent: "all")
    }
}

@available(iOS 18.0, macOS 26.0, *)
struct ClaudeControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        usageControl(kind: "TokenBarClaudeControl", name: "Claude", about: "Uso do Claude Code.", agent: "claude")
    }
}

@available(iOS 18.0, macOS 26.0, *)
struct CodexControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        usageControl(kind: "TokenBarCodexControl", name: "Codex", about: "Uso do Codex.", agent: "codex")
    }
}

/// Atalhos: abrir o flutuante ou o aparelho.
@available(iOS 18.0, macOS 26.0, *)
struct OpenMiniControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "TokenBarOpenMini") {
            ControlWidgetButton(action: OpenTokenBarIntent(target: "mini")) {
                Label(Lang.t("Flutuante"), systemImage: "pip")
            }
        }
        .displayName(LocalizedStringResource(String.LocalizationValue(Lang.t("TokenBar flutuante"))))
        .description(LocalizedStringResource(String.LocalizationValue(Lang.t("Abre o TokenBar pequeno, sempre na frente."))))
    }
}

@available(iOS 18.0, macOS 26.0, *)
struct OpenMainControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "TokenBarOpenMain") {
            ControlWidgetButton(action: OpenTokenBarIntent(target: "main")) {
                Label(Lang.t("Aparelho"), systemImage: "rectangle.inset.filled")
            }
        }
        .displayName(LocalizedStringResource(String.LocalizationValue(Lang.t("TokenBar aparelho"))))
        .description(LocalizedStringResource(String.LocalizationValue(Lang.t("Abre o aparelho grande."))))
    }
}
#endif
