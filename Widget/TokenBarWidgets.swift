import SwiftUI
import WidgetKit
import AppIntents

// MARK: - Configuração (segurar o widget → Editar)

enum AgentChoice: String, AppEnum {
    case all, claude, codex, cycle

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "IA / AI"
    static var caseDisplayRepresentations: [AgentChoice: DisplayRepresentation] = [
        // Metadados de App Intents são lidos na compilação (texto fixo): ficam nos dois idiomas.
        .all: "Todas / All", .claude: "Claude Code", .codex: "Codex", .cycle: "Uma por vez / One at a time",
    ]
}

/// Toque na tecla do widget: passa para a próxima IA (modo "Uma por vez").
struct NextAgentIntent: AppIntent {
    static var title: LocalizedStringResource = "Próxima IA / Next AI"
    static var isDiscoverable = false

    func perform() async throws -> some IntentResult {
        let ids = Prefs.allProviders
        let cur = TB.defaults.string(forKey: "widgetCycleAgent") ?? ids[0]
        TB.defaults.set(ids[((ids.firstIndex(of: cur) ?? 0) + 1) % ids.count], forKey: "widgetCycleAgent")
        return .result()
    }
}

enum WindowChoice: String, AppEnum {
    case short, long, both

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Janela / Window"
    static var caseDisplayRepresentations: [WindowChoice: DisplayRepresentation] = [
        .short: "5 horas / 5 hours", .long: "7 dias / 7 days", .both: "As duas / Both",
    ]
}

struct TokenBarConfig: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "TokenBar"
    static var description = IntentDescription("Escolha a IA e a janela de limite. / Choose the AI and the limit window.")

    @Parameter(title: "IA / AI", default: .all) var agent: AgentChoice
    @Parameter(title: "Janela / Window", default: .short) var window: WindowChoice
}

// MARK: - Dados

struct UsageEntry: TimelineEntry {
    var date: Date
    var snapshot: UsageSnapshot
    var paired: Bool
    var agent: String = "all"
    var window: String = "short"
    var cycling = false
}

struct ConfigProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> UsageEntry {
        UsageEntry(date: .now, snapshot: .preview, paired: true)
    }

    func snapshot(for config: TokenBarConfig, in context: Context) async -> UsageEntry {
        let cached = SharedStore.loadSnapshot()
        return UsageEntry(date: .now, snapshot: context.isPreview ? (cached ?? .preview) : (cached ?? .empty),
                          paired: SharedStore.loadPairing() != nil || cached != nil,
                          agent: Self.agent(config), window: config.window.rawValue)
    }

    /// "Uma por vez": a IA atual fica no App Group e a tecla do widget troca.
    static func agent(_ c: TokenBarConfig) -> String {
        c.agent == .cycle ? (TB.defaults.string(forKey: "widgetCycleAgent") ?? Prefs.allProviders[0]) : c.agent.rawValue
    }

    func timeline(for config: TokenBarConfig, in context: Context) async -> Timeline<UsageEntry> {
        let snapshot = await Self.load()
        let now = Date.now
        // Um entry agora e outro em cada reset das próximas horas: a barra zera na hora certa sem rede.
        let dates = Array(([now] + snapshot.upcomingResets(after: now).filter { $0 < now.addingTimeInterval(6 * 3600) }).prefix(8))
        let paired = SharedStore.loadPairing() != nil || !snapshot.providers.isEmpty
        let entries = dates.map {
            UsageEntry(date: $0, snapshot: snapshot, paired: paired, agent: Self.agent(config), window: config.window.rawValue,
                       cycling: config.agent == .cycle)
        }
        return Timeline(entries: entries, policy: .after(now.addingTimeInterval(15 * 60)))
    }

    #if os(watchOS)
    /// No relógio não existe "Editar": o mostrador oferece estas combinações prontas.
    func recommendations() -> [AppIntentRecommendation<TokenBarConfig>] {
        let combos: [(AgentChoice, WindowChoice, String)] = [
            (.all, .short, "Todas · 5h"), (.all, .long, "Todas · 7d"),
            (.claude, .both, "Claude · 5h e 7d"), (.codex, .both, "Codex · 5h e 7d"),
            (.claude, .short, "Claude · 5h"), (.codex, .short, "Codex · 5h"),
        ]
        return combos.map { a, w, name in
            let c = TokenBarConfig()
            c.agent = a
            c.window = w
            return AppIntentRecommendation(intent: c, description: Text(Lang.t(name)))
        }
    }
    #endif

    /// O app grava o último retrato no App Group; com servidor, o widget ainda tenta um número mais novo.
    static func load() async -> UsageSnapshot {
        let cached = SharedStore.loadSnapshot() ?? .empty
        #if os(macOS)
        return cached
        #else
        guard let p = SharedStore.loadPairing(), p.server != nil, let fresh = try? await API.fetch(p),
              fresh.updatedAt > cached.updatedAt else { return cached }
        SharedStore.saveSnapshot(fresh)
        return fresh
        #endif
    }
}

// MARK: - Widget

struct EntryView: View {
    @Environment(\.widgetFamily) private var family
    var entry: UsageEntry

    var body: some View {
        cycleWrap(
            WidgetContent(family: family, snapshot: entry.snapshot, agent: entry.agent, window: entry.window,
                          now: entry.date, theme: Prefs.theme, paired: entry.paired, cycling: entry.cycling)
                .padding(isSystem ? 8 : 0)
        )
            .environment(\.locale, Lang.locale)
            .containerBackground(for: .widget) { Color.black }
            .widgetURL(URL(string: "\(TB.urlScheme)://open"))
    }

    /// "Uma por vez": o widget inteiro é o botão — tocar em qualquer lugar passa para a próxima IA.
    @ViewBuilder private func cycleWrap<V: View>(_ v: V) -> some View {
        #if os(watchOS)
        v
        #else
        if entry.cycling && isSystem {
            Button(intent: NextAgentIntent()) { v }.buttonStyle(.plain)
        } else {
            v
        }
        #endif
    }

    private var isSystem: Bool {
        #if os(watchOS)
        false
        #else
        [.systemSmall, .systemMedium, .systemLarge, .systemExtraLarge].contains(family)
        #endif
    }
}

struct TokenBarWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "TokenBar", intent: TokenBarConfig.self, provider: ConfigProvider()) {
            EntryView(entry: $0)
        }
        // Nome e descrição da galeria: lidos quando o sistema carrega a extensão (no idioma escolhido naquela hora).
        .configurationDisplayName(Lang.t("Personalizado"))
        .description(Lang.t("Escolha a IA e a janela (segure o widget → Editar)."))
        .supportedFamilies(Self.families)
        .contentMarginsDisabled()
    }

    static var families: [WidgetFamily] {
        #if os(watchOS)
        [.accessoryRectangular, .accessoryCircular, .accessoryCorner, .accessoryInline]
        #elseif os(macOS)
        [.systemSmall, .systemMedium, .systemLarge]
        #else
        [.systemSmall, .systemMedium, .systemLarge, .accessoryRectangular, .accessoryCircular, .accessoryInline]
        #endif
    }
}

// MARK: - Widgets prontos (aparecem direto na galeria; empilhe e deslize entre eles)

struct PresetProvider: TimelineProvider {
    var agent: String
    var window: String

    func placeholder(in context: Context) -> UsageEntry {
        UsageEntry(date: .now, snapshot: .preview, paired: true, agent: agent, window: window)
    }

    func getSnapshot(in context: Context, completion: @escaping (UsageEntry) -> Void) {
        let cached = SharedStore.loadSnapshot()
        completion(UsageEntry(date: .now, snapshot: context.isPreview ? (cached ?? .preview) : (cached ?? .empty),
                              paired: true, agent: agent, window: window))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<UsageEntry>) -> Void) {
        let agent = agent, window = window
        Task {
            let snapshot = await ConfigProvider.load()
            let now = Date.now
            let dates = Array(([now] + snapshot.upcomingResets(after: now).filter { $0 < now.addingTimeInterval(6 * 3600) }).prefix(8))
            let paired = SharedStore.loadPairing() != nil || !snapshot.providers.isEmpty
            let entries = dates.map { UsageEntry(date: $0, snapshot: snapshot, paired: paired, agent: agent, window: window) }
            completion(Timeline(entries: entries, policy: .after(now.addingTimeInterval(15 * 60))))
        }
    }
}

private func preset(kind: String, name: String, about: String, agent: String, window: String) -> some WidgetConfiguration {
    StaticConfiguration(kind: kind, provider: PresetProvider(agent: agent, window: window)) { EntryView(entry: $0) }
        .configurationDisplayName(Lang.t(name))
        .description(Lang.t(about))
        .supportedFamilies(TokenBarWidget.families)
        .contentMarginsDisabled()
}

struct ClaudeBothWidget: Widget {
    var body: some WidgetConfiguration {
        preset(kind: "TokenBarClaudeBoth", name: "Claude · 5h e 7d", about: "As duas janelas do Claude Code.",
               agent: "claude", window: "both")
    }
}

struct CodexBothWidget: Widget {
    var body: some WidgetConfiguration {
        preset(kind: "TokenBarCodexBoth", name: "Codex · 5h e 7d", about: "As duas janelas do Codex.",
               agent: "codex", window: "both")
    }
}

struct AllShortWidget: Widget {
    var body: some WidgetConfiguration {
        preset(kind: "TokenBarAllShort", name: "Todas · 5h", about: "Todas as IAs, janela de 5 horas.",
               agent: "all", window: "short")
    }
}

struct AllBothWidget: Widget {
    var body: some WidgetConfiguration {
        preset(kind: "TokenBarAllBoth", name: "Todas · 5h e 7d", about: "Todas as IAs, as duas janelas.",
               agent: "all", window: "both")
    }
}

@main
struct TokenBarWidgetBundle: WidgetBundle {
    var body: some Widget {
        AllBothWidget()
        AllShortWidget()
        ClaudeBothWidget()
        CodexBothWidget()
        TokenBarWidget()
        #if !os(watchOS)
        #if !os(watchOS)
        UsageControl()
        ClaudeControl()
        CodexControl()
        OpenMiniControl()
        OpenMainControl()
        #endif
        #endif
    }
}
