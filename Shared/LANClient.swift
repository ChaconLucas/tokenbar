import Foundation
import Network

#if !os(watchOS)
/// Acha o Mac pareado na rede local (Bonjour) e lê os números dele, sem servidor.
enum LANClient {
    enum Failure: LocalizedError {
        case notFound, unauthorized, bad

        var errorDescription: String? {
            switch self {
            case .notFound: Lang.t("Mac não encontrado no Wi-Fi")
            case .unauthorized: Lang.t("O Mac recusou a chave (pareie de novo)")
            case .bad: Lang.t("Resposta inválida do Mac")
            }
        }
    }

    /// Procura o Mac com o mesmo id do pareamento e pede os números. Desiste em `timeout` segundos.
    static func fetch(_ p: Pairing, timeout: TimeInterval = 4) async throws -> UsageSnapshot {
        let endpoint = try await find(lanID: p.lanID, timeout: timeout)
        let data = try await get(endpoint, token: p.token, timeout: timeout)
        guard let s = try? JSONCoding.decoder.decode(UsageSnapshot.self, from: data) else { throw Failure.bad }
        return s
    }

    private static func find(lanID: String, timeout: TimeInterval) async throws -> NWEndpoint {
        let browser = NWBrowser(for: .bonjourWithTXTRecord(type: TB.bonjourType, domain: nil), using: .tcp)
        let box = Once<NWEndpoint>()
        browser.browseResultsChangedHandler = { results, _ in
            for r in results {
                if case .bonjour(let txt) = r.metadata, txt["id"] == lanID { box.finish(.success(r.endpoint)); return }
            }
        }
        browser.start(queue: .global())
        defer { browser.cancel() }
        return try await box.wait(timeout: timeout, onTimeout: Failure.notFound)
    }

    private static func get(_ endpoint: NWEndpoint, token: String, timeout: TimeInterval) async throws -> Data {
        let c = NWConnection(to: endpoint, using: .tcp)
        let box = Once<Data>()
        var received = Data()
        func read() {
            c.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { data, _, done, error in
                if let data { received.append(data) }
                if done || error != nil { box.finish(.success(received)) } else { read() }
            }
        }
        c.stateUpdateHandler = { state in
            switch state {
            case .ready:
                let req = "GET /v1/usage HTTP/1.1\r\nHost: tokenbar\r\nAuthorization: Bearer \(token)\r\nConnection: close\r\n\r\n"
                c.send(content: Data(req.utf8), completion: .contentProcessed { _ in read() })
            case .failed, .cancelled:
                box.finish(.failure(Failure.notFound))
            default: break
            }
        }
        c.start(queue: .global())
        defer { c.cancel() }
        let raw = try await box.wait(timeout: timeout, onTimeout: Failure.notFound)

        // "HTTP/1.1 200 OK\r\n...\r\n\r\n{json}"
        guard let split = raw.range(of: Data("\r\n\r\n".utf8)) else { throw Failure.bad }
        let head = String(decoding: raw[..<split.lowerBound], as: UTF8.self)
        if head.hasPrefix("HTTP/1.1 401") { throw Failure.unauthorized }
        guard head.hasPrefix("HTTP/1.1 200") else { throw Failure.bad }
        return raw[split.upperBound...]
    }
}

/// Resultado que chega uma vez só, de callback, com prazo.
private final class Once<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var cont: CheckedContinuation<T, Error>?
    private var result: Result<T, Error>?

    func finish(_ r: Result<T, Error>) {
        lock.lock(); defer { lock.unlock() }
        guard result == nil else { return }
        result = r
        cont?.resume(with: r)
        cont = nil
    }

    func wait(timeout: TimeInterval, onTimeout: Error) async throws -> T {
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout) { self.finish(.failure(onTimeout)) }
        return try await withCheckedThrowingContinuation { c in
            lock.lock()
            if let result { lock.unlock(); c.resume(with: result) } else { cont = c; lock.unlock() }
        }
    }
}
#endif
