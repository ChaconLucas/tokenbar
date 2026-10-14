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

/// Mini: painel flutuante de verdade (NSPanel). Fica por cima de tudo, inclusive de apps em tela cheia,
/// vai para todas as mesas e pode ser redimensionado pelas bordas, mantendo a proporção.
@MainActor
final class MiniPanel: NSObject, NSWindowDelegate {
    static let shared = MiniPanel()
    private var panel: NSPanel?
    static let ratio = NSSize(width: 420, height: 150)

    var isOpen: Bool { panel?.isVisible == true }

    func show(model: MacModel, openMain: @escaping () -> Void) {
        if let panel { panel.orderFrontRegardless(); return }
        let view = MiniContent(close: { [weak self] in self?.close() },
                               grande: { [weak self] in openMain(); self?.close() })
            .environmentObject(model)
        let host = NSHostingView(rootView: view)
        host.safeAreaRegions = []   // sem a faixa da barra de título escondida
        host.sizingOptions = []     // o painel manda no tamanho; o SwiftUI só acompanha (senão entra em laço)

        let w = UserDefaults.standard.double(forKey: "miniWidth")
        let width = w > 0 ? w : Self.ratio.width
        let size = NSSize(width: width, height: width * Self.ratio.height / Self.ratio.width)
        let p = NSPanel(contentRect: NSRect(origin: .zero, size: size),
                        styleMask: [.titled, .fullSizeContentView, .resizable, .nonactivatingPanel, .utilityWindow],
                        backing: .buffered, defer: false)
        p.identifier = NSUserInterfaceItemIdentifier("mini-panel")
        p.titleVisibility = .hidden
        p.titlebarAppearsTransparent = true
        [.closeButton, .miniaturizeButton, .zoomButton].forEach { p.standardWindowButton($0)?.isHidden = true }
        p.isFloatingPanel = true
        p.level = .statusBar                 // acima de janelas normais e de flutuantes comuns
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        p.hidesOnDeactivate = false
        p.isMovableByWindowBackground = false  // o arrasto no display troca de IA; mover é pela borda/teclas
        p.backgroundColor = .clear
        p.isOpaque = false
        p.hasShadow = true
        p.contentAspectRatio = Self.ratio
        p.contentMinSize = NSSize(width: 210, height: 75)
        p.contentMaxSize = NSSize(width: 1400, height: 500)
        // O SwiftUI vai dentro de uma caixa que só acompanha o painel (sem restrições de tamanho brigando).
        let box = NSView(frame: NSRect(origin: .zero, size: size))
        host.frame = box.bounds
        host.autoresizingMask = [.width, .height]
        host.translatesAutoresizingMaskIntoConstraints = true
        box.addSubview(host)
        p.contentView = box
        p.delegate = self

        if let x = UserDefaults.standard.object(forKey: "miniX") as? Double,
           let y = UserDefaults.standard.object(forKey: "miniY") as? Double {
            p.setFrameOrigin(NSPoint(x: x, y: y))
        } else if let screen = NSScreen.main {
            p.setFrameOrigin(NSPoint(x: screen.visibleFrame.maxX - size.width - 24, y: screen.visibleFrame.maxY - size.height - 24))
        }
        p.orderFrontRegardless()
        panel = p
        UserDefaults.standard.set(true, forKey: "miniOpen")
    }

    func close() {
        panel?.orderOut(nil)
        panel = nil
        UserDefaults.standard.set(false, forKey: "miniOpen")
    }

    func windowDidMove(_ n: Notification) { save() }
    func windowDidResize(_ n: Notification) { save() }

    private func save() {
        guard let f = panel?.frame else { return }
        UserDefaults.standard.set(f.origin.x, forKey: "miniX")
        UserDefaults.standard.set(f.origin.y, forKey: "miniY")
        UserDefaults.standard.set(f.width, forKey: "miniWidth")
    }
}

/// O conteúdo do Mini: o aparelho do app, que cresce e encolhe com o painel.
struct MiniContent: View {
    @EnvironmentObject var model: MacModel
    var close: () -> Void
    var grande: () -> Void
    @State private var hover = false

    var body: some View {
        // Desenhado num tamanho base e escalado por igual: diminuir o painel encolhe tudo junto, nada é cortado.
        GeometryReader { geo in
            let base = MiniPanel.ratio
            let k = min(geo.size.width / base.width, geo.size.height / base.height)
            BusyDevice(snapshot: model.snapshot, visible: $model.visible, windowChoice: $model.windowChoice,
                       theme: model.theme, swapKey: ("GRANDE", grande))
                .frame(width: base.width, height: base.height)
                .scaleEffect(k, anchor: .topLeading)
                .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
        }
            .overlay(alignment: .bottomTrailing) {
                // Fechar: aparece ao passar o mouse, no canto de baixo (fora das teclas).
                Button(action: close) {
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 16, height: 16)
                        .background(Circle().fill(.black.opacity(0.9)))
                        .overlay(Circle().strokeBorder(.white.opacity(0.4)))
                }
                .buttonStyle(.plain)
                .offset(x: -3, y: -3)
                .opacity(hover ? 1 : 0)
                .animation(.easeOut(duration: 0.15), value: hover)
                .help("Fechar")
            }
            .onHover { hover = $0 }
            .environment(\.colorScheme, .dark)
            .contextMenu {
                Button("Voltar ao aparelho grande", action: grande)
                Divider()
                Button("Fechar Mini", action: close)
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
