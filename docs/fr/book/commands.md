# Commandes

Chaque commande de `cesia`, et chaque option. `cesia` seul affiche la forme courte de cette page.

## Les exit codes

L'*exit code* d'une commande est le nombre qu'elle rend au shell (le programme qui lit vos commandes dans le terminal)
ou au programme qui l'a lancée : `$?` dans un shell.

| Code | Quand |
|---|---|
| `0` | tout s'est bien passé |
| `1` | une erreur a arrêté le programme : une erreur de syntaxe, une panic (l'arrêt net du programme sur un bug), une permission refusée, une limite atteinte ; ou un test a échoué, ou `cesia check` a trouvé une erreur |
| `2` | la ligne de commande est fausse : une option inconnue, une mauvaise valeur de `--limit` ou de `--workers`, un fichier qui ne peut pas être lu |
| `3` | une erreur interne de Cesia lui-même, un bug à signaler |
| `128 + N` | un deuxième signal d'arrêt (l'avis que le système envoie à un programme pour l'arrêter) a fini le programme aussitôt : 130 pour INT, 143 pour TERM |
| tout autre | le code qu'un programme a donné à [sys.Exit] |

## cesia run

```bash
cesia run [--allow LIST] [--limit LIST] [--watch] [--workers N] [--debugger FILE] [--repl] [--no-spec] [--no-jit] [--seed N] file.ce [args...]
```

Lance un programme. Les mots après le fichier sont ses arguments, dans [sys.Args].

| Option | Ce qu'elle fait |
|---|---|
| `--allow LIST` | les permissions, séparées par des virgules : `read`, `write`, `net`, `exec`, `env`, `ffi`, `debug`, `all`, chacune avec `=` et une portée (ce qu'elle couvre) si besoin. Voir [Permissions](permissions.md). |
| `--limit LIST` | les limites : `memory=512M`, `steps=N`, `depth=N`, `nesting=N`. Voir [Permissions](permissions.md). |
| `--watch` | recharge le code à chaque enregistrement de l'un de ses fichiers, sans arrêter le programme : un changement agit en moins de 100 ms. Un programme qui a fini repart au changement suivant |
| `--workers N` | sert sur N processus, de 1 à 1 024, ou un par cœur logique avec `cores`, sous un supervisor (le processus qui démarre les workers) qui redémarre un worker qui finit et les remplace tous sur HUP. Voir [Tous les cœurs](http.md#tous-les-cœurs) et [Comment Cesia fonctionne](internals.md#sur-chaque-cœur). Pas avec `--watch`, et pas sous Windows. |
| `--debugger FILE` | lance un debugger (un programme qui exécute le vôtre et peut l'arrêter, pour montrer ses variables) écrit en Cesia à côté du programme, et lui donne de lui-même la permission `debug` : pas besoin de `--allow debug`. `--debugger debugger` est celui qui vient avec Cesia. Voir [Le prompt et le debugger](debug.md). |
| `--repl` | ouvre un prompt (une ligne où vous tapez du code, et qui y répond) à côté du programme, dans le package de son fichier principal : une expression montre sa valeur, une fonction définie de nouveau remplace celle du programme. Sans fichier, un prompt sur un programme vide. Voir [Le prompt et le debugger](debug.md). |
| `--no-spec` | lance sans les versions de chaque fonction que Cesia fabrique pour les types qu'il voit : les résultats doivent être les mêmes |
| `--no-jit` | lance sans code natif, dans l'[interpréteur](glossary.md#interpreter-and-jit) seulement |
| `--seed N` | donne à [std/random] le seed N (le nombre dont part le générateur de nombres au hasard), un nombre entier, à la place d'un seed tiré du système : le même seed donne les mêmes nombres. [random.Seed] dit le seed d'un run. |

`cesia run .` lance tous les fichiers du dossier courant comme un seul programme. `cesia run --repl` sans fichier ouvre
le prompt sur un programme vide. Sans `--limit memory`, la limite est de 80 % de la mémoire de la machine.

## cesia test

```bash
cesia test [path | file.ce:isName] [--seed N] [--cases N] [--update] [--allow LIST] [--no-spec]
```

Lance les exemples de la documentation et les fonctions de test du projet, ou d'un dossier ou d'un fichier, ou une seule
fonction de test d'un fichier. Finit avec le code 1 quand un test échoue. Voir [Tests](tests.md).

| Option | Ce qu'elle fait |
|---|---|
| `--seed N` | de nouveau les cas de [test.ForAll] d'un run précédent : le résumé d'un run qui a essayé des propriétés donne son seed |
| `--cases N` | combien de cas essaie chaque [test.ForAll], 100 par défaut |
| `--update` | accepte les [test.Snapshot] nouveaux ou modifiés des tests qui tournent |
| `--allow LIST` | plus de permissions pour les tests, comme pour `cesia run`, au-delà de celles qu'un test a par défaut |
| `--no-spec` | lance sans les versions de chaque fonction par type, comme `cesia run --no-spec` |

Un projet est testé par unités côte à côte : chaque package avec ses fichiers de test, et chaque fichier qui tient seul,
comme ceux d'un dossier `tests/`. Chaque unité tourne dans un `cesia test` à elle, autant à la fois que la machine a de
cœurs, chacune avec sa part de la limite de mémoire ; les fichiers que nomme `serial` de `[test]` tournent seuls, après
les autres. L'option `--worker` est celle que le runner (le programme qui lance les unités) donne à chacune d'elles :
elle n'est pas pour la ligne de commande.

## cesia check

```bash
cesia check [--json] [--stdin file.ce] [path...]
```

Lit le code et dit ce qui ne va pas, sans en exécuter une ligne : la syntaxe, les noms, les arguments d'une fonction,
d'une struct ou d'une fonction native connue, les valeurs qui ne correspondent sûrement pas à un type, et les
[résultats](types.md#vérifier-sans-exécuter-cesia-check) laissés sans traitement. Un chemin est un fichier, ou un
dossier avec ses sous-dossiers ; sans chemin, les dossiers de sources de `cesia.toml`. Un fichier d'un dossier de
sources est lu avec les autres fichiers de son package, comme `use` les lit, et un test avec son package ; tout autre
fichier tient seul, comme un programme. Il ne demande que la permission de lire, donc vérifier un projet venu d'ailleurs
est sans danger. Finit avec le code 1 quand il y a une erreur ; des warnings (des avertissements) seuls donnent 0.

| Option | Ce qu'elle fait |
|---|---|
| `--json` | un objet JSON par ligne, et rien d'autre : `file`, `line`, `column`, `end` (la colonne après l'étendue signalée), `severity` (`"error"` ou `"warning"`), `message`, `hint` |
| `--stdin file.ce` | le texte de ce fichier vient de l'entrée au lieu du disque, comme un éditeur envoie un buffer (le texte qu'il garde en mémoire) pas encore enregistré |

## cesia fmt

```bash
cesia fmt [--check] [path...]
```

Écrit les fichiers dans le style que partage le code de Cesia, et nomme chacun de ceux qu'il change. Une ligne qui
commence un statement (une instruction) est indentée de deux espaces pour chaque bloc où elle se trouve, `defn`, `if`,
`for`, `while`, `match` ou `struct`, et une ligne qui continue un statement, entre parenthèses ou crochets ou après une
virgule, se déplace avec la ligne qu'elle continue ; aucune ligne ne finit par des espaces ; deux lignes vides ne se
suivent jamais, et aucune ne commence ni ne finit le fichier. Rien d'autre ne change : pas un mot, pas un commentaire,
pas un texte, pas un `\r\n`. Avant d'écrire un fichier, il vérifie que le code se lit comme le même programme ; un
fichier qui ne se lit pas reste tel quel, et est nommé avec son erreur. Un chemin est un fichier, ou un dossier avec ses
sous-dossiers ; sans chemin, le projet d'ici, sans ses `std/` et `deps/`. Il demande les permissions de lire et
d'écrire. Finit avec le code 1 quand un fichier reste tel quel.

| Option | Ce qu'elle fait |
|---|---|
| `--check` | n'écrit rien : nomme chaque fichier hors du style, et finit avec le code 1 s'il y en a un |

## cesia lsp

```bash
cesia lsp
```

Un *language server*, pour les éditeurs qui parlent le Language Server Protocol, LSP, version 3.17 : un programme qu'un
éditeur lance et auquel il parle en JSON, pour qu'un seul serveur donne à chaque éditeur les erreurs, la documentation et
les définitions d'un langage. Il lit leurs messages sur son entrée et répond sur sa sortie, et compte les positions dans
une ligne en code units UTF-16 (les unités de 16 bits du codage UTF-16), comme le dit le protocole. Il montre ce que
`cesia check` trouve dans un fichier ouvert pendant qu'on le tape, la documentation du nom sous le curseur, l'endroit où
un nom est défini, et les noms d'un package après son point. L'éditeur le lance dans le dossier du projet, comme
[Éditeurs](editors.md) le montre pour chacun. Il ne demande que la permission de lire.

## cesia do

```bash
cesia do [task]
```

Sans tâche, liste les tâches de `cesia.toml`. Avec une tâche, lance les tâches dont elle a besoin, puis elle-même, et
affiche d'abord chaque commande. Voir [cesia.toml](toml.md).

## cesia new

```bash
cesia new name
```

Crée un projet dans un nouveau dossier : `cesia.toml`, `src/main.ce`, `.gitignore`, `std/` et `cesia.lock`.

## cesia pkg

```bash
cesia pkg [install | update [label] [--to tag] | add url@tag [package...] | move old new | --check]
```

| Commande | Ce qu'elle fait |
|---|---|
| `cesia pkg` | chaque package, sa version, et s'il est tel qu'il a été installé |
| `cesia pkg install` | rend `std/` et `deps/` conformes à ce que disent `cesia.toml` et `cesia.lock` |
| `cesia pkg update [label] [--to tag]` | une dépendance vers son tag (le nom git d'une version, comme v1.1.0) le plus récent, ou vers celui-là, et `std/` vers ce Cesia |
| `cesia pkg add url@tag [package...]` | écrit une table `[deps]` et l'installe |
| `cesia pkg move old new` | prend un fork (une copie d'un dépôt, publiée ailleurs) au lieu d'un dépôt, et réécrit les lignes use du projet |
| `cesia pkg --check` | les tags plus récents, par le réseau |

Voir [Packages](packages.md).

## cesia upgrade

```bash
cesia upgrade [--nightly]
```

Montre les notes de la release (une version publiée) la plus récente de Cesia, et demande avant de l'installer.
`--nightly` prend le build du jour (la version construite chaque nuit).

## cesia doc

```bash
cesia doc [name]
cesia doc --site [folder] [--open]
```

`cesia doc` liste les modules ; avec un module, comme `std/num`, ses noms ; avec un nom, comme `num.Solve` ou `Sort`, son
texte et ses exemples. `--site` construit le site du projet dans `site/`, ou dans le dossier donné, et `--open` l'ouvre
dans le navigateur. Voir [Tests](tests.md).

## cesia version

```bash
cesia version
```

Affiche la version de Cesia.
