import Foundation
import Combine

/// Persists projects and settings as JSON in Application Support/loadcli.
@MainActor
final class Store: ObservableObject {
    @Published var projects: [Project] = []
    @Published var settings = AppSettings()

    private let dir: URL
    private let projectsURL: URL
    private let settingsURL: URL

    init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        dir = base.appendingPathComponent("loadcli", isDirectory: true)
        projectsURL = dir.appendingPathComponent("projects.json")
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
        if let data = try? Data(contentsOf: settingsURL),
           let s = try? dec.decode(AppSettings.self, from: data) {
            settings = s
        }
    }

    func save() {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? enc.encode(projects) { try? data.write(to: projectsURL) }
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

    var configFolder: URL { dir }
}
