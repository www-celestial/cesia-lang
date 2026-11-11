# Modules pour les outils

Cinq modules de `std/` servent aux outils autour des programmes plutôt qu'aux programmes : les outils de Cesia lui-même,
`cesia pkg`, `cesia fmt`, `cesia lsp`, le site de la documentation, le debugger (le programme qui exécute le vôtre et
peut l'arrêter) et le prompt (la ligne où vous tapez du code à côté d'un programme qui tourne), sont écrits en Cesia avec
eux, et les vôtres peuvent l'être aussi. Chaque nom a sa page dans la référence, avec ses exemples ; cette page dit à
quoi sert chaque module.

## std/cesia : Cesia sur lui-même

[std/cesia] dit à un outil ce que Cesia sait : [cesia.Version] sa version, [cesia.IsDev] s'il a été construit depuis ses
sources, [cesia.Binary] le chemin du binaire qui tourne, [cesia.Libraries] les bibliothèques de `std/` qu'il contient, et
[cesia.Keywords] les mots réservés, pour un highlighter (un outil qui colore le code). [cesia.IsVersion] et
[cesia.Compare] lisent et rangent des versions comme des tags (les noms git des versions), `v1.2.0` avant `v1.10.0` ;
[cesia.Fingerprint] donne le BLAKE2b-256 d'un texte, tel que `cesia.lock` les garde.

```cesia
use std/cesia
cesia.Compare("v1.2.0", "v1.10.0") < 0 -->
cesia.IsVersion("v2.0") -->
cesia.Fingerprint("abc") -->
```

Les autres lisent du code sans l'exécuter. [cesia.Check] donne ce que `cesia check` trouve dans des fichiers ;
[cesia.Uses] les lignes use d'une source, [cesia.Definitions] ce qu'elle définit à son niveau le plus haut, hors de toute
fonction ; [cesia.SameTree] dit si deux sources se lisent comme le même programme quels que soient leurs espaces et leurs
commentaires, ce que `cesia fmt` demande avant d'écrire un fichier ; [cesia.Toml] lit un `cesia.toml` ou un
`cesia.lock` sous forme de tables. [cesia.Doc], [cesia.DocNames] et [cesia.DocEntry] donnent la documentation telle que
`cesia doc` et le site la lisent, et [cesia.Asset] les fichiers de l'apparence du site, gardés dans le binaire.

```cesia
cesia.Uses("use std/io\nuse src/shop\nio.Print(1)") -->
cesia.SameTree("x = 1  (* one *)", "x = 1") -->
```

## std/syntax : les couleurs du code

[std/syntax] lit une ligne de Cesia à la fois et donne ses mots, chacun avec son rôle : [syntax.Keyword], [syntax.Name]
d'un appel, [syntax.Field] après un point, [syntax.Number], [syntax.Text], [syntax.Comment] ou [syntax.Plain]. Une ligne
est lue en une passe, par *états* : un texte ou un commentaire qui ne finit pas sur sa ligne porte son état à la
suivante, et c'est tout ce dont une ligne a besoin des lignes d'avant. [syntax.Tokens] lit une ligne à partir d'un état,
[syntax.FirstState] est l'état au début d'un fichier. Rien dans ce module ne déclenche de panic (l'arrêt net d'un
programme sur un bug), quelle que soit la ligne.

```cesia
use std/syntax
syntax.Tokens("n = 2 (* two", syntax.FirstState).Tokens -->
```

Pour un éditeur qui colore un long fichier et en change une ligne, [syntax.BlankColors], [syntax.ColoredTo] et
[syntax.ForgetFrom] gardent les couleurs des lignes déjà lues, et ne relisent qu'à partir de la ligne changée. Le site de
la documentation colore son code avec lui.

## std/columns : le travail sur des colonnes entières

[std/columns] est l'OCaml sous [std/frame] et [std/sql] : le travail sur des colonnes entières, qui tourne sur plusieurs
cœurs pour une grande colonne. [columns.ReadCsv] lit un CSV avec un en-tête en colonnes nommées, les nombres comme des
nombres, et [columns.Csv] en lignes de textes ; [columns.Groups] numérote les groupes de lignes qui partagent leurs clés,
et [columns.Split] donne les valeurs de chaque groupe ; [columns.Join] apparie deux colonnes de clés, le hash join (qui
met les clés de l'une dans une hash table, puis y cherche celles de l'autre) de [frame.JoinOn] ; [columns.Pick],
[columns.Positions] et [columns.Present] prennent des valeurs par position, par masque, ou sans celles qui sont missing ;
[columns.Rows] fabrique des lignes sous forme de maps qui partagent leurs clés, si bien qu'une ligne ne coûte que ses
valeurs ; [columns.Kind] dit comment une colonne est rangée, `"int"`, `"float"` ou `"value"` ; et [columns.Cores]
combien de cœurs un gros travail peut utiliser.

```cesia
use std/columns
columns.Kind([1, 2, 3]) -->
columns.Kind([1, "a"]) -->
columns.Positions([true, false, true]) -->
columns.Groups([["a", "b", "a"]]) -->
```

## std/sqlite3 : les fonctions natives de SQLite

[std/sqlite3] est le côté OCaml de [std/sql] : [sqlite3.Pool] ouvre un pool de connexions (un groupe de connexions
ouvertes d'avance, qu'on emprunte et qu'on rend), [sqlite3.Take] et [sqlite3.Give] en prennent une et la rendent,
[sqlite3.Run] prépare un statement (une instruction SQL), depuis un cache de 128 rangés par leur texte, et lie ses
valeurs, [sqlite3.Next] donne les lignes suivantes par lots, [sqlite3.Query], [sqlite3.One] et [sqlite3.Exec] exécutent
un statement, [sqlite3.Script] plusieurs, [sqlite3.Close] ferme un curseur, une connexion ou un pool, et
[sqlite3.Version] dit la version de SQLite. Un programme utilise [std/sql], qui vérifie ce que ces fonctions lui
laissent ; un outil qui a besoin des curseurs eux-mêmes utilise celles-ci.

## std/debug : le moteur d'un debugger

[std/debug] donne à un debugger passé à `cesia run --debugger` ses breakpoints (les lignes où le programme doit
s'arrêter), [debug.SetBreak], [debug.ClearBreak] et [debug.Breaks] ; ses watches (les expressions qu'il montre à chaque arrêt),
[debug.Watch], [debug.Unwatch] et [debug.Watches] ; [debug.Eval], qui exécute du code dans une frame (les variables d'un
appel en cours) du programme arrêté ; [debug.Reload] ; et [debug.ReadLine] et [debug.IsComplete] pour son prompt. Ils
demandent la permission `debug`. [Le prompt et le debugger](debug.md#votre-propre-debugger) écrit un debugger avec eux.

## La suite

Les [Commandes](commands.md) disent ce que fait chacun de ces outils depuis la ligne de commande.
