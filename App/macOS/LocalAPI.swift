import Foundation
import Network

/// API local, só para este Mac: `http://localhost:41777/v1/usage`. Outro ouvinte, separado do LANServer.
/// Sem chave (só 127.0.0.1 escuta), sem CORS (sites no navegador não leem) e com o `Host` conferido
/// (um domínio que aponte para 127.0.0.1 não passa: proteção contra DNS rebinding).
/// Ao subir grava `~/.tokenbar/api.json` com a porta; ao sair, apaga.
final class LocalAPI {
    static let shared = LocalAPI()
    static let firstPort: UInt16 = 41777
    static let lastPort: UInt16 = 41787
    static var infoFile: URL { Collector.tokenbarDir.appending(path: "api.json") }
    static let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"

    /// Porta em uso (nil = parada) e se esgotou as portas; chamado na fila principal.
    var onState: ((_ port: UInt16?, _ failed: Bool) -> Void)?

    private let queue = DispatchQueue(label: "tokenbar.api")
    private var listener: NWListener?
    private var port: UInt16?
    private var generation = 0
    private var snapshot = UsageSnapshot.empty

    func update(_ s: UsageSnapshot) { queue.async { self.snapshot = s } }

    func setEnabled(_ on: Bool) {
        queue.async {
            self.stopLocked()
            if on { self.start(Self.firstPort) }
        }
    }

    /// Ao sair do app: para e apaga o api.json na hora (síncrono).
    func stop() { queue.sync { stopLocked() } }

    private func stopLocked() {
        generation += 1
        listener?.cancel()
        listener = nil
        if port != nil { removeInfoIfOurs() }
        port = nil
        report(nil, failed: false)
    }

    private func start(_ p: UInt16) {
        guard p <= Self.lastPort else { report(nil, failed: true); return }
        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = false
        params.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: NWEndpoint.Port(rawValue: p)!)
        guard let l = try? NWListener(using: params) else { start(p + 1); return }
        let gen = generation
        l.stateUpdateHandler = { [weak self, weak l] state in
            guard let self, gen == self.generation else { return }
            switch state {
            case .ready:
                self.port = p
                self.writeInfo(p)
                self.report(p, failed: false)
            case .failed, .waiting:
                // Porta ocupada: tenta a próxima.
                l?.stateUpdateHandler = nil
                l?.cancel()
                self.listener = nil
                self.start(p + 1)
            default: break
            }
        }
        l.newConnectionHandler = { [weak self] c in self?.handle(c) }
        l.start(queue: queue)
        listener = l
    }

    private func report(_ p: UInt16?, failed: Bool) {
        DispatchQueue.main.async { self.onState?(p, failed) }
    }

    /// Só apaga o api.json se fomos nós que escrevemos (outro TokenBar pode estar rodando).
    private func removeInfoIfOurs() {
        guard let data = try? Data(contentsOf: Self.infoFile),
              let info = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              (info["pid"] as? Int) == Int(ProcessInfo.processInfo.processIdentifier) else { return }
        try? FileManager.default.removeItem(at: Self.infoFile)
    }

    private func writeInfo(_ p: UInt16) {
        let info: [String: Any] = ["port": Int(p), "pid": Int(ProcessInfo.processInfo.processIdentifier),
                                   "app": "TokenBar", "version": Self.version, "platform": "mac"]
        guard let data = try? JSONSerialization.data(withJSONObject: info, options: [.sortedKeys]) else { return }
        try? FileManager.default.createDirectory(at: Collector.tokenbarDir, withIntermediateDirectories: true)
        try? data.write(to: Self.infoFile, options: .atomic)
    }

    // MARK: HTTP

    private func handle(_ c: NWConnection) {
        c.start(queue: queue)
        // Conexão que não manda o pedido inteiro não fica pendurada.
        queue.asyncAfter(deadline: .now() + 5) { c.cancel() }
        receive(c, Data())
    }

    private func receive(_ c: NWConnection, _ buffer: Data) {
        c.receive(minimumIncompleteLength: 1, maximumLength: 16 * 1024) { [weak self] data, _, done, error in
            guard let self else { c.cancel(); return }
            var b = buffer
            if let data { b.append(data) }
            let complete = b.range(of: Data("\r\n\r\n".utf8)) != nil
            if !complete && !done && error == nil && b.count < 32 * 1024 {
                self.receive(c, b)
                return
            }
            let response = self.respond(to: String(decoding: b, as: UTF8.self))
            c.send(content: response, completion: .contentProcessed { _ in c.cancel() })
        }
    }

    private func respond(to request: String) -> Data {
        let lines = request.components(separatedBy: "\r\n")
        let parts = (lines.first ?? "").split(separator: " ")
        guard parts.count >= 2, let port else { return Self.http(400, ["error": "bad_request"]) }
        let host = lines.dropFirst().first { $0.lowercased().hasPrefix("host:") }
            .map { $0.dropFirst(5).trimmingCharacters(in: .whitespaces).lowercased() }
        guard let host, host == "127.0.0.1:\(port)" || host == "localhost:\(port)" else {
            return Self.http(403, ["error": "forbidden"])
        }
        guard parts[0] == "GET" else { return Self.http(405, ["error": "method_not_allowed"]) }
        let path = String(parts[1].split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false).first ?? "")
        let now = Date.now

        switch path {
        case "/v1/health":
            return Self.http(200, ["ok": true, "app": "TokenBar", "version": Self.version, "platform": "mac"])
        case "/v1/usage":
            return Self.http(200, ["updatedAt": UsageJSON.seconds(snapshot.updatedAt),
                                   "providers": snapshot.providers.map { UsageJSON.provider($0, now: now) }])
        default:
            let prefix = "/v1/usage/"
            if path.hasPrefix(prefix) {
                let id = String(path.dropFirst(prefix.count)).removingPercentEncoding ?? ""
                if let p = snapshot.provider(id) { return Self.http(200, UsageJSON.provider(p, now: now)) }
            }
            return Self.http(404, ["error": "not_found"])
        }
    }

    private static func http(_ code: Int, _ object: [String: Any]) -> Data {
        let body = (try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])) ?? Data("{}".utf8)
        let reason = [200: "OK", 400: "Bad Request", 403: "Forbidden", 404: "Not Found",
                      405: "Method Not Allowed"][code] ?? "Error"
        var head = "HTTP/1.1 \(code) \(reason)\r\n"
        head += "Content-Type: application/json; charset=utf-8\r\n"
        head += "Cache-Control: no-store\r\n"
        if code == 405 { head += "Allow: GET\r\n" }
        head += "Content-Length: \(body.count)\r\nConnection: close\r\n\r\n"
        return Data(head.utf8) + body
    }
}

/// O formato público dos números (API local e webhooks; o app do Windows e a CLI usam o mesmo).
enum UsageJSON {
    static func seconds(_ d: Date) -> Int { Int(d.timeIntervalSince1970) }

    static func window(_ w: UsageWindow, now: Date = .now) -> [String: Any] {
        [
            "id": w.id,
            "label": w.label,
            "usedPercent": w.usedPercent,
            "usedNow": w.used(at: now),
            "resetsAt": w.resetsAt.map { seconds($0) as Any } ?? NSNull(),
            "resetsInSeconds": w.resetsAt.map { max(0, Int($0.timeIntervalSince(now))) as Any } ?? NSNull(),
            "windowMinutes": w.windowMinutes.map { $0 as Any } ?? NSNull(),
        ]
    }

    static func provider(_ p: ProviderUsage, now: Date = .now) -> [String: Any] {
        [
            "id": p.id,
            "name": p.name,
            "color": p.color.map { $0 as Any } ?? NSNull(),
            "observedAt": seconds(p.observedAt),
            "windows": p.windows.map { window($0, now: now) },
        ]
    }
}
