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

## Criação e troca de mesas — a decisão central (validada no macOS 26.3)

**Criar** um Space usável com a API privada do SkyLight (`SLSSpaceCreate`) **não funciona**
num processo normal: o espaço criado não se vincula a um display (verificado empiricamente).
É por isso que o *yabai* injeta um *scripting addition* no Dock e exige **SIP parcialmente
desligado** — inaceitável para um produto vendável.

**Criação — Mission Control via Acessibilidade** (mesmo caminho do `hs.spaces` do Hammerspoon):
- O Mission Control é aberto/fechado com `CoreDockSendNotification("com.apple.expose.awake")`
  (toggle; fallback: abrir `Mission Control.app` / tecla Esc).
- Com o MC aberto, o processo **Dock** expõe uma árvore com **AXIdentifiers estáveis**:
  `mc` → `mc.display` (um por monitor, com atributo **`AXDisplayID`** = CGDirectDisplayID)
  → `mc.spaces` → `mc.spaces.add` (botão “+”) e `mc.spaces.list` (mesas, na ordem do SkyLight).
- O monitor alvo é casado por `AXDisplayID` (fallback: origem CG do grupo `mc.display`).
- `AXPress` no `mc.spaces.add` cria a mesa. A criação é confirmada por **diff de space-IDs**
  (`SLSCopyManagedDisplaySpaces`) — nunca por contagem nem por nomes (que se repetem entre
  displays e se reordenam com o `mru-spaces`).
- É preciso um **settle (~350 ms)** após o MC abrir antes de pressionar qualquer botão — presses
  cedo demais retornam sucesso sem efeito (fragilidade conhecida, Hammerspoon `MCwaitTime`).

**Troca — clique real no thumbnail (dirigido pelo Dock), sempre verificada:**
- No macOS 26, `AXPress` no thumbnail de uma mesa **retorna sucesso, fecha o MC e NÃO troca**
  (verificado empiricamente em 26.3 — era o bug raiz do loadcli).
- A chamada privada `SLSManagedDisplaySetCurrentSpace` troca o estado no WindowServer, mas o
  **Dock não executa a transição**: o compositor fica com as **duas mesas (e duas barras de
  menu) sobrepostas** até a próxima transição real, e uma interação posterior com o Mission
  Control pode até **voltar** para a mesa que o Dock achava corrente (dessincronia — o mesmo
  motivo pelo qual o yabai injeta código no Dock para atualizar `_currentSpace`).
- Por isso o lançamento troca com um **clique sintético real** no thumbnail da mesa nova, com o
  MC ainda aberto da criação: o cursor paira no topo do display para **expandir a barra** (só
  então os thumbnails têm coordenadas reais na tela), clica no centro do botão e restaura o
  cursor. O Dock faz a transição completa — sem artefato — e o **foco de teclado vai para o
  display alvo**. Verificada com `SLSManagedDisplayGetCurrentSpace`.
- `SLSManagedDisplaySetCurrentSpace` fica como **fallback** e para caminhos programáticos
  (ex.: restauração no doctor), sempre verificado.
- Fallback final gracioso: segue na mesa atual e avisa o usuário.
- Ao final do lançamento, o **foco fica no terminal novo** (`AXRaise` + `kAXMain` + ativação do
  app) — seguro nesse momento porque a janela está na mesa corrente (auto-swoosh não dispara).

**Janelas na mesa nova — verificação por space-ID:**
- Terminal/navegador são lançados **sem `activate`** (com `AppleSpacesSwitchOnActivate` — o
  padrão — ativar um app pula para o Space das janelas existentes dele).
- Cold start do Terminal: `do script` com o app fechado abriria **duas** janelas; o loadcli
  lança o app em background (`NSWorkspace`, `activates=false`), espera a janela inicial e roda
  `do script … in window 1`. iTerm análogo.
- A janela nova é identificada por **diff de `CGWindowID`** (`_AXUIElementGetWindow`), pois sem
  ativação ela não é a frontmost. Apps abrem a janela onde estava a última — possivelmente em
  **outro display** —, então `WindowPositioner.placeVerified` move a janela para o retângulo do
  display alvo (o que a re-associa ao Space corrente daquele display, a mesa nova) e **confirma**
  com `SLSCopySpacesForWindows`, com retries.
- `SLSMoveWindowsToManagedSpace` está quebrado desde o macOS 14.5 (no-op silencioso) — não é usado.

**Autoteste:** `loadcli.app/Contents/MacOS/loadcli --doctor` roda um ciclo criar → entrar →
voltar → remover em cada monitor e imprime PASS/FALHA por etapa — útil após updates do macOS.

## Coordenadas
- `NSScreen` usa origem inferior-esquerda; Acessibilidade/CG usam superior-esquerda.
- `DisplayManager.cocoaToCG` faz o flip usando a altura da tela primária (origem zero).
- `WindowPositioner.halfRects` calcula as metades a partir de `visibleFrame` (exclui Dock/menu).

## Permissões
- **Acessibilidade**: ler a árvore AX do Dock, pressionar botões, posicionar janelas, postar
  `Esc` (CGEvent). Concedida pelo usuário; persistente quando o app é assinado de forma estável.
- **Automação (Apple Events)**: controlar Terminal e navegador. Pedida no 1º uso.

## Camadas
- **Models**: `Project`, `ProjectDoc` (parser/serializador do `LOADCLI.md`), `ProjectFolder`
  (estilo do grupo, por nome), `LocalPrefs` (monitor + recentes, por máquina), `AppSettings`,
  `LegacyMigration`, `Store` (índice + cache), `AppModel` (estado/UI).
- **Services**: `ProjectScanner`, `SpaceManager`, `AppLauncher`, `WindowPositioner`, `DisplayManager`,
  `SkyLight` (leitura + troca de mesa), `AX` (wrappers), `Permissions`, `LaunchFlow`, `Doctor`.
- **Views**: busca + abas (Projetos/Recentes), grid de cards, editores, ajustes,
  overlay de progresso, menu de status.

## Origem dos projetos
A fonte da verdade de um projeto é o **`LOADCLI.md` dentro da própria pasta dele** — nunca um banco
central. O `Store` varre as raízes configuradas (`ProjectScanner`, fora do MainActor), podando em
qualquer pasta que já tenha um documento e reaproveitando entradas cujo `mtime` não mudou.

Três invariantes sustentam a portabilidade entre máquinas sincronizadas:
1. **Nenhum caminho absoluto é gravado.** A pasta do projeto é onde o documento está.
2. **O que é da máquina fica na máquina** (`local.json`): monitor escolhido e histórico de recentes —
   assim o documento não é reescrito a cada lançamento, o que geraria cópias de conflito no Drive.
3. **Todo caminho indexado passa por `AppSettings.canonical(_:)`.** O `FileManager` devolve caminhos
   resolvidos ao enumerar (`/var` → `/private/var`) enquanto `URL.resolvingSymlinksInPath()` remove o
   `/private`; sem uma forma canônica única o cache por `mtime` nunca acerta.

Em `Application Support` ficam só derivados: `index.json` (cache da varredura), `folders.json`
(estilo dos grupos), `settings.json` e `local.json`.

## Portabilidade
A lógica de janelas/mesas é específica de SO. O que é portável é o **formato `LOADCLI.md`** —
lido tal e qual pelo port Windows (ver `WINDOWS_ROADMAP.md`).
