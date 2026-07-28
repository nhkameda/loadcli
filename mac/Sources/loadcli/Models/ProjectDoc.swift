import Foundation
import CryptoKit

/// Reader/writer for `LOADCLI.md` — the file that lives inside a project folder
/// and *is* the card.
///
/// Layout: a front matter block of `chave: valor` lines between `---` markers,
/// followed by free markdown that becomes the project's description.
///
/// ```markdown
/// ---
/// loadcli: 1
/// id: 6C0F2A18-3D4B-4E71-9A02-1F5C8B3E77D9
/// nome: Acme Site
/// grupo: Clientes
/// ---
///
/// Loja da Acme. Deploy pela Vercel.
/// ```
///
/// Two rules make it portable across synced machines:
/// * no absolute path is ever written — the project folder is wherever the file
///   was found, and `pastaFinder` is stored relative to it;
/// * unknown keys and the markdown body are preserved on rewrite, so anything
///   the user (or a future version) adds by hand survives.
struct ProjectDoc {
    static let fileName = "LOADCLI.md"
    static let formatVersion = 1

    /// The card built from the document (`folderPath` already resolved).
    var project: Project
    /// Front-matter lines we didn't recognise, kept verbatim.
    var unknownLines: [String]
    /// The markdown body (also mirrored into `project.details`).
    var body: String

    // MARK: - Reading

    /// Absolute path of the document inside `folderPath`.
    static func path(inFolder folderPath: String) -> String {
        (folderPath as NSString).appendingPathComponent(fileName)
    }

    static func exists(inFolder folderPath: String) -> Bool {
        FileManager.default.fileExists(atPath: path(inFolder: folderPath))
    }

    /// Read and parse the document in `folderPath`. Returns nil when there is no
    /// file there or it can't be read.
    static func read(inFolder folderPath: String, fallbackID: UUID? = nil) -> ProjectDoc? {
        let file = path(inFolder: folderPath)
        guard let text = try? String(contentsOfFile: file, encoding: .utf8) else { return nil }
        return parse(text, folderPath: folderPath, fallbackID: fallbackID)
    }

    /// Build a document from raw text. `folderPath` is the directory the file
    /// lives in — always the source of truth for the project's location.
    static func parse(_ text: String, folderPath: String, fallbackID: UUID? = nil) -> ProjectDoc {
        let (pairs, unknownCandidates, body) = splitFrontMatter(text)

        var fields: [String: String] = [:]
        for (key, value) in pairs where fields[normalize(key)] == nil {
            fields[normalize(key)] = value
        }

        var p = Project()
        p.folderPath = folderPath
        p.id = fields.uuid(Keys.id) ?? fallbackID ?? stableID(for: folderPath)
        p.name = fields.string(Keys.name) ?? (folderPath as NSString).lastPathComponent
        p.group = fields.string(Keys.group)
        p.iconSymbol = fields.string(Keys.icon) ?? p.iconSymbol
        p.colorHex = fields.string(Keys.color).flatMap(sanitizeHex) ?? p.colorHex
        p.repoURL = fields.string(Keys.repo) ?? ""
        p.url = fields.string(Keys.url) ?? ""
        p.terminalApp = fields.string(Keys.terminal).flatMap(resolveTerminal) ?? p.terminalApp

        if let browser = fields.string(Keys.browser).flatMap(resolveBrowser) {
            p.browserBundleID = browser.id
            p.browserName = browser.name
        }

        if let tool = fields.string(Keys.cli).flatMap(resolveCLITool) {
            p.cliTool = tool
        }
        if let command = fields.string(Keys.command) {
            p.cliCommand = command
            if fields.string(Keys.cli) == nil { p.cliTool = .custom }
        }
        if let model = fields.string(Keys.model) {
            switch p.cliTool {
            case .claude: p.claudeModel = model
            case .codex:  p.codexModel = model
            case .custom: break
            }
        }
        if let effort = fields.string(Keys.effort) {
            switch p.cliTool {
            case .claude: p.claudeEffort = effort
            case .codex:  p.codexEffort = effort
            case .custom: break
            }
        }

        if let pane = fields.string(Keys.pane).flatMap(resolvePane) {
            p.secondaryPane = pane
        }
        if let finder = fields.string(Keys.finderPath), !finder.isEmpty {
            // Stored relative to the project folder; absolute values still work.
            p.finderPath = finder.hasPrefix("/")
                ? finder
                : (folderPath as NSString).appendingPathComponent(finder)
        }
        if let mode = fields.string(Keys.workspace).flatMap(resolveWorkspace) {
            p.workspaceMode = mode
        }
        if let side = fields.string(Keys.side).flatMap(resolveSide) {
            p.splitSide = side
        }
        if let ratio = fields.double(Keys.ratio) {
            p.splitRatio = min(0.7, max(0.3, ratio > 1 ? ratio / 100 : ratio))
        }
        if let fullscreen = fields.bool(Keys.fullscreen) {
            p.soloTerminalLayout = fullscreen ? .fullscreen : .maximized
        }

        let trimmedBody = body.trimmingCharacters(in: .whitespacesAndNewlines)
        p.details = trimmedBody

        return ProjectDoc(project: p, unknownLines: unknownCandidates, body: trimmedBody)
    }

    // MARK: - Writing

    /// Render the document text for `project`, preserving anything unknown that
    /// the previous version of the file carried.
    static func render(_ project: Project, preserving previous: ProjectDoc? = nil) -> String {
        var lines: [String] = ["---"]
        func put(_ key: String, _ value: String?) {
            guard let value, !value.isEmpty else { return }
            lines.append("\(key): \(quoteIfNeeded(value))")
        }

        lines.append("\(Keys.version): \(formatVersion)")
        put(Keys.id, project.id.uuidString)
        put(Keys.name, project.name.trimmingCharacters(in: .whitespacesAndNewlines))
        put(Keys.group, project.groupName)
        put(Keys.icon, project.iconSymbol)
        put(Keys.color, project.colorHex)
        put(Keys.repo, project.trimmedRepo)
        put(Keys.url, project.trimmedURL)
        put(Keys.browser, project.browserBundleID)
        put(Keys.terminal, project.terminalApp)
        put(Keys.cli, project.cliTool.rawValue)
        if project.cliTool == .custom {
            put(Keys.command, project.cliCommand)
        } else {
            switch project.cliTool {
            case .claude:
                put(Keys.model, project.claudeModel)
                put(Keys.effort, project.claudeEffort)
            case .codex:
                put(Keys.model, project.codexModel)
                put(Keys.effort, project.codexEffort)
            case .custom:
                break
            }
        }
        put(Keys.pane, project.secondaryPane.rawValue)
        put(Keys.finderPath, relativeFinderPath(for: project))
        put(Keys.workspace, project.workspaceMode.rawValue)
        if project.secondaryPane != .none {
            put(Keys.side, project.splitSide.rawValue)
            put(Keys.ratio, String(format: "%.2f", project.splitRatio))
        }
        put(Keys.fullscreen, project.soloTerminalLayout == .fullscreen ? "sim" : "nao")

        if let extras = previous?.unknownLines, !extras.isEmpty {
            lines.append(contentsOf: extras)
        }

        lines.append("---")
        lines.append("")

        let body = project.trimmedDetails
        if !body.isEmpty {
            lines.append(body)
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }

    /// Write `project`'s `LOADCLI.md` into its own folder, keeping any unknown
    /// keys that were already there. Creates the folder if needed.
    @discardableResult
    static func write(_ project: Project) throws -> String {
        let folder = project.folderPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !folder.isEmpty else {
            throw NSError(domain: "loadcli", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "O projeto não tem uma pasta definida.",
            ])
        }
        try FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)
        let previous = read(inFolder: folder)
        let text = render(project, preserving: previous)
        let file = path(inFolder: folder)
        try text.write(toFile: file, atomically: true, encoding: .utf8)
        return file
    }

    /// Move a project's document to the Trash (reversible). The project folder
    /// itself is never touched.
    static func trashDocument(inFolder folderPath: String) throws {
        let file = path(inFolder: folderPath)
        guard FileManager.default.fileExists(atPath: file) else { return }
        try FileManager.default.trashItem(at: URL(fileURLWithPath: file), resultingItemURL: nil)
    }

    // MARK: - Identity

    /// A UUID derived from the folder's own name + its parent, used only when a
    /// hand-written document has no `id:`. Deterministic, so the same folder
    /// keeps the same identity on every machine.
    static func stableID(for folderPath: String) -> UUID {
        let ns = folderPath as NSString
        let seed = [(ns.deletingLastPathComponent as NSString).lastPathComponent,
                    ns.lastPathComponent].joined(separator: "/")
        var bytes = Array(SHA256.hash(data: Data(seed.utf8)).prefix(16))
        // Stamp version 5 / RFC-4122 variant bits so it is a well-formed UUID.
        bytes[6] = (bytes[6] & 0x0F) | 0x50
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3],
                           bytes[4], bytes[5], bytes[6], bytes[7],
                           bytes[8], bytes[9], bytes[10], bytes[11],
                           bytes[12], bytes[13], bytes[14], bytes[15]))
    }

    // MARK: - Front matter plumbing

    /// Split `text` into recognised key/value pairs, unrecognised front-matter
    /// lines and the markdown body.
    private static func splitFrontMatter(_ text: String) -> ([(String, String)], [String], String) {
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n")
        let lines = normalized.components(separatedBy: "\n")

        // Find the opening marker (allowing a leading blank line or BOM).
        var index = 0
        while index < lines.count, lines[index].trimmingCharacters(in: .whitespaces).isEmpty { index += 1 }
        guard index < lines.count, isMarker(lines[index]) else {
            return ([], [], normalized)   // no front matter: everything is body
        }
        index += 1

        var pairs: [(String, String)] = []
        var unknown: [String] = []
        var closed = false
        while index < lines.count {
            let line = lines[index]
            if isMarker(line) { closed = true; index += 1; break }
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") {
                index += 1
                continue
            }
            if let colon = trimmed.firstIndex(of: ":") {
                let key = String(trimmed[trimmed.startIndex..<colon]).trimmingCharacters(in: .whitespaces)
                let value = unquote(String(trimmed[trimmed.index(after: colon)...])
                    .trimmingCharacters(in: .whitespaces))
                if Keys.all.contains(normalize(key)) {
                    pairs.append((key, value))
                } else {
                    unknown.append(trimmed)
                }
            } else {
                unknown.append(trimmed)
            }
            index += 1
        }

        guard closed else { return ([], [], normalized) }   // unterminated → treat as plain markdown
        let body = lines[index...].joined(separator: "\n")
        return (pairs, unknown, body)
    }

    private static func isMarker(_ line: String) -> Bool {
        let t = line.trimmingCharacters(in: .whitespaces)
        return t == "---" || t == "----"
    }

    private static func unquote(_ value: String) -> String {
        guard value.count >= 2 else { return value }
        let quotes: [Character] = ["\"", "'"]
        if let first = value.first, let last = value.last,
           quotes.contains(first), first == last {
            return String(value.dropFirst().dropLast())
        }
        return value
    }

    private static func quoteIfNeeded(_ value: String) -> String {
        if value.hasPrefix("#") || value.hasPrefix(" ") || value.hasSuffix(" ") || value.contains("\n") {
            return "\"" + value.replacingOccurrences(of: "\"", with: "\\\"") + "\""
        }
        return value
    }

    /// Lower-cased, accent-free key so `esforço`, `esforco` and `Effort` match.
    private static func normalize(_ key: String) -> String {
        key.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "pt_BR"))
            .trimmingCharacters(in: .whitespaces)
    }

    private static func sanitizeHex(_ value: String) -> String? {
        let v = value.hasPrefix("#") ? value : "#" + value
        let hex = v.dropFirst()
        guard hex.count == 6 || hex.count == 3,
              hex.allSatisfy({ $0.isHexDigit }) else { return nil }
        return v.uppercased()
    }

    private static func relativeFinderPath(for project: Project) -> String? {
        let finder = project.finderPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !finder.isEmpty, finder != project.folderPath else { return nil }
        let base = project.folderPath.hasSuffix("/") ? project.folderPath : project.folderPath + "/"
        if finder.hasPrefix(base) { return String(finder.dropFirst(base.count)) }
        return finder
    }

    // MARK: - Value resolution (accepts Portuguese and English spellings)

    private static func resolveCLITool(_ raw: String) -> CLITool? {
        switch normalize(raw) {
        case "claude", "claude code", "claudecode": return .claude
        case "codex": return .codex
        case "custom", "personalizado", "shell": return .custom
        default: return CLITool(rawValue: raw)
        }
    }

    private static func resolvePane(_ raw: String) -> SecondaryPane? {
        switch normalize(raw) {
        case "none", "nenhum", "nao", "no", "": return Optional(SecondaryPane.none)
        case "browser", "navegador", "site", "web": return .browser
        case "finder", "pasta", "folder": return .finder
        default: return SecondaryPane(rawValue: raw)
        }
    }

    private static func resolveWorkspace(_ raw: String) -> WorkspaceMode? {
        switch normalize(raw) {
        case "newdesktop", "nova", "nova mesa", "new": return .newDesktop
        case "splitcurrent", "atual", "mesa atual", "current": return .splitCurrent
        default: return WorkspaceMode(rawValue: raw)
        }
    }

    private static func resolveSide(_ raw: String) -> SplitSide? {
        switch normalize(raw) {
        case "terminalright", "direita", "right": return .terminalRight
        case "terminalleft", "esquerda", "left": return .terminalLeft
        default: return SplitSide(rawValue: raw)
        }
    }

    private static func resolveTerminal(_ raw: String) -> String? {
        let key = normalize(raw)
        if let byName = AppCatalog.terminals.first(where: { normalize($0.name) == key }) { return byName.name }
        if let byID = AppCatalog.terminals.first(where: { normalize($0.id) == key }) { return byID.name }
        return nil
    }

    private static func resolveBrowser(_ raw: String) -> AppCatalog.Option? {
        let key = normalize(raw)
        return AppCatalog.browsers.first { normalize($0.id) == key || normalize($0.name) == key }
    }

    /// Front-matter key names. The first spelling is what we write.
    enum Keys {
        static let version = "loadcli"
        static let id = "id"
        static let name = "nome"
        static let group = "grupo"
        static let icon = "icone"
        static let color = "cor"
        static let repo = "repositorio"
        static let url = "url"
        static let browser = "navegador"
        static let terminal = "terminal"
        static let cli = "cli"
        static let command = "comando"
        static let model = "modelo"
        static let effort = "esforco"
        static let pane = "painel"
        static let finderPath = "pastaFinder"
        static let workspace = "mesa"
        static let side = "lado"
        static let ratio = "divisao"
        static let fullscreen = "telaCheia"

        /// Every accepted spelling (normalised), Portuguese + English. A key
        /// that is NOT in here is preserved verbatim on rewrite instead of
        /// being silently dropped.
        static let all: Set<String> = [
            version, id, name, group, icon, color, repo, url, browser, terminal,
            cli, command, model, effort, pane, "pastafinder", workspace, side,
            ratio, "telacheia",
            // English aliases
            "name", "project", "title", "group", "icon", "color", "colour",
            "repository", "repo", "git", "site", "website", "browser", "tool",
            "command", "model", "effort", "pane", "finder", "workspace",
            "desktop", "side", "ratio", "split", "fullscreen",
        ]

        /// Maps every accepted spelling onto the canonical key.
        static let aliases: [String: String] = [
            "project": name, "title": name, "name": name,
            "group": group,
            "icon": icon,
            "color": color, "colour": color,
            "repository": repo, "repo": repo, "git": repo,
            "site": url, "website": url,
            "tool": cli,
            "command": command,
            "model": model,
            "effort": effort,
            "pane": pane,
            "finder": "pastafinder", "pastafinder": "pastafinder",
            "workspace": workspace, "desktop": workspace,
            "side": side,
            "ratio": ratio, "split": ratio,
            "fullscreen": "telacheia", "telacheia": "telacheia",
            "browser": browser,
        ]
    }
}

/// Small typed accessors over the parsed front matter, resolving aliases.
private extension Dictionary where Key == String, Value == String {
    func raw(_ canonical: String) -> String? {
        let wanted = canonical.folding(options: [.diacriticInsensitive, .caseInsensitive],
                                       locale: Locale(identifier: "pt_BR"))
        if let direct = self[wanted] { return direct }
        for (spelling, target) in ProjectDoc.Keys.aliases where target == canonical || target == wanted {
            if let value = self[spelling] { return value }
        }
        return nil
    }

    func string(_ key: String) -> String? {
        guard let v = raw(key)?.trimmingCharacters(in: .whitespacesAndNewlines), !v.isEmpty else { return nil }
        return v
    }

    func uuid(_ key: String) -> UUID? { string(key).flatMap(UUID.init(uuidString:)) }

    func double(_ key: String) -> Double? {
        guard let v = string(key) else { return nil }
        return Double(v.replacingOccurrences(of: ",", with: "."))
    }

    func bool(_ key: String) -> Bool? {
        guard let v = string(key)?.folding(options: [.diacriticInsensitive, .caseInsensitive],
                                           locale: Locale(identifier: "pt_BR")) else { return nil }
        switch v {
        case "sim", "yes", "true", "1", "on": return true
        case "nao", "no", "false", "0", "off": return false
        default: return nil
        }
    }
}
