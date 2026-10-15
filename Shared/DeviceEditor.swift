import SwiftUI

#if !os(watchOS)
/// Gaveta de edição que desce de dentro do aparelho: muda cores e pontos ao vivo.
struct DeviceEditor: View {
    @Binding var theme: Theme
    var onMore: (() -> Void)?

    static let presets: [RGBA] = [
        RGBA(0.62, 0.36, 1.0),   // roxo
        RGBA(0.93, 0.16, 0.76),  // rosa
        RGBA(0.20, 0.85, 0.95),  // ciano
        RGBA(0.22, 1.0, 0.42),   // verde
        RGBA(1.0, 0.70, 0.10),   // âmbar
        RGBA(1.0, 0.27, 0.27),   // vermelho
        RGBA(1, 1, 1),           // branco
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(Lang.t("APARÊNCIA")).font(Arcade.label(11)).tracking(3).foregroundStyle(Arcade.dim)
            VStack(alignment: .leading, spacing: 10) {
                swatchRow("CLAUDE", $theme.claude)
                swatchRow("CODEX", $theme.codex)
                swatchRow(Lang.t("TEXTO"), $theme.text)
                swatchRow(Lang.t("TEMPO"), $theme.timer)
            }
            Divider().opacity(0.4)
            HStack(spacing: 12) {
                Text(Lang.t("PONTOS")).font(Arcade.label(10)).foregroundStyle(Arcade.dim).frame(width: 54, alignment: .leading)
                segmented
                Spacer()
            }
            HStack(spacing: 12) {
                Text(Lang.t("BRILHO")).font(Arcade.label(10)).foregroundStyle(Arcade.dim).frame(width: 54, alignment: .leading)
                Slider(value: $theme.glow, in: 0...2)
            }
            HStack {
                Text(Lang.t("Vermelho a partir de 85%"))
                Spacer()
                Toggle("", isOn: $theme.warnRed).labelsHidden().disabled(theme.levelColors)
            }
            HStack {
                Text(Lang.t("Cor pelo uso (verde → vermelho)"))
                Spacer()
                Toggle("", isOn: $theme.levelColors).labelsHidden()
            }
            HStack {
                Button(Lang.t("Restaurar padrão")) { withAnimation { theme = .standard } }
                Spacer()
                if let onMore { Button(Lang.t("Mais ajustes…"), action: onMore) }
            }
            .padding(.top, 2)
        }
        .font(.callout)
        .toggleStyle(.switch)
        .controlSize(.small)
        .tint(theme.claude.color)
        .padding(18)
        .frame(width: 380)
    }

    private var segmented: some View {
        HStack(spacing: 0) {
            ForEach([(true, "●"), (false, "■")], id: \.0) { round, label in
                Button {
                    withAnimation(.easeOut(duration: 0.15)) { theme.roundDots = round }
                } label: {
                    Text(label)
                        .font(.system(size: 11))
                        .frame(width: 28, height: 22)
                        .foregroundStyle(theme.roundDots == round ? Color.black : .white.opacity(0.7))
                        .background(theme.roundDots == round ? Color.white : .clear, in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(Capsule().fill(.white.opacity(0.08)))
        .accessibilityLabel(Lang.t("Formato dos pontos"))
    }

    private func swatchRow(_ label: String, _ value: Binding<RGBA>) -> some View {
        HStack(spacing: 7) {
            Text(label).font(Arcade.label(10)).tracking(1).foregroundStyle(Arcade.dim)
                .frame(width: 54, alignment: .leading)
            ForEach(Self.presets, id: \.self) { c in
                let selected = close(c, value.wrappedValue)
                Button {
                    withAnimation(.easeOut(duration: 0.15)) { value.wrappedValue = c }
                } label: {
                    Circle()
                        .fill(c.color)
                        .frame(width: 16, height: 16)
                        .overlay(Circle().strokeBorder(.white, lineWidth: selected ? 2 : 0).padding(-3))
                        .shadow(color: c.color.opacity(selected ? 0.8 : 0), radius: 4)
                }
                .buttonStyle(PressDown())
            }
            // Qualquer outra cor: bolinha de arco-íris; o seletor do sistema fica invisível por cima dela.
            let custom = !Self.presets.contains { close($0, value.wrappedValue) }
            ZStack {
                Circle()
                    .fill(AngularGradient(colors: [.red, .yellow, .green, .cyan, .blue, .purple, .red], center: .center))
                    .frame(width: 16, height: 16)
                    .overlay(Circle().strokeBorder(.white, lineWidth: custom ? 2 : 0).padding(-3))
                ColorPicker("", selection: Binding(get: { value.wrappedValue.color }, set: { value.wrappedValue = RGBA($0) }),
                            supportsOpacity: false)
                    .labelsHidden()
                    .opacity(0.02)
                    .frame(width: 18, height: 18)
                    .clipShape(Circle())
            }
            .frame(width: 18, height: 18)
            .help(Lang.t("Outra cor"))
        }
    }

    private func close(_ a: RGBA, _ b: RGBA) -> Bool {
        abs(a.r - b.r) < 0.02 && abs(a.g - b.g) < 0.02 && abs(a.b - b.b) < 0.02
    }
}
#endif
