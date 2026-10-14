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
                    // Mini display de LED: uma faixa por IA, o fundo enche com o gasto.
                    AccessoryDots(snapshot: entry.snapshot, ids: providers.map(\.id), now: entry.date)
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
                // Anel de pontos: acende no sentido horário até o gasto.
                ZStack {
                    DotRing(percent: w == nil ? 0 : pct, color: Prefs.theme.fill(providerID, percent: pct))
                    VStack(spacing: -2) {
                        Text(w == nil ? "—" : "\(Int(pct.rounded()))")
                            .font(.system(size: 17, weight: .heavy, design: .monospaced))
                        Text(providerID == "codex" ? "CX" : "CL")
                            .font(.system(size: 8, weight: .bold, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }
                .widgetAccentable()
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

/// Faixas de pontos para a complicação retangular e a Pilha Inteligente.
struct AccessoryDots: View {
    var snapshot: UsageSnapshot
    var ids: [String]
    var now: Date

    var body: some View {
        let theme = Prefs.theme
        VStack(spacing: 3) {
            ForEach(ids, id: \.self) { id in
                let w = Prefs.pick(snapshot.provider(id))
                let pct = w?.used(at: now) ?? 0
                GeometryReader { geo in
                    let cols = 44
                    let dot = max(1, geo.size.width / CGFloat(cols))
                    let rows = max(9, Int((geo.size.height.isFinite ? geo.size.height : 0) / dot))
                    DotCanvas(bitmap: bitmap(id: id, w: w, pct: pct, cols: cols, rows: rows), dot: dot,
                              textColor: .white, fieldColor: theme.fill(id, percent: pct).opacity(0.75),
                              offColor: .white.opacity(0.08), round: theme.roundDots)
                }
            }
        }
        .widgetAccentable()
    }

    private func bitmap(id: String, w: UsageWindow?, pct: Double, cols: Int, rows: Int) -> DotBitmap {
        var b = DotBitmap(cols: cols, rows: rows)
        let filled = Int((min(max(pct, 0), 100) / 100 * Double(cols)).rounded())
        for x in 0..<filled { for y in 0..<rows { b.set(x, y, 1) } }
        let y = (rows - 7) / 2
        b.draw(id == "codex" ? "CODEX" : "CLAUDE", x: 1, y: y)
        let t = w == nil ? "--" : "\(Int(pct.rounded()))%"
        b.draw(t, x: cols - 1 - DotFont.width(t), y: y)
        return b
    }
}

/// Anel feito de pontos, aceso até a porcentagem.
struct DotRing: View {
    var percent: Double
    var color: Color

    var body: some View {
        Canvas { ctx, size in
            let n = 24
            let r = min(size.width, size.height) / 2 - 3
            let c = CGPoint(x: size.width / 2, y: size.height / 2)
            let lit = Int((min(max(percent, 0), 100) / 100 * Double(n)).rounded())
            for i in 0..<n {
                let a = Double(i) / Double(n) * 2 * .pi - .pi / 2
                let p = CGPoint(x: c.x + r * cos(a), y: c.y + r * sin(a))
                let d: CGFloat = 4
                ctx.fill(Path(ellipseIn: CGRect(x: p.x - d / 2, y: p.y - d / 2, width: d, height: d)),
                         with: .color(i < lit ? color : .white.opacity(0.18)))
            }
        }
    }
}
