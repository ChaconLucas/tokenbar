import Foundation
import Network

/// Serve o último retrato de uso na rede local e se anuncia por Bonjour (`_tokenbar._tcp`).
/// Só responde a quem manda a chave do pareamento; o anúncio leva apenas os 8 primeiros caracteres dela.
final class LANServer {
    private var listener: NWListener?
    private let queue = DispatchQueue(label: "tokenbar.lan")
    private var body = Data("{}".utf8)
    private var token = ""
    private var link = ""
    /// Código de 6 números para parear relógios sem celular; troca a cada 10 min.
    private(set) var pairCode = LANServer.newCode()
    private var codeBorn = Date.now
    private var failures = 0
    private var lockedUntil = Date.distantPast

    static func newCode() -> String { String(format: "%06d", Int.random(in: 0..<1_000_000)) }

    /// O código atual (renova sozinho depois de 10 min).
    func currentCode() -> String {
        queue.sync {
            if Date.now.timeIntervalSince(codeBorn) > 600 { pairCode = Self.newCode(); codeBorn = .now }
            return pairCode
        }
    }

    /// Atualiza o que é servido; liga o anúncio na primeira vez.
    func publish(_ snapshot: UsageSnapshot, pairing: Pairing) {
        let data = (try? JSONCoding.encoder.encode(snapshot)) ?? Data("{}".utf8)
        queue.async {
            self.body = data
            self.link = pairing.link.absoluteString
            if self.token != pairing.token {
                self.token = pairing.token
                self.restart(lanID: pairing.lanID)
            }
        }
    }

    private func restart(lanID: String) {
        listener?.cancel()
        guard let l = try? NWListener(using: .tcp) else { return }
        let name = Host.current().localizedName ?? "Mac"
        l.service = NWListener.Service(name: name, type: TB.bonjourType, txtRecord: NWTXTRecord(["id": lanID]))
        l.newConnectionHandler = { [weak self] c in self?.handle(c) }
        l.start(queue: queue)
        listener = l
    }

    private func handle(_ c: NWConnection) {
        c.start(queue: queue)
        c.receive(minimumIncompleteLength: 1, maximumLength: 16 * 1024) { [weak self] data, _, _, _ in
            guard let self else { c.cancel(); return }
            let request = data.map { String(decoding: $0, as: UTF8.self) } ?? ""
            let firstLine = request.split(separator: "\r\n").first ?? ""
            let authorized = request.contains("Authorization: Bearer \(self.token)") && !self.token.isEmpty
            let response: Data
            if firstLine.hasPrefix("GET /v1/pair?code=") {
                response = self.pair(firstLine)
            } else if !firstLine.hasPrefix("GET /v1/usage") {
                response = Self.http(404, Data(#"{"error":"not_found"}"#.utf8))
            } else if !authorized {
                response = Self.http(401, Data(#"{"error":"unauthorized"}"#.utf8))
            } else {
                response = Self.http(200, self.body)
            }
            c.send(content: response, completion: .contentProcessed { _ in c.cancel() })
        }
    }

    /// Relógio sem celular: troca o código de 6 números pelo link de pareamento.
    /// Errou 5 vezes, trava 1 minuto; acertou, o código muda (vale uma vez).
    private func pair(_ line: Substring) -> Data {
        guard Date.now > lockedUntil else { return Self.http(429, Data(#"{"error":"wait"}"#.utf8)) }
        if Date.now.timeIntervalSince(codeBorn) > 600 { pairCode = Self.newCode(); codeBorn = .now }
        let code = line.dropFirst("GET /v1/pair?code=".count).prefix(6)
        guard code == pairCode, !link.isEmpty else {
            failures += 1
            if failures >= 5 { lockedUntil = Date.now.addingTimeInterval(60); failures = 0 }
            return Self.http(401, Data(#"{"error":"wrong_code"}"#.utf8))
        }
        failures = 0
        pairCode = Self.newCode(); codeBorn = .now
        let body = (try? JSONSerialization.data(withJSONObject: ["link": link])) ?? Data()
        return Self.http(200, body)
    }

    private static func http(_ code: Int, _ body: Data) -> Data {
        let reason = [200: "OK", 401: "Unauthorized", 404: "Not Found", 429: "Too Many Requests"][code] ?? "Error"
        var head = "HTTP/1.1 \(code) \(reason)\r\n"
        head += "Content-Type: application/json\r\nContent-Length: \(body.count)\r\nConnection: close\r\n\r\n"
        return Data(head.utf8) + body
    }
}
