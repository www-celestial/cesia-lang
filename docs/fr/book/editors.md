# Éditeurs

N'importe quel éditeur convient, puisqu'un programme est un fichier texte. Un éditeur qui parle le
[Language Server Protocol](https://microsoft.github.io/language-server-protocol/) (le protocole par lequel un éditeur
demande à un programme les erreurs et la documentation d'un fichier) en fait plus avec
[cesia lsp](commands.md#cesia-lsp), un language server (le programme qui répond à ces demandes) qui vient dans le binaire :

- ce que trouve [cesia check](commands.md#cesia-check), sous le code, pendant que vous tapez : un nom qui n'existe pas, un
  appel avec de mauvais arguments, un résultat laissé sans traitement ;
- la documentation du nom sous le curseur, `list.Map` ou une fonction à vous ;
- l'endroit où un nom est défini, dans votre projet ;
- les noms d'un package après son point : `list.` liste `Map`, `Filter` et les autres.

L'éditeur lance `cesia lsp` dans le dossier du projet, celui qui contient `cesia.toml`, et lui parle sur son entrée et
sa sortie. Le serveur lit les fichiers et n'en écrit jamais un. Ci-dessous, les quelques lignes de configuration de
chaque éditeur.

## Ce que parle le serveur

Le protocole est LSP 3.17 : des messages en JSON, chacun après un en-tête `Content-Length`. `cesia lsp` répond à
`initialize`, `shutdown` et `exit` ; il prend le texte entier d'un fichier à chaque changement, `textDocument/didOpen`,
`didChange`, `didSave` et `didClose`, et vérifie les fichiers qui ont changé une fois que l'éditeur est resté calme
pendant 50 ms, si bien que la frappe ne vérifie qu'une fois, puis il envoie `textDocument/publishDiagnostics`, les
marques sous le code. Il répond à `textDocument/hover` par la documentation d'un nom, à `textDocument/definition` par
son endroit, et à `textDocument/completion`, après un `.`, par les noms d'un package. Les positions comptent des code
units UTF-16 (les unités de 16 bits du codage UTF-16), comme le fait le protocole, si bien qu'une ligne avec un emoji est
marquée au bon endroit.

## Neovim

Les sources de Cesia contiennent `tools/editors/nvim/` : copiez-le dans `~/.config/nvim/`. Il donne à Neovim le type de
fichier, les couleurs, et `lsp/cesia.lua`, la configuration du serveur. Ensuite, une ligne dans `init.lua` lance le
serveur sur chaque fichier `.ce`, à partir de Neovim 0.11 :

```lua
vim.lsp.enable('cesia')
```

Sans la copie, la même chose dans `init.lua` :

```lua
vim.filetype.add({ extension = { ce = 'cesia' } })
vim.lsp.config('cesia', { cmd = { 'cesia', 'lsp' }, filetypes = { 'cesia' }, root_markers = { 'cesia.toml', '.git' } })
vim.lsp.enable('cesia')
```

`K` montre la documentation sous le curseur, `Ctrl-]` va à une définition, et `Ctrl-X Ctrl-O` complète après un point.

## Helix

Dans `~/.config/helix/languages.toml` :

```text
[language-server.cesia]
command = "cesia"
args = ["lsp"]

[[language]]
name = "cesia"
scope = "source.cesia"
file-types = ["ce"]
roots = ["cesia.toml"]
block-comment-tokens = { start = "(*", end = "*)" }
indent = { tab-width = 2, unit = "  " }
language-servers = ["cesia"]
```

Helix n'a pas de grammaire de Cesia, donc il ne colore pas le code ; les erreurs, `Space k` pour la documentation et
`g d` pour une définition marchent.

## Emacs

`tools/editors/cesia-mode.el` est le mode de Cesia : ajoutez `(load "/path/to/cesia/tools/editors/cesia-mode.el")` à
`init.el`. Il dit à Eglot, le client LSP qui vient avec Emacs, comment lancer le serveur : `M-x eglot` dans un fichier
`.ce` le lance.

## Zed et VS Code

Les deux ne lancent un language server que par une extension à eux, et Cesia n'en a pas encore. Celle de Zed demande
aussi une grammaire de Cesia, qui n'existe pas. En attendant, servez-vous de l'un des éditeurs ci-dessus.
