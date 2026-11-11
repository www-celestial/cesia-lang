# Cesia

Un petit langage pour résoudre directement de vrais problèmes : un script qui nettoie un CSV, un serveur web sur une base de
données, un programme qui pilote d'autres programmes. Il démarre tout de suite, il est sûr par défaut, et quand quelque chose
ne va pas, il dit quoi écrire.

```cesia
use std/http

app = http.App() then http.Get("/hello/:name", r -> http.Plain("Hello, $(r.Params.name)!"))
http.Serve(app, port = 8080)
```

## Installer

```bash
curl -fsSL https://raw.githubusercontent.com/www-celestial/cesia-lang/main/install.sh | sh    # Linux and macOS
irm https://raw.githubusercontent.com/www-celestial/cesia-lang/main/install.ps1 | iex         # Windows, in PowerShell
cesia upgrade              # later: the newest release, after its notes and a question
cesia upgrade --nightly    # a build of main between releases, made by hand
```

Une release (une version publiée) contient le binaire et toutes les bibliothèques C dont ses bibliothèques ont besoin, dans
`~/.cesia/lib/` : OpenBLAS pour BLAS et LAPACK (macOS a les siennes), libsodium, SQLite, et OpenSSL sur macOS et Windows
(Linux garde celle du système, pour ses correctifs de sécurité). Rien d'autre ne s'installe à la main. Depuis la 1.0, le
premier nombre d'une version monte quand un changement peut casser un programme, celui du milieu quand quelque chose est
ajouté, et le dernier pour une correction. [`CHANGELOG.md`](https://github.com/www-celestial/cesia-lang/blob/main/CHANGELOG.md) dit ce qu'apporte chaque version, et les notes
d'une release viennent des messages de ses commits.

Depuis les sources, avec OCaml 5.5 et dune :

```bash
dune build --profile release
ln -s "$PWD/_build/default/src/bin/main.exe" ~/.local/bin/cesia
ln -s "$PWD/_build/default/src/bin/main.exe" ~/.local/bin/ce      # optional: the short name of the same binary
```

Un tel binaire affiche `cesia 1.1.0+dev` : ce sont `git pull` et `dune build` qui le mettent à jour, pas `cesia upgrade`.
`ce` et `cesia` sont un seul programme, comme `vi` et `vim` : `ce run file.ce` est `cesia run file.ce`.

## Lire le livre

Le livre enseigne Cesia depuis le début, en 23 chapitres courts, et la référence a une page pour chaque nom, chacune avec
des exemples qui ont tourné quand le site a été construit : **https://www-celestial.github.io/cesia-lang/**. Il suit
`main`, et chaque push le publie à nouveau.

Les chapitres sont du Markdown simple, dans [`docs/fr/book/`](docs/fr/book/index.md). Depuis un clone, `cesia doc --site --open`
construit le même site dans `site/` et l'ouvre, et `cesia doc list.Sort` ou `cesia doc num.Solve` affiche une page dans le
terminal.

## Vérifier sans exécuter

`cesia check` lit les dossiers de sources d'un projet et dit ce qui ne va pas, sans en exécuter une ligne : des noms qui
n'existent pas, des appels avec les mauvais arguments, des valeurs qui ne peuvent pas tenir dans un type, et des résultats
dont l'`Err` passerait inaperçu. Il n'a besoin que de la permission de lecture. `cesia check --json --stdin file.ce` prend
sur l'entrée un buffer (le texte ouvert dans l'éditeur) pas encore enregistré, et écrit un objet par ligne, pour qu'un
éditeur montre chaque erreur sur sa ligne.

## Éditeurs

`cesia lsp` est un language server (un programme qui donne à un éditeur ce qu'il sait du code) : un éditeur qui parle le
Language Server Protocol montre les erreurs de `cesia check` pendant la frappe, la documentation sous le curseur, la
définition d'un nom et les noms qui suivent le point d'un package.

Neovim et Vim : copiez `tools/editors/nvim/` dans `~/.config/nvim/` ; depuis Neovim 0.11, `vim.lsp.enable('cesia')` dans
`init.lua` démarre le serveur.

Emacs : ajoutez `(load "/path/to/cesia/tools/editors/cesia-mode.el")` à votre `init.el` ; `M-x eglot` démarre le serveur.

Helix, et pourquoi pas encore Zed et VS Code : [Éditeurs](docs/fr/book/editors.md).

## Limites

- Les arrays ont deux dimensions au plus.
- Linux sur x86-64 est la plateforme vérifiée. `.github/workflows/ci.yml` lance aussi les tests sur macOS, et ne fait que
  construire sur Windows.

## Licence

Cesia est sous licence MIT : voir `LICENSE`.
