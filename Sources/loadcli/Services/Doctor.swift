import AppKit

/// `loadcli --doctor` — self-test of the desktop ("mesa") machinery, printed to
/// stdout. Runs a create → switch → remove round-trip on every display and
/// restores the previous state. Use it to validate permissions and each
/// mechanism, especially after a macOS update.
enum Doctor {
    /// Pump the main run loop until the async self-test finishes (the app
    /// never starts NSApplication in doctor mode).
    static func runBlocking() -> Int32 {
        final class Box { var code: Int32? }
        let box = Box()
        Task { @MainActor in box.code = await run() }
        while box.code == nil {
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        }
        return box.code!
    }

    @discardableResult
    private static func line(_ ok: Bool, _ label: String) -> Bool {
        print("  [\(ok ? "PASS" : "FALHA")] \(label)")
        return ok
    }

    @MainActor
    static func run() async -> Int32 {
        print("loadcli --doctor — autoteste de criação/troca de mesas")
        print("macOS \(ProcessInfo.processInfo.operatingSystemVersionString)")
        var allOK = true

        let ax = Permissions.hasAccessibility()
        allOK = line(ax, "Permissão de Acessibilidade") && allOK
        guard ax else {
            Permissions.requestAccessibility()
            print("→ Conceda Acessibilidade ao loadcli em Ajustes do Sistema e rode novamente.")
            return 1
        }
        allOK = line(SkyLight.isAvailable, "SkyLight — leitura de mesas") && allOK
        allOK = line(SkyLight.canSwitch, "SkyLight — troca de mesa disponível") && allOK

        for display in DisplayManager.displays() {
            print("Monitor: \(display.name)")
            let originalCurrent = SkyLight.currentSpace(onDisplay: display.id)
            print("  mesas: \(SkyLight.desktopIDs(onDisplay: display.id)) · corrente: \(originalCurrent)")

            switch await SpaceManager.createAndEnterDesktop(on: display) {
            case .created(let id):
                line(true, "criar nova mesa e entrar nela (space \(id))")
                let back = await SpaceManager.switchTo(spaceID: originalCurrent, display: display)
                allOK = line(back, "voltar para a mesa original") && allOK
                let removed = await SpaceManager.removeDesktop(spaceID: id, display: display)
                allOK = line(removed, "remover a mesa de teste") && allOK
            case .createdNoSwitch(let id):
                allOK = false
                line(false, "entrar na nova mesa (space \(id) criado, mas sem alternar)")
                let removed = await SpaceManager.removeDesktop(spaceID: id, display: display)
                line(removed, "remover a mesa de teste")
            case .failed:
                allOK = false
                line(false, "criar nova mesa")
            }
        }
        print(allOK ? "Resultado: tudo OK" : "Resultado: há falhas")
        return allOK ? 0 : 1
    }
}
