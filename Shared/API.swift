import Foundation

enum APIError: LocalizedError {
    case http(Int)
    case notFound
    case noServer

    var errorDescription: String? {
        switch self {
        case .http(let code): Lang.f("Servidor respondeu %d", code)
        case .notFound: Lang.t("Nenhum dado enviado ainda pelo Mac")
        case .noServer: Lang.t("Sem servidor configurado")
        }
    }
}

enum API {
    private static func request(_ p: Pairing, method: String) throws -> URLRequest {
        guard let server = p.server else { throw APIError.noServer }
        var r = URLRequest(url: server.appending(path: "v1/usage"), timeoutInterval: 10)
        r.httpMethod = method
        r.setValue("Bearer \(p.token)", forHTTPHeaderField: "Authorization")
        r.cachePolicy = .reloadIgnoringLocalCacheData
        return r
    }

    static func fetch(_ p: Pairing) async throws -> UsageSnapshot {
        let (data, resp) = try await URLSession.shared.data(for: try request(p, method: "GET"))
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        if code == 404 { throw APIError.notFound }
        guard code == 200 else { throw APIError.http(code) }
        return try JSONCoding.decoder.decode(UsageSnapshot.self, from: data)
    }

    static func push(_ s: UsageSnapshot, _ p: Pairing) async throws {
        var r = try request(p, method: "PUT")
        r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        r.httpBody = try JSONCoding.encoder.encode(s)
        let (_, resp) = try await URLSession.shared.data(for: r)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard code == 200 || code == 204 else { throw APIError.http(code) }
    }
}
