// Gera os ícones do TokenBar: swift scripts/make-icon.swift <pasta-de-saída>
import SwiftUI
import AppKit

let purple = Color(red: 0.62, green: 0.36, blue: 1.0)
let claude = Color(red: 0.85, green: 0.47, blue: 0.34)   // terracota

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
                        .fill(RadialGradient(colors: [claude.opacity(0.22), .clear], center: .init(x: 0.5, y: 0.5), startRadius: 0, endRadius: shape * 0.7))
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
                // Sol de raios (estilo do símbolo do Claude) amostrado numa grade de pontos.
                // Aceso no sentido horário a partir das 12h até `filled`, como um ponteiro de relógio.
                let n = 19
                let cell = s.width / CGFloat(n)
                let dot = cell * 0.82
                let c = Double(n) / 2
                let filled = 0.72
                let rays: [(angle: Double, length: Double)] = (0..<12).map { i in
                    let jitter = [0.0, 5, -4, 3, -5, 2, 4, -3, 4, -4, 1, -2][i]
                    let length = [8.6, 7.4, 8.2, 7.0, 8.8, 7.6, 8.0, 7.2, 8.6, 7.4, 8.2, 7.8][i]
                    return ((Double(i) * 30 + jitter) * .pi / 180, length)
                }
                func inside(_ px: Double, _ py: Double) -> Bool {
                    let dx = px - c, dy = py - c
                    let d = (dx * dx + dy * dy).squareRoot()
                    if d <= 1.4 { return true }
                    for r in rays {
                        // Projeção no eixo do raio (0 = topo, sentido horário).
                        let ux = sin(r.angle), uy = -cos(r.angle)
                        let along = dx * ux + dy * uy
                        let across = abs(dx * uy - dy * ux)
                        guard along > 0, along <= r.length else { continue }
                        let half = 0.95 * (1 - along / (r.length + 0.6)) + 0.12   // afina na ponta
                        if across <= half { return true }
                    }
                    return false
                }
                for y in 0..<n {
                    for x in 0..<n {
                        var hits = 0
                        for sy in 0..<5 { for sx in 0..<5 {
                            if inside(Double(x) + (Double(sx) + 0.5) / 5, Double(y) + (Double(sy) + 0.5) / 5) { hits += 1 }
                        } }
                        let inShape = hits >= 8
                        let dx = Double(x) + 0.5 - c, dy = Double(y) + 0.5 - c
                        var sweep = atan2(dx, -dy)
                        if sweep < 0 { sweep += 2 * .pi }
                        let lit = sweep / (2 * .pi) <= filled
                        let color: Color = inShape ? (lit ? claude : claude.opacity(0.34)) : .white.opacity(0.04)
                        let r = CGRect(x: CGFloat(x) * cell + (cell - dot) / 2, y: CGFloat(y) * cell + (cell - dot) / 2, width: dot, height: dot)
                        ctx.fill(Path(ellipseIn: r), with: .color(color))
                    }
                }
            }
            .frame(width: shape * 0.74, height: shape * 0.74)
            .shadow(color: claude.opacity(0.6), radius: shape * 0.03)
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
MainActor.assumeIsolated {
    render(DotIcon(size: 1024, fullBleed: false), 1024, to: out.appending(path: "mac-1024.png"))
    render(DotIcon(size: 1024, fullBleed: true), 1024, to: out.appending(path: "ios-1024.png"))
}
print("ok")
