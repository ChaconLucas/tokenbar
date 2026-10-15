import SwiftUI
import AppKit
import Combine

/// Ilha no notch: uma pílula preta colada na câmera do MacBook, com a % de cada IA nas "asas".
/// Passar o mouse abre a ilha (cresce para baixo, como a Dynamic Island do iPhone).
/// Sem notch (monitor externo, Mac sem notch): fica no alto, no meio, logo abaixo da barra de menu.
@MainActor
final class NotchIsland: NSObject {
    static let shared = NotchIsland()

    /// Há notch em alguma tela agora (decide o padrão do ajuste).
    static var screenHasNotch: Bool { NSScreen.screens.contains { $0.safeAreaInsets.top > 0 } }

    private var panel: NotchPanel?
    private let state = NotchState()
    private weak var model: MacModel?
    private var openMain: (() -> Void)?
    /// Abre os Ajustes (com a % só no notch, a ilha é a porta de entrada).
    var openSettings: (() -> Void)?
    private var expandWork: DispatchWorkItem?
    private var collapseWork: DispatchWorkItem?
    private var shrinkWork: DispatchWorkItem?
    private var observers: [NSObjectProtocol] = []
    /// Tamanho da pílula pedido pelo SwiftUI (o painel acompanha).
    private var shapeSize = CGSize(width: 300, height: 32)
    /// -TBNotchExpanded YES (capturas): começa aberta e não fecha sozinha.
    private var pinned = false

    /// Chamado uma vez, na abertura do app.
    func start(model: MacModel, openMain: @escaping () -> Void) {
        self.model = model
        self.openMain = openMain
        #if DEBUG
        if UserDefaults.standard.bool(forKey: "TBNotchExpanded") { pinned = true; state.expanded = true }
        #endif
        let nc = NotificationCenter.default
        observers.append(nc.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { NotchIsland.shared.screensChanged() }
        })
        // Trocar de mesa (ou entrar em app de tela cheia): garante a pílula na frente.
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { NotchIsland.shared.panel?.orderFrontRegardless() }
        })
        setEnabled(model.notchIsland)
    }

    func setEnabled(_ on: Bool) {
        guard let model else { return }
        if on {
            if panel == nil { build(model: model) }
            screensChanged()
            panel?.orderFrontRegardless()
        } else {
            panel?.orderOut(nil)
            panel = nil
        }
    }

    // MARK: Painel

    private func build(model: MacModel) {
        let view = NotchIslandView(state: state,
                                   open: { [weak self] in self?.openMain?(); self?.collapse() },
                                   fit: { [weak self] size in self?.fit(size) })
            .environmentObject(model)
        let host = FirstMouseHostingView(rootView: view)
        host.safeAreaRegions = []
        host.sizingOptions = []   // o painel manda no tamanho (como no Mini: senão entra em laço)

        let p = NotchPanel(contentRect: NSRect(x: 0, y: 0, width: 300, height: 32),
                           styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.identifier = NSUserInterfaceItemIdentifier("notch-island")
        p.isFloatingPanel = true
        // Acima da barra de menu e dos ícones dela; abaixo dos menus abertos e dos alertas do sistema.
        p.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        p.hidesOnDeactivate = false
        p.isMovable = false
        p.backgroundColor = .clear
        p.isOpaque = false
        p.hasShadow = false
        p.animationBehavior = .none

        // O SwiftUI vai dentro de uma caixa que só acompanha o painel; a caixa também sente o mouse.
        let box = NotchHoverView(frame: p.contentLayoutRect)
        box.onHover = { [weak self] inside in self?.hover(inside) }
        host.frame = box.bounds
        host.autoresizingMask = [.width, .height]
        host.translatesAutoresizingMaskIntoConstraints = true
        box.addSubview(host)
        p.contentView = box
        panel = p
    }

    /// Recalcula onde fica o notch (ou o meio do alto da tela) e reposiciona.
    private func screensChanged() {
        var noNotch = false
        #if DEBUG
        noNotch = UserDefaults.standard.bool(forKey: "TBNotchNoNotch")   // testa o caminho sem notch
        #endif
        let screen = (noNotch ? nil : NSScreen.screens.first { $0.safeAreaInsets.top > 0 }) ?? NSScreen.main ?? NSScreen.screens.first
        guard let screen else { return }
        var g = NotchGeometry()
        if !noNotch, screen.safeAreaInsets.top > 0, let l = screen.auxiliaryTopLeftArea, let r = screen.auxiliaryTopRightArea {
            g.hasNotch = true
            g.notchWidth = max(0, r.minX - l.maxX)
            g.band = screen.safeAreaInsets.top
            g.centerX = (l.maxX + r.minX) / 2
            g.top = screen.frame.maxY
        } else {
            let menu = screen.frame.maxY - screen.visibleFrame.maxY
            g.hasNotch = false
            g.notchWidth = 0
            g.band = 28
            g.centerX = screen.frame.midX
            g.top = screen.frame.maxY - (menu > 0 && menu < 60 ? menu : NSStatusBar.system.thickness)
        }
        if state.geometry != g { state.geometry = g }
        place(size: shapeSize)
    }

    // MARK: Tamanho

    /// O SwiftUI pediu outro tamanho: cresce na hora; encolhe depois da animação (senão corta a mola).
    private func fit(_ size: CGSize) {
        shapeSize = size
        shrinkWork?.cancel()
        guard let panel else { return }
        let cur = panel.frame.size
        let want = panelSize(for: size)
        if want.width >= cur.width && want.height >= cur.height {
            place(size: size)
        } else {
            place(size: CGSize(width: max(size.width, cur.width - 2 * NotchGeometry.flare),
                               height: max(size.height, cur.height)))
            let w = DispatchWorkItem { [weak self] in self?.place(size: size) }
            shrinkWork = w
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: w)
        }
    }

    private func panelSize(for size: CGSize) -> CGSize {
        CGSize(width: ceil(size.width + 2 * NotchGeometry.flare), height: ceil(size.height))
    }

    private func place(size: CGSize) {
        guard let panel else { return }
        let g = state.geometry
        let s = panelSize(for: size)
        let frame = NSRect(x: (g.centerX - s.width / 2).rounded(), y: g.top - s.height, width: s.width, height: s.height)
        if panel.frame != frame { panel.setFrame(frame, display: true) }
    }

    // MARK: Mouse

    private func hover(_ inside: Bool) {
        if inside {
            collapseWork?.cancel()
            guard !state.expanded else { return }
            let w = DispatchWorkItem { [weak self] in self?.setExpanded(true) }
            expandWork = w
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: w)
        } else {
            expandWork?.cancel()
            guard state.expanded, !pinned else { return }
            let w = DispatchWorkItem { [weak self] in self?.setExpanded(false) }
            collapseWork = w
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: w)
        }
    }

    private func collapse() {
        expandWork?.cancel(); collapseWork?.cancel()
        pinned = false
        setExpanded(false)
    }

    private func setExpanded(_ on: Bool) {
        guard state.expanded != on else { return }
        withAnimation(on ? .spring(response: 0.42, dampingFraction: 0.74) : .spring(response: 0.34, dampingFraction: 0.9)) {
            state.expanded = on
        }
    }
}

/// Onde a ilha mora e quanto mede o notch.
struct NotchGeometry: Equatable {
    var hasNotch = false
    /// Largura do notch (0 sem notch).
    var notchWidth: CGFloat = 0
    /// Altura da faixa de cima (a barra de menu ao lado do notch).
    var band: CGFloat = 32
    var centerX: CGFloat = 0
    /// Topo da pílula, em coordenadas de tela.
    var top: CGFloat = 0

    /// Curvinha côncava nos cantos de cima: a pílula "escorre" da borda da tela, como o próprio notch.
    static let flare: CGFloat = 7
    /// Cada asa (fora do notch) da pílula fechada.
    static let wing: CGFloat = 62

    var collapsedSize: CGSize {
        CGSize(width: hasNotch ? notchWidth + 2 * Self.wing : 2 * Self.wing + 16, height: band)
    }
    var expandedWidth: CGFloat { max(460, notchWidth + 2 * 178) }
}

@MainActor
final class NotchState: ObservableObject {
    @Published var expanded = false
    @Published var geometry = NotchGeometry()
}

/// Painel sem moldura que nunca rouba o foco.
final class NotchPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Aceita o primeiro clique: o app quase nunca está ativo quando se clica na ilha.
final class FirstMouseHostingView<V: View>: NSHostingView<V> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// Caixa do painel: sente o mouse entrar e sair (mesmo com o app inativo).
final class NotchHoverView: NSView {
    var onHover: ((Bool) -> Void)?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                       owner: self, userInfo: nil))
    }

    override func mouseEntered(with event: NSEvent) { onHover?(true) }
    override func mouseExited(with event: NSEvent) { onHover?(false) }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// Retângulo de cantos de baixo arredondados e cantos de cima côncavos (abrindo para fora, colados na borda da tela).
struct NotchShape: Shape {
    var flare: CGFloat
    var radius: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(flare, radius) }
        set { flare = newValue.first; radius = newValue.second }
    }

    func path(in rect: CGRect) -> Path {
        let f = min(flare, rect.width / 4, rect.height / 2)
        let r = min(radius, (rect.width - 2 * f) / 2, rect.height - f)
        let (minX, maxX, minY, maxY) = (rect.minX, rect.maxX, rect.minY, rect.maxY)
        var p = Path()
        p.move(to: CGPoint(x: minX, y: minY))
        p.addLine(to: CGPoint(x: maxX, y: minY))
        p.addArc(tangent1End: CGPoint(x: maxX - f, y: minY), tangent2End: CGPoint(x: maxX - f, y: minY + f), radius: f)
        p.addLine(to: CGPoint(x: maxX - f, y: maxY - r))
        p.addArc(tangent1End: CGPoint(x: maxX - f, y: maxY), tangent2End: CGPoint(x: maxX - f - r, y: maxY), radius: r)
        p.addLine(to: CGPoint(x: minX + f + r, y: maxY))
        p.addArc(tangent1End: CGPoint(x: minX + f, y: maxY), tangent2End: CGPoint(x: minX + f, y: maxY - r), radius: r)
        p.addLine(to: CGPoint(x: minX + f, y: minY + f))
        p.addArc(tangent1End: CGPoint(x: minX + f, y: minY), tangent2End: CGPoint(x: minX, y: minY), radius: f)
        p.closeSubpath()
        return p
    }
}

// MARK: - Conteúdo

/// Uma IA na ilha: % e reset de 5h e de 7d.
struct NotchRow: Identifiable, Hashable {
    var id: String
    var name: String
    var short: UsageWindow?
    var long: UsageWindow?

    func window(_ w: String) -> UsageWindow? { w == "long" ? (long ?? short) : short }
    func percent(_ w: String, at now: Date) -> Double { window(w)?.used(at: now) ?? 0 }
    func resets(_ w: String, at now: Date) -> Date? {
        guard let win = window(w), !win.didReset(at: now) else { return nil }
        return win.resetsAt
    }
}

struct NotchIslandView: View {
    @EnvironmentObject var model: MacModel
    @ObservedObject var state: NotchState
    var open: () -> Void
    var fit: (CGSize) -> Void

    /// "all" ou o id da IA; "short" | "long" | "both". As mesmas escolhas da ilha do iPhone.
    @AppStorage("notchAgent") private var agent = "all"
    @AppStorage("notchWindow") private var window = "short"

    private static let windows = ["short", "long", "both"]

    var body: some View {
        let g = state.geometry
        let rows = self.rows
        let size = state.expanded ? expandedSize(g, rows: rows.count) : g.collapsedSize
        let flare = NotchGeometry.flare
        let radius: CGFloat = state.expanded ? 24 : 10
        let shape = NotchShape(flare: flare, radius: radius)

        TimelineView(.periodic(from: .now, by: 30)) { ctx in
            ZStack(alignment: .top) {
                if state.expanded {
                    expanded(g, rows: rows, now: ctx.date)
                        .transition(.asymmetric(insertion: .opacity.animation(.easeOut(duration: 0.22).delay(0.08)),
                                                removal: .opacity.animation(.easeIn(duration: 0.1))))
                } else {
                    collapsed(g, rows: rows, now: ctx.date)
                        .transition(.asymmetric(insertion: .opacity.animation(.easeOut(duration: 0.2).delay(0.12)),
                                                removal: .opacity.animation(.easeIn(duration: 0.08))))
                }
            }
            .padding(.horizontal, flare)
            .frame(width: size.width + 2 * flare, height: size.height, alignment: .top)
            .background(shape.fill(.black))
            .clipShape(shape)
            .contentShape(shape)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .environment(\.colorScheme, .dark)
        .environment(\.locale, Lang.locale)
        .onAppear { fit(size) }
        .onChange(of: size) { _, s in fit(s) }
    }

    // MARK: Dados

    /// Todas as visíveis (até 3) ou só a IA escolhida (se ela sumir, volta para todas).
    private var rows: [NotchRow] {
        let s = model.snapshot
        var ps: [ProviderUsage]
        if agent != "all", let one = s.provider(agent) {
            ps = [one]
        } else {
            ps = model.visible.compactMap { s.provider($0) }
            if ps.isEmpty { ps = s.providers }
        }
        return ps.prefix(3).map { p in
            NotchRow(id: p.id, name: UsageStyle.shortName(p.id), short: p.windows.first,
                     long: p.windows.count > 1 ? p.windows[1] : nil)
        }
    }

    private var single: Bool { agent != "all" && model.snapshot.provider(agent) != nil }
    private var compactWindow: String { window == "long" ? "long" : "short" }

    private func cycleAgent() {
        let ids = model.snapshot.providers.map(\.id)
        let known = ["claude", "codex"].filter { ids.contains($0) }
        let list = ["all"] + known + ids.filter { !known.contains($0) }
        agent = list[((list.firstIndex(of: agent) ?? 0) + 1) % list.count]
    }

    private func cycleWindow() {
        window = Self.windows[((Self.windows.firstIndex(of: window) ?? 0) + 1) % Self.windows.count]
    }

    // MARK: Fechada

    private func collapsed(_ g: NotchGeometry, rows: [NotchRow], now: Date) -> some View {
        HStack(spacing: 0) {
            Group {
                if let first = rows.first {
                    NotchTag(row: first, window: compactWindow, now: now, theme: model.theme,
                             marker: window == "long" ? "7D" : nil)
                } else {
                    LEDText(text: "TOKENBAR", color: .white.opacity(0.8), dot: 1.1)
                }
            }
            .frame(width: NotchGeometry.wing - 12, alignment: .leading)
            .padding(.leading, 12)

            Spacer(minLength: g.hasNotch ? g.notchWidth : 16)

            Group {
                if !single && rows.count > 1 {
                    NotchTag(row: rows[1], window: compactWindow, now: now, theme: model.theme)
                } else if let row = rows.first {
                    if window == "both", let w = row.long {
                        HStack(spacing: 3) {
                            Text("7D").font(.system(size: 9, weight: .heavy, design: .monospaced))
                                .foregroundStyle(.white.opacity(0.55))
                            Text(UsageStyle.percent(w.used(at: now)))
                                .font(.system(size: 13, weight: .heavy, design: .monospaced))
                                .foregroundStyle(model.theme.fill(row.id, percent: w.used(at: now)))
                        }
                    } else {
                        NotchCountdown(resetsAt: row.resets(compactWindow, at: now), now: now)
                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                            .foregroundStyle(model.theme.timer.color)
                    }
                }
            }
            .frame(width: NotchGeometry.wing - 12, alignment: .trailing)
            .padding(.trailing, 12)
        }
        .frame(height: g.band)
        .lineLimit(1)
    }

    // MARK: Aberta

    private func lineDot(count: Int) -> CGFloat {
        switch (count <= 1, window == "both") {
        case (true, false): 3.4
        case (true, true): 2.8
        case (false, false): 2.6
        case (false, true): 2.0
        }
    }

    private func blockHeight(dot: CGFloat) -> CGFloat {
        window == "both" ? 18 * dot + dot * 2 : 9 * dot
    }

    private func blockSpacing(dot: CGFloat) -> CGFloat { window == "both" ? dot * 5.5 : 10 }

    private func expandedSize(_ g: NotchGeometry, rows count: Int) -> CGSize {
        let n = max(1, count)
        let dot = lineDot(count: n)
        let h = g.band + 14 + CGFloat(n) * blockHeight(dot: dot) + CGFloat(n - 1) * blockSpacing(dot: dot) + 32
        return CGSize(width: g.expandedWidth, height: ceil(h))
    }

    private func expanded(_ g: NotchGeometry, rows: [NotchRow], now: Date) -> some View {
        let dot = lineDot(count: rows.count)
        let theme = model.theme
        let agentText = single ? (rows.first.map { UsageStyle.abbr($0.id) } ?? "-") : Lang.t("TODAS")
        let agentColor = single ? (rows.first.map { theme.base($0.id) } ?? .white) : Color.white
        return VStack(spacing: 14) {
            // Faixa de cima: metade de cada lado do notch, com largura fixa — nada fica embaixo da câmera.
            let side = g.hasNotch ? (g.expandedWidth - g.notchWidth) / 2 - 18 : nil
            HStack(spacing: 0) {
                HStack(spacing: 6) {
                    Button(action: open) { LEDText(text: "TOKENBAR", color: .white, dot: 1.5).contentShape(Rectangle()) }
                        .buttonStyle(PressDown())
                        .help(Lang.t("Abrir o aparelho"))
                    Button { NotchIsland.shared.openSettings?() } label: {
                        NotchPill(text: Lang.t("AJUSTES"), color: .white.opacity(0.8), dot: 1.15)
                    }
                    .buttonStyle(PressDown())
                    .help(Lang.t("Ajustes"))
                }
                .frame(width: side, alignment: .leading)
                if g.hasNotch { Spacer().frame(width: g.notchWidth) } else { Spacer(minLength: 12) }
                HStack(spacing: 5) {
                    Button(action: cycleAgent) { NotchPill(text: "\(Lang.t("IA")) \(agentText) >", color: agentColor, dot: 1.15) }
                        .buttonStyle(PressDown())
                        .help(Lang.t("Trocar a IA"))
                    Button(action: cycleWindow) {
                        NotchPill(text: window == "long" ? "7D" : window == "both" ? "5H 7D" : "5H",
                                  color: theme.timer.color, dot: 1.15)
                    }
                    .buttonStyle(PressDown())
                    .help(Lang.t("Trocar a janela"))
                }
                .frame(width: side, alignment: .trailing)
            }
            .padding(.horizontal, 18)
            .frame(height: g.band)

            if rows.isEmpty {
                Text(Lang.t("Sem dados")).font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.5))
            } else {
                VStack(spacing: blockSpacing(dot: dot)) {
                    ForEach(rows) { row in
                        if window == "both" {
                            VStack(spacing: dot * 2) {
                                NotchLine(row: row, window: "short", left: row.name, right: "5H", now: now, theme: theme, dot: dot, rows: 9)
                                NotchLine(row: row, window: "long", left: nil, right: "7D", now: now, theme: theme, dot: dot, rows: 9)
                            }
                        } else {
                            NotchLine(row: row, window: window, left: row.name, right: nil, now: now, theme: theme, dot: dot, rows: 9)
                        }
                    }
                }
                .padding(.horizontal, 20)
            }
            Spacer(minLength: 0)
        }
    }
}

/// "CL 56%" na cor da IA (igual à ilha do iPhone).
struct NotchTag: View {
    var row: NotchRow
    var window: String
    var now: Date
    var theme: Theme
    var marker: String? = nil

    var body: some View {
        let pct = row.percent(window, at: now)
        let c = theme.fill(row.id, percent: pct)
        HStack(spacing: 4) {
            Text(UsageStyle.abbr(row.id))
                .font(.system(size: 10, weight: .heavy, design: .monospaced))
                .foregroundStyle(.black)
                .padding(.horizontal, 3).padding(.vertical, 1)
                .background(RoundedRectangle(cornerRadius: 3).fill(c))
            Text(row.window(window) == nil ? "--" : UsageStyle.percent(pct))
                .font(.system(size: 13, weight: .heavy, design: .monospaced))
                .foregroundStyle(c)
            if let marker {
                Text(marker)
                    .font(.system(size: 7, weight: .heavy, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.55))
                    .baselineOffset(5)
            }
        }
        .fixedSize()
    }
}

/// Pílula escura com o texto em pontos acesos (as teclas da ilha).
struct NotchPill: View {
    var text: String
    var color: Color
    var dot: CGFloat
    @State private var hover = false

    var body: some View {
        LEDText(text: text, color: color, dot: dot)
            .padding(.horizontal, dot * 3.5)
            .padding(.vertical, dot * 2.4)
            .background {
                Capsule().fill(.white.opacity(hover ? 0.16 : 0.08))
                    .overlay(Capsule().strokeBorder(color.opacity(0.45), lineWidth: 1))
            }
            .contentShape(Capsule())
            .onHover { hover = $0 }
    }
}

/// Uma faixa de pontos que enche com o gasto (nome e % escritos nela) e, à direita, a contagem.
struct NotchLine: View {
    var row: NotchRow
    var window: String
    var left: String?
    var right: String?
    var now: Date
    var theme: Theme
    var dot: CGFloat
    var rows: Int

    var body: some View {
        let pct = row.percent(window, at: now)
        let fill = theme.fill(row.id, percent: pct)
        let fs = max(11, dot * CGFloat(rows) * 0.6)
        HStack(spacing: 10) {
            GeometryReader { geo in
                let cols = max(24, Int(geo.size.width / dot))
                DotCanvas(bitmap: bitmap(cols: cols, pct: pct), dot: dot, textColor: theme.text.color,
                          fieldColor: fill.opacity(0.75), offColor: fill.opacity(0.13), round: theme.roundDots)
            }
            .frame(height: CGFloat(rows) * dot)
            NotchCountdown(resetsAt: row.resets(window, at: now), now: now)
                .font(.system(size: fs, weight: .bold, design: .monospaced))
                .foregroundStyle(window == "long" ? theme.timer.color.opacity(0.75) : theme.timer.color)
                .lineLimit(1).minimumScaleFactor(0.6)
                .frame(width: fs * 5, alignment: .trailing)
        }
    }

    private func bitmap(cols: Int, pct: Double) -> DotBitmap {
        var b = DotBitmap(cols: cols, rows: rows)
        let filled = Int((min(max(pct, 0), 100) / 100 * Double(cols)).rounded())
        for x in 0..<filled { for y in 0..<rows { b.set(x, y, 1) } }
        let num = row.window(window) == nil ? "--" : "\(min(Int(pct.rounded()), 999))%"
        let text = right.map { "\($0) \(num)" } ?? num
        let y = (rows - DotFont.height) / 2
        let rightX = cols - 2 - DotFont.width(text)
        b.draw(text, x: rightX, y: y)
        if let left {
            let name = 2 + DotFont.width(left) + 4 <= rightX ? left : LEDPanel.abbreviate(left)
            if 2 + DotFont.width(name) + 4 <= rightX { b.draw(name, x: 2, y: y) }
        }
        return b
    }
}

/// Contagem até zerar: hh:mm:ss andando sozinha; mais de um dia vira "3D 05H"; depois do reset, "--:--".
struct NotchCountdown: View {
    var resetsAt: Date?
    var now: Date

    var body: some View {
        if let r = resetsAt, r > now {
            let left = r.timeIntervalSince(now)
            if left >= 86400 {
                Text(String(format: "%dD %02dH", Int(left / 86400), Int(left.truncatingRemainder(dividingBy: 86400) / 3600)))
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
