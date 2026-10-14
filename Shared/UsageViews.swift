import SwiftUI

// MARK: - Tema: painel de fliperama / relógio digital

enum Arcade {
    static let green = Color(red: 0.22, green: 1.0, blue: 0.42)
    static let amber = Color(red: 1.0, green: 0.78, blue: 0.10)
    static let red = Color(red: 1.0, green: 0.22, blue: 0.24)
    static let cyan = Color(red: 0.35, green: 0.86, blue: 1.0)
    static let dim = Color(white: 0.42)
    static let bgTop = Color(red: 0.055, green: 0.06, blue: 0.08)
    static let bgBottom = Color(red: 0.01, green: 0.01, blue: 0.015)

    /// Cor do segmento pela posição na barra, como um medidor de VU.
    static func segmentColor(_ position: Double) -> Color {
        switch position {
        case ..<0.6: green
        case ..<0.85: amber
        default: red
        }
    }

    static func digits(_ size: CGFloat) -> Font {
        .system(size: size, weight: .heavy, design: .monospaced)
    }

    static func label(_ size: CGFloat) -> Font {
        .system(size: size, weight: .bold, design: .monospaced)
    }
}

enum UsageStyle {
    static func color(_ pct: Double) -> Color { Arcade.segmentColor(pct / 100) }

    static func percent(_ pct: Double) -> String { "\(Int(pct.rounded()))%" }

    /// "16:40" hoje, "SEX 16:40" em outro dia.
    static func resetText(_ date: Date, now: Date = .now) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "pt_BR")
        f.dateFormat = Calendar.current.isDate(date, inSameDayAs: now) ? "HH:mm" : "EEE HH:mm"
        return f.string(from: date).replacingOccurrences(of: ".", with: "").uppercased()
    }

    /// "02:08" (h:min) até 1 dia, "2D 22H" depois.
    static func countdown(to date: Date, now: Date = .now) -> String {
        let s = max(0, Int(date.timeIntervalSince(now)))
        let d = s / 86400, h = (s % 86400) / 3600, m = (s % 3600) / 60
        if d > 0 { return "\(d)D \(h)H" }
        return String(format: "%02d:%02d", h, m)
    }

    static func icon(_ providerID: String) -> String {
        providerID == "codex" ? "chevron.left.forwardslash.chevron.right" : "sparkle"
    }

    static func shortName(_ providerID: String) -> String {
        providerID == "codex" ? "CODEX" : "CLAUDE"
    }
}

// MARK: - Fundo e painel com profundidade

/// Preto com um brilho fraco no alto e uma grade de pontos, como vidro de máquina antiga.
struct ArcadeBackground: View {
    var body: some View {
        ZStack {
            LinearGradient(colors: [Arcade.bgTop, Arcade.bgBottom], startPoint: .top, endPoint: .bottom)
            RadialGradient(colors: [Arcade.cyan.opacity(0.10), .clear], center: .top, startRadius: 0, endRadius: 420)
            Canvas { ctx, size in
                let step: CGFloat = 6
                var y: CGFloat = 0
                while y < size.height {
                    ctx.fill(Path(CGRect(x: 0, y: y, width: size.width, height: 1)), with: .color(.white.opacity(0.018)))
                    y += step
                }
            }
        }
        .ignoresSafeArea()
    }
}

/// Painel rebaixado: escuro por dentro, filete claro em cima, sombra em baixo.
struct ArcadePanel<Content: View>: View {
    var padding: CGFloat = 14
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .background {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(LinearGradient(colors: [Color(white: 0.02), Color(white: 0.07)], startPoint: .top, endPoint: .bottom))
                    .overlay {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(LinearGradient(colors: [.black, .white.opacity(0.12)], startPoint: .top, endPoint: .bottom), lineWidth: 1)
                    }
                    .shadow(color: .black.opacity(0.9), radius: 10, y: 6)
            }
    }
}

// MARK: - Peças

/// Barra de segmentos de LED. Os acesos brilham; os apagados ficam visíveis, fracos.
struct UsageBar: View {
    var percent: Double
    var height: CGFloat = 14
    var segments: Int = 24

    var body: some View {
        let lit = Int((min(max(percent, 0), 100) / 100 * Double(segments)).rounded(.up))
        HStack(spacing: max(1.5, height * 0.18)) {
            ForEach(0..<segments, id: \.self) { i in
                let c = Arcade.segmentColor(Double(i) / Double(segments))
                let on = i < lit
                RoundedRectangle(cornerRadius: height * 0.18, style: .continuous)
                    .fill(on ? AnyShapeStyle(c.gradient) : AnyShapeStyle(c.opacity(0.09)))
                    .shadow(color: on ? c.opacity(0.85) : .clear, radius: height * 0.35)
            }
        }
        .frame(height: height)
        .animation(.easeOut(duration: 0.35), value: lit)
        .accessibilityElement()
        .accessibilityLabel(UsageStyle.percent(percent))
    }
}

/// Número de display: os "88" apagados atrás, o valor aceso na frente.
struct DigitalNumber: View {
    var text: String
    var ghost: String
    var size: CGFloat
    var color: Color

    var body: some View {
        ZStack(alignment: .trailing) {
            Text(ghost).foregroundStyle(color.opacity(0.08))
            Text(text)
                .foregroundStyle(color)
                .shadow(color: color.opacity(0.75), radius: size * 0.22)
        }
        .font(Arcade.digits(size))
        .monospacedDigit()
    }
}

/// Uma janela: rótulo, número grande, barra e quando reseta.
struct WindowRow: View {
    var window: UsageWindow
    var now: Date = .now
    var compact = false

    var body: some View {
        let pct = window.used(at: now)
        let color = UsageStyle.color(pct)
        VStack(alignment: .leading, spacing: compact ? 3 : 7) {
            HStack(alignment: .lastTextBaseline) {
                Text(window.label.uppercased())
                    .font(Arcade.label(compact ? 10 : 12))
                    .foregroundStyle(Arcade.dim)
                Spacer()
                DigitalNumber(text: "\(Int(pct.rounded()))%", ghost: "888%", size: compact ? 13 : 26, color: color)
            }
            UsageBar(percent: pct, height: compact ? 7 : 14, segments: compact ? 16 : 24)
            if !compact, let r = window.resetsAt {
                HStack {
                    if window.didReset(at: now) {
                        Text("RESETOU")
                    } else {
                        Text("RESET \(UsageStyle.resetText(r, now: now))")
                        Spacer()
                        Text("T-\(UsageStyle.countdown(to: r, now: now))").foregroundStyle(Arcade.cyan)
                    }
                }
                .font(Arcade.label(10))
                .foregroundStyle(Arcade.dim)
            }
        }
    }
}

struct ProviderCard: View {
    var provider: ProviderUsage
    var now: Date = .now
    var compact = false

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 6 : 14) {
            HStack(spacing: 6) {
                Image(systemName: UsageStyle.icon(provider.id))
                    .foregroundStyle(Arcade.cyan)
                    .shadow(color: Arcade.cyan.opacity(0.7), radius: 4)
                Text(UsageStyle.shortName(provider.id))
                    .font(Arcade.label(compact ? 11 : 15))
                    .tracking(compact ? 1 : 3)
                    .foregroundStyle(.white)
                Spacer()
                if !compact {
                    Circle().fill(freshColor).frame(width: 6, height: 6).shadow(color: freshColor, radius: 3)
                    Text(ageText).font(Arcade.label(9)).foregroundStyle(Arcade.dim)
                }
            }
            ForEach(provider.windows) { WindowRow(window: $0, now: now, compact: compact) }
        }
    }

    /// Verde se leu há pouco; apagado se o número é velho (sessão fechada).
    private var freshColor: Color {
        now.timeIntervalSince(provider.observedAt) < 15 * 60 ? Arcade.green : Arcade.dim
    }

    private var ageText: String {
        let m = Int(now.timeIntervalSince(provider.observedAt) / 60)
        if m < 1 { return "AO VIVO" }
        if m < 60 { return "HÁ \(m) MIN" }
        if m < 1440 { return "HÁ \(m / 60) H" }
        return "HÁ \(m / 1440) D"
    }
}

/// Anel compacto para complicações e menu.
struct UsageRing: View {
    var percent: Double
    var lineWidth: CGFloat = 5

    var body: some View {
        ZStack {
            Circle().stroke(.white.opacity(0.08), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: min(percent, 100) / 100)
                .stroke(UsageStyle.color(percent), style: StrokeStyle(lineWidth: lineWidth, lineCap: .butt, dash: [3, 1.5]))
                .rotationEffect(.degrees(-90))
                .shadow(color: UsageStyle.color(percent), radius: 3)
        }
    }
}

struct ArcadeButtonStyle: ButtonStyle {
    var tint: Color = Arcade.cyan

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Arcade.label(11))
            .tracking(1.5)
            .foregroundStyle(tint)
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background {
                RoundedRectangle(cornerRadius: 6)
                    .fill(tint.opacity(configuration.isPressed ? 0.25 : 0.08))
                    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(tint.opacity(0.4)))
            }
            .shadow(color: tint.opacity(configuration.isPressed ? 0.6 : 0.2), radius: 6)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
    }
}

struct SectionTitle: View {
    var text: String
    var body: some View {
        Text(text).font(Arcade.label(11)).tracking(3).foregroundStyle(Arcade.dim)
            .padding(.top, 8)
    }
}

