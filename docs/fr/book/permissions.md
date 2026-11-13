# Permissions

Dans ce chapitre, vous décidez de ce qu'un programme a le droit de toucher : les fichiers, le réseau, les autres
programmes. Un programme Cesia ne peut rien toucher hors de lui-même tant que sa ligne de commande ne le permet pas : il
tourne dans une [sandbox](glossary.md#sandbox), un endroit où un programme n'a que les droits qu'on lui a donnés. Python,
Node, Java et Go donnent à un programme tous les droits de l'utilisateur qui le lance ; Deno, un runtime de JavaScript
(le programme qui exécute du JavaScript hors d'un navigateur), fait comme Cesia, sans aucun droit par défaut et avec des
flags `--allow` (des options de la ligne de commande). Vous fixez aussi des limites sur la durée de son exécution et sur
la mémoire qu'il prend, pour qu'un programme en qui vous n'avez pas confiance, ou un bug, ne puisse pas nuire à la
machine.

## Rien par défaut

Sans permission, un programme calcule et affiche, et c'est tout. Une fonction qui a besoin de plus arrête le programme,
et le message dit quoi ajouter :

```cesia fails
use std/sys
sys.Read("notes.txt")
```

Une permission refusée est un bug, pas un `Err` : le programme a demandé quelque chose qu'on ne lui a pas donné, et la
correction se fait sur la ligne de commande.

## --allow

`--allow` prend une liste de permissions, séparées par des virgules :

```bash
cesia run --allow read program.ce
cesia run --allow read=./data,write=./out program.ce
cesia run --allow net=:8080,env=HOME server.ce
```

| Permission | Permet |
|---|---|
| `read`, `read=./data` | lire des fichiers, tous ou ceux qui sont sous un dossier, et dire où ils sont, comme le fait [path.Abs] |
| `write`, `write=./out` | écrire, renommer et supprimer des fichiers, tous ou sous un dossier |
| `net`, `net=:8080` | le réseau, ou seulement l'écoute sur un port de cette machine : l'adresse, ou celle que donne un nom, est 127.0.0.1 ou ::1 |
| `net=0.0.0.0:8080`, `net=[::]:8080` | l'écoute sur un port, aussi pour les autres machines, sur toutes les adresses ou sur une seule |
| `net=example.com`, `net=example.com:443` | la connexion à un hôte, sur n'importe quel port ou sur un seul |
| `net=own` | l'écoute sur cette machine, et la connexion aux seuls listeners du programme lui-même (les sockets où il attend des connexions) tant qu'ils sont ouverts, par adresse ou par `localhost`, sans chercher aucun nom : ce que reçoit un test |
| `exec`, `exec=git` | lancer d'autres programmes, tous ou un seul |
| `env`, `env=HOME` | lire les variables d'environnement, toutes ou une seule |
| `ffi=m`, `ffi=build/libdemo.so` | charger une bibliothèque C, par son nom ou par le chemin exact de son fichier |
| `native=cepheus` | faire tourner le moteur d'un [package natif](native.md), par l'étiquette de son entrée `[deps]` dans `cesia.toml` : une confiance totale, comme `ffi=` |
| `debug` | les breakpoints (les lignes où le programme s'arrête pour qu'on l'examine) et le code lancé par [std/debug] ; `cesia run --debugger` et `cesia run --repl` la donnent d'eux-mêmes, sans `--allow` |
| `all` | tout |

### Cette machine ou le réseau

Un serveur écoute par défaut sur 127.0.0.1, que seuls les programmes de la même machine atteignent, et `net=:8080` ne
permet que cela. Pour accepter des connexions venues d'autres machines, comme d'un téléphone sur le même wifi, le serveur
écoute sur `0.0.0.0` (toutes les adresses de la machine), et la permission nomme aussi cette adresse :

```bash
cesia run --allow net=0.0.0.0:8080 server.ce
```

où `server.ce` appelle `http.Serve(app, host = "0.0.0.0")`. Avec `net=:8080`, cette écoute est refusée, et le message
dit quelle permission écrire.

### Aussi étroite que possible

Une permission avec `=` est la plus étroite que vous puissiez écrire. Donnez celle-là, selon le
[principle of least privilege](glossary.md#principle-of-least-privilege) (le principe du moindre privilège) : un
programme qui lit ses données dans `./data` a besoin de `read=./data`, pas de `read`. Lire hors du dossier est refusé
comme si rien n'avait été donné. Un dossier contient un chemin selon l'endroit où ce chemin mène, liens suivis : un lien
dans `./data` qui pointe au-dehors est refusé lui aussi, comme l'écriture d'un nouveau fichier à travers un tel lien.

Les permissions disent ce que le programme peut toucher ; les autres personnes de la machine sont tenues à l'écart par les
modes des fichiers (les droits que le système note sur chacun). Ce qui contient un secret, des clés ou une session,
s'écrit avec `private = true`, que prennent [sys.Write] et [sys.Mkdir] : le fichier ou le dossier est alors à son
propriétaire seul dès son premier octet (voir [À vous seul](files.md#à-vous-seul)).

## ffi est une confiance totale

Une bibliothèque C, appelée par la [foreign function interface](glossary.md#foreign-function-interface) (la façon dont un
langage appelle des fonctions écrites dans un autre), tourne hors des vérifications de Cesia : elle peut lire n'importe
quel fichier, ouvrir n'importe quelle connexion, et casser la mémoire du programme. `ffi=NAME` donne tout à un programme
pour cette bibliothèque : ne la donnez donc qu'à des bibliothèques en qui vous avez confiance, comme celles qu'utilisent
les modules de Cesia lui-même. `native=LABEL` est la même confiance, pour le moteur OCaml d'un
[package natif](native.md).

## Une tâche garde ses permissions

Taper les permissions à chaque fois est lent et source d'erreurs. Une tâche de `cesia.toml` les écrit une fois, à côté
du fichier qu'elle lance :

```toml
[tasks.serve]
file = "src/server.ce"
allow = ["read=data", "write=data/uploads", "net=:8080"]
limit = "memory=1G"
```

`cesia do serve` la lance, et affiche d'abord la commande `cesia run` exacte. Un lecteur du projet voit en un seul
endroit ce que chaque programme a le droit de faire.

## --limit

`--limit` arrête un programme qui va trop loin, avec `Limit "memory" reached.` (la limite de mémoire est atteinte) et la
ligne où il en était :

```bash
cesia run --limit memory=512M,steps=10000000 program.ce
```

| Limite | Arrête le programme quand |
|---|---|
| `memory=512M` | il garde plus de mémoire que cela : `K`, `M` et `G` sont ses unités |
| `steps=1000000` | il a exécuté autant de pas, comme une boucle qui ne finit jamais : un pas est un appel ou un tour de boucle, et une fonction native compte environ un pas pour 16 valeurs qu'elle fabrique |
| `depth=10000` | les appels dans des appels vont plus profond que cela : la valeur par défaut est 10 000 |
| `nesting=600` | du code, du JSON ou des valeurs sont imbriqués plus profond que cela : la valeur par défaut est 600 |

### Les valeurs par défaut

Sans `--limit memory`, un programme peut prendre au plus 80 % de la mémoire de la machine, pour qu'un seul grand array
(une liste de valeurs rangées par position) ne puisse pas la figer. Une fonction qui s'appelle elle-même sans fin
s'arrête à la limite de profondeur, avec la ligne de l'appel :

```cesia fails
forever(n) = forever(n + 1) + 1
forever(1)
```

### D'où viennent les limites

Les pas et la profondeur sont comptés de la même façon par l'interpréteur et par le code machine du JIT (la partie qui
change en code machine ce qui tourne souvent) : une limite arrête donc un programme au même pas, quel que soit celui des
deux qui l'exécute ; la mémoire est le heap d'OCaml (la mémoire où OCaml range les valeurs), regardé tous les millions de
pas et avant chaque grosse allocation, comme l'explique
[Comment Cesia fonctionne](internals.md#la-mémoire-et-le-garbage-collector). Une limite atteinte arrête le programme avec
l'exit code 1 (le nombre que le programme rend à celui qui l'a lancé). Dans une fiber (une fonction qui tourne à côté
des autres dans le même programme), une limite de mémoire ou d'imbrication n'arrête que cette fiber, comme la requête
d'un serveur ; les pas appartiennent au programme entier.

## Ce que les commandes de Cesia ont le droit de toucher

Les commandes de `cesia` qui exécutent du code Cesia, comme `cesia check` ou `cesia lsp`, l'exécutent avec ces seules
permissions :

| Commande | Ses permissions |
|---|---|
| `cesia check`, `cesia lsp` | `read` |
| `cesia fmt` | `read,write` |
| `cesia pkg` | `read,write,exec=git,env=HOME,env=XDG_CACHE_HOME` |
| `cesia doc --site` | `read`, `write` dans le dossier du site, le cache et le dossier des programmes du livre, `exec` de ce `cesia` et du programme du système qui ouvre les pages, `env=CESIA_CORES` |
| `cesia upgrade` | `read,write,net,exec,env=HOME,env=CESIA_RELEASES,ffi=ssl,ffi=crypto,debug` |
| `cesia test` | pour chaque test, comme ci-dessous |

Un test de `cesia test` a le droit de lire le projet, d'écrire dans son propre dossier temporaire, et d'utiliser
`net=own` ; le `allow` de `[test]` dans `cesia.toml` et `--allow` s'y ajoutent, comme le montre [Tests](tests.md).

## Lancer le code de quelqu'un d'autre

Ensemble, les permissions et les limites permettent de lancer sans danger un programme que vous venez de télécharger :

- lancez-le d'abord sans `--allow` : chaque message dit ce qu'il veut, une chose à la fois ;
- donnez pour chacune la permission la plus étroite, un dossier ou un port ;
- ajoutez un `--limit memory` et `steps` pendant que vous regardez ce qu'il fait.

## La suite

Vos programmes ne touchent que ce que vous permettez. Le chapitre suivant, [Fichiers](files.md), lit et écrit des
fichiers, liste des dossiers, lance d'autres programmes, et lit l'horloge.
