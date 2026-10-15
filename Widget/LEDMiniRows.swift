import SwiftUI
import WidgetKit

/// Uma faixa do LED pequeno (relógio: Smart Stack e Atividade ao Vivo no pulso).
/// A barra de pontos enche com o gasto, com o nome e a % escritos nela; a contagem fica ao lado.
struct MiniLine: Identifiable, Hashable {
    var id: String
    var providerID: String
    /// Nome em pontos à esquerda (nil = só a %).
    var name: String?
    /// Etiqueta da janela antes da % ("5H 32%"), quando a IA mostra as duas.
    var tag: String?
    /// nil = sem dados ("--").
    var percent: Double?
    var resetsAt: Date?
    /// Primeira faixa de uma IA: ganha um vão maior em cima (separa as IAs no modo "as duas").
    var groupStart = true
    /// Janela de 7 dias: contagem mais apagada (a de 5h é a que manda).
    var dim = false

    /// Rótulo curto da janela, igual à tecla do aparelho.
    static func windowLabel(_ w: String) -> String { w == "long" ? "7D" : w == "both" ? "5H 7D" : "5H" }

    /// As faixas de um retrato: "all" ou uma IA; "short", "long" ou "both".
    static func lines(_ s: UsageSnapshot, agent: String, window: String, now: Date) -> [MiniLine] {
        var ids = (agent == "all" ? Prefs.allProviders : [agent]).filter { s.provider($0) != nil }
        if ids.isEmpty { ids = agent == "all" ? s.providers.map(\.id) : [agent] }
        var out: [MiniLine] = []
        for id in ids.prefix(window == "both" ? 2 : 3) {
            let p = s.provider(id)
            let ws = p?.windows ?? []
            let short = ws.first, long = ws.count > 1 ? ws[1] : nil
            func line(_ w: UsageWindow?, name: String?, tag: String?, first: Bool, dim: Bool) -> MiniLine {
                MiniLine(id: "\(id)-\(tag ?? "x")", providerID: id, name: name, tag: tag,
                         percent: w?.used(at: now), resetsAt: w?.didReset(at: now) == true ? nil : w?.resetsAt,
                         groupStart: first, dim: dim)
            }
            if window == "both" {
                out.append(line(short, name: UsageStyle.shortName(id), tag: "5H", first: true, dim: false))
                if let long { out.append(line(long, name: nil, tag: "7D", first: false, dim: true)) }
            } else {
                let w = window == "long" ? (long ?? short) : short
                out.append(line(w, name: UsageStyle.shortName(id), tag: nil, first: true, dim: window == "long"))
            }
        }
        return out
    }
}

/// As faixas empilhadas, do tamanho que couber: pontos maiores com poucas faixas.
/// Com até duas faixas sobra altura para um letreiro ("TOKENBAR" + janela) em cima.
struct MiniLEDRows: View {
    var lines: [MiniLine]
    var theme: Theme
    var now: Date = .now
    var header: String? = nil
    var badge: String? = nil
    /// Teto do ponto (o cartão do relógio não precisa de pontos enormes).
    var maxDot: CGFloat = 2.6

    var body: some View {
        GeometryReader { geo in
            // Uma faixa só: alta, com a % em pontos dobrados. Até 3: 9 linhas. Mais: 7.
            let rows = lines.count == 1 ? 16 : lines.count <= 3 ? 9 : 7
            let k = rows >= 16 ? 2 : 1
            let showHeader = header != nil && lines.count <= 2
            let groups = lines.dropFirst().filter(\.groupStart).count
            let inner = lines.dropFirst().count - groups
            // Altura toda em "pontos": faixas + vãos (1 dentro da IA, 2,5 entre IAs) + letreiro.
            let headDots: CGFloat = showHeader ? 7 * 0.62 + 3 : 0
            let units = CGFloat(lines.count * rows) + CGFloat(inner) * 1 + CGFloat(groups) * 2.5 + headDots
            let dot = max(1, min(k == 2 ? min(maxDot, 2) : maxDot, geo.size.height / max(units, 1)))
            // A barra é a estrela: a contagem fica com no máximo ~1/3 da largura.
            let fs = min((dot * CGFloat(rows) * 0.8).rounded(.down), (geo.size.width * (k == 2 ? 0.4 : 0.34) / (0.61 * 7)).rounded(.down))
            let cw = MiniCountdown.width(fontSize: fs)
            let cols = Int((geo.size.width - cw - dot * 2.5) / dot)
            // Todas as faixas com o nome inteiro, ou todas com a sigla.
            let full = lines.allSatisfy { l in
                l.name.map { 2 + DotFont.width($0) + 3 + DotFont.width(MiniLineView.right(l), scale: k) + 2 <= cols } ?? true
            }
            VStack(alignment: .leading, spacing: 0) {
                if showHeader {
                    HStack(spacing: 0) {
                        Self.ledText(header ?? "", color: .white, dot: dot * 0.62, round: theme.roundDots)
                        Spacer(minLength: 4)
                        if let badge {
                            Self.ledText(badge, color: theme.timer.color.opacity(0.8), dot: dot * 0.62, round: theme.roundDots)
                        }
                    }
                    .padding(.bottom, dot * 3)
                }
                ForEach(Array(lines.enumerated()), id: \.element.id) { i, l in
                    MiniLineView(line: l, theme: theme, now: now, dot: dot, rows: rows, fontSize: fs, countdownWidth: cw, fullName: full)
                        .padding(.top, i == 0 ? 0 : dot * (l.groupStart ? 2.5 : 1))
                }
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .center)
        }
    }

    static func ledText(_ text: String, color: Color, dot: CGFloat, round: Bool) -> some View {
        var b = DotBitmap(cols: max(1, DotFont.width(text)), rows: DotFont.height)
        b.draw(text, x: 0, y: 0)
        return DotCanvas(bitmap: b, dot: dot, textColor: color, fieldColor: .clear, offColor: .clear, round: round)
    }
}

struct MiniLineView: View {
    var line: MiniLine
    var theme: Theme
    var now: Date
    var dot: CGFloat
    var rows: Int
    var fontSize: CGFloat
    var countdownWidth: CGFloat
    var fullName = true

    /// O texto da direita da faixa: "72%" ou "5H 72%".
    static func right(_ l: MiniLine) -> String {
        let num = l.percent.map { "\(min(Int($0.rounded()), 999))%" } ?? "--"
        return l.tag.map { "\($0) \(num)" } ?? num
    }

    var body: some View {
        let pct = line.percent ?? 0
        let fill = theme.fill(line.providerID, percent: pct)
        HStack(spacing: dot * 2.5) {
            GeometryReader { geo in
                let cols = max(16, Int(geo.size.width / dot))
                DotCanvas(bitmap: bitmap(cols: cols, pct: pct), dot: dot, textColor: theme.text.color,
                          fieldColor: fill.opacity(0.78), offColor: fill.opacity(0.15), round: theme.roundDots)
                    .shadow(color: fill.opacity(0.4 * theme.glow), radius: dot * theme.glow)
            }
            .frame(height: CGFloat(rows) * dot)
            MiniCountdown(resetsAt: line.resetsAt, now: now)
                .font(.system(size: fontSize, weight: .bold, design: .monospaced))
                .foregroundStyle(line.dim ? theme.timer.color.opacity(0.62) : theme.timer.color)
                .lineLimit(1).minimumScaleFactor(0.7)
                .frame(width: countdownWidth, alignment: .trailing)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(UsageStyle.displayName(line.providerID)) \(line.tag ?? "") \(line.percent.map(UsageStyle.percent) ?? "--")")
    }

    private func bitmap(cols: Int, pct: Double) -> DotBitmap {
        var b = DotBitmap(cols: cols, rows: rows)
        let filled = line.percent == nil ? 0 : Int((min(max(pct, 0), 100) / 100 * Double(cols)).rounded())
        for x in 0..<filled { for y in 0..<rows { b.set(x, y, 1) } }
        let text = Self.right(line)
        // % em pontos dobrados (faixa alta) se couber; senão, normal.
        let k = rows >= 16 && DotFont.width(text, scale: 2) + 4 <= cols ? 2 : 1
        let y = (rows - DotFont.height) / 2
        let rightX = cols - 2 - DotFont.width(text, scale: k)
        b.draw(text, x: rightX, y: (rows - DotFont.height * k) / 2, scale: k)
        if let name = line.name {
            // Nome inteiro se couber; senão a sigla (CL, CX); senão nada.
            for n in (fullName ? [name] : []) + [UsageStyle.abbr(line.providerID)] where 2 + DotFont.width(n) + 3 <= rightX {
                b.draw(n, x: 2, y: y)
                break
            }
        }
        return b
    }
}

/// Contagem até o reset: anda sozinha (`Text(timerInterval:)`); mais de um dia vira "3D05H".
struct MiniCountdown: View {
    var resetsAt: Date?
    var now: Date

    /// Largura fixa da coluna ("4:59:59"), para as faixas ficarem alinhadas.
    static func width(fontSize: CGFloat) -> CGFloat { (fontSize * 0.61 * 7).rounded(.up) }

    var body: some View {
        if let r = resetsAt, r > now {
            let left = r.timeIntervalSince(now)
            if left >= 86400 {
                Text(String(format: "%dD%02dH", Int(left / 86400), Int(left.truncatingRemainder(dividingBy: 86400) / 3600)))
            } else {
                Text(timerInterval: now...r, countsDown: true, showsHours: true)
                    .multilineTextAlignment(.trailing)
                    .monospacedDigit()
            }
        } else {
            Text("--:--")
        }
    }
}

/// Quanto o widget importa agora, para a Smart Stack do relógio subir com ele:
/// uso alto (≥ 70%) ou um reset nos próximos 30 minutos.
enum MiniRelevance {
    static func make(_ lines: [MiniLine], at date: Date) -> TimelineEntryRelevance {
        let top = lines.compactMap(\.percent).max() ?? 0
        let soon = lines.compactMap(\.resetsAt).filter { $0 > date }.min()
        let untilReset = soon.map { $0.timeIntervalSince(date) } ?? .infinity
        var score: Float = 10
        if top >= 70 { score = max(score, Float(40 + min(top, 100) * 0.6)) }   // 70% → 82, 100% → 100
        if untilReset <= 30 * 60 { score = max(score, 90) }
        // Reset perto: vale até o reset (e um pouco depois, para mostrar a barra zerada).
        let duration: TimeInterval = untilReset <= 30 * 60 ? untilReset + 5 * 60 : 0
        return TimelineEntryRelevance(score: score, duration: duration)
    }

    /// Momentos em que a relevância muda: 30 min antes de cada reset (e o próprio reset).
    static func dates(_ s: UsageSnapshot, now: Date, horizon: TimeInterval = 6 * 3600) -> [Date] {
        let resets = s.upcomingResets(after: now).filter { $0 < now.addingTimeInterval(horizon) }
        let early = resets.map { $0.addingTimeInterval(-30 * 60) }.filter { $0 > now }
        return Array(Set([now] + resets + early)).sorted().prefix(12).map { $0 }
    }
}
