# loadcli · app macOS

O app nativo em SwiftUI. Todos os comandos rodam **de dentro desta pasta**:

```bash
cd mac
make bootstrap     # instala xcodegen, xcbeautify, create-dmg
make run           # gera o projeto, compila e abre o app
```

| Alvo | O que faz |
|------|-----------|
| `make gen` | gera `loadcli.xcodeproj` a partir do `project.yml` |
| `make build` | build Debug |
| `make release` | build Release |
| `make icon` | regenera o ícone do app (`scripts/make_icon.swift`) |
| `make sign-notarize` | assina (Developer ID) + notariza + gera o DMG em `dist/` |

Os mesmos alvos existem na raiz do repositório e apenas delegam para cá, então
`make build` também funciona de `loadcli/`.

```
project.yml                 # definição do projeto (XcodeGen)
Makefile
scripts/                    # bootstrap, gerador de ícone, assinatura/notarização
Sources/loadcli/
  Models/                   # Project, ProjectDoc (LOADCLI.md), ProjectFolder,
                            # LocalPrefs, AppSettings, LegacyMigration, Store, AppModel
  Services/                 # ProjectScanner, SpaceManager, AppLauncher,
                            # WindowPositioner, DisplayManager, SkyLight, AX
  Views/                    # SwiftUI — busca + abas, grid + pastas, editores, ajustes
  Resources/                # Info.plist, entitlements, Assets (ícone)
```

Documentação geral, arquitetura e o formato do `LOADCLI.md` ficam na raiz do
repositório e em [`../docs/`](../docs/).
