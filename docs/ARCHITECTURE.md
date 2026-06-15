# Arquitetura — loadcli (macOS)

## Visão geral
App nativo **SwiftUI** (macOS 14+), distribuído como **Developer ID** (fora da Mac App Store).
Sem App Sandbox; Hardened Runtime ligado; entitlement de Apple Events.

## Fluxo de lançamento (`LaunchFlow.run`)
1. **Verifica Acessibilidade** (`AXIsProcessTrusted`). Sem ela, aborta com instrução.
2. **Nova mesa** (se `workspaceMode == .newDesktop`) → `SpaceManager.createAndEnterDesktop`.
3. **Terminal + CLI** → `AppLauncher.openTerminal` (Apple Events: `do script` com `cd … && <cli>`).
4. **Navegador + URL** → `AppLauncher.openBrowser` (nova janela + URL).
5. **Posiciona janelas** → `WindowPositioner` via Acessibilidade (`kAXPosition`/`kAXSize`).

## Criação de mesas — a decisão central
Criar um Space **usável** com a API privada do SkyLight (`SLSSpaceCreate`) **não funciona de
forma confiável** num processo normal: o espaço criado não se vincula a um display (verificado
empiricamente — a contagem de spaces por display não muda). É por isso que o *yabai* injeta um
*scripting addition* no Dock e exige **SIP parcialmente desligado** — inaceitável para um
produto vendável.

**Solução:** dirigir o **Mission Control** pela Acessibilidade.
- `SpaceManager.openMissionControl()` abre `/System/Applications/Mission Control.app`.
- O processo **Dock** expõe, por display, um grupo “Barra do Spaces” com botões de mesa e um
  botão **“+”**. O “+” é detectado de forma **independente de idioma**: é o botão da barra com
  **título vazio** (botões de mesa sempre têm título).
- O **monitor alvo** é escolhido pela **posição** do botão “+” (`AX.position` → display).
- Após o clique, a nova mesa é identificada por **diferença de títulos** e clicada para
  **alternar** (clicar uma mesa no Mission Control troca e fecha o overview).
- `SkyLight` (somente leitura, `SLSCopyManagedDisplaySpaces`) **confirma** que a contagem de
  mesas do display alvo aumentou.
- Fallback gracioso: se falhar, segue na mesa atual e avisa o usuário.

## Coordenadas
- `NSScreen` usa origem inferior-esquerda; Acessibilidade/CG usam superior-esquerda.
- `DisplayManager.cocoaToCG` faz o flip usando a altura da tela primária (origem zero).
- `WindowPositioner.halfRects` calcula as metades a partir de `visibleFrame` (exclui Dock/menu).

## Permissões
- **Acessibilidade**: ler a árvore AX do Dock, pressionar botões, posicionar janelas, postar
  `Esc` (CGEvent). Concedida pelo usuário; persistente quando o app é assinado de forma estável.
- **Automação (Apple Events)**: controlar Terminal e navegador. Pedida no 1º uso.

## Camadas
- **Models**: `Project`, `AppSettings`, `Store` (JSON em Application Support), `AppModel` (estado/UI).
- **Services**: `SpaceManager`, `AppLauncher`, `WindowPositioner`, `DisplayManager`,
  `SkyLight` (read-only), `AX` (wrappers), `Permissions`, `LaunchFlow`.
- **Views**: grid de cards, editor, seletor de monitor, ajustes, overlay de progresso, menu de status.

## Portabilidade
A lógica de janelas/mesas é específica de SO. O que é portável é o **schema `projects.json`** —
reaproveitado pelo port Windows (ver `WINDOWS_ROADMAP.md`).
