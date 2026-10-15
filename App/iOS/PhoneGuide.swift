import SwiftUI
import VisionKit

/// Tutorial do iPhone: um passo por tela, com a animação mostrando o gesto. PULAR fecha;
/// "Ver tutorial" nos ajustes reabre.
struct PhoneGuide: View {
    @EnvironmentObject var model: PhoneModel
    @Environment(\.dismiss) private var dismiss
    @AppStorage("guideSkipped") private var skipped = false
    @State private var page = 0
    @State private var scanning = false
    @State private var pasted = ""

    private let pages = 4

    var body: some View {
        GeometryReader { geo in
            let wide = geo.size.width > geo.size.height
            VStack(spacing: 0) {
                HStack {
                    Text("PRIMEIROS PASSOS  \(page + 1)/\(pages)").font(Arcade.label(10)).tracking(2).foregroundStyle(Arcade.dim)
                    Spacer()
                    Button(model.pairing == nil ? "PULAR" : "FECHAR") { skipped = true; dismiss() }
                        .buttonStyle(ArcadeButtonStyle(tint: Arcade.dim))
                }
                TabView(selection: $page) {
                    ForEach(0..<pages, id: \.self) { i in
                        slide(i, wide: wide).tag(i)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                footer
            }
            .padding(.horizontal, 20).padding(.vertical, 12)
        }
        .background(ArcadeBackground())
        .preferredColorScheme(.dark)
        .fullScreenCover(isPresented: $scanning) {
            QRScanner { text in
                scanning = false
                if let u = URL(string: text), u.scheme == "tokenbar" { model.pair(with: u); dismiss() }
            } onCancel: { scanning = false }
        }
        #if DEBUG
        .onAppear { page = UserDefaults.standard.integer(forKey: "TBGuidePage") }   // capturas de tela
        #endif
        // Pareou por qualquer caminho (câmera do sistema, link colado): o guia sai da frente.
        .onChange(of: model.pairing?.token) { _, t in if t != nil { dismiss() } }
    }

    @ViewBuilder
    private func slide(_ i: Int, wide: Bool) -> some View {
        let layout = wide ? AnyLayout(HStackLayout(spacing: 24)) : AnyLayout(VStackLayout(spacing: 16))
        layout {
            ArtFrame(width: 340, height: 180) { art(i) }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(RoundedRectangle(cornerRadius: 16).fill(.white.opacity(0.03)))
            VStack(alignment: wide ? .leading : .center, spacing: 12) {
                Text(title(i)).font(Arcade.digits(22)).tracking(3).foregroundStyle(.white)
                    .shadow(color: Arcade.cyan.opacity(0.5), radius: 8)
                Text(text(i)).font(.callout).foregroundStyle(.white.opacity(0.75))
                    .multilineTextAlignment(wide ? .leading : .center)
                action(i)
            }
            .frame(maxWidth: wide ? 300 : .infinity, alignment: wide ? .leading : .center)
        }
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private func art(_ i: Int) -> some View {
        switch i {
        case 0:
            ArtLoop(period: 3.5) { t in
                LaptopArt {
                    ZStack {
                        Color.black
                        VStack(spacing: 6) {
                            DotBar(fill: 0.62 * Art.seg(t, 0.2, 0.7), color: Art.claude, cols: 14, rows: 3)
                            DotBar(fill: 0.38 * Art.seg(t, 0.3, 0.8), color: Art.codex, cols: 14, rows: 3)
                        }
                        .padding(10)
                    }
                }
            }
        case 1:
            ArtLoop(period: 4) { t in
                LaptopArt {
                    ZStack {
                        Color.black
                        VStack(spacing: 5) {
                            Text("PRIMEIROS PASSOS").font(.system(size: 8, weight: .bold, design: .monospaced)).foregroundStyle(.white)
                            Text("CELULAR E RELÓGIO").font(.system(size: 7, design: .monospaced))
                                .padding(.horizontal, 5).padding(.vertical, 2)
                                .background(Capsule().fill(Arcade.cyan.opacity(t > 0.3 ? 0.35 : 0.08)))
                                .foregroundStyle(.white)
                            FakeQR().frame(width: 48, height: 48).opacity(Art.seg(t, 0.4, 0.6))
                        }
                    }
                }
            }
        case 2:
            ScanArt { FakeQR() }
        default:
            WifiArt()
        }
    }

    private func title(_ i: Int) -> String {
        ["INSTALE NO COMPUTADOR", "ABRA O GUIA NELE", "ESCANEIE O QR", "MESMO WI-FI"][i]
    }

    private func text(_ i: Int) -> String {
        [
            "Mac, Windows ou Linux: é o computador que lê os limites das IAs.",
            "No TokenBar do computador: Primeiros passos → Celular e relógio → IPHONE.",
            "Aponte o iPhone para o QR que aparece no computador.",
            "iPhone e computador na mesma rede. Quando pedir, permita a Rede Local.",
        ][i]
    }

    @ViewBuilder
    private func action(_ i: Int) -> some View {
        switch i {
        case 0:
            Link("ABRIR O SITE", destination: URL(string: "https://github.com/ChaconLucas/tokenbar")!)
                .font(Arcade.label(11)).tracking(1.5).foregroundStyle(Arcade.cyan)
        case 2:
            if DataScannerViewController.isSupported {
                Button("ESCANEAR QR") { scanning = true }
                    .buttonStyle(ArcadeButtonStyle(tint: Arcade.amber)).controlSize(.large)
            } else {
                Text("Use a Câmera do iPhone e toque em Abrir no TokenBar.").font(.caption).foregroundStyle(Arcade.dim)
            }
            HStack(spacing: 6) {
                TextField("", text: $pasted, prompt: Text("ou cole o link").foregroundStyle(Arcade.dim))
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                    .font(Arcade.label(11))
                    .padding(8).background(RoundedRectangle(cornerRadius: 8).fill(.black))
                Button("PAREAR") { if let u = URL(string: pasted) { model.pair(with: u) } }
                    .buttonStyle(ArcadeButtonStyle()).disabled(pasted.isEmpty)
            }
            if let e = model.error { Text(e).font(.caption).foregroundStyle(Arcade.red) }
        default:
            EmptyView()
        }
    }

    private var footer: some View {
        HStack {
            Button("VOLTAR") { withAnimation { page -= 1 } }
                .buttonStyle(ArcadeButtonStyle(tint: Arcade.dim))
                .opacity(page == 0 ? 0 : 1).disabled(page == 0)
            Spacer()
            HStack(spacing: 8) {
                ForEach(0..<pages, id: \.self) { i in
                    Circle().fill(i == page ? Arcade.cyan : .white.opacity(0.2)).frame(width: 7, height: 7)
                }
            }
            Spacer()
            let last = page == pages - 1
            Button(last ? "ENTENDI" : "AVANÇAR") {
                if last { skipped = true; dismiss() } else { withAnimation { page += 1 } }
            }
            .buttonStyle(ArcadeButtonStyle(tint: last ? Arcade.green : Arcade.cyan))
        }
    }
}

/// Leitor de QR dentro do app (VisionKit): devolve o primeiro texto lido.
struct QRScanner: UIViewControllerRepresentable {
    var onFound: (String) -> Void
    var onCancel: () -> Void

    func makeUIViewController(context: Context) -> UINavigationController {
        let scanner = DataScannerViewController(recognizedDataTypes: [.barcode(symbologies: [.qr])],
                                                qualityLevel: .balanced, isHighlightingEnabled: true)
        scanner.delegate = context.coordinator
        scanner.navigationItem.leftBarButtonItem = UIBarButtonItem(systemItem: .cancel, primaryAction: UIAction { _ in onCancel() })
        try? scanner.startScanning()
        return UINavigationController(rootViewController: scanner)
    }

    func updateUIViewController(_ vc: UINavigationController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onFound: onFound) }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let onFound: (String) -> Void
        private var done = false
        init(onFound: @escaping (String) -> Void) { self.onFound = onFound }

        func dataScanner(_ s: DataScannerViewController, didAdd items: [RecognizedItem], allItems: [RecognizedItem]) {
            guard !done else { return }
            for case .barcode(let code) in items {
                if let text = code.payloadStringValue, text.hasPrefix("tokenbar://") {
                    done = true
                    s.stopScanning()
                    onFound(text)
                    return
                }
            }
        }
    }
}
