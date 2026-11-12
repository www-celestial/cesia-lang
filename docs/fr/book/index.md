# Cesia

Cesia est un petit langage pour résoudre directement de vrais problèmes. Servez-vous-en pour :

- un script qui nettoie un CSV ;
- un serveur web sur une base de données ;
- un programme qui pilote d'autres programmes.

Il démarre tout de suite et il est sûr par défaut, et quand quelque chose ne va pas, il dit quoi écrire.

```cesia
use std/io
io.Print("Hello from Cesia")
```

Ce livre enseigne Cesia depuis le début. Chaque exemple de ces pages a tourné quand le site a été construit, et le texte
en dessous est ce qu'il a affiché. Quand le site se construit, un exemple qui donne un autre résultat arrête la
construction : le livre ne peut donc pas s'écarter du langage.

## Comment le lire

- La première fois, lisez les chapitres dans l'ordre : chacun se sert de ce que les précédents ont montré.
- Tapez les exemples vous-même, dans un fichier ou dans votre éditeur. Changez-les et relancez-les : c'est la façon la plus
  rapide d'apprendre.
- Un nom dans le texte mène à sa page dans la référence : [io.Print], par exemple, ou le mot-clé [match].
- Appuyez sur `/` pour chercher, sur `n` et `p` pour tourner les pages, et sur `?` pour voir toutes les touches.

## Sommaire

1. [Installer et lancer un premier programme](install.md) : Cesia sur votre machine, un premier programme, un projet.
2. [Valeurs et noms](values.md) : les nombres, les textes, true et false, missing, et comment marchent les noms.
3. [Textes](texts.md) : couper, joindre et chercher dans les textes.
4. [Listes et arrays](lists.md) : à partir de 1, les ranges, le tri, les sommes et les matrices.
5. [Choix et boucles](choices.md) : `if`, `for`, `while` et `match`.
6. [Fonctions](functions.md) : vos propres fonctions, et celles qui prennent des fonctions.
7. [Maps](maps.md) : des valeurs sous des noms, compter, des dictionnaires imbriqués.
8. [Structs](structs.md) : des formes déclarées une fois, les valeurs par défaut, les méthodes, `From` et `Fields`.
9. [Erreurs](errors.md) : `Ok` et `Err`, `?`, les étapes sur des résultats, et les bugs.
10. [Types](types.md) : les types sur les champs, les paramètres et les résultats, `?` pour une valeur absente, les
    interfaces.
11. [Packages](packages.md) : `use`, les dossiers comme packages, `cesia.toml`, les tâches, le code d'autres projets.
12. [Permissions](permissions.md) : `--allow`, `--limit`, et les permissions d'une tâche.
13. [Fichiers](files.md) : lire, écrire, les dossiers et les chemins, les arguments et les flags, les autres programmes,
    l'horloge et l'heure locale.
14. [Données](data.md) : les comprehensions, les groupes, les comptes et les rangs, les tables de colonnes tirées d'un
    fichier CSV, les échantillons au hasard.
15. [Nombres et algorithmes](numbers.md) : std/math, std/num et LAPACK, les algorithmes classiques, les sets, les queues
    et les heaps, et ce que chacun coûte.
16. [Graphiques](graphs.md) : courbes, points, barres, histogrammes, cartes de chaleur et densités comme
    valeurs, dessinés en SVG, et la méthode que suit chaque étape.
17. [Méthodes numériques](numerical.md) : le zéro d'une fonction et les équations différentielles, comme
    `fzero` et `ode45`, avec ce que promet chaque méthode, à côté de scipy et d'Octave.
18. [JSON et CSV](json.md) : lire, écrire, et vérifier ce qui arrive.
19. [HTTP](http.md) : un serveur web avec des routes et du JSON, testé sans le réseau, les live screens (des pages
    qui changent d'elles-mêmes), et le client.
20. [Cryptographie](crypto.md) : les hashes, les mots de passe, le chiffrement avec une clé ou pour quelqu'un, les
    signatures, grâce à libsodium.
21. [Fibers](fibers.md) : plusieurs choses à la fois, `Spawn`, `Wait`, `Pmap` et les channels.
22. [SQLite](sqlite.md) : les tables, les lignes, les queries avec `?`, les transactions et les lignes comme structs.
23. [Tests](tests.md) : les exemples dans la documentation, les fonctions de test, les propriétés, les snapshots,
    `cesia test`, et un site pour votre projet.
24. [Le prompt et le debugger](debug.md) : `--repl` à côté d'un programme qui tourne, les breakpoints, les arrêts sur
    erreur, corriger et continuer.
25. [Cells](cells.md) : un notebook (du code coupé en cellules, chacune avec son résultat) dans un fichier `.ce`, des
    cellules qui tournent de nouveau quand ce qu'elles lisent change, une session, et une page à partager.
26. [Vitesse](speed.md) : ce qui devient du code machine pendant qu'un programme tourne, et Cesia à côté de Python, Node,
    Java, Go, OCaml, Lua et LuaJIT, mesuré : le démarrage, les boucles, les maps, les fibers et un serveur.
27. [C et C++](c.md) : les bibliothèques du système, leurs types, la mémoire, les callbacks, et le C++ à travers une couche
    C.
28. [Packages natifs](native.md) : le moteur d'un package en OCaml, compilé une fois, sa permission, et comment en écrire
    un.
29. [Un vrai programme](project.md) : un service web de notes sur SQLite, avec ses tests, de `cesia new` jusqu'à un
    serveur.
30. [Résoudre un vrai problème](duplicates.md) : quels fichiers d'un dossier sont des doublons, en sept étapes, de la
    première mesure à la preuve que c'est résolu : les propriétés, la borne des anniversaires, et les temps à côté de
    Python.
31. [Comment Cesia fonctionne](internals.md) : le lexer, le parser, les closures, les valeurs en mémoire, le hash trie des
    maps, le JIT, les fibers et leur scheduler, les channels, le serveur sur tous les cœurs, le garbage collector et le
    démarrage, avec leurs chiffres.

Annexes, pour chercher quelque chose :

- [Commandes](commands.md) : chaque commande de `cesia` et chaque option.
- [Éditeurs](editors.md) : les erreurs, la documentation et les définitions dans Neovim, Helix et Emacs, grâce à
  `cesia lsp`.
- [cesia.toml](toml.md) : chaque table et chaque clé du fichier d'un projet.
- [Variables d'environnement](env.md) : celles que Cesia lit.
- [Messages d'erreur](messages.md) : chaque message que Cesia peut afficher, d'où il vient, et quoi faire.
- [Modules pour les outils](tools.md) : std/cesia, std/syntax, std/columns, std/sqlite3 et std/debug, avec lesquels les
  propres outils de Cesia sont écrits.
- [Mots](glossary.md) : les noms des idées de ce livre, tels que les programmeurs les disent, chacun avec son chapitre.
- [Références](references.md) : les articles, les standards et les livres que Cesia suit, chacun avec ce qu'il en a pris.

La référence, sous [Référence](ref/index.html), liste chaque module, chaque nom et chaque mot-clé, chacun avec ses exemples.
