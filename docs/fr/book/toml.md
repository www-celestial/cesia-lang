# cesia.toml

Chaque table et chaque clé de `cesia.toml`, le fichier à la racine d'un projet. Il est écrit en TOML, un format de tables
entre crochets et de lignes `key = value`, et Cesia lit un sous-ensemble strict de TOML 1.0 : des textes, `true` et
`false`, et des listes de textes. Un fichier que Cesia accepte veut dire la même chose pour tout lecteur de TOML, et tout
le reste est une erreur sur sa ligne, jamais une supposition. Une clé que Cesia ne connaît pas arrête `cesia do` avec sa
ligne, si bien qu'une faute de frappe ne peut pas passer inaperçue. Les clés de `[site]` sont l'exception :
`cesia doc --site` les lit, et c'est lui qui les vérifie.

## `[project]`

```toml
[project]
name = "shop"
cesia = "1.0"
src = ["src"]
native = ["sodium"]
```

| Clé | Ce qu'elle dit |
|---|---|
| `name` | le nom du projet |
| `cesia` | la plus ancienne version de Cesia dont il a besoin : une plus ancienne s'arrête tout de suite, et dit de lancer `cesia upgrade` |
| `src` | les dossiers de son code, `["src"]` quand la clé manque : ce qu'un autre projet prend sans `take`, et ce que lisent `cesia doc` et `--site` |
| `native` | les bibliothèques C qu'il charge : chaque tâche qui lance un fichier reçoit `ffi=` pour chacune d'elles |

## `[native]`

Le moteur d'un [package natif](native.md) : de l'OCaml compilé une fois, qui fait tourner les fonctions natives d'un des
packages du projet.

```toml
[native]
package = "cesia/echo"
natives = ["reverse", "later"]
```

| Clé | Ce qu'elle dit |
|---|---|
| `package` | le package dont les fichiers voient les fonctions natives, sous la forme d'un chemin depuis la racine |
| `natives` | leurs noms, chacun un nom privé (qui commence par une minuscule) : le moteur `native/NAME-TAG.cmxs` doit enregistrer exactement ceux-là |

## `[tasks.NAME]`

Une tâche est un programme à lancer avec ses permissions, une commande, ou un groupe d'autres tâches. `cesia do NAME` la
lance.

```toml
[tasks.serve]
file = "src/server.ce"
allow = ["read=data", "write=data", "net=:8080"]
limit = "memory=1G"
watch = true
needs = ["test"]

[tasks.test]
run = ["tests/run.sh"]

[tasks.all]
needs = ["test", "serve"]
```

| Clé | Ce qu'elle dit |
|---|---|
| `file` | le fichier Cesia à lancer, ou `"."` pour tous les fichiers de la racine comme un seul programme |
| `allow` | ses permissions, comme `--allow` les prend, une par texte |
| `limit` | ses limites, comme `--limit` les prend, dans un seul texte |
| `watch` | `true` pour recharger à chaque enregistrement, comme `--watch` |
| `workers` | les workers (les processus qui servent) d'un serveur, comme `--workers` les prend, dans un texte : `"4"` ou `"cores"` ; pas avec `watch` |
| `run` | une commande et ses arguments, lancés tels quels, sans shell ; une tâche a `file` ou `run`, pas les deux |
| `needs` | les tâches à lancer d'abord, dans l'ordre ; une tâche qui n'a que `needs` est un groupe |

## `[test]`

Ce que `cesia test` donne à chaque test du projet, au-delà de ce qu'il a par défaut : lire le projet, écrire dans son
propre dossier temporaire, et `net=own`.

```toml
[test]
allow = ["net=example.com:443", "exec=git"]
timeout = "30"
serial = ["tests/db"]
skip = ["tests/e2e"]
```

| Clé | Ce qu'elle dit |
|---|---|
| `allow` | plus de permissions, comme `--allow` les prend, une par texte |
| `timeout` | les secondes qu'un test peut prendre, sous la forme d'un texte : `"10"` sans elle |
| `serial` | les fichiers et les dossiers dont les tests partagent quelque chose, comme un port ou une base de données, et tournent seuls, après les autres |
| `skip` | les fichiers et les dossiers que `cesia test` laisse de côté, sauf si son chemin est dans l'un d'eux : `cesia test tests/e2e` lance ceux-là |

## `[deps.LABEL]`

Un projet dont celui-ci prend des packages. `cesia pkg add` écrit la table.

```toml
[deps.geometry]
from = "github.com/someone/geometry"
version = "v1.2.0"
take = ["src/shapes"]
```

| Clé | Ce qu'elle dit |
|---|---|
| `from` | le dépôt, sans `https://` |
| `version` | un de ses tags (le nom git d'une version), ou le hash entier d'un commit pour un projet qui n'a pas encore de tag |
| `take` | les packages pris, sous la forme de chemins depuis sa racine ; sans elle, chaque package de son `src` |

## `[site]`

Ce que `cesia doc --site` écrit sur chaque page.

```toml
[site]
title = "Shop"
source = "https://github.com/someone/shop/blob/main/"
color = "#0c8599"
```

| Clé | Ce qu'elle dit |
|---|---|
| `title` | le nom en haut de chaque page |
| `source` | le début d'un lien vers le code : la page d'un nom renvoie à son fichier et à sa ligne |
| `color` | la couleur du projet, `#rrggbb`, dont le site tire ses couleurs au contraste AA : voir [Tests](tests.md#couleurs) |
