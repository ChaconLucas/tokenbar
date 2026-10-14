import SwiftUI
import WidgetKit
import AppIntents

#if !os(watchOS)
/// Abre o app (no Mac, o flutuante) a partir da Central de Controle.
struct OpenTokenBarIntent: AppIntent {
    static var title: LocalizedStringResource = "Abrir TokenBar"
    static var openAppWhenRun = true

    func perform() async throws -> some IntentResult {
        TB.defaults.set(true, forKey: "openMiniRequest")
        return .result()
    }
}

/// Lê o último retrato gravado pelo app e monta o texto curto: "CL 83% · CX 8%".
@available(iOS 18.0, macOS 26.0, *)
struct UsageControlProvider: ControlValueProvider {
    var previewValue: String { "CL 42% · CX 8%" }

    func currentValue() async throws -> String {
        guard let s = SharedStore.loadSnapshot(), !s.providers.isEmpty else { return "Sem dados" }
        let window = Prefs.window == "long" ? "long" : "short"
        return Prefs.allProviders.compactMap { id -> String? in
            guard let w = Prefs.pickFrom(s.provider(id), window) else { return nil }
            return "\(id == "codex" ? "CX" : "CL") \(Int(w.used().rounded()))%"
        }.joined(separator: " · ")
    }
}

/// Controle da Central de Controle (Mac e iPhone): ícone de medidor + quanto já foi gasto.
@available(iOS 18.0, macOS 26.0, *)
struct UsageControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "TokenBarControl", provider: UsageControlProvider()) { value in
            ControlWidgetButton(action: OpenTokenBarIntent()) {
                Label(value, systemImage: "gauge.with.dots.needle.67percent")
            }
        }
        .displayName("TokenBar")
        .description("Quanto já foi gasto dos limites de IA.")
    }
}
#endif
