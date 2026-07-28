# O formato `LOADCLI.md`

Cada pasta de projeto carrega um `LOADCLI.md`, e **esse arquivo é o card**. Não
existe banco de dados de projetos: o app varre as pastas-raiz cadastradas em
Ajustes, encontra esses documentos e monta a grade a partir do que está escrito
neles.

Implementação de referência: [`mac/Sources/loadcli/Models/ProjectDoc.swift`](../mac/Sources/loadcli/Models/ProjectDoc.swift).
O port Windows lê exatamente o mesmo formato — ver [`windows/ROADMAP.md`](../windows/ROADMAP.md).

## Estrutura

Front matter de linhas `chave: valor` entre marcadores `---`, seguido de markdown
livre que vira a **descrição** do card.

```markdown
---
loadcli: 1
id: 6C0F2A18-3D4B-4E71-9A02-1F5C8B3E77D9
nome: Acme Site
grupo: Clientes
icone: cart.fill
cor: "#3B82F6"
repositorio: https://github.com/voce/acme
url: https://app.acme.com
cli: claude
modelo: opus
esforco: xhigh
painel: browser
---

Loja da Acme. Deploy pela Vercel, banco no Neon.
```

## As três invariantes

1. **Nenhum caminho absoluto é gravado.** A pasta do projeto é, por definição, o
   diretório onde o arquivo está. É isso que faz a mesma pasta funcionar em
   qualquer Mac, com qualquer nome de usuário, quando ela é sincronizada.
2. **O que é da máquina não entra aqui.** Monitor escolhido e histórico de
   recentes ficam em `~/Library/Application Support/loadcli/local.json`. Se
   fossem gravados no documento, todo lançamento reescreveria o arquivo e o
   Drive produziria cópias de conflito.
3. **O que o app não conhece, ele preserva.** Chaves desconhecidas e o corpo em
   markdown sobrevivem a qualquer regravação.

## Chaves

| Chave | Valores | Padrão | O que faz |
|---|---|---|---|
| `loadcli` | inteiro | `1` | versão do formato |
| `id` | UUID | derivado do caminho | identidade do card; amarra monitor e recentes |
| `nome` | texto | nome da pasta | título do card |
| `grupo` | texto | — | pasta (grupo) na tela principal; ausente = sem pasta |
| `icone` | SF Symbol | `terminal.fill` | ícone do card |
| `cor` | hex | `#7C5CFF` | cor do card. **Sempre entre aspas** — `#` inicia comentário |
| `repositorio` | URL ou `git@…` | lido do `.git/config` | botão do repositório |
| `url` | URL | — | site do projeto; também o que o painel navegador abre |
| `navegador` | bundle id ou nome | `com.google.Chrome` | Chrome, Safari, Brave, Edge, Arc |
| `terminal` | nome | `Terminal` | Terminal, iTerm, Warp |
| `cli` | `claude` · `codex` · `custom` | `claude` | qual CLI roda no terminal |
| `comando` | texto | — | só com `cli: custom`; o comando literal |
| `modelo` | texto | — | modelo do CLI escolhido |
| `esforco` | texto | — | *effort* do CLI escolhido |
| `painel` | `none` · `browser` · `finder` | `none` | o que abre ao lado do terminal |
| `pastaFinder` | caminho **relativo** | pasta do projeto | com `painel: finder` |
| `mesa` | `newDesktop` · `splitCurrent` | `newDesktop` | criar mesa nova ou usar a atual |
| `lado` | `terminalRight` · `terminalLeft` | `terminalRight` | de que lado fica o terminal |
| `divisao` | 0,3 a 0,7 | `0.50` | fração reservada ao painel da esquerda |
| `telaCheia` | `sim` · `nao` | `nao` | só-terminal em tela cheia nativa |

**Catálogos.** `cli: claude` aceita `modelo` em `fable`, `opus`, `sonnet`,
`haiku` e `esforco` em `low`, `medium`, `high`, `xhigh`, `max`, `ultracode`.
`cli: codex` aceita `modelo` em `gpt-5.6-sol`, `gpt-5.5` e `esforco` em
`minimal`, `low`, `medium`, `high`. Vazio significa "padrão do CLI" — nenhuma
flag é passada.

## Tolerância na leitura

- **Acentos e maiúsculas não importam:** `esforco`, `esforço` e `Effort` são a
  mesma chave.
- **Inglês também vale:** `name`, `group`, `icon`, `color`/`colour`,
  `repository`/`repo`/`git`, `site`/`website`, `browser`, `tool`, `command`,
  `model`, `effort`, `pane`, `finder`, `workspace`/`desktop`, `side`,
  `ratio`/`split`, `fullscreen`.
- **Booleanos:** `sim`/`nao`, `yes`/`no`, `true`/`false`, `1`/`0`, `on`/`off`.
- **Sem front matter?** O arquivo inteiro vira a descrição e o nome cai para o
  nome da pasta.
- **Sem `id`?** O app deriva um UUID determinístico do nome da pasta e do pai
  (SHA-256, versão 5), então o mesmo projeto mantém a identidade em todas as
  máquinas mesmo escrito à mão. Ao salvar pelo editor, o `id` passa a ser gravado.

## Como o app varre

Poda agressiva, porque quem tem `~/DEV` tem também dezenas de `node_modules`:

- pasta com `LOADCLI.md` **é** um projeto, e a varredura **não desce** nela;
- ignora `.git`, `node_modules`, `Pods`, `build`, `.build`, `DerivedData`,
  `dist`, `vendor`, `target`, `venv`, `__pycache__`, `.next`, `.cache`,
  `Library` e afins, além de tudo que começa com ponto;
- não segue links simbólicos (evita ciclos);
- profundidade máxima configurável (padrão 6);
- documento com `mtime` inalterado é reaproveitado do cache, sem reler o disco;
- raiz ilegível (um Drive que ainda não sincronizou) **mantém** os cards do
  cache em vez de esvaziar a grade.

Todo caminho indexado passa por uma forma canônica única (til expandido,
symlinks resolvidos, sem barra final). Sem isso o cache por `mtime` nunca acerta:
o `FileManager` devolve caminhos resolvidos ao enumerar (`/var` vira
`/private/var`) enquanto `URL.resolvingSymlinksInPath()` remove o `/private`.

## Excluir

Excluir um card manda o `LOADCLI.md` para o **Lixo**. A pasta do projeto e tudo
dentro dela nunca são tocados.
