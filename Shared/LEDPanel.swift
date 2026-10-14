import SwiftUI

/// Painel de LED genérico (widgets): título em cima, reset apagado, % grande; o fundo enche com o gasto.
/// Escolhe sozinho onde cabe cada coisa pela quantidade de pontos disponível.
struct LEDPanel: View {
    var window: UsageWindow?
    var title: String
    var providerID: String
    var now: Date
    var theme: Theme
    /// Mínimo de colunas (cabe "CLAUDE" + folga); o ponto sai do espaço disponível.
    var minCols: Int = 44
    var maxScale: Int = 3

    var body: some View {
        let p = window?.used(at: now) ?? 0
        let level = theme.fill(providerID, percent: p)
        GeometryReader { geo in
            let w = geo.size.width.isFinite ? geo.size.width : 0
            let h = geo.size.height.isFinite ? geo.size.height : 0
            // Ponto pela altura (~26 linhas), mas nunca com menos colunas que o mínimo.
            let dot = max(1, min(h / 26, w / CGFloat(minCols)))
            let cols = max(minCols, Int(w / dot)), rows = max(12, Int(h / dot))
            DotCanvas(bitmap: bitmap(p, cols: min(cols, 300), rows: min(rows, 200)), dot: dot,
                      textColor: theme.text.color, fieldColor: level.opacity(0.62), offColor: level.opacity(0.10),
                      round: theme.roundDots)
                .shadow(color: level.opacity(0.3 * theme.glow), radius: 2 * theme.glow)
                .frame(width: w, height: h, alignment: .topLeading)
        }
        .accessibilityElement()
        .accessibilityLabel("\(title) \(UsageStyle.percent(p))")
    }

    private func bitmap(_ p: Double, cols: Int, rows: Int) -> DotBitmap {
        var b = DotBitmap(cols: cols, rows: rows)
        let filled = Int((min(max(p, 0), 100) / 100 * Double(cols)).rounded())
        for x in 0..<filled { for y in 0..<rows { b.set(x, y, 1) } }

        guard window != nil else {
            b.draw(title, x: 2, y: 2)
            b.drawCentered("--", y: max(10, rows / 2 - 3))
            return b
        }
        let t = timeText
        let big = "\(min(Int(p.rounded()), 999))%"
        func w(_ s: String, _ k: Int = 1) -> Int { DotFont.width(s, scale: k) }
        func best(top: Int, bottom: Int) -> Int {
            var k = maxScale
            while k > 0 && (w(big, k) > cols - 4 || top + 7 * k > bottom) { k -= 1 }
            return k
        }
        func drawBig(_ k: Int, top: Int, bottom: Int) {
            let y = top + max(0, (bottom - top - 7 * k) / 2)
            // Sempre centrada no painel: as duas faixas ficam alinhadas.
            let x = (cols - w(big, k)) / 2
            b.draw(big, x: x, y: y, scale: k)
        }

        // 1) Título e tempo na linha de cima; % embaixo, o maior possível.
        for name in [title, LEDPanel.abbreviate(title)] where 2 + w(name) + 6 + w(t) <= cols - 2 {
            let k = best(top: 10, bottom: rows - 1)
            if k >= 2 || (k == 1 && name == LEDPanel.abbreviate(title)) {
                b.draw(name, x: 2, y: 2)
                b.draw(t, x: cols - 2 - w(t), y: 2, value: 3)
                drawBig(k, top: 10, bottom: rows - 1)
                return b
            }
        }
        // 2) Título em cima, tempo embaixo, % no meio.
        let k2 = best(top: 10, bottom: rows - 10)
        if k2 >= 1 {
            b.draw(title, x: 2, y: 2)
            b.draw(t, x: 2, y: rows - 9, value: 3)
            drawBig(k2, top: 10, bottom: rows - 10)
            return b
        }
        // 3) Apertado: nome curto e % na mesma linha, tempo embaixo se couber.
        let name = LEDPanel.abbreviate(title)
        b.draw(name, x: 2, y: 2)
        b.draw(big, x: cols - 2 - w(big), y: 2)
        if rows >= 18 { b.draw(t, x: 2, y: 11, value: 3) }
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
    static func make(_ s: UsageSnapshot, agent: String, window: String) -> [Item] {
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
                if ids.count == 1 { title = w?.label.uppercased() ?? UsageStyle.shortName(id) }
                else if window == "both" { title = (id == "codex" ? "CX " : "CL ") + (w?.label.uppercased() ?? "") }
                else { title = UsageStyle.shortName(id) }
                out.append(Item(key: "\(id)-\(w?.id ?? "none")", providerID: id, window: w, title: title))
            }
        }
        return out
    }
}
