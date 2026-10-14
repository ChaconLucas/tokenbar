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
                // Medidor genérico de uso: anel de pontos aceso no sentido horário (roxo → ciano)
                // e um "%" de pontos no centro. Não é o símbolo de nenhuma IA.
                let c = CGPoint(x: s.width / 2, y: s.height / 2)
                let filled = 0.7
                for (ring, radius, count, dot) in [(0, 0.46, 40, 0.055), (1, 0.37, 32, 0.05)] {
                    for i in 0..<count {
                        let f = Double(i) / Double(count)
                        let a = f * 2 * .pi - .pi / 2
                        let r = Double(s.width) * radius
                        let p = CGPoint(x: c.x + CGFloat(r * cos(a)), y: c.y + CGFloat(r * sin(a)))
                        let d = s.width * dot
                        let lit = f < filled
                        let color: Color = lit ? mix(f / filled) : .white.opacity(ring == 0 ? 0.10 : 0.07)
                        ctx.fill(Path(ellipseIn: CGRect(x: p.x - d / 2, y: p.y - d / 2, width: d, height: d)), with: .color(color))
                    }
                }
                // "%" em pontos no meio.
                let glyph = ["##....#", "##...#.", "....#..", "...#...", "..#....", ".#...##", "#....##"]
                let cell = s.width * 0.062
                let ox = c.x - cell * 3.5, oy = c.y - cell * 3.5
                for (y, row) in glyph.enumerated() {
                    for (x, ch) in row.enumerated() where ch == "#" {
                        let d = cell * 0.8
                        ctx.fill(Path(ellipseIn: CGRect(x: ox + CGFloat(x) * cell + (cell - d) / 2,
                                                        y: oy + CGFloat(y) * cell + (cell - d) / 2, width: d, height: d)),
                                 with: .color(.white))
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
MainActor.assumeIsolated {
    render(DotIcon(size: 1024, fullBleed: false), 1024, to: out.appending(path: "mac-1024.png"))
    render(DotIcon(size: 1024, fullBleed: true), 1024, to: out.appending(path: "ios-1024.png"))
}
print("ok")
