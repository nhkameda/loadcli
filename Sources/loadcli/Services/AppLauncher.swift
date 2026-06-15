import AppKit

/// Launches the Terminal (running the CLI in the project folder) and the
/// browser (opening the deploy URL) via Apple Events.
@MainActor
enum AppLauncher {
    @discardableResult
    static func run(_ source: String) -> (ok: Bool, error: String?) {
        var err: NSDictionary?
        guard let script = NSAppleScript(source: source) else { return (false, "script inválido") }
        script.executeAndReturnError(&err)
        if let err { return (false, (err[NSAppleScript.errorMessage] as? String) ?? "erro AppleScript") }
        return (true, nil)
    }

    /// Quote a string for safe use inside a single-quoted POSIX shell argument.
    private static func shellSingleQuoted(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    /// Escape a string for an AppleScript double-quoted literal.
    private static func asLiteral(_ s: String) -> String {
        "\"" + s.replacingOccurrences(of: "\\", with: "\\\\")
                 .replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }

    @discardableResult
    static func openTerminal(folder: String, command: String, appName: String) -> (ok: Bool, error: String?) {
        var shell = "cd " + shellSingleQuoted(folder)
        let cmd = command.trimmingCharacters(in: .whitespacesAndNewlines)
        if !cmd.isEmpty { shell += " && " + cmd }

        let appLit = asLiteral(appName)
        let cmdLit = asLiteral(shell)

        if appName == "iTerm" {
            let src = """
            tell application \(appLit)
                activate
                set newWin to (create window with default profile)
                tell current session of newWin to write text \(cmdLit)
            end tell
            """
            return run(src)
        }
        // Apple Terminal (and compatible)
        let src = """
        tell application \(appLit)
            activate
            do script \(cmdLit)
        end tell
        """
        return run(src)
    }

    @discardableResult
    static func openBrowser(url: String, bundleID: String, name: String) -> (ok: Bool, error: String?) {
        let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return (true, nil) }
        let normalized = (trimmed.contains("://") ? trimmed : "https://" + trimmed)
        let nameLit = asLiteral(name)
        let urlLit = asLiteral(normalized)

        let chromeFamily = ["com.google.Chrome", "com.brave.Browser",
                            "com.microsoft.edgemac", "company.thebrowser.Browser"]
        if chromeFamily.contains(bundleID) {
            let src = """
            tell application \(nameLit)
                activate
                make new window
                set URL of active tab of front window to \(urlLit)
            end tell
            """
            return run(src)
        }
        if bundleID == "com.apple.Safari" || name == "Safari" {
            let src = """
            tell application "Safari"
                activate
                make new document with properties {URL:\(urlLit)}
            end tell
            """
            return run(src)
        }
        // Generic fallback: open a new window via `open`.
        let src = "do shell script \"open -na \(name.replacingOccurrences(of: "\"", with: "")) --args --new-window \(normalized)\""
        return run(src)
    }
}
