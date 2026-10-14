// Gera os ícones do TokenBar: swift scripts/make-icon.swift <pasta-de-saída>
import SwiftUI
import AppKit

let purple = Color(red: 0.62, green: 0.36, blue: 1.0)
let cyan = Color(red: 0.20, green: 0.85, blue: 0.95)
/// Roxo → ciano ao longo do anel.
func mix(_ t: Double) -> Color {
    Color(red: 0.62 + (0.20 - 0.62) * t, green: 0.36 + (0.85 - 0.36) * t, blue: 1.0 + (0.95 - 1.0) * t)
}

// "%" em 7×7 numa grade 11×11
let glyph = ["##....#", "##...#.", "....#..", "...#...", "..#....", ".#...##", "#....##"]

struct DotIcon: View {
    var size: CGFloat
    var fullBleed: Bool   // iPhone/Watch: o sistema recorta; Mac: a forma vem desenhada

    var body: some View {
        let shape = fullBleed ? size : size * 0.805
        let radius = fullBleed ? 0 : shape * 0.225
        ZStack {
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(LinearGradient(colors: [Color(white: 0.13), Color(white: 0.02)], startPoint: .top, endPoint: .bottom))
                .overlay {
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .fill(RadialGradient(colors: [purple.opacity(0.25), .clear], center: .init(x: 0.5, y: 0.5), startRadius: 0, endRadius: shape * 0.7))
                }
                .overlay {
                    if !fullBleed {
                        RoundedRectangle(cornerRadius: radius, style: .continuous)
                            .strokeBorder(LinearGradient(colors: [.white.opacity(0.25), .white.opacity(0.03)], startPoint: .top, endPoint: .bottom), lineWidth: shape * 0.006)
                    }
                }
                .frame(width: shape, height: shape)
                .shadow(color: .black.opacity(fullBleed ? 0 : 0.45), radius: size * 0.02, y: size * 0.012)

            Canvas { ctx, s in
                let n = 17
                let cell = s.width / CGFloat(n)
                let dotD = cell * 0.8
                func put(_ x: Int, _ y: Int, _ color: Color) {
                    ctx.fill(Path(ellipseIn: CGRect(x: CGFloat(x) * cell + (cell - dotD) / 2,
                                                    y: CGFloat(y) * cell + (cell - dotD) / 2, width: dotD, height: dotD)),
                             with: .color(color))
                }
                let off = Color.white.opacity(0.06)
                switch style {
                case "display":
                    // Mini display do app: bloco cheio até 60% com "42%" em cima.
                    for y in 0..<n { for x in 0..<n { put(x, y, off) } }
                    for y in 3...13 { for x in 1...15 { put(x, y, x <= 9 ? purple.opacity(0.75) : .white.opacity(0.10)) } }
                    let g4 = ["#..#", "#..#", "####", "...#", "...#"], g2 = ["###", "..#", "###", "#..", "###"]
                    for (r, row) in g4.enumerated() { for (c, ch) in row.enumerated() where ch == "#" { put(3 + c, 6 + r, .white) } }
                    for (r, row) in g2.enumerated() { for (c, ch) in row.enumerated() where ch == "#" { put(8 + c, 6 + r, .white) } }
                    let pc = ["#..#", "..#.", ".#..", "#..#"]
                    for (r, row) in pc.enumerated() { for (c, ch) in row.enumerated() where ch == "#" { put(12 + c, 6 + r, .white) } }
                case "bars":
                    // Medidor de barras (VU): colunas subindo, roxo→ciano.
                    let heights = [4, 6, 9, 7, 11, 13, 10, 12]
                    for y in 0..<n { for x in 0..<n { put(x, y, off) } }
                    for (i, h) in heights.enumerated() {
                        let x = 1 + i * 2
                        for k in 0..<h { put(x, 15 - k, mix(Double(i) / Double(heights.count - 1))) }
                    }
                case "coin":
                    // Ficha de token: círculo de pontos com um "T" no meio.
                    let c = Double(n - 1) / 2
                    for y in 0..<n { for x in 0..<n {
                        let d = ((Double(x) - c) * (Double(x) - c) + (Double(y) - c) * (Double(y) - c)).squareRoot()
                        var color = off
                        if d <= 7.6 { color = mix(Double(y) / Double(n - 1)).opacity(d > 6.4 ? 1 : 0.35) }
                        if (y == 4 && x >= 4 && x <= 12) || (x == 8 && y >= 4 && y <= 12) || (x == 7 && y >= 5 && y <= 12) || (x == 9 && y >= 5 && y <= 12) || (y == 5 && x >= 4 && x <= 12) { color = .white }
                        put(x, y, color)
                    } }
                case "star":
                    // Sol de raios neutro, aceso no sentido horário roxo→ciano.
                    let c = Double(n) / 2
                    for y in 0..<n { for x in 0..<n {
                        let dx = Double(x) + 0.5 - c, dy = Double(y) + 0.5 - c
                        let d = (dx * dx + dy * dy).squareRoot()
                        var sweep = atan2(dx, -dy); if sweep < 0 { sweep += 2 * .pi }
                        let ang = sweep.truncatingRemainder(dividingBy: .pi / 4)
                        let onRay = min(ang, .pi / 4 - ang) * d < 0.75 && d < 8
                        let inShape = d < 1.6 || onRay
                        let f = sweep / (2 * .pi)
                        put(x, y, inShape ? (f < 0.75 ? mix(f / 0.75) : .white.opacity(0.18)) : off)
                    } }
                case "ring":
                    // Anel de pontos (o atual) em grade: aceso até 70%.
                    let c = Double(n - 1) / 2
                    for y in 0..<n { for x in 0..<n {
                        let dx = Double(x) - c, dy = Double(y) - c
                        let d = (dx * dx + dy * dy).squareRoot()
                        var sweep = atan2(dx, -dy); if sweep < 0 { sweep += 2 * .pi }
                        let f = sweep / (2 * .pi)
                        var color = off
                        if d > 5.6 && d < 8.2 { color = f < 0.7 ? mix(f / 0.7) : .white.opacity(0.12) }
                        put(x, y, color)
                    } }
                    let glyph = ["#...#", "...#.", "..#..", ".#...", "#...#"]
                    for (r, row) in glyph.enumerated() { for (cc, ch) in row.enumerated() where ch == "#" { put(6 + cc, 6 + r, .white) } }
                case "battery":
                    // Bateria deitada: corpo 13×7 com polo à direita; carga roxo→ciano até 60%.
                    for y in 0..<n { for x in 0..<n { put(x, y, off) } }
                    let x0 = 1, x1 = 14, y0 = 5, y1 = 11
                    for x in x0...x1 { put(x, y0, .white); put(x, y1, .white) }
                    for y in y0...y1 { put(x0, y, .white); put(x1, y, .white) }
                    for y in 7...9 { put(15, y, .white) }
                    let inner = (x0 + 2)...(x1 - 2)
                    let full = inner.lowerBound + Int(Double(inner.count) * 0.6) - 1
                    for x in inner { for y in (y0 + 2)...(y1 - 2) {
                        put(x, y, x <= full ? mix(Double(x - inner.lowerBound) / Double(inner.count - 1)) : .white.opacity(0.10))
                    } }
                default:
                    // Ampulheta: em cima sobra (roxo), embaixo já caiu (ciano), um fio no meio.
                    for y in 0..<n {
                        let half = y < n / 2 ? (n / 2 - y) : (y - n / 2)
                        let w = max(0, min(7, half))   // meia-largura por linha
                        for x in 0..<n {
                            let dx = abs(x - n / 2)
                            var color = off
                            if y == 1 || y == n - 2 { if dx <= 7 { color = .white } }
                            else if y > 1 && y < n - 2 && dx == w && w > 0 { color = .white.opacity(0.85) }
                            else if y > 2 && y < n / 2 - 1 && dx < w && y >= 5 { color = purple }
                            else if y > n / 2 + 1 && y < n - 2 && dx < w && y >= 12 { color = cyan }
                            else if x == n / 2 && y >= n / 2 - 1 && y <= n / 2 + 3 { color = mix(0.5) }
                            put(x, y, color)
                        }
                    }
                }
            }
            .frame(width: shape * 0.74, height: shape * 0.74)
            .shadow(color: purple.opacity(0.6), radius: shape * 0.03)
        }
        .frame(width: size, height: size)
    }
}

@MainActor func render(_ view: some View, _ size: CGFloat, to url: URL) {
    let r = ImageRenderer(content: view)
    r.scale = 1
    r.proposedSize = .init(width: size, height: size)
    guard let cg = r.cgImage else { fatalError("render") }
    let rep = NSBitmapImageRep(cgImage: cg)
    try! rep.representation(using: .png, properties: [:])!.write(to: url)
}

let out = URL(fileURLWithPath: CommandLine.arguments[1])
let style = CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : "hourglass"
MainActor.assumeIsolated {
    render(DotIcon(size: 1024, fullBleed: false), 1024, to: out.appending(path: "mac-1024.png"))
    render(DotIcon(size: 1024, fullBleed: true), 1024, to: out.appending(path: "ios-1024.png"))
}
print("ok")
