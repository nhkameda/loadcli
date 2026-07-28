import Foundation

/// One project found on disk during a scan.
struct ScannedProject: Codable, Hashable {
    var project: Project
    /// Absolute path of the `LOADCLI.md` that produced it.
    var documentPath: String
    /// The document's modification date, used to skip re-parsing next time.
    var modified: Date
    /// Which configured root it was found under (kept so an unreachable root
    /// can hold on to its cached cards instead of having them disappear).
    var root: String

    init(project: Project, documentPath: String, modified: Date, root: String) {
        self.project = project
        self.documentPath = documentPath
        self.modified = modified
        self.root = root
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        project = try c.decode(Project.self, forKey: .project)
        documentPath = try c.decodeIfPresent(String.self, forKey: .documentPath) ?? ""
        modified = try c.decodeIfPresent(Date.self, forKey: .modified) ?? .distantPast
        root = try c.decodeIfPresent(String.self, forKey: .root) ?? ""
    }
}

/// Result of walking every configured root.
struct ScanOutcome {
    var found: [ScannedProject] = []
    /// Roots that could not be read this time (volume not mounted, Drive still
    /// syncing, folder renamed). Their cached cards are kept.
    var unavailableRoots: [String] = []
    var visitedDirectories: Int = 0
}

/// Walks the configured root folders looking for `LOADCLI.md` files and turns
/// each one into a card.
///
/// The walk is deliberately shallow-ish and prunes aggressively: once a folder
/// has a `LOADCLI.md` it *is* a project, so there is no reason to descend into
/// it — that alone keeps a `~/DEV` with dozens of `node_modules` fast.
enum ProjectScanner {
    /// Directory names never worth descending into.
    static let ignoredDirectories: Set<String> = [
        ".git", ".hg", ".svn", "node_modules", "Pods", "Carthage", "build",
        ".build", "DerivedData", "dist", "out", "vendor", "target", "venv",
        ".venv", "env", "__pycache__", ".next", ".nuxt", ".cache", ".gradle",
        ".idea", ".vscode", "Library", "bower_components", ".terraform",
        ".pytest_cache", ".mypy_cache", ".tox", "coverage", ".yarn", ".pnpm-store",
    ]

    /// Scan every root off the main actor.
    ///
    /// - Parameter cache: previously indexed documents keyed by absolute path;
    ///   an entry whose modification date is unchanged is reused as-is instead
    ///   of being read and parsed again.
    static func scan(roots: [String],
                     maxDepth: Int,
                     cache: [String: ScannedProject]) async -> ScanOutcome {
        await Task.detached(priority: .utility) {
            scanSync(roots: roots, maxDepth: maxDepth, cache: cache)
        }.value
    }

    /// Synchronous core — also used by the migration, which already runs off the
    /// UI's critical path.
    static func scanSync(roots: [String],
                         maxDepth: Int,
                         cache: [String: ScannedProject]) -> ScanOutcome {
        var outcome = ScanOutcome()
        let fm = FileManager.default
        var seenDocuments = Set<String>()

        for root in AppSettings.normalize(roots: roots) {
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: root, isDirectory: &isDir), isDir.boolValue else {
                outcome.unavailableRoots.append(root)
                continue
            }

            // A root can itself be a project folder.
            var queue: [(url: URL, depth: Int)] = [(URL(fileURLWithPath: root, isDirectory: true), 0)]
            var readFailures = 0
            var directoriesRead = 0

            while let current = queue.popLast() {
                // FileManager hands back resolved paths while enumerating
                // (`/var` comes back as `/private/var`), so every folder is put
                // through the same canonical form the roots and the index use —
                // otherwise the mtime cache would never hit.
                let folderPath = AppSettings.canonical(current.url.path)

                if let entry = document(at: folderPath, root: root, cache: cache, fm: fm) {
                    if seenDocuments.insert(entry.documentPath).inserted {
                        outcome.found.append(entry)
                    }
                    continue   // prune: a project folder is a leaf
                }

                guard current.depth < max(1, maxDepth) else { continue }

                let children: [URL]
                do {
                    children = try fm.contentsOfDirectory(
                        at: current.url,
                        includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
                        options: [.skipsHiddenFiles, .skipsPackageDescendants])
                    directoriesRead += 1
                } catch {
                    readFailures += 1
                    continue
                }

                for child in children {
                    let name = child.lastPathComponent
                    if ignoredDirectories.contains(name) || name.hasPrefix(".") { continue }
                    let values = try? child.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
                    guard values?.isDirectory == true else { continue }
                    // Don't follow symlinks — they are the usual source of cycles.
                    if values?.isSymbolicLink == true { continue }
                    queue.append((child, current.depth + 1))
                }
                outcome.visitedDirectories += 1
            }

            // The root existed but nothing under it could be read at all —
            // treat it as unavailable so its cached cards survive.
            if directoriesRead == 0 && readFailures > 0 {
                outcome.unavailableRoots.append(root)
            }
        }

        return outcome
    }

    // MARK: - One folder

    /// Build (or reuse) the entry for `folderPath` when it holds a `LOADCLI.md`.
    private static func document(at folderPath: String,
                                 root: String,
                                 cache: [String: ScannedProject],
                                 fm: FileManager) -> ScannedProject? {
        let docPath = ProjectDoc.path(inFolder: folderPath)
        guard let attributes = try? fm.attributesOfItem(atPath: docPath),
              attributes[.type] as? FileAttributeType != FileAttributeType.typeDirectory
        else { return nil }

        let modified = (attributes[.modificationDate] as? Date) ?? Date()

        if let cached = cache[docPath],
           abs(cached.modified.timeIntervalSince(modified)) < 0.5 {
            var reused = cached
            reused.root = root
            reused.project.folderPath = folderPath   // the folder may have moved
            return reused
        }

        guard var doc = ProjectDoc.read(inFolder: folderPath) else { return nil }
        if doc.project.repoURL.trimmingCharacters(in: .whitespaces).isEmpty,
           let remote = gitRemote(inFolder: folderPath) {
            doc.project.repoURL = remote
        }
        return ScannedProject(project: doc.project,
                              documentPath: docPath,
                              modified: modified,
                              root: root)
    }

    /// Best-effort read of the `origin` remote straight out of `.git/config` —
    /// no subprocess, so it is cheap enough to do while scanning.
    static func gitRemote(inFolder folderPath: String) -> String? {
        let config = (folderPath as NSString)
            .appendingPathComponent(".git")
        var configPath = (config as NSString).appendingPathComponent("config")

        // Worktrees / submodules store a `.git` file pointing elsewhere.
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: config, isDirectory: &isDir), !isDir.boolValue {
            guard let pointer = try? String(contentsOfFile: config, encoding: .utf8),
                  let range = pointer.range(of: "gitdir:") else { return nil }
            let target = pointer[range.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
            let resolved = target.hasPrefix("/")
                ? target
                : (folderPath as NSString).appendingPathComponent(target)
            configPath = (resolved as NSString).appendingPathComponent("config")
        }

        guard let text = try? String(contentsOfFile: configPath, encoding: .utf8) else { return nil }

        var inOrigin = false
        var firstRemote: String?
        for rawLine in text.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("[") {
                inOrigin = line.replacingOccurrences(of: " ", with: "")
                    .lowercased()
                    .hasPrefix("[remote\"origin\"]")
                continue
            }
            guard line.lowercased().hasPrefix("url") ,
                  let eq = line.firstIndex(of: "=") else { continue }
            let value = String(line[line.index(after: eq)...]).trimmingCharacters(in: .whitespaces)
            guard !value.isEmpty else { continue }
            if inOrigin { return value }
            if firstRemote == nil { firstRemote = value }
        }
        return firstRemote
    }
}
