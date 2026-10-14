import SwiftUI
import WidgetKit

/// O conteúdo de qualquer widget do TokenBar. Recebe a família como parâmetro para poder ser desenhado fora do WidgetKit.
struct WidgetContent: View {
    var family: WidgetFamily
    var snapshot: UsageSnapshot
    var agent: String      // "all" | "claude" | "codex"
    var window: String     // "short" | "long" | "both"
    var now: Date
    var theme: Theme
    var paired: Bool

    var body: some View {
        let items = WidgetItems.make(snapshot, agent: agent, window: window)
        if snapshot.providers.isEmpty {
            EmptyUsage(paired: paired)
        } else {
            switch family {
            case .accessoryRectangular:
                AccessoryRows(items: Array(items.prefix(3)), now: now, theme: theme)
            case .accessoryCircular:
                AccessoryRing(item: items.first, now: now, theme: theme)
            case .accessoryInline:
                Text(inline(items))
            #if os(watchOS)
            case .accessoryCorner:
                corner(items.first)
            #endif
            #if !os(watchOS)
            case .systemSmall:
                grid(Array(items.prefix(2)), columns: 1, cols: 40, gap: 4)
            case .systemMedium:
                grid(Array(items.prefix(4)), columns: items.count == 1 ? 1 : 2, cols: items.count == 1 ? 80 : 44, gap: 5)
            case .systemLarge, .systemExtraLarge:
                VStack(spacing: 8) {
                    header
                    grid(Array(items.prefix(4)), columns: items.count > 2 ? 2 : 1, cols: items.count > 2 ? 44 : 80, gap: 6)
                }
            #endif
            default:
                grid(Array(items.prefix(2)), columns: 1, cols: 40, gap: 4)
            }
        }
    }

    /// Painéis em grade; cada um recebe a sua fatia exata da área.
    private func grid(_ items: [WidgetItems.Item], columns: Int, cols: Int, gap: CGFloat) -> some View {
        GeometryReader { geo in
            let rows = Int((Double(items.count) / Double(columns)).rounded(.up))
            let w = (geo.size.width - gap * CGFloat(columns - 1)) / CGFloat(columns)
            let h = (geo.size.height - gap * CGFloat(max(rows - 1, 0))) / CGFloat(max(rows, 1))
            VStack(spacing: gap) {
                ForEach(0..<rows, id: \.self) { r in
                    HStack(spacing: gap) {
                        ForEach(0..<columns, id: \.self) { c in
                            let i = r * columns + c
                            if i < items.count {
                                let it = items[i]
                                LEDPanel(window: it.window, title: it.title, providerID: it.providerID,
                                         now: now, theme: theme)
                                    .frame(width: w, height: h)
                                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            } else {
                                Color.clear.frame(width: w, height: h)
                            }
                        }
                    }
                }
            }
        }
    }

    /// Faixa do widget grande: "TOKENBAR" em pontos e há quanto tempo foi lido.
    private var header: some View {
        HStack {
            let b: DotBitmap = {
                var b = DotBitmap(cols: DotFont.width("TOKENBAR"), rows: 7)
                b.draw("TOKENBAR", x: 0, y: 0)
                return b
            }()
            DotCanvas(bitmap: b, dot: 2.6, textColor: .white, fieldColor: .clear, offColor: .clear, round: theme.roundDots)
            Spacer()
            Text(snapshot.updatedAt, style: .relative)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(.white.opacity(0.45))
        }
        .padding(.horizontal, 4)
    }

    private func inline(_ items: [WidgetItems.Item]) -> String {
        items.prefix(2).map { it in
            let p = it.window.map { UsageStyle.percent($0.used(at: now)) } ?? "—"
            return "\(it.providerID == "codex" ? "Codex" : "Claude") \(p)"
        }.joined(separator: " · ")
    }

    #if os(watchOS)
    private func corner(_ it: WidgetItems.Item?) -> some View {
        let p = it?.window?.used(at: now) ?? 0
        let color = theme.fill(it?.providerID ?? "claude", percent: p)
        return Text(it?.window == nil ? "—" : "\(Int(p.rounded()))%")
            .font(.system(size: 14, weight: .heavy, design: .monospaced))
            .widgetCurvesContent()
            .widgetLabel {
                Gauge(value: min(p, 100), in: 0...100) { Text(UsageStyle.shortName(it?.providerID ?? "claude")) }
                    .tint(color)
            }
    }
    #endif
}

/// Tela bloqueada / relógio: até 3 faixas de pontos com nome e %.
struct AccessoryRows: View {
    var items: [WidgetItems.Item]
    var now: Date
    var theme: Theme

    var body: some View {
        GeometryReader { geo in
            let n = max(items.count, 1)
            let gap: CGFloat = 3
            let h = (geo.size.height - gap * CGFloat(n - 1)) / CGFloat(n)
            VStack(spacing: gap) {
                ForEach(items, id: \.key) { it in
                    let p = it.window?.used(at: now) ?? 0
                    let cols = 46
                    let dot = max(1, geo.size.width / CGFloat(cols))
                    let rows = max(9, Int(h / dot))
                    DotCanvas(bitmap: bitmap(it, p: p, cols: cols, rows: rows), dot: dot,
                              textColor: .white, fieldColor: theme.fill(it.providerID, percent: p).opacity(0.8),
                              offColor: .white.opacity(0.1), round: theme.roundDots)
                        .frame(width: geo.size.width, height: h, alignment: .top)
                        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                }
            }
        }
        .widgetAccentable()
    }

    private func bitmap(_ it: WidgetItems.Item, p: Double, cols: Int, rows: Int) -> DotBitmap {
        var b = DotBitmap(cols: cols, rows: rows)
        let filled = Int((min(max(p, 0), 100) / 100 * Double(cols)).rounded())
        for x in 0..<filled { for y in 0..<rows { b.set(x, y, 1) } }
        let y = (rows - 7) / 2
        let t = it.window == nil ? "--" : "\(Int(p.rounded()))%"
        // Nome curto quando o nome inteiro encostaria na %.
        // Todas as faixas usam a mesma forma do nome (todas inteiras ou todas curtas).
        let fits = items.allSatisfy { DotFont.width($0.title) + 3 + 4 * 5 <= cols - 2 }
        let name = fits ? it.title : LEDPanel.abbreviate(it.title)
        b.draw(name, x: 1, y: y)
        b.draw(t, x: cols - 1 - DotFont.width(t), y: y)
        return b
    }
}

/// Anel de pontos com a % no meio.
struct AccessoryRing: View {
    var item: WidgetItems.Item?
    var now: Date
    var theme: Theme

    var body: some View {
        let p = item?.window?.used(at: now) ?? 0
        ZStack {
            DotRing(percent: item?.window == nil ? 0 : p, color: theme.fill(item?.providerID ?? "claude", percent: p))
            VStack(spacing: -2) {
                Text(item?.window == nil ? "—" : "\(Int(p.rounded()))")
                    .font(.system(size: 17, weight: .heavy, design: .monospaced))
                Text(item?.providerID == "codex" ? "CX" : "CL")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
        }
        .widgetAccentable()
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
