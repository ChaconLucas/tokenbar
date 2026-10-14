import Foundation
import Network

/// Serve o último retrato de uso na rede local e se anuncia por Bonjour (`_tokenbar._tcp`).
/// Só responde a quem manda a chave do pareamento; o anúncio leva apenas os 8 primeiros caracteres dela.
final class LANServer {
    private var listener: NWListener?
    private let queue = DispatchQueue(label: "tokenbar.lan")
    private var body = Data("{}".utf8)
    private var token = ""

    /// Atualiza o que é servido; liga o anúncio na primeira vez.
    func publish(_ snapshot: UsageSnapshot, pairing: Pairing) {
        let data = (try? JSONCoding.encoder.encode(snapshot)) ?? Data("{}".utf8)
        queue.async {
            self.body = data
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
            if !firstLine.hasPrefix("GET /v1/usage") {
                response = Self.http(404, Data(#"{"error":"not_found"}"#.utf8))
            } else if !authorized {
                response = Self.http(401, Data(#"{"error":"unauthorized"}"#.utf8))
            } else {
                response = Self.http(200, self.body)
            }
            c.send(content: response, completion: .contentProcessed { _ in c.cancel() })
        }
    }

    private static func http(_ code: Int, _ body: Data) -> Data {
        let reason = [200: "OK", 401: "Unauthorized", 404: "Not Found"][code] ?? "Error"
        var head = "HTTP/1.1 \(code) \(reason)\r\n"
        head += "Content-Type: application/json\r\nContent-Length: \(body.count)\r\nConnection: close\r\n\r\n"
        return Data(head.utf8) + body
    }
}
