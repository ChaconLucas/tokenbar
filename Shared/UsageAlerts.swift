import Foundation
import UserNotifications

/// Avisos de limite: ao passar de 80% e 95% de uma janela, e quando ela reseta.
/// Roda no iPhone; o Apple Watch recebe as notificações espelhadas.
enum UsageAlerts {
    static let thresholds: [Double] = [80, 95]
    private static let sentKey = "alertsSent"

    static func requestPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    /// Compara com o que já foi avisado (por janela e por ciclo de reset) e avisa só uma vez cada limite.
    static func check(_ snapshot: UsageSnapshot, now: Date = .now) {
        var sent = TB.defaults.dictionary(forKey: sentKey) as? [String: Double] ?? [:]
        let center = UNUserNotificationCenter.current()

        for p in snapshot.providers {
            for w in p.windows {
                let key = "\(p.id).\(w.id)"
                let cycle = w.resetsAt?.timeIntervalSince1970 ?? 0
                let used = w.used(at: now)
                let name = "\(UsageStyle.shortName(p.id).capitalized) \(w.label.uppercased())"

                // Limite cruzado neste ciclo (o registro guarda "ciclo + limite" para não repetir).
                for t in thresholds where used >= t {
                    let id = "\(key).\(Int(t))"
                    guard sent[id] != cycle else { continue }
                    sent[id] = cycle
                    post(id: id, title: "\(name): \(Int(used.rounded()))%",
                         body: t >= 95 ? "Quase no limite." : "Passou de \(Int(t))% do limite.",
                         at: nil)
                }

                // Aviso agendado para o reset: só faz sentido se a janela estava bem usada.
                if let r = w.resetsAt, r > now, used >= 50 {
                    post(id: "\(key).reset", title: "\(name) liberado", body: "O limite resetou.", at: r)
                } else {
                    center.removePendingNotificationRequests(withIdentifiers: ["\(key).reset"])
                }
            }
        }
        TB.defaults.set(sent, forKey: sentKey)
    }

    private static func post(id: String, title: String, body: String, at date: Date?) {
        let c = UNMutableNotificationContent()
        c.title = title
        c.body = body
        c.sound = .default
        let trigger = date.map {
            UNTimeIntervalNotificationTrigger(timeInterval: max(1, $0.timeIntervalSinceNow), repeats: false)
        }
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: id, content: c, trigger: trigger))
    }
}
