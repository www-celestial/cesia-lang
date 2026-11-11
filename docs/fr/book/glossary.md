# Mots

Les mots que les programmeurs emploient pour les idées de ce livre, dans l'ordre alphabétique de leur nom anglais, que le
français garde. Chacun dit ce qu'il veut dire en général, puis comment Cesia le fait, et mène au chapitre qui le montre.

## ABI

Une application binary interface : la façon dont le code compilé passe ses arguments et range ses données en mémoire,
pour que du code compilé à part puisse l'appeler. Le C en a une stable sur chaque système et le C++ n'en a aucune : Cesia
atteint donc le C++ à travers une petite couche C. Voir [C et C++](c.md).

## Amortized cost

Le coût moyen d'une opération sur une longue suite d'opérations, quand la plupart sont bon marché et quelques-unes chères.
[list.Append] sur une liste que rien d'autre ne tient écrit dans des cases libres gardées après la dernière, et en double
le nombre quand il n'en reste plus : une copie de temps en temps, un temps constant par élément en moyenne. Voir
[Comment Cesia fonctionne](internals.md#value-semantics-and-copy-on-write).

## Anonymous function

Une fonction sans nom, écrite là où elle sert ; on l'appelle aussi une lambda. En Cesia, `x -> x + 1` sur une ligne, ou
`defn (x)` jusqu'à `end` pour plusieurs lignes : voir [Fonctions](functions.md#functions-as-values).

## Atomic operation

Une opération qui se fait d'un seul coup ou pas du tout : aucun autre programme ne peut la voir à moitié faite. Un
renommage dans un même système de fichiers est atomique sur Linux et macOS : écrire un nouveau fichier, puis le renommer
par-dessus l'ancien, remplace donc un fichier sans risque, là où [sys.Write] seul peut le laisser coupé en route. Voir
[Fichiers](files.md#replacing-a-file-safely).

## Authenticated encryption

Un chiffrement qui prouve aussi que le message n'a pas été modifié : un tag (une étiquette de quelques octets) que seul le
détenteur de la clé peut fabriquer l'accompagne, et un message dont le tag ne correspond pas est refusé au lieu d'être
déchiffré en données sans sens. [crypto.Seal] et [crypto.BoxSeal] le font avec XSalsa20 et Poly1305 : voir
[Cryptographie](crypto.md#encrypting-with-a-key).

## Backpressure

Un destinataire lent qui ralentit son expéditeur, pour que les valeurs qui attendent entre eux restent peu nombreuses et la
mémoire bornée. En Cesia, un channel créé avec une taille, `fiber.Channel(size = 100)`, fait attendre [fiber.Send] tant
qu'il est plein : voir [Fibers](fibers.md#a-channel-of-a-size).

## Backtracking

Essayer l'une après l'autre les façons dont une expression régulière peut correspondre, et revenir en arrière pour
essayer la suivante quand l'une échoue. Un pattern comme `(a+)+$` prend alors un temps qui double à chaque lettre du texte.
[std/regex] ne fait jamais de backtracking : voir [Textes](texts.md#why-no-pattern-can-hang-a-program).

## Bail and deoptimization

Quitter le code machine pour revenir à l'interpréteur quand un pari du JIT se révèle faux, chaque variable étant remise là
où l'interpréteur la garde, pour que le programme reprenne au même statement. Les autres JIT appellent cela
deoptimization. Le JIT de Cesia fait son bail juste avant le statement dont le guard a échoué : voir
[Comment Cesia fonctionne](internals.md#bets-guards-and-bails).

## Baseline

La première mesure d'un problème, prise avant de rien changer : le nombre auquel chaque changement est comparé. Sans elle,
« plus rapide » ne veut rien dire. La baseline de [Résoudre un vrai problème](duplicates.md#the-baseline) est le temps de
la première façon qui vient à l'esprit, chaque fichier comparé à tous les autres.

## Big O notation

Une façon de dire comment le coût d'un programme grandit avec la taille $n$ de son entrée, sans sa constante : $O(n)$
grandit comme $n$, $O(n^2)$ comme son carré, donc une entrée deux fois plus grande demande quatre fois plus de travail.
Comparer chaque fichier à tous les autres est en $O(n^2)$ ; les grouper d'abord par taille lit chaque fichier au plus une
fois : voir [Résoudre un vrai problème](duplicates.md#2-measure-before-changing-anything).

## Binding

Le lien entre un nom et une valeur. En Cesia, `=` lie un nom, et le lier à nouveau lui donne une autre valeur : voir
[Valeurs et noms](values.md#noms).

## Birthday bound

La borne de la probabilité que deux des $k$ valeurs tirées au hasard parmi $N$ soient égales : au plus $k(k - 1)/(2N)$,
une chance sur $N$ pour chacune des $k(k - 1)/2$ paires. Son nom vient de la surprise qu'il suffise de 23 personnes pour
que deux aient le même anniversaire plus d'une fois sur deux. Pour un million de fichiers et un digest (l'empreinte que
donne une fonction de hash) de 256 bits, elle vaut $4{,}3 \times 10^{-66}$ : voir
[Résoudre un vrai problème](duplicates.md#the-bound-worked-out).

## BLAS and LAPACK

Deux interfaces standard d'algèbre linéaire : BLAS pour les opérations de base, comme le produit de matrices, et LAPACK,
écrit par-dessus, pour résoudre des systèmes, factoriser et trouver les valeurs propres. OpenBLAS et Accelerate d'Apple
en sont des versions rapides, réglées pour chaque processeur. [std/num] en utilise une pour les grandes matrices, et
[std/lapack] l'appelle directement : voir [Nombres et algorithmes](numbers.md#grandes-matrices-blas-et-lapack).

## Boxed and unboxed

Un nombre boxed est rangé dans un bloc de mémoire à lui, derrière un pointeur, avec un tag qui dit de quelle sorte il est ; un nombre
unboxed est le nombre machine nu, dans un registre ou un slot (une place de taille fixe). Les floats de Cesia (les nombres à virgule) sont boxed dans
les valeurs de toute sorte, et unboxed dans une version d'une fonction que l'inférence a typée, dans un array de floats,
dans une map ou une struct dont toutes les valeurs sont des floats, et dans le code machine, où une variable qui tient un
float le garde dans un registre pendant toute la boucle : une boucle de floats n'alloue donc rien. Voir
[Comment Cesia fonctionne](internals.md#what-it-makes).

## Breakpoint

Un endroit du code où un debugger arrête le programme, pour regarder ses variables avant qu'il continue. En Cesia,
`break FILE LINE` dans le debugger, avec `if` et une condition pour ne s'arrêter que quand elle est vraie : voir
[Le prompt et le debugger](debug.md#the-debugger).

## Call stack and frame

Les appels en cours, chacun attendant celui qu'il a fait : la call stack (la pile des appels). Chaque appel a une frame,
les slots de ses variables. Le debugger les montre avec `where`, et la limite `depth`, 10 000 par défaut, borne leur
nombre : voir [Le prompt et le debugger](debug.md#the-debugger) et [Fonctions](functions.md#a-function-that-calls-itself).

## Capture by value

Une closure qui garde les valeurs des noms qu'elle utilise telles qu'elles étaient quand elle a été créée : un nom qui
reçoit une autre valeur plus tard ne la change pas. Les closures de Cesia capturent par valeur ; celles de JavaScript et
de Python capturent la variable elle-même, et voient ses valeurs suivantes : voir [Fonctions](functions.md#closures).

## CHAMP

Le compressed hash-array mapped prefix tree de Steindorfer et Vinju, 2015 : un [hash array mapped
trie](#hash-array-mapped-trie) dont les nœuds gardent sur place chaque clé qui ne partage 5 bits de hash avec aucune autre
clé sous eux, et un nœud du niveau suivant pour les bits que plusieurs partagent, avec deux bitmaps pour dire lesquels. Il
prend moins de mémoire qu'un trie à buckets (des petits paquets de clés), et aucun nœud ne tient une clé seule en dessous
de lui. Une map de Cesia de plus de 32 clés en est un : voir
[Comment Cesia fonctionne](internals.md#maps-a-hash-table-then-a-hash-trie).

## Checkpoint

Un moment où l'interpréteur arrête de compter pour regarder le programme : au moins tous les 10 000 pas, il vérifie les
limites de pas et de profondeur, et tous les millions de pas, un checkpoint complet, il vide la sortie, vérifie la
mémoire, recharge un fichier modifié et laisse tourner les autres fibers : voir
[Comment Cesia fonctionne](internals.md#steps-and-checkpoints).

## Closure

Une fonction avec les noms qu'elle voyait là où elle a été créée, qu'elle peut encore utiliser une fois cet endroit fini.
Une closure de Cesia garde les valeurs que ces noms avaient quand elle a été créée : voir
[Fonctions](functions.md#functions-as-values).

## Closure compilation

Exécuter un syntax tree en changeant d'abord chacun de ses nœuds en une fonction du langage hôte, une closure, qui appelle
les closures de ses enfants : le travail de regarder un nœud est fait une fois, pas à chaque pas. L'interpréteur de Cesia
est écrit ainsi, en OCaml : voir [Comment Cesia fonctionne](internals.md#running-closures-as-code).

## Collision resistance

La propriété d'une fonction de hash que personne ne peut trouver deux textes de même digest, une collision, plus vite
qu'en essayant. Pour un digest de $b$ bits, essayer demande environ $2^{b/2}$ hashes, d'après la birthday bound : la
sécurité de BLAKE2b-256 contre les collisions est donc de $2^{128}$. MD5 l'a perdue en 2005. Voir
[Résoudre un vrai problème](duplicates.md#4-research).

## Column-major order

L'ordre des éléments d'une matrice en mémoire, colonne après colonne, de sorte que la première position varie le plus
vite, comme en Fortran, MATLAB, R et Julia ; le C et numpy par défaut sont row-major (ligne après ligne). Les arrays de
Cesia sont column-major, et une position seule compte dans cet ordre : voir
[Listes et arrays](lists.md#arrays-of-more-dimensions).

## Columnar data

Une table gardée comme un array par colonne plutôt qu'un enregistrement par ligne, pour qu'une somme ou un filtre parcoure
toute une colonne. Une data frame, comme dans pandas, est une telle table ; celle de Cesia est [std/frame] : voir
[Données](data.md#une-table-à-partir-d-un-fichier-csv).

## Comprehension

Une liste construite à partir d'une autre entre crochets : une valeur, un `for`, et une condition s'il le faut, comme en
Python. En Cesia, `[x * x for x in xs if x > 0]` est la forme courte de [list.Map] et [list.Filter] : voir
[Données](data.md#comprehensions).

## Concurrency and parallelism

La concurrency, c'est plusieurs tâches en cours à la fois, qui se relaient ; le parallelism, c'est plusieurs tâches qui
tournent au même instant, sur plusieurs cœurs. Les fibers de Cesia sont concurrentes, et son travail sur des arrays et des
colonnes entières est parallèle : voir [Fibers](fibers.md) et `CESIA_CORES` dans
[Variables d'environnement](env.md).

## Confidence interval

Un intervalle qui contient la vraie valeur d'une mesure avec une probabilité donnée, comme 95 % : plus il est large, plus
la mesure est bruitée. Les temps de [Vitesse](speed.md#beside-the-giants) donnent la médiane de leurs runs (leurs
exécutions) et l'intervalle à 95 % de cette médiane, tiré des rangs des runs triés, sans rien supposer de leur
répartition.

## Continuation

Le reste d'un calcul, tenu comme une valeur que l'on peut reprendre : ce qu'il reste à faire à une fiber quand elle se met
en attente. Les effect handlers d'OCaml 5 la donnent, une seule fois, et le scheduler de Cesia la reprend quand ce que la
fiber attend est prêt : voir [Comment Cesia fonctionne](internals.md#how-a-fiber-stops-and-starts).

## Copy-on-write

Partager une valeur jusqu'à ce que l'un de ceux qui la tiennent écrive dedans, et ne la copier qu'à ce moment-là. Une
liste, une struct ou une map de Cesia porte un bit qui dit si un seul endroit la tient : une écriture la change sur place,
et une écriture dans une valeur partagée la copie d'abord. Cela donne la value semantics au prix d'une copie seulement là
où une copie est nécessaire : voir [Comment Cesia fonctionne](internals.md#value-semantics-and-copy-on-write).

## CSP

Communicating sequential processes : le modèle de C. A. R. Hoare, de 1978, où des processus ne partagent aucune mémoire et
ne font qu'échanger des messages sur des channels, un envoi et une réception qui se rencontrent. Les channels de Go le
suivent, et ceux de Cesia aussi : voir [Fibers](fibers.md#channels) et
[Comment Cesia fonctionne](internals.md#channels).

## Data frame

Une table de colonnes nommées, toutes de la même longueur, comme pandas en a en Python et comme R en a d'origine, sur
laquelle un filtre, un groupe ou une somme traite une colonne entière à la fois. Celle de Cesia est [std/frame] : voir
[Données](data.md#une-table-à-partir-d-un-fichier-csv).

## Data race

Deux threads qui touchent la même mémoire au même moment, l'un des deux en écrivant, avec un résultat qui dépend de celui
qui est passé le premier. Les fibers de Cesia tournent une à la fois et ne partagent aucune valeur qui peut changer : elles
ne peuvent donc pas avoir de data race, et n'ont besoin d'aucun lock. Voir [Fibers](fibers.md#shared-values).

## Deadlock

Des tâches qui attendent chacune une autre, de sorte qu'aucune ne peut jamais continuer. Quand toutes les fibers
attendent et que rien au-dehors ne peut en réveiller une, Cesia arrête le programme avec la ligne de l'attente,
`All fibers are waiting and nothing can wake them.` : voir [Fibers](fibers.md#when-every-fiber-waits).

## Definite assignment

La règle qui veut qu'un nom reçoive une valeur avant d'être lu, sur chaque chemin du code. Cesia la vérifie au chargement
du fichier : un nom lu trop tôt est donc une erreur avant que rien ne tourne. Voir
[Comment Cesia fonctionne](internals.md#names-the-resolver).

## Delta debugging

Rendre une entrée qui fait échouer un programme plus petite pas à pas, en gardant chaque entrée plus petite qui échoue
encore, jusqu'à ce que ce qui reste montre la cause de l'échec : la méthode de Zeller et Hildebrandt, de 2002. Le
[shrinking](#shrinking) de [test.ForAll] le fait sur les tirages qui ont produit un cas : voir
[Résoudre un vrai problème](duplicates.md#a-shortcut-proved-wrong).

## Dependency

Du code d'un autre projet que le vôtre utilise : une dépendance. En Cesia, une table `[deps]` de `cesia.toml` nomme son
dépôt et son tag, et `cesia pkg` la récupère dans `deps/` : voir [Packages](packages.md#code-from-other-projects).

## Deque

Une double-ended queue : une suite qui prend et donne des éléments à ses deux bouts. [std/queue] en est une persistante,
chaque opération en $O(\log_{32} n)$ : voir [Nombres et algorithmes](numbers.md#sets-queues-et-heaps).

## Destructuring

Défaire une valeur en morceaux nommés en un seul pas. En Cesia, un pattern de [match] le fait : `[a, b]` pour une liste de
deux éléments, `{Name: n}` pour un dictionnaire, `Point(x, y)` pour une struct : voir [Choix et boucles](choices.md#match).

## Doctest

Un test écrit comme un exemple dans la documentation d'une fonction, pour que l'exemple ne puisse pas devenir faux. En
Cesia, un `call --> value` en retrait dans un commentaire `(**` en est un, et `cesia test` le lance : voir
[Tests](tests.md#examples-in-the-documentation).

## Dynamic typing

Des types qui appartiennent aux valeurs, vérifiés quand une opération s'exécute, plutôt qu'aux variables, vérifiés avant
que le programme tourne. Cesia a un typage dynamique, avec des types que vous pouvez écrire, vérifiés quand une valeur
arrive, et des types que l'inférence prouve pour rendre le code plus rapide : voir
[Types](types.md#checked-when-a-value-comes-in) et [Comment Cesia fonctionne](internals.md#types-inference-and-versions).

## Edit distance

Le plus petit nombre d'insertions, de suppressions et de remplacements d'un caractère qui changent un texte en un autre,
qu'on appelle aussi la distance de Levenshtein : 3 de `kitten` à `sitting`. [algo.Levenshtein] la donne : voir
[Nombres et algorithmes](numbers.md#algorithmes-std-algo).

## Effect handler

Une partie d'un programme qui attrape un *effect*, une demande que fait le code à l'intérieur d'elle, comme une exception,
mais qui peut reprendre le code qui l'a faite. OCaml 5 en a, et chaque fiber de Cesia se met en attente en faisant un
effect : voir [Comment Cesia fonctionne](internals.md#how-a-fiber-stops-and-starts).

## Epoll

L'interface de Linux qui dit lesquelles de nombreuses sockets (les bouts d'une connexion réseau) sont prêtes à lire ou à
écrire, pour un coût qui ne grandit qu'avec celles qui sont prêtes. Le scheduler de Cesia l'attend quand aucune fiber
n'est prête, et attend `select` sur macOS et Windows ; `EPOLLEXCLUSIVE` fait qu'une nouvelle connexion ne réveille qu'un
worker de `--workers` : voir [Comment Cesia fonctionne](internals.md#waiting-on-the-system).

## Equivalence relation

Une relation qui lie une chose à elle-même, deux choses dans les deux sens, et une première à une troisième en passant par
une deuxième, comme « contient les mêmes octets que » entre des fichiers. Elle découpe les choses en classes, les
ensembles dont les membres sont liés entre eux : les groupes de copies d'un dossier sont les classes de deux fichiers ou
plus. Voir [Résoudre un vrai problème](duplicates.md#1-the-problem-stated-precisely).

## Error propagation

Faire remonter une erreur de la fonction qui l'a rencontrée jusqu'à un appelant qui peut la traiter. En Cesia, `?` après
un résultat le fait : il donne la valeur d'un `Ok`, ou renvoie tout de suite l'`Err`. Voir
[Erreurs](errors.md#passing-an-error-on).

## Error value

Une erreur qu'une fonction rend comme résultat, pour que le code montre où elle va. Les erreurs de Cesia sont des valeurs :
un [result.Err] autour de ce qui n'a pas marché, à côté du [result.Ok] d'une réussite. Voir [Erreurs](errors.md).

## Exception

Une erreur qui saute hors du code qui l'a levée, jusqu'à un `try` qui l'attrape. Cesia n'a ni l'un ni l'autre : un échec
qui peut arriver est une [error value](#error-value), et un bug arrête le programme avec une panic (un arrêt net, avec le
message et la ligne). Voir [Erreurs](errors.md#errors-and-bugs).

## Exit code

Le nombre qu'un programme rend à celui qui l'a lancé : 0 quand tout s'est bien passé, un autre quand quelque chose a
échoué. En Cesia, [sys.Exit] termine avec un code, et un programme arrêté par un bug termine avec 1 : voir
[Fichiers](files.md#standard-input-and-the-exit-code).

## Expression and statement

Une expression est du code qui donne une valeur, comme `2 + 3` ; un statement (une instruction) est du code qui fait
seulement quelque chose, sans donner de valeur. En Cesia, `if` et `match` sont des expressions : `kind = if n > 0 "positive" else "other" end`.
Voir [Choix et boucles](choices.md#if-gives-a-value).

## Falsifiable

Se dit d'une hypothèse qu'une expérience pourrait réfuter, parce qu'elle prédit quelque chose qui se mesure : le critère de
Karl Popper pour une affirmation scientifique. « Le temps passe à relire les mêmes fichiers » est falsifiable, car cette
hypothèse prédit que lire chaque fichier une seule fois fait disparaître presque tout le temps : voir
[Résoudre un vrai problème](duplicates.md#3-a-hypothesis-that-can-be-proved-wrong).

## Fiber

Une fonction qui tourne à côté des autres dans le même programme, avec sa propre stack (la pile de ses appels en cours), menée par le langage plutôt que
par le système : on l'appelle aussi un green thread, ou une coroutine avec un scheduler. Des milliers coûtent peu, environ
2,1 KB chacune. Elles tournent une à la fois sur un cœur. En Cesia, [fiber.Spawn] en démarre une et [fiber.Wait] attend
sa fin : voir [Fibers](fibers.md) et [Comment Cesia fonctionne](internals.md#fibers-and-the-scheduler).

## Fix and continue

Changer le code d'un programme arrêté dans un debugger, puis continuer sans le redémarrer : l'appel suivant d'une fonction
modifiée exécute son nouveau code. Smalltalk et Lisp l'ont eu les premiers. Le debugger de Cesia recharge les fichiers
modifiés quand il reprend : voir [Le prompt et le debugger](debug.md#fix-and-continue).

## Flat closure

Une closure qui copie les valeurs qu'elle capture dans un petit array à elle, plutôt que de garder un lien vers la frame
où elle a été créée. Les closures de Cesia sont flat, et c'est pourquoi elles capturent par valeur : voir
[Comment Cesia fonctionne](internals.md#closures).

## Floored division

Une division d'entiers qui arrondit vers moins l'infini, pour que le reste ait le signe du diviseur : `math.Div(-7, 3)`
vaut `-3` et `math.Mod(-7, 3)` vaut `2`, comme en Python. Le C et Java tronquent plutôt vers zéro, ce qui donne `-2` et
`-1` : voir [Nombres et algorithmes](numbers.md#un-nombre-std-math).

## Foreign function interface

La façon dont un langage appelle des fonctions écrites dans un autre, le plus souvent en C ; FFI en abrégé. Celle de Cesia
est [std/c] : [c.Open] charge une bibliothèque et [c.Fn] lie une fonction par ses types, avec la permission `ffi` : voir
[C et C++](c.md).

## Frame descriptor

Ce qu'écrit le compilateur d'un langage à garbage collector pour chaque endroit du code où un appel revient : la taille de
la frame et lesquels de ses slots tiennent des valeurs, pour que le collector puisse les trouver sur la stack. OCaml
construit une hash table de tous ces descripteurs au démarrage : 19 723 pour le binaire de Cesia, une partie de son temps
de démarrage. Voir [Comment Cesia fonctionne](internals.md#start-up).

## Fsync

L'appel système qui ne rend la main qu'une fois que le disque tient les données d'un fichier, et pas seulement la mémoire
du système, qui les écrit plus tard : après lui, une coupure de courant ne fait rien perdre du fichier. Le dossier qui
tient le nom d'un nouveau fichier a besoin de son propre fsync. [sys.Write] avec `sync = true` fait les deux : voir
[Fichiers](files.md#surviving-a-power-cut).

## Future

Une valeur qu'un calcul donnera plus tard, et qu'un programme peut attendre : on l'appelle aussi une promise. Une tâche de
[fiber.Spawn] en est une, et [fiber.Wait] attend sa valeur : voir [Fibers](fibers.md#spawn-and-wait).

## Garbage collector

La partie d'un runtime (ce qui accompagne un programme pendant qu'il tourne) qui libère la mémoire vers laquelle plus rien
ne pointe : un programme ne la libère donc jamais à la main. Cesia utilise celui d'OCaml, qui est *generational* : les
nouveaux blocs vont dans un petit heap vidé souvent, puisque la plupart meurent jeunes, et les autres dans un grand heap
nettoyé par tranches. Voir [Comment Cesia fonctionne](internals.md#memory-and-the-garbage-collector).

## Golden test

Un test qui lance un programme et compare tout ce qu'il a affiché avec une sortie enregistrée, la sortie golden (celle
qui fait foi). Les sources de Cesia testent le langage de cette façon. Un projet teste plutôt des valeurs, avec des
doctests et des fonctions de test : voir [Tests](tests.md).

## Guard

Un test que le code machine fait avant de se servir d'un pari du JIT, comme « cette valeur est un float » : quand il
échoue, le code fait un bail vers l'interpréteur. Voir [Comment Cesia fonctionne](internals.md#bets-guards-and-bails).

## Handler

La fonction qui répond à une sorte de requête. Dans [std/http], elle prend la requête, un dictionnaire, et donne la
réponse : voir [HTTP](http.md#an-application).

## Hard and symbolic links

Un hard link est un nom de plus pour le même fichier : les octets sont une seule fois sur le disque, et effacer un nom ne
libère rien tant qu'il en reste un autre. Un symbolic link est un petit fichier qui tient un chemin, que le système suit.
[sys.Walk] liste un symbolic link et ne le suit jamais ; [sys.Stat] dit qu'un chemin est un symbolic link, mais pas que
deux noms sont des hard links vers un même fichier : voir [Résoudre un vrai problème](duplicates.md#7-what-is-left).

## Hash array mapped trie

Un HAMT : un arbre où chaque niveau est choisi par 5 bits du hash d'une clé, de sorte qu'un nœud a jusqu'à 32 enfants,
gardé compact par un bitmap de ceux qui existent. Phil Bagwell l'a décrit en 2001, et Clojure en a fait ses maps
persistantes. Une map de Cesia de plus de 32 clés en devient un, de la sorte appelée [CHAMP](#champ), à sa première
écriture qui doit garder l'ancienne map : une lecture suit environ $\log_{32} n$ niveaux, et une écriture ne copie que son
chemin. Voir [Comment Cesia fonctionne](internals.md#maps-a-hash-table-then-a-hash-trie).

## Hash flooding

Une attaque qui envoie à un programme beaucoup de clés de même hash, pour que chaque lecture de sa hash table les parcoure
toutes et que le programme ralentisse jusqu'à s'arrêter : un déni de service. Le hash de Cesia prend un seed (une valeur
de départ) tiré à chaque lancement, et les clés d'un même hash vont dans un arbre équilibré : voir
[Comment Cesia fonctionne](internals.md#maps-a-hash-table-then-a-hash-trie).

## Hash table

Un array de *slots* où le hash d'une clé désigne le slot où chercher d'abord, de sorte qu'une lecture ou une écriture prend
un temps constant en moyenne, quel que soit le nombre de clés. Avec l'*open addressing* et le *linear probing*, une clé
dont le slot est pris va au slot libre suivant, et une lecture parcourt les slots depuis le premier jusqu'à la clé ou à
un slot libre ; quand la table est remplie au plus à moitié, cela fait 1,5 slot pour une clé présente et 2,5 pour une
clé absente. Le `dict` de Python, depuis la 3.6, garde ses entrées dans un second array dans l'ordre où elles sont
arrivées, et ses slots tiennent leurs numéros : une table *insertion-ordered*. Une map de Cesia de plus de 32 clés qu'un
seul nom tient en est une : voir [Comment Cesia fonctionne](internals.md#maps-a-hash-table-then-a-hash-trie).

## Hash function

Une fonction qui change un texte de n'importe quelle longueur en un nombre ou un texte court, son digest, le même pour le
même texte. Dans une hash table, elle choisit la place d'une clé ; en cryptographie, il doit aussi être impossible de
l'inverser ou de faire entrer deux textes en collision, comme avec SHA-256 et BLAKE2b : voir
[Cryptographie](crypto.md#hashes).

## Hash join

Un join de deux tables (qui associe leurs lignes par une clé commune) qui met les clés de l'une dans une hash table, puis
y cherche chaque ligne de l'autre : un temps d'environ la somme de leurs tailles, pas leur produit. [frame.JoinOn] fait
ses joins ainsi : voir [Données](data.md#joindre-deux-tables).

## Heilmeier catechism

Les questions que George Heilmeier, directeur de la DARPA de 1975 à 1977, posait à chaque projet de recherche :
qu'essayez-vous de faire, en mots simples ; comment est-ce fait aujourd'hui, et quelles en sont les limites ; qu'y a-t-il de nouveau
dans votre approche ; à qui cela importe-t-il ; quels sont les risques ; combien cela coûte-t-il ; combien de temps cela
prend-il ; quels sont les examens qui vérifient la réussite. Voir
[Résoudre un vrai problème](duplicates.md#1-the-problem-stated-precisely).

## Hidden class

La disposition d'un objet, les noms de ses champs et leurs places, partagée par tous les objets de même forme, pour que la
lecture d'un champ puisse être une comparaison et une lecture en mémoire. Self les appelait maps, V8 hidden classes. Une
struct de Cesia a sa forme, et les maps créées à un même endroit du code partagent leurs clés : voir
[Comment Cesia fonctionne](internals.md#maps-a-hash-table-then-a-hash-trie).

## Higher-order function

Une fonction qui prend une fonction, ou en rend une. [list.Map], [list.Filter] et [list.Reduce] en prennent une, et
`adder(n) = x -> x + n` en rend une : voir [Fonctions](functions.md#map-filter-and-reduce).

## HMAC

Un hash sous une clé secrète : seul celui qui a la clé peut le fabriquer, il prouve donc qu'un message vient de lui et n'a
pas été modifié. [crypto.HmacSha256] en donne un : voir [Cryptographie](crypto.md#hashes).

## Hot reload

Du nouveau code chargé dans un programme pendant qu'il tourne, pour qu'il garde son état. `cesia run --watch` le fait à
chaque enregistrement : voir [Installer et lancer un premier programme](install.md#le-relancer-à-chaque-enregistrement).

## Immutability

Une valeur qui ne change jamais une fois créée : chaque opération donne une nouvelle valeur. Toutes les valeurs de Cesia
se comportent ainsi ; `xs[1] = 5` donne au nom `xs` une nouvelle liste, que Cesia fabrique en changeant l'ancienne sur
place quand rien d'autre ne la tient, par [copy-on-write](#copy-on-write) : voir [Valeurs et noms](values.md#noms).

## Inline cache

Une petite mémoire gardée à un endroit du code, comme une lecture de champ, de la dernière sorte de valeur rencontrée là
et de la place où le champ s'y trouvait, pour que la lecture suivante de la même sorte soit rapide. Cesia garde une forme
à chaque site, un inline cache *monomorphic* : voir [Comment Cesia fonctionne](internals.md#caches-at-each-site). Celui
qui garde plusieurs sortes est *polymorphic* : le JIT de Cesia en fait un pour chaque appel à travers une valeur, des
fonctions qu'il a atteintes, jusqu'à quatre ; au-delà, un appel est *megamorphic*, et reste dans l'interpréteur : voir
[Comment Cesia fonctionne](internals.md#calls-through-a-value).

## Intermediate representation

Une IR : la forme qu'un compilateur donne à un programme entre sa source et le code machine, plus simple à analyser que
l'une et l'autre. Le JIT de Cesia change une unité hot (qui tourne souvent) en une IR de basic blocks (des suites
d'instructions sans saut au milieu) d'instructions typées, dont MIR fait ensuite du code machine : voir
[Comment Cesia fonctionne](internals.md#what-it-makes).

## Interpreter and JIT

Un interpréteur exécute un programme pas à pas, depuis une forme gardée en mémoire ; un just-in-time compiler, un JIT,
change en code machine les parties qui tournent souvent, pendant que le programme tourne. Le JIT de Cesia est un method
JIT avec des loop regions : il compile les versions hot des fonctions qui donnent des nombres et les boucles hot, sur des
nombres, des arrays, des maps et des structs, et rend la main à l'interpréteur quand un pari échoue. Voir
[Vitesse](speed.md) et [Comment Cesia fonctionne](internals.md#the-jit).

## Keep-alive

Une connexion HTTP gardée ouverte après une réponse, pour la requête suivante du même client, ce qui évite d'ouvrir une
connexion à chaque fois. [http.Serve] garde les connexions, et ferme celle qui attend au-delà de son délai : voir
[Comment Cesia fonctionne](internals.md#the-server).

## Language server

Un programme qu'un éditeur démarre et à qui il parle en JSON, par le Language Server Protocol, LSP, pour qu'un seul
serveur donne à tous les éditeurs les erreurs, la documentation et les définitions d'un langage. `cesia lsp` est celui de
Cesia : voir [Éditeurs](editors.md).

## Lexer and parser

Le lexer découpe le texte d'un programme en tokens, ses mots ; le parser change les tokens en un syntax tree, en suivant
la grammaire. Le parser de Cesia est écrit à la main, par recursive descent, une fonction par règle : voir
[Comment Cesia fonctionne](internals.md#reading-the-lexer-and-the-parser).

## Lexical scope

Les noms que voit un morceau de code sont ceux écrits autour de lui, pas ceux de son appelant. En Cesia, une fonction voit
ses paramètres, ses propres noms et ceux de son fichier ; un nom qui reçoit une valeur à l'intérieur d'elle est le sien,
et `if` et `for` ne créent pas de scope (de portée) : voir [Fonctions](functions.md).

## Little's law

Dans un système qui reçoit des requêtes à un rythme régulier, le nombre de requêtes qui attendent à l'intérieur, $L$, est
le rythme, $\lambda$, multiplié par le temps que chacune y passe, $W$ : $L = \lambda W$ (Little, 1961). Un serveur qui
tient 1 000 connexions, chacune avec une requête en attente, et répond à 36 000 requêtes par seconde, répond à chacune en
$1\,000 / 36\,000$ s, 28 ms, en moyenne, quelle que soit la façon dont il les ordonne. Voir
[Comment Cesia fonctionne](internals.md#what-it-serves).

## Lock file

Un fichier qui garde la version exacte et l'empreinte de chaque dépendance, pour que toutes les machines installent le
même code. Celui de Cesia est `cesia.lock`, que `cesia new` et `cesia pkg` écrivent : voir
[Packages](packages.md#code-from-other-projects).

## Median

La valeur du milieu de nombres mis en ordre, la médiane : la moitié sont en dessous et la moitié au-dessus. Elle bouge
moins que la moyenne quand quelques runs sont lents parce que la machine était occupée : [Vitesse](speed.md#beside-the-giants)
donne donc des médianes.

## Message passing

Des tâches qui partagent des données en se les envoyant, au lieu de changer la même mémoire. En Cesia, un
[fiber.Channel] porte des valeurs d'une fiber à une autre, avec [fiber.Send] et [fiber.Receive] : voir
[Fibers](fibers.md#channels).

## Method and receiver

Une méthode est une fonction attachée à un type, et son receiver est la valeur sur laquelle on l'appelle.
`defn (r Rect) Area()` nomme son receiver `r` entre parenthèses avant le nom, et `r.Area()` l'appelle : voir
[Structs](structs.md#methods).

## Method JIT and tracing JIT

Un method JIT compile des fonctions entières, ou des boucles entières ; un tracing JIT, comme celui de LuaJIT, enregistre
le chemin que prend une boucle hot et ne compile que ce chemin, avec des sorties pour les autres. Le JIT de Cesia est un
method JIT avec des loop regions, ce qui garde sa vitesse stable sur du code plein de branches : voir
[Comment Cesia fonctionne](internals.md#the-jit).

## Middleware

Du code entre un serveur et ses handlers, qui voit chaque requête et chaque réponse : un log, un header, une vérification.
[http.Wrap] en place un devant une application : voir [HTTP](http.md#middleware).

## Minor heap

La partie jeune de la mémoire, dans un garbage collector qui range les valeurs par âge : une nouvelle valeur y est créée
en avançant un pointeur, et le collector la vide souvent, en recopiant ailleurs les quelques valeurs encore utilisées. La
plupart des valeurs meurent jeunes : les libérer ne coûte donc presque rien. Celui d'OCaml fait 256k mots machine par
défaut ; Cesia tourne avec 2M mots (16 MB) : voir [Packages natifs](native.md#what-a-call-costs).

## Native package

Un package dont le cœur est du code compilé que le langage charge pendant qu'un programme tourne : un extension module en
Python, un addon en Node, un NIF en Erlang. Celui de Cesia est un package dont le moteur est en OCaml, compilé une fois
contre `Cesia_v1`, et qu'un programme lance avec la permission `native` : voir [Packages natifs](native.md).

## Nominal typing

Une valeur a un type à cause de ce qui l'a créée, pas à cause de ce qu'elle contient : une valeur est un `Point` parce
que `Point` l'a créée, et un dictionnaire avec les mêmes clés n'en est pas un. Les structs de Cesia sont nominales, ses
interfaces [structurelles](#structural-typing) : voir [Structs](structs.md#struct-or-dictionary).

## Non-blocking I/O

Une lecture ou une écriture qui rend la main tout de suite quand elle ne peut pas avancer, au lieu de faire attendre le
thread, pour qu'un seul thread puisse servir beaucoup de connexions. Chaque socket de Cesia est non-blocking : une fiber
qui devrait attendre se met en attente, et le scheduler la réveille quand le système dit que la socket est prête. Voir
[Comment Cesia fonctionne](internals.md#waiting-on-the-system).

## Nonce

Un number used once, un nombre qui ne sert qu'une fois : une valeur qui accompagne chaque message chiffré sous une clé et
ne doit jamais servir deux fois avec cette clé. [crypto.Seal] en tire un au hasard et le garde devant le message : voir
[Cryptographie](crypto.md#encrypting-with-a-key).

## Null

Une valeur qui veut dire « pas de valeur » : `null`, `nil` ou `None` dans d'autres langages. Celle de Cesia est
`missing`, et un type ne l'accepte qu'avec un `?`, comme `Text?` : voir [Valeurs et noms](values.md#missing) et
[Types](types.md#maybe-missing).

## On-stack replacement

Faire passer une boucle qui tourne déjà de l'interpréteur au code machine, au milieu de ses tours, en emportant ses
variables. Le JIT de Cesia le fait à un checkpoint dans une boucle hot : voir
[Comment Cesia fonctionne](internals.md#bets-guards-and-bails).

## Optional typing

Des types qu'un programme peut écrire ou laisser de côté. En Cesia, les types sont un plus : le code sans eux tourne aussi
vite, et un type écrit est vérifié chaque fois qu'une valeur arrive : voir [Types](types.md).

## Order statistic

La k-ième plus petite d'un ensemble de mesures, une fois qu'elles sont mises en ordre : la première est le minimum, celle
du milieu la médiane. Deux d'entre elles bornent un confidence interval de la médiane sans rien supposer de la
répartition des mesures : sur 11 runs, la 2e et la 10e encadrent la vraie médiane avec une probabilité de 98,8 %. Voir
[Résoudre un vrai problème](duplicates.md#how-it-was-measured).

## Overlong form

Un caractère UTF-8 écrit avec plus d'octets qu'il ne lui en faut, comme `0xC0 0x80` pour le caractère 0, qui tient sur
un octet. La RFC 3629 l'interdit, car une vérification octet par octet pourrait laisser passer un caractère interdit
déguisé : [text.IsUtf8] le refuse. Voir [Textes](texts.md#valid-utf-8).

## Package

Du code groupé sous un nom, qu'on appelle aussi un module, dont on atteint les noms à travers lui : son namespace. En
Cesia, un package est un dossier de fichiers `.ce` : `use std/sql` en fait entrer un, et `sql.Open` nomme une de ses
fonctions publiques : voir [Packages](packages.md).

## Page cache

Les copies des fichiers que le système garde dans la mémoire libre après les avoir lus, pour que la lecture suivante des
mêmes octets ne coûte aucun accès au disque. Un cache *warm* (chaud) les tient, un cache *cold* (froid) non : un programme
qui lit un dossier deux fois est plus rapide la seconde fois. [Résoudre un vrai problème](duplicates.md#threats-to-validity)
mesure les deux.

## Page fault

L'interruption que subit un programme la première fois qu'il touche une page de mémoire, 4 KB, que le kernel n'a pas
encore mise en place pour lui : le kernel installe la page, la remplit de zéros, ou la copie quand le programme écrit une
page qu'il partage, comme les données d'un binaire que le loader corrige. Environ 2 µs chacune sur la machine de
[Vitesse](speed.md#beside-the-giants) ; un démarrage de Cesia en coûte environ 590, voir
[Comment Cesia fonctionne](internals.md#start-up).

## Parameterized query

Une query dont les valeurs voyagent à part de son texte SQL, pour qu'aucune entrée tapée par un utilisateur ne puisse
changer la query : une SQL injection. Dans [std/sql], chaque `?` prend une valeur de la liste : voir
[SQLite](sqlite.md#values-never-go-into-the-text).

## Partial inlining

Ne copier qu'une partie d'une fonction aux endroits qui l'appellent, le plus souvent le test qui rend la main tôt, le
reste restant un appel (Zhao et Amaral, 2005). Le JIT de Cesia le fait quand une fonction appelée commence par un test de
ses paramètres qui donne l'un d'eux ou une constante, comme le `if n < 2 then n` de `fib` : les feuilles d'une récursion
ne coûtent alors aucun appel. Voir [Comment Cesia fonctionne](internals.md#what-it-makes).

## Partition refinement

Découper un ensemble en groupes selon une clé, puis redécouper chaque groupe selon une clé plus fine, et ainsi de suite,
de sorte qu'aucune étape ne réunit ce qu'une étape précédente avait séparé. C'est ainsi qu'on trouve les fichiers en
double : par taille, puis par digest parmi les fichiers d'une même taille. Voir
[Résoudre un vrai problème](duplicates.md#4-research).

## Pattern matching

Comparer une valeur à des formes, dans l'ordre, et exécuter le code de la première qui lui va, avec des noms pour ses
morceaux. [match] le fait sur les valeurs, les listes, les dictionnaires, les structs et les résultats : voir
[Choix et boucles](choices.md#match).

## Percent-encoding

Écrire un octet qu'une URL ne peut pas contenir sous la forme `%` suivi de ses deux chiffres hexadécimaux : une espace
est `%20`. [encode.UrlEncode] et [encode.UrlDecode] le font : voir
[JSON et CSV](json.md#bytes-as-text-hexadecimal-base64-and-urls).

## Persistent data structure

Une structure qui garde son ancienne version quand elle change, et partage la plus grande partie de sa mémoire avec la
nouvelle, par [structural sharing](#structural-sharing). Un grand dictionnaire de Cesia qui est partagé est un hash trie,
comme en Clojure : [dict.Put] en donne un nouveau qui partage le reste avec l'ancien ; tant qu'un seul nom le tient, c'est
une hash table changée sur place, que personne d'autre ne peut voir. Voir [Maps](maps.md) et
[Comment Cesia fonctionne](internals.md#maps-a-hash-table-then-a-hash-trie).

## Pike machine

Une façon d'exécuter une expression régulière qui suit à la fois tous les chemins que le pattern peut prendre, pas à pas
le long du texte, comme le fait la méthode de Ken Thompson de 1968, et qui garde les positions de ses groupes : son temps
est linéaire dans la longueur du texte. Rob Pike l'a écrite pour son éditeur sam, et Russ Cox l'a décrite. [std/regex] en
est une : voir [Textes](texts.md#why-no-pattern-can-hang-a-program).

## Pipeline operator

Un opérateur qui passe une valeur à la fonction suivante, pour que les étapes se lisent de gauche à droite : `|>` en F#,
Elixir et OCaml. Celui de Cesia est [then] : voir [Fonctions](functions.md#then).

## Position-independent executable

Un programme qui peut être chargé à n'importe quelle adresse de la mémoire, choisie au hasard par le système à chaque
démarrage, ce qui rend un bug en C plus difficile à exploiter. Le binaire de Cesia en est un : le système corrige donc
les adresses de ses données à chaque démarrage, une partie de son temps de démarrage. Voir
[Comment Cesia fonctionne](internals.md#start-up).

## Pre-fork server

Un serveur dont le premier processus ouvre la socket d'écoute, puis démarre plusieurs processus, les workers, qui y
prennent tous leurs connexions, comme le fait nginx. `cesia run --workers` sert de cette façon, sous un supervisor : voir
[HTTP](http.md#every-core) et [Comment Cesia fonctionne](internals.md#on-every-core).

## Preemptive scheduling

Le scheduler passe d'une tâche à une autre de lui-même, sans attendre que la tâche lui cède la place. Les fibers de Cesia
cèdent la place quand elles attendent, et une fiber qui calcule la cède tous les millions de pas, comme Erlang compte ses
réductions ; aucun timer n'interrompt une fiber, et une fonction de `std/` écrite en OCaml va jusqu'à sa fin. Voir
[Fibers](fibers.md#a-long-computation) et [Comment Cesia fonctionne](internals.md#how-a-fiber-stops-and-starts).

## Principle of least privilege

Un programme reçoit les droits dont il a besoin, et pas plus. En Cesia, `--allow read=./data` plutôt que `read`, et
`net=:8080` plutôt que `net` : voir [Permissions](permissions.md#allow).

## Priority queue

Une collection qui rend toujours d'abord sa plus petite clé. [std/heap] en est une, un leftist heap, chaque insertion et
chaque retrait en $O(\log n)$ : voir [Nombres et algorithmes](numbers.md#sets-queues-et-heaps).

## Property-based testing

Tester une règle sur beaucoup de cas qu'un générateur fabrique, plutôt que sur quelques cas écrits à la main, puis
réduire un cas qui échoue au plus petit. QuickCheck l'a commencé en Haskell ; [test.ForAll] le fait : voir
[Tests](tests.md#properties).

## Public-key cryptography

La cryptographie avec une paire de clés : une clé publique, donnée à tous, et une clé secrète, gardée. Ce que la clé
publique chiffre, seule la clé secrète l'ouvre ; ce que la clé secrète signe, la clé publique le vérifie.
[crypto.BoxSeal] et [crypto.Sign] s'en servent : voir [Cryptographie](crypto.md#encrypting-for-someone).

## Pure function

Une fonction dont le résultat ne dépend que de ses arguments, et qui ne fait rien d'autre : pas d'affichage, pas de
fichier, pas d'horloge. Une fonction de Cesia ne peut pas changer les valeurs qu'on lui donne : elle est pure quand elle
laisse le monde extérieur tranquille. Voir [Fonctions](functions.md).

## Range analysis

Ce qu'un compilateur prouve des valeurs que peut prendre un entier, pour retirer les vérifications que ces valeurs rendent
inutiles. Dans le JIT de Cesia, `math.Mod(i, 4)` est entre 0 et 3, donc `math.Mod(i, 4) + 1` n'a besoin d'aucune
vérification d'overflow (le dépassement de la taille d'un entier) ; et dans le `else` de `if n < 2`, `n` vaut au moins 2,
donc `n - 1` n'en a pas besoin non plus : ce sont les bornes que prouve le test d'une branche, comme dans ABCD (Bodík,
Gupta et Sarkar, 2000). Voir [Comment Cesia fonctionne](internals.md#what-it-makes).

## Radix sort

Un tri de nombres par leurs chiffres, un chiffre à la fois en commençant par le plus faible, chaque passe rangeant les
nombres dans des buckets selon ce chiffre et gardant, dans chaque bucket, l'ordre de la passe précédente : aucune
comparaison, un temps proportionnel au nombre de nombres multiplié par le nombre de chiffres. Une map de Cesia qui passe
d'une hash table à un trie trie ainsi ses hashes, 10 bits à la fois : voir
[Comment Cesia fonctionne](internals.md#maps-a-hash-table-then-a-hash-trie).

## Recursion

Une fonction qui s'appelle elle-même, directement ou à travers d'autres : la récursion. Chaque appel attend celui qu'il a
fait, jusqu'à la limite `depth`, sauf un appel en [tail position](#tail-call) : voir
[Fonctions](functions.md#a-function-that-calls-itself).

## Recursive descent

Une façon d'écrire un parser à la main : une fonction par règle de la grammaire, chacune appelant les autres, de sorte que
l'imbrication des appels suit l'imbrication du code. Le parser de Cesia en est un : voir
[Comment Cesia fonctionne](internals.md#reading-the-lexer-and-the-parser).

## Regular expression

Un petit texte qui décrit un ensemble de textes, comme `\d+`, un chiffre ou plus, pour chercher, couper ou remplacer dans
un texte : une expression régulière. [std/regex] les exécute en un temps linéaire dans la longueur du texte : voir
[Textes](texts.md#regular-expressions).

## Rendezvous

Un envoi qui attend qu'un destinataire prenne sa valeur, de sorte que les deux tâches se rencontrent : le channel
synchrone de CSP, et l'unbuffered channel de Go. Un [fiber.Channel] de taille 0 en est un : voir
[Fibers](fibers.md#a-channel-of-a-size).

## REPL

Read, eval, print loop : un prompt qui exécute chaque expression tapée et montre sa valeur. Celui de Cesia tourne à côté
du programme en cours, `cesia run --repl app.ce`, à l'intérieur du package de son fichier principal : voir
[Le prompt et le debugger](debug.md#the-prompt).

## Route

Une règle qui envoie les requêtes d'une méthode et d'un chemin à un handler. [http.Get] et [http.Post] en ajoutent une, et
`:name` dans un chemin prend n'importe quel mot : voir [HTTP](http.md#an-application).

## Salt

Des octets au hasard gardés avec le hash d'un mot de passe, pour que deux mots de passe égaux donnent deux hashes
différents et qu'une table de hashes calculée à l'avance ne serve à rien. [crypto.HashPassword] en ajoute un : voir
[Cryptographie](crypto.md#passwords).

## Sandbox

Un endroit où un programme tourne avec les seuls droits qu'on lui a donnés. Un programme Cesia démarre dans une sandbox,
et chaque `--allow` lui donne le droit à une sorte de chose, dans une portée donnée, comme Deno le fait pour JavaScript.
Voir [Permissions](permissions.md).

## Scalar replacement and allocation sinking

Deux façons pour un compilateur d'éviter de fabriquer une valeur qu'il voit en entier. Le *scalar replacement* garde un
objet qui ne quitte jamais un morceau de code sous la forme de ses seuls champs, dans des registres, comme Graal le fait
pour Java (Stadler, Würthinger et Mössenböck, 2014) ; l'*allocation sinking* ne fabrique l'objet que sur le chemin rare
qui en a besoin en entier, comme LuaJIT le fait aux sorties de ses traces (Pall, 2012). Dans le JIT de Cesia, `p = ps[i]`
lu seulement pour `p.X` et ses semblables, ce sont quatre doubles (des floats de 64 bits) dans des registres, et la map
n'est fabriquée que quand l'exécution rend la main à l'interpréteur : voir
[Comment Cesia fonctionne](internals.md#what-it-makes).

## Scheduler

La partie d'un runtime qui décide quelle tâche tourne ensuite. Celui de Cesia garde une queue, premier entré, premier
sorti, des fibers prêtes à tourner, et attend le système quand aucune ne l'est : voir
[Comment Cesia fonctionne](internals.md#how-a-fiber-stops-and-starts).

## Seed

Le nombre d'où part un générateur de nombres au hasard : le même seed donne les mêmes nombres, et une exécution peut donc
être rejouée. Une exécution de Cesia en prend un au système, [random.Seed] le dit, et `cesia run --seed N` le donne : voir
[Données](data.md#les-mêmes-nombres-une-seconde-fois).

## Serializable and snapshot isolation

Deux garanties d'une base de données sur les transactions qui tournent en même temps. Avec la *snapshot isolation*,
chaque transaction lit la base telle qu'elle était quand elle a commencé ; avec l'isolation *serializable*, le résultat est
le même que si les transactions avaient tourné l'une après l'autre. SQLite donne les deux : chaque lecture voit un
snapshot (une image figée de la base), et les écritures passent une à la fois. Voir
[SQLite](sqlite.md#what-a-transaction-guarantees).

## Shared library

Un fichier de code machine qu'un programme en cours charge et lie à lui-même, comme un `.so` sur Linux, un `.dylib` sur
macOS et un `.dll` sur Windows. Celles d'OCaml sont des plugins, des fichiers `.cmxs` : Cesia charge ainsi son JIT, son
SQLite et les moteurs des packages natifs, à leur première utilisation. Voir [Packages natifs](native.md#using-one).

## Shell injection

Une commande que personne n'a écrite, lancée parce qu'un texte donné à un shell contient un `;` ou un backtick (l'accent
grave) : un fichier nommé `x; touch owned` lancerait `touch`. [sys.Run] passe ses arguments sous forme de liste, à aucun
shell : cela ne peut donc pas arriver. Voir [Fichiers](files.md#other-programs).

## Short-circuit evaluation

`and` et `or` s'arrêtent dès que la réponse est connue : leur côté droit peut donc ne jamais s'exécuter.
`false and f()` n'appelle jamais `f`. Voir [Valeurs et noms](values.md#vrai-et-faux).

## Shrinking

Rendre un cas qui échoue plus petit tant qu'il échoue encore, pour que l'échec montré soit le plus simple.
[test.ForAll] réduit les tirages qui ont produit un cas, sa tape (la bande des tirages), comme le fait Hypothesis : voir
[Tests](tests.md#properties).

## Side effect

Ce qu'une fonction fait en plus de donner son résultat : afficher, écrire un fichier, envoyer une requête. En Cesia,
chaque side effect qui touche la machine demande une permission : la ligne de commande dit donc lesquels un programme peut
avoir. Voir [Fichiers](files.md).

## Signature

Un texte court fabriqué à partir d'un message avec une clé secrète, que n'importe qui ayant la clé publique peut
vérifier : il prouve qui a écrit le message et que celui-ci n'a pas été modifié. [crypto.Sign] en fabrique une en
Ed25519 : voir [Cryptographie](crypto.md#signatures).

## Snapshot testing

Un test qui garde le texte d'une valeur dans un fichier à côté de lui, et compare la valeur à ce texte à chaque
exécution, pour qu'une longue sortie n'ait pas à être écrite à la main. [test.Snapshot] le fait : voir
[Tests](tests.md#snapshots).

## Specialization

Fabriquer une version à part d'une fonction pour chaque combinaison des types de ses arguments, pour que chaque version
connaisse ses types : on l'appelle customization dans le langage Self, où elle est née. Une fonction de Cesia a jusqu'à
8 versions, puis une version générique : voir [Comment Cesia fonctionne](internals.md#types-inference-and-versions).

## SSA form

Static single assignment : une forme de code où chaque variable reçoit sa valeur à un seul endroit, de sorte qu'un
compilateur voit tout de suite d'où vient chaque valeur. Là où deux chemins se rejoignent, comme au début d'une boucle,
un *phi* choisit la version du chemin par lequel on est arrivé ; quitter le SSA pour la machine met une copie sur chaque
chemin qui y mène. MIR, qui fabrique le code machine de Cesia, travaille ainsi, et on n'entre dans une boucle de Cesia
que par un point placé juste avant elle, pour que son seul point de rencontre ne tienne que ce que la boucle change : voir
[Comment Cesia fonctionne](internals.md#what-it-makes).

## Standard input and output

Le texte qu'un programme lit, et le texte qu'il écrit, dans un terminal ou un pipe du shell (un tuyau qui relie la sortie
d'un programme à l'entrée d'un autre) ; la standard error est une seconde sortie, pour ce qui n'a pas marché. En Cesia,
[io.Print] écrit sur la standard output, [io.PrintError] sur la standard error, et [sys.ReadInput] lit toute la standard
input : voir [Fichiers](files.md#standard-input-and-the-exit-code).

## Static typing

Des types vérifiés avant que le programme tourne, pour chaque variable et chaque expression, comme en Java, Go et OCaml :
un programme dont on ne peut pas prouver qu'il est juste est refusé. Les types de Cesia sont vérifiés quand le programme
tourne, et `cesia check` signale avant ce qu'il peut prouver faux : voir
[Types](types.md#checked-when-a-value-comes-in).

## Storage strategy

Une collection qui range ses éléments selon leur sorte, comme des nombres machine nus tant qu'ils sont tous des nombres
d'une même sorte, et qui passe une fois, pour de bon, à un rangement général quand une autre sorte arrive (Bolz,
Diekmann et Tratt, 2013, venu de PyPy). Les listes de Cesia gardent ainsi des entiers, des floats ou des valeurs, la hash
table d'une grande map garde nues ses valeurs entières, et une petite map ou une struct garde ses valeurs en doubles
tant que toutes sont des floats : le programme voit les mêmes valeurs dans tous les cas. Voir
[Comment Cesia fonctionne](internals.md#maps-a-hash-table-then-a-hash-trie).

## String interpolation

Des valeurs écrites à l'intérieur d'un texte, là où elles vont. En Cesia, `"Hello, $name"` et `"$(2 + 2)"`, qui sont la
forme courte de [text.Str] : voir [Valeurs et noms](values.md#textes).

## Struct

Une valeur avec un ensemble fixe de champs nommés, qu'on appelle aussi un record. [struct] en déclare une, avec des
valeurs par défaut et des types, et un champ mal écrit est une erreur : voir [Structs](structs.md).

## Structural sharing

Deux versions d'une structure persistante qui partagent les parties qu'elles ont en commun, de sorte qu'un changement ne
copie que ce qu'il touche. Une écriture dans une map de Cesia copie le chemin de nœuds jusqu'à sa clé, au plus 6 petits
arrays, et partage le reste : voir [Comment Cesia fonctionne](internals.md#maps-a-hash-table-then-a-hash-trie).

## Structural typing

Une valeur satisfait un type par ce qu'elle a, pas par une déclaration qui nomme le type. Une [interface] de Cesia est
satisfaite par toute valeur qui a ses méthodes, comme en Go : voir [Types](types.md#interfaces).

## Sum type

Un type dont les valeurs sont l'un de quelques cas, chacun avec ses propres données. Celui de Cesia est le résultat : soit
[result.Ok] d'une valeur, soit [result.Err] d'une erreur, et [match] le défait cas par cas : voir
[Erreurs](errors.md#looking-at-a-result).

## Supervisor

Un processus qui en démarre d'autres et redémarre celui qui s'arrête, comme le font les supervisors d'Erlang. Sous
`cesia run --workers`, le premier processus est le supervisor des workers, et attend un peu plus longtemps chaque fois que
l'un d'eux s'arrête trop tôt : voir [Comment Cesia fonctionne](internals.md#on-every-core).

## Surrogate

Un code point (le numéro d'un caractère dans Unicode) de U+D800 à U+DFFF, que UTF-16 réserve pour écrire en deux moitiés
les caractères au-delà de U+FFFF. Ce n'est pas un caractère à lui seul : un UTF-8 valide n'en contient donc jamais.
[text.IsUtf8] le refuse. Voir [Textes](texts.md#valid-utf-8).

## SWAR

SIMD within a register : la même opération sur plusieurs petites valeurs serrées dans un seul mot machine, comme huit
octets dans 64 bits, avec les instructions ordinaires du processeur. [text.Count] trouve ainsi les octets égaux à celui
qu'il compte, huit à la fois, et [text.ByteFind] l'octet le plus rare de la partie qu'il cherche : voir
[Textes](texts.md#searching) et [Bytes](texts.md#bytes).

## Syntax sugar

Une façon plus courte d'écrire ce que le langage sait déjà dire. Ce livre montre chacune à côté de sa forme simple,
vérifiée : `a..b` est [list.Range]`(a, b)`, et `d.Name` est `d["Name"]` : voir [Listes et arrays](lists.md#ranges).

## Syntax tree

Le programme sous forme d'arbre, un nœud par expression ou par statement, avec la ligne et la colonne de chacun : ce que
le parser fabrique à partir du texte, et ce que Cesia compile. Voir
[Comment Cesia fonctionne](internals.md#reading-the-lexer-and-the-parser).

## Tail call

Un appel dont le résultat est le résultat de la fonction qui le fait, sans rien qui reste à faire après lui. Une fonction
de Cesia qui s'appelle elle-même en tail position tourne comme une boucle, dans une seule frame : elle n'a donc pas de
limite de profondeur. Voir [Fonctions](functions.md#a-function-that-calls-itself).

## Threat to validity

Une cause qui pourrait rendre fausse la conclusion d'une expérience alors que rien en elle n'a l'air faux : un cache
warm, un dossier d'une forme inhabituelle, un autre programme sur la machine. Chacune est nommée, puis écartée ou mesurée :
voir [Résoudre un vrai problème](duplicates.md#threats-to-validity).

## Thundering herd

Beaucoup de processus réveillés à la fois pour un événement qu'un seul d'entre eux peut prendre, et qui se le disputent
ensuite pour rien. Sur Linux, les workers de `--workers` surveillent le listener (la socket qui accepte les connexions)
avec `EPOLLEXCLUSIVE` : une nouvelle connexion n'en réveille donc qu'un. Voir
[Comment Cesia fonctionne](internals.md#on-every-core).

## Timing attack

Trouver un secret en mesurant le temps qu'un programme met à comparer un essai avec lui, puisqu'une comparaison qui
s'arrête au premier octet faux prend plus longtemps pour un meilleur essai. [crypto.IsSame] compare en un temps qui ne
dépend que de la longueur : voir [Cryptographie](crypto.md#comparing-secrets).

## Transaction

Des changements dans une base de données qui se font tous ensemble ou pas du tout. Ceux de SQLite sont ACID : atomic,
consistent, isolated et durable (atomiques, cohérents, isolés et durables). [sql.Transaction] les garde tous sur un `Ok`,
et les défait tous sur un `Err` ou une panic : voir [SQLite](sqlite.md#transactions).

## Trie

Un arbre où chaque niveau est choisi par un morceau de la clé, comme un dictionnaire de mots est rangé par leur première
lettre, puis la deuxième. Dans un hash trie, les morceaux viennent du hash de la clé : voir
[hash array mapped trie](#hash-array-mapped-trie).

## Type coercion

Une valeur changée en un autre type par le langage lui-même. Cesia le fait dans un seul cas : un `Int` devient un `Float`
là où un `Float` est attendu, ou à côté d'un float dans un calcul. Un texte ne devient jamais un nombre de lui-même :
voir [Types](types.md#an-int-becomes-a-float).

## Type feedback

Les types qu'un programme a vraiment rencontrés pendant qu'il tournait, qu'un JIT lit pour parier dessus. Le JIT de Cesia
les lit dans la frame d'une boucle quand il la compile : voir [Comment Cesia fonctionne](internals.md#bets-guards-and-bails).

## Union bound

La règle qui dit que la probabilité qu'au moins un de plusieurs événements arrive est au plus la somme de leurs
probabilités. Elle ne suppose rien sur la façon dont les événements dépendent les uns des autres, et c'est pourquoi elle
donne si simplement la birthday bound : voir [Résoudre un vrai problème](duplicates.md#4-research).

## UTF-8

La façon habituelle d'écrire un texte en octets : `a` en prend un, `é` deux, un emoji quatre. Un texte de Cesia est en
UTF-8 : [value.Len] et [text.Slice] comptent des caractères, [text.ByteLength] et [text.ByteSlice] des octets : voir
[Textes](texts.md#bytes).

## Value semantics

Donner un second nom à une valeur, ou la passer à une fonction, se comporte comme une copie : un changement par un nom ne
se voit jamais par l'autre. Toutes les valeurs de Cesia marchent ainsi, les listes et les dictionnaires aussi : voir
[Valeurs et noms](values.md#noms).

## Vectorized operation

Une seule opération sur un array entier, exécutée élément par élément par la machine au lieu d'une boucle du programme.
En Cesia, `prices * 2` et `Sqrt(xs)` travaillent sur des arrays entiers, et sur les colonnes d'une frame : voir
[Listes et arrays](lists.md#whole-arrays-at-once).

## Vendoring

Copier dans le projet lui-même le code dont il dépend, pour qu'il tourne exactement sur ce code. Un projet Cesia garde
ainsi `std/` et `deps/`, refaits à partir de `cesia.lock` par `cesia pkg install` : voir [Packages](packages.md#cesia-pkg).

## Wall clock

L'heure du jour telle que le système la tient, que le système peut avancer ou reculer, comme quand il se corrige par le
réseau. [sys.Now] la lit : voir [Fichiers](files.md#the-clock).

## WebSocket

Une connexion qui reste ouverte après une requête HTTP et porte des messages dans les deux sens, pour un chat ou une page
qui se met à jour seule, comme la RFC 6455 la définit. [http.Websocket] en sert une : voir [HTTP](http.md#websocket).

## Write-ahead log

Un fichier où chaque changement est écrit avant d'être appliqué à la base de données, pour qu'après un crash la base le
rejoue et ne perde rien de ce qui avait été confirmé ; il laisse aussi les lecteurs continuer pendant qu'un écrivain
travaille. Cesia ouvre chaque fichier SQLite dans ce mode, WAL : voir [SQLite](sqlite.md#what-a-transaction-guarantees).

## XSS

Cross-site scripting : un texte d'un visiteur qu'une page montre sans l'échapper (sans changer ses caractères spéciaux en
texte inoffensif), de sorte qu'un `<script>` qu'il contient tourne dans les pages des autres visiteurs. [http.Escape] et
[http.Template] échappent ce qu'ils mettent dans une page : voir [HTTP](http.md#escaping).

## Zero-downtime reload

Mettre en place une nouvelle version d'un serveur sans refuser ni perdre une seule requête : les nouveaux processus
démarrent et acceptent avant que les anciens s'arrêtent. HUP (un signal que le système envoie à un processus) le fait sous
`cesia run --workers` : voir [HTTP](http.md#a-new-version-without-a-pause).
