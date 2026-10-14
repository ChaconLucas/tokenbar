import SwiftUI
import AppKit

/// Rótulo da barra de menu: uma mini barra de LED por IA, cheia até o gasto, com a % ao lado.
enum MenuBarImage {
    @MainActor
    static func make(snapshot: UsageSnapshot, visible: [String], windowChoice: String, theme: Theme) -> NSImage {
        let items = Prefs.allProviders.filter { visible.contains($0) }.map { id -> (String, Double?) in
            let w = Prefs.pickFrom(snapshot.provider(id), windowChoice == "both" ? "short" : windowChoice)
            return (id, w?.used())
        }
        let view = HStack(spacing: 7) {
            ForEach(items, id: \.0) { id, pct in
                HStack(spacing: 3) {
                    // 10 pontos em 2 linhas: acendem conforme o gasto, na cor da IA.
                    Canvas { ctx, size in
                        let lit = Int(((pct ?? 0) / 100 * 10).rounded())
                        let d: CGFloat = 2.6, gap: CGFloat = 0.9
                        for i in 0..<10 {
                            let x = CGFloat(i % 5) * (d + gap), y = CGFloat(i / 5) * (d + gap) + 4
                            let on = i < lit
                            ctx.fill(Path(ellipseIn: CGRect(x: x, y: y, width: d, height: d)),
                                     with: .color(on ? theme.fill(id, percent: pct ?? 0) : .white.opacity(0.28)))
                        }
                    }
                    .frame(width: 17, height: 14)
                    Text(pct.map { "\(Int($0.rounded()))%" } ?? "—")
                        .font(.system(size: 12, weight: .semibold, design: .rounded).monospacedDigit())
                        .foregroundStyle(.white)
                }
            }
            if items.isEmpty {
                Text("TokenBar").font(.system(size: 12, weight: .semibold)).foregroundStyle(.white)
            }
        }
        .padding(.horizontal, 1)
        .frame(height: 18)

        let r = ImageRenderer(content: view)
        r.scale = NSScreen.main?.backingScaleFactor ?? 2
        let img = r.nsImage ?? NSImage()
        img.isTemplate = false
        return img
    }
}

/// Janela "Mini": compacta, sem moldura, sempre na frente e em todas as mesas.
struct MiniWindow: View {
    @EnvironmentObject var model: MacModel
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow
    @AppStorage("miniWindowChoice") private var windowChoice = "both"

    var body: some View {
        let items = WidgetItems.make(model.snapshot, agent: "all", window: windowChoice)
            .filter { model.visible.contains($0.providerID) }
        TimelineView(.periodic(from: .now, by: 1)) { ctx in
            VStack(spacing: 4) {
                ForEach(items, id: \.key) { it in
                    MiniRow(item: it, now: ctx.date, theme: model.theme)
                        .frame(height: 24)
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
            }
        }
        .padding(6)
        .frame(width: 300)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.black)
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(.white.opacity(0.15)))
                .gesture(WindowDragGesture())
        }
        .environment(\.colorScheme, .dark)
        .contextMenu {
            Picker("Janela", selection: $windowChoice) {
                Text("5 horas").tag("short"); Text("7 dias").tag("long"); Text("As duas").tag("both")
            }
            Button("Abrir aparelho") { openWindow(id: "main"); NSApp.activate() }
            Divider()
            Button("Fechar Mini") { dismissWindow(id: "mini") }
        }
        .onAppear { pin(); UserDefaults.standard.set(true, forKey: "miniOpen") }
        .onDisappear { UserDefaults.standard.set(false, forKey: "miniOpen") }
    }

    /// Sempre na frente, em todas as mesas, inclusive sobre apps em tela cheia.
    private func pin() {
        DispatchQueue.main.async {
            guard let w = NSApp.windows.first(where: { $0.identifier?.rawValue == "mini" }) else { return }
            w.level = .floating
            w.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            w.isMovableByWindowBackground = true
            w.hasShadow = true
        }
    }
}

/// Uma linha do Mini: nome, tempo apagado e % — pontos grandes, fundo enchendo com o gasto.
struct MiniRow: View {
    var item: WidgetItems.Item
    var now: Date
    var theme: Theme

    static let cols = 88, rows = 11

    var body: some View {
        let p = item.window?.used(at: now) ?? 0
        GeometryReader { geo in
            let dot = geo.size.width / CGFloat(Self.cols)
            DotCanvas(bitmap: bitmap(p), dot: dot, textColor: theme.text.color,
                      fieldColor: theme.fill(item.providerID, percent: p).opacity(0.65),
                      offColor: theme.fill(item.providerID, percent: p).opacity(0.10), round: theme.roundDots)
                .frame(width: geo.size.width, height: geo.size.height)
        }
    }

    private func bitmap(_ p: Double) -> DotBitmap {
        var b = DotBitmap(cols: Self.cols, rows: Self.rows)
        let filled = Int((min(max(p, 0), 100) / 100 * Double(Self.cols)).rounded())
        for x in 0..<filled { for y in 0..<Self.rows { b.set(x, y, 1) } }
        let y = 2
        b.draw(item.title, x: 2, y: y)
        let big = item.window == nil ? "--" : "\(Int(p.rounded()))%"
        b.draw(big, x: Self.cols - 2 - DotFont.width(big), y: y)
        // Colunas fixas: o tempo termina sempre no mesmo ponto, antes do espaço reservado para "100%".
        let t = time
        let timeEnd = Self.cols - 2 - DotFont.width("100%") - 4
        b.draw(t, x: timeEnd - DotFont.width(t), y: y, value: 3)
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
