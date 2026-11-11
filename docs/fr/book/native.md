# Packages natifs

Dans ce chapitre, vous écrivez un package dont le cœur est de l'OCaml compilé en code machine, les instructions que le
processeur exécute directement : son moteur. Une base de données, un solver (un programme qui résout des équations ou des
contraintes), un codec (ce qui code et décode un format, comme une image ou un son) : du travail qui demande ses propres
structures de données et chaque nanoseconde. Le moteur est compilé une fois, par l'auteur du package, et Cesia le charge au
premier appel de l'une de ses natives (les fonctions que fournit le moteur), comme il charge son propre JIT (la partie qui
change en code machine le code qui tourne souvent). Aucun de ceux qui utilisent le package ne compile quoi que ce soit.

Pour une bibliothèque C qui existe déjà, utilisez [std/c](c.md). Un package natif sert au nouveau code natif, en OCaml.

## Une confiance totale

Un moteur est du code machine qui tourne avec les droits du programme : les permissions et les limites de Cesia s'arrêtent
à sa porte. Un programme demande donc `native=LABEL` pour en lancer un, où `LABEL` est le label du package dans les
`[deps]` de son `cesia.toml` (le nom sous lequel il y est déclaré), ou le nom du projet pour son propre moteur :

```bash
cesia run --allow native=echo main.ce
```

Un package honnête demande à Cesia les permissions de ce que le programme lui donne, un chemin à lire par exemple. Cesia
ne peut pas forcer un package malhonnête à les demander : `native=` est la confiance que vous accordez à son auteur, comme
`ffi=` l'est pour une bibliothèque C. `cesia check`, `doc`, `lsp`, `fmt` et `pkg` ne chargent jamais un moteur : ouvrir un
projet dans un éditeur n'exécute aucun code natif.

## En utiliser un

Un package natif s'utilise comme n'importe quel package d'un autre projet, et ses natives sont des noms privés du package,
que ses propres fonctions enveloppent :

```text
use deps/someone/echo/cesia/echo
use std/io
io.Print(echo.Reverse([1, 2, 3]))
```

Son moteur est un fichier du package, `native/echo-TAG.cmxs`. Un `.cmxs` est un plugin OCaml : une shared library (un
fichier de code machine qu'un programme en cours charge et lie à lui-même, comme un `.so` sur Linux ou un `.dll` sous
Windows). `TAG` est ce que donne [cesia.Native] : `1-ocaml5.5.0-linux-x86_64`, la version de l'interface native, l'OCaml
qui a construit ce Cesia, et le système. Comme chaque fichier de `deps/`, il ne se charge que tel que `cesia.lock` dit qu'il
a été installé. Un moteur fait pour l'OCaml d'un autre Cesia est refusé, avec ce qu'il faut faire ; quand le moteur manque,
le message nomme les tags que le package possède :

```text
deps/someone/echo has no engine for 1-ocaml5.5.0-linux-x86_64 (it has 1-ocaml5.4.0-linux-x86_64): run cesia pkg install.
```

Le moteur reste chargé jusqu'à la fin du processus. `cesia run --watch` le garde d'une exécution à la suivante, et le dit
si son fichier a changé entre-temps.

## En écrire un

### Le projet

La table `[native]` du `cesia.toml` du package nomme le package Cesia dont les fichiers voient les natives, puis les
natives. Chacune est un nom privé, avec une minuscule en première lettre : les noms publics sont ceux du côté Cesia,
documentés.

```toml
[project]
name = "echo"
src = ["cesia"]

[native]
package = "cesia/echo"
natives = ["echo4", "reverse", "later"]
```

```text
echo/
  cesia.toml
  cesia/echo/echo.ce     the Cesia side: the public functions, documented
  engine/echo.ml         the OCaml side: the natives, on Cesia_v1
  native/                the engines built for each Cesia
```

Le côté Cesia enveloppe les natives, comme `std/list` enveloppe les siennes :

```text
(** Echo: maps made again, lists the other way round, and values that come back later. *)

Echo4(i, x, s, b) = echo4(i, x, s, b)  (** A map of four values, each read and made again by the engine. *)
Reverse(items) = reverse(items)  (** A list, the other way round. *)
Later(seconds, v) = later(seconds, v)  (** An Ok of v, after so many seconds. *)
```

Les outils lisent les noms dans `cesia.toml` : `cesia check` et l'éditeur les connaissent donc sans faire tourner le
moteur.

### Le moteur

Le moteur n'atteint le programme que par le module `Cesia_v1`, l'interface native. Il voit chaque valeur du programme
comme une `Cesia_v1.value`, un variant : un type OCaml dont la valeur est l'un de quelques cas nommés, chacun avec ses
propres données, comme l'est un [sum type](glossary.md#sum-type). Les valeurs simples sont celles d'OCaml, `Int 3` ou
`Text "a"` : le moteur les fabrique et les lit donc avec les constructeurs d'OCaml et `match`, sans rien demander à Cesia.
Une liste, une map (des valeurs sous des clés), une struct (une forme déclarée, aux champs nommés) ou une fonction est un
`compound`, dont la disposition en mémoire est propre à Cesia et change d'une release (une version publiée) à l'autre : le
moteur ne le lit qu'à travers les fonctions de `Cesia_v1`. C'est pourquoi un moteur compilé une fois se charge dans chaque
Cesia ultérieur construit avec le même OCaml.

```ocaml
module C = Cesia_v1

(* The engine's own readers of arguments: a match each, and Cesia's message for a wrong one. *)
let int ctx name = function C.Int i -> i | v -> C.need ctx name "an Int" v
let float ctx name = function C.Float x -> x | C.Int i -> float_of_int i | v -> C.need ctx name "a Float" v
let text ctx name = function C.Text s -> s | v -> C.need ctx name "a Text" v
let bool ctx name = function C.Bool b -> b | v -> C.need ctx name "a Bool" v

(* The names of the fields, made once: their hashes are computed here, not at each call. *)
let four = C.keys [| "Int"; "Float"; "Text"; "Bool" |]

let echo4 ctx a =
  let name = "echo.Echo4" in
  C.record ctx four
    [| Int (int ctx name a.(0)); Float (float ctx name a.(1)); Text (text ctx name a.(2)); Bool (bool ctx name a.(3)) |]

let reverse ctx a =
  match a.(0) with
  | C.List l -> let n = C.length l in C.list ctx (Array.init n (fun i -> C.item ctx l (n - 1 - i)))
  | v -> C.need ctx "echo.Reverse" "a list" v

(* The work goes on a domain of the engine; the other fibers run until resume wakes this one. *)
let later ctx a =
  let seconds = float ctx "echo.Later" a.(0) in
  C.suspend ctx (fun resume -> ignore (Domain.spawn (fun () -> Unix.sleepf seconds; resume ())));
  C.ok ctx a.(1)

let () = C.register [ "echo4", 4, 4, echo4; "reverse", 1, 1, reverse; "later", 2, 2, later ]
```

```text
echo.Echo4(1, 2, "a", true)    gives {Int: 1, Float: 2.0, Text: "a", Bool: true}
echo.Echo4(1, 2, 3, true)      stops: echo.Echo4 needs a Text, not the number 3.
```

`register` prend le nom de chaque native, le plus petit et le plus grand nombre de ses arguments, et son code : une
fonction de la fiber qui appelle, `ctx`, et des arguments, qui donne le résultat. Les noms doivent être ceux de
`[native]`. Un domain est l'unité de parallélisme d'OCaml, un thread (un fil d'exécution) du système qui exécute du code
OCaml à côté de celui de Cesia ; une [fiber](glossary.md#fiber) est l'un des threads légers de Cesia, nombreux dans un même
domain.

### Le construire

Le moteur est compilé contre `cesia_v1.cmi` seul : la forme compilée du fichier d'interface `cesia_v1.mli`, qui contient
les types et les signatures de `Cesia_v1` et aucun code. Un Cesia construit depuis ses sources le garde dans
`_build/default/src/native/.cesia_native.objs/byte/`. Le fichier du moteur contient ses propres modules, et aucun de la
Stdlib ni d'Unix, que contient le binaire de Cesia :

```bash
ocamlfind ocamlopt -package unix -I CESIA_NATIVE -shared -o native/echo-$(cesia run tag.ce).cmxs engine/echo.ml
```

où `tag.ce` affiche [cesia.Native]. L'OCaml doit être celui qui a construit ce Cesia : le tag dit lequel. Puis
`cesia test` lance les tests du côté Cesia, sur le moteur qui vient d'être construit.

## Les règles d'un moteur

- **Les valeurs.** Entre deux appels, un moteur garde des données OCaml, jamais un `compound` : Cesia change sur place une
  liste, une map ou une struct que rien d'autre ne tient. Un compound que le moteur rend, comme résultat ou dans une liste,
  est marqué partagé : une écriture ultérieure du programme le copie donc d'abord. Un handle (une valeur qui désigne une
  ressource gardée ailleurs) nomme ce que le moteur garde : `Handle ("echo.thing", 3)`, une sorte nommée d'après le
  package, et un numéro. Un handle n'a pas de finaliser, le code qu'un garbage collector (la partie qui libère la mémoire
  que plus rien n'utilise) exécuterait en libérant une valeur : le package fournit un `Close`.
- **Les domains.** Seul le domain de Cesia, le principal, touche aux valeurs. Les domains du moteur font le long travail, et
  rendent la main par le `resume` de `suspend`, la seule fonction que n'importe quel domain peut appeler. Une native qui
  bloque sans `suspend` bloque toutes les fibers. Un moteur n'appelle jamais `Gc.set`, `Unix.fork` ni `Sys.set_signal`.
- **Les exceptions.** Une exception OCaml qui sort d'une native devient une panic (l'arrêt net de la fiber sur un bug) qui la nomme :
  `echo.boom raised Not_found: a bug of its native package.` (echo.boom a levé Not_found : un bug de son package natif).
  Les panics et les limites propres à Cesia traversent le moteur sans être touchées : il n'écrit donc jamais `with _ ->`
  autour d'un appel à `Cesia_v1`. Une fiber annulée pendant qu'elle attend dans `suspend` s'arrête aussitôt, et le
  `resume` tardif ne fait rien.
- **Les modules.** Un moteur peut utiliser les modules de la Stdlib et d'Unix que contient le binaire de Cesia, et apporte
  les siens. Il ne peut pas apporter un module que le programme ou un autre moteur contient déjà, ni un module dont le nom
  commence par `Cesia`, ni atteindre l'intérieur de Cesia au-delà de `Cesia_v1` : le moteur est refusé avant que la moindre
  partie de son code tourne, et le message nomme le module.

## Cesia_v1

### Les valeurs

| Cas | Ce que c'est |
|---|---|
| `Missing` | `missing` |
| `Bool b`, `Int i`, `Float x` | `true` et `false`, un nombre entier de 63 bits, un float de 64 bits |
| `Text s` | un texte, en UTF-8 ; la string (la chaîne d'octets d'OCaml) est celle du programme, non copiée |
| `Handle (kind, n)` | un handle de cette sorte et de ce numéro, comme `<echo.thing 3>` ; un handle propre à Cesia qui tient une tâche est `Other` |
| `List c` | une liste, un array à une dimension |
| `Map c`, `Struct c` | une map, une struct |
| `Function c` | une fonction, qu'un moteur ne peut pas appeler dans cette version |
| `Other c` | tout le reste, comme une matrice, et ce qu'ajouteront les releases suivantes |

### Les fonctions

| Fonction | Ce qu'elle fait |
|---|---|
| `list ctx values` | une liste de ces valeurs, comptée pour `--limit memory` |
| `keys names` | les noms de champs de maps, faits une fois au démarrage du moteur, chaque nom une fois ; leurs hashes calculés à ce moment-là |
| `record ctx keys values` | une map avec une valeur pour chaque nom de `keys`, dans l'ordre : une panic si leurs nombres diffèrent |
| `ok ctx v`, `err ctx v` | `result.Ok(v)` et `result.Err(v)` |
| `length c` | le nombre d'éléments d'une liste, de champs d'une map ou d'une struct ; 0 pour tout le reste |
| `item ctx c i` | un élément d'une liste, à partir de 0 : une panic si `i` est en dehors, ou si `c` n'est pas une liste |
| `fields keys c` | les champs d'une map ou d'une struct qui ont les noms de `keys`, dans l'ordre, `Missing` pour un nom qui lui manque, en un seul appel |
| `names c`, `values c` | les noms des champs d'une struct, ou les clés textes d'une map, dans l'ordre, et leurs valeurs |
| `need ctx name what v` | une panic qui nomme la native, ce dont elle a besoin et ce qu'elle a reçu : `echo.Echo4 needs a Text, not the number 3.` |
| `suspend ctx f` | suspend la fiber et appelle `f resume` ; `resume` la réveille une fois, depuis n'importe quel domain |
| `need_read ctx path`, `need_write ctx path` | une panic, sauf si le programme peut lire ou écrire le chemin |
| `panic ctx message` | arrête la fiber, comme [bug.Panic] |
| `pay ctx n`, `reserve ctx words` | compte un parcours de valeurs pour `--limit steps`, et la mémoire que le moteur garde pour `--limit memory` |
| `register natives` | les natives du moteur, une fois, à son démarrage |

`cesia_v1.mli` ne change jamais une fois publié, pas même un commentaire. OCaml écrit dans chaque fichier compilé un
digest, un checksum MD5 (un petit nombre calculé sur les octets, qui change dès qu'un octet change), de chaque interface
contre laquelle il a été compilé, et refuse de charger un plugin dont les digests diffèrent de ceux du programme : un seul
octet changé dans `cesia_v1.mli` ferait refuser tous les moteurs construits avant. Ce qui vient plus tard va dans de
nouveaux modules, `Cesia_v1_1` et la suite, et un moteur qui a besoin de l'un d'eux le dit avec le `cesia` de son
`[project]`.

## Ce que coûte un appel

Une valeur traverse l'interface par une conversion. La disposition des valeurs de Cesia reste privée : `Int 3` dans le
moteur et `3` dans le programme sont donc deux blocs de mémoire différents, et chaque traversée fabrique l'autre : une
allocation, quelques mots du minor heap, la partie jeune de la mémoire que le garbage collector d'OCaml vide souvent.
Allouer est bon marché mais pas gratuit : 0,6 à 0,8 ns par mot dans ces boucles. Chaque argument d'une native est converti
à l'aller, et son résultat au retour ; `record`, `list` et `fields` convertissent leurs valeurs en un seul appel.

Quatre champs faits par `record` et relus par `fields`, contre le même travail fait par le code de Cesia lui-même
(mesure 1) :

| | minor heap de 2 MB | 16 MB, comme Cesia tourne |
|---|---|---|
| par `Cesia_v1`, contre le code de Cesia lui-même | +24,7 ns (88,4 contre 63,8), intervalle à 95 % de 24,2 à 25,1, $n = 40$ | +27,8 ns (98,5 contre 70,4), intervalle à 95 % de 26,5 à 28,7, $n = 40$ |
| sa première forme, jamais publiée : un appel à Cesia pour chaque valeur | +60,9 ns (166,2 contre 105,9), intervalle à 95 % de 59,4 à 65,9, $n = 40$ | +64,4 ns (178,7 contre 115,7), intervalle à 95 % de 62,1 à 68,2, $n = 40$ |

Depuis un programme Cesia, un million d'appels (mesure 2), contre la première forme de l'interface (jamais publiée), qui
donnait à un moteur les propres valeurs de Cesia et un appel pour chacune :

| Appel | Maintenant | Première forme | Différence |
|---|---|---|---|
| `math.Near(i, 2.0, 1e-9, 0.0)`, une native de std/math, par une fonction Cesia | 134 ns | 134 ns | -0,0 ns (-2,1 à +2,6) |
| `mk(i, 2.0, "a", true)`, une fonction Cesia qui fait une map de 4 | 52 ns | 52 ns | +0,6 ns (-0,4 à +1,3) |
| `echo.Echo4(i, 2.0, "a", true)`, une native de package qui lit 4 arguments et fait une map de 4 | 170 ns | 160 ns | +8,4 ns (+6,9 à +12,8) |
| `echo.Same(i, 2.0, "a", true)`, une native de package qui rend son premier argument | 118 ns | 91 ns | +26,1 ns (+25,0 à +27,6) |

Les natives propres à Cesia ne traversent pas `Cesia_v1`, et ne bougent pas. Une native de package paie pour ses
arguments : appelée depuis OCaml sans l'interpréteur, la conversion de 4 arguments et du résultat coûte environ 20 ns
(`same` : 29,8 ns contre 10,1). Sur cette machine, un bloc de deux mots (une box) coûte à peu près autant qu'un appel :
pour `echo4`, les conversions coûtent donc un peu plus que les appels qu'elles épargnent ; c'est un moteur qui lit et
fabrique des maps qui épargne le plus (mesure 1).

Le premier appel des natives d'un package charge le plugin de `Cesia_v1` et le moteur, et vérifie le fingerprint
(l'empreinte) du moteur : 548 µs (intervalle à 95 % de 536 à 564, $n = 1000$) de plus qu'une exécution qui n'en appelle
aucune, pour le moteur de 45 KB des tests.

### À côté des géants

La même tâche dans chaque système : une fonction prend un entier, un float, un texte et un booléen, lit chacun, et donne
un nouvel enregistrement des quatre ; elle est appelée un million de fois depuis une boucle du langage hôte. Une fois
écrite dans le langage hôte, une fois en code natif par l'interface native du système ; le prix est la différence.

| Système | Fonction hôte | Par son interface native | Prix |
|---|---|---|---|
| Cesia, un package natif | 50,0 ns | 164,9 ns | +114,3 ns (+113,8 à +115,3) |
| CPython 3.14, une extension C (METH_FASTCALL) | 209,0 ns | 203,8 ns | -3,0 ns (-3,7 à -2,6) |
| Node.js 26, Node-API | 19,2 ns | 1 307,8 ns | +1 287,3 ns (+1 273,3 à +1 298,6) |
| Java 21 (HotSpot), JNI | 9,4 ns | 174,0 ns | +165,1 ns (+164,5 à +166,8) |
| OCaml 5.5, un `external` en C | 6,3 ns | 24,2 ns | +17,9 ns (+17,8 à +18,4) |

Là où un géant gagne, et pourquoi :

- **L'`external` d'OCaml** traverse pour 18 ns : un appel direct à C, qui lit et fabrique sur place les propres valeurs
  d'OCaml. C'est ce que `Cesia_v1` refuse exprès à un moteur : un moteur qui connaîtrait la disposition des valeurs de
  Cesia devrait être reconstruit à chaque release.
- **L'extension C de CPython** ne coûte pas plus qu'une fonction Python, parce qu'un appel Python est lui-même lent
  (209 ns) et que le code C lit sur place les objets de Python, au prix d'un binaire par version de Python (sauf avec la
  limited API).
- **Le prix de Cesia**, 114 ns, est surtout celui de l'appel d'une native depuis un programme Cesia, pas celui de
  `Cesia_v1` : la fonction Cesia `Echo4` qui enveloppe la native, le stub (le petit morceau de code qui fait le pont), le
  compte des arguments, le guard (la vérification) qui change une exception en panic, et la conversion des 4 arguments
  et du résultat (environ 20 ns, mesurées à part). Fabriquer et lire la map par `Cesia_v1` coûte 25 ns de plus que le code
  de Cesia lui-même (mesure 1).
- **La JNI de Java** paie 165 ns parce que `NewObject` appelle le constructeur de l'enregistrement depuis C, un appel du
  code natif qui revient dans Java.
- **Node-API** paie 1,3 µs : chaque `napi_set_named_property` fabrique la clé de la propriété à partir d'une chaîne C et
  passe par les handles de V8, alors qu'un objet fait en JavaScript est fabriqué en ligne par le JIT de V8 en 19 ns.

Comment ces nombres ont été mesurés : sur une seule machine, un Intel Core i7-4720HQ (4 cœurs, 8 threads, 2,6 GHz) sous
Linux, en builds de release (compilés comme pour une version publiée), chaque exécution sous un lock qui tient à l'écart
les autres benchmarks (les programmes de mesure) de la machine ; la boucle hôte et la boucle native alternées par tour, les
systèmes alternés par processus ; 40 tours d'un million d'appels chacun. Chaque nombre est une médiane, et chaque prix la
médiane des différences par tour avec son intervalle à 95 %, par bootstrap (un rééchantillonnage des mesures). La mesure 1
est un programme OCaml qui charge un vrai moteur, construit contre `cesia_v1.cmi` seul, et le compare aux mêmes maps
fabriquées et lues par le code de Cesia lui-même, les hashes étant calculés une fois des deux côtés.

## La suite

Vos packages peuvent apporter du code natif. Le dernier chapitre, [Un vrai programme](project.md), assemble les chapitres :
un petit service web sur SQLite, avec ses tests, de `cesia new` à un serveur qui tourne.
