import SwiftUI
import Combine
import WidgetKit

/// O aparelho é a tela inteira: vidro preto de ponta a ponta, as teclas acesas em pontos dentro dele.
/// Com mais de uma IA ligada, quem troca é a pessoa, arrastando o display para o lado.
struct BusyDevice: View {
    var snapshot: UsageSnapshot
    @Binding var visible: [String]
    @Binding var windowChoice: String
    var theme: Theme = Prefs.theme
    /// Com o tema editável, a tecla vira um botão "Editar" que abre o painel de aparência.
    var editableTheme: Binding<Theme>? = nil
    var onMore: (() -> Void)?
    /// Mac: tecla que troca entre o aparelho grande e o pequeno flutuante. Nil esconde a tecla.
    var swapKey: (label: String, action: () -> Void)? = nil
    var onSettings: (() -> Void)?
    /// Celular: sem moldura e o display ocupando a área inteira.
    var fullBleed = false
    /// Vidro líquido (macOS 26 / iOS 26) no lugar do vidro preto.
    var liquidGlass = false
    /// Margem lateral do aparelho (Dynamic Island), em pontos: o texto recua, o fundo não.
    var sideSafeInset: CGFloat = 0

    @State private var showEditor = false

    @State private var index = 0
    @State private var drag: CGFloat = 0          // trackpad (dois dedos)
    @GestureState private var mouseDrag: CGFloat = 0   // mouse/toque: volta a 0 sozinho se o gesto for interrompido
    @State private var lastTouch = Date.distantPast
    #if os(macOS)
    @State private var scrollMonitor: Any?
    @State private var hostWindow = WindowRef()
    @State private var scrolling = false
    @State private var scrollRaw: CGFloat = 0
    #endif
    @State private var pageWidth: CGFloat = 400

    var body: some View {
        GeometryReader { geo in
            // O tamanho do ponto acompanha a janela: o aparelho cresce inteiro, teclas junto.
            if fullBleed {
                // Celular: o display é a tela inteira e as teclas ficam dentro dele, na faixa de cima.
                let dot = geo.size.width / CGFloat(DotDisplay.totalCols)
                ZStack(alignment: .top) {
                    pager(topInset: Self.keyInsetRows)
                    keys(dot: dot * 0.42)
                        // Longe das quinas arredondadas da tela, que cortariam as teclas.
                        .padding(.horizontal, max(dot * 2.5, 44))
                        .padding(.top, max(dot * 1.2, 10))
                }
            } else {
                let pad = max(10, geo.size.height * 0.05)
                let keyDot = max(1.6, min(geo.size.height / 95, geo.size.width / 260))
                VStack(spacing: keyDot * 4) {
                    keys(dot: keyDot)
                    pager(topInset: 0)
                }
                .padding(pad)
            }
        }
        .background {
            // Mover o aparelho: pela borda e pela faixa das teclas, nunca pelo display (lá o arrasto troca de IA).
            #if os(macOS)
            glass.gesture(WindowDragGesture())
            #else
            glass.opacity(fullBleed ? 0 : 1)
            #endif
        }
        .onChange(of: visible) { _, v in if index >= v.count { index = 0 } }
        .task {
            // -TBShowEditor YES abre o painel ao iniciar (usado para capturas de tela).
            if editableTheme != nil, UserDefaults.standard.bool(forKey: "TBShowEditor") {
                try? await Task.sleep(for: .milliseconds(600))
                showEditor = true
            }
        }
        #if os(macOS)
        .background(WindowReader(ref: hostWindow))
        .onAppear(perform: installScroll)
        .onDisappear { if let m = scrollMonitor { NSEvent.removeMonitor(m) } }
        #endif
    }

    private var ids: [String] { visible.isEmpty ? Prefs.allProviders : visible }

    /// As IAs lado a lado; arrastar (ou deslizar dois dedos no trackpad) passa de uma para outra.
    /// Linhas de pontos reservadas no alto do display para as teclas (celular).
    static let keyInsetRows = 8

    private func pager(topInset: Int) -> some View {
        GeometryReader { geo in
            let w = geo.size.width
            TimelineView(.periodic(from: .now, by: 1)) { ctx in
                HStack(spacing: 0) {
                    ForEach(ids, id: \.self) { id in
                        let p = snapshot.provider(id)
                        DotDisplay(provider: p, providerID: id, window: Prefs.pickFrom(p, windowChoice),
                                   second: windowChoice == "both" && (p?.windows.count ?? 0) > 1 ? p?.windows[1] : nil,
                                   now: ctx.date, theme: theme, fillsArea: fullBleed, topInset: topInset,
                                   sideInset: Int((sideSafeInset * 0.7 / (w / CGFloat(DotDisplay.totalCols))).rounded(.up)))
                        .frame(width: w, height: geo.size.height)
                    }
                }
                .offset(x: -CGFloat(index % max(ids.count, 1)) * w + drag + mouseDrag)
            }
            .frame(width: w, alignment: .leading)
            .clipped()
            .contentShape(Rectangle())
            .gesture(
                // Espaço local: a conta não depende da janela (que não se move ao arrastar o display).
                DragGesture(minimumDistance: 4, coordinateSpace: .local)
                    .updating($mouseDrag) { v, state, _ in state = resisted(v.translation.width) }
                    .onEnded { v in settle(predicted: v.predictedEndTranslation.width, moved: v.translation.width) }
            )
            .onAppear { pageWidth = w }
            .onChange(of: w) { _, nw in pageWidth = nw }
        }
    }

    /// O display acompanha o dedo; nas pontas resiste, como uma lista que acabou.
    private func resisted(_ dx: CGFloat) -> CGFloat {
        guard ids.count > 1 else { return 0 }
        let atEdge = (index == 0 && dx > 0) || (index == ids.count - 1 && dx < 0)
        return atEdge ? dx / 3 : dx
    }

    private func follow(_ dx: CGFloat) { drag = resisted(dx) }

    /// Ao soltar: passou de um quarto da largura (ou foi rápido) troca de página; senão volta.
    private func settle(predicted: CGFloat, moved: CGFloat = 0) {
        // Troca com um arrasto curto (40 pt ou 15% da largura) ou com um gesto rápido.
        let limit = min(40, pageWidth * 0.15)
        let d = abs(moved) > abs(predicted) ? moved : predicted
        let step = d < -limit ? 1 : d > limit ? -1 : 0
        lastTouch = .now
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            index = min(max(index + step, 0), ids.count - 1)
            drag = 0
        }
    }

    /// Passo para o lado; no fim da fila volta ao começo.
    private func go(_ step: Int) {
        guard ids.count > 1 else { return }
        withAnimation(.spring(response: 0.4, dampingFraction: 0.9)) {
            index = (index + step + ids.count) % ids.count
        }
    }

    #if os(macOS)
    /// Dois dedos no trackpad: um deslize = um passo. Só reage o aparelho que está debaixo do cursor;
    /// a inércia e a roda repetida são ignoradas até o gesto acabar.
    private func installScroll() {
        guard scrollMonitor == nil else { return }
        scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { e in
            guard ids.count > 1, let win = e.window, win === hostWindow.window,
                  win.contentView?.hitTest(e.locationInWindow) != nil else { return e }
            // Inércia depois de soltar: engole sem fazer nada.
            if !e.momentumPhase.isEmpty { return nil }

            if e.phase.isEmpty {
                // Roda lateral de mouse: no máximo um passo a cada 0,5 s.
                guard abs(e.scrollingDeltaX) > abs(e.scrollingDeltaY), abs(e.scrollingDeltaX) > 3 else { return e }
                guard Date.now.timeIntervalSince(lastTouch) > 0.5 else { return nil }
                lastTouch = .now
                withAnimation(.spring(response: 0.35, dampingFraction: 0.9)) {
                    index = min(max(index + (e.scrollingDeltaX > 0 ? -1 : 1), 0), ids.count - 1)
                }
                return nil
            }
            if e.phase.contains(.began) || e.phase.contains(.mayBegin) {
                scrolling = abs(e.scrollingDeltaX) >= abs(e.scrollingDeltaY)
                scrollRaw = 0
            }
            guard scrolling else { return e }
            if e.phase.contains(.changed) || e.phase.contains(.began) {
                scrollRaw += e.scrollingDeltaX
                follow(scrollRaw)
            }
            if e.phase.contains(.ended) || e.phase.contains(.cancelled) {
                scrolling = false
                let step = scrollRaw < -40 ? 1 : scrollRaw > 40 ? -1 : 0
                lastTouch = .now
                withAnimation(.spring(response: 0.35, dampingFraction: 0.9)) {
                    index = min(max(index + step, 0), ids.count - 1)
                    drag = 0
                }
                scrollRaw = 0
            }
            return nil
        }
    }

    #endif

    // MARK: Teclas dentro da tela

    private func keys(dot: CGFloat) -> some View {
        HStack(spacing: dot * 5) {
            ForEach(Prefs.allProviders, id: \.self) { id in
                let on = visible.contains(id)
                DotKey(text: Prefs.allProviders.count > 2 ? UsageStyle.abbr(id) : UsageStyle.shortName(id),
                       on: on, color: theme.base(id), dot: dot, round: theme.roundDots) {
                    if on { if visible.count > 1 { visible.removeAll { $0 == id } } }
                    else { visible = Prefs.allProviders.filter { visible.contains($0) || $0 == id } }
                    save()
                }
            }
            Spacer(minLength: dot * 4)
            // Página atual quando alterna entre IAs.
            if visible.count > 1 {
                HStack(spacing: dot * 1.5) {
                    ForEach(visible.indices, id: \.self) { i in
                        Circle()
                            .fill(i == index % visible.count ? theme.base(visible[i]) : Color.white.opacity(0.15))
                            .onTapGesture { lastTouch = .now; withAnimation(.spring(response: 0.4, dampingFraction: 0.9)) { index = i } }
                            .frame(width: dot * 2.5, height: dot * 2.5)
                    }
                }
                Spacer(minLength: dot * 4)
            }
            DotKey(text: windowChoice == "long" ? "7D" : windowChoice == "both" ? "5H 7D" : "5H",
                   on: true, color: theme.timer.color, dot: dot, round: theme.roundDots) {
                windowChoice = windowChoice == "short" ? "long" : windowChoice == "long" ? "both" : "short"
                save()
            }
            if let swapKey {
                // Ícone em vez de palavra: "destacar" (vira flutuante) ou "expandir" (volta ao grande).
                Button(action: swapKey.action) {
                    Image(systemName: swapKey.label == "GRANDE" ? "arrow.up.left.and.arrow.down.right" : "pip.exit")
                        .font(.system(size: max(10, dot * 5), weight: .semibold))
                        .foregroundStyle(.white.opacity(0.85))
                        .padding(.horizontal, dot * 4).padding(.vertical, dot * 2.4)
                        .background(Capsule().fill(.black.opacity(0.72)).overlay(Capsule().strokeBorder(.white.opacity(0.25))))
                }
                .buttonStyle(PressDown())
                .help(swapKey.label == "GRANDE" ? Lang.t("Voltar ao aparelho grande") : Lang.t("Destacar: janelinha flutuante, sempre na frente"))
            }
            #if !os(watchOS)
            if let binding = editableTheme {
                Button { showEditor.toggle() } label: {
                    DotKeyFace(text: Lang.t("EDITAR"), on: true, color: theme.timer.color, dot: dot,
                               round: theme.roundDots, highlighted: showEditor)
                }
                .buttonStyle(PressDown())
                .popover(isPresented: $showEditor, arrowEdge: .bottom) {
                    DeviceEditor(theme: binding, onMore: onMore.map { more in { showEditor = false; more() } })
                        .preferredColorScheme(.dark)
                }
            }
            #endif
            if editableTheme == nil, let onSettings {
                DotKey(text: "SET", on: true, color: theme.timer.color, dot: dot, round: theme.roundDots, action: onSettings)
            }
        }
    }

    private func save() {
        Prefs.visible = visible
        Prefs.window = windowChoice
        WidgetCenter.shared.reloadAllTimelines()
    }

    // MARK: Vidro

    @ViewBuilder private var glass: some View {
        if liquidGlass, #available(macOS 26.0, iOS 26.0, watchOS 26.0, *) {
            // Vidro líquido escurecido: deixa ver o fundo e mantém os LEDs nítidos.
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(.black.opacity(0.35))
                .glassEffect(.regular.tint(.black.opacity(0.25)), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        } else {
            solidGlass
        }
    }

    private var solidGlass: some View {
        RoundedRectangle(cornerRadius: 22, style: .continuous)
            .fill(.black)
            .overlay {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(LinearGradient(colors: [.white.opacity(0.06), .clear], startPoint: .top, endPoint: .init(x: 0.5, y: 0.35)))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(LinearGradient(colors: [.white.opacity(0.20), .white.opacity(0.04)], startPoint: .top, endPoint: .bottom), lineWidth: 1)
            }
    }
}

/// Tecla desenhada em pontos de LED: acesa na cor quando ligada, apagada quando não.
struct DotKey: View {
    var text: String
    var on: Bool
    var color: Color
    var dot: CGFloat
    var round = true
    var action: () -> Void

    @State private var hover = false

    var body: some View {
        Button(action: action) { DotKeyFace(text: text, on: on, color: color, dot: dot, round: round, highlighted: hover) }
            .buttonStyle(PressDown())
            #if os(macOS)
            .onHover { hover = $0 }
            #endif
            .accessibilityLabel(text)
    }
}

/// O rosto da tecla: pílula escura com o texto em pontos acesos na cor (ou apagados quando desligada).
struct DotKeyFace: View {
    var text: String
    var on: Bool
    var color: Color
    var dot: CGFloat
    var round = true
    var highlighted = false

    var body: some View {
        let bitmap: DotBitmap = {
            var b = DotBitmap(cols: DotFont.width(text), rows: DotFont.height)
            b.draw(text, x: 0, y: 0, value: 2)
            return b
        }()
        let lit = on ? color : Color.white.opacity(0.32)
        DotCanvas(bitmap: bitmap, dot: dot, textColor: lit, fieldColor: .clear, offColor: .clear, round: round)
            .shadow(color: on ? color.opacity(0.8) : .clear, radius: dot * 1.2)
            .padding(.horizontal, dot * 4)
            .padding(.vertical, dot * 2.4)
            .background {
                // Fundo escuro: a tecla continua legível em cima do preenchimento colorido do display.
                Capsule().fill(.black.opacity(highlighted ? 0.55 : 0.72))
                    .overlay(Capsule().strokeBorder(lit.opacity(on ? 0.45 : 0.18), lineWidth: 1))
            }
    }
}

/// Afunda um pouco ao apertar.
struct PressDown: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .brightness(configuration.isPressed ? 0.2 : 0)
            .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
    }
}

extension Prefs {
    static func pickFrom(_ p: ProviderUsage?, _ choice: String) -> UsageWindow? {
        guard let p else { return nil }
        return choice == "long" ? (p.windows.count > 1 ? p.windows[1] : p.windows.first) : p.windows.first
    }
}

#if os(macOS)
/// Guarda a janela em que o aparelho está (para o trackpad só mexer no aparelho certo).
final class WindowRef { weak var window: NSWindow? }

struct WindowReader: NSViewRepresentable {
    var ref: WindowRef
    func makeNSView(context: Context) -> NSView {
        let v = NSView()
        DispatchQueue.main.async { ref.window = v.window }
        return v
    }
    func updateNSView(_ v: NSView, context: Context) {
        if ref.window == nil { DispatchQueue.main.async { ref.window = v.window } }
    }
}
#endif
