#if os(iOS)
import ActivityKit
import SwiftUI
import WidgetKit

/// Atividade ao Vivo: tela bloqueada e Dynamic Island com o uso de cada IA.
/// A contagem é `Text(timerInterval:)`: anda sozinha, sem o app mandar nada.
/// O que aparece (TODAS ou uma IA; 5H, 7D ou as duas) vem pronto no estado; as teclas trocam.
struct UsageLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: UsageActivityAttributes.self) { ctx in
            LiveContent(state: ctx.state, stale: ctx.isStale, theme: Prefs.theme)
                .activityBackgroundTint(.black)
                .activitySystemActionForegroundColor(.white)
                .widgetURL(URL(string: "\(TB.urlScheme)://open"))
                .environment(\.locale, Lang.locale)
        } dynamicIsland: { ctx in
            let theme = Prefs.theme
            let state = ctx.state
            let top = state.top
            let color = top.map { theme.fill($0.id, percent: $0.percent(state.compactWindow)) } ?? .white
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    LEDText(text: "TOKENBAR", color: .white, dot: 1.6)
                        .padding(.leading, 6).padding(.top, 6)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    LiveKeys(state: state, theme: theme, dot: 1.25)
                        .padding(.trailing, 4).padding(.top, 2)
                        .dynamicIsland(verticalPlacement: .belowIfTooWide)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    LiveRows(state: state, theme: theme, place: .island)
                        .padding(.horizontal, 4).padding(.top, 4)
                        .opacity(ctx.isStale ? 0.55 : 1)
                }
            } compactLeading: {
                LiveCompactLeading(state: state, theme: theme)
            } compactTrailing: {
                LiveCompactTrailing(state: state, theme: theme)
            } minimal: {
                LiveMinimal(state: state, theme: theme)
            }
            .keylineTint(color)
            .widgetURL(URL(string: "\(TB.urlScheme)://open"))
        }
        // Apple Watch (Smart Stack) e CarPlay: o cartão pequeno, desenhado em LiveSmall.
        .supplementalActivityFamilies([.small])
    }
}

/// Tela bloqueada (família média) ou o cartão pequeno do relógio.
struct LiveContent: View {
    @Environment(\.activityFamily) private var family
    var state: UsageActivityAttributes.ContentState
    var stale: Bool
    var theme: Theme

    var body: some View {
        if family == .small {
            LiveSmall(state: state, stale: stale, theme: theme)
        } else {
            LiveLockScreen(state: state, stale: stale, theme: theme)
        }
    }
}

/// Cartão pequeno (Apple Watch, ~160×70 pt): uma faixa de LED por IA (ou 5H e 7D de cada),
/// com a contagem ao lado. Sem teclas: no pulso não há onde tocar com folga.
struct LiveSmall: View {
    var state: UsageActivityAttributes.ContentState
    var stale: Bool
    var theme: Theme

    var body: some View {
        MiniLEDRows(lines: Self.lines(state), theme: theme, header: "TOKENBAR",
                    badge: state.all ? MiniLine.windowLabel(state.window)
                        : "\(state.rows.first.map { UsageStyle.abbr($0.id) } ?? "") \(MiniLine.windowLabel(state.window))")
            .padding(.horizontal, 8).padding(.vertical, 6)
            .opacity(stale ? 0.55 : 1)
    }

    static func lines(_ state: UsageActivityAttributes.ContentState) -> [MiniLine] {
        let both = state.window == "both"
        return state.rows.prefix(both ? 2 : 3).flatMap { r -> [MiniLine] in
            if both {
                var out = [MiniLine(id: r.id + "-5", providerID: r.id, name: r.name, tag: "5H", percent: r.used,
                                    resetsAt: r.resetsAt)]
                if let w = r.week {
                    out.append(MiniLine(id: r.id + "-7", providerID: r.id, name: nil, tag: "7D", percent: w,
                                        resetsAt: r.weekResetsAt, groupStart: false, dim: true))
                }
                return out
            }
            return [MiniLine(id: r.id, providerID: r.id, name: r.name, tag: nil, percent: r.percent(state.window),
                             resetsAt: r.resets(state.window), dim: state.window == "long")]
        }
    }
}

// MARK: - Dynamic Island compacta e mínima

/// Esquerda: a primeira IA ("CL 56%"); 7D leva a marquinha.
struct LiveCompactLeading: View {
    var state: UsageActivityAttributes.ContentState
    var theme: Theme

    var body: some View {
        if let first = state.rows.first {
            IslandTag(row: first, window: state.compactWindow, theme: theme,
                      marker: state.window == "long" ? "7D" : nil)
                .padding(.leading, 2)
        }
    }
}

/// Direita: TODAS → a segunda IA; uma IA → a contagem (5H/7D) ou o "7D 30%" (AMBAS).
struct LiveCompactTrailing: View {
    var state: UsageActivityAttributes.ContentState
    var theme: Theme

    var body: some View {
        if state.all && state.rows.count > 1 {
            IslandTag(row: state.rows[1], window: state.compactWindow, theme: theme)
        } else if let row = state.rows.first {
            if state.window == "both", let w = row.week {
                HStack(spacing: 3) {
                    Text("7D").font(.system(size: 9, weight: .heavy, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.55))
                    Text("\(Int(w.rounded()))%").font(.system(size: 13, weight: .heavy, design: .monospaced))
                        .foregroundStyle(theme.fill(row.id, percent: w))
                }
            } else {
                LiveCountdown(resetsAt: row.resets(state.compactWindow))
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white)
                    .frame(width: 58, alignment: .trailing)
            }
        }
    }
}

/// Mínima: a sigla dentro do anel, da IA escolhida (ou da mais gasta).
struct LiveMinimal: View {
    var state: UsageActivityAttributes.ContentState
    var theme: Theme

    var body: some View {
        let top = state.top
        let pct = top?.percent(state.compactWindow) ?? 0
        let color = top.map { theme.fill($0.id, percent: pct) } ?? .white
        ZStack {
            MiniDotRing(percent: pct, color: color)
            Text(top.map { UsageStyle.abbr($0.id) } ?? "-")
                .font(.system(size: 8, weight: .heavy, design: .monospaced))
                .foregroundStyle(color)
        }
        .frame(width: 24, height: 24)
    }
}

// MARK: - Teclas (botões de App Intent)

/// As duas teclas: "IA TODAS >" troca a IA, "5H"/"7D"/"5H 7D" troca a janela.
struct LiveKeys: View {
    var state: UsageActivityAttributes.ContentState
    var theme: Theme
    var dot: CGFloat

    var body: some View {
        let agent = state.all ? Lang.t("TODAS") : (state.rows.first.map { UsageStyle.abbr($0.id) } ?? "-")
        let agentColor = state.all ? Color.white : (state.rows.first.map { theme.base($0.id) } ?? .white)
        HStack(spacing: dot * 3) {
            Button(intent: LiveNextAgentIntent()) {
                LivePill(text: "\(Lang.t("IA")) \(agent) >", color: agentColor, dot: dot)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Lang.t("Trocar a IA"))
            Button(intent: LiveNextWindowIntent()) {
                LivePill(text: LiveChoice.windowLabel(state.window), color: theme.timer.color, dot: dot)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Lang.t("Trocar a janela"))
        }
    }
}

/// Pílula escura com o texto em pontos acesos (a mesma cara das teclas do aparelho).
struct LivePill: View {
    var text: String
    var color: Color
    var dot: CGFloat

    var body: some View {
        LEDText(text: text, color: color, dot: dot)
            .padding(.horizontal, dot * 3.5)
            .padding(.vertical, dot * 2.4)
            .background {
                Capsule().fill(.white.opacity(0.08))
                    .overlay(Capsule().strokeBorder(color.opacity(0.45), lineWidth: 1))
            }
            .contentShape(Capsule())
    }
}

// MARK: - Faixas (ilha aberta e tela bloqueada)

/// Onde as faixas vão: o tamanho dos pontos muda (a tela bloqueada tem mais espaço).
enum LivePlace { case island, lock }

/// Uma IA por bloco; com AMBAS, a de 5h e a de 7d empilhadas. Uma IA só: pontos maiores.
struct LiveRows: View {
    var state: UsageActivityAttributes.ContentState
    var theme: Theme
    var place: LivePlace

    var body: some View {
        let both = state.window == "both"
        let single = state.rows.count == 1
        let dot: CGFloat = switch (place, single, both) {
        case (.island, true, false): 3.6
        case (.island, true, true): 3.0
        case (.island, false, false): 2.4
        case (.island, false, true): 1.9
        case (.lock, true, false): 4.2
        case (.lock, true, true): 3.4
        case (.lock, false, false): 3.0
        case (.lock, false, true): 2.2
        }
        VStack(spacing: both ? dot * 2.2 : 5) {
            ForEach(state.rows) { row in
                if both {
                    VStack(spacing: dot * 0.8) {
                        LiveLine(row: row, window: "short", left: row.name, right: "5H", theme: theme, dot: dot, rows: 7)
                        LiveLine(row: row, window: "long", left: nil, right: "7D", theme: theme, dot: dot, rows: 7)
                    }
                } else {
                    LiveLine(row: row, window: state.window, left: row.name, right: nil, theme: theme, dot: dot, rows: 9)
                }
            }
        }
    }
}

/// Uma faixa de pontos que enche com o gasto (nome e % escritos nela) e, à direita, a contagem.
struct LiveLine: View {
    var row: UsageActivityAttributes.ContentState.Row
    var window: String
    var left: String?
    /// Etiqueta da janela antes da % ("5H 32%"), quando há duas faixas.
    var right: String?
    var theme: Theme
    var dot: CGFloat
    var rows: Int

    var body: some View {
        let pct = row.percent(window)
        let fill = theme.fill(row.id, percent: pct)
        let fs = max(10, dot * CGFloat(rows) * 0.55)
        HStack(spacing: 8) {
            GeometryReader { geo in
                let cols = max(24, Int(geo.size.width / dot))
                DotCanvas(bitmap: bitmap(cols: cols, pct: pct), dot: dot, textColor: theme.text.color,
                          fieldColor: fill.opacity(0.75), offColor: fill.opacity(0.13), round: theme.roundDots)
            }
            .frame(height: CGFloat(rows) * dot)
            LiveCountdown(resetsAt: row.resets(window))
                .font(.system(size: fs, weight: .bold, design: .monospaced))
                .foregroundStyle(window == "long" ? theme.timer.color.opacity(0.75) : theme.timer.color)
                .lineLimit(1).minimumScaleFactor(0.6)
                .frame(width: fs * 5, alignment: .trailing)
        }
    }

    private func bitmap(cols: Int, pct: Double) -> DotBitmap {
        var b = DotBitmap(cols: cols, rows: rows)
        let filled = Int((min(max(pct, 0), 100) / 100 * Double(cols)).rounded())
        for x in 0..<filled { for y in 0..<rows { b.set(x, y, 1) } }
        let num = "\(min(Int(pct.rounded()), 999))%"
        let text = right.map { "\($0) \(num)" } ?? num
        let y = (rows - DotFont.height) / 2
        let rightX = cols - 2 - DotFont.width(text)
        b.draw(text, x: rightX, y: y)
        if let left {
            let name = 2 + DotFont.width(left) + 4 <= rightX ? left : LEDPanel.abbreviate(left)
            if 2 + DotFont.width(name) + 4 <= rightX { b.draw(name, x: 2, y: y) }
        }
        return b
    }
}

/// Tela bloqueada: "TOKENBAR" e as teclas no alto, as faixas embaixo.
struct LiveLockScreen: View {
    var state: UsageActivityAttributes.ContentState
    var stale: Bool
    var theme: Theme

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                LEDText(text: "TOKENBAR", color: .white, dot: 1.6)
                Spacer()
                LiveKeys(state: state, theme: theme, dot: 1.4)
            }
            LiveRows(state: state, theme: theme, place: .lock)
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .opacity(stale ? 0.55 : 1)
    }
}

/// Contagem regressiva até o reset; mais de um dia vira "3D 05H" (o 7D não cabe em hh:mm:ss).
/// Depois do reset (ou sem data), "--:--".
struct LiveCountdown: View {
    var resetsAt: Date?

    var body: some View {
        if let r = resetsAt, r > .now {
            let left = r.timeIntervalSinceNow
            if left >= 86400 {
                Text(String(format: "%dD %02dH", Int(left / 86400), Int(left.truncatingRemainder(dividingBy: 86400) / 3600)))
            } else {
                Text(timerInterval: Date.now...r, countsDown: true, showsHours: true)
                    .multilineTextAlignment(.trailing)
                    .monospacedDigit()
            }
        } else {
            Text("--:--")
        }
    }
}

/// Anel pequeno de pontos (Dynamic Island), aceso até a porcentagem.
struct MiniDotRing: View {
    var percent: Double
    var color: Color

    var body: some View {
        Canvas { ctx, size in
            let n = 12
            let side = min(size.width, size.height)
            let d = side * 0.2
            let r = side / 2 - d / 2
            let c = CGPoint(x: size.width / 2, y: size.height / 2)
            let lit = Int((min(max(percent, 0), 100) / 100 * Double(n)).rounded())
            for i in 0..<n {
                let a = Double(i) / Double(n) * 2 * .pi - .pi / 2
                let p = CGPoint(x: c.x + r * cos(a), y: c.y + r * sin(a))
                ctx.fill(Path(ellipseIn: CGRect(x: p.x - d / 2, y: p.y - d / 2, width: d, height: d)),
                         with: .color(i < lit ? color : .white.opacity(0.2)))
            }
        }
    }
}

/// "CL 56%" na cor da IA: dá para saber de quem é o número sem abrir a ilha.
struct IslandTag: View {
    var row: UsageActivityAttributes.ContentState.Row
    var window: String = "short"
    var theme: Theme
    /// Marquinha da janela ("7D") depois da %.
    var marker: String? = nil

    var body: some View {
        let pct = row.percent(window)
        let c = theme.fill(row.id, percent: pct)
        HStack(spacing: 3) {
            Text(UsageStyle.abbr(row.id))
                .font(.system(size: 10, weight: .heavy, design: .monospaced))
                .foregroundStyle(.black)
                .padding(.horizontal, 3).padding(.vertical, 1)
                .background(RoundedRectangle(cornerRadius: 3).fill(c))
            Text("\(Int(pct.rounded()))%")
                .font(.system(size: 13, weight: .heavy, design: .monospaced))
                .foregroundStyle(c)
            if let marker {
                Text(marker)
                    .font(.system(size: 7, weight: .heavy, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.55))
                    .baselineOffset(5)
            }
        }
    }
}
#endif
