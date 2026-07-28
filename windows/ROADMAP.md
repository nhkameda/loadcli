# Roadmap — versão Windows do loadcli

Objetivo: app **nativo Windows** com a mesma experiência (um clique → nova área de trabalho
virtual no monitor escolhido, terminal com CLI + navegador na URL, lado a lado).

## Stack
- **.NET 8 + WinUI 3** (C#), empacotado como **MSIX** assinado. (Opcional: Microsoft Store.)
- UI espelhando a do macOS (grid de projetos, editor, seletor de monitor, ajustes).

## Mapeamento de capacidades

| Capacidade            | macOS (atual)                                  | Windows (planejado)                                            |
|-----------------------|------------------------------------------------|---------------------------------------------------------------|
| Nova “mesa”           | Mission Control via Acessibilidade             | **Virtual Desktops**: `IVirtualDesktopManager` (público) + lib da comunidade (`VirtualDesktop`) para **criar/alternar** |
| Abrir terminal + CLI  | AppleScript no Terminal/iTerm                  | `wt.exe -d "<pasta>" <cli>` (Windows Terminal) ou `cmd /k`     |
| Abrir navegador + URL | AppleScript (Chrome/Safari…)                   | `chrome.exe --new-window <url>` / protocolo padrão            |
| Posicionar janelas    | Acessibilidade (`kAXPosition/Size`)            | Win32 `SetWindowPos` / `MoveWindow`                           |
| Multi-monitor         | `NSScreen` + UUID                              | `EnumDisplayMonitors` / `GetMonitorInfo`                      |
| Achar a janela aberta | AX (`AXWindows`/`AXFocusedWindow`)            | `EnumWindows` + PID + `GetWindowThreadProcessId`             |

## Notas
- No Windows, **criar/alternar áreas virtuais é API mais acessível** que no macOS (sem
  equivalente ao “SIP”): a `VirtualDesktop` (wrapper de COM não documentado) é estável e amplamente usada.
- O **`projects.json`** é idêntico — mesma estrutura `Project` (pasta, CLI, URL, navegador,
  terminal, modo, layout, monitor). Basta reimplementar a camada de serviços.
- Assinatura: certificado de **Authenticode**; distribuição via MSIX/instalador próprio.

## Fases sugeridas
1. UI + persistência (`projects.json`) — paridade visual.
2. Launchers (terminal/navegador) + posicionamento Win32.
3. Áreas de trabalho virtuais (criar/alternar) + seletor de monitor.
4. Empacotamento MSIX assinado + auto-update.
