# Comment Cesia fonctionne

Dans ce chapitre, vous regardez à l'intérieur de Cesia : ce qui se passe entre le texte d'un programme et ce qu'il
affiche, comment ses valeurs sont rangées en mémoire, comment le JIT fabrique du code machine, comment les fibers (des
fonctions qui tournent côte à côte dans un même programme) se relaient, et comment un serveur se sert de chaque cœur.
Rien de tout cela n'est nécessaire pour écrire des programmes. Ce chapitre vous dit pourquoi un programme est rapide ou
lent, sur quoi repose une garantie, et quels mots chercher pour en apprendre plus. Chaque partie nomme le fichier du
dépôt où se trouve le code, sous `src/`, et les [Références](references.md) donnent les articles.

Chaque nombre de cette page dit comment il a été mesuré, sur une seule machine : un Intel Core i7-4720HQ de 2015, à
2,6 GHz, 4 cœurs et 8 cœurs logiques, Linux, OCaml 5.5, le build `release` (le binaire compilé comme pour une release) ;
les autres viennent de `bench/RESULTS.md`, dans le dépôt, avec leur date.

## Le chemin d'un programme

Cesia est un interpréteur écrit en OCaml, avec un JIT pour ce qui devient hot, le code qui tourne souvent. Un
*interpréteur* exécute un programme à partir d'une forme de celui-ci gardée en mémoire, sans fabriquer d'abord un
fichier de code machine ; un *JIT*, un just-in-time compiler (un compilateur « juste à temps »), fabrique du code
machine pour des parties du programme pendant qu'il tourne. Un programme passe par ces étapes, chacune un module de
`src/lib/` :

| Étape | Ce qu'elle produit | Fichier |
|---|---|---|
| Le lexer | les tokens : les noms, les nombres, les textes, les opérateurs, les fins de ligne | `lexer.ml` |
| Le parser | le syntax tree : un nœud par expression | `parser.ml` |
| Le resolver | chaque nom relié à sa place : une variable de la fonction, une variable capturée, un nom du fichier ou d'un package (une bibliothèque que le fichier importe) | `resolve.ml` |
| L'inférence | un type pour chaque variable et chaque nœud d'une version d'une fonction | `infer.ml` |
| Le compilateur | des closures OCaml, une par nœud, qui exécutent le programme | `compile.ml` |
| Le JIT | du code machine pour les fonctions et les boucles hot | `src/jit/`, chargé au besoin |

Les étapes se font par fichier, quand le programme en a besoin pour la première fois, et par fonction, quand elle est
appelée pour la première fois : une fonction qui ne tourne jamais n'est jamais compilée. `cesia check` fait les trois
premières étapes et ses propres vérifications des appels et des types (`check.ml`), et n'exécute jamais le programme.

## Lire : le lexer et le parser

Le *lexer* découpe le texte en *tokens*, les mots du langage : `count`, `=`, `42`, `"a text"`. Il lit l'UTF-8 et refuse
un fichier qui n'en est pas. Un texte qui contient un `$` devient ses morceaux : le texte simple, et les tokens de chaque
bout de code, que le parser lit comme un appel de [text.Str].

Le *parser* change les tokens en un *syntax tree* (un arbre syntaxique) : un arbre dont les nœuds sont les expressions
et les statements (les instructions) du programme, chacun avec sa ligne et sa colonne. Pour `total = price * (1 + tax)` :

```text
Assign total
└── Bin *
    ├── Name price
    └── Bin +
        ├── Int 1
        └── Name tax
```

Le parser est écrit à la main : c'est un parser à *recursive descent* (descente récursive), une fonction par règle de la
grammaire, chacune appelant les autres, de sorte que l'imbrication des appels suit l'imbrication du code. Chaque niveau
d'opérateurs a sa fonction, du moins prioritaire au plus prioritaire : `then`, `or`, `and`, `not`, les comparaisons,
`..`, `+` et `-`, `*` et `/`, le `-` unaire, `^`, et les appels, les index et les champs. Cet ordre est la *précédence*
des opérateurs : `1 + 2 * 3` se lit `1 + (2 * 3)` parce que `*` est lu à un niveau plus profond. Une fin de ligne
termine un statement, sauf entre `( )` et `{ }` ; entre `[ ]`, elle commence une nouvelle ligne de la matrice.

Une erreur de syntaxe arrête le chargement avec son fichier, sa ligne et sa colonne, et la plupart des messages disent
quoi écrire à la place. Du code imbriqué plus profondément que la limite `nesting`, 600 par défaut, est refusé ici,
avant que rien ne tourne : le parser s'appelle lui-même une fois par niveau, et une limite empêche un fichier hostile de
faire déborder sa stack (la pile de ses appels en cours).

## Les noms : le resolver

Le *resolver* parcourt l'arbre une fois et décide ce que veut dire chaque nom. Cesia a un *lexical scope* (une portée
lexicale) : les noms que voit un morceau de code sont ceux qui sont écrits autour de lui dans le texte, pas ceux de qui
l'appelle. Un nom est l'un de ceux-ci :

- une *variable locale* : un paramètre, ou un nom qui reçoit une valeur dans la fonction. Elle reçoit un slot, une place
  numérotée dans la frame de la fonction, l'ensemble des places de ses variables pendant un appel ;
- une *variable capturée* : un nom d'une fonction englobante, utilisé par une fonction écrite à l'intérieur de celle-ci ;
- un nom du fichier, ou d'un autre fichier du même package ;
- un nom d'un package que le fichier utilise, comme `list.Map`.

Le resolver vérifie aussi la *definite assignment* (l'affectation certaine) : un nom lu avant qu'une valeur ne l'atteigne
est une erreur au chargement, `"x" has no value yet.`, et non une surprise à l'exécution. Il marque les appels en *tail
position* (en position terminale) : un appel dont le résultat est le résultat même de la fonction, sans rien à faire
après lui. Une fonction qui s'appelle elle-même à cette place tourne comme une boucle, donc sa profondeur ne grandit pas.

```cesia
defn countdown(n)
  if n == 0
    return "done"
  end
  countdown(n - 1)
end
countdown(100000) --> "done"
```

L'appel à `countdown` est en tail position, donc 100 000 appels tournent dans une seule frame, sous la limite de
profondeur de 10 000.

### Closures

Une fonction écrite dans une autre est une *closure* : une fonction avec les variables qu'elle a capturées là où elle a
été écrite. Cesia fait des *flat closures* (des closures plates) : quand la fonction intérieure est créée, les valeurs
des variables qu'elle capture y sont copiées, dans un petit array (un tableau de valeurs). Une closure voit donc les
valeurs que ses variables avaient quand elle a été créée :

```cesia
n = 10
f = () -> n
n = 20
f() --> 10
```

C'est ce que la [value semantics](#les-valeurs-en-mémoire) donne pour toute valeur, et cela permet d'envoyer une closure à une
autre fiber sans rien partager.

## Les types : inférence et versions

Cesia a des *dynamic types*, un typage dynamique : une variable peut tenir un entier à un moment et un texte à un autre,
et une opération vérifie les sortes de ses opérandes quand elle s'exécute. Vérifier coûte du temps à chaque opération,
donc Cesia prouve, là où il le peut, qu'une vérification ne peut pas échouer, et la retire.

Une fonction reçoit une *version* pour chaque combinaison des types de ses arguments qu'elle rencontre : `area(2, 3)` et
`area(2.0, 3.0)` appellent deux versions de `area`, une pour deux entiers et une pour deux floats (des nombres à
virgule). On appelle cela la *specialization*, ou la *customization* dans le langage Self, où elle est née. Pour chaque
version, l'*inférence* donne un type à chaque variable et à chaque nœud, parmi cinq : pas encore de type, un entier, un
float, un array de floats, ou « n'importe quoi ». L'inférence est une *dataflow analysis* (une analyse du flot des
données) : elle suit les valeurs à travers le code jusqu'à ce que les types ne changent plus. Deux types qui se
rencontrent, comme un `if` qui donne un entier d'un côté et un float de l'autre, deviennent « n'importe quoi ». Un type
que donne l'inférence est prouvé, jamais deviné : dans une version pour des entiers, `a + b` additionne deux entiers
machine avec un test d'overflow (le dépassement de la taille d'un entier), et rien d'autre.

Une fonction a au plus 8 versions ; au-delà, une *version générique*, typée « n'importe quoi » partout, prend les autres
appels. `--no-spec` exécute chaque fonction dans sa version générique seulement, ce dont les tests se servent pour
vérifier que les deux donnent les mêmes résultats. Un type écrit dans le code, comme `n Int`, est vérifié quand une
valeur arrive, et ne sert jamais à rendre le code plus rapide : un programme sans types tourne aussi vite qu'un
programme typé, par choix de l'auteur de Cesia.

## L'exécution : des closures comme code

Le compilateur change le syntax tree en *closures* : des fonctions OCaml créées une fois par nœud, chacune appelant
celles de ses enfants. `a + b` devient une fonction qui exécute la fonction de `a`, la fonction de `b`, et additionne.
Exécuter une closure est bien plus rapide que de parcourir l'arbre à nouveau à chaque pas, parce que le travail de
regarder le nœud est fait une fois, quand la closure est créée. C'est la *closure compilation*, une vieille technique
d'interpréteurs, des années 1980.

Une version fait trois sortes de closures, selon ce qu'elles donnent : une valeur, un entier unboxed ou un float
unboxed. Un nombre *boxed* est rangé dans son propre bloc de mémoire, derrière un pointeur, avec un tag qui dit sa
sorte ; un nombre *unboxed* est le nombre machine nu, dans un registre ou un slot. Une version pour des floats garde ses
floats unboxed, donc `x * y + z` n'alloue rien.

Une fonction qui tourne garde ses variables dans une *frame* : une suite de slots sur une stack. Cesia a trois stacks
par fiber, une de valeurs, une d'entiers et une de floats, donc un nombre unboxed n'a jamais besoin d'être boxed pour
être rangé. Les stacks commencent à 4 096 slots pour le programme principal et à 8 pour une fiber, et doublent quand
elles sont pleines.

Un texte fait par [string interpolation](glossary.md#string-interpolation) (l'insertion de valeurs dans un texte, avec le signe dollar)
à partir d'un mot et d'un entier, comme `"key$k"`, est écrit d'un seul morceau : le mot, puis les chiffres, dans
un buffer (une zone de mémoire où l'on écrit avant de copier) que garde l'interpréteur, et le texte en est copié une
fois. Fait en trois étapes, les chiffres, un texte de ceux-ci, puis un texte des deux, il demandait trois allocations et
trois copies ; une copie est le minimum en OCaml sans ses fonctions unsafe (celles qui ne vérifient pas leurs accès), que
le cœur de Cesia n'utilise jamais : un buffer ne devient un texte que par une copie. `bench/maps.ce` fabrique un million
de ces clés : 277 ms avant, 253 après, 1 830 millions d'instructions avant, 1 643 millions après (les compteurs du
processeur, un seul run de chacun, c'est-à-dire une exécution). Un entier montré seul, comme `"$k"` ou [io.Print], est fait de la même
façon.

### Pas et checkpoints

Le programme compte des *pas* (steps) : un appel en est un, un tour de boucle en est un, et une native (une fonction de
la bibliothèque standard écrite en OCaml) qui construit une liste de `n` valeurs compte environ `n / 16`. De temps en temps, à un
*checkpoint*, un arrêt prévu pour ses vérifications, l'interpréteur regarde les limites :

- au moins tous les 10 000 pas, sous la limite de profondeur par défaut : la limite `steps`, et la profondeur des appels ;
- tous les 1 000 000 pas, un *checkpoint complet* : la sortie est vidée, la limite de mémoire vérifiée, un fichier
  modifié rechargé sous `--watch`, et les autres fibers ont leur tour (voir [Fibers](#les-fibers-et-le-scheduler)).

Sous `--watch`, un checkpoint complet vient tous les 100 000 pas, pour qu'un fichier modifié prenne effet dans les
100 ms. Compter, c'est une soustraction et un test à chaque appel et à chaque tour de boucle ; la profondeur des appels
n'est comptée qu'à un checkpoint, chaque frame une fois, donc un appel ne coûte rien de plus pour la limite de
profondeur. Une limite est exacte malgré tout : les pas entre deux checkpoints sont bornés par ce qu'il reste avant la
limite.

### Des caches à chaque site

Une lecture de champ, comme `p.X`, trouve la place de `X` dans la struct (une valeur à champs nommés) ou dans la map (un
dictionnaire de clés et de valeurs). Chaque endroit du code qui lit un champ, chaque site, garde la dernière *forme*
(shape) qu'il a rencontrée et la place du champ dans celle-ci : c'est un *monomorphic inline cache*, un cache placé dans
le code, pour une seule forme. Quand la valeur suivante a la même forme, comme presque toujours dans une boucle, la
lecture est une comparaison et un chargement. Une forme est décrite dans [Les valeurs en mémoire](#les-valeurs-en-mémoire).

## Les valeurs en mémoire

Chaque valeur de Cesia est une valeur d'un seul type OCaml, `Types.t` dans `src/lib/types.mli`, une *tagged union* (une
union étiquetée) : un mot de mémoire qui est soit une petite constante, soit un pointeur vers un bloc dont l'en-tête dit
de quel cas il s'agit.

| Valeur | En mémoire |
|---|---|
| `missing`, `true`, `false` | une constante dans le mot lui-même : aucune allocation |
| un entier | 63 bits, dans le mot lui-même : OCaml garde un bit pour distinguer les nombres des pointeurs |
| un float | 64 bits d'IEEE 754, dans un bloc à lui ; unboxed dans une version typée et dans un array de floats |
| un texte | ses octets, en UTF-8, dans un bloc qui ne change jamais |
| une liste, une matrice, un array | une taille par dimension et une seule zone de cellules, colonne par colonne : des floats, des entiers ou des valeurs |
| une struct | sa *forme*, les noms de ses champs, partagée par toutes les structs de son espèce, et une zone de ses valeurs : leurs doubles (les floats nus) tant que toutes sont des floats, comme les garde un array de floats, sinon les valeurs |
| une map | voir [Maps : une hash table, puis un hash trie](#maps--une-hash-table-puis-un-hash-trie) |
| une fonction | son code, et les valeurs qu'elle a capturées |
| une tâche, un channel (une file de valeurs entre fibers), une connexion | un *handle* : une sorte et un numéro, que le système suit |

Un entier qui grandit au-delà de 63 bits est une erreur, ni un wraparound silencieux (un passage aux nombres négatifs),
ni un nombre plus grand et plus lent : le message dit d'utiliser un float.

```cesia fails
4611686018427387903 + 1
```

### Value semantics et copy-on-write

Les valeurs de Cesia ont une *value semantics* (une sémantique de valeur) : donner un second nom à une valeur, ou la
passer à une fonction, agit comme une copie, et un changement par un nom ne se voit jamais par l'autre.

```cesia
xs = [1, 2, 3]
ys = xs
ys[1] = 10
xs --> [1, 2, 3]
ys --> [10, 2, 3]
```

Copier une liste à chaque affectation serait lent, donc Cesia ne copie que quand il le faut, ce qu'on appelle le
*copy-on-write* (la copie à l'écriture). Une liste, une struct ou une map porte un bit, *owned* (possédée) : vrai tant
qu'un seul endroit la tient. Une écriture dans une valeur owned la change sur place ; un second nom efface le bit, et une
écriture plus tard copie d'abord la valeur, puis possède la copie. Dans la boucle ci-dessous, `xs` est owned tout du
long, donc chacune des 1 000 écritures change la liste sur place :

```cesia
use std/list
xs = list.Fill(0, 1000)
for k in 1..1000
  xs[k] = k * k
end
xs[1000] --> 1000000
```

Le bit n'est jamais remis une fois effacé : une valeur qui a été partagée est copiée à sa prochaine écriture même si
l'autre nom a disparu. Cela coûte une copie, jamais un résultat faux. Une liste faite par [list.Append] garde des
cellules libres après la dernière, en nombre doublé quand il n'y en a plus, donc une boucle d'ajouts coûte un temps
constant par élément en moyenne : un temps constant *amortized* (amorti, en moyenne sur une longue suite d'opérations).

## Maps : une hash table, puis un hash trie

Une map, que Cesia appelle un dictionnaire, prend n'importe quel nombre ou texte comme clé. C'est une
[persistent data structure](glossary.md#persistent-data-structure) (une structure de données persistante) :
[dict.Put] donne une nouvelle map et laisse l'ancienne telle qu'elle était, et les deux partagent la plus grande partie
de leur mémoire. Son stockage, dans `src/lib/trie.ml`, a trois variantes, et un programme n'en voit aucune : les mêmes
clés, valeurs, ordre, `==` et erreurs dans chacune.

**Jusqu'à 32 clés, un bloc.** Les clés sont rangées dans l'ordre où elles sont arrivées, à côté de leurs hashes (le
nombre calculé à partir de chaque clé), et les valeurs dans un second array. Les maps faites à un même endroit du code
partagent leur array de clés, comme les structs d'une même espèce partagent leur forme : `{X: 1, Y: 2}` dans une boucle
fait beaucoup de maps avec un seul array de clés. Une lecture de champ met alors en cache la place de sa clé, comme pour
une struct. Ce partage est l'idée des *hidden classes* (des classes cachées), venue de Self, où on les appelait maps, et
de V8.

Les valeurs d'une telle map, et les champs d'une struct, ont une [storage strategy](glossary.md#storage-strategy) à eux
(une façon de ranger les cellules qui dépend de ce qu'elles tiennent) : tant que toutes sont des floats, elles sont
gardées comme des doubles nus, comme un array de floats garde ses cellules ; une valeur d'une autre sorte écrite dans
l'une d'elles change cette zone en un array de valeurs, une fois. Un entier reste un entier : `{X: 1}` garde un `Int`,
contrairement à une liste de nombres, qui garde ses entiers comme des floats. Une map de quatre floats prend ainsi
11 mots de mémoire, la map, sa zone et quatre doubles, contre 25 quand chaque float était une valeur à lui : une valeur
float, c'est deux blocs d'OCaml, le cas de la valeur et le double boxed vers lequel il pointe (Leroy, 1992, dit pourquoi
OCaml met un float dans une box hors d'un array de floats ou d'un record de floats). Le prix est dans l'interpréteur :
lire `p.X` dans une telle map fabrique une valeur float, 4 mots, là où la lecture prenait celle qui était rangée ; dans
un calcul, comme `p.X + 1.0`, l'interpréteur lit le double sans en fabriquer une. L'interpréteur seul exécute
`bench/structs.ce` 8 % plus lentement à cause de cela, 595 ms contre 550 (5 runs chacun, en alternance) ; le code
machine, qui lit et écrit les doubles eux-mêmes, l'exécute en environ 50 ms, comme le montre
[Ce qu'il produit](#ce-quil-produit).

```text
{X: 1.0, Y: 2.0, Vx: 1.0, Vy: 0.5}
before: map 4 words -> values 5 words -> 4 floats of 4 words each      25 words, 6 blocks
now:    map 4 words -> store 2 words  -> 4 doubles, 5 words           11 words, 3 blocks
```

**Au-delà de 32 clés, tant qu'un seul nom tient la map, une hash table**, une table où le hash d'une clé dit où la
chercher. Une map *owned*, le bit du [copy-on-write](#value-semantics-et-copy-on-write), garde ses clés dans une
*insertion-ordered hash table* (une hash table qui garde l'ordre d'insertion), la disposition du `dict` de Python depuis
la 3.6, d'après un design de Raymond Hettinger. Les entrées sont rangées dans des arrays dans l'ordre où elles sont
arrivées, les clés dans l'un et les valeurs dans un autre ; les valeurs sont des entiers machine nus dans un array
d'entiers tant que toutes sont des entiers, une *storage strategy* comme en ont les listes de Cesia (Bolz, Diekmann et
Tratt, 2013), et une valeur d'une autre sorte change cet array en un array de valeurs, une fois. À côté des entrées, un
*index* de slots, une puissance de deux au moins deux fois plus grande que le nombre d'entrées, chacun vide ou tenant le
hash d'une entrée et son numéro. Une clé se trouve par *linear probing* (le sondage linéaire) : à partir du slot que
désigne son hash, les slots l'un après l'autre jusqu'à la clé, comparée d'abord par le hash du slot, ou jusqu'à un slot
vide. À cette demi-charge, une clé présente prend 1,5 slot en moyenne et une clé absente 2,5 (Knuth, *The Art of
Computer Programming*, vol. 3, 6.4), le tout dans une ou deux cache lines de l'index (les petits blocs de mémoire que le
processeur charge d'un coup dans ses caches), là où le trie ci-dessous suit quatre ou cinq nœuds. L'ordre des clés ne
coûte rien : c'est l'ordre des entrées.

```text
a map of 4 keys, its index of 8 slots
slots     [  -  | h2 #2 |  -  | h0 #0 | h3 #3 |  -  | h1 #1 |  -  ]    each empty, or a hash and an entry's number
entries   #0 "apple" -> 3   #1 "pear" -> 9   #2 "fig" -> 1   #3 "kiwi" -> 4    in the order they came
```

Une écriture met une nouvelle clé à la fin des entrées et dans le premier slot vide à partir de son hash : sur place, en
un temps constant en moyenne. Quand les entrées sont pleines, les deux arrays doublent et les slots sont replacés à
partir de leurs hashes : un temps constant *amortized* par clé.

**Une fois qu'une map est partagée puis écrite, un hash array mapped trie**, un HAMT. Une écriture qui doit garder
l'ancienne map, comme [dict.Put] sur n'importe quelle map, ou une écriture dans une map que tient un autre nom, change
d'abord la table en trie, sur place et pour de bon, avec les mêmes clés, valeurs et ordre : les écritures suivantes ne
copient alors qu'un chemin, comme ci-dessous. Il est construit en une passe : le hash de chaque entrée, ses six morceaux
de 5 bits pris dans l'ordre inverse, est trié par trois passes d'un *radix sort*, un tri qui range les nombres morceau
par morceau (ici par 10 bits à la fois, en comptant), pour que les clés de chaque nœud du trie soient côte à côte, et
chaque nœud est fait une seule fois, à sa taille. Cela coûte environ 0,11 s pour un million de clés quand elles tiennent
dans les caches du processeur, et 0,25 s au-delà (109 et 245 ns par clé, à 100 000 et 1 000 000 de clés), une fois par
map ; un programme qui garde les anciennes versions d'une grande map le paie à son premier [dict.Put], puis chaque Put
coûte un chemin. Un *hash* est un nombre calculé à partir d'une clé, le même pour la même clé ; un *trie* est un arbre
où chaque niveau est choisi par un morceau de la clé. Dans un HAMT, chaque niveau prend 5 bits du hash de la clé, donc
un nœud a jusqu'à 32 places, gardées compactes par un *bitmap* de 32 bits qui dit quelles places sont prises : la place
d'une clé dans les arrays du nœud est le nombre de bits à 1 sous le sien, compté par quelques opérations sur le mot.
Cesia utilise 30 bits de hash, donc une clé est au plus à 6 niveaux de profondeur.

Les nœuds de Cesia sont ceux de *CHAMP*, le compressed hash-array mapped prefix tree de Steindorfer et Vinju, 2015. Un
nœud a deux bitmaps. Le premier marque les clés tenues dans le nœud lui-même, inline (sur place), chacune à côté de son
hash et de sa valeur : les clés dont aucune autre clé sous le nœud ne partage les 5 bits de ce niveau. Le second marque
les places que plusieurs clés partagent, chacune tenant pour elles un nœud du niveau suivant. Une clé ne descend donc
d'un niveau que quand une autre clé partage ses bits, et aucun nœud ne tient jamais une clé seule en dessous de lui :
quand une clé est retirée et n'en laisse qu'une à côté d'elle, celle-ci remonte dans son parent. Une lecture suit un
chemin depuis la racine, environ $\log_{32} n$ niveaux, ce qui s'écrit $O(\log_{32} n)$ : 3 pour 30 000 clés, 4 pour un
million. Une écriture ne copie que les nœuds de ce chemin, et de chacun seulement l'array qu'elle change, en partageant
le reste avec l'ancienne map : c'est le *structural sharing* (le partage de structure).

```text
a map of 100,000 keys
root: 32 places, each a node, by bits 1-5 of the hash
└── place 17: a node of 32 places, by bits 6-10
    └── place 4: a node of about 98 keys under 32 places
        ├── "apple" -> 3, "pear" -> 9, ...      the keys alone at their place, inline
        └── place 12: a node of the 3 keys that share it
```

Quand plus rien d'autre ne tient une map devenue un trie, son bit owned permet à une écriture de changer ses propres
nœuds sur place : chaque nœud porte la marque de la map qui l'a fait, et ses arrays gardent de la place pour quelques
clés de plus, doublée quand ils se remplissent, jusqu'à 32. Une écriture dans une map partagée fait des nœuds sans
marque, que personne ne change sur place.

Avant CHAMP, les maps profondes de Cesia finissaient en blocs de 8 clés au plus, chacun fait avec de la place pour 8 quel
que soit son contenu : à 500 000 clés, un niveau de blocs d'une ou deux clés chacun, à cinq niveaux de profondeur, et un
heap (la mémoire où vivent les blocs alloués) de 16 millions de mots, 128 MB, là où celui de CHAMP en prend 7,7 millions,
avec un cinquième de l'allocation (`bench/maps.ce`, les compteurs du garbage collector d'OCaml, la partie qui libère la
mémoire que plus rien n'utilise).

Chaque clé du trie porte son rang dans l'ordre d'insertion, donc [dict.Keys] donne les clés dans l'ordre où elles sont
arrivées, à toute taille.

**Pourquoi la table d'abord.** Le benchmark (le programme de mesure) `bench/maps.ce`, 500 000 clés de texte écrites puis
lues, prenait 815 ms dans le trie et 275 ms dans la table, 258 depuis que ses clés sont faites en une copie (11 runs de
chaque langage, en alternance, [Vitesse](speed.md#le-calcul)) : une lecture du trie suivait quatre ou cinq nœuds, chacun
un cache miss (une donnée absente des caches du processeur, qu'il faut aller chercher en mémoire) dès que la map les
dépasse, 18,7 misses du dernier niveau de cache par opération contre 4,3 pour Go et 3,7 pour Python (comptés par les
compteurs du processeur lui-même) ; et chaque nœud, chaque clé et chaque entier boxed était copié hors du jeune heap
d'OCaml et marqué de nouveau à chaque cycle majeur de son collector. La table tient une clé dans une entrée et sa valeur
entière dans un array d'entiers que le collector parcourt sans rien suivre. Une map est partagée puis écrite bien moins
souvent qu'elle n'est construite ou lue, et quand elle l'est, elle devient, une fois, le trie dont la persistance a
besoin.

Trois détails comptent pour la sûreté et pour les nombres :

- **Le hash prend un seed**, un nombre aléatoire tiré une fois par run. Sans lui, quelqu'un qui connaît la fonction de
  hash pourrait envoyer à un serveur des clés qui partagent toutes un même hash, et chaque lecture les parcourrait
  toutes : une attaque par *hash flooding* (on inonde la table de clés de même hash), un denial of service (un déni de
  service : le serveur ne répond plus).
- **Les clés dont les 30 bits de hash sont tous égaux** vont dans un arbre binaire équilibré, trié par clé, donc même des
  clés choisies pour entrer en collision coûtent $O(\log n)$, jamais $O(n)$. Dans la table, des clés qui tombent ensemble
  font de longues suites de slots pleins : une nouvelle clé dont le probe (la suite des slots qu'elle parcourt) dépasse
  128 slots change la map en trie, qu'aucun choix de clés ne rend plus profond. Des clés aléatoires n'en approchent pas :
  dans une simulation de notre table à sa charge, le plus long probe d'une insertion était de 45 slots en dix runs d'un
  million de clés aléatoires, et de 51 en deux runs de quatre millions.
- **`1` et `1.0` sont une seule clé**, puisque ce sont des nombres égaux : le hash d'un nombre se calcule à partir de sa
  valeur.

```cesia
m = {1: "one"}
m[1.0] --> "one"
```

## Le JIT

Le JIT de Cesia est dans `src/jit/`. C'est un *method JIT* qui compile aussi des *loop regions* (des régions de
boucle) : il fait du code machine pour toute une version d'une fonction, ou pour l'une de ses boucles, plutôt que pour un
seul chemin à travers le programme, comme le fait un *tracing JIT*. Il n'est pas chargé au démarrage : c'est un plugin
(un module chargé à part, seulement quand il sert), `cesia_jit.cmxs`, chargé une fois, à la première unité qui devient
hot, donc un programme qui ne devient jamais hot ne le paie jamais.

### Quand le code devient hot

- Une version d'une fonction dont l'inférence prouve que le résultat est un nombre, un entier ou un float, après
  1 000 appels.
- Une boucle, au deuxième checkpoint rencontré à l'intérieur : après 10 000 à 20 000 tours d'une boucle qui tourne
  seule. Une boucle qui tourne souvent mais brièvement, comme dans une fonction appelée pour chaque requête, devient
  hot une fois que ses runs font 100 000 pas en tout.

`CESIA_JIT=always` compile chaque candidat à son premier appel ou à son premier run, ce dont les tests se servent pour
comparer les deux niveaux d'exécution, l'interpréteur et le code machine, sur toute la suite. `CESIA_JIT_SHOW=1` affiche
chaque unité compilée, ou pourquoi le JIT ne s'est pas chargé.

### Ce qu'il produit

Le JIT change une unité hot en sa propre *intermediate representation*, une IR (une forme du programme entre la
source et le code machine) : des basic blocks (des suites d'instructions où l'on n'entre que par le début et d'où l'on
ne sort que par la fin) d'instructions typées sur des registres virtuels, de trois sortes, entier, float et valeur. Il
écrit l'IR sous forme de texte pour [MIR](references.md#le-jit), un petit compilateur de Vladimir Makarov, écrit en C et
copié dans `src/sys/mir/`, qui fait le code machine. Les entiers sont rangés doublés dans les registres, `2n` pour `n`,
pour que le flag d'overflow du processeur lui-même (le bit d'état qu'il lève quand un calcul déborde) signale sans aucun
coût l'overflow à 63 bits des entiers de Cesia.

**Un seul point de rencontre par boucle.** L'exécution du code machine d'une boucle peut partir vers l'interpréteur et
revenir : à un checkpoint complet, quand le collector doit faire de la place, ou après un pas qu'un guard (un test du
code machine qui vérifie un pari) a laissé à l'interpréteur en échouant. Chacun de ces retours revient *avant* la boucle,
là où le même test de son compteur et le même pas y mènent, jamais dans son corps : l'entrée à la tête d'une boucle de
Fink et Qian, 2003. MIR travaille en *SSA form* (static single assignment), où chaque variable est affectée une seule
fois et où un *phi*, une fusion de ses versions, se tient à chaque bloc où des chemins se rejoignent ; sortir de la SSA
form met une copie sur chaque chemin qui entre dans un tel bloc (Boissinot et ses coauteurs, 2009). Quand l'exécution
revenait dans le corps, chaque variable de la boucle s'y rejoignait, à chaque tour, et MIR, qui en garde la plupart dans
des slots de la stack, copiait chacune d'un slot à un autre : environ 60 instructions par tour de `dyn` et de `structs`.
Désormais, seul ce que la boucle change se rejoint au début de son corps : `dyn` tourne en 1 340 millions d'instructions
au lieu de 1 919, et en 114 ms au lieu de 184 ; `structs` en 1 220 millions au lieu de 1 500, en 187 ms au lieu de 225
(11 runs chacun, en alternance, à côté du binaire de la branche main).

**Un nombre reste un nombre d'un tour à l'autre.** Dans `dyn`, `total` vient d'un appel à travers une valeur, donc
l'inférence ne peut pas lui donner de type, et avant, chaque tour mettait son float dans une nouvelle valeur boxed et l'en
sortait à son usage suivant. Une variable de la boucle que la frame tient comme float ou comme entier quand la boucle est
compilée, et que la boucle lit avant de l'affecter dans un tour, ou n'affecte qu'avec de l'arithmétique, reçoit désormais
un registre de float ou d'entier pour toute l'exécution : le code machine vérifie sa sorte une fois, à l'entrée, chaque
affectation donne cette sorte ou fait un bail (rend la main à l'interpréteur), et la box n'est faite qu'une fois, quand
l'exécution réécrit ses variables pour l'interpréteur. C'est l'*unboxing* (sortir un nombre de sa box) par spéculation,
la façon dont HotSpot et LuaJIT gardent l'accumulateur d'une boucle dans un registre. Avec lui, un registre lu après les
appels de la write barrier (le code qu'OCaml exécute à chaque écriture d'un pointeur dans un bloc, pour tenir son garbage
collector au courant) était gardé par MIR dans un slot de la stack pendant toute la boucle ; l'exécution réécrit donc
maintenant ses nombres avant ces appels : `total` vit dans un registre, et un tour de `dyn` coûte 64 instructions et
18 cycles du processeur, contre 126 et 34 avant cette partie et la suivante (les compteurs du processeur, le coût d'un
tour de plus, mesuré comme la différence entre 10 et 20 millions de tours).

**Une valeur est marquée partagée une seule fois.** Une liste ou une map lue d'une liste dans une variable est tenue deux
fois, donc elle doit perdre son bit *owned* ([copy-on-write](#value-semantics-et-copy-on-write)) avant que rien ne
puisse l'écrire sur place. Le code machine n'écrit sur place aucune variable de ce genre, donc il efface maintenant le
bit une seule fois, quand l'exécution réécrit la variable, au lieu de le faire à chaque lecture ; une valeur dont le code
sait que c'est un nombre n'a besoin d'aucune marque.

**Des bornes prouvées.** `math.Mod(i, 4)` par une constante positive est entre 0 et 3, donc `math.Mod(i, 4) + 1` ne peut
pas faire d'overflow : l'addition se fait sans test. C'est la *range analysis* (l'analyse des intervalles de valeurs),
dans sa plus petite forme, sur les bornes des registres d'entiers. Les tests du programme prouvent aussi des bornes, dans
chaque branche d'un `if` qui compare un paramètre à une constante, quand la fonction n'affecte jamais ce paramètre : à
partir du `else` de `if n < 2`, `n` vaut au moins 2, donc `n - 1` et `n - 2` se font sans test. Une borne peut ne tenir
que d'un côté : `n >= 2` ne dit rien de la taille de `n`, et pourtant `n - 1` ne peut pas faire d'overflow, puisqu'il
descend depuis au moins 2 et ne peut pas monter. Les tests qui gardent les branches sont la façon dont ABCD (Bodík, Gupta
et Sarkar, 2000) prouve ses bornes, comme des contraintes qui tiennent le long de chaque arête du programme.

**Une feuille à l'appel.** `fib` est un arbre d'appels, et la moitié de ses 30 millions d'appels sont des feuilles,
`fib(0)` et `fib(1)`, qui ne font que rendre leur argument ; chacune payait un appel entier, la sauvegarde et la
restauration de cinq registres comprises. Quand le corps d'une fonction appelée commence par un test de ses paramètres
qui donne l'un d'eux ou une constante, comme `if n < 2 then n`, le JIT fait ce test à l'appel, sur les arguments :

```text
fib(n - 1)        before: a call, whatever n - 1 is
                  after:  if n - 1 < 2, and its frame is under the limit of depth, and the fuel has a step left:
                              one step counted, the result is n - 1, no call
                          else the call, as before
```

Quand le test échoue, ou quand la frame atteint la limite de profondeur ou que le fuel (les pas qu'il reste à faire avant
le prochain checkpoint) est épuisé, l'appel est fait, et la fonction appelée fait ce qu'elle a toujours fait à son
entrée, donc les limites de profondeur et de pas, et les traces, restent celles de l'interpréteur. C'est le *partial
inlining* (Zhao et Amaral, 2005) : la partie d'une fonction qui rend la main tôt est copiée dans ses appelants, le reste
reste un appel. Un appel de `fib` coûte 18,8 instructions et 5,5 cycles au lieu de 26,4 et 7,2 (les compteurs du
processeur, le coût d'un appel de plus, mesuré comme la différence entre `fib(30)` et `fib(35)`), contre 14,5 et 5,9 pour
Go.

**Une map qui n'est jamais faite.** Dans `structs`, chaque tour lit une map dans une liste, calcule avec ses champs, et
écrit une nouvelle map au même endroit :

```text
p = ps[i]
vy = p.Vy - 9.81 * dt
ps[i] = {X: p.X + p.Vx * dt, Y: p.Y + vy * dt, Vx: p.Vx, Vy: vy}
```

`p` ne sert que pour ses champs, donc le code machine ne la fabrique jamais : quand il lit `ps[i]`, il vérifie que la map
qui s'y trouve a ces clés et une zone de floats, et charge ses quatre doubles dans des registres, qui tiennent lieu de
`p`. C'est le *scalar replacement* (Stadler, Würthinger et Mössenböck, 2014) : une valeur remplacée par ses morceaux. Si
l'exécution doit rendre la main à l'interpréteur, la map est faite à ce moment-là, à partir de ces registres, et
seulement alors : c'est l'*allocation sinking* (une allocation repoussée jusqu'à l'endroit où elle sert), comme le fait
LuaJIT sur ses traces (Pall, 2012). Et la nouvelle map réécrite a les mêmes clés, toutes des floats : quand la map
qu'elle remplace est owned, rien d'autre ne peut la voir, donc ses quatre doubles sont écrits sur place, dans la zone de
l'ancienne map, ce que la value semantics permet ; c'est la réutilisation d'une valeur unique dont Lorenzen, Leijen et
Swierstra (2023) font la règle des programmes fonctionnels *fully in-place* (entièrement sur place). Un tour n'alloue
alors rien et n'appelle aucune write barrier ; quand la map qui est là ne peut pas les prendre, l'interpréteur fait cette
écriture-là et la boucle continue en code machine. Une struct reçoit la même chose, comme
`ps[i] = Particle(x, y, vx, vy, p.M)` dans `bench/real/particles.ce`. Les valeurs d'une map qui sont toutes des floats
sont des doubles dans sa zone ([Maps](#maps--une-hash-table-puis-un-hash-trie)), donc un champ est un seul chargement et la
vérification de sa sorte disparaît aussi : un tour de `structs` coûte 60 instructions et 24 cycles, contre 235 et 122
avant, mesurés de la même façon.

Il compile les nombres et les boucles sur eux, les arrays de floats et de valeurs lus et écrits par index, les appels
entre versions compilées, la récursion, dans une boucle les champs des maps et des structs et les nouvelles qu'elle y
fait, et les appels d'une fonction tenue dans une variable, comme le montre la partie suivante.

Une division ou un modulo d'entiers par une puissance de deux, comme `math.Mod(i, 4)`, devient un décalage ou un masque
de bits : une instruction de division coûte des dizaines de cycles, un masque un seul. Les résultats sont ceux de la
floored division (la division arrondie vers le bas), que donnent le `Div` et le `Mod` de Cesia, pour les nombres négatifs
aussi : `math.Mod(-7, 4)` vaut 1 dans les deux.

### Ce que coûte sa fabrication

Le code machine prend du temps à faire, qu'un run paie avant de gagner quoi que ce soit. MIR passe 6 à 7 µs sur chaque
ligne du texte que lui donne le JIT, à son niveau 2, où il travaille en SSA form, numérote les valeurs, sort d'une boucle
ce qu'elle ne change pas et alloue les registres (mesuré sur une copie de MIR avec une horloge sur chacune de ses passes :
faire la SSA form prend un quart du temps, allouer les registres un sixième, la liveness des valeurs, savoir où chacune
sert encore, un dixième). Son niveau 1 fait du code en 40 % de temps en moins, et `matmul` tourne alors moitié plus
longtemps : le niveau 2 reste. Le JIT donne donc moins de lignes à MIR :

- Les chemins qu'une exécution prend quand il se passe quelque chose de rare, une vérification qui échoue, une limite,
  une erreur, écrivent ce dont l'interpréteur a besoin pour continuer, et faisaient les quatre cinquièmes des lignes de
  `fib`. Les stubs (les petits bouts de code de ces chemins) de ceux qui ne reviennent jamais finissent désormais dans un
  bloc que leur fonction partage, un pour une erreur, un pour une frame au-delà de la limite de profondeur, un pour un
  appel qui remonte après que sa fonction appelée s'est arrêtée : chaque stub met ses propres valeurs dans quelques
  registres et y saute.
- La frame la plus extérieure d'une version, celle qu'appelle l'interpréteur, appelle une copie imbriquée de la version
  au lieu d'en contenir le code inline : elle tourne une fois par appel venu de l'interpréteur, et la copie imbriquée
  fait le travail. Cela a aussi corrigé une boucle qui appelait sa propre fonction : MIR refusait l'appel, et son erreur
  éteignait le JIT pour le reste du programme.
- Les vérifications des arrays d'une exécution, et ses constantes, sont écrites une fois pour son début et ses reprises,
  et non deux fois.
- La base de la frame d'une fonction appelée dont le code est inline est écrite à partir de la base de la fonction
  elle-même et d'une constante, donc aucun registre ne la tient à travers un appel.

L'unité de `fib` est passée de 1 200 lignes et 7,4 ms de compilation à 700 lignes et 3,4 ms ; les deux unités de
`matmul`, de 1 310 lignes à 1 090, et de 10,4 ms à 8,4. Un stub qui revient dans sa boucle, celui qui prend un nouveau
quantum de fuel, reste inline : sous forme d'appel, il faisait garder par MIR chaque float de la boucle en mémoire à
chaque tour, autour d'un appel qu'il ne fait presque jamais. Ce qui reste du coût fixe, à côté du démarrage du processus
(2,6 ms) : charger le plugin, 0,65 ms, et la compilation de MIR, 3 à 4 ms par unité.

### Paris, guards et bails

Là où l'inférence ne peut pas prouver un type, le JIT *spécule* : il regarde les valeurs de la frame quand il compile, le
*type feedback* (ce que les valeurs déjà vues disent de leurs types), et parie qu'elles gardent leur sorte, que `p` reste
un `Particle` et `p.X` un float. Chaque pari est un *guard*, un test dans le code machine. Quand un guard échoue, le code
machine s'arrête avant le statement où il a échoué, chaque variable remise dans son slot comme l'interpréteur la veut, et
l'interpréteur continue à partir de ce statement : c'est un *bail*, que d'autres JIT appellent *deoptimization*. La
boucle retrouve son code machine à son tour suivant. La réponse est la même, un peu plus tard.

Entrer dans du code machine au milieu d'une boucle qui tourne déjà, à un checkpoint, s'appelle l'*on-stack
replacement* ; Cesia le fait pour les boucles, en mettant le compteur et la borne d'un `for` dans leurs slots.

### Les appels à travers une valeur

Un appel d'une fonction tenue dans une variable, comme `f(total, x)` où `f` vient d'une liste de fonctions, peut
atteindre une fonction différente à chaque fois. L'interpréteur note, à chaque appel de ce genre, les fonctions qu'il a
atteintes, quatre au plus. Le JIT parie sur elles : le code machine compare la fonction à la première, puis à la
deuxième, et appelle celle qui correspond comme il appelle une fonction nommée dans le code, ou copie son corps sur
place, ce qui s'appelle l'*inlining* ; une fonction qu'il n'a pas vue fait un bail, comme un guard qui échoue. C'est un
*polymorphic inline cache* (un inline cache pour plusieurs formes), l'idée de Hölzle, Chambers et Ungar (1991), dont V8
et HotSpot se servent pour la même sorte d'appel. Un appel qui a atteint cinq fonctions ou plus est *megamorphic* (il a
trop de formes pour un cache) : le JIT le laisse à l'interpréteur, comme un appel d'une fonction qui a capturé des
variables, ou qui prend ou donne autre chose que des nombres.

```text
f(total, x)                      in machine code
├── f is (a, b) -> a + b ?       total + x, unboxed, inline
├── f is (a, b) -> a * 0.5 + b ? total * 0.5 + x, inline
└── else                         back to the interpreter, before the statement
```

### Le contrat

Le même programme donne la même sortie, les mêmes erreurs aux mêmes lignes et les mêmes limites, dans l'interpréteur et
en code machine. Le code machine compte les pas comme l'interpréteur, vérifie les bornes et l'overflow comme lui, et
part vers l'interpréteur à chaque checkpoint complet, où les autres fibers ont leur tour. Il n'exécute jamais le garbage
collector : chaque tour d'une boucle compilée réserve d'abord la mémoire dont il aura besoin, et part s'il n'y en a pas
assez, donc le collector tourne en OCaml comme d'habitude. Les tests exécutent toute la suite dans les deux niveaux, et
une différence est un bug du JIT.

### Ce qui reste dans l'interpréteur

- les natives, des fonctions de `std/` écrites en OCaml, comme [text.Split] : elles sont déjà du code machine ;
- `for x in xs` sur les éléments d'une liste, et un appel à travers une valeur qui a atteint cinq fonctions ou plus, ou
  une fonction qui a capturé des variables ;
- une map lue ou écrite avec une clé calculée pendant que le programme tourne, comme `m["key$k"]`, et le texte construit
  pour elle. Le code natif ne rappelle jamais OCaml : rien ne collecte pendant une exécution, ce qui permet aux valeurs
  qu'il tient de rester dans des registres, où le collector ne pourrait pas les trouver pour les déplacer. Le hash, le
  probe de la table, sa croissance et le nouveau texte demanderaient chacun un tel appel, avec chaque valeur réécrite
  dans son slot avant et relue après ; ce que le code natif pourrait épargner, c'est la part propre de l'interpréteur
  dans `bench/maps.ce`, un dixième de son temps dans son profil (la mesure de l'endroit où passe le temps), et ces appels
  en reprendraient une bonne partie ;
- sous un debugger (un programme qui exécute le vôtre et peut l'arrêter, pour montrer ses variables), les fonctions qui
  tiennent un breakpoint (une ligne où le programme doit s'arrêter) et le code que vous parcourez pas à pas ;
- tout sur arm64, comme les puces d'Apple, pour l'instant : les programmes y tournent dans l'interpréteur, avec les mêmes
  résultats.

### Ce qu'il gagne

Mesuré le 2026-11-09, profil `release`, sur la machine de [Vitesse](speed.md#à-côté-des-géants) pendant que
d'autres travaux y tournaient : chaque programme de `bench/` 11 fois avec le JIT et 11 fois avec `CESIA_JIT=off`, en
alternance avec les géants, du début du processus à sa fin (`real/particles` contre le binaire de la branche main, en
alternance). La médiane (la valeur du milieu des temps triés), puis son intervalle à 95 % (celui qui contient la vraie
médiane avec une probabilité de 95 %) :

| Programme | Ce qu'il fait | Avec le JIT | Interpréteur seul |
|---|---|---:|---:|
| `fib` | `fib(35)`, des appels récursifs sur des entiers | 58 ms (57–59) | 441 ms (438–489) |
| `mandel` | une boucle de floats | 61 ms (61–62) | 456 ms (453–467) |
| `matmul` | des matrices de floats, lues par index | 44 ms (43–45) | 977 ms (963–1 017) |
| `structs` | 1 000 maps de 4 floats, refaites 5 000 fois | 46 ms (44–48) | 587 ms (579–594) |
| `real/particles` | 2 000 structs, la gravité et des murs | 53 ms (49–59) | |
| `dyn` | des appels à travers une liste de fonctions | 55 ms (55–57) | 761 ms (692–802) |
| `maps` | 500 000 clés de texte écrites puis lues | 257 ms (254–263) | 256 ms (251–278) |

`fib` prenait 74 ms la veille, jusqu'à ce que les feuilles de sa récursion soient testées à leur appel et que son unité
demande à MIR moitié moins de temps de compilation. `dyn` appelle chaque fonction à travers une valeur ; le JIT en fait
du code machine, avec son inline cache de fonctions, ses `math.Mod(i, 2)` et `math.Mod(i, 4)` changés en masques de bits,
et son `total` gardé en float dans un registre : avant cela, le 2026-11-08, il prenait 714 ms avec le JIT, puis 182
avant que sa boucle ne soit plus entrée que par sa tête, et 114 avant que `total` reste dans un registre. `structs`
prenait 219, puis 186 avant que ses maps soient gardées en doubles, et `real/particles` 175, puis 136. La boucle de
`maps` construit un texte à chaque tour et reste dans l'interpréteur : son gain est celui de la hash table.

[Vitesse](speed.md#à-côté-des-géants) met ces programmes à côté de Python, Node, Java, Go, OCaml, Lua et LuaJIT.

## Les fibers et le scheduler

Une [fiber](fibers.md) est une fonction qui tourne à côté des autres, dans le même programme, avec sa propre stack : ce
que d'autres langages appellent un *green thread* (un thread mené par le langage plutôt que par le système) ou une
*coroutine*. Toutes les fibers tournent sur un seul thread du système (un fil d'exécution que le système d'exploitation
fait tourner), une à la fois. Elles sont *concurrentes*, ce que l'anglais appelle concurrency : plusieurs en cours, qui
se relaient ; elles ne sont pas *parallèles*, le parallelism : plusieurs au même instant, sur plusieurs cœurs.

### Comment une fiber s'arrête et repart

Les fibers de Cesia sont les *effect handlers* d'OCaml 5, dans `src/lib/fiber.ml`. Un *effect* est comme une exception
qui peut revenir : une fiber qui doit attendre lance l'effect `Suspend`, et le handler qui entoure la fiber, le code qui
attrape l'effect, reçoit le reste du travail de la fiber, sa *continuation*, une valeur qui peut être reprise une fois.
Le handler la range dans la chose que la fiber attend, un channel, un timer (une minuterie), une socket (le bout d'une
connexion réseau), et rend la main au scheduler. Quand la chose est prête, la continuation va dans la queue (la file
d'attente) des fibers prêtes à tourner, et elle est reprise à son tour. Une continuation tient la stack OCaml de la
fiber, qui commence petite et grandit au besoin : une nouvelle fiber prend environ 270 mots, 2,1 KB, comme le mesure
`tools/fiber-size.sh`, avec ses trois stacks de 8 slots ; environ 1 KB de cela est la stack OCaml, qu'OCaml commence à
64 mots et double au premier appel de la fiber. Un seul handler, fait une fois, sert toutes les fibers : l'effect porte
la fiber qui le lance, et le réveil d'une fiber mise en attente est gardé dans le contexte de la fiber, où
[fiber.Cancel] le trouve. Le programme principal n'est pas une fiber : il garde sa propre stack, et quand il attend, il
fait tourner lui-même le scheduler jusqu'à ce qu'on le réveille.

Le *scheduler*, la partie qui choisit la fiber qui tourne, garde une seule queue, premier entré, premier sorti, des
fibers prêtes à tourner. Une fiber tourne jusqu'à l'un de ces moments :

- elle attend : [sys.Sleep], une lecture ou une écriture sur le réseau qui bloquerait, [fiber.Wait], [fiber.Receive],
  [fiber.Select], un [fiber.Send] sur un channel plein, une base de données occupée ;
- elle atteint un checkpoint complet, tous les 1 000 000 pas, pendant qu'une autre fiber est prête : elle va alors au
  bout de la queue ;
- elle se termine, ou fait une panic (l'arrêt sur un bug).

Un long calcul ne peut donc pas retenir les autres plus d'un million de pas. C'est proche de ce que fait Erlang en
comptant des *reductions* (des unités de travail), et Erlang appelle cela *preemptive* (préemptif) : personne n'écrit de
yield, l'instruction qui cède la main. Ce n'est pas la préemption d'un thread du système, qu'un timer peut interrompre
n'importe où : une fiber n'est changée qu'à une attente ou à un checkpoint. Deux conséquences :

- une native tourne jusqu'à sa fin : [list.Sort] d'un million d'éléments, ou [json.Parse] d'un gros fichier, tourne en
  entier avant qu'une autre fiber ait son tour ;
- dans du code machine qui s'appelle lui-même, une récursion compilée par le JIT, un changement de fiber attend que
  l'appel compilé le plus extérieur revienne ou que sa boucle atteigne son pas suivant. Les résultats ne changent
  jamais ; seul l'ordre dans lequel les fibers affichent peut y être différent.

Puisqu'une fiber n'est changée qu'à ces moments-là, le code entre deux d'entre eux ne voit aucune autre fiber : il n'y a
pas de *data races*, deux threads qui changent la même mémoire en même temps, et aucun lock (ce qui réserve une donnée à
un seul à la fois et fait attendre les autres) à prendre. Les valeurs ne sont de toute façon pas partagées : une valeur
envoyée sur un channel agit comme une copie.

### Attendre le système

Une socket de Cesia est *non-blocking* (non bloquante) : une lecture qui n'a rien rend la main tout de suite, et la fiber
se met en attente. Quand aucune fiber n'est prête, le scheduler demande au système quelles sockets sont prêtes, et réveille
leurs fibers. Sur Linux, il utilise *epoll*, qui surveille n'importe quel nombre de sockets en ne coûtant que pour celles
qui sont prêtes ; sur macOS et Windows, *select*, qui en surveille jusqu'à 1 000. Tant que des fibers sont prêtes, il
regarde quand même le système tous les 256 tours, donc un programme occupé continue d'entendre le réseau. Les timers,
pour [sys.Sleep] et les timeouts (les délais au-delà desquels on abandonne), sont gardés dans un arbre trié par leur
échéance.

Quand chaque fiber attend, que rien n'est prêt et que rien ne peut l'être, puisqu'aucune socket, aucun timer ni aucun
signal n'est attendu, le programme attendrait pour toujours : c'est un *deadlock* (des tâches qui s'attendent l'une l'autre, sans fin). Cesia l'arrête avec
la ligne de l'attente :

```cesia fails
use std/fiber
ch = fiber.Channel()
fiber.Receive(ch)
```

### L'annulation et les panics

[fiber.Cancel] marque une fiber. Si la fiber attend, elle est réveillée tout de suite ; sinon, elle s'arrête à sa
prochaine attente ou à son prochain checkpoint complet. Dans les deux cas, la fiber remonte ses appels comme lors d'une
panic, sans rien afficher, et [fiber.Wait] donne un `Err` de sorte `"cancelled"` avec le fichier et la ligne où elle en
était. Une panic dans une fiber ne termine que cette fiber, et sa tâche donne un `Err` avec le message. Une fiber qui
prend plus de mémoire que la limite, ou qui imbrique une valeur trop profondément, s'arrête seule elle aussi : la requête
d'un serveur qui prend trop échoue seule, et libère ce qu'elle a pris.

## Channels

Un channel, [fiber.Channel], est une queue de valeurs entre fibers. Il vient des *communicating sequential processes*,
CSP, le modèle de C. A. R. Hoare en 1978, où des processus ne partagent aucune mémoire et ne font qu'échanger des
messages, et de Go, dont les channels le suivent. Ceux de Cesia sont proches de ceux de Go, avec ces règles exactes :

- **Sans borne par défaut.** [fiber.Send] n'attend jamais sur un channel créé sans taille : il peut tenir n'importe quel
  nombre de valeurs, autant que la mémoire le permet.
- **Borné avec une taille.** Avec `size = n`, le channel tient au plus `n` valeurs, et un envoi sur un channel plein met
  sa fiber en attente jusqu'à ce qu'un receveur prenne une valeur : c'est la [backpressure](glossary.md#backpressure),
  un destinataire lent qui ralentit son expéditeur.
- **Une taille de 0 est un rendez-vous.** Chaque envoi attend un receveur, donc les deux fibers se rencontrent : le
  channel synchrone du CSP de Hoare, et l'unbuffered channel (le channel sans buffer) de Go.
- **Premier arrivé, premier servi.** Le plus ancien receveur en attente sur un channel reçoit la valeur suivante, et le
  plus ancien expéditeur en attente sur un channel plein passe en premier.
- **Fermer.** Après [fiber.Close], les valeurs déjà dans le channel arrivent encore, puis [fiber.Receive] donne un `Err`
  de sorte `"closed"`. Un envoi sur un channel fermé, ou une seconde fermeture, est un bug, et fait une panic.
- **Select dans l'ordre.** [fiber.Select] prend dans le premier channel de sa liste qui a une valeur, dans l'ordre de la
  liste. Go choisit au hasard parmi ceux qui sont prêts ; l'ordre de Cesia permet à un programme de donner la priorité à
  un channel, comme un ordre d'arrêt avant le travail.

## Le serveur

[http.Serve] est écrit en Cesia, dans `src/std/http.ce`, sur [std/net]. Une fiber accepte les connexions, et chaque
connexion reçoit une fiber à elle, qui lit les requêtes, appelle le handler (la fonction du programme qui répond à une
requête) et écrit les réponses. Une connexion reste ouverte entre les requêtes : c'est le *keep-alive* de HTTP/1.1. Une
dernière fiber, le reaper (le faucheur), ferme chaque connexion qui dépasse son échéance. Un client lent ne met en
attente que sa propre fiber, donc les autres continuent.

### Sur chaque cœur

Un processus utilise un cœur. `cesia run --workers N` sert sur `N` processus, depuis `src/sys/workers.ml`, dans le
modèle *pre-fork* des serveurs comme nginx, où les processus qui servent sont lancés d'avance :

1. Le premier processus exécute le programme jusqu'à ce qu'il ouvre son listener, la socket qui prend les nouvelles
   connexions. Il devient alors le *supervisor* : il lance les workers (les processus qui servent), et ne sert rien
   lui-même.
2. Chaque worker est un `cesia run` du même programme, qui reçoit ce listener comme entrée standard, et y accepte ses
   connexions. Les workers partagent le listener et rien d'autre : chacun a sa propre mémoire, ses fibers et ses valeurs.
3. Sur Linux, chaque worker surveille le listener avec `EPOLLEXCLUSIVE`, donc une nouvelle connexion réveille un seul
   worker, et non tous, qui se la disputeraient : le problème du *thundering herd* (le troupeau qui se rue).
4. Un worker qui se termine est relancé ; celui qui se termine moins d'une seconde après son lancement attend d'abord,
   0,1 s, puis deux fois plus longtemps à chaque fois, jusqu'à 30 s, donc un worker qui ne peut pas démarrer ne tourne
   pas en boucle.
5. Au signal HUP, le supervisor lance un nouvel ensemble de workers à partir des fichiers tels qu'ils sont maintenant.
   Une fois que chacun d'eux accepte, les anciens reçoivent le signal TERM, et chacun finit les requêtes en cours. Le
   listener reste ouvert tout du long, donc aucune connexion n'est refusée : c'est un *zero-downtime reload* (un
   rechargement sans interruption de service). Les nouveaux workers qui n'acceptent pas dans les 30 secondes sont
   arrêtés, et les anciens restent.

Les workers écrivent leurs lignes sur une seule sortie standard. Une écriture d'au plus 4 096 octets qui finit une ligne
est *atomique* (faite d'un seul coup) sur un pipe (le tuyau qui relie deux processus), par la règle de POSIX appelée
`PIPE_BUF` : l'écriture d'aucun autre worker ne peut la couper, donc les lignes de [std/log] ne se mélangent jamais.

### Ce qu'il sert

Sur un cœur de la machine ci-dessus, une toute petite route répond à environ 64 000 requêtes par seconde avec
100 connexions gardées ouvertes, et la route JSON à 47 700, devant Node, sans perdre une requête, et une connexion
inactive prend 2,3 KB : ce sont les médianes de 6 runs de `tools/http-bench.sh`, que
[Vitesse](speed.md#un-serveur-sous-charge) donne en entier, à côté de Node et de Go, avec là où ils gagnent.
`tools/http-gate.sh` fait échouer un changement du serveur qui perd une requête, passe sous Node ou sous ses planchers,
dépasse 10 ms au 99e percentile (le temps sous lequel tombent 99 % des réponses), ou laisse `--workers 2` donner moins
d'une fois et demie ce que donne un seul processus.

Chaque requête exécute son handler dans une fiber à elle, qui commence avec de petites stacks et les fait grandir dans
ses premiers appels. Chaque croissance demandait à OCaml la taille de son heap, pour vérifier la limite de mémoire, et
OCaml la compte en parcourant ses pools (ses réserves de blocs de même taille) : un dixième du temps d'un serveur, dans
le profil de la route JSON (les stacks de gdb, relevées toutes les 3 ms). Les stacks de moins de 4 096 entrées sont
désormais laissées à la vérification des checkpoints complets. Les timers du scheduler, un ou deux par requête, sont
gardés dans un arbre équilibré ordonné par leur temps, qui compare désormais un temps et un nombre directement, sans
passer par la comparaison générique d'OCaml. Ces deux changements ont rendu la toute petite route un cinquième plus
rapide, et la route JSON 14 % plus rapide que le binaire d'avant.

À 1 000 connexions gardées ouvertes, un cœur sert 1 000 fibers à tour de rôle, et la *Little's law* (la loi de Little)
fixe le plancher de la latence : un serveur qui répond à $\lambda$ requêtes par seconde avec $L$ d'entre elles en
attente répond à chacune en $L / \lambda$ en moyenne, $1\,000 / 36\,200\ \text{s} = 27{,}6\ \text{ms}$ ici, donc son
99e percentile ne peut pas descendre sous cette valeur tant qu'il ne répond pas à plus de requêtes. Les requêtes en cours
survivent aussi à plus de minor collections d'OCaml (les collections du jeune heap) : les données d'une requête sont
copiées dans le major heap, 478 mots par requête à 1 000 connexions contre 69 à 100 (les compteurs d'OCaml, `v=0x400`),
et le collector y prend environ un cinquième du temps.

## La mémoire et le garbage collector

Cesia ne libère pas la mémoire lui-même : le *garbage collector* d'OCaml le fait, le GC, qui trouve les blocs vers
lesquels plus rien ne pointe et réutilise leur mémoire. Celui d'OCaml est *generational* (il range les blocs par
générations) : les nouveaux blocs vont dans un petit *minor heap*, qui est vidé souvent et vite, parce que la plupart des
blocs meurent jeunes, comme les floats boxed d'un calcul ; les blocs encore vivants passent dans le *major heap*, qui est
collecté petit à petit, par tranches, donc un programme ne s'arrête jamais longtemps. Cesia fait grandir le minor heap
des 2 MB d'OCaml à 16 MB, 2 millions de mots, au premier checkpoint d'un programme, ou une fois qu'il a chargé 32 KB de
source, puisque ses closures et ses floats boxed y meurent presque tous jeunes. Le faire grandir coûte environ 0,15 ms,
qu'un programme court qui charge peu ne paie jamais.

Les arbres du code que fait un chargement sont un autre cas : ils vivent aussi longtemps que le programme, et la première
minor collection qui les suit les copie tous dans le major heap, environ 15 ns par mot. Au milieu du chargement d'un
programme de 324 KB de source en 44 modules, cela faisait 740 000 mots et 11 ms, un tiers de son chargement, à l'endroit,
quel qu'il soit, où le minor heap se remplissait. Aussi le lexer, le parser et le resolver font-ils aussi peu de déchets
qu'ils le peuvent : aucune closure pour chaque nœud de l'arbre ou pour chaque nom, et l'array des tokens d'un fichier est
vidé une fois le fichier lu par le parser, car un array de plus de 256 places est fait dans le major heap, et les jeunes
tokens vers lesquels il pointe seraient copiés avec les arbres, alors que plus rien ne les lit. Le chargement de ce
programme fait 1,84 million de mots au lieu de 3,38 millions et finit avant que le minor heap soit plein : 24,4 ms au lieu
de 38,2, les médianes de 21 runs, le 2026-11-11. Un chargement plus grand a une minor collection tous les 2 millions de
mots qu'il fait, chacune copiant les arbres faits depuis la précédente : chaque arbre est copié une fois, donc le coût
grandit comme le code.

La limite de mémoire, 80 % de la mémoire de la machine sauf si `--limit memory=` dit autre chose, est vérifiée aux
checkpoints complets et avant chaque grande allocation. Quand le heap semble la dépasser, Cesia fait d'abord une
collection complète, et n'arrête le programme que si la mémoire encore utilisée dépasse la limite : les déchets seuls ne
l'atteignent jamais.

Le travail sur des arrays et des colonnes entières de [std/num], [std/frame] et [std/sql] tourne sur plusieurs cœurs, à
travers les *domains* d'OCaml 5, ses threads du système : la moitié des cœurs logiques, 16 au plus, sauf si
`CESIA_CORES` dit autre chose. Un petit array reste sur un cœur, puisque lancer un domain a son coût. Ce travail ne
touche aucune valeur du programme pendant qu'il tourne, donc il ne peut pas y avoir de data race avec les fibers.

## Le démarrage

Un programme démarre tout de suite. Mesuré le 2026-11-09 sur la machine ci-dessus, 101 runs de chacun en
alternance avec le binaire d'avant ce changement, du début du processus à sa fin, la médiane :

| Programme | Temps |
|---|---:|
| `/usr/bin/true`, un programme qui ne fait rien | 0,53 ms |
| le `print_endline "1"` d'OCaml lui-même, compilé | 1,10 ms |
| `use std/io` et `io.Print(1)` | 2,62 ms, 2,84 avant |

Ce que fait un démarrage, compté par le compteur du processeur des instructions exécutées dans le programme, lu à des
points du démarrage dans un debugger, et par le compte que fait le système des *page faults*, chacun une page de 4 KB de
mémoire que le noyau mappe, copie ou met à zéro la première fois que le programme la touche, environ 2 µs chacun sur
cette machine :

- **Le loader corrige les adresses du binaire** : 850 000 instructions, contre 283 000 pour le programme d'OCaml
  lui-même. Le loader est le code du système qui charge un programme en mémoire. Cesia est un *position-independent
  executable*, un exécutable qui peut être chargé à n'importe quelle adresse, ce qui rend un bug en C plus difficile à
  exploiter ; chacun des 30 332 pointeurs de ses données reçoit donc en plus l'adresse où le binaire a été chargé, et
  chaque page de 4 KB où ils se trouvent, 256 en tout, est copiée pour le processus : un page fault chacune.
- **Le runtime d'OCaml (le code qui accompagne chaque programme OCaml) lit ses frame descriptors** :
  722 000 instructions. Un frame descriptor dit, pour un endroit du code où un appel revient, quels slots de la stack
  tiennent des valeurs, pour que le garbage collector puisse les trouver ; OCaml les met tous dans une hash table au
  démarrage, 19 723 pour Cesia, dont l'interpréteur, le compilateur, le parser et les natives de `std/` sont dans le
  binaire, contre 322 pour le programme d'OCaml lui-même. La table prend 512 KB, 129 page faults, et les descriptors
  eux-mêmes font les deux tiers des pages relocalisées ci-dessus.
- **Les modules démarrent** : 190 000 instructions, dont leurs tables de natives et de messages.
- **Le programme tourne** : 400 000 instructions, de la lecture de `cesia.toml` s'il y en a un jusqu'au dernier vidage
  de la sortie ; les sources de `std/` sont dans le binaire, donc rien n'est lu sur le disque sauf le programme
  lui-même. Un package de `std/` est lu quand un fichier l'utilise pour la première fois : un package écrit en Cesia,
  comme `std/list`, coûte environ 0,8 ms de plus pour passer par le parser et le resolver, comme l'a mesuré
  `bench/RESULTS.md` le 2026-11-07, à son premier run, et moins une fois qu'il vient du
  [cache des packages chargés](#le-cache-des-packages-chargés) ; les parties en OCaml ne coûtent rien tant qu'on ne les
  appelle pas.
- Le JIT, SQLite, le runner de `cesia test` (le programme qui lance les tests) et le moteur du debugger sont des plugins
  à côté du binaire, chargés à leur première utilisation. Aucun d'eux ne coûte quoi que ce soit à un programme qui ne
  s'en sert pas.

Le jeune heap ne grandit jusqu'à 16 MB qu'au premier checkpoint d'un programme, ou une fois qu'il a chargé 32 KB de
source ([La mémoire](#la-mémoire-et-le-garbage-collector)) : le faire grandir au démarrage coûtait à chaque programme
0,2 ms, environ 260 000 instructions et 70 page faults, la première collection comprise, dont un programme court n'avait
jamais besoin. Déplacer dans des plugins le code dont un run a rarement besoin retirerait du démarrage environ 6 % des
frame descriptors : la hash table n'est réduite de moitié que sous 16 384 descriptors.

Le chargement, le lexer, le parser et le resolver ensemble, lit environ 520 000 lignes par seconde : les 320 001 lignes
de `bench/load.sh` en 614 ms, la médiane de 11 runs, contre 648 ms avant que le chargement fasse moins de déchets, le
2026-11-11. C'est le premier run d'un package : les suivants le lisent dans le cache ci-dessous.

## Le cache des packages chargés

Le lexer, le parser et le resolver coûtent environ 3 µs par ligne, à chaque run : un programme qui utilise [std/plot]
lisait 2 300 lignes avant que sa propre première ligne ne tourne, environ les deux tiers de son temps. Cesia garde donc
la forme chargée de chaque package, ses arbres tels que le resolver les laisse, dans le *cache des packages chargés* (un
cache est une copie gardée pour ne pas refaire un travail) : le dossier `cesia/load` du dossier des caches,
`$XDG_CACHE_HOME`, ou `~/.cache` sans cette variable. Au run suivant, un package dont les fichiers sont les mêmes ne
repasse ni par le lexer, ni par le parser, ni par le resolver : ses arbres sont relus, et ses instructions tournent
comme avant. Rien d'autre ne change : la même sortie, les mêmes erreurs aux mêmes lignes, et la même vitesse une fois
que le programme tourne. Le code est dans `cache.ml` et `src/sys/entries.ml`.

**Ce que garde une entrée.** Un fichier par package, nommé d'après un digest (une empreinte, voir plus bas) de l'endroit
où est le package (son dossier, ou le nom d'un fichier de `std/` dans le binaire), et remplacé quand le package change :
l'arbre de chacun de ses fichiers après le resolver, les noms que chaque fichier lit dans chaque package qu'il utilise,
et les questions que le resolver a posées sur les autres modules, avec leurs réponses. Un nom que le resolver a lié à un
module d'un autre package garde ce module par sa place : le j-ième module, compté depuis la fin, du package du u-ième
use du fichier. Dans un autre run, les modules reçoivent d'autres numéros, et les places les retrouvent. Un package de
`std/` qui a des natives (des fonctions écrites en OCaml) les garde en dernier, et son code Cesia, qui ne se charge que
pour un fichier qui en nomme quelque chose, se place avant elles : comptée depuis la fin, une place reste la même, qu'un
autre package du run ait chargé ce code ou non. Rien n'est gardé pour ce qu'ajoute le debugger (`--debugger`), pour ce
que `cesia check` et les verdicts de `cesia test` lisent avec leurs propres règles, ni pour les packages de moins de 512
octets, que le parser lit plus vite qu'on ne trouve et ne vérifie leur entrée.

**Ce qu'un run vérifie avant d'utiliser une entrée**, dans cet ordre :

- le fichier est à la personne, et à personne d'autre : un fichier ordinaire, pas un lien, que personne d'autre ne peut
  lire ni écrire, dans un dossier qui n'est qu'à elle, ce que Cesia fait en le créant (les permissions 0700 pour le
  dossier, 0600 pour chaque fichier) ; le fichier ouvert est celui qu'on a regardé, le même device et le même inode (le
  disque et le numéro du fichier sur ce disque), donc un lien mis à sa place entre-temps n'est pas suivi ;
- son *digest* est celui écrit à son début. Un digest est une empreinte de tous les octets d'un fichier, qui change dès
  que l'un d'eux change ; celui de Cesia est BLAKE2b, sur 16 octets. Une entrée abîmée ou coupée n'est jamais décodée ;
- l'entrée nomme ce build de Cesia (cette version compilée du binaire), un digest de ses sources fait quand il est
  compilé, la même limite `nesting`, et le digest de chaque source du package, dans l'ordre : un fichier changé depuis
  le dernier run est relu. Un fichier de `std/` dans le binaire ne change qu'avec le build, et n'a pas besoin d'un
  digest à lui ;
- chaque use est retrouvé sur le disque, comme sans cache, et chaque question que le resolver a posée est reposée : ce
  qu'est un nom d'un package utilisé, dans quelle cellule il vit, si c'est un struct. L'entrée n'est utilisée que si
  chaque réponse est la même ; sinon le package repasse par le resolver depuis ses sources, comme quand un package qu'il
  utilise a gagné une fonction avant celle qu'il appelle, et son entrée est réécrite.

Le lecteur d'une entrée est de l'OCaml ordinaire, sans `Marshal`, le lecteur de valeurs d'OCaml lui-même, qui fait
confiance à ses octets : il vérifie chaque compte contre les octets qui restent, et chaque référence dans l'entrée, à un
texte, un module ou une définition, contre ce qui s'y trouve, donc une entrée fausse ne peut vouloir dire que « pas
utilisée ». Tout échec, une entrée absente, abîmée, d'un autre build, un dossier où l'on ne peut pas écrire ou un disque
plein, veut seulement dire que le package se charge comme sans cache. Les permissions ne sont jamais dans une entrée :
elles viennent de la ligne de commande et de `cesia.toml` à chaque run, comme les fichiers qu'un use nomme viennent du
disque.

**L'écriture.** Les entrées d'un run sont écrites une fois qu'il a fini, sa sortie partie et son code de sortie fixé,
par une copie du processus que la fin n'attend pas, faite avec `fork` (l'appel du système qui copie un processus) : un
run ne dure pas plus longtemps que sans cache. Avant toute chose, la copie ferme chaque descripteur du programme (le
numéro par lequel il tient un fichier, un socket ou un pipe ouvert), et le run ne finit qu'une fois qu'elle l'a fait :
un port sur lequel le programme écoutait, un verrou qu'il tenait et un pipe où il écrivait sont libres dès qu'il a fini,
et plus rien n'arrive dans un fichier qu'il écrivait. La copie met ensuite son entrée et sa sortie sur `/dev/null`,
quitte la session du terminal et ne garde aucun des gestionnaires de signaux du programme, donc un shell qui attend la
fin de la sortie, ou une touche qui arrête le programme, ni ne l'attend ni ne l'arrête ; elle finit en 10 s quoi qu'il
arrive, sans refaire la fin du programme. Un run tué, ou qui finit pendant que du travail tourne encore sur d'autres
cœurs, ne laisse pas d'entrée, pas plus qu'un run sur Windows, qui n'a pas `fork` : le run suivant lit ses packages
comme sans cache. Un programme qui tourne longtemps, comme un serveur, écrit ses entrées quand il s'arrête. Chaque
entrée est écrite dans un nouveau fichier à côté d'elle, qu'aucun autre fichier ne peut être (Cesia le crée avec
`O_EXCL`), puis renommée à la place de l'ancienne, qui est d'abord retirée : btrfs (un système de fichiers de Linux)
écrit tout de suite sur le disque un fichier renommé par-dessus un autre, environ 8 ms. Un run qui lit une entrée
pendant qu'un autre l'écrit voit l'ancienne, la nouvelle ou aucune, jamais une moitié, et deux runs qui l'écrivent en
même temps en écrivent chacun une entière. À la première écriture d'un run, au-delà de 256 MB d'entrées, celles qui ont
servi le moins récemment partent, jusqu'à 128 MB ; lire une entrée garde sa date fraîche, une fois par jour. Le dossier
peut être supprimé à tout moment, comme n'importe quel cache.

**Ce que ça fait gagner.** Du début du processus à sa fin, la médiane de 21 runs de chacun et son intervalle à 95 %,
les trois à tour de rôle, le 2026-11-12 pendant que d'autres travaux tournaient sur la machine : avant le cache ; le
premier run, avec un cache vide, dont les entrées sont écrites une fois qu'il a fini ; et les runs suivants, qui les
lisent. Pour Cemacs, c'est son démarrage jusqu'à sa première image, comme son livre le mesure.

| Programme | Avant | Premier run | Runs suivants |
|---|---:|---:|---:|
| `use std/io` et `io.Print(1)`, aucun package en Cesia | 4,50 ms [3,37, 5,17] | 3,99 ms [3,00, 4,55] | 3,75 ms [3,05, 4,26] |
| `use std/plot`, 2 300 lignes | 9,66 ms [9,58, 9,85] | 9,61 ms [9,45, 9,88] | 5,69 ms [5,58, 5,75] |
| `use std/cells`, 1 250 lignes | 6,79 ms [6,75, 6,91] | 6,86 ms [6,78, 7,19] | 4,36 ms [4,29, 4,57] |
| `src/browser` de Ceti, 1 500 lignes | 7,14 ms [7,00, 7,46] | 7,22 ms [7,14, 7,91] | 4,70 ms [4,61, 4,95] |
| Cemacs, 8 300 lignes en 28 packages | 52,16 ms [51,52, 53,09] | 54,26 ms [52,47, 57,66] | 36,97 ms [35,88, 38,63] |
| Cemacs avec son notebook, 10 000 lignes en 32 packages | 61,27 ms [59,22, 66,12] | 62,88 ms [60,62, 73,07] | 39,62 ms [38,74, 42,10] |

Le premier run prend le temps qu'il prenait avant le cache, à l'écart près entre les runs, sauf environ 2 ms pour
Cemacs : environ 1 ms est le `fork` d'un processus plus gros, le reste les questions notées pendant le resolver. Relire
une entrée est deux à trois fois plus rapide que de passer sa source par le lexer et le parser, et le resolver ne tourne
pas du tout ; ce qui reste d'un chargement est surtout cette lecture, et les collections du jeune heap qui copient les
nouveaux arbres vers le major heap (la grande partie de la mémoire, où vivent les valeurs qui durent), comme pour des
arbres qui viennent du parser.

**Testé** par `tests/cache_test.ml`, qui abîme chaque entrée à 60 endroits, la coupe à 8 longueurs, l'allonge, l'échange
avec une autre et la lit avec un autre build, à chaque fois avec la même sortie et l'entrée réécrite telle qu'elle
était, qui change un fichier et une dépendance, et qui lance tour à tour deux programmes qui chargent le code Cesia de
`std/list` avant et après un package qui n'en lit que les natives, sans rien résoudre de nouveau ; par
`tests/cache/entries.cmd`, la même chose avec le binaire, et avec un lien, une entrée que d'autres peuvent lire, un
dossier que d'autres peuvent lire et un dossier où l'on ne peut pas écrire, et quatre runs en même temps ; et par les
golden tests (des tests qui comparent la sortie à un texte attendu), lancés une fois sans cache, une fois avec un cache
vide et une fois avec un cache plein.

## Recharger le code : --watch

Sous `cesia run --watch`, Cesia regarde toutes les 50 ms la date, la taille et le numéro de fichier de chaque fichier du
programme. Un fichier modifié repasse par le parser et le resolver au checkpoint complet suivant. S'il a une erreur,
l'ancien code reste et l'erreur est montrée ; sinon, ses fonctions et ses structs remplacent les anciennes, chaque
fonction est compilée de nouveau à son appel suivant, et le code déjà compilé qui appelle une ancienne version atteint
la nouvelle. Les valeurs et les fibers du programme restent telles qu'elles étaient : c'est le *hot reload* (le
rechargement à chaud). `tools/reload-test.sh` a mesuré 12 à 19 ms entre l'enregistrement et le moment où la nouvelle
fonction tourne, le 1er novembre 2026.

## Pour aller plus loin

Les [Références](references.md) donnent chaque publication avec son lien. Celles sur lesquelles repose ce chapitre :

- la hash table d'une map owned : le `dict` compact de Python 3.6, d'après Hettinger ; le linear probing et son coût,
  Knuth, *The Art of Computer Programming*, vol. 3, 6.4 ; ses valeurs entières, Bolz, Diekmann et Tratt, *Storage
  Strategies for Collections in Dynamically Typed Languages*, 2013 ;
- le hash trie : Bagwell, *Ideal Hash Trees*, 2001, et les maps persistantes de Clojure, venues après lui ;
- les versions par type, les inline caches, les hidden classes et la deoptimization : les articles de Self, par
  Chambers, Ungar et Hölzle, de 1989 à 1994 ;
- les closures comme code : Feeley et Lapalme, *Using Closures for Code Generation*, 1987 ;
- les fibers : Sivaramakrishnan et ses coauteurs, *Retrofitting Effect Handlers onto OCaml*, 2021 ;
- les channels : Hoare, *Communicating Sequential Processes*, 1978, et la spécification de Go ;
- le garbage collector : Sivaramakrishnan et ses coauteurs, *Retrofitting Parallelism onto OCaml*, 2020 ;
- le hash flooding : Crosby et Wallach, *Denial of Service via Algorithmic Complexity Attacks*, 2003.

## La suite

Les [Références](references.md) listent les articles, les normes et les livres que Cesia suit, chacun avec ce que Cesia
en a pris.
