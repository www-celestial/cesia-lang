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
  virgule) ou de valeurs, lus et écrits par index.
- Les fonctions sur des nombres qui s'appellent entre elles, comme dans une récursion.
- Dans une boucle, les maps (des valeurs rangées sous des clés) et les structs (des valeurs dont les champs sont déclarés
  une fois) : lire leurs champs, calculer avec eux, en créer de nouvelles, les ranger dans une liste.
- Dans une boucle, l'appel d'une fonction gardée dans une variable, comme `f(x)` où `f` vient d'une liste : le code
  machine teste les fonctions que l'appel a rencontrées, quatre au plus, et lance celle qu'il trouve, comme le montre
  [Comment Cesia fonctionne](internals.md#les-appels-à-travers-une-valeur).

Cette boucle sur une liste de structs tourne en code machine dès qu'elle est hot, environ quinze fois plus vite que dans
l'interpréteur : `bench/real/particles.ce`, la même boucle sur 2 000 particules, prend 49 ms contre 811 ms sans le JIT,
les médianes de 11 et de 5 runs (exécutions) sur la machine d'[À côté des géants](#à-côté-des-géants) :

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
[Comment Cesia fonctionne](internals.md#ce-qu-il-produit).

## Ce qui reste dans l'interpréteur

- Les appels aux fonctions des packages (du code groupé sous un nom) écrits en OCaml, comme [text.Split] ou
  [json.Parse] : elles sont déjà du code machine.
- Les boucles sur les éléments d'une liste, `for x in xs`, et un appel à travers une valeur qui a rencontré cinq
  fonctions ou plus, ou une fonction qui a capturé ses propres variables.
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
i7-4720HQ de 2015, 8 cœurs logiques, Linux, mesurés le 2026-11-08 pendant que d'autres travaux tournaient dessus (charge
de 1,3 à 4). Les versions : Python 3.14.9, Node 26.13 (V8), Java 21 (OpenJDK, HotSpot), Go 1.26.3, OCaml 5.5.0
(`ocamlopt`, sans flambda), Lua 5.5.1, LuaJIT 2.1, et Cesia dans son build `release` (la version compilée avec toutes
ses optimisations).

**La méthode.** Chaque programme fait le même travail et affiche la même réponse, vérifiée à chaque run. Les runs de tous
les langages alternent, un de chacun à tour de rôle, pour qu'une minute plus lente de la machine tombe sur tous. Chaque
temps est celui du processus entier, de son début à sa fin, démarrage compris : un programme Java ou Node paie 25 à
40 ms avant sa première ligne. Chaque case donne la *médiane* de 11 runs, celui du milieu, et après elle le *confidence
interval* à 95 % de cette médiane : l'intervalle qui contient la vraie médiane avec une probabilité d'au moins 95 %,
ici 98,8 %, tiré des rangs des runs triés, le 2e et le 10e, sans rien supposer de la façon dont les temps se
répartissent. Un intervalle large signale une mesure bruitée. Les programmes sont dans `bench/` du dépôt : `NAME.ce`,
`.py`, `.js`, `.lua`, `.go`, `.java` et `ocaml/NAME.ml`.

### Le démarrage

Un programme qui affiche `1`, 101 runs de chacun, alternés :

| | Médiane | Intervalle à 95 % |
|---|---:|---:|
| `/usr/bin/true`, rien | 0,53 ms | 0,51 à 0,53 |
| Lua | 0,84 ms | 0,80 à 0,86 |
| LuaJIT | 0,98 ms | 0,95 à 1,00 |
| OCaml, natif | 1,10 ms | 1,09 à 1,11 |
| Go | 1,31 ms | 1,29 à 1,35 |
| **Cesia** | **2,65 ms** | 2,62 à 2,67 |
| Python | 14,06 ms | 14,00 à 14,11 |
| Java | 25,09 ms | 24,98 à 25,19 |
| Node | 37,86 ms | 37,23 à 38,64 |

Mesuré de nouveau le 2026-11-09 : 2,84 ms pour le binaire d'avant le changement qui ne fait grandir son young heap (la
petite partie de la mémoire où naissent les nouvelles valeurs, vidée souvent) que quand un programme en a besoin,
alterné dans les mêmes runs. Cesia démarre 5 fois plus vite que Python, 9 fois plus vite que Java et 14 fois plus vite
que Node. Un programme compilé en Go ou en OCaml, ou Lua, démarre en environ la moitié de son temps : Cesia porte dans un
seul binaire tout son runtime (ce qui accompagne un programme pendant qu'il tourne), sa bibliothèque standard et son
compilateur, 19 723 endroits de son code que le garbage collector d'OCaml (la partie qui libère la mémoire que plus rien
n'utilise) doit connaître, contre 322 dans le programme d'OCaml lui-même, et le système doit corriger les adresses de
ses données à chaque démarrage, comme le montre [Comment Cesia fonctionne](internals.md#le-démarrage).

### Le calcul

En millisecondes, la médiane et l'intervalle à 95 % de 11 runs :

| Programme | Cesia | Cesia, sans JIT | Python | Node | Java | Go | OCaml | Lua | LuaJIT |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| `fib` | **58** (57–59) | 441 (438–489) | 1 425 (1 420–1 510) | 173 (169–212) | 71 (70–77) | 49 (49–58) | 52 (51–56) | 688 (685–699) | 97 (91–98) |
| `mandel` | **61** (61–62) | 456 (453–467) | 2 583 (2 568–2 633) | 90 (88–95) | 82 (81–84) | 52 (51–55) | 57 (56–61) | 431 (428–434) | 55 (55–55) |
| `matmul` | **44** (43–45) | 977 (963–1 017) | 4 753 (4 709–4 821) | 97 (94–98) | 93 (93–94) | 33 (33–34) | 59 (59–63) | 825 (823–837) | 87 (86–89) |
| `structs` | **46** (44–48) | 587 (579–594) | 1 736 (1 726–1 753) | 173 (169–180) | 111 (109–111) | 9 (9–9) | 30 (29–30) | 1 515 (1 482–1 557) | 395 (391–399) |
| `dyn` | **55** (55–57) | 761 (692–802) | 1 374 (1 363–1 403) | 167 (163–176) | 97 (87–103) | 28 (28–30) | 67 (67–71) | 714 (710–719) | 57 (57–57) |
| `maps` | **257** (254–263) | 256 (251–278) | 408 (401–415) | 547 (526–574) | 224 (214–226) | 273 (269–284) | 507 (494–588) | 806 (789–844) | 311 (304–326) |

Mesuré de nouveau le 2026-11-09, après que les feuilles d'une récursion (ses derniers appels, qui ne rappellent plus la
fonction) ont été testées à leur appel et que le JIT a donné à MIR (le petit compilateur qui produit le code machine de
Cesia) deux cinquièmes de lignes en moins à compiler ([Comment Cesia fonctionne](internals.md#ce-qu-il-produit)) : la
veille, `fib` prenait 74 ms, `matmul` 47, `structs` 49, `dyn` 57, et les autres lignes restaient à quelques pour cent de
celles d'aujourd'hui.

Ce que fait chaque programme : `fib` est `fib(35)`, environ 30 millions d'appels récursifs sur des entiers ; `mandel`
une boucle de floats sur $600 \times 400$ points ; `matmul` le produit de deux matrices $300 \times 300$ lues par index ;
`structs` 1 000 enregistrements de quatre floats, chacun refait à chacun des 5 000 pas ; `dyn` 10 millions d'appels à
travers une liste de deux fonctions, sur des valeurs de sortes mêlées ; `maps` une map de 500 000 clés de texte, écrite
puis lue.

**Là où Cesia gagne.** Sur les boucles de nombres et sur la récursion, le JIT place Cesia devant Java, Node et LuaJIT :
`matmul` tourne en environ la moitié du temps de Java, de Node et de LuaJIT, et devant OCaml, `fib` en 58 ms contre 71
pour Java et 97 pour LuaJIT, et `mandel` devant Java et Node. Face à Python, le langage d'où viennent la plupart de ses
utilisateurs, Cesia est 25 fois plus rapide sur `fib`, 42 fois sur `mandel` et 108 fois sur `matmul` ; face à Lua, 7 à
33 fois, et 3 fois sur `maps`. Sur `dyn`, il est devant Node, Java et OCaml, 55 ms contre 167, 97 et 67, à égalité avec
LuaJIT, et 25 fois plus rapide que Python. Sur `structs`, il est devant Java, 46 ms contre 111, devant Node, 173, et
devant LuaJIT, 395. Sur `maps`, il est devant tous les langages sauf Java, Go compris : 257 ms contre 273.

**Là où un géant gagne, et pourquoi.**

- **Go gagne toutes les lignes sauf `maps` ; OCaml gagne `fib`, `mandel` et `structs`.** Ils compilent tout le
  programme en code machine avant qu'il tourne, chaque type connu, et démarrent en 1,1 à 1,3 ms. Un appel de `fib` coûte
  maintenant à Cesia 5,5 cycles du processeur, contre 5,9 à Go (selon les compteurs du processeur : le coût d'un appel de
  plus) : ce qui garde Go 9 ms devant, c'est le coût fixe, le démarrage (2,65 ms contre 1,31), le chargement du JIT,
  0,65 ms, et la compilation par MIR, 3,4 ms ([Comment Cesia fonctionne](internals.md#ce-que-coûte-sa-fabrication)). La boucle
  intérieure de `mandel` attend sa chaîne de floats, une soustraction, une addition et une multiplication d'un tour au
  suivant, 11 cycles, le plancher de tout langage : Cesia et Go prennent tous deux 3,7 à 3,8 ns par tour, et les 9 ms
  qui les séparent sont encore le coût fixe. La boucle intérieure de `matmul` tourne elle aussi à la vitesse de Go,
  1,15 ns par pas ; ses deux boucles coûtent chacune 3 à 5 ms de compilation à MIR.
- **`structs` : OCaml prend 0,6 fois le temps de Cesia, Go un sixième.** Une map de quatre floats les garde maintenant
  comme des doubles (le nombre machine de 64 bits, nu, sans bloc de mémoire autour), et le JIT ne construit jamais la
  map qu'il lit dans la liste : il garde ses quatre doubles dans des registres et écrit les nouveaux à la place des
  anciens, que rien d'autre ne tient ([Comment Cesia fonctionne](internals.md#ce-qu-il-produit)). Un pas n'alloue rien (il
  ne demande aucune mémoire) : 219 ms, puis 186, 49, maintenant 46. Ce qui reste, environ 60 instructions et 24 cycles
  par pas contre 19 et 5 pour Go : chaque pas lit dans la liste l'adresse de la map et vérifie sa sorte, ses clés,
  qu'elle n'est tenue que par un seul nom et que son stockage contient des doubles, là où l'array de Go contient les
  floats des enregistrements eux-mêmes, à des places connues ; et environ 10 ms de coût fixe, le démarrage du processus,
  les premiers pas dans l'interpréteur et la compilation de la boucle. OCaml construit un nouvel enregistrement de 5 mots
  à chaque pas, sans aucune vérification : 30 ms.
- **`dyn` : Go prend la moitié du temps ; LuaJIT est à égalité ; Cesia est devant Java, OCaml et Node.** `total` vient
  d'un appel à travers une fonction gardée dans une liste, que l'inférence (l'analyse qui trouve les types sans qu'on les
  écrive) ne peut pas typer ; le JIT le garde comme un float dans un registre pendant toute la boucle, et l'appel devient
  un test des deux fonctions qu'il a rencontrées, dont le code est recopié sur place (inlined), le *polymorphic inline
  cache* (la mémoire, à l'endroit de l'appel, des fonctions qu'il a déjà rencontrées) de
  [Comment Cesia fonctionne](internals.md#les-appels-à-travers-une-valeur) : 714 ms, puis 182, 114, 57, maintenant 55. Le pas de Go
  est un appel de code tout en floats, sans test de sorte et sans compte des pas.
- **`maps` : Java prend un huitième de temps en moins ; Cesia est devant tous les autres, Go compris.** Une grande map
  que tient un seul nom est maintenant une hash table (un array de slots où le hash d'une clé, un nombre calculé à partir
  d'elle, désigne la place où la chercher) rangée dans l'ordre d'insertion, la disposition de Python, et ne devient le
  trie (un arbre où chaque niveau choisit sa branche d'après quelques bits du hash) [CHAMP](glossary.md#champ) des
  [persistent](glossary.md#persistent-data-structure) maps (qui gardent leur ancienne version quand elles changent) qu'une
  fois partagée et modifiée ([Comment Cesia fonctionne](internals.md#maps-une-hash-table-puis-un-hash-trie)) : 815 ms
  avant, 275 avec la table, 258 depuis que chaque clé `"key$k"` est construite en une copie au lieu de trois
  ([Comment Cesia fonctionne](internals.md#l-exécution-des-closures-comme-code)), en 68 Mo, contre 70 Mo pour Python, 50 pour Go et
  139 pour Java. Les compteurs du processeur disent pourquoi : 3,1 cache misses (des lectures qui ne trouvent pas leur
  donnée dans le cache, la mémoire rapide du processeur, et doivent aller la chercher plus loin) par opération dans son
  dernier niveau de cache, là où le trie en faisait 18,7, contre 3,7 pour Python et 4,3 pour Go. Les 224 ms de Java
  viennent d'un garbage collector qui travaille sur les autres cœurs et d'un hash gardé dans chacune de ses chaînes ; et
  la boucle de `maps`, qui construit un texte à chaque tour, reste dans l'interpréteur de Cesia : sa part est d'environ
  un dixième du temps, et du code natif devrait rappeler OCaml pour le hash, la table et le texte
  ([Comment Cesia fonctionne](internals.md#ce-qui-reste-dans-l-interpréteur)). Le prix de la table : le premier [dict.Put]
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
relancées par une boucle. 11 runs de chacun, alternés, le 2026-11-09 ; le temps par tâche est celui de 100 000 tâches
moins celui d'une seule, divisé par 100 000, et la mémoire par tâche le pic de mémoire du processus avec 100 000 tâches
moins celui avec une seule, divisé par 100 000 :

| | 100 000 tâches | Intervalle à 95 % | Par tâche | Mémoire par tâche |
|---|---:|---:|---:|---:|
| Coroutines de LuaJIT | 59 ms | 58 à 69 | 0,6 µs | 0,4 Ko |
| Node `async` | 167 ms | 165 à 173 | 1,3 µs | 1,3 Ko |
| Goroutines de Go | 129 ms | 127 à 134 | 1,3 µs | 2,6 Ko |
| Coroutines de Lua | 132 ms | 131 à 134 | 1,3 µs | 1,0 Ko |
| **Fibers de Cesia** | **351 ms** | 348 à 353 | **3,4 µs** | **2,1 Ko** |
| Python `asyncio` | 1 072 ms | 1 055 à 1 083 | 10,0 µs | 1,4 Ko |
| Virtual threads de Java | 1 663 ms | 1 562 à 1 738 | 16,2 µs | 2,3 Ko |

Une fiber de Cesia prend le tiers du temps d'une tâche Python et le cinquième de celui d'un virtual thread de Java pour
démarrer, se mettre en attente et finir, et 2,7 fois celui d'une goroutine ; avec sa tâche, elle prend 2,1 Ko, moins que
les 2,6 Ko d'une goroutine et les 2,3 Ko d'un virtual thread. Elle prenait 4,3 µs et 2,5 Ko jusqu'au 2026-11-08 : ses
piles commencent maintenant à 8 slots (des places de taille fixe), et non 16, son corps et sa fin ne créent aucune
closure (une fonction qui garde les noms de l'endroit où elle a été créée), une fiber qui attend une tâche y laisse sa
propre fonction de réveil, et un seul handler (le code qui reçoit une fiber quand elle s'arrête pour attendre), créé une
fois, sert toutes les fibers. Chaque fiber a trois piles à elle, pour les valeurs, les entiers et les floats, à côté de
sa pile OCaml : elles doublent quand elles sont pleines, comme la pile d'une goroutine commence à 2 Ko et est recopiée
dans une plus grande. Environ 1 Ko des 2,1 est cette pile OCaml : OCaml démarre une fiber à 64 mots et la double au
premier appel de l'interpréteur en elle (gdb compte un agrandissement par fiber), si bien qu'une fiber en attente tient
128 mots. Ce qu'une goroutine ne paie pas, c'est le garbage collector : celui d'OCaml copie chaque fiber vivante hors de
son young heap et la marque de nouveau à chaque cycle majeur, ce qui fait l'essentiel du temps d'une fiber ici. Les
goroutines de Go tournent aussi en parallèle sur tous les cœurs ; les fibers de Cesia tournent sur un seul, et
`--workers` donne tous les cœurs à un serveur, comme le montre [HTTP](http.md#tous-les-cœurs).

### Textes et fichiers

Un texte de 100 Mo, 2,46 millions de lignes de source OCaml : lu en entier depuis un [page cache](glossary.md#page-cache)
warm (la copie des fichiers que le système garde en mémoire après les avoir lus, ici qui tient déjà ce fichier), un mot
cherché jusqu'à la fin en respectant la casse et en l'ignorant, ses lignes jointes de nouveau, et 16 Mo écrits, avec et
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
| écrire 16 Mo | **3,5** (3,5–4,0) | 6,0 (5,8–7,0) | 7,2 (6,5–8,9) | 2,6 (2,4–3,1) |
| écrire 16 Mo, puis fsync | **44** (43–75) | 60 (47–105) | 50 (45–91) | 44 (41–60) |

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
vivantes pendant que le programme alloue les 100 Mo du résultat, là où Python compte les références et où le garbage
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

Des requêtes par seconde, mesurées le 2026-11-09, le binaire d'avant ce changement alternant dans les mêmes runs : il
répondait à 53 918 et 53 546 requêtes sur la petite route à 10 et 100 connexions, 32 682 à 1 000, et 41 980 sur la
route JSON. Le 99e percentile de la latence, le temps en dessous duquel 99 requêtes sur 100 reçoivent leur réponse, à
100 connexions gardées sur la petite route : Cesia 3,2 ms, Node 3,3 ms, Go 3,2 ms ; à 1 000 : Cesia 34,5 ms, Node
17,7 ms, Go 27,3 ms. Une connexion inactive prend 2,3 Ko dans Cesia, 2,5 Ko dans Node et 18 Ko dans Go, et un serveur au
repos 15 Mo, 54 Mo et 10 Mo.

Cesia répond à autant de petites requêtes que Go sur un cœur, et à deux cinquièmes de plus que Node ; sur de nouvelles
connexions, il est le plus rapide des trois ; sur la route JSON, il devance Node d'un sixième, et Go garde un dixième
d'avance : son encodeur est du code compilé, là où le handler de Cesia (la fonction qui traite une requête) et sa
réponse tournent en partie dans l'interpréteur. Le handler de chaque requête tourne dans sa propre fiber, et chacune
agrandissait ses piles, ce qui demandait à OCaml la taille de son heap (la mémoire où vivent les valeurs) à chaque
agrandissement, un dixième du temps du serveur, jusqu'à ce que des piles aussi petites soient laissées aux checkpoints
(les moments où l'interpréteur arrête de compter pour regarder le programme)
([Comment Cesia fonctionne](internals.md#ce-qu-il-sert)).

**Là où un géant gagne, et pourquoi : 1 000 connexions.** Node et Go répondent à plus de requêtes à 1 000 connexions
gardées, et Node tient son 99e percentile à la moitié de celui de Cesia. Un seul cœur fait tourner les 1 000 fibers de
Cesia chacune à son tour : d'après la *loi de Little* (le nombre de requêtes en attente est égal au débit multiplié par
le temps que chacune attend), 1 000 requêtes en attente, servies à 36 200 par seconde, attendent chacune 27,6 ms en
moyenne, si bien que le 99e percentile ne peut pas descendre sous 25 ms avant que le serveur ne réponde à plus de
requêtes, et les requêtes en cours survivent aux minor collections d'OCaml (les passages fréquents du garbage collector
sur le young heap), qui les copient dans le major heap (la grande partie de la mémoire, nettoyée par tranches), sept
fois plus de mots qu'à 100 connexions. Les goroutines de Go prennent d'elles-mêmes tous les cœurs de la machine, et
l'event loop de Node (la boucle unique qui traite les événements l'un après l'autre) ne garde aucune pile par
connexion. `--workers 2` donne deux cœurs à Cesia, et environ 1,5 fois le nombre de requêtes, ce que
`tools/http-gate.sh` vérifie à chaque changement.

```bash
tools/http-bench.sh    # each load against Node, and Go if it is there
tools/http-gate.sh     # the gate that a change to the server must pass
```

`tools/http-bench.sh` fait aussi tourner 10 connexions actives à côté de 10 000 inactives, ce qui donne la mémoire d'une
connexion inactive. `tools/http-gate.sh` lance les charges principales et échoue si une requête échoue, si Cesia répond
à moins de requêtes que Node ou que ses planchers (les nombres minimaux fixés pour chaque charge), si son 99e percentile
dépasse 10 ms, si une connexion inactive prend plus de 4 Ko, ou si deux workers (deux processus du même serveur, chacun
sur un cœur) ne donnent pas une fois et demie un seul processus. `HTTP_GATE_SCALE=0.5` divise les planchers par deux
sur une machine plus lente.

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

Vos programmes tournent vite sans que vous ayez rien à écrire. Le chapitre suivant, [C et C++](c.md), appelle les
bibliothèques du système depuis Cesia.
