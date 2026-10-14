import SwiftUI
import WidgetKit
import AppIntents

// MARK: - Configuração (segurar o widget → Editar)

enum AgentChoice: String, AppEnum {
    case all, claude, codex

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "IA"
    static var caseDisplayRepresentations: [AgentChoice: DisplayRepresentation] = [
        .all: "Todas", .claude: "Claude Code", .codex: "Codex",
    ]
}

enum WindowChoice: String, AppEnum {
    case short, long, both

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Janela"
    static var caseDisplayRepresentations: [WindowChoice: DisplayRepresentation] = [
        .short: "5 horas", .long: "7 dias", .both: "As duas",
    ]
}

struct TokenBarConfig: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "TokenBar"
    static var description = IntentDescription("Escolha a IA e a janela de limite.")

    @Parameter(title: "IA", default: .all) var agent: AgentChoice
    @Parameter(title: "Janela", default: .short) var window: WindowChoice
}

// MARK: - Dados

struct UsageEntry: TimelineEntry {
    var date: Date
    var snapshot: UsageSnapshot
    var paired: Bool
    var agent: String = "all"
    var window: String = "short"
}

struct ConfigProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> UsageEntry {
        UsageEntry(date: .now, snapshot: .preview, paired: true)
    }

    func snapshot(for config: TokenBarConfig, in context: Context) async -> UsageEntry {
        let cached = SharedStore.loadSnapshot()
        return UsageEntry(date: .now, snapshot: context.isPreview ? (cached ?? .preview) : (cached ?? .empty),
                          paired: SharedStore.loadPairing() != nil || cached != nil,
                          agent: config.agent.rawValue, window: config.window.rawValue)
    }

    func timeline(for config: TokenBarConfig, in context: Context) async -> Timeline<UsageEntry> {
        let snapshot = await Self.load()
        let now = Date.now
        // Um entry agora e outro em cada reset das próximas horas: a barra zera na hora certa sem rede.
        let dates = Array(([now] + snapshot.upcomingResets(after: now).filter { $0 < now.addingTimeInterval(6 * 3600) }).prefix(8))
        let paired = SharedStore.loadPairing() != nil || !snapshot.providers.isEmpty
        let entries = dates.map {
            UsageEntry(date: $0, snapshot: snapshot, paired: paired, agent: config.agent.rawValue, window: config.window.rawValue)
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
            return AppIntentRecommendation(intent: c, description: Text(name))
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
        WidgetContent(family: family, snapshot: entry.snapshot, agent: entry.agent, window: entry.window,
                      now: entry.date, theme: Prefs.theme, paired: entry.paired)
            .padding(isSystem ? 8 : 0)
            .containerBackground(for: .widget) { Color.black }
            .widgetURL(URL(string: "\(TB.urlScheme)://open"))
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
        .configurationDisplayName("TokenBar")
        .description("Quanto já foi gasto dos limites de IA e quando reseta.")
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

@main
struct TokenBarWidgetBundle: WidgetBundle {
    var body: some Widget {
        TokenBarWidget()
    }
}
