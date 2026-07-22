import Foundation
import Combine

/// Persists projects and settings as JSON in Application Support/loadcli.
@MainActor
final class Store: ObservableObject {
    @Published var projects: [Project] = []
    @Published var folders: [ProjectFolder] = []
    @Published var settings = AppSettings()

    private let dir: URL
    private let projectsURL: URL
    private let foldersURL: URL
    private let settingsURL: URL

    init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        dir = base.appendingPathComponent("loadcli", isDirectory: true)
        projectsURL = dir.appendingPathComponent("projects.json")
        foldersURL = dir.appendingPathComponent("folders.json")
        settingsURL = dir.appendingPathComponent("settings.json")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        load()
    }

    func load() {
        let dec = JSONDecoder()
        if let data = try? Data(contentsOf: projectsURL),
           let p = try? dec.decode([Project].self, from: data) {
            projects = p
        }
        if let data = try? Data(contentsOf: foldersURL),
           let f = try? dec.decode([ProjectFolder].self, from: data) {
            folders = f
        }
        if let data = try? Data(contentsOf: settingsURL),
           let s = try? dec.decode(AppSettings.self, from: data) {
            settings = s
        }
    }

    func save() {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? enc.encode(projects) { try? data.write(to: projectsURL) }
        if let data = try? enc.encode(folders) { try? data.write(to: foldersURL) }
        if let data = try? enc.encode(settings) { try? data.write(to: settingsURL) }
    }

    func upsert(_ project: Project) {
        if let i = projects.firstIndex(where: { $0.id == project.id }) {
            projects[i] = project
        } else {
            projects.append(project)
        }
        save()
    }

    func delete(_ project: Project) {
        projects.removeAll { $0.id == project.id }
        save()
    }

    func duplicate(_ project: Project) {
        var copy = project
        copy.id = UUID()
        copy.name = project.name + " cópia"
        if let i = projects.firstIndex(where: { $0.id == project.id }) {
            projects.insert(copy, at: i + 1)
        } else {
            projects.append(copy)
        }
        save()
    }

    func move(from source: IndexSet, to destination: Int) {
        projects.move(fromOffsets: source, toOffset: destination)
        save()
    }

    /// Reassign a project to a folder (nil = ungrouped).
    func setFolder(_ folderID: UUID?, for project: Project) {
        guard let i = projects.firstIndex(where: { $0.id == project.id }) else { return }
        projects[i].folderID = folderID
        save()
    }

    // MARK: Folders

    func projects(in folderID: UUID?) -> [Project] {
        projects.filter { $0.folderID == folderID }
    }

    func upsertFolder(_ folder: ProjectFolder) {
        if let i = folders.firstIndex(where: { $0.id == folder.id }) {
            folders[i] = folder
        } else {
            folders.append(folder)
        }
        save()
    }

    /// Delete a folder. By default its projects are kept, just un-grouped.
    func deleteFolder(_ folder: ProjectFolder, keepingProjects: Bool = true) {
        if keepingProjects {
            for i in projects.indices where projects[i].folderID == folder.id {
                projects[i].folderID = nil
            }
        } else {
            projects.removeAll { $0.folderID == folder.id }
        }
        folders.removeAll { $0.id == folder.id }
        save()
    }

    func toggleCollapsed(_ folder: ProjectFolder) {
        guard let i = folders.firstIndex(where: { $0.id == folder.id }) else { return }
        folders[i].collapsed.toggle()
        save()
    }

    var configFolder: URL { dir }
}
