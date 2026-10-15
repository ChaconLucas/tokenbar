import SwiftUI

/// Ilustrações animadas do tutorial: mostram o gesto em vez de descrever.
/// Todas rodam num laço de poucos segundos a partir de um `t` de 0 a 1.
enum Art {
    static let claude = Color(red: 0.62, green: 0.36, blue: 1.0)
    static let codex = Color(red: 0.93, green: 0.16, blue: 0.76)

    /// Progresso de 0 a 1 entre dois instantes do laço, suavizado.
    static func seg(_ t: Double, _ a: Double, _ b: Double) -> Double {
        let x = min(max((t - a) / (b - a), 0), 1)
        return x * x * (3 - 2 * x)
    }
}

/// Relógio do laço: entrega `t` de 0 a 1 a cada `period` segundos.
struct ArtLoop<Content: View>: View {
    var period: Double = 4
    @ViewBuilder var content: (Double) -> Content
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if reduceMotion {
            content(0.95)   // quadro final, parado
        } else {
            TimelineView(.animation) { ctx in
                content(ctx.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: period) / period)
            }
        }
    }
}

/// Desenho de tamanho fixo que cresce até caber no espaço que tiver (sem distorcer).
struct ArtFrame<Content: View>: View {
    var width: CGFloat = 340
    var height: CGFloat = 170
    @ViewBuilder var content: Content

    var body: some View {
        GeometryReader { geo in
            let k = max(0.5, min(geo.size.width / width, geo.size.height / height))
            content
                .frame(width: width, height: height)
                .scaleEffect(k)
                .frame(width: geo.size.width, height: geo.size.height)
        }
    }
}

/// Barra de pontos de LED que acende até `fill`.
struct DotBar: View {
    var fill: Double
    var color: Color
    var cols = 24
    var rows = 3

    var body: some View {
        Canvas { ctx, size in
            let d = min(size.width / CGFloat(cols), size.height / CGFloat(rows))
            let lit = Int((fill * Double(cols)).rounded())
            for x in 0..<cols {
                for y in 0..<rows {
                    let r = CGRect(x: CGFloat(x) * d + d * 0.1, y: CGFloat(y) * d + d * 0.1, width: d * 0.8, height: d * 0.8)
                    ctx.fill(Path(ellipseIn: r), with: .color(x < lit ? color : .white.opacity(0.08)))
                }
            }
        }
        .aspectRatio(CGFloat(cols) / CGFloat(rows), contentMode: .fit)
        .shadow(color: color.opacity(0.6), radius: 4)
    }
}

/// QR de mentira (a forma conta, não o conteúdo) para quando o real não está à mão.
struct FakeQR: View {
    var body: some View {
        Canvas { ctx, size in
            let n = 21, d = size.width / CGFloat(n)
            func finder(_ x: Int, _ y: Int) {
                ctx.fill(Path(CGRect(x: CGFloat(x) * d, y: CGFloat(y) * d, width: d * 7, height: d * 7)), with: .color(.black))
                ctx.fill(Path(CGRect(x: CGFloat(x + 1) * d, y: CGFloat(y + 1) * d, width: d * 5, height: d * 5)), with: .color(.white))
                ctx.fill(Path(CGRect(x: CGFloat(x + 2) * d, y: CGFloat(y + 2) * d, width: d * 3, height: d * 3)), with: .color(.black))
            }
            for y in 0..<n {
                for x in 0..<n where (x * 7 + y * 13 + x * y) % 3 == 0 {
                    ctx.fill(Path(CGRect(x: CGFloat(x) * d, y: CGFloat(y) * d, width: d, height: d)), with: .color(.black))
                }
            }
            for (x, y) in [(0, 0), (14, 0), (0, 14)] {
                ctx.fill(Path(CGRect(x: CGFloat(x) * d, y: CGFloat(y) * d, width: d * 7, height: d * 7)), with: .color(.white))
                finder(x, y)
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .padding(4)
        .background(.white, in: RoundedRectangle(cornerRadius: 4))
    }
}

/// Um terminal digita o comando, a statusline aparece e a barra de LED da IA enche.
struct TerminalArt: View {
    var command: String
    var color: Color
    var fill = 0.6

    var body: some View {
        ArtLoop(period: 4.5) { t in
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 4) {
                        ForEach([Color.red, .yellow, .green], id: \.self) { Circle().fill($0.opacity(0.8)).frame(width: 7, height: 7) }
                    }
                    let typed = command.prefix(Int(Double(command.count) * Art.seg(t, 0.05, 0.3)))
                    Text("› " + typed + (t < 0.35 && Int(t * 12) % 2 == 0 ? "▌" : " "))
                        .font(.system(size: 13, weight: .semibold, design: .monospaced)).foregroundStyle(.white)
                    Spacer(minLength: 0)
                    Text("5h \(Int(fill * 100))% · 7d 12%")
                        .font(.system(size: 9, design: .monospaced)).foregroundStyle(color)
                        .opacity(Art.seg(t, 0.35, 0.45))
                }
                .padding(10)
                .frame(width: 150, height: 96, alignment: .topLeading)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color(white: 0.13)))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.white.opacity(0.3)))

                // Pontinhos que levam o número do terminal até o display.
                HStack(spacing: 5) {
                    ForEach(0..<4) { i in
                        Circle().fill(color).frame(width: 5, height: 5)
                            .opacity(Art.seg(t, 0.45 + Double(i) * 0.04, 0.5 + Double(i) * 0.04) * (1 - Art.seg(t, 0.9, 0.98)))
                    }
                }
                DotBar(fill: fill * Art.seg(t, 0.6, 0.85), color: color, cols: 16, rows: 5)
                    .frame(width: 120)
                    .padding(8)
                    .background(RoundedRectangle(cornerRadius: 10).fill(.black))
                    .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.white.opacity(0.3)))
            }
        }
    }
}

/// Notebook com algo na tela.
struct LaptopArt<Screen: View>: View {
    @ViewBuilder var screen: Screen

    var body: some View {
        VStack(spacing: 0) {
            screen
                .frame(width: 150, height: 94)
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .padding(6)
                .background(RoundedRectangle(cornerRadius: 9).fill(Color(white: 0.12)))
                .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(.white.opacity(0.2)))
            UnevenRoundedRectangle(bottomLeadingRadius: 6, bottomTrailingRadius: 6)
                .fill(Color(white: 0.18)).frame(width: 190, height: 8)
        }
    }
}

/// Celular de perfil: a tela acende com pontos de LED quando `lit` passa de 0.
struct PhoneShape: View {
    var lit: Double = 0
    var check = false

    var body: some View {
        RoundedRectangle(cornerRadius: 12)
            .fill(Color(white: 0.08))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.white.opacity(0.35), lineWidth: 2))
            .overlay {
                VStack(spacing: 4) {
                    DotBar(fill: 0.7 * lit, color: Art.claude, cols: 8, rows: 2)
                    DotBar(fill: 0.4 * lit, color: Art.codex, cols: 8, rows: 2)
                }
                .padding(8)
            }
            .overlay(alignment: .top) {
                if check {
                    Image(systemName: "checkmark.circle.fill").font(.system(size: 22)).foregroundStyle(Arcade.green)
                        .offset(y: -12).shadow(color: Arcade.green, radius: 6)
                }
            }
            .frame(width: 54, height: 100)
    }
}

/// O celular chega perto do QR, a linha de leitura passa e a tela dele acende.
struct ScanArt<QR: View>: View {
    @ViewBuilder var qr: QR

    var body: some View {
        ArtLoop(period: 4) { t in
            let approach = Art.seg(t, 0.0, 0.3)
            let sweep = Art.seg(t, 0.32, 0.62)
            ZStack {
                LaptopArt {
                    ZStack {
                        Color.black
                        qr.frame(width: 76, height: 76)
                            .overlay(alignment: .top) {
                                Rectangle().fill(Arcade.cyan).frame(height: 2)
                                    .shadow(color: Arcade.cyan, radius: 6)
                                    .offset(y: 76 * sweep)
                                    .opacity(t > 0.32 && t < 0.64 ? 1 : 0)
                            }
                    }
                }
                PhoneShape(lit: Art.seg(t, 0.66, 0.85), check: t > 0.7)
                    .rotationEffect(.degrees(-8 * (1 - approach)))
                    .offset(x: 150 - 60 * approach, y: 10)
            }
            .frame(width: 330)
        }
    }
}

/// Relógio redondo: os números do código aparecem um a um.
struct WatchCodeArt: View {
    var code: String

    var body: some View {
        ArtLoop(period: 4) { t in
            let shown = code.prefix(Int(Double(code.count) * Art.seg(t, 0.05, 0.6)) + (t > 0.6 ? 1 : 0))
            ZStack {
                RoundedRectangle(cornerRadius: 10).fill(Color(white: 0.15)).frame(width: 52, height: 170)
                Circle().fill(.black).frame(width: 120, height: 120)
                    .overlay(Circle().strokeBorder(.white.opacity(0.35), lineWidth: 3))
                VStack(spacing: 4) {
                    Text(String(shown).padding(toLength: code.count, withPad: "_", startingAt: 0))
                        .font(.system(size: 20, weight: .bold, design: .monospaced)).foregroundStyle(.white)
                    if t > 0.7 {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(Arcade.green)
                            .shadow(color: Arcade.green, radius: 6)
                    }
                }
            }
        }
    }
}

/// O cursor vai até as barrinhas da barra de menu, clica e o resumo desce; depois um arrasto troca de IA.
struct MenuBarArt: View {
    var body: some View {
        ArtLoop(period: 5) { t in
            let open = Art.seg(t, 0.4, 0.52)
            let swipe = Art.seg(t, 0.68, 0.85)
            ZStack(alignment: .topTrailing) {
                VStack(spacing: 0) {
                    HStack(spacing: 10) {
                        ForEach(0..<4) { _ in Capsule().fill(.white.opacity(0.2)).frame(width: 24, height: 5) }
                        Spacer()
                        HStack(spacing: 3) {
                            DotBar(fill: 0.6, color: Art.claude, cols: 6, rows: 2).frame(width: 22)
                            DotBar(fill: 0.3, color: Art.codex, cols: 6, rows: 2).frame(width: 22)
                        }
                        .padding(3)
                        .background(RoundedRectangle(cornerRadius: 4).fill(.white.opacity(t > 0.38 && t < 0.95 ? 0.2 : 0)))
                    }
                    .padding(.horizontal, 10)
                    .frame(height: 22)
                    .background(Color(white: 0.14))
                    Spacer()
                }
                .frame(width: 330, height: 150)
                .background(Color(white: 0.04))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.white.opacity(0.15)))

                // O resumo que desce.
                ZStack {
                    HStack(spacing: 0) {
                        DotBar(fill: 0.6, color: Art.claude, cols: 14, rows: 4).frame(width: 120)
                        DotBar(fill: 0.3, color: Art.codex, cols: 14, rows: 4).frame(width: 120)
                    }
                    .offset(x: 60 - 120 * swipe)
                }
                .frame(width: 130, height: 56)
                .clipped()
                .padding(6)
                .background(RoundedRectangle(cornerRadius: 10).fill(.black))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.white.opacity(0.2)))
                .offset(x: -6, y: 28)
                .opacity(open * (1 - Art.seg(t, 0.93, 1)))
                .scaleEffect(0.9 + 0.1 * open, anchor: .top)

                // Cursor e, depois, o dedo do arrasto.
                let cx = 260 * Art.seg(t, 0.05, 0.35), cy = 120 - 112 * Art.seg(t, 0.05, 0.35)
                Image(systemName: t < 0.6 ? "cursorarrow" : "hand.point.up.left.fill")
                    .font(.system(size: 18)).foregroundStyle(.white)
                    .shadow(radius: 2)
                    .scaleEffect(t > 0.38 && t < 0.43 ? 0.8 : 1)
                    .position(x: t < 0.6 ? 20 + cx : 280 - 90 * swipe, y: t < 0.6 ? 10 + cy : 66)
                    .frame(width: 330, height: 150, alignment: .topLeading)
            }
            .frame(width: 330, height: 150)
        }
    }
}

/// Celular e computador com o Wi-Fi pulsando entre os dois.
struct WifiArt: View {
    var body: some View {
        ArtLoop(period: 2.4) { t in
            HStack(spacing: 18) {
                PhoneShape(lit: 1)
                ZStack {
                    ForEach(0..<3) { i in
                        let p = (t + Double(i) / 3).truncatingRemainder(dividingBy: 1)
                        Image(systemName: "wifi").font(.system(size: 22 + 26 * p))
                            .foregroundStyle(Arcade.cyan.opacity(1 - p))
                    }
                }
                .frame(width: 70)
                LaptopArt {
                    ZStack {
                        Color.black
                        VStack(spacing: 6) {
                            DotBar(fill: 0.6, color: Art.claude, cols: 14, rows: 3)
                            DotBar(fill: 0.3, color: Art.codex, cols: 14, rows: 3)
                        }
                        .padding(10)
                    }
                }
            }
        }
    }
}
