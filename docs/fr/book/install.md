# Installer et lancer un premier programme

Dans ce chapitre, vous installez Cesia, vous lancez un premier programme et vous créez un projet avec ses propres tâches.

## Installer

Sur Linux et macOS, dans un terminal :

```sh
curl -fsSL https://raw.githubusercontent.com/www-celestial/cesia-lang/main/install.sh | sh
```

Sur Windows, dans PowerShell :

```powershell
irm https://raw.githubusercontent.com/www-celestial/cesia-lang/main/install.ps1 | iex
```

Le script (un petit programme qu'on lance tel quel) télécharge la release, c'est-à-dire la version publiée de Cesia, pour
votre système : Linux ou macOS sur x86-64 ou arm64, Windows sur x86-64. Il vérifie ensuite son fingerprint : un
*fingerprint* (une empreinte), ou checksum, est un nombre court calculé à partir de chaque octet d'un fichier, ici son
SHA-256, et qui change si un seul octet change. La release publie le fingerprint de chaque archive, et un téléchargement
qui ne lui correspond pas est refusé : un fichier coupé ou abîmé en route n'est donc jamais installé. Le script met la
release dans `~/.cesia`, et deux noms pour le même programme dans `~/.local/bin` : `cesia` et le nom court `ce`. Votre
`PATH` est la liste des dossiers où le shell (le programme qui lit vos commandes dans le terminal) cherche une commande ;
si `~/.local/bin` n'y est pas encore, le script le dit. `CESIA_HOME` et `CESIA_BIN` changent ces deux dossiers, et
`CESIA_RELEASES` l'endroit où se trouvent les releases, comme le dit [Variables d'environnement](env.md).

Une release contient toutes les bibliothèques C dont les bibliothèques de Cesia ont besoin : rien d'autre ne s'installe à
la main. Vérifiez que tout marche :

```sh
cesia version
```

La commande affiche la version, par exemple `cesia 1.1.0`. Plus tard, `cesia upgrade` montre les notes de la dernière
release et demande votre accord avant de l'installer ; elle vérifie de la même façon le fingerprint BLAKE2b de ce
qu'elle télécharge.

## Un premier programme

Un programme est un fichier texte dont le nom finit par `.ce`. Créez un fichier `hello.ce` qui contient :

```cesia
use std/io
io.Print("Hello, world!")
```

Lancez-le :

```sh
cesia run hello.ce
```

[io.Print] écrit ses arguments sur une ligne, séparés par un espace, avec une fin de ligne après le dernier. Cette
fonction prend n'importe quelle valeur, pas seulement des textes :

```cesia
io.Print("Two and two make", 2 + 2)
io.Print([1, 2, 3])
```

Un programme s'exécute de sa première ligne à sa dernière. Il n'y a pas de `main` à écrire : les lignes écrites au
premier niveau du fichier sont le programme.

## Le relancer à chaque enregistrement

`--watch` garde le programme en marche et charge vos changements chaque fois que vous enregistrez le fichier : c'est un
[hot reload](glossary.md#hot-reload), où le nouveau code remplace l'ancien dans le programme qui tourne, et ce programme
garde ses valeurs. Un changement tourne moins de 100 ms après l'enregistrement :

```sh
cesia run --watch hello.ce
```

Un programme qui s'est terminé repart quand le fichier change. Un programme qui tourne encore, comme un serveur ou une
fenêtre, garde son état et prend tout de suite le nouveau code. Appuyez sur `Ctrl-C` pour arrêter.

### Essayer une ligne

`cesia run --repl` ouvre un prompt (une ligne où vous tapez du code), une [REPL](glossary.md#repl), pour *read, eval,
print loop* (lire, évaluer, afficher, et recommencer) : tapez une expression, et il montre sa valeur. C'est commode pour
essayer une fonction avant de l'écrire dans un fichier. Ctrl-D en sort.

```text
$ cesia run --repl
> use std/text
> text.Upper("hello")
HELLO
```

Le chapitre [Le prompt et le debugger](debug.md) en montre davantage.

## Quand quelque chose ne va pas

Une erreur nomme le fichier, la ligne et la colonne, et montre la ligne. Cesia vérifie chaque nom d'un programme avant
d'en exécuter la première ligne : une faute de frappe l'arrête donc avant que rien ne se passe. Ici, la première ligne
n'affiche jamais son texte.

```cesia fails
io.Print("This line never runs")
Pritn("Hello")
```

### Les fautes qui apparaissent quand leur ligne s'exécute

D'autres fautes n'apparaissent que quand leur ligne s'exécute. Ici, un texte et un nombre sont additionnés, et le message
dit quoi écrire à la place :

```cesia fails
io.Print("Total: " + 3)
```

## Un projet

Un fichier suffit pour un script. Pour davantage, créez un projet :

```sh
cesia new hello
cd hello
cesia do run
```

`cesia new` crée un dossier qui contient :

- `cesia.toml`, qui nomme le projet et ses tâches ;
- `src/main.ce`, le programme, qui affiche `Hello from hello` ;
- `std/`, une copie des bibliothèques de Cesia, et `cesia.lock`, un [lock file](glossary.md#lock-file) qui garde le
  fingerprint de chacun de leurs fichiers, son BLAKE2b-256 : un fichier changé à la main, ou une copie différente sur une
  autre machine, se voit donc ;
- `.gitignore`, qui laisse `std/` et `deps/` hors de git : `cesia pkg install` les recrée après un clone (une copie du
  dépôt git).

### Son cesia.toml

Le `cesia.toml` d'un nouveau projet :

```toml
[project]
name = "hello"
cesia = "1.0"

[tasks.run]
file = "src/main.ce"
```

`cesia = "1.0"` est la plus ancienne version de Cesia dont le projet a besoin. Une version plus ancienne s'arrête tout de
suite, et dit de lancer `cesia upgrade`.

## Tâches

Une tâche nomme un programme à lancer et ce qu'il a le droit de toucher. `cesia do` liste les tâches, et `cesia do run`
lance la tâche `run`, en montrant d'abord la commande exacte :

```sh
$ cesia do run
> cesia run src/main.ce
Hello from hello
```

Vous n'avez donc jamais à retenir une longue commande : écrivez-la une fois dans `cesia.toml`, et `cesia do` la lance.
Les packages (du code groupé sous un nom) et les tâches ont plus loin un chapitre à eux.

## Éditeurs

N'importe quel éditeur convient, puisqu'un programme est un fichier texte. Les sources de Cesia contiennent un mode pour
Emacs et un autre pour Neovim et Vim, dans `tools/editors/`, qui colorent le code. Gardez un terminal à côté de votre
éditeur avec `cesia run --watch` : chaque enregistrement montre aussitôt son résultat. Un éditeur qui parle le Language
Server Protocol (le protocole par lequel un éditeur demande à un programme les erreurs et la documentation d'un fichier)
montre aussi les erreurs d'un fichier dans ses lignes pendant que vous tapez, et la documentation du nom sous le curseur,
grâce à [cesia lsp](commands.md#cesia-lsp) : [Éditeurs](editors.md) donne les quelques lignes dont chacun a besoin.

## La suite

Vous savez lancer un programme. Le chapitre suivant, [Valeurs et noms](values.md), montre avec quoi un programme
travaille : les nombres, les textes, true et false, et les noms qui les gardent.
