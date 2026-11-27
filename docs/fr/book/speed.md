# Vitesse

Dans ce chapitre, vous voyez comment Cesia rend un programme rapide sans votre aide, ce qu'il rend rapide, et comment le
voir.

Cesia démarre tout de suite et exécute un programme dans son [interpréteur](glossary.md#interpreter-and-jit). Pendant
que le programme tourne, les parties qui tournent souvent, les fonctions et les boucles hot, deviennent du code machine :
c'est le JIT (le just-in-time compiler, qui compile pendant que le programme tourne). Vous n'écrivez rien pour cela, et
un [type](types.md) ne rend jamais le code plus rapide : le JIT trouve lui-même les types, dans ce que fait le programme.
Les résultats, les erreurs et les limites sont les mêmes que ceux de l'interpréteur, jusqu'au dernier chiffre. Le JIT
tourne sur x86-64, sous Linux, macOS et Windows ; sur arm64, comme les puces d'Apple, il est éteint pour l'instant, et
les programmes tournent dans l'interpréteur, avec les mêmes résultats.

Une fonction qui donne un nombre est *hot* (chaude : elle tourne assez souvent pour être compilée) après 1 000 appels, et
une boucle après 10 000 à 20 000 tours : [Comment Cesia fonctionne](internals.md#le-jit) dit exactement quand, quelle
sorte de JIT c'est, comment il parie sur les types et comment il rend la main à l'interpréteur quand un pari échoue.

## Ce qui devient du code machine

- Les boucles sur des nombres, et les arrays (des suites de valeurs lues par leur numéro), de floats (des nombres à
  virgule), d'entiers ou de valeurs, lus et écrits par index : un produit sparse sur des listes de numéros de lignes, un
  histogramme, une permutation suivie.
- Dans une boucle, les petits arrays de floats, jusqu'à 15 cellules, faits et travaillés cellule par cellule, comme
  l'état d'une équation dans `y + h * f(t, y)` : ils ne sont jamais faits pendant que la boucle tourne, et une fonction
  qui en donne un, comme `f` ici, est inlinée (son corps mis à la place de l'appel).
- Les fonctions sur des nombres qui s'appellent entre elles, comme dans une récursion.
- Les fonctions qui donnent n'importe quelle valeur, appelées depuis une boucle ou une récursion : un test qui boucle et
  donne un Bool, comme `isPrime(k)` dans `for k in 1..n`, une recherche qui donne un nombre ou `missing`, une récursion
  qui fait des maps, comme le montre [Comment Cesia fonctionne](internals.md#les-versions-qui-donnent-des-valeurs).
- Dans une boucle, les maps (des valeurs rangées sous des clés) et les structs (des valeurs dont les champs sont déclarés
  une fois) : lire leurs champs, calculer avec eux, en créer de nouvelles, les ranger dans une liste.
- Dans une boucle, l'appel d'une fonction gardée dans une variable, comme `f(x)` où `f` vient d'une liste, ou `f()` sans
  argument : le code machine teste les fonctions que l'appel a rencontrées, quatre au plus, et lance celle qu'il trouve,
  comme le montre [Comment Cesia fonctionne](internals.md#les-appels-à-travers-une-valeur) ; une fonction qu'une cell ou
  le prompt définit de nouveau avec le même code est la même pour lui.
- Les fonctions entières, comme les handlers (les fonctions qui traitent une requête) des routes d'un serveur, sans
  pari : leurs champs, et les clés écrites dans le code de `dict.Get`, `dict.Has` et `dict.GetOr`, lus à travers des
  inline caches (des caches posés au site même de la lecture), leurs tests et calculs de valeurs, leurs textes faits de
  morceaux, `text.ByteLength`, et la frame (la place de ses variables) d'une closure (une fonction qui garde des
  variables d'ailleurs), comme le montre [Comment Cesia fonctionne](internals.md#les-versions-entières-sans-pari). Ce que le code
  machine ne sait pas y faire, il l'appelle à travers OCaml, donc une telle fonction n'est du code machine que si elle
  calcule assez entre ces appels ; dans une boucle, les clés et les longueurs en cache n'appellent rien : `dict.Has`
  d'une clé dans une boucle prend 5 ns par appel au lieu de 54.
- Une variable d'un module dont le nombre change sous le code machine, comme celui d'un slider que [cells.Set] donne en
  place : lue dans un slot à chaque lancement, si bien que le code reste pour chaque nouveau nombre.
- `random.Float()`, le pas de son générateur fait sur place, les mêmes nombres que ceux de l'interpréteur dans le même
  ordre.

Un produit sparse (sur une matrice presque toute faite de zéros), sa matrice en colonnes (CSC : les lignes et les
valeurs de chaque colonne, l'une après l'autre, et l'endroit où commence chaque colonne), est fait de deux boucles sur des
listes d'entiers : `for j in 1..n` sur les colonnes, et à l'intérieur `for q in colptr[j]..colptr[j + 1] - 1` sur les
non-zéros de la colonne `j`, qui ajoute `vals[q] * x[j]` à `y[i]` pour la ligne `i = rowidx[q]`. Une fois hot, il prend
2,8 ns par non-zéro : 1,25 ms pour les 448 800 non-zéros d'une matrice de Poisson 2-D de 300 × 300 points, contre
4,9 ns pour le produit d'Octave et 1,2 ns pour celui de scipy (médianes de 21 runs). La boucle de scipy est du C qui lit
chaque ligne comme un entier de 32 bits, 12 octets par non-zéro contre 16 pour Cesia, et ne vérifie aucune ligne par
rapport à la taille de `y`, là où Cesia les vérifie toutes, pour qu'une mauvaise ligne soit une erreur à sa ligne,
jamais une écriture hors de l'array. Les vérifications de `x[j]`, `colptr[j]` et `colptr[j + 1]` sont faites une seule
fois, avant les boucles, comme le dit la partie *Ce qu'il produit* de Comment Cesia fonctionne.

Cette boucle sur une liste de structs tourne en code machine dès qu'elle est hot, environ quinze fois plus vite que dans
l'interpréteur : `bench/real/particles.ce`, une boucle du même genre sur 2 000 particules, avec la gravité, des murs et
un sol, prend 49 ms contre 811 ms sans le JIT, les médianes de 11 et de 5 runs (exécutions) sur la machine
d'[À côté des géants](#à-côté-des-géants) :

```cesia
use std/list

struct Particle { X, V }

defn move(n, steps)
  ps = list.Fill(0, n)
  for i in 1..n
    ps[i] = Particle(i * 1.0, 0.5)
  end
  for s in 1..steps
    for i in 1..n
      p = ps[i]
      ps[i] = Particle(p.X + p.V * 0.01, p.V)
    end
  end
  ps[n].X
end

move(1000, 300) --> 1001.4999999999986
```

Le JIT parie sur ce qu'il a vu : que `p` est une `Particle`, que `p.X` tient un float. Quand un pari échoue, par exemple
si un champ tient un texte, le programme continue dans l'interpréteur à partir de cette ligne, puis la boucle revient au
code machine : la réponse est la même, un peu plus tard. Tant que les paris tiennent, `p` n'est jamais construite : le
code machine garde ses deux floats dans des registres (les petites mémoires du processeur lui-même, où il calcule), et
écrit la nouvelle `Particle` à la place de l'ancienne, que rien d'autre ne tient, comme le montre
[Comment Cesia fonctionne](internals.md#ce-quil-produit).

## Ce qui reste dans l'interpréteur

- Les appels aux fonctions des packages (du code groupé sous un nom) écrits en OCaml, comme [text.Split] ou
  [json.Parse], quand ils viennent trop souvent pour ce que calcule le code autour : le code machine les appelle à
  travers OCaml, pour environ 100 ns de plus que l'interpréteur, donc une boucle faite seulement de tels appels reste
  interprétée ; ceux des fonctions qui attendent, comme sur le réseau, le restent toujours
  ([Comment Cesia fonctionne](internals.md#le-code-machine-qui-appelle-ocaml)). Les handlers d'un serveur, qui appellent
  surtout de telles fonctions, se compilent maintenant, et restent interprétés pour cette raison.
- Les boucles sur les éléments d'une liste, `for x in xs`, et un appel à travers une valeur qui a rencontré cinq
  fonctions ou plus, ou une closure appelée depuis le code machine, qui passent par OCaml.
- Dans une boucle, une instruction à l'intérieur d'un if qu'il ne sait pas faire, comme le `return` d'une erreur ou un
  `io.Print` : cette instruction passe à l'interpréteur chaque fois qu'elle tourne, et le reste de la boucle reste du
  code machine.
- Sous un debugger (un programme qui exécute le vôtre et peut l'arrêter, pour montrer ses variables), une fonction dont
  le code contient un breakpoint (une ligne où le programme doit s'arrêter), et le code que vous parcourez pas à pas :
  tout le reste demeure du code machine, comme le dit le chapitre [Le prompt et le debugger](debug.md#vitesse).
- Au prompt (la ligne où vous tapez du code à côté du programme qui tourne), sous `--watch` et sous un debugger, le code
  qui se sert de ce que donnent les fonctions du programme lui-même : une telle fonction peut être définie de nouveau
  pendant qu'un appel à elle tourne, avec des résultats d'un autre type, et ce code les prend aussitôt.

## Le voir

`CESIA_JIT_SHOW=1` affiche ce qui est devenu du code machine, et pourquoi le JIT ne s'est pas chargé ; `--no-jit` lance
l'interpréteur seul, pour comparer :

```bash
CESIA_JIT_SHOW=1 cesia run particles.ce
cesia run --no-jit particles.ce
```

Voir [Variables d'environnement](env.md) et [Commandes](commands.md#cesia-run).

## À côté des géants

Les mêmes programmes en Cesia, Python, Node, Java, Go, OCaml, Lua et LuaJIT, sur une seule machine : un Intel Core
i7-4720HQ de 2015, 8 cœurs logiques, Linux 7.2, mesurés le 2026-11-19 pendant que d'autres travaux tournaient dessus
(charge de 1,0 à 4,6). Les versions : Python 3.14.10, Node 26.13 (V8), Java 21.0.13 (OpenJDK, HotSpot), Go 1.26.3, OCaml
5.5.0 (`ocamlopt`, sans flambda), Lua 5.5.1, LuaJIT 2.1, et Cesia 1.2.0+dev dans son build `release` (la version compilée avec toutes
ses optimisations).

**La méthode.** Chaque programme fait le même travail et affiche la même réponse, vérifiée à chaque run. Les runs de tous
les langages alternent, un de chacun à tour de rôle, pour qu'une minute plus lente de la machine tombe sur tous. Chaque
temps est celui du processus entier, de son début à sa fin, démarrage compris : un programme Java ou Node paie 25 à
40 ms avant sa première ligne. Chaque case donne la *médiane* de 101 runs, celui du milieu, et après elle le *confidence
interval* à 95 % de cette médiane : l'intervalle qui contient la vraie médiane avec une probabilité d'au moins 95 %,
ici 95,4 %, tiré des rangs des runs triés, le 41e et le 61e, sans rien supposer de la façon dont les temps se
répartissent. Un intervalle large signale une mesure bruitée. Les programmes sont dans `bench/` du dépôt : `NAME.ce`,
`.py`, `.js`, `.lua`, `.go`, `.java` et `ocaml/NAME.ml`.

### Le démarrage

Un programme qui affiche `1`, 101 runs de chacun, alternés :

| | Médiane | Intervalle à 95 % |
|---|---:|---:|
| `/usr/bin/true`, rien | 0,53 ms | 0,52 à 0,54 |
| Lua | 0,88 ms | 0,85 à 0,90 |
| LuaJIT | 1,00 ms | 0,98 à 1,01 |
| OCaml, natif | 1,08 ms | 1,06 à 1,09 |
| Go | 1,32 ms | 1,29 à 1,35 |
| **Cesia** | **2,68 ms** | 2,67 à 2,70 |
| Python | 13,88 ms | 13,86 à 13,94 |
| Java | 23,99 ms | 23,94 à 24,14 |
| Node | 37,24 ms | 35,93 à 38,29 |

```cesia allow=read,write
use std/plot
starters = ["true", "Lua", "LuaJIT", "OCaml", "Go", "Cesia", "Python", "Java", "Node"]
startMs = [0.53, 0.88, 1.00, 1.08, 1.32, 2.68, 13.88, 23.99, 37.24]
startup = plot.Of([plot.Bars(starters, startMs)], title = "Start-up: a program that prints 1, median of 101 runs",
  y = "milliseconds", size = [640, 340])
plot.Save(startup, "speed-startup.svg") -->
```

Mesuré de nouveau le 2026-11-09 : 2,84 ms pour le binaire d'avant le changement qui ne fait grandir son young heap (la
petite partie de la mémoire où naissent les nouvelles valeurs, vidée souvent) que quand un programme en a besoin,
alterné dans les mêmes runs. Cesia démarre 5 fois plus vite que Python, 9 fois plus vite que Java et 13 fois plus vite
que Node. Un programme compilé en Go ou en OCaml, ou Lua, démarre en la moitié à un tiers de son temps : Cesia porte dans un
seul binaire tout son runtime (ce qui accompagne un programme pendant qu'il tourne), sa bibliothèque standard et son
compilateur, 22 247 endroits de son code que le garbage collector d'OCaml (la partie qui libère la mémoire que plus rien
n'utilise) doit connaître, contre 322 dans le programme d'OCaml lui-même, et le système doit corriger les adresses de
ses données à chaque démarrage, comme le montre [Comment Cesia fonctionne](internals.md#le-démarrage).

Le démarrage avait grandi depuis Cesia 1.1.0, de 0,11 ms : un bug, puisque rien ne doit ralentir le démarrage, corrigé
depuis. Chaque démarrage joignait les natives de `std/` par package en cherchant dans une liste pour chaque groupe, avec
le compare polymorphe d'OCaml (la comparaison qui marche sur toute valeur en parcourant sa structure, plus lente qu'une
comparaison de textes), et construisait trois tables, celles de `text.Fold`, des puissances de dix de `json.Parse` et
des chiffres d'un entier : 243 000 instructions en tout ; la jointure se fait maintenant en un seul passage sur une
table, et les tables sont des constantes du binaire. Construit de la même façon et lancé en alternance, 101 tours de
50 runs de chacun le 2026-11-19, chaque tour la médiane de ses 50, la sortie jetée : 1.1.0 affiche `1` en 2,52 ms
(2,51 à 2,53), celui-ci en 2,52 (2,50 à 2,53), et avant la correction 2,63 (2,61 à 2,64). Ce que 1.2.0 ajoute encore au
démarrage, c'est son nouveau code, 22 247 frame descriptors (la description, pour chaque endroit où un appel revient,
des cases de la pile qui tiennent des valeurs) au lieu de 19 746, que le loader (la partie du système qui charge le
programme) reloge et que le runtime range dans sa table : d'après les compteurs du processeur, 180 000 instructions de
plus à cet endroit, et le démarrage fait 2,04 millions d'instructions en tout, contre 2,06 millions pour 1.1.0 et
2,29 millions avant la correction.

Un programme qui utilise des packages écrits en Cesia les lit à son premier run et les garde dans le
[cache des packages chargés](internals.md#le-cache-des-packages-chargés) : à partir du run suivant, un package dont les
fichiers sont les mêmes ne repasse ni par le lexer, ni par le parser, ni par le resolver. Mesuré le 2026-11-12, 21 runs
de chacun, alternés, médianes : `use std/plot` démarre en 5,69 ms contre 9,66 avant, et Cemacs arrive à sa première
image en 36,97 ms contre 52,16. Le premier run, dont les entrées sont écrites une fois qu'il a fini, prend à peu près le
temps qu'il prenait avant : 9,61 et 54,26 ms. Depuis le 2026-11-13, le corps d'une fonction n'est lu dans le cache
qu'à son premier appel : `use std/plot` démarre alors en 4,03 ms contre 5,74 avec chaque corps lu au chargement, et
Cemacs avec ses cells et son IDE, de `bin/cemacs` jusqu'à sa première image, en 50,62 ms contre 61,12, 21 runs de
chacun, alternés, médianes. Depuis le 2026-11-19, une fonction qui ne rend aucun nombre n'est inférée que quand elle
tourne, un array du cœur qui grandit ne vide plus le minor heap d'OCaml, et une entrée est vérifiée par XXH64 au lieu de
BLAKE2b : un premier [plot.Svg] d'une ligne, du début du programme à sa fin, prend 6,99 ms contre 10,29, une session de
cells qui en dessine une 7,74 contre 11,54, et `use std/plot` 4,08 contre 4,38, 21 runs de chacun, alternés, médianes
([Comment Cesia fonctionne](internals.md#le-cache-des-packages-chargés)).

### Le calcul

En millisecondes, la médiane et l'intervalle à 95 % de 101 runs ; la ligne `dyn` mesurée de nouveau, de la même façon,
une fois son ralentissement corrigé, plus bas :

| Programme | Cesia | Cesia, sans JIT | Python | Node | Java | Go | OCaml | Lua | LuaJIT |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| `fib` | **59** (59–59) | 454 (452–455) | 1 439 (1 435–1 443) | 171 (170–171) | 70 (70–70) | 50 (49–50) | 52 (52–52) | 694 (693–696) | 95 (94–97) |
| `mandel` | **61** (61–62) | 471 (470–473) | 2 624 (2 615–2 639) | 91 (90–91) | 81 (81–81) | 52 (52–52) | 57 (57–57) | 434 (433–435) | 55 (55–55) |
| `matmul` | **45** (45–45) | 980 (976–983) | 4 720 (4 701–4 756) | 96 (95–97) | 82 (82–82) | 33 (33–34) | 60 (60–60) | 832 (831–835) | 87 (87–88) |
| `structs` | **38** (38–40) | 614 (611–616) | 1 722 (1 715–1 732) | 168 (167–169) | 110 (109–111) | 9 (9–9) | 30 (30–30) | 1 533 (1 521–1 537) | 397 (396–399) |
| `dyn` | **58** (58–58) | 685 (683–690) | 1 370 (1 363–1 381) | 165 (164–165) | 96 (96–96) | 28 (28–28) | 68 (67–68) | 716 (715–717) | 57 (57–57) |
| `maps` | **255** (254–255) | 250 (249–250) | 399 (399–400) | 528 (524–531) | 247 (244–248) | 268 (265–271) | 496 (493–500) | 788 (784–794) | 307 (306–309) |

Les mêmes médianes sur une échelle logarithmique, où chaque puissance de dix prend la même longueur, chaque langage un peu
à côté des autres pour chaque programme :

```cesia allow=read,write
programs = ["fib", "mandel", "matmul", "structs", "dyn", "maps"]
langs = [
  {Name: "Cesia", Ms: [59, 61, 45, 38, 58, 255], Shape: "circle", Color: "#3a5ad9"},
  {Name: "Cesia, no JIT", Ms: [454, 471, 980, 614, 685, 250], Shape: "circle", Color: "#9aaae8"},
  {Name: "Python", Ms: [1439, 2624, 4720, 1722, 1370, 399], Shape: "square", Color: "#000000"},
  {Name: "Node", Ms: [171, 91, 96, 168, 165, 528], Shape: "triangle", Color: "#000000"},
  {Name: "Java", Ms: [70, 81, 82, 110, 96, 247], Shape: "diamond", Color: "#000000"},
  {Name: "Go", Ms: [50, 52, 33, 9, 28, 268], Shape: "cross", Color: "#000000"},
  {Name: "OCaml", Ms: [52, 57, 60, 30, 68, 496], Shape: "plus", Color: "#000000"},
  {Name: "Lua", Ms: [694, 434, 832, 1533, 716, 788], Shape: "square", Color: "#999999"},
  {Name: "LuaJIT", Ms: [95, 55, 87, 397, 57, 307], Shape: "triangle", Color: "#999999"}]
dots = [plot.Points([p + (k - 5) * 0.07 for p in 1..6], langs[k].Ms, label = langs[k].Name, shape = langs[k].Shape,
  color = langs[k].Color, size = 7) for k in 1..9]
computing = plot.Of(dots, title = "Six programs: milliseconds, median of 101 runs", y = "milliseconds (log scale)",
  yscale = "log", xticks = 1..6, xlabels = programs, size = [640, 400])
plot.Save(computing, "speed-computing.svg") -->
```

Mesuré de nouveau le 2026-11-09, après que les feuilles d'une récursion (ses derniers appels, qui ne rappellent plus la
fonction) ont été testées à leur appel et que le JIT a donné à MIR (le petit compilateur qui produit le code machine de
Cesia) deux cinquièmes de lignes en moins à compiler ([Comment Cesia fonctionne](internals.md#ce-quil-produit)) : la
veille, `fib` prenait 74 ms, `matmul` 47, `structs` 49, `dyn` 57, et les autres lignes restaient à quelques pour cent de
celles d'aujourd'hui.

Ce que fait chaque programme : `fib` est `fib(35)`, environ 30 millions d'appels récursifs sur des entiers ; `mandel`
une boucle de floats sur $600 \times 400$ points ; `matmul` le produit de deux matrices $300 \times 300$ lues par index ;
`structs` 1 000 enregistrements de quatre floats, chacun refait à chacun des 5 000 pas ; `dyn` 10 millions d'appels à
travers une liste de deux fonctions, sur des valeurs de sortes mêlées ; `maps` une map de 500 000 clés de texte, écrite
puis lue.

**Là où Cesia gagne.** Sur les boucles de nombres et sur la récursion, le JIT place Cesia devant Java, Node et LuaJIT :
`matmul` tourne en environ la moitié du temps de Java, de Node et de LuaJIT, et devant OCaml, `fib` en 59 ms contre 70
pour Java et 95 pour LuaJIT, et `mandel` devant Java et Node. Face à Python, le langage d'où viennent la plupart de ses
utilisateurs, Cesia est 24 fois plus rapide sur `fib`, 43 fois sur `mandel` et 105 fois sur `matmul` ; face à Lua, 7 à
40 fois, et 3 fois sur `maps`. Sur `dyn`, il est devant Node, Java et OCaml, 58 ms contre 165, 96 et 68, et 24 fois plus
rapide que Python. Sur `structs`, il est devant Java, 38 ms contre 110, devant Node, 168, et devant LuaJIT, 397. Sur
`maps`, il est devant tous les langages sauf Java, Go compris : 255 ms contre 268.

**Là où un géant gagne, et pourquoi.**

- **Go gagne toutes les lignes sauf `maps` ; OCaml gagne `fib`, `mandel` et `structs` ; LuaJIT gagne `mandel` et
  `dyn` ; Java gagne `maps`.** Go et OCaml compilent tout le programme en code machine avant qu'il tourne, chaque type
  connu, et démarrent en 1,1 à 1,4 ms. Un appel de `fib` coûte
  maintenant à Cesia 5,5 cycles du processeur, contre 5,9 à Go (selon les compteurs du processeur : le coût d'un appel de
  plus) : ce qui garde Go 9 ms devant, c'est le coût fixe, le démarrage (2,68 ms contre 1,32), le chargement du JIT,
  0,65 ms, et la compilation par MIR, 3,4 ms ([Comment Cesia fonctionne](internals.md#ce-que-coûte-sa-fabrication)). La boucle
  intérieure de `mandel` attend sa chaîne de floats, une soustraction, une addition et une multiplication d'un tour au
  suivant, 11 cycles, le plancher de tout langage : Cesia et Go prennent tous deux 3,7 à 3,8 ns par tour, et les 10 ms
  qui les séparent sont encore le coût fixe ; LuaJIT, 55 ms, trace la boucle (il compile le chemin qu'elle prend) et
  démarre en 1,0 ms. La boucle intérieure de `matmul` tourne elle aussi à la vitesse de Go,
  1,15 ns par pas ; ses deux boucles coûtent chacune 3 à 5 ms de compilation à MIR.
- **`structs` : OCaml prend 0,77 fois le temps de Cesia, Go moins d'un quart.** Une map de quatre floats les garde maintenant
  comme des doubles (le nombre machine de 64 bits, nu, sans bloc de mémoire autour), et le JIT ne construit jamais la
  map qu'il lit dans la liste : il garde ses quatre doubles dans des registres et écrit les nouveaux à la place des
  anciens, que rien d'autre ne tient ([Comment Cesia fonctionne](internals.md#ce-quil-produit)). Un pas n'alloue rien (il
  ne demande aucune mémoire) : 219 ms, puis 186, 49, 46, et 38 le 2026-11-19. Ce qui restait à 46 ms, selon les
  compteurs du processeur, environ 60 instructions et 24 cycles par pas contre 19 et 5 pour Go : chaque pas lit dans la liste l'adresse de la map et vérifie sa sorte, ses clés,
  qu'elle n'est tenue que par un seul nom et que son stockage contient des doubles, là où l'array de Go contient les
  floats des enregistrements eux-mêmes, à des places connues ; et environ 10 ms de coût fixe, le démarrage du processus,
  les premiers pas dans l'interpréteur et la compilation de la boucle. OCaml construit un nouvel enregistrement de 5 mots
  à chaque pas, sans aucune vérification : 30 ms.
- **`dyn` : Go prend moins de la moitié du temps, LuaJIT 2 % de moins ; Cesia est devant Java, OCaml et Node.** `total`
  vient d'un appel à travers une fonction gardée dans une liste, que l'inférence (l'analyse qui trouve les types sans
  qu'on les écrive) ne peut pas typer ; le JIT le garde comme un float dans un registre pendant toute la boucle, et
  l'appel devient un test des deux fonctions qu'il a rencontrées, dont le code est recopié sur place (inlined), le
  *polymorphic inline cache* (la mémoire, à l'endroit de l'appel, des fonctions qu'il a déjà rencontrées) de [Comment
  Cesia fonctionne](internals.md#les-appels-à-travers-une-valeur) : 714 ms, puis 182, 114, 57, 55 le 2026-11-08, 64 le
  2026-11-19, et 58 une fois corrigé un bug trouvé ce jour-là : quand aucune des deux fonctions ne correspondait, le run
  retournait à l'interpréteur avec le fuel (le compte des pas qu'il peut encore faire avant de laisser la main) du début
  de l'instruction, et l'instruction recopiait donc son fuel à son début à chaque tour, alors qu'aucun pas ne tournait
  sur ce chemin. Cesia 1.1.0, construit de la même façon et lancé en alternance avec celui-ci, 101 runs de chacun, prend
  55,4 ms (55,3 à 55,5) contre 58,9 (58,5 à 59,1) : l'appel teste maintenant la fonction par l'identité de son code,
  deux lectures en mémoire là où 1.1.0 en comparait une avec un registre, pour qu'une fonction qu'une session définit de
  nouveau avec le même code garde son code machine, environ 1,5 ms ; et la boucle tourne au niveau 1 de MIR pendant ses
  7 premières ms, jusqu'à ce que le niveau 2 arrive d'un autre cœur. Le pas de Go est un appel de code tout en floats,
  sans test de sorte et sans compte des pas.
- **`maps` : Java prend 3 % de temps en moins ; Cesia est devant tous les autres, Go compris.** Une grande map
  que tient un seul nom est maintenant une hash table (un array de slots où le hash d'une clé, un nombre calculé à partir
  d'elle, désigne la place où la chercher) rangée dans l'ordre d'insertion, la disposition de Python, et ne devient le
  trie (un arbre où chaque niveau choisit sa branche d'après quelques bits du hash) [CHAMP](glossary.md#champ) des
  [persistent](glossary.md#persistent-data-structure) maps (qui gardent leur ancienne version quand elles changent) qu'une
  fois partagée et modifiée ([Comment Cesia fonctionne](internals.md#maps--une-hash-table-puis-un-hash-trie)) : 815 ms
  avant, 275 avec la table, 258 depuis que chaque clé `"key$k"` est construite en une copie au lieu de trois
  ([Comment Cesia fonctionne](internals.md#lexécution--des-closures-comme-code)), en 68 MB, contre 70 MB pour Python, 51 pour Go et
  148 pour Java. Les compteurs du processeur disent pourquoi : 3,1 cache misses (des lectures qui ne trouvent pas leur
  donnée dans le cache, la mémoire rapide du processeur, et doivent aller la chercher plus loin) par opération dans son
  dernier niveau de cache, là où le trie en faisait 18,7, contre 3,7 pour Python et 4,3 pour Go. Les 247 ms de Java
  viennent d'un garbage collector qui travaille sur les autres cœurs et d'un hash gardé dans chacune de ses chaînes ; et
  la boucle de `maps`, qui construit un texte à chaque tour, reste dans l'interpréteur de Cesia : sa part est d'environ
  un dixième du temps, et du code natif appellerait OCaml pour le hash, la table et le texte, chaque appel coûtant plus
  que ça ([Comment Cesia fonctionne](internals.md#ce-qui-reste-dans-linterpréteur)). Le prix de la table : le premier [dict.Put]
  sur une grande map construite sur place la change en trie, environ 0,25 s pour un million de clés, une seule fois.
- **Node et Java démarrent lentement mais tournent vite** : leurs JIT compilent davantage, et plus tard, avec plus de
  temps à y consacrer.

### Les fibers à côté des goroutines, d'async et des virtual threads

100 000 tâches qui se mettent en attente devant une même porte, puis finissent toutes dès qu'elle s'ouvre : les fibers
de Cesia (des fonctions qui tournent à côté des autres dans le même programme, menées par le langage plutôt que par le
système), les goroutines de Go, les fonctions `async` de Node sur une seule promise (une valeur qu'un calcul donnera plus
tard), les tâches `asyncio` de Python sur un événement, les virtual threads de Java 21 (ses threads légers, menés par la
machine virtuelle de Java) sur un latch (un compteur qui libère d'un coup tous ceux qui l'attendent quand il tombe à
zéro), et les coroutines de Lua, qui n'ont pas de scheduler (la partie qui choisit quelle tâche tourne ensuite),
relancées par une boucle. 101 runs de chacun, alternés, le 2026-11-19 ; le temps par tâche est celui de 100 000 tâches
moins celui d'une seule, divisé par 100 000, et la mémoire par tâche le pic de mémoire du processus avec 100 000 tâches
moins celui avec une seule, divisé par 100 000 :

| | 100 000 tâches | Intervalle à 95 % | Par tâche | Mémoire par tâche |
|---|---:|---:|---:|---:|
| Coroutines de LuaJIT | 61 ms | 60 à 61 | 0,6 µs | 0,4 KB |
| Goroutines de Go | 120 ms | 120 à 121 | 1,2 µs | 2,6 KB |
| Coroutines de Lua | 133 ms | 133 à 134 | 1,3 µs | 1,0 KB |
| Node `async` | 169 ms | 167 à 170 | 1,3 µs | 1,3 KB |
| **Fibers de Cesia** | **321 ms** | 320 à 322 | **3,1 µs** | **2,2 KB** |
| Python `asyncio` | 1 075 ms | 1 072 à 1 078 | 10,0 µs | 1,4 KB |
| Virtual threads de Java | 1 725 ms | 1 692 à 1 751 | 16,8 µs | 2,0 KB |

```cesia allow=read,write
tasks = ["LuaJIT", "Go", "Lua", "Node", "Cesia", "Python", "Java"]
perTask = [0.6, 1.2, 1.3, 1.3, 3.1, 10.0, 16.8]
memory = [0.4, 2.6, 1.0, 1.3, 2.2, 1.4, 2.0]
fibers = plot.Of([plot.Points(perTask, memory), plot.Text(perTask, memory, tasks)],
  title = "A task that starts, parks and ends: its time and its memory", x = "microseconds per task (log scale)",
  y = "KB per task", xscale = "log", xlim = [0.4, 30], ylim = [0, 3], size = [640, 360])
plot.Save(fibers, "speed-fibers.svg") -->
```

Une fiber de Cesia prend le tiers du temps d'une tâche Python et le cinquième de celui d'un virtual thread de Java pour
démarrer, se mettre en attente et finir, et 2,6 fois celui d'une goroutine ; avec sa tâche, elle prend 2,2 KB, moins que
les 2,6 KB d'une goroutine, et plus que les 2,0 KB d'un virtual thread, les 1,4 de Python et les 1,3 de Node. Elle
prenait 3,4 µs et 2,1 KB le 2026-11-09, et 4,3 µs et 2,5 KB jusqu'au 2026-11-08 : ses
stacks (ses piles de valeurs) commencent maintenant à 8 slots (des places de taille fixe), et non 16, son corps et sa
fin ne créent aucune closure (une fonction qui garde les noms de l'endroit où elle a été créée), une fiber qui attend
une tâche y laisse sa propre fonction de réveil, et un seul handler (le code qui reçoit une fiber quand elle s'arrête
pour attendre), créé une fois, sert toutes les fibers. Chaque fiber a trois stacks à elle, pour les valeurs, les entiers
et les floats, à côté de sa stack OCaml : elles doublent quand elles sont pleines, comme la stack d'une goroutine
commence à 2 KB et est recopiée dans une plus grande. Environ 1 KB des 2,2 est cette stack OCaml : OCaml démarre une
fiber à 64 mots et la double au premier appel de l'interpréteur en elle (gdb compte un agrandissement par fiber), si
bien qu'une fiber en attente tient 128 mots. Ce qu'une goroutine ne paie pas, c'est le garbage collector : celui d'OCaml
copie chaque fiber vivante hors de son young heap et la marque de nouveau à chaque cycle majeur, ce qui fait l'essentiel
du temps d'une fiber ici. Les goroutines de Go tournent aussi en parallèle sur tous les cœurs ; les fibers de Cesia
tournent sur un seul, et `--workers` donne tous les cœurs à un serveur, comme le montre [HTTP](http.md#tous-les-cœurs).

### Textes et fichiers

Un texte de 100 MB, 2,46 millions de lignes de source OCaml : lu en entier depuis un [page cache](glossary.md#page-cache)
warm (la copie des fichiers que le système garde en mémoire après les avoir lus, ici qui tient déjà ce fichier), un mot
cherché jusqu'à la fin en respectant la casse et en l'ignorant, ses lignes jointes de nouveau, et 16 MB écrits, avec et
sans [fsync](glossary.md#fsync) (l'appel système qui attend que les octets écrits soient vraiment sur le disque).
Chaque mesure est prise dans le programme, autour de la seule opération, 7 runs de chaque langage alternés ; la médiane,
et le plus bas et le plus haut des 7, qui encadrent la médiane avec une probabilité de 98,4 %. En millisecondes :

| | Cesia | Python | Node | Go |
|---|---:|---:|---:|---:|
| lire le fichier, ses octets | **22** (22–23) | 20 (19–25) | 19 (19–22) | 18 (17–20) |
| le lire comme de l'UTF-8 vérifié | | 56 (51–80) | 47 (45–51) | |
| chercher un mot, exact | **39** (38–40) | 46 (44–48) | 49 (49–52) | 7 (6–19) |
| chercher un mot, casse ignorée | **41** (40–44), `fold` | 797 (761–906), `re.I` | 26 (25–28), `/i` | 3 296 (3 224–3 562), `(?i)` |
| une copie en minuscules, puis une recherche | 317 (314–366) | 100 (95–116) | 74 (73–80) | 186 (183–295) |
| joindre les 2,46 millions de lignes | 218 (217–223) | 59 (58–88) | 142 (137–151) | 50 (49–53) |
| écrire 16 MB | **3,5** (3,5–4,0) | 6,0 (5,8–7,0) | 7,2 (6,5–8,9) | 2,6 (2,4–3,1) |
| écrire 16 MB, puis fsync | **44** (43–75) | 60 (47–105) | 50 (45–91) | 44 (41–60) |

Les mêmes médianes sur une échelle logarithmique ; une case laissée vide dans le tableau est un `NaN` (*not a number*,
une valeur qui n'est pas un nombre), que [plot.Points] laisse de côté :

```cesia allow=read,write
use std/math
operations = ["read", "as UTF-8", "search", "no case", "lowercase", "join", "write", "fsync"]
texts = [
  {Name: "Cesia", Ms: [22, math.Nan, 39, 41, 317, 218, 3.5, 44], Shape: "circle", Color: "#3a5ad9"},
  {Name: "Python", Ms: [20, 56, 46, 797, 100, 59, 6.0, 60], Shape: "square", Color: "#000000"},
  {Name: "Node", Ms: [19, 47, 49, 26, 74, 142, 7.2, 50], Shape: "triangle", Color: "#000000"},
  {Name: "Go", Ms: [18, math.Nan, 7, 3296, 186, 50, 2.6, 44], Shape: "cross", Color: "#000000"}]
textDots = [plot.Points([p + (k - 2.5) * 0.12 for p in 1..8], texts[k].Ms, label = texts[k].Name, shape = texts[k].Shape,
  color = texts[k].Color, size = 7) for k in 1..4]
textTimes = plot.Of(textDots, title = "A text of 100 MB: milliseconds, median of 7 runs", y = "milliseconds (log scale)",
  yscale = "log", xticks = 1..8, xlabels = operations, size = [660, 400])
plot.Save(textTimes, "speed-texts.svg") -->
```

Dans Cesia, [sys.Read] lit les octets dans un seul texte de la taille du fichier, aussi vite que les autres lisent des octets ; il ne
vérifie pas l'UTF-8 (un programme le demande avec [text.IsUtf8], 26 ms de plus), là où Python et Node décodent dans
leurs propres chaînes. [text.ByteFind] avec `fold` ignore la casse aussi vite qu'il cherche en la respectant, 19 fois
plus vite que `re` de Python et 80 fois plus vite que `regexp` de Go, qui font tourner pour cela un moteur général de
recherche de motifs.

**Là où un géant gagne, et pourquoi.** La recherche exacte de Go, 7 ms, est de l'assembleur qui compare 32 octets à la
fois avec les instructions AVX2 du processeur ; le noyau de Cesia, en OCaml seulement, en compare 8 à la fois dans un mot
de 64 bits. Le `/i` de Node, 26 ms, est une regular expression compilée en code machine par V8, qui saute les octets
qui ne peuvent pas commencer une correspondance. Et joindre les lignes prend 3,7 fois moins de temps en Python et 4,4
fois moins en Go : les octets sont copiés à la même vitesse, mais le profil (la mesure de l'endroit où passe le temps)
met l'essentiel du temps de Cesia dans le garbage collector d'OCaml, qui marque de nouveau les 2,46 millions de lignes
vivantes pendant que le programme alloue les 100 MB du résultat, là où Python compte les références et où le garbage
collector de Go tourne sur les autres cœurs. Le temps d'un fsync est celui du disque, le même pour tous.

## Un serveur sous charge

[std/http] contre le module `http` de Node et `net/http` de Go, chacun sur un seul cœur, sur la machine
d'[À côté des géants](#à-côté-des-géants) : le serveur fixé sur le premier cœur, le client de charge sur le deuxième, Go
tenu à un seul cœur par `GOMAXPROCS=1`. Chacun sert les deux mêmes routes (une route envoie les requêtes d'une méthode
et d'un chemin à leur fonction), un tout petit texte et un petit objet JSON, depuis `bench/http.ce`, `bench/http.js` et
`bench/http.go`. `tools/http-bench.sh` a tourné 6 fois, les trois serveurs et le binaire d'avant ce changement à tour de
rôle, l'ordre décalé d'un cran à chaque run, chaque charge pendant 3 secondes ; chaque case donne la médiane des 6 runs,
et entre parenthèses le plus bas et le plus haut, qui encadrent la médiane avec une probabilité de 96,9 %. Aucune
requête n'a échoué, dans aucun run.

| Charge | Cesia | Node | Go |
|---|---:|---:|---:|
| petite route, 10 connexions gardées ouvertes | **66 935** (64 769–68 234) | 44 398 (43 057–45 727) | 66 676 (65 570–67 089) |
| petite route, 100 connexions gardées ouvertes | **64 070** (56 386–65 963) | 45 619 (42 014–51 156) | 66 140 (62 414–67 089) |
| petite route, 1 000 connexions gardées ouvertes | **36 200** (34 482–36 992) | 42 235 (38 249–45 212) | 54 369 (53 777–54 619) |
| route JSON, 100 connexions gardées ouvertes | **47 728** (46 565–50 264) | 41 228 (38 300–45 993) | 52 330 (51 391–52 859) |
| une nouvelle connexion par requête, 10 | **23 024** (22 616–23 298) | 12 066 (11 902–12 184) | 20 578 (19 774–20 728) |
| une nouvelle connexion par requête, 100 | **22 973** (21 888–23 297) | 13 116 (12 663–13 791) | 20 188 (19 267–20 314) |

```cesia allow=read,write
loads = ["tiny 10", "tiny 100", "tiny 1,000", "JSON 100", "new 10", "new 100"]
served = plot.Bars(loads, [[66935, 64070, 36200, 47728, 23024, 22973], [44398, 45619, 42235, 41228, 12066, 13116],
  [66676, 66140, 54369, 52330, 20578, 20188]], label = ["Cesia", "Node", "Go"], color = ["#3a5ad9", "#999999", "#000000"])
server = plot.Of([served], title = "A server on one core: requests per second, median of 6 runs", x = "route, connections",
  y = "requests per second", size = [640, 360])
plot.Save(server, "speed-server.svg") -->
```

Des requêtes par seconde, mesurées le 2026-11-09, le binaire d'avant ce changement alternant dans les mêmes runs : il
répondait à 53 918 et 53 546 requêtes sur la petite route à 10 et 100 connexions, 32 682 à 1 000, et 41 980 sur la
route JSON. Le 99e percentile de la latence, le temps en dessous duquel 99 requêtes sur 100 reçoivent leur réponse, à
100 connexions gardées sur la petite route : Cesia 3,2 ms, Node 3,3 ms, Go 3,2 ms ; à 1 000 : Cesia 34,5 ms, Node
17,7 ms, Go 27,3 ms. Une connexion inactive prend 2,3 KB dans Cesia, 2,5 KB dans Node et 18 KB dans Go, et un serveur au
repos 15 MB, 54 MB et 10 MB.

Cesia répond à autant de petites requêtes que Go sur un cœur, et à deux cinquièmes de plus que Node ; sur de nouvelles
connexions, il est le plus rapide des trois ; sur la route JSON, il devance Node d'un sixième, et Go garde un dixième
d'avance : son encodeur est du code compilé, là où le handler de Cesia (la fonction qui traite une requête) et sa
réponse tournent en partie dans l'interpréteur. Le handler de chaque requête tourne dans sa propre fiber, et chacune
agrandissait ses stacks, ce qui demandait à OCaml la taille de son heap (la mémoire où vivent les valeurs) à chaque
agrandissement, un dixième du temps du serveur, jusqu'à ce que des stacks aussi petites soient laissées aux checkpoints
(les moments où l'interpréteur arrête de compter pour regarder le programme)
([Comment Cesia fonctionne](internals.md#ce-quil-sert)).

**Là où un géant gagne, et pourquoi : 1 000 connexions.** Node et Go répondent à plus de requêtes à 1 000 connexions
gardées, et Node tient son 99e percentile à la moitié de celui de Cesia. Un seul cœur fait tourner les 1 000 fibers de
Cesia chacune à son tour : d'après la *loi de Little* (le nombre de requêtes en attente est égal au débit multiplié par
le temps que chacune attend), 1 000 requêtes en attente, servies à 36 200 par seconde, attendent chacune 27,6 ms en
moyenne, si bien que le 99e percentile ne peut pas descendre sous 25 ms avant que le serveur ne réponde à plus de
requêtes, et les requêtes en cours survivent aux minor collections d'OCaml (les passages fréquents du garbage collector
sur le young heap), qui les copient dans le major heap (la grande partie de la mémoire, nettoyée par tranches), sept
fois plus de mots qu'à 100 connexions. Les goroutines de Go prennent d'elles-mêmes tous les cœurs de la machine, et
l'event loop de Node (la boucle unique qui traite les événements l'un après l'autre) ne garde aucune stack par
connexion. `--workers 2` donne deux cœurs à Cesia, et environ 1,5 fois le nombre de requêtes, ce que
`tools/http-gate.sh` vérifie à chaque changement.

```bash
tools/http-bench.sh    # each load against Node, and Go if it is there
tools/http-gate.sh     # the gate that a change to the server must pass
```

`tools/http-bench.sh` fait aussi tourner 10 connexions actives à côté de 10 000 inactives, ce qui donne la mémoire d'une
connexion inactive. `tools/http-gate.sh` lance les charges principales et échoue si une requête échoue, si Cesia répond
à moins de requêtes que Node ou que ses planchers (les nombres minimaux fixés pour chaque charge), si son 99e percentile
dépasse 10 ms, si une connexion inactive prend plus de 4 KB, ou si deux workers (deux processus du même serveur, chacun
sur un cœur) ne donnent pas une fois et demie un seul processus. `HTTP_GATE_SCALE=0.5` divise les planchers par deux
sur une machine plus lente.

### La requête d'un framework à côté des géants

Centauri, un framework (un cadre qui fournit la structure d'une application) de Cesia, répond à `/hello` avec un JSON
d'un champ à travers sa porte, sa session, ses limites, ses shapes et son journal ; [std/http] seul répond à la même
route sans rien autour, comme le font le `net/http` de Go, le `http` de Node et le `HttpServer` du JDK (sur un pool de 4
threads). Mesuré le 2026-11-27, profil `release`, chaque serveur épinglé sur 4 cœurs et le client de charge (256
connexions gardées, 4 threads) sur les 4 autres, 21 mesures de 2 s chacune, l'ordre tourné à chaque tour, pendant que
d'autres travaux tournaient sur la machine (charge 3,0 à 5,2) ; le CPU est celui du serveur sur la mesure, ses threads
ensemble ; la médiane, puis la plus basse et la plus haute :

| Serveur | Requêtes par seconde | Cœurs | Requêtes par seconde par cœur | 99e percentile | Mémoire |
|---|---:|---:|---:|---:|---:|
| Centauri | 14 009 (12 735–14 770) | 0,95 | 14 702 | 29,2 ms | 51 MB |
| Centauri, le binaire de main d'avant | 14 002 (8 205–14 504) | 0,95 | 14 693 | 26,3 ms | 51 MB |
| `std/http` seul | 32 674 (17 799–34 469) | 0,90 | 36 218 | 15,4 ms | 45 MB |
| Go, `net/http` | 73 141 (35 722–106 921) | 3,10 | 22 814 | 21,3 ms | 21 MB |
| Node, `http` | 39 982 (30 086–42 563) | 0,85 | 46 755 | 9,9 ms | 95 MB |
| Java, `HttpServer` | 32 967 (17 586–34 664) | 1,87 | 17 732 | 42,6 ms | 637 MB |

```cesia allow=read,write
servers = ["Centauri", "std/http", "Go", "Node", "Java"]
perSecond = plot.Bars(servers, [[14009, 32674, 73141, 39982, 32967], [14702, 36218, 22814, 46755, 17732]],
  label = ["requests a second", "per core"], color = ["#3a5ad9", "#999999"])
hello = plot.Of([perSecond], title = "/hello under load: median of 21 measures", x = "server", y = "requests a second",
  size = [640, 360])
plot.Save(hello, "speed-hello.svg") -->
```

Le binaire d'avant et celui de maintenant répondent pareil : apparié par tour, maintenant a donné 1,01 fois les
requêtes d'avant (0,90 à 1,61), devant dans 15 tours sur 21, et dans une seconde série de 21, 1,00 (0,76 à 2,33), devant
dans 11 ; les unités du chemin de requête qui se compilent maintenant restent interprétées, car elles font trop peu
d'opérations pour leurs appels à travers OCaml ([Comment Cesia fonctionne](internals.md#les-versions-entières-sans-pari)).
Le `HttpServer` de Java a fait échouer environ 51 600 requêtes à chaque mesure, plus de deux cinquièmes de ce qu'on lui envoyait :
c'est le petit serveur du JDK, pour les outils et les tests, et Netty ou Jetty, pas mesurés ici, sont ce sur quoi tourne
un serveur Java.

**Où un géant gagne, et pourquoi.** Par cœur, Node répond à 1,3 fois ce que répond `std/http` et à 3,2 fois Centauri :
son parser (le lecteur) de HTTP est du C, `llhttp`, et V8 compile le handler ; `std/http` lit en OCaml et lance le
handler dans l'interpréteur. Go répond à 2,2 fois `std/http`, car ses goroutines prennent les cœurs d'elles-mêmes, là où
ce serveur Cesia est un processus sur un cœur : `--workers` lui en donne plus, comme le mesure
[Un serveur sous charge](#un-serveur-sous-charge). Une requête de Centauri prend 2,3 fois celle de `std/http` seul, pour
sa session, ses limites et son journal, en bonne partie dans des natives (un échantillonnage donne 33 % de son temps à
elles et 12 % au collector) ; la part propre de l'interpréteur, 53 %, est ce que le code machine pourrait prendre, et
seulement là où il appelle OCaml moins souvent qu'il ne calcule.

## Pour aller plus loin

- Craig Chambers et David Ungar, *Customization*, 1989, et les articles de Self qui l'ont suivi sur les inline caches
  (une petite mémoire, à un endroit du code, de la sorte de valeur rencontrée là), la deoptimization (le retour du code
  machine à l'interpréteur quand un pari échoue) et le type feedback (les types qu'un programme a vraiment rencontrés,
  que le JIT lit pour parier) : les idées du JIT de Cesia.
- Urs Hölzle, Craig Chambers et David Ungar, *Optimizing Dynamically-Typed Object-Oriented Languages With Polymorphic
  Inline Caches*, 1991 : le test de chaque fonction qu'un appel a rencontrée, que le JIT de Cesia fait pour un appel à
  travers une valeur.
- Michael J. Steindorfer et Jurgen J. Vinju, *Optimizing Hash-Array Mapped Tries for Fast and Lean Immutable JVM
  Collections*, 2015 : CHAMP, le trie des maps de Cesia.
- Andreas Gal et d'autres, *Trace-based Just-in-Time Type Specialization for Dynamic Languages*, 2009 : le tracing JIT
  (un JIT qui enregistre le chemin que prend une boucle hot et ne compile que ce chemin), ce qu'est LuaJIT, et pas Cesia.
- Le MIR de Vladimir Makarov, qui produit le code machine de Cesia.

Chacun avec son lien dans [Références](references.md#le-jit) et [Valeurs et maps](references.md#valeurs-et-maps) ;
[Comment Cesia fonctionne](internals.md#le-jit) montre le JIT de l'intérieur.

## La suite

Vos programmes tournent vite sans que vous ayez rien à écrire. Le chapitre suivant, [Compiler vers WebAssembly](wasm.md),
les lance dans une page web.
