import Foundation

/// Liga o Claude Code ao TokenBar: a statusline passa a ser um script que guarda uma cópia do
/// JSON (com `rate_limits`) e depois repassa para a statusline que a pessoa já tinha.
enum ClaudeHook {
    static var settingsURL: URL { Collector.home.appending(path: ".claude/settings.json") }
    static var teeScript: URL { Collector.tokenbarDir.appending(path: "claude-tee.sh") }
    static var originalFile: URL { Collector.tokenbarDir.appending(path: "statusline-original") }

    static let script = """
    #!/bin/sh
    # TokenBar: guarda o JSON da statusline do Claude Code e repassa para a statusline original.
    d="$HOME/.tokenbar"
    input=$(cat)
    case "$input" in
      *'"rate_limits"'*) mkdir -p "$d" && printf '%s' "$input" > "$d/claude.json.tmp" && mv "$d/claude.json.tmp" "$d/claude.json" ;;
    esac
    orig=$(cat "$d/statusline-original" 2>/dev/null)
    if [ -n "$orig" ]; then printf '%s' "$input" | sh -c "$orig"; fi

    """

    static var isInstalled: Bool {
        currentCommand()?.contains("claude-tee.sh") == true
    }

    static func currentCommand() -> String? {
        guard let data = try? Data(contentsOf: settingsURL),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let status = obj["statusLine"] as? [String: Any]
        else { return nil }
        return status["command"] as? String
    }

    static func install() throws {
        let fm = FileManager.default
        try fm.createDirectory(at: Collector.tokenbarDir, withIntermediateDirectories: true)
        try script.write(to: teeScript, atomically: true, encoding: .utf8)
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: teeScript.path)
        if isInstalled { return }

        let original = currentCommand() ?? ""
        try original.write(to: originalFile, atomically: true, encoding: .utf8)

        // Troca só o texto do comando: o resto do settings.json fica como a pessoa escreveu.
        try fm.createDirectory(at: settingsURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        var text = (try? String(contentsOf: settingsURL, encoding: .utf8)) ?? "{}"
        if fm.fileExists(atPath: settingsURL.path) {
            try Data(text.utf8).write(to: settingsURL.appendingPathExtension("tokenbar-backup"))
        }
        let ours = jsonString(teeScript.path)
        let block = try NSRegularExpression(pattern: #""statusLine"\s*:\s*\{[^{}]*\}"#)
        let command = try NSRegularExpression(pattern: #""command"\s*:\s*"(?:\\.|[^"\\])*""#)
        let whole = NSRange(text.startIndex..., in: text)

        if let m = block.firstMatch(in: text, range: whole), let r = Range(m.range, in: text) {
            var inner = String(text[r])
            let innerRange = NSRange(inner.startIndex..., in: inner)
            if command.firstMatch(in: inner, range: innerRange) != nil {
                inner = command.stringByReplacingMatches(in: inner, range: innerRange,
                                                         withTemplate: NSRegularExpression.escapedTemplate(for: "\"command\": \(ours)"))
            } else {
                inner = "\"statusLine\": {\"type\": \"command\", \"command\": \(ours)}"
            }
            text.replaceSubrange(r, with: inner)
        } else if let brace = text.firstIndex(of: "{") {
            let rest = text[text.index(after: brace)...].trimmingCharacters(in: .whitespacesAndNewlines)
            let sep = rest.hasPrefix("}") ? "" : ","
            text.insert(contentsOf: "\n  \"statusLine\": {\"type\": \"command\", \"command\": \(ours)}\(sep)", at: text.index(after: brace))
        }

        // Só grava se continuar sendo JSON válido.
        guard (try? JSONSerialization.jsonObject(with: Data(text.utf8))) != nil else {
            throw CocoaError(.fileWriteUnknown, userInfo: [NSLocalizedDescriptionKey: Lang.t("Não consegui editar o settings.json com segurança")])
        }
        try Data(text.utf8).write(to: settingsURL, options: .atomic)
    }

    private static func jsonString(_ s: String) -> String {
        let data = try! JSONSerialization.data(withJSONObject: [s], options: [.withoutEscapingSlashes])
        return String(decoding: data, as: UTF8.self).dropFirst().dropLast().description
    }
}
