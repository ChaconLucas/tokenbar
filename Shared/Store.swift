import Foundation

enum TB {
    /// No Mac o grupo leva o prefixo do time (vem do Info.plist); com "group." o macOS pede permissão a cada abertura.
    /// Vem do Info.plist de cada alvo (TB_APP_GROUP em Config/Signing.xcconfig).
    static let appGroup = Bundle.main.object(forInfoDictionaryKey: "TBAppGroup") as? String ?? "group.tokenbar"
    static let urlScheme = "tokenbar"
    /// Serviço Bonjour que o Mac anuncia na rede local.
    static let bonjourType = "_tokenbar._tcp"

    /// Sem o App Group assinado (build sem time) cai no padrão local — o app funciona, só o widget fica sem dados.
    static var defaults: UserDefaults { UserDefaults(suiteName: appGroup) ?? .standard }
}

/// A chave secreta que liga o iPhone ao Mac; o servidor é opcional (sem ele, só Wi-Fi local).
struct Pairing: Codable, Hashable {
    var server: URL?
    var token: String

    /// tokenbar://pair?token=...[&server=https://...]
    var link: URL {
        var c = URLComponents()
        c.scheme = TB.urlScheme
        c.host = "pair"
        c.queryItems = [.init(name: "token", value: token)]
        if let server { c.queryItems?.append(.init(name: "server", value: server.absoluteString)) }
        return c.url!
    }

    /// Identifica o Mac na rede sem revelar a chave: o iPhone só conversa com o Mac que tem este id.
    var lanID: String { String(token.prefix(8)) }

    init(server: URL?, token: String) {
        self.server = server
        self.token = token
    }

    init?(link: URL) {
        guard link.scheme == TB.urlScheme, link.host == "pair",
              let items = URLComponents(url: link, resolvingAgainstBaseURL: false)?.queryItems,
              let token = items.first(where: { $0.name == "token" })?.value, token.count >= 32
        else { return nil }
        let server = items.first(where: { $0.name == "server" })?.value.flatMap(URL.init(string:))
        self.init(server: server, token: token)
    }

    static func newToken() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

enum SharedStore {
    private static let snapshotKey = "snapshot"
    private static let pairingKey = "pairing"

    static func loadSnapshot() -> UsageSnapshot? {
        guard let data = TB.defaults.data(forKey: snapshotKey) else { return nil }
        return try? JSONCoding.decoder.decode(UsageSnapshot.self, from: data)
    }

    static func saveSnapshot(_ s: UsageSnapshot) {
        if let data = try? JSONCoding.encoder.encode(s) { TB.defaults.set(data, forKey: snapshotKey) }
    }

    static func loadPairing() -> Pairing? {
        guard let data = TB.defaults.data(forKey: pairingKey) else { return nil }
        return try? JSONCoding.decoder.decode(Pairing.self, from: data)
    }

    static func savePairing(_ p: Pairing?) {
        if let p, let data = try? JSONCoding.encoder.encode(p) {
            TB.defaults.set(data, forKey: pairingKey)
        } else {
            TB.defaults.removeObject(forKey: pairingKey)
        }
    }
}
