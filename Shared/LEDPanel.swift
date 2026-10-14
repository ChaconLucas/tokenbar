import SwiftUI

/// Painel de LED genérico (widgets): título em cima, reset apagado, % grande; o fundo enche com o gasto.
/// Escolhe sozinho onde cabe cada coisa pela quantidade de pontos disponível.
struct LEDPanel: View {
    var window: UsageWindow?
    var title: String
    var providerID: String
    var now: Date
    var theme: Theme
    /// Mantidos por compatibilidade com quem já chama assim.
    var minCols: Int = 44
    var maxScale: Int = 3
    /// Escala do número; se nil, o painel escolhe sozinho. Widgets passam a mesma para todos os painéis.
    var scale: Int? = nil
    /// Título mais longo do widget: garante que título e tempo caibam em todos os painéis.
    var longestTitle: String? = nil

    var body: some View {
        let p = window?.used(at: now) ?? 0
        let level = theme.fill(providerID, percent: p)
        GeometryReader { geo in
            let w = geo.size.width.isFinite ? geo.size.width : 0
            let h = geo.size.height.isFinite ? geo.size.height : 0
            let t = longestTitle ?? title
            let k = scale ?? LEDPanel.bestScale(width: w, height: h, longestTitle: t, maxScale: maxScale)
            let dot = LEDPanel.dot(width: w, height: h, k: k, longestTitle: t)
            let rows = max(LEDPanel.rows(for: k), Int(h / dot))
            let cols = max(10, Int(w / dot))
            DotCanvas(bitmap: bitmap(p, k: k, cols: min(cols, 300), rows: min(rows, 200)), dot: dot,
                      textColor: theme.text.color, fieldColor: level.opacity(0.62), offColor: level.opacity(0.10),
                      round: theme.roundDots)
                .shadow(color: level.opacity(0.3 * theme.glow), radius: 2 * theme.glow)
                .frame(width: w, height: h, alignment: .topLeading)
        }
        .accessibilityElement()
        .accessibilityLabel("\(title) \(UsageStyle.percent(p))")
    }

    // Grade fixa: margem 2 · título 7 · vão 3 · número 7k · margem 2.
    static func rows(for k: Int) -> Int { 2 + 7 + 3 + 7 * k + 2 }

    /// Colunas que a escala k precisa: "100%" e "TÍTULO  0:00" inteiros.
    static func colsNeeded(k: Int, longestTitle: String) -> Int {
        max(DotFont.width("100%", scale: k) + 4, 2 + DotFont.width(longestTitle) + 6 + DotFont.width("0:00") + 2)
    }

    /// O ponto cabe na altura (grade da escala k) e na largura (colunas necessárias).
    static func dot(width w: CGFloat, height h: CGFloat, k: Int, longestTitle: String) -> CGFloat {
        max(1, min(h / CGFloat(rows(for: k)), w / CGFloat(colsNeeded(k: k, longestTitle: longestTitle))))
    }

    /// Maior escala cujo ponto ainda fica visível (o número cresce o quanto der sem apertar nada).
    static func bestScale(width w: CGFloat, height h: CGFloat, longestTitle: String, maxScale: Int = 3) -> Int {
        guard w > 0, h > 0 else { return 1 }
        for k in stride(from: maxScale, through: 2, by: -1)
        where dot(width: w, height: h, k: k, longestTitle: longestTitle) >= 1.9 { return k }
        return 1
    }

    private func bitmap(_ p: Double, k: Int, cols: Int, rows: Int) -> DotBitmap {
        var b = DotBitmap(cols: cols, rows: rows)
        let filled = Int((min(max(p, 0), 100) / 100 * Double(cols)).rounded())
        for x in 0..<filled { for y in 0..<rows { b.set(x, y, 1) } }

        // Título à esquerda; tempo (mais apagado) à direita na mesma linha, se couber.
        let name = 2 + DotFont.width(title) + 6 + DotFont.width(timeText) + 2 <= cols ? title : LEDPanel.abbreviate(title)
        b.draw(name, x: 2, y: 2)
        if window != nil, 2 + DotFont.width(name) + 6 + DotFont.width(timeText) + 2 <= cols {
            b.draw(timeText, x: cols - 2 - DotFont.width(timeText), y: 2, value: 3)
        }
        let big = window == nil ? "--" : "\(min(Int(p.rounded()), 999))%"
        // Número centrado no espaço abaixo do título.
        let y = 12 + max(0, (rows - 2 - 12 - 7 * k) / 2)
        b.draw(big, x: (cols - DotFont.width(big, scale: k)) / 2, y: y, scale: k)
        return b
    }

    /// CLAUDE → CL, CODEX → CX (o resto fica igual).
    static func abbreviate(_ s: String) -> String {
        s.replacingOccurrences(of: "CLAUDE", with: "CL").replacingOccurrences(of: "CODEX", with: "CX")
    }

    private var timeText: String {
        guard let w = window, let r = w.resetsAt else { return "" }
        if w.didReset(at: now) { return "OK" }
        let s = max(0, Int(r.timeIntervalSince(now)))
        let d = s / 86400, h = (s % 86400) / 3600, m = (s % 3600) / 60
        return d > 0 ? "\(d)D" : "\(h):" + String(format: "%02d", m)
    }
}

/// O que um widget mostra: quais IAs e quais janelas.
enum WidgetItems {
    struct Item: Hashable {
        var key: String
        var providerID: String
        var window: UsageWindow?
        var title: String
    }

    /// agent: "all" | "claude" | "codex"; window: "short" | "long" | "both".
    static func make(_ s: UsageSnapshot, agent: String, window: String, showName: Bool = false) -> [Item] {
        let ids = agent == "all" ? Prefs.allProviders : [agent]
        var out: [Item] = []
        for id in ids {
            let p = s.provider(id)
            let ws = p?.windows ?? []
            let picked: [UsageWindow?] = window == "both" ? (ws.isEmpty ? [nil] : ws.map { $0 })
                : [Prefs.pickFrom(p, window)]
            for w in picked {
                // Uma IA só: o título é a janela. Várias: o nome da IA (+ janela se mostrar as duas).
                let title: String
                if ids.count == 1 && showName { title = (id == "codex" ? "CX " : "CL ") + (w?.label.uppercased() ?? "") }
                else if ids.count == 1 { title = w?.label.uppercased() ?? UsageStyle.shortName(id) }
                else if window == "both" { title = (id == "codex" ? "CX " : "CL ") + (w?.label.uppercased() ?? "") }
                else { title = UsageStyle.shortName(id) }
                out.append(Item(key: "\(id)-\(w?.id ?? "none")", providerID: id, window: w, title: title))
            }
        }
        return out
    }
}

/// Faixa fina de LED: nome à esquerda, tempo apagado e % à direita; o fundo enche com o gasto.
struct SlimRow: View {
    var item: WidgetItems.Item
    var now: Date
    var theme: Theme
    var showTime = true

    var body: some View {
        let p = item.window?.used(at: now) ?? 0
        GeometryReader { geo in
            let rows = 11
            let dot = max(1, geo.size.height / CGFloat(rows))
            let cols = max(20, Int(geo.size.width / dot))
            DotCanvas(bitmap: bitmap(p, cols: cols, rows: rows), dot: dot, textColor: theme.text.color,
                      fieldColor: theme.fill(item.providerID, percent: p).opacity(0.65),
                      offColor: theme.fill(item.providerID, percent: p).opacity(0.10), round: theme.roundDots)
                .frame(width: geo.size.width, height: geo.size.height, alignment: .leading)
        }
    }

    private func bitmap(_ p: Double, cols: Int, rows: Int) -> DotBitmap {
        var b = DotBitmap(cols: cols, rows: rows)
        let filled = Int((min(max(p, 0), 100) / 100 * Double(cols)).rounded())
        for x in 0..<filled { for y in 0..<rows { b.set(x, y, 1) } }
        let big = item.window == nil ? "--" : "\(Int(p.rounded()))%"
        let right = cols - 2 - DotFont.width(big)
        // Nome inteiro só se não encostar na %.
        let name = 2 + DotFont.width(item.title) + 8 <= right - (showTime ? DotFont.width(time) + 4 : 0)
            ? item.title : LEDPanel.abbreviate(item.title)
        b.draw(name, x: 2, y: 2)
        b.draw(big, x: right, y: 2)
        let t = time
        if showTime, 2 + DotFont.width(name) + 4 + DotFont.width(t) + 4 <= right {
            b.draw(t, x: right - 4 - DotFont.width(t), y: 2, value: 3)
        }
        return b
    }

    private var time: String {
        guard let w = item.window, let r = w.resetsAt else { return "" }
        if w.didReset(at: now) { return "OK" }
        let s = max(0, Int(r.timeIntervalSince(now)))
        let d = s / 86400, h = (s % 86400) / 3600, m = (s % 3600) / 60
        return d > 0 ? "\(d)D" : "\(h):" + String(format: "%02d", m)
    }
}
