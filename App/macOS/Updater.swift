import AppKit

/// Atualização sem sair do app: vê a última versão nos Releases do GitHub, baixa o zip,
/// confere a assinatura (mesmo time que assinou este app), troca o app em /Applications e reabre.
@MainActor
final class Updater: ObservableObject {
    static let shared = Updater()

    @Published var available: String?
    @Published var busy = false
    @Published var error: String?

    static let current = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    private static let latestAPI = URL(string: "https://api.github.com/repos/ChaconLucas/tokenbar/releases/latest")!
    private static let zipURL = URL(string: "https://github.com/ChaconLucas/tokenbar/releases/latest/download/TokenBar-macOS.zip")!
    private var timer: Timer?

    /// Olha logo e depois a cada 6 horas (a API do GitHub aceita 60 consultas por hora sem login).
    func start() {
        guard timer == nil else { return }
        Task { await check() }
        timer = Timer.scheduledTimer(withTimeInterval: 6 * 3600, repeats: true) { _ in
            Task { @MainActor in await Updater.shared.check() }
        }
    }

    func check() async {
        var req = URLRequest(url: Self.latestAPI, timeoutInterval: 15)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        guard let (data, _) = try? await URLSession.shared.data(for: req),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tag = root["tag_name"] as? String
        else { return }
        let version = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
        available = Self.isNewer(version, than: Self.current) ? version : nil
        #if DEBUG
        // -TBAutoUpdate YES: instala sozinho (teste da troca sem clicar).
        if available != nil, UserDefaults.standard.bool(forKey: "TBAutoUpdate") { install() }
        #endif
    }

    static func isNewer(_ a: String, than b: String) -> Bool {
        let x = a.split(separator: ".").map { Int($0) ?? 0 }, y = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(x.count, y.count) {
            let p = i < x.count ? x[i] : 0, q = i < y.count ? y[i] : 0
            if p != q { return p > q }
        }
        return false
    }

    func install() {
        guard !busy else { return }
        busy = true
        error = nil
        Task {
            do {
                try await Self.downloadAndSwap()
            } catch {
                self.error = error.localizedDescription
                busy = false
            }
        }
    }

    private struct Failure: LocalizedError {
        var errorDescription: String?
        init(_ s: String) { errorDescription = s }
    }

    private static func downloadAndSwap() async throws {
        let (zip, _) = try await URLSession.shared.download(from: zipURL)
        let dir = FileManager.default.temporaryDirectory.appending(path: "tokenbar-update-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try run("/usr/bin/ditto", ["-x", "-k", zip.path, dir.path])
        let fresh = dir.appending(path: "TokenBar.app")
        guard FileManager.default.fileExists(atPath: fresh.path) else { throw Failure("O pacote baixado não tem o TokenBar.app.") }

        // Só troca se o app novo foi assinado pelo mesmo time deste: um zip trocado no caminho não passa.
        let team = try teamID(of: Bundle.main.bundleURL)
        do {
            try run("/usr/bin/codesign", ["--verify", "--deep", "--strict",
                                          "-R=anchor apple generic and certificate leaf[subject.OU] = \"\(team)\"", fresh.path])
        } catch {
            throw Failure("A assinatura da atualização não confere. Nada foi trocado.")
        }

        // Um script pequeno espera este app fechar, troca a pasta e abre a versão nova.
        let target = Bundle.main.bundleURL.path
        let script = """
        while kill -0 \(ProcessInfo.processInfo.processIdentifier) 2>/dev/null; do sleep 0.2; done
        rm -rf "\(target)" && /usr/bin/ditto "\(fresh.path)" "\(target)"
        /usr/bin/xattr -dr com.apple.quarantine "\(target)" 2>/dev/null
        open "\(target)"
        rm -rf "\(dir.path)"
        """
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = ["-c", script]
        try p.run()
        await MainActor.run { NSApp.terminate(nil) }
    }

    private static func teamID(of app: URL) throws -> String {
        let out = try run("/usr/bin/codesign", ["-dv", app.path])
        guard let line = out.split(separator: "\n").first(where: { $0.hasPrefix("TeamIdentifier=") }) else {
            throw Failure("Não consegui ler a assinatura deste app.")
        }
        let team = String(line.dropFirst("TeamIdentifier=".count))
        guard team.range(of: "^[A-Z0-9]{10}$", options: .regularExpression) != nil else {
            throw Failure("Este app não tem assinatura de time; atualize pelo comando do README.")
        }
        return team
    }

    /// Roda um comando e devolve a saída (o codesign escreve em stderr).
    @discardableResult
    private static func run(_ tool: String, _ args: [String]) throws -> String {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: tool)
        p.arguments = args
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        try p.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        guard p.terminationStatus == 0 else { throw Failure("Falhou: \(URL(fileURLWithPath: tool).lastPathComponent)") }
        return String(decoding: data, as: UTF8.self)
    }
}
