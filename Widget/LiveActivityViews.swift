#if os(iOS)
import ActivityKit
import SwiftUI
import WidgetKit

/// Atividade ao Vivo: tela bloqueada e Dynamic Island com o uso de cada IA.
/// A contagem é `Text(timerInterval:)`: anda sozinha, sem o app mandar nada.
struct UsageLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: UsageActivityAttributes.self) { ctx in
            LiveLockScreen(state: ctx.state, stale: ctx.isStale, theme: Prefs.theme)
                .activityBackgroundTint(.black)
                .activitySystemActionForegroundColor(.white)
                .widgetURL(URL(string: "\(TB.urlScheme)://open"))
                .environment(\.locale, Lang.locale)
        } dynamicIsland: { ctx in
            let theme = Prefs.theme
            let top = ctx.state.top
            let color = top.map { theme.fill($0.id, percent: $0.used) } ?? .white
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    LEDText(text: "TOKENBAR", color: .white, dot: 1.7)
                        .padding(.leading, 6).padding(.top, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    LEDText(text: "5H", color: .white.opacity(0.5), dot: 1.7)
                        .padding(.trailing, 6).padding(.top, 4)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: 5) {
                        ForEach(ctx.state.rows) { LiveRow(row: $0, theme: theme, dot: 2.4, timerWidth: 66) }
                    }
                    .padding(.horizontal, 4).padding(.top, 2)
                    .opacity(ctx.isStale ? 0.55 : 1)
                }
            } compactLeading: {
                HStack(spacing: 4) {
                    MiniDotRing(percent: top?.used ?? 0, color: color).frame(width: 18, height: 18)
                    Text(top.map { "\(Int($0.used.rounded()))%" } ?? "--")
                        .font(.system(size: 13, weight: .heavy, design: .monospaced))
                        .foregroundStyle(color)
                }
                .padding(.leading, 2)
            } compactTrailing: {
                LiveCountdown(resetsAt: top?.resetsAt)
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white)
                    .frame(width: 58, alignment: .trailing)
            } minimal: {
                ZStack {
                    MiniDotRing(percent: top?.used ?? 0, color: color)
                    Text(top.map { "\(Int($0.used.rounded()))" } ?? "-")
                        .font(.system(size: 9, weight: .heavy, design: .monospaced))
                        .foregroundStyle(color)
                }
                .frame(width: 24, height: 24)
            }
            .keylineTint(color)
            .widgetURL(URL(string: "\(TB.urlScheme)://open"))
        }
    }
}

/// Tela bloqueada: "TOKENBAR" em pontos e uma faixa de LED por IA, com a contagem ao lado.
struct LiveLockScreen: View {
    var state: UsageActivityAttributes.ContentState
    var stale: Bool
    var theme: Theme

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                LEDText(text: "TOKENBAR", color: .white, dot: 1.6)
                Spacer()
                LEDText(text: "5H", color: .white.opacity(0.45), dot: 1.6)
            }
            ForEach(state.rows) { LiveRow(row: $0, theme: theme, dot: 3, timerWidth: 76) }
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .opacity(stale ? 0.55 : 1)
    }
}

/// Uma IA: faixa de pontos que enche com o gasto (nome e % escritos nela) e, à direita, a contagem e o 7D.
struct LiveRow: View {
    var row: UsageActivityAttributes.ContentState.Row
    var theme: Theme
    var dot: CGFloat
    var timerWidth: CGFloat

    static let rows = 9

    var body: some View {
        let fill = theme.fill(row.id, percent: row.used)
        HStack(spacing: 8) {
            GeometryReader { geo in
                let cols = max(24, Int(geo.size.width / dot))
                DotCanvas(bitmap: bitmap(cols: cols), dot: dot, textColor: theme.text.color,
                          fieldColor: fill.opacity(0.75), offColor: fill.opacity(0.13), round: theme.roundDots)
            }
            .frame(height: CGFloat(Self.rows) * dot)
            VStack(alignment: .trailing, spacing: 0) {
                LiveCountdown(resetsAt: row.resetsAt)
                    .font(.system(size: dot * 4.6, weight: .bold, design: .monospaced))
                    .foregroundStyle(theme.timer.color)
                if let w = row.week {
                    Text("7D \(Int(w.rounded()))%")
                        .font(.system(size: dot * 3, weight: .semibold, design: .monospaced))
                        .foregroundStyle(theme.fill(row.id, percent: w).opacity(0.8))
                }
            }
            .frame(width: timerWidth, alignment: .trailing)
        }
    }

    private func bitmap(cols: Int) -> DotBitmap {
        var b = DotBitmap(cols: cols, rows: Self.rows)
        let filled = Int((min(max(row.used, 0), 100) / 100 * Double(cols)).rounded())
        for x in 0..<filled { for y in 0..<Self.rows { b.set(x, y, 1) } }
        let pct = "\(min(Int(row.used.rounded()), 999))%"
        let right = cols - 2 - DotFont.width(pct)
        let name = 2 + DotFont.width(row.name) + 4 <= right ? row.name : LEDPanel.abbreviate(row.name)
        b.draw(name, x: 2, y: 1)
        b.draw(pct, x: right, y: 1)
        return b
    }
}

/// Contagem regressiva até o reset da janela de 5h; depois do reset (ou sem data), "--:--".
struct LiveCountdown: View {
    var resetsAt: Date?

    var body: some View {
        if let r = resetsAt, r > .now {
            Text(timerInterval: Date.now...r, countsDown: true, showsHours: true)
                .multilineTextAlignment(.trailing)
                .monospacedDigit()
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
#endif
