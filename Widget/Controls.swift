import SwiftUI
import WidgetKit
import AppIntents

#if !os(watchOS)
/// Abre o app a partir da Central de Controle. No Mac, "mini" abre o flutuante e "main" o aparelho grande.
struct OpenTokenBarIntent: AppIntent {
    static var title: LocalizedStringResource = "Abrir TokenBar"
    static var openAppWhenRun = true

    @Parameter(title: "O que abrir") var target: String

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
            return ControlReading(text: "Sem dados", detail: "abra o TokenBar", symbol: "gauge.with.dots.needle.0percent")
        }
        let window = Prefs.window == "long" ? "long" : "short"
        let ids = agent == "all" ? Prefs.allProviders : [agent]
        let parts = ids.compactMap { id -> (String, UsageWindow)? in
            guard let w = Prefs.pickFrom(s.provider(id), window) else { return nil }
            return (id, w)
        }
        guard !parts.isEmpty else { return ControlReading(text: "Sem dados", symbol: "gauge.with.dots.needle.0percent") }
        let label = window == "long" ? "7d" : "5h"
        func pct(_ w: UsageWindow) -> String { "\(Int(w.used().rounded()))%" }
        func left(_ w: UsageWindow) -> String {
            guard let r = w.resetsAt else { return "" }
            if w.didReset() { return "OK" }
            let sec = max(0, Int(r.timeIntervalSinceNow))
            let d = sec / 86400, h = (sec % 86400) / 3600, m = (sec % 3600) / 60
            return d > 0 ? "\(d)d \(h)h" : "\(h):" + String(format: "%02d", m)
        }
        let max = parts.map { $0.1.used() }.max() ?? 0
        if agent == "all" {
            return ControlReading(
                text: parts.map { "\($0.0 == "codex" ? "CX" : "CL") \(pct($0.1))" }.joined(separator: " · "),
                detail: "\(label) · reseta " + parts.map { left($0.1) }.joined(separator: " · "),
                symbol: symbol(max))
        }
        let (id, w) = parts[0]
        return ControlReading(text: "\(id == "codex" ? "Codex" : "Claude") \(pct(w))",
                              detail: "\(label) · reseta \(left(w))", symbol: symbol(max))
    }

    /// O ponteiro do ícone acompanha o gasto (0, 33, 50, 67 ou 100%).
    static func symbol(_ pct: Double) -> String {
        let step = pct < 17 ? 0 : pct < 42 ? 33 : pct < 59 ? 50 : pct < 84 ? 67 : 100
        return "gauge.with.dots.needle.\(step)percent"
    }
}

@available(iOS 18.0, macOS 26.0, *)
struct UsageValue: ControlValueProvider {
    var agent: String
    var previewValue: ControlReading { ControlReading(text: agent == "codex" ? "Codex 8%" : agent == "all" ? "CL 42% · CX 8%" : "Claude 42%",
                                                      detail: "5h · reseta 2:40", symbol: "gauge.with.dots.needle.50percent") }
    func currentValue() async throws -> ControlReading { ControlReading.make(agent: agent) }
}

@available(iOS 18.0, macOS 26.0, *)
private func usageControl(kind: String, name: LocalizedStringResource, about: LocalizedStringResource, agent: String) -> some ControlWidgetConfiguration {
    StaticControlConfiguration(kind: kind, provider: UsageValue(agent: agent)) { r in
        ControlWidgetButton(action: OpenTokenBarIntent(target: "mini")) {
            // Duas linhas no tamanho grande: o gasto em cima, quando reseta embaixo.
            Label {
                Text(r.text)
                Text(r.detail)
            } icon: {
                Image(systemName: r.symbol)
            }
        }
    }
    .displayName(name)
    .description(about)
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
                Label("Flutuante", systemImage: "pip")
            }
        }
        .displayName("TokenBar flutuante")
        .description("Abre o TokenBar pequeno, sempre na frente.")
    }
}

@available(iOS 18.0, macOS 26.0, *)
struct OpenMainControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "TokenBarOpenMain") {
            ControlWidgetButton(action: OpenTokenBarIntent(target: "main")) {
                Label("Aparelho", systemImage: "rectangle.inset.filled")
            }
        }
        .displayName("TokenBar aparelho")
        .description("Abre o aparelho grande.")
    }
}
#endif
