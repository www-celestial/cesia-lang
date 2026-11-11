# Nombres et algorithmes

Dans ce chapitre, vous découvrez les bibliothèques de calcul : [std/math] pour un nombre seul, [std/num] pour les arrays
(les listes et les matrices de nombres), les matrices et les statistiques, [std/lapack] pour les grandes matrices,
[std/algo] pour les algorithmes classiques, et trois structures à côté des listes et des dictionnaires : les sets (des
ensembles sans doublon), les queues (des files) et les heaps (des tas, qui rendent d'abord la plus petite clé). Chaque
fonction est dans la référence, avec ses exemples ; ce chapitre montre à quoi sert chaque bibliothèque, et ce qu'elle
coûte.

## Un nombre : std/math

[std/math] contient les opérateurs sous forme de fonctions, [math.Add], [math.Sub], [math.Mul], [math.Div] et [math.Mod],
et [math.Inc] et [math.Dec] ; les arrondis, [math.Round], [math.Floor] et [math.Ceil] ; [math.Abs] et [math.Sign] ; les
racines, les puissances et les logarithmes, [math.Sqrt], [math.Exp] et [math.Log] ; la trigonométrie en radians,
[math.Sin], [math.Cos], [math.Tan], [math.Asin], [math.Acos], [math.Atan], et [math.Atan2] pour l'angle d'un point ; les
constantes [math.Pi] et [math.Nan] ; et les tests [math.IsZero], [math.IsPos], [math.IsNeg], [math.IsEven] et
[math.IsOdd]. Chaque fonction d'un seul nombre marche aussi sur un array, élément par élément.

```cesia
use std/math
math.Ceil(2.1) -->
math.Sign(-3) -->
math.Atan2(1.0, 1.0) * 4 --> math.Pi
math.Log(math.Exp(2.0)) -->
math.Sqrt([4, 9]) -->
math.IsEven(10) -->
```

[math.Div] arrondit vers le bas, vers moins l'infini, et [math.Mod] a le signe du diviseur : `math.Mod(-7, 3)` vaut donc
`2`, et `math.Div(-7, 3) * 3 + math.Mod(-7, 3)` redonne `-7`. C'est la *floored division* (la division arrondie vers le
bas) de Python, pas la division *tronquée* (arrondie vers zéro) du C et de Java, où `-7 % 3` vaut `-1`.

```cesia
math.Div(-7, 3) -->
math.Mod(-7, 3) -->
```

### Les bits

[math.BitAnd], [math.BitOr], [math.BitXor] et [math.BitNot] travaillent sur les bits des entiers, et [math.BitShift] les
décale vers la gauche pour un nombre de positions positif, vers la droite pour un nombre négatif :

```cesia
math.BitAnd(12, 10) -->
math.BitOr(12, 10) -->
math.BitXor(12, 10) -->
math.BitShift(1, 4) -->
math.BitShift(16, -2) -->
```

## Arrays et statistiques : std/num

[std/num] fait du calcul numérique dans l'esprit de numpy : un array est une liste ou une matrice de floats (de nombres à
virgule), et les opérateurs du langage agissent déjà dessus élément par élément. Il ajoute le reste.

| Pour | Utilisez |
|---|---|
| faire des arrays | [num.Linspace] des floats régulièrement espacés, [num.Eye] la matrice identité, [num.Diag] une matrice diagonale |
| tirer des arrays au hasard | [num.Uniform] de 0 à 1, [num.Normal] selon la loi normale de moyenne 0 et d'écart type 1, tous deux avec le générateur de [std/random] |
| décrire | [num.Median], [num.Percentile], [num.Variance], [num.Std], [num.Covariance], [num.Correlation], [num.Histogram] |
| cumuler le long d'un array | [num.Cumsum] la somme cumulée, [num.Diff] les différences, [num.Trapezoid] l'aire sous des points |
| ajuster | [num.Polyfit] un polynôme passant par des points, [num.Polyval] sa valeur, [num.Interpolate] entre des points, [num.LeastSquares] le meilleur `x` de `a * x = b` |
| algèbre linéaire | [num.Dot], [num.Norm], [num.Det], [num.Solve], [num.Inverse], [num.Qr], [num.Eigen] |
| signaux | [num.Fft] et [num.Ifft], la transformée de Fourier et son inverse |

```cesia
use std/num
num.Linspace(0.0, 1.0, 5) -->
num.Percentile(90, 1..10) -->
num.Correlation([1.0, 2.0, 3.0], [2.0, 4.0, 6.5]) -->
num.Cumsum([1, 2, 3]) -->
num.Trapezoid([0.0, 1.0, 2.0], [0.0, 1.0, 4.0]) -->
num.Solve([2.0, 1.0; 1.0, 3.0], [3.0; 5.0]) -->
num.Det([1.0, 2.0; 3.0, 4.0]) -->
```

### Comment il calcule

- [num.Solve], [num.Det] et [num.Inverse] utilisent l'*élimination de Gauss avec pivot partiel* : à chaque colonne, la
  ligne qui a la plus grande valeur passe en premier, ce qui garde les erreurs d'arrondi petites. Une matrice dont le
  pivot tombe sous $10^{-14}$ est *singulière* : elle n'a pas d'inverse, et donne une `Err` de sorte `"math"`.
- [num.Eigen] prend une matrice symétrique et la rend diagonale par des *rotations de Jacobi*, dont chacune annule une
  valeur hors de la diagonale ; la diagonale qui reste contient les *valeurs propres*, les nombres $\lambda$ pour lesquels
  $a v = \lambda v$ a une solution $v$, son *vecteur propre*.
- [num.LeastSquares] résout les *équations normales*, $a^T a x = a^T b$. C'est rapide, mais cela élève au carré le
  *nombre de conditionnement* de $a$, qui dit de combien une erreur dans les données grossit dans la réponse : un $a$
  presque singulier perd donc des chiffres. [num.Qr] donne les facteurs d'une méthode plus stable.
- [num.Fft] est la *transformée de Fourier rapide* en base 2 de Cooley et Tukey, en $O(n \log n)$, quand la longueur est
  une puissance de deux, et la somme directe, en $O(n^2)$, sinon.

### Grandes matrices : BLAS et LAPACK

*BLAS* est l'interface standard des opérations de base de l'algèbre linéaire, comme le produit de matrices, et *LAPACK*
celle de la résolution, de la factorisation et des valeurs propres, écrite sur BLAS ; OpenBLAS et Accelerate d'Apple en
sont des versions rapides, réglées pour chaque processeur. Une release de Cesia (une version publiée) apporte OpenBLAS
sur Linux et Windows, et utilise Accelerate sur macOS. [num.Backend] et [lapack.Name] disent laquelle sert, ou `missing`.
[matrix.Matmul], [num.Solve], [num.Det], [num.Qr] et [num.Eigen] l'appellent pour une grande matrice, à partir de
l'ordre 32, ou à partir de $32 \times 32 \times 32$ multiplications pour un produit, et utilisent le code de Cesia lui-même
en dessous, ou quand aucune bibliothèque n'est là ; ce code donne les mêmes bits sur toutes les machines. [std/lapack]
l'appelle directement, et donne `missing` là où il ne le peut pas : [lapack.Solve], [lapack.Det], [lapack.Qr] et
[lapack.Eigen]. `CESIA_BLAS=none` ne fait tourner que le code de Cesia, pour comparer.

## Algorithmes : std/algo

[std/algo] contient les algorithmes classiques, écrits en Cesia, avec les fonctions en premiers arguments et la collection
en dernier.

| Pour | Utilisez |
|---|---|
| chercher dans un array trié | [algo.BinarySearch] la position d'une valeur, [algo.LowerBound] la première position dont la valeur n'est pas plus petite, en $O(\log n)$ |
| couper et combiner | [algo.Chunk] des morceaux de `n`, [algo.Windows] des fenêtres glissantes de `n`, [algo.Partition] selon un test, [algo.Combinations], [algo.Permutations] |
| entiers | [algo.Gcd] et [algo.Lcm] (PGCD et PPCM), [algo.IsPrime] par divisions successives, [algo.Primes] par le crible d'Ératosthène |
| textes | [algo.Levenshtein], l'*edit distance* : le plus petit nombre d'insertions, de suppressions et de remplacements d'un caractère pour passer d'un texte à l'autre |
| graphes | [algo.Bfs] en largeur d'abord et [algo.Dfs] en profondeur d'abord, [algo.Dijkstra] les plus courtes distances, [algo.TopologicalSort] un ordre où chaque nœud vient après ceux dont il a besoin |

```cesia
use std/algo
algo.BinarySearch(7, [1, 3, 7, 9]) -->
algo.Chunk(2, [1, 2, 3, 4, 5]) -->
algo.Windows(2, [1, 2, 3]) -->
algo.Gcd(84, 36) -->
algo.Primes(20) -->
algo.Levenshtein("kitten", "sitting") -->
```

Un *graphe* est ici une fonction qui donne les voisins d'un nœud : aucune structure n'a donc à être construite d'abord.

```cesia
roads = {a: [{Node: "b", Weight: 4}, {Node: "c", Weight: 1}], c: [{Node: "b", Weight: 2}], b: []}
algo.Dijkstra(n -> roads[n], "a") -->
algo.Bfs(n -> [e.Node for e in roads[n]], "a") -->
needs = {app: ["lib", "log"], lib: ["log"], log: []}
algo.TopologicalSort(n -> needs[n], ["app", "lib", "log"]) -->
```

[algo.Dijkstra] garde les nœuds à visiter dans un [std/heap], selon leur distance trouvée jusque-là : il prend donc
$O(E \log E)$ pour $E$ arêtes ; ses poids ne doivent pas être négatifs. [algo.TopologicalSort] parcourt le graphe en
profondeur d'abord, et donne une `Err` de sorte `"cycle"` quand un nœud a besoin de lui-même à travers d'autres.

## Sets, queues et heaps

Trois structures persistantes, comme les listes et les dictionnaires : un changement donne une nouvelle valeur, et
l'ancienne reste.

- Un *set*, [std/set], contient des nombres et des textes, chacun une seule fois, dans l'ordre : [set.Of], [set.Empty],
  [set.Add], [set.Remove], [set.Has], [set.Items], [set.Union], [set.Intersection], [set.Difference] et [set.IsSubset].
  C'est un dictionnaire dont les clés sont ses éléments : un test ou un changement coûte donc ce que coûte celui d'un
  dictionnaire, $O(\log_{32} n)$ ; [set.Items] les trie, en $O(n \log n)$.
- Une *queue*, [std/queue], est ouverte aux deux bouts, une *deque* : [queue.Push] ajoute à l'arrière et
  [queue.PushFront] à l'avant, [queue.Pop] et [queue.PopBack] retirent, [queue.First] et [queue.Last] lisent les bouts,
  [queue.Items] donne tous les éléments, [queue.Of] et [queue.Empty] en font une, [queue.IsEmpty] demande si elle est
  vide ; [queue.Queue] est sa struct (sa forme déclarée, aux champs nommés). C'est un dictionnaire des positions vers les
  éléments : chaque opération est donc en $O(\log_{32} n)$, comme pour un dictionnaire.
- Un *heap*, [std/heap], rend la plus petite clé en premier, une *priority queue* : [heap.Insert] ajoute une valeur sous
  une clé, [heap.Peek] lit la plus petite, [heap.Pop] la retire, [heap.Merge] réunit deux heaps, [heap.Items] les donne
  toutes dans l'ordre, puis [heap.Empty] et [heap.IsEmpty]. C'est un *leftist heap*, tiré du livre d'Okasaki : sa branche
  la plus courte est toujours à droite, si bien qu'une insertion, un retrait ou une fusion se fait en $O(\log n)$.

```cesia
use std/set
use std/queue
use std/heap
set.Items(set.Union(set.Of([3, 1]), set.Of([2, 3]))) -->
set.IsSubset(set.Of([1]), set.Of([1, 2])) -->
q = queue.Of([1, 2]) then queue.Push(3) then queue.PushFront(0)
queue.Items(q) -->
queue.First(queue.Pop(q)) -->
h = heap.Empty() then heap.Insert(5, "low") then heap.Insert(1, "urgent")
heap.Peek(h) -->
heap.Items(heap.Pop(h)) -->
```

## Pour aller plus loin

- E. Anderson et al., *LAPACK Users' Guide*, 1999 ; Cooley et Tukey, *An Algorithm for the Machine Calculation of
  Complex Fourier Series*, 1965 ; Charles R. Harris et al., *Array programming with NumPy*, 2020.
- E. W. Dijkstra, *A note on two problems in connexion with graphs*, 1959 ; V. I. Levenshtein, *Binary codes capable of
  correcting deletions, insertions, and reversals*, 1966.
- Chris Okasaki, *Purely Functional Data Structures*, 1998 : le leftist heap et les structures persistantes.

Chacun avec son lien dans [Références](references.md#data-and-numbers).

## La suite

Vous savez calculer avec des nombres et des structures. Le chapitre suivant, [JSON et CSV](json.md), lit les données
d'autres programmes et en écrit pour eux.
