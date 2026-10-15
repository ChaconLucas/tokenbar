import Foundation
import UserNotifications

/// O app do iPhone não se atualiza pela internet (conta gratuita da Apple): avisa quando há versão nova
/// e quando vai vencer, e deixa uma notificação marcada para a véspera.
@MainActor
final class AppLifetime: ObservableObject {
    static let shared = AppLifetime()

    @Published var newVersion: String?
    @Published var expires: Date?

    static let current = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    static let command = "curl -fsSL https://raw.githubusercontent.com/ChaconLucas/tokenbar/main/scripts/install-ios.sh | sh"

    var daysLeft: Int? {
        expires.map { Int(ceil($0.timeIntervalSinceNow / 86400)) }
    }

    /// Faltando 3 dias ou menos, ou com versão nova, vale avisar.
    var needsAttention: Bool { newVersion != nil || (daysLeft.map { $0 <= 3 } ?? false) }

    func refresh() async {
        expires = Self.profileExpiration()
        scheduleReminder()
        var req = URLRequest(url: URL(string: "https://api.github.com/repos/ChaconLucas/tokenbar/releases/latest")!, timeoutInterval: 15)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        guard let (data, _) = try? await URLSession.shared.data(for: req),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tag = root["tag_name"] as? String else { return }
        let v = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
        newVersion = Self.isNewer(v, than: Self.current) ? v : nil
    }

    static func isNewer(_ a: String, than b: String) -> Bool {
        let x = a.split(separator: ".").map { Int($0) ?? 0 }, y = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(x.count, y.count) {
            let p = i < x.count ? x[i] : 0, q = i < y.count ? y[i] : 0
            if p != q { return p > q }
        }
        return false
    }

    /// A validade mora no perfil que o Xcode embute no app (um plist dentro de um envelope assinado).
    static func profileExpiration() -> Date? {
        guard let url = Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision"),
              let data = try? Data(contentsOf: url),
              let start = data.range(of: Data("<?xml".utf8)),
              let end = data.range(of: Data("</plist>".utf8), in: start.lowerBound..<data.endIndex),
              let plist = try? PropertyListSerialization.propertyList(from: data[start.lowerBound..<end.upperBound], format: nil) as? [String: Any]
        else { return nil }
        return plist["ExpirationDate"] as? Date
    }

    /// Uma notificação na véspera (substitui a anterior a cada abertura, então acompanha cada reinstalação).
    private func scheduleReminder() {
        let center = UNUserNotificationCenter.current()
        let id = "tokenbar.expiry"
        center.removePendingNotificationRequests(withIdentifiers: [id])
        guard let expires, let when = Calendar.current.date(byAdding: .day, value: -1, to: expires), when > .now else { return }
        let content = UNMutableNotificationContent()
        content.title = Lang.t("O TokenBar vence amanhã")
        content.body = Lang.t("Conecte o iPhone ao Mac e rode o comando de instalação de novo para renovar.")
        let parts = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: when)
        center.add(UNNotificationRequest(identifier: id, content: content,
                                         trigger: UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)))
    }
}
