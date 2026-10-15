import SwiftUI

#if os(macOS) || os(iOS)

/// Peças de ajustes com a cara do aparelho: texto em pontos, teclas de LED, chave acesa,
/// brilho em fileira de pontos, paleta de bolinhas. Pouco texto; explicação vai no ⓘ.

/// Texto desenhado em pontos de LED.
struct LEDText: View {
    var text: String
    var color: Color = .white
    var dot: CGFloat = 1.6

    var body: some View {
        let bitmap: DotBitmap = {
            var b = DotBitmap(cols: max(1, DotFont.width(text)), rows: DotFont.height)
            b.draw(text, x: 0, y: 0, value: 2)
            return b
        }()
        DotCanvas(bitmap: bitmap, dot: dot, textColor: color, fieldColor: .clear, offColor: .clear)
            .shadow(color: color.opacity(0.5), radius: dot)
    }
}

/// Grupo de teclas de LED onde só uma fica acesa (abas, idioma, formato dos pontos).
struct LEDChoice<T: Hashable>: View {
    var options: [(T, String)]
    @Binding var selection: T
    var color: Color = Arcade.cyan
    var dot: CGFloat = 1.5

    var body: some View {
        HStack(spacing: 6) {
            ForEach(options, id: \.0) { value, label in
                DotKey(text: label, on: value == selection, color: color, dot: dot) { selection = value }
            }
        }
    }
}

/// Chave liga/desliga: o ponto acende na cor quando ligada.
struct LEDSwitch: View {
    @Binding var isOn: Bool
    var color: Color = Arcade.green

    var body: some View {
        Button { withAnimation(.easeOut(duration: 0.15)) { isOn.toggle() } } label: {
            Capsule()
                .fill(.black)
                .overlay(Capsule().strokeBorder((isOn ? color : .white).opacity(isOn ? 0.6 : 0.2), lineWidth: 1))
                .overlay(alignment: isOn ? .trailing : .leading) {
                    Circle().fill(isOn ? color : .white.opacity(0.25))
                        .frame(width: 12, height: 12)
                        .shadow(color: isOn ? color : .clear, radius: 5)
                        .padding(4)
                }
                .frame(width: 40, height: 20)
        }
        .buttonStyle(.plain)
        .accessibilityValue(isOn ? "on" : "off")
    }
}

/// Valor contínuo como fileira de pontos: clica no ponto para escolher.
struct LEDDots: View {
    @Binding var value: Double
    var range: ClosedRange<Double>
    var steps = 12
    var color: Color = Arcade.cyan

    var body: some View {
        let lit = Int(((value - range.lowerBound) / (range.upperBound - range.lowerBound) * Double(steps)).rounded())
        HStack(spacing: 4) {
            ForEach(0..<steps, id: \.self) { i in
                Circle()
                    .fill(i < lit ? color : .white.opacity(0.1))
                    .frame(width: 10, height: 10)
                    .shadow(color: i < lit ? color.opacity(0.7) : .clear, radius: 3)
                    .contentShape(Rectangle().inset(by: -2))
                    .onTapGesture {
                        // Clicar no último aceso apaga tudo (zero); nos outros, acende até ali.
                        let n = (i + 1 == lit) ? 0 : i + 1
                        value = range.lowerBound + (range.upperBound - range.lowerBound) * Double(n) / Double(steps)
                    }
            }
        }
    }
}

/// Paleta de cores em bolinhas, com a do sistema no fim para qualquer outra.
struct LEDSwatches: View {
    @Binding var value: RGBA
    static let palette: [RGBA] = [
        RGBA(0.62, 0.36, 1.0), RGBA(0.93, 0.16, 0.76), RGBA(0.20, 0.85, 0.95), RGBA(0.35, 0.85, 0.45),
        RGBA(1.0, 0.78, 0.10), RGBA(1.0, 0.42, 0.20), RGBA(1, 1, 1),
    ]

    var body: some View {
        HStack(spacing: 6) {
            ForEach(Self.palette, id: \.self) { c in
                let on = close(c, value)
                Circle().fill(c.color)
                    .frame(width: 16, height: 16)
                    .overlay(Circle().strokeBorder(.white, lineWidth: on ? 2 : 0).padding(-3))
                    .shadow(color: c.color.opacity(on ? 0.8 : 0.3), radius: on ? 5 : 2)
                    .onTapGesture { value = c }
            }
            // Qualquer outra cor: bolinha de arco-íris que abre o seletor do sistema.
            let rainbow = Circle()
                .fill(AngularGradient(colors: [.red, .yellow, .green, .cyan, .blue, .purple, .red], center: .center))
                .frame(width: 16, height: 16)
                .overlay(Circle().strokeBorder(.white.opacity(0.5), lineWidth: 1))
            #if os(macOS)
            Button { ColorPanel.shared.open(value) { value = $0 } } label: { rainbow }
                .buttonStyle(.plain)
            #else
            rainbow.overlay {
                ColorPicker("", selection: Binding(get: { value.color }, set: { value = RGBA($0) }), supportsOpacity: false)
                    .labelsHidden().opacity(0.02)
            }
            #endif
        }
    }

    private func close(_ a: RGBA, _ b: RGBA) -> Bool {
        abs(a.r - b.r) + abs(a.g - b.g) + abs(a.b - b.b) < 0.06
    }
}

#if os(macOS)
/// O seletor de cores do macOS, devolvendo cada cor escolhida para quem abriu.
final class ColorPanel: NSObject {
    static let shared = ColorPanel()
    private var onChange: ((RGBA) -> Void)?

    func open(_ current: RGBA, onChange: @escaping (RGBA) -> Void) {
        self.onChange = onChange
        let panel = NSColorPanel.shared
        panel.showsAlpha = false
        panel.color = NSColor(current.color)
        panel.setTarget(self)
        panel.setAction(#selector(changed(_:)))
        panel.makeKeyAndOrderFront(nil)
    }

    @objc private func changed(_ panel: NSColorPanel) {
        onChange?(RGBA(Color(nsColor: panel.color)))
    }
}
#endif

/// ⓘ que abre a explicação num balão: o texto longo sai da tela.
struct InfoTip: View {
    var text: String
    @State private var shown = false

    var body: some View {
        Button { shown.toggle() } label: {
            Image(systemName: "info.circle").foregroundStyle(.white.opacity(0.45))
        }
        .buttonStyle(.plain)
        .popover(isPresented: $shown) {
            Text(text).font(.callout).padding(14).frame(width: 280).fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// Linha de ajuste: rótulo em LED à esquerda, controle à direita, filete embaixo.
struct LEDRow<Control: View>: View {
    var label: String
    var info: String? = nil
    @ViewBuilder var control: Control

    var body: some View {
        HStack(spacing: 10) {
            Text(label).font(Arcade.label(11)).tracking(2).foregroundStyle(.white.opacity(0.8))
            if let info { InfoTip(text: info) }
            Spacer(minLength: 12)
            control
        }
        .frame(minHeight: 28)
        .padding(.vertical, 5)
    }
}

/// O vidro preto onde as linhas moram, com filetes entre elas.
struct LEDGroup<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        Group {
            if #available(iOS 18.0, macOS 15.0, *) {
                VStack(spacing: 0) {
                    Group(subviews: content) { rows in
                        ForEach(Array(rows.enumerated()), id: \.offset) { i, row in
                            if i > 0 { Rectangle().fill(.white.opacity(0.06)).frame(height: 1) }
                            row
                        }
                    }
                }
            } else {
                VStack(spacing: 0) { content }
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 6)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(LinearGradient(colors: [Color(white: 0.07), Color(white: 0.03)], startPoint: .top, endPoint: .bottom))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(.white.opacity(0.09)))
        }
    }
}

/// Pontinho de estado + texto curto: verde funcionando, âmbar esperando, cinza desligado.
struct LEDStatus: View {
    enum Kind { case ok, wait, off, error }
    var kind: Kind
    var text: String

    var body: some View {
        let c: Color = switch kind {
        case .ok: Arcade.green
        case .wait: Arcade.amber
        case .off: .white.opacity(0.35)
        case .error: Arcade.red
        }
        HStack(spacing: 6) {
            Circle().fill(c).frame(width: 7, height: 7).shadow(color: c, radius: kind == .off ? 0 : 4)
            Text(text).font(Arcade.label(10)).tracking(1).foregroundStyle(c)
        }
    }
}
#endif
