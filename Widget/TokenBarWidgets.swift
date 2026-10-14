import SwiftUI
import WidgetKit

struct UsageEntry: TimelineEntry {
    var date: Date
    var snapshot: UsageSnapshot
    var paired: Bool
}

struct UsageProvider: TimelineProvider {
    func placeholder(in context: Context) -> UsageEntry {
        UsageEntry(date: .now, snapshot: .preview, paired: true)
    }

    func getSnapshot(in context: Context, completion: @escaping (UsageEntry) -> Void) {
        let cached = SharedStore.loadSnapshot()
        completion(UsageEntry(date: .now, snapshot: context.isPreview ? (cached ?? .preview) : (cached ?? .empty),
                              paired: SharedStore.loadPairing() != nil || cached != nil))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<UsageEntry>) -> Void) {
        Task {
            let snapshot = await Self.load()
            let now = Date.now
            // Um entry agora e outro em cada reset das próximas horas: a barra zera na hora certa sem rede.
            var dates = [now] + snapshot.upcomingResets(after: now).filter { $0 < now.addingTimeInterval(6 * 3600) }
            dates = Array(dates.prefix(8))
            let paired = SharedStore.loadPairing() != nil || !snapshot.providers.isEmpty
            let entries = dates.map { UsageEntry(date: $0, snapshot: snapshot, paired: paired) }
            completion(Timeline(entries: entries, policy: .after(now.addingTimeInterval(15 * 60))))
        }
    }

    /// No Mac quem escreve é o app (lê do disco); no iPhone e no Watch o widget busca no servidor.
    static func load() async -> UsageSnapshot {
        let cached = SharedStore.loadSnapshot() ?? .empty
        #if os(macOS)
        return cached
        #else
        guard let p = SharedStore.loadPairing(), let fresh = try? await API.fetch(p) else { return cached }
        SharedStore.saveSnapshot(fresh)
        return fresh
        #endif
    }
}

// MARK: - Todos os provedores

struct AllUsageView: View {
    @Environment(\.widgetFamily) private var family
    var entry: UsageEntry

    var body: some View {
        let visible = Prefs.visible
        let providers = entry.snapshot.providers.filter { visible.contains($0.id) }
        Group {
            if entry.snapshot.providers.isEmpty {
                EmptyUsage(paired: entry.paired)
            } else {
                switch family {
                case .accessoryRectangular:
                    VStack(alignment: .leading, spacing: 3) {
                        ForEach(providers) { p in
                            if let w = Prefs.pick(p) { MiniRow(provider: p, window: w, now: entry.date) }
                        }
                    }
                case .systemSmall:
                    DisplayStack(snapshot: entry.snapshot, visible: visible, windowChoice: Prefs.window,
                                 now: entry.date, compact: true, spacing: 6)
                default:
                    DisplayStack(snapshot: entry.snapshot, visible: visible, windowChoice: Prefs.window,
                                 now: entry.date, spacing: 8)
                }
            }
        }
        .containerBackground(for: .widget) { Color.black }
    }
}

/// "5h 32% · reseta 16:40" numa linha, para os espaços apertados.
struct MiniRow: View {
    var provider: ProviderUsage
    var window: UsageWindow
    var now: Date

    var body: some View {
        let pct = window.used(at: now)
        HStack(spacing: 4) {
            Image(systemName: UsageStyle.icon(provider.id)).font(.caption2)
            Gauge(value: min(pct, 100), in: 0...100) { EmptyView() }
                .gaugeStyle(.accessoryLinearCapacity)
                .tint(UsageStyle.color(pct))
            Text(UsageStyle.percent(pct)).font(.caption2.monospacedDigit().weight(.semibold))
        }
    }
}

struct ResetFooter: View {
    var snapshot: UsageSnapshot
    var now: Date

    var body: some View {
        let parts = snapshot.providers.compactMap { p -> String? in
            guard let r = p.primary?.resetsAt, r > now else { return nil }
            return "\(p.id == "codex" ? "Codex" : "Claude") \(UsageStyle.resetText(r, now: now))"
        }
        if !parts.isEmpty {
            Text("reseta: " + parts.joined(separator: " · "))
                .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
        }
    }
}

struct EmptyUsage: View {
    var paired: Bool

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: "gauge.with.dots.needle.33percent")
            Text(paired ? "Sem dados ainda" : "Abra o TokenBar para parear")
                .font(.caption2).multilineTextAlignment(.center)
        }
        .foregroundStyle(.secondary)
    }
}

struct AllUsageWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "TokenBarAll", provider: UsageProvider()) { AllUsageView(entry: $0) }
            .configurationDisplayName("Limites de IA")
            .description("Claude Code e Codex: quanto já foi usado e quando reseta.")
            .supportedFamilies(Self.families)
    }

    static var families: [WidgetFamily] {
        #if os(watchOS)
        [.accessoryRectangular]
        #elseif os(macOS)
        [.systemSmall, .systemMedium, .systemLarge]
        #else
        [.systemSmall, .systemMedium, .systemLarge, .accessoryRectangular]
        #endif
    }
}

// MARK: - Um provedor (complicações redondas e linha do relógio)

struct SingleUsageView: View {
    @Environment(\.widgetFamily) private var family
    var providerID: String
    var entry: UsageEntry

    var body: some View {
        let p = entry.snapshot.provider(providerID)
        let w = Prefs.pick(p)
        let pct = w?.used(at: entry.date) ?? 0
        let short = providerID == "codex" ? "Codex" : "Claude"

        Group {
            switch family {
            case .accessoryInline:
                if let w {
                    Text("\(short) \(UsageStyle.percent(pct))" + (w.resetsAt.map { $0 > entry.date ? " · \(UsageStyle.resetText($0, now: entry.date))" : "" } ?? ""))
                } else {
                    Text("\(short) —")
                }
            #if os(watchOS)
            case .accessoryCorner:
                Image(systemName: UsageStyle.icon(providerID))
                    .widgetLabel {
                        Gauge(value: min(pct, 100), in: 0...100) { Text(short) } currentValueLabel: { Text(UsageStyle.percent(pct)) }
                            .tint(UsageStyle.color(pct))
                    }
            #endif
            case .accessoryCircular:
                Gauge(value: min(pct, 100), in: 0...100) {
                    Image(systemName: UsageStyle.icon(providerID))
                } currentValueLabel: {
                    Text(w == nil ? "—" : "\(Int(pct.rounded()))")
                }
                .gaugeStyle(.accessoryCircularCapacity)
                .tint(UsageStyle.color(pct))
            default:
                if p != nil {
                    DotDisplay(provider: p, providerID: providerID, window: Prefs.pick(p), now: entry.date, compact: true)
                } else {
                    EmptyUsage(paired: entry.paired)
                }
            }
        }
        .containerBackground(for: .widget) { Color.black }
        .widgetURL(URL(string: "\(TB.urlScheme)://open"))
    }
}

struct ClaudeWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "TokenBarClaude", provider: UsageProvider()) {
            SingleUsageView(providerID: "claude", entry: $0)
        }
        .configurationDisplayName("Claude Code")
        .description("Limite de 5 horas do Claude Code.")
        .supportedFamilies(singleFamilies)
    }
}

struct CodexWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "TokenBarCodex", provider: UsageProvider()) {
            SingleUsageView(providerID: "codex", entry: $0)
        }
        .configurationDisplayName("Codex")
        .description("Limite de 5 horas do Codex.")
        .supportedFamilies(singleFamilies)
    }
}

private var singleFamilies: [WidgetFamily] {
    #if os(watchOS)
    [.accessoryCircular, .accessoryCorner, .accessoryInline]
    #elseif os(macOS)
    [.systemSmall]
    #else
    [.systemSmall, .accessoryCircular, .accessoryInline]
    #endif
}

@main
struct TokenBarWidgetBundle: WidgetBundle {
    var body: some Widget {
        AllUsageWidget()
        ClaudeWidget()
        CodexWidget()
    }
}
