import AppKit

/// Launches the Terminal (running the CLI in the project folder) and the
/// browser (opening the deploy URL) via Apple Events.
///
/// No script ever calls `activate`: with the system default
/// `AppleSpacesSwitchOnActivate` (auto-swoosh) ON, activating an app jumps to a
/// Space that already has its windows — pulling focus off the desktop we just
/// created. Windows created without activation join the Space that is active
/// on their display at creation time.
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

    private static func isRunning(_ bundleID: String) -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty
    }

    /// Launch an app in the background (no activation → no auto-swoosh) and
    /// wait until it has at least one window, so scripts can target `window 1`.
    private static func launchAndWaitForWindow(_ bundleID: String,
                                               timeout: TimeInterval = 6) async -> Bool {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            return false
        }
        let config = NSWorkspace.OpenConfiguration()
        config.activates = false
        config.addsToRecentItems = false
        _ = try? await NSWorkspace.shared.openApplication(at: url, configuration: config)

        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let app = NSRunningApplication
                .runningApplications(withBundleIdentifier: bundleID).first,
               !AX.windows(AX.app(pid: app.processIdentifier)).isEmpty {
                return true
            }
            try? await Task.sleep(nanoseconds: 200_000_000)
        }
        return false
    }

    @discardableResult
    static func openTerminal(folder: String, command: String,
                             appName: String, bundleID: String) async -> (ok: Bool, error: String?) {
        var shell = "cd " + shellSingleQuoted(folder)
        let cmd = command.trimmingCharacters(in: .whitespacesAndNewlines)
        if !cmd.isEmpty { shell += " && " + cmd }

        let appLit = asLiteral(appName)
        let cmdLit = asLiteral(shell)

        if appName == "iTerm" {
            // Cold start: iTerm already opens one window at launch — writing the
            // command into it avoids the classic duplicate-window bug. When it
            // is already running, create a fresh window.
            if !isRunning(bundleID), await launchAndWaitForWindow(bundleID) {
                let reuse = run("""
                tell application \(appLit)
                    tell current session of current window to write text \(cmdLit)
                end tell
                """)
                if reuse.ok { return reuse }
            }
            return run("""
            tell application \(appLit)
                set newWin to (create window with default profile)
                tell current session of newWin to write text \(cmdLit)
            end tell
            """)
        }

        // Apple Terminal (and compatible). Cold start: `do script` on a
        // non-running Terminal opens TWO windows (startup + script), so launch
        // it in the background first and run the script in the startup window.
        if !isRunning(bundleID), await launchAndWaitForWindow(bundleID) {
            let reuse = run("tell application \(appLit) to do script \(cmdLit) in window 1")
            if reuse.ok { return reuse }
        }
        return run("tell application \(appLit) to do script \(cmdLit)")
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
        // A timeout guards against a busy browser hanging the launch.
        if chromeFamily.contains(bundleID) {
            let src = """
            with timeout of 12 seconds
                tell application \(nameLit)
                    set w to make new window
                    set URL of active tab of w to \(urlLit)
                end tell
            end timeout
            """
            return run(src)
        }
        if bundleID == "com.apple.Safari" || name == "Safari" {
            let src = """
            with timeout of 12 seconds
                tell application "Safari" to make new document with properties {URL:\(urlLit)}
            end timeout
            """
            return run(src)
        }
        // Generic fallback: open a new window via `open` without activation.
        let src = "do shell script \"open -g -na \(name.replacingOccurrences(of: "\"", with: "")) --args --new-window \(normalized)\""
        return run(src)
    }
}
