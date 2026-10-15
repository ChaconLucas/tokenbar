import SwiftUI

/// Cor guardável (Color não é Codable).
struct RGBA: Codable, Equatable, Hashable {
    var r: Double, g: Double, b: Double, a: Double = 1

    var color: Color { Color(.sRGB, red: r, green: g, blue: b, opacity: a) }

    init(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1) {
        self.r = r; self.g = g; self.b = b; self.a = a
    }

    /// "#RRGGBB" → cor.
    init?(hex: String) {
        let h = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard h.count == 6, let v = UInt32(h, radix: 16) else { return nil }
        self.init(Double((v >> 16) & 0xFF) / 255, Double((v >> 8) & 0xFF) / 255, Double(v & 0xFF) / 255)
    }

    init(_ color: Color) {
        let c = color.resolve(in: EnvironmentValues())
        self.init(Double(c.red), Double(c.green), Double(c.blue), Double(c.opacity))
    }
}

/// Tudo o que a pessoa pode mudar no visual. Vale para app, widgets e relógio.
struct Theme: Codable, Equatable {
    var claude = RGBA(0.62, 0.36, 1.0)      // roxo
    var codex = RGBA(0.20, 0.85, 0.95)      // ciano
    var text = RGBA(1, 1, 1)
    var timer = RGBA(1, 1, 1)
    var roundDots = true
    var levelColors = false                 // verde → amarelo → vermelho pelo uso, em vez da cor da IA
    var warnRed = true                      // vermelho a partir de 85%, mesmo com cor própria
    var glow = 1.0                          // 0 = sem brilho, 2 = muito

    func base(_ providerID: String) -> Color {
        switch providerID {
        case "claude": claude.color
        case "codex": codex.color
        default:
            // Outras IAs: a cor que mandaram ("#RRGGBB") ou uma da paleta, fixa por nome.
            if let hex = SharedStore.loadSnapshot()?.provider(providerID)?.color, let c = RGBA(hex: hex) { c.color }
            else { Theme.palette[abs(providerID.hashValueStable) % Theme.palette.count].color }
        }
    }

    static let palette: [RGBA] = [RGBA(1.0, 0.62, 0.20), RGBA(0.35, 0.85, 0.45), RGBA(1.0, 0.85, 0.25),
                                  RGBA(0.40, 0.60, 1.0), RGBA(1.0, 0.45, 0.65), RGBA(0.65, 0.90, 0.95)]

    /// A cor do bloco para este uso.
    func fill(_ providerID: String, percent: Double) -> Color {
        if levelColors { return Arcade.segmentColor(percent / 100) }
        if warnRed && percent >= 85 { return Arcade.red }
        return base(providerID)
    }

    static let standard = Theme()
}

extension Prefs {
    private static let themeKey = "theme"

    static var theme: Theme {
        get {
            guard let d = TB.defaults.data(forKey: themeKey),
                  let t = try? JSONDecoder().decode(Theme.self, from: d) else { return .standard }
            return t
        }
        set {
            if let d = try? JSONEncoder().encode(newValue) { TB.defaults.set(d, forKey: themeKey) }
        }
    }
}

#if !os(watchOS)
/// Tela de aparência: cores, pontos e brilho, com o resultado ao vivo no aparelho.
struct ThemeEditor: View {
    @Binding var theme: Theme

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            colorRow("CLAUDE", $theme.claude)
            colorRow("CODEX", $theme.codex)
            colorRow(Lang.t("TEXTO"), $theme.text)
            colorRow(Lang.t("CONTADOR"), $theme.timer)

            Toggle(Lang.t("Cor muda com o uso (verde → amarelo → vermelho)"), isOn: $theme.levelColors)
            Toggle(Lang.t("Vermelho a partir de 85%"), isOn: $theme.warnRed).disabled(theme.levelColors)

            Picker(Lang.t("Pontos"), selection: $theme.roundDots) {
                Text(Lang.t("Redondos")).tag(true)
                Text(Lang.t("Quadrados")).tag(false)
            }
            .pickerStyle(.segmented)

            HStack {
                Text(Lang.t("BRILHO")).font(Arcade.label(11)).foregroundStyle(Arcade.dim)
                Slider(value: $theme.glow, in: 0...2)
            }

            Button(Lang.t("RESTAURAR PADRÃO")) { theme = .standard }.buttonStyle(ArcadeButtonStyle())
        }
        .font(.callout)
        .tint(theme.claude.color)
    }

    private func colorRow(_ label: String, _ value: Binding<RGBA>) -> some View {
        ColorPicker(selection: Binding(get: { value.wrappedValue.color }, set: { value.wrappedValue = RGBA($0) }),
                    supportsOpacity: false) {
            Text(label).font(Arcade.label(11)).tracking(1).foregroundStyle(.white)
        }
    }
}
#endif

extension String {
    /// Hash estável entre execuções (o hashValue do Swift muda a cada abertura).
    var hashValueStable: Int { unicodeScalars.reduce(5381) { ($0 &* 33) &+ Int($1.value) } }
}
