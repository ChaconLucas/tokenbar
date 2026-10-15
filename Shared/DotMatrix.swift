import SwiftUI

// MARK: - Fonte 5×7 de matriz de pontos

enum DotFont {
    static let height = 7

    // "#" = ponto aceso. Cada glifo tem 7 linhas da mesma largura.
    static let glyphs: [Character: [String]] = [
        "0": [".###.", "#...#", "#...#", "#...#", "#...#", "#...#", ".###."],
        "1": ["..#..", ".##..", "..#..", "..#..", "..#..", "..#..", ".###."],
        "2": [".###.", "#...#", "....#", "...#.", "..#..", ".#...", "#####"],
        "3": ["#####", "...#.", "..#..", "...#.", "....#", "#...#", ".###."],
        "4": ["...#.", "..##.", ".#.#.", "#..#.", "#####", "...#.", "...#."],
        "5": ["#####", "#....", "####.", "....#", "....#", "#...#", ".###."],
        "6": ["..##.", ".#...", "#....", "####.", "#...#", "#...#", ".###."],
        "7": ["#####", "....#", "...#.", "..#..", ".#...", ".#...", ".#..."],
        "8": [".###.", "#...#", "#...#", ".###.", "#...#", "#...#", ".###."],
        "9": [".###.", "#...#", "#...#", ".####", "....#", "...#.", ".##.."],
        "%": ["##...", "##..#", "...#.", "..#..", ".#...", "#..##", "...##"],
        ":": ["..", "##", "##", "..", "##", "##", ".."],
        ".": [".", ".", ".", ".", ".", ".", "#"],
        "-": [".....", ".....", ".....", "#####", ".....", ".....", "....."],
        " ": ["...", "...", "...", "...", "...", "...", "..."],
        "A": [".###.", "#...#", "#...#", "#####", "#...#", "#...#", "#...#"],
        "B": ["####.", "#...#", "#...#", "####.", "#...#", "#...#", "####."],
        "C": [".###.", "#...#", "#....", "#....", "#....", "#...#", ".###."],
        "D": ["###..", "#..#.", "#...#", "#...#", "#...#", "#..#.", "###.."],
        "E": ["#####", "#....", "#....", "####.", "#....", "#....", "#####"],
        "F": ["#####", "#....", "#....", "####.", "#....", "#....", "#...."],
        "G": [".###.", "#...#", "#....", "#.###", "#...#", "#...#", ".####"],
        "H": ["#...#", "#...#", "#...#", "#####", "#...#", "#...#", "#...#"],
        "I": [".###.", "..#..", "..#..", "..#..", "..#..", "..#..", ".###."],
        "J": ["..###", "...#.", "...#.", "...#.", "...#.", "#..#.", ".##.."],
        "Q": [".###.", "#...#", "#...#", "#...#", "#.#.#", "#..#.", ".##.#"],
        ">": ["#....", ".#...", "..#..", "...#.", "..#..", ".#...", "#...."],
        "/": ["....#", "....#", "...#.", "..#..", ".#...", "#....", "#...."],
        "+": [".....", "..#..", "..#..", "#####", "..#..", "..#..", "....."],
        "K": ["#...#", "#..#.", "#.#..", "##...", "#.#..", "#..#.", "#...#"],
        "L": ["#....", "#....", "#....", "#....", "#....", "#....", "#####"],
        "M": ["#...#", "##.##", "#.#.#", "#.#.#", "#...#", "#...#", "#...#"],
        "N": ["#...#", "#...#", "##..#", "#.#.#", "#..##", "#...#", "#...#"],
        "O": [".###.", "#...#", "#...#", "#...#", "#...#", "#...#", ".###."],
        "P": ["####.", "#...#", "#...#", "####.", "#....", "#....", "#...."],
        "R": ["####.", "#...#", "#...#", "####.", "#.#..", "#..#.", "#...#"],
        "S": [".####", "#....", "#....", ".###.", "....#", "....#", "####."],
        "T": ["#####", "..#..", "..#..", "..#..", "..#..", "..#..", "..#.."],
        "U": ["#...#", "#...#", "#...#", "#...#", "#...#", "#...#", ".###."],
        "V": ["#...#", "#...#", "#...#", "#...#", "#...#", ".#.#.", "..#.."],
        "W": ["#...#", "#...#", "#...#", "#.#.#", "#.#.#", "##.##", "#...#"],
        "X": ["#...#", "#...#", ".#.#.", "..#..", ".#.#.", "#...#", "#...#"],
        "Y": ["#...#", "#...#", ".#.#.", "..#..", "..#..", "..#..", "..#.."],
        "Z": ["#####", "....#", "...#.", "..#..", ".#...", "#....", "#####"],
    ]

    /// Letra acentuada sem desenho próprio usa a base, como nos letreiros (Ç → C, Ã → A).
    static func glyph(_ c: Character) -> [String] {
        let up = Character(c.uppercased())
        if let g = glyphs[up] { return g }
        let base = String(up).folding(options: .diacriticInsensitive, locale: nil)
        return base.first.flatMap { glyphs[$0] } ?? glyphs[" "]!
    }

    /// Largura em pontos de um texto, com 1 ponto entre letras (multiplicado pela escala).
    static func width(_ text: String, scale: Int = 1) -> Int {
        let w = text.map { glyph($0)[0].count }.reduce(0, +) + max(0, text.count - 1)
        return w * scale
    }
}

/// Grade de pontos: o que está "aceso" é desenhado forte; o resto aparece fraco, como num painel de LED.
struct DotBitmap {
    var cols: Int
    var rows: Int
    /// 0 = apagado, 1 = fundo colorido, 2 = texto, 3 = texto apagado
    var cells: [UInt8]

    init(cols: Int, rows: Int, fill: UInt8 = 0) {
        self.cols = cols
        self.rows = rows
        cells = Array(repeating: fill, count: cols * rows)
    }

    mutating func set(_ x: Int, _ y: Int, _ v: UInt8) {
        guard x >= 0, y >= 0, x < cols, y < rows else { return }
        cells[y * cols + x] = v
    }

    func get(_ x: Int, _ y: Int) -> UInt8 { cells[y * cols + x] }

    mutating func draw(_ text: String, x: Int, y: Int, scale: Int = 1, value: UInt8 = 2) {
        var cx = x
        for ch in text {
            let g = DotFont.glyph(ch)
            for (row, line) in g.enumerated() {
                for (col, px) in line.enumerated() where px == "#" {
                    for sy in 0..<scale { for sx in 0..<scale { set(cx + col * scale + sx, y + row * scale + sy, value) } }
                }
            }
            cx += (g[0].count + 1) * scale
        }
    }

    /// Texto centrado na horizontal (dentro de `lo..<hi`, se dado).
    mutating func drawCentered(_ text: String, y: Int, scale: Int = 1, value: UInt8 = 2, lo: Int = 0, hi: Int? = nil) {
        let hi = hi ?? cols
        draw(text, x: lo + max(0, (hi - lo - DotFont.width(text, scale: scale))) / 2, y: y, scale: scale, value: value)
    }
}

struct DotCanvas: View {
    var bitmap: DotBitmap
    var dot: CGFloat
    var textColor: Color
    var fieldColor: Color
    var offColor: Color
    var round = true

    var body: some View {
        Canvas { ctx, _ in
            let gap = dot * (round ? 0.16 : 0.22)
            let size = dot - gap
            for y in 0..<bitmap.rows {
                for x in 0..<bitmap.cols {
                    let v = bitmap.get(x, y)
                    let rect = CGRect(x: CGFloat(x) * dot, y: CGFloat(y) * dot, width: size, height: size)
                    let color: Color = v == 2 ? textColor : v == 3 ? textColor.opacity(0.72) : v == 1 ? fieldColor : offColor
                    let path = round ? Path(ellipseIn: rect) : Path(roundedRect: rect, cornerRadius: size * 0.22)
                    ctx.fill(path, with: .color(color))
                }
            }
        }
        .frame(width: CGFloat(bitmap.cols) * dot, height: CGFloat(bitmap.rows) * dot)
        .clipShape(RoundedRectangle(cornerRadius: dot * 2.5, style: .continuous))
    }
}

// MARK: - O display (estilo BUSY Bar)

/// Um provedor num painel: à esquerda o bloco colorido com a %, à direita quanto falta para resetar.
struct DotDisplay: View {
    var provider: ProviderUsage?
    var providerID: String
    var window: UsageWindow?
    /// Com as duas janelas: 5H em cima, 7D embaixo, cada faixa com o seu preenchimento.
    var second: UsageWindow? = nil
    var now: Date
    var compact = false
    var theme: Theme = Prefs.theme
    /// Ocupa a área inteira: acrescenta linhas de pontos em vez de deixar faixa vazia (tela do celular).
    var fillsArea = false
    /// Linhas no alto deixadas livres (as teclas do celular ficam ali, dentro do display).
    var topInset = 0
    /// Colunas nas bordas de fora sem texto (a Dynamic Island do celular deitado); o fundo continua até a borda.
    var sideInset = 0

    static let rows = 31
    /// Colunas do display inteiro (bloco 58 + vão 3 + tempo 62): o letreiro usa o mesmo ponto.
    static let totalCols = 123
    /// Bloco do gasto (maior) e do tempo (menor): 68 + vão 3 + 52 = 123.
    static let leftCols = 68
    /// Largura fixa do painel do tempo: cabe "6D22H" e "RESET" e não muda de uma IA para outra.
    static let rightCols = 52

    var body: some View {
        let pct = window?.used(at: now) ?? 0
        let level = theme.fill(providerID, percent: pct)
        let glow = theme.glow
        let base = bitmaps(pct: pct, rows: Self.rows)

        GeometryReader { geo in
            if fillsArea {
                phoneLayout(size: geo.size, glow: glow)
            } else {
            let totalCols = CGFloat(base.0.cols + (base.1?.cols ?? 0) + (base.1 == nil ? 0 : gap))
            let byWidth = geo.size.width / totalCols
            // Sobrando altura, cresce o painel em linhas (com o conteúdo centrado) em vez de encolher os pontos.
            let rows = fillsArea ? max(Self.rows + topInset, Int(geo.size.height / byWidth)) : Self.rows
            let (left, right) = rows == Self.rows ? base : bitmaps(pct: pct, rows: rows)
            let dot = max(1, min(byWidth, geo.size.height / CGFloat(rows)))
            if let window, let second, !compact {
                // Duas medições: dois painéis separados pelo mesmo vão que separa a % do tempo.
                let bandRows = (rows - gap) / 2
                VStack(spacing: dot * CGFloat(gap)) {
                    band(window, rows: bandRows, inset: topInset, dot: dot, glow: glow)
                    band(second, rows: bandRows, inset: 0, dot: dot, glow: glow)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
            HStack(spacing: dot * CGFloat(gap)) {
                DotCanvas(bitmap: left, dot: dot,
                          textColor: theme.text.color, fieldColor: level.opacity(0.62), offColor: level.opacity(0.10),
                          round: theme.roundDots)
                    .shadow(color: level.opacity(0.35 * glow), radius: dot * 2 * glow)
                if let right {
                    let (rb, rd) = fillsArea ? finePanel(singleTimeLines(), rows: rows, dot: dot, inset: topInset) : (right, dot)
                    DotCanvas(bitmap: rb, dot: rd,
                              textColor: theme.timer.color, fieldColor: theme.timer.color.opacity(0.35),
                              offColor: theme.timer.color.opacity(0.06), round: theme.roundDots)
                        .shadow(color: theme.timer.color.opacity(0.25 * glow), radius: rd * glow)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            }
        }
        // aspectRatio(nil) não é neutro: força a proporção ideal (quadrada) do GeometryReader.
        .modifier(KeepAspect(ratio: fillsArea ? nil : aspect))
        .accessibilityElement()
        .accessibilityLabel("\(UsageStyle.shortName(providerID)) \(UsageStyle.percent(pct))")
    }

    /// Uma medição em faixa própria: rótulo + % (o fundo enche até a %) e o tempo ao lado.
    private func band(_ w: UsageWindow, rows: Int, inset: Int, dot: CGFloat, glow: Double) -> some View {
        let textTop = min(rows - 14, inset + max(0, rows - inset - 14) / 2)
        let p = w.used(at: now)
        let level = theme.fill(providerID, percent: p)
        var left = DotBitmap(cols: Self.leftCols, rows: rows, fill: 0)
        let filled = Int((min(max(p, 0), 100) / 100 * Double(left.cols)).rounded())
        for x in 0..<filled { for y in 0..<rows { left.set(x, y, 1) } }
        left.draw(w.label.uppercased(), x: 3 + sideInset, y: textTop + 4, scale: 1)
        let big = "\(min(Int(p.rounded()), 999))%"
        left.draw(big, x: left.cols - 3 - DotFont.width(big, scale: 2), y: textTop, scale: 2)
        var right = DotBitmap(cols: Self.rightCols, rows: rows)
        right.drawCentered(timeText(w), y: textTop, scale: 2, hi: Self.rightCols - sideInset)
        return HStack(spacing: dot * CGFloat(gap)) {
            DotCanvas(bitmap: left, dot: dot,
                      textColor: theme.text.color, fieldColor: level.opacity(0.62), offColor: level.opacity(0.10),
                      round: theme.roundDots)
                .shadow(color: level.opacity(0.35 * glow), radius: dot * 2 * glow)
            let (rb, rd) = fillsArea ? finePanel([timeText(w)], rows: rows, dot: dot, inset: inset) : (right, dot)
            DotCanvas(bitmap: rb, dot: rd,
                      textColor: theme.timer.color, fieldColor: theme.timer.color.opacity(0.35),
                      offColor: theme.timer.color.opacity(0.06), round: theme.roundDots)
                .shadow(color: theme.timer.color.opacity(0.25 * glow), radius: rd * glow)
        }
    }

    // MARK: Celular: o gasto ocupa a tela, o reset fica pequeno num canto

    @ViewBuilder
    private func phoneLayout(size: CGSize, glow: Double) -> some View {
        let cols = Self.totalCols
        let dot = size.width / CGFloat(cols)
        let rows = max(Self.rows + topInset, Int(size.height / dot))
        if let window, let second, !compact {
            let bandRows = (rows - 1) / 2
            VStack(spacing: dot) {
                phoneBand(window, label: window.label.uppercased(), rows: bandRows, inset: topInset, dot: dot, glow: glow, inline: true)
                phoneBand(second, label: second.label.uppercased(), rows: bandRows, inset: 0, dot: dot, glow: glow, inline: true)
            }
        } else {
            let name = UsageStyle.shortName(providerID) + (window.map { " " + $0.label.uppercased() } ?? "")
            phoneBand(window, label: name, rows: rows, inset: topInset, dot: dot, glow: glow)
        }
    }

    private func phoneBand(_ w: UsageWindow?, label: String, rows: Int, inset: Int, dot: CGFloat, glow: Double,
                           inline: Bool = false) -> some View {
        let cols = Self.totalCols
        let p = w?.used(at: now) ?? 0
        let level = theme.fill(providerID, percent: p)
        var b = DotBitmap(cols: cols, rows: rows)
        let filled = Int((min(max(p, 0), 100) / 100 * Double(cols)).rounded())
        for x in 0..<filled { for y in 0..<rows { b.set(x, y, 1) } }

        let big = w == nil ? "--" : "\(min(Int(p.rounded()), 999))%"
        let reset: String = {
            guard let w else { return Lang.t("SEM DADOS") }
            guard let r = w.resetsAt else { return "" }
            if w.didReset(at: now) { return Lang.t("RESETOU") }
            let s = max(0, Int(r.timeIntervalSince(now)))
            let d = s / 86400, h = (s % 86400) / 3600, m = (s % 3600) / 60
            return "RESET " + (d > 0 ? "\(d)D \(h)H" : "\(h):" + String(format: "%02d", m))
        }()
        let left = 3 + sideInset, right = cols - 3 - sideInset

        if inline {
            // Faixa baixa: rótulo | % grande | reset pequeno, tudo numa linha, centrado na altura livre.
            // Só o tempo (sem "RESET"): sobra espaço para a % crescer.
            let reset = reset.hasPrefix("RESET ") ? String(reset.dropFirst(6)) : reset
            let labelW = DotFont.width(label), resetW = DotFont.width(reset)
            let room = right - left - labelW - resetW - 12
            var scale = 5
            // Mede por "100%": as duas faixas ficam com a % do mesmo tamanho, qualquer que seja o número.
            while scale > 1 && (7 * scale > rows - topInset - 2 || DotFont.width("100%", scale: scale) > room) { scale -= 1 }
            let mid = inset + (rows - inset) / 2
            b.draw(label, x: left, y: mid - 3)
            b.draw(big, x: left + labelW + 6 + max(0, (room - DotFont.width(big, scale: scale)) / 2),
                   y: mid - 7 * scale / 2, scale: scale)
            b.draw(reset, x: right - resetW, y: mid - 3, value: 3)
        } else {
            // % o maior possível que caiba (com o rótulo em cima e o canto do reset livre).
            let usable = right - left
            var scale = 6
            while scale > 1 && (7 * scale + 10 > rows - inset - 9 || DotFont.width(big, scale: scale) > usable) { scale -= 1 }
            let block = 7 + 3 + 7 * scale
            let top = inset + max(0, (rows - inset - 9 - block) / 2)
            b.drawCentered(label, y: top, scale: 1)
            b.drawCentered(big, y: top + 10, scale: scale)
            // Reset: pequeno e apagado, no canto de baixo à direita.
            b.draw(reset, x: right - DotFont.width(reset), y: rows - 9, value: 3)
        }

        return DotCanvas(bitmap: b, dot: dot,
                         textColor: theme.text.color, fieldColor: level.opacity(0.62), offColor: level.opacity(0.10),
                         round: theme.roundDots)
            .shadow(color: level.opacity(0.35 * glow), radius: dot * 2 * glow)
    }

    /// Celular: o painel do tempo usa pontos mais finos (texto ~30% menor) no mesmo espaço.
    static let fineFactor: CGFloat = 1.45

    private func finePanel(_ lines: [String], rows: Int, dot: CGFloat, inset: Int) -> (DotBitmap, CGFloat) {
        let k = Self.fineFactor
        let cols = Int((CGFloat(Self.rightCols) * k).rounded(.down))
        let fr = Int((CGFloat(rows) * k).rounded(.down))
        let fi = Int((CGFloat(inset) * k).rounded(.up))
        let fside = Int((CGFloat(sideInset) * k).rounded(.up))
        var b = DotBitmap(cols: cols, rows: fr)
        let block = lines.count * 14 + (lines.count - 1) * 3
        let top = fi + max(0, (fr - fi - block) / 2)
        for (i, t) in lines.enumerated() {
            b.drawCentered(t, y: top + i * 17, scale: 2, hi: cols - fside)
        }
        return (b, dot * CGFloat(Self.rightCols) / CGFloat(cols))
    }

    private func singleTimeLines() -> [String] {
        let (a, b) = rightText()
        return [a, b]
    }

    /// Vão entre os painéis, em pontos: estreito no celular (tela cheia), mais folgado no Mac.
    private var gap: Int { fillsArea ? 1 : 3 }

    private var aspect: CGFloat {
        let (l, r) = bitmaps(pct: 0, rows: Self.rows)
        let cols = l.cols + (r?.cols ?? 0) + (r == nil ? 0 : 3)
        return CGFloat(cols) / CGFloat(Self.rows)
    }

    private func bitmaps(pct: Double, rows: Int) -> (DotBitmap, DotBitmap?) {
        if let second, let window, !compact { return dualBitmaps(window, second, rows: rows) }
        return singleBitmaps(pct: pct, rows: rows)
    }

    /// Duas faixas de 15 linhas: rótulo + % grande à esquerda (o fundo enche até a %), tempo à direita.
    private func dualBitmaps(_ a: UsageWindow, _ b: UsageWindow, rows: Int) -> (DotBitmap, DotBitmap?) {
        let off = (rows - Self.rows) / 2
        var left = DotBitmap(cols: Self.leftCols, rows: rows, fill: 0)
        var times: [String] = []
        for (band, w) in [a, b].enumerated() {
            let top = band * 16 + off
            // A faixa de cima vai até o topo e a de baixo até o fim: o fundo cobre a altura toda.
            let bandRows = band == 0 ? 0..<(top + 15) : top..<rows
            let p = w.used(at: now)
            let filled = Int((min(max(p, 0), 100) / 100 * Double(left.cols)).rounded())
            for x in 0..<filled { for y in bandRows { left.set(x, y, 1) } }
            left.draw(w.label.uppercased(), x: 2, y: top + 4, scale: 1)
            let big = "\(min(Int(p.rounded()), 999))%"
            left.draw(big, x: left.cols - 2 - DotFont.width(big, scale: 2), y: top + 1, scale: 2)
            times.append(timeText(w))
        }
        var right = DotBitmap(cols: Self.rightCols, rows: rows)
        for (band, t) in times.enumerated() { right.drawCentered(t, y: band * 16 + 1 + off, scale: 2) }
        return (left, right)
    }

    /// "3:43" (sem zero na frente); "6D11H" se couber no painel do tempo, senão "6D".
    static func fitTime(d: Int, h: Int, m: Int) -> String {
        if d > 0 {
            let full = "\(d)D\(h)H"
            return DotFont.width(full, scale: 2) + 2 <= rightCols ? full : "\(d)D"
        }
        return "\(h):" + String(format: "%02d", m)
    }

    private func timeText(_ w: UsageWindow) -> String {
        guard let r = w.resetsAt else { return "--:--" }
        if w.didReset(at: now) { return "OK" }
        let s = max(0, Int(r.timeIntervalSince(now)))
        let d = s / 86400, h = (s % 86400) / 3600, m = (s % 3600) / 60
        return Self.fitTime(d: d, h: h, m: m)
    }

    private func singleBitmaps(pct: Double, rows: Int) -> (DotBitmap, DotBitmap?) {
        let off = min(rows - Self.rows, topInset + max(0, rows - topInset - Self.rows) / 2)
        let name = UsageStyle.shortName(providerID) + (window.map { " " + $0.label.uppercased() } ?? "")
        let big = window == nil ? "--" : "\(min(Int(pct.rounded()), 999))%"

        // Esquerda: nome pequeno, número grande, barra de progresso no rodapé.
        // O fundo colorido enche da esquerda até a % gasta; o texto fica por cima.
        var left = DotBitmap(cols: Self.leftCols, rows: rows, fill: 0)
        let filled = Int((min(max(pct, 0), 100) / 100 * Double(left.cols)).rounded())
        for x in 0..<filled { for y in 0..<rows { left.set(x, y, 1) } }
        left.drawCentered(name, y: 3 + off, scale: 1, lo: sideInset)
        left.drawCentered(big, y: 13 + off, scale: 2, lo: sideInset)

        let (top, bottom) = rightText()
        if compact {
            // Sem painel da direita: o nome sai e o tempo vai em cima.
            for x in 0..<left.cols { for y in off..<(11 + off) { left.set(x, y, x < filled ? 1 : 0) } }
            left.drawCentered(top, y: 3 + off, scale: 1)
            return (left, nil)
        }

        var right = DotBitmap(cols: Self.rightCols, rows: rows)
        right.drawCentered(top, y: 1 + off, scale: 2, hi: Self.rightCols - sideInset)
        right.drawCentered(bottom, y: 17 + off, scale: 2, hi: Self.rightCols - sideInset)
        return (left, right)
    }

    /// "02:08" + "LEFT"; "2D22H" + "LEFT" se faltar mais de um dia.
    private func rightText() -> (String, String) {
        guard let w = window else { return ("OFF", "LINE") }
        guard let r = w.resetsAt else { return ("--:--", "LEFT") }
        if w.didReset(at: now) { return ("OK", Lang.t("NOVO")) }
        let s = max(0, Int(r.timeIntervalSince(now)))
        let d = s / 86400, h = (s % 86400) / 3600, m = (s % 3600) / 60
        return (Self.fitTime(d: d, h: h, m: m), "LEFT")
    }
}

/// Moldura de aparelho: vidro preto rebaixado, reflexo no alto.
struct DeviceBezel<Content: View>: View {
    var padding: CGFloat = 12
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .background {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(.black)
                    .overlay {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(LinearGradient(colors: [.white.opacity(0.07), .clear], startPoint: .top, endPoint: .center))
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(LinearGradient(colors: [.white.opacity(0.18), .white.opacity(0.03)], startPoint: .top, endPoint: .bottom), lineWidth: 1)
                    }
                    .shadow(color: .black, radius: 14, y: 8)
            }
    }
}

// MARK: - Preferências: quais IAs aparecem e qual janela

enum Prefs {
    /// As IAs com dados: Claude e Codex primeiro, depois as outras na ordem em que chegaram.
    static var allProviders: [String] {
        let ids = SharedStore.loadSnapshot()?.providers.map(\.id) ?? []
        let known = ["claude", "codex"]
        let rest = ids.filter { !known.contains($0) }
        let list = known.filter { ids.isEmpty || ids.contains($0) } + rest
        return list.isEmpty ? known : list
    }
    private static let visibleKey = "visibleProviders"
    private static let windowKey = "displayWindow"

    /// Vazio nunca: se a pessoa desligar tudo, volta a mostrar todas.
    /// Guarda as IAs DESLIGADAS: assim uma IA nova já chega ligada.
    static var visible: [String] {
        get {
            let all = allProviders
            let hidden = Set(TB.defaults.array(forKey: hiddenKey) as? [String] ?? [])
            let v = all.filter { !hidden.contains($0) }
            return v.isEmpty ? all : v
        }
        set {
            let all = allProviders
            TB.defaults.set(all.filter { !newValue.contains($0) }, forKey: hiddenKey)
        }
    }
    private static let hiddenKey = "hiddenProviders"

    /// "short" = 5h, "long" = 7d.
    static var window: String {
        get { TB.defaults.string(forKey: windowKey) ?? "short" }
        set { TB.defaults.set(newValue, forKey: windowKey) }
    }

    static func pick(_ p: ProviderUsage?) -> UsageWindow? {
        guard let p else { return nil }
        return window == "long" ? (p.windows.count > 1 ? p.windows[1] : p.windows.first) : p.windows.first
    }
}

/// Os displays das IAs escolhidas, empilhados.
struct DisplayStack: View {
    var snapshot: UsageSnapshot
    var visible: [String]
    var windowChoice: String
    var now: Date
    var compact = false
    var spacing: CGFloat = 10
    var theme: Theme = Prefs.theme

    var body: some View {
        VStack(spacing: spacing) {
            ForEach(visible, id: \.self) { id in
                let p = snapshot.provider(id)
                DotDisplay(provider: p, providerID: id, window: pick(p), now: now, compact: compact, theme: theme)
            }
        }
    }

    private func pick(_ p: ProviderUsage?) -> UsageWindow? {
        guard let p else { return nil }
        return windowChoice == "long" ? (p.windows.count > 1 ? p.windows[1] : p.windows.first) : p.windows.first
    }
}

/// Botões para ligar e desligar cada IA e escolher 5H/7D.
struct DisplayControls: View {
    @Binding var visible: [String]
    @Binding var windowChoice: String

    var body: some View {
        HStack(spacing: 8) {
            ForEach(Prefs.allProviders, id: \.self) { id in
                let on = visible.contains(id)
                Button {
                    if on { if visible.count > 1 { visible.removeAll { $0 == id } } }
                    else { visible = Prefs.allProviders.filter { visible.contains($0) || $0 == id } }
                } label: {
                    Label(UsageStyle.shortName(id), systemImage: on ? "circle.fill" : "circle")
                }
                .buttonStyle(ChipStyle(on: on))
            }
            Spacer(minLength: 8)
            ForEach([("short", "5H"), ("long", "7D")], id: \.0) { key, label in
                Button(label) { windowChoice = key }.buttonStyle(ChipStyle(on: windowChoice == key))
            }
        }
    }
}

struct ChipStyle: ButtonStyle {
    var on: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Arcade.label(11))
            .tracking(1)
            .labelStyle(.titleAndIcon)
            .imageScale(.small)
            .foregroundStyle(on ? Color.black : Arcade.dim)
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(Capsule().fill(on ? AnyShapeStyle(Color.white) : AnyShapeStyle(Color.white.opacity(0.06))))
            .overlay(Capsule().strokeBorder(.white.opacity(on ? 0 : 0.12)))
            .shadow(color: on ? .white.opacity(0.35) : .clear, radius: 6)
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.easeOut(duration: 0.15), value: on)
    }
}

private struct KeepAspect: ViewModifier {
    var ratio: CGFloat?
    func body(content: Content) -> some View {
        if let ratio { content.aspectRatio(ratio, contentMode: .fit) } else { content }
    }
}
