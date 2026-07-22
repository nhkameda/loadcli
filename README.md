# loadcli

**Lançador de workspaces de desenvolvimento para macOS.**

Escolha um projeto e, com **um clique**, o loadcli:

1. cria uma **nova mesa** (área de trabalho do Mission Control) no monitor que você escolher;
2. abre o **Terminal** já com `cd` na pasta do projeto e o seu **CLI** rodando (ex.: `claude`);
3. abre o **navegador** na URL de deploy (ex.: `https://erp.kamedatec.com`);
4. organiza as duas janelas **lado a lado** (terminal à direita, navegador à esquerda).

Tudo é configurável por projeto — pasta, comando CLI, URL, navegador, terminal, layout e
monitor — e você pode ter **dezenas de projetos**, cada um a um clique.

<p align="center">
  <img src="Sources/loadcli/Resources/Assets.xcassets/AppIcon.appiconset/icon_256x256.png" width="128" alt="ícone do loadcli">
</p>

---

## Recursos

- 🖥️ **Nova mesa por projeto** no monitor escolhido (com seletor de monitor quando há 2+ telas).
- ⌨️ **Terminal + CLI** na pasta certa (Terminal.app ou iTerm).
- 🌐 **Navegador + URL** de deploy (Chrome, Brave, Edge, Arc, Safari).
- ↔️ **Split automático** das janelas (proporção ajustável).
- 🗂️ **Catálogo de projetos** com ícones, cores, edição, duplicação e exclusão.
- 🧭 **Menu na barra de status** para lançar qualquer projeto sem abrir a janela principal.
- ⚙️ Configurações, tela **Sobre**, ícone próprio e interface nativa SwiftUI.

## Como funciona (e por que assim)

**Criar** uma mesa via API privada (SkyLight) **não funciona** num app normal no macOS
moderno — é por isso que ferramentas como o *yabai* exigem **desligar o SIP**. O loadcli cria
a mesa pelo caminho **sem SIP**: dirige o botão “+” do **Mission Control** pela **API de
Acessibilidade**, usando os identificadores estáveis do Dock (`mc.spaces.add`) e mirando o
monitor pelo `AXDisplayID` — o mesmo caminho do `hs.spaces` do Hammerspoon. A criação é
confirmada por **diff de IDs de space** (SkyLight, leitura).

Para **entrar** na mesa nova, o clique de Acessibilidade no thumbnail é ignorado no macOS 26
(verificado empiricamente), então o loadcli usa `SLSManagedDisplaySetCurrentSpace` — troca
instantânea, sem abrir UI — **sempre verificando** o resultado e com fallback para um clique
real no Mission Control. Terminal e navegador são lançados **sem ativação** (para o macOS não
“pular” para outra mesa) e cada janela nova é **verificada e corrigida** até estar na mesa
certa. `loadcli --doctor` roda um autoteste completo desse mecanismo em cada monitor.

> Decisão de distribuição: **Developer ID** (fora da Mac App Store). A criação de mesas e o
> controle de janelas dependem de Acessibilidade/Apple Events fora do sandbox da loja.
> Veja [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md).

## Permissões (1ª execução)

O loadcli pede duas permissões padrão do macOS:

- **Acessibilidade** — criar mesas e posicionar janelas
  (Ajustes do Sistema › Privacidade e Segurança › **Acessibilidade**).
- **Automação** — controlar Terminal e navegador (o macOS pergunta no primeiro uso; clique em
  *Permitir*).

## Build & execução

Pré-requisitos: **Xcode** + Homebrew.

```bash
make bootstrap     # instala xcodegen, create-dmg, xcbeautify
make run           # gera o projeto, compila (assinatura ad-hoc) e abre o app
```

Outros alvos:

```bash
make icon          # regenera o ícone do app
make gen           # gera loadcli.xcodeproj a partir do project.yml
make build         # build Debug
make release       # build Release
```

## Distribuição (assinar + notarizar + DMG)

Requer conta **Apple Developer** paga e um certificado **Developer ID Application** instalado
(Xcode › Settings › Accounts › Manage Certificates › “+”). Credenciais via ambiente
(use `op run` — **nunca** comite segredos):

```bash
# Uma vez: guarde o perfil de notarização no Keychain
xcrun notarytool store-credentials loadcli-notary \
  --apple-id "voce@exemplo.com" --team-id "TEAMID" --password "app-specific-password"

export LOADCLI_SIGN_ID="Developer ID Application: Seu Nome (TEAMID)"
export LOADCLI_NOTARY_PROFILE="loadcli-notary"
make sign-notarize     # -> dist/loadcli-<versão>.dmg (assinado, notarizado, stapled)
```

## Roadmap

- **Windows** (app nativo .NET/WinUI 3, Virtual Desktops + Win32): [`docs/WINDOWS_ROADMAP.md`](docs/WINDOWS_ROADMAP.md).
- Login automático opcional, perfis de layout, atalhos globais por projeto.

## Estrutura

```
project.yml                 # definição do projeto (XcodeGen)
Makefile                    # gen / build / run / release / sign-notarize
scripts/                    # bootstrap, gerador de ícone, assinatura/notarização
Sources/loadcli/
  Models/                   # Project, AppSettings, Store, AppModel
  Services/                 # SpaceManager, AppLauncher, WindowPositioner, DisplayManager, SkyLight, AX
  Views/                    # SwiftUI (grid, editor, seletor de monitor, ajustes…)
  Resources/                # Info.plist, entitlements, Assets (ícone)
docs/                       # arquitetura + roadmap Windows
```

---

© 2026 KamedaTec. Todos os direitos reservados. Veja [LICENSE](LICENSE).
