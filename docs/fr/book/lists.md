# Listes et arrays

Dans ce chapitre, vous gardez beaucoup de valeurs en une seule : une liste de noms, une colonne de nombres, une matrice.
Vous les lisez, vous y ajoutez, vous les triez, et vous calculez d'un coup sur des arrays entiers : un array est une
liste de valeurs rangées par position, ou une matrice.

## Listes

Une liste s'écrit entre crochets. Ses éléments peuvent être de n'importe quelle sorte, et le premier est à la position 1 :

```cesia
use std/value
names = ["Ana", "Bo", "Cyril"]
names[1] -->
names[3] -->
value.Len(names) -->
```

`names[1]` est la forme courte de [list.Nth]`(1, names)` :

```cesia
use std/list
list.Nth(1, names) --> names[1]
```

### Hors de la liste

Une position hors de la liste est une erreur, qui donne la taille de la liste :

```cesia fails
names[5]
```

[list.First] et [list.Last] lisent les deux bouts, et donnent `missing` pour une liste vide au lieu d'arrêter le
programme.

```cesia
list.Last(names) -->
list.First([]) -->
```

## Ajouter et prendre

[list.Append] donne une nouvelle liste avec un élément de plus à la fin. [list.Concat] joint deux listes, [list.Take]
garde les premiers éléments et [list.Skip] les laisse de côté :

```cesia
list.Append("Dee", names) -->
list.Concat([1, 2], [3, 4]) -->
list.Take(2, names) -->
list.Skip(1, names) -->
```

Comme pour toute valeur, la liste que vous donnez ne change pas, elle est [immutable](glossary.md#immutability) :

```cesia
more = list.Append("Dee", names)
value.Len(names) -->
value.Len(more) -->
```

### Construire une liste dans une boucle

Une liste grandit bien un élément à la fois : la construire dans une boucle est donc la façon habituelle. Une liste que
rien d'autre ne garde a des cases libres derrière son dernier élément, et leur nombre double quand elles viennent à
manquer : chaque [list.Append] coûte donc en moyenne un temps constant, une constante *amortized* (amortie sur toute la
suite des ajouts) :

```cesia
squares = []
for n in 1..5
  squares = list.Append(n * n, squares)
end
squares -->
```

### Changer un élément

Pour changer un élément, donnez sa position. Seul ce nom voit le changement :

```cesia
scores = [10, 20, 30]
scores[2] = 25
scores -->
```

## Ranges

`a..b`, une range, est la liste des entiers de `a` à `b`, tous deux compris. C'est la forme courte de
[list.Range]`(a, b)`, qui prend aussi un pas :

```cesia
1..5 -->
list.Range(1, 5) --> 1..5
list.Range(0, 1, step = 0.25) -->
list.Sum(1..100) -->
```

### Une partie d'une liste

Dans les crochets d'une liste, une range en prend une partie, et `end` est sa dernière position. Ce sont des formes
courtes de [list.Take] et [list.Skip] :

```cesia
names[1..2] --> list.Take(2, names)
names[2..end] --> list.Skip(1, names)
```

## Trier

[list.Sort] range les éléments dans l'ordre croissant, nombres ou textes. [list.SortBy] trie selon ce qu'une fonction
donne pour chaque élément, ici la longueur de chaque nom. [list.Reverse] retourne une liste :

```cesia
list.Sort([3, 1, 2]) -->
list.Sort(["pear", "apple", "fig"]) -->
list.SortBy(value.Len, ["pear", "apple", "fig"]) -->
list.Reverse([1, 2, 3]) -->
```

Les deux fonctions de tri gardent les éléments égaux dans l'ordre qu'ils avaient.

### Unique et IndexOf

[list.Unique] enlève les répétitions, et [list.IndexOf] trouve où est une valeur, ou donne `missing` :

```cesia
list.Unique([1, 2, 1, 3, 2]) -->
list.IndexOf("Bo", names) -->
```

### in

`x in xs` demande si une valeur est un élément d'une liste. C'est la forme courte d'une demande de position à
[list.IndexOf] :

```cesia
"Bo" in names -->
"Zoe" in names -->
"Bo" in names --> value.IsSome(list.IndexOf("Bo", names))
```

## Des arrays entiers d'un coup

Un array de nombres calcule élément par élément, une [vectorized operation](glossary.md#vectorized-operation) : pas de
boucle à écrire. Un opérateur entre deux arrays de même taille agit sur chaque paire, et un nombre avec un array agit
sur chaque élément :

```cesia
use std/math
prices = [10, 20, 30]
prices * 2 -->
prices + [1, 2, 3] -->
math.Sqrt([1, 4, 9]) -->
```

### Comparer des listes entières

Une comparaison agit aussi sur chaque paire : `==` entre deux listes donne une liste de `true` et de `false`. Pour
demander si deux listes sont identiques dans leur ensemble, [value.Equal] donne une seule réponse :

```cesia
prices == [10, 25, 30] -->
value.Equal(prices, [10, 20, 30]) -->
```

### Un nombre tiré d'un array

[list.Sum], [list.Mean], [list.Min] et [list.Max] réduisent un array à un seul nombre :

```cesia
list.Sum(prices) -->
list.Mean(prices) -->
list.Max(prices) -->
```

C'est aussi la façon rapide : le travail tourne dans une boucle en code machine, et non en un pas du programme par
élément.

## Matrices

Une matrice s'écrit ligne par ligne, les lignes séparées par `;`. Deux positions lisent un élément : la ligne, puis la
colonne. [value.Size] donne le nombre de lignes et de colonnes :

```cesia
use std/matrix
m = [1, 2; 3, 4]
m[2, 1] -->
value.Size(m) -->
matrix.Transpose(m) -->
```

[matrix.Matmul] est le produit de matrices, en floats (des nombres à virgule) :

```cesia
matrix.Matmul(m, m) -->
```

Pour aller plus loin, comme résoudre un système d'équations, la bibliothèque `std/num` a [num.Solve] et ses voisines ;
le chapitre sur les données y revient.

## Des arrays de plus de dimensions

Un champ de températures dans l'espace, ou une pile d'images, est un array de trois dimensions ou plus. [matrix.Zeros],
[matrix.Ones] et [list.Fill] prennent une taille pour chaque dimension, et un élément prend une position pour chacune :

```cesia
a = matrix.Zeros(2, 3, 4)
a[1, 2, 3] = 5.0
a[1, 2, 3] -->
value.Size(a) -->
```

Les éléments se suivent colonne par colonne : la première position change le plus vite. C'est le *column-major order*
(l'ordre par colonnes), comme en Fortran, MATLAB, R et Julia ; le C et numpy gardent plutôt les lignes ensemble, en
*row-major* (l'ordre par lignes). Une position seule compte dans cet ordre, comme dans une matrice :

```cesia
a[15] -->
```

Un tel array ne s'écrit pas dans le code : [matrix.Reshape] donne aux éléments d'une liste la forme d'une liste de
tailles. L'array s'affiche matrice par matrice sur ses deux premières dimensions, avec `;;;` avant la suivante le long
de la troisième, et `;;;;` le long de la quatrième :

```cesia
c = matrix.Reshape([2, 2, 2], 1..8)
c -->
matrix.Reshape([2, 4], c) -->
```

Un mauvais nombre de positions est une erreur, qui dit combien l'array en prend :

```cesia fails
c[1, 2]
```

Les calculs et les comparaisons agissent élément par élément, comme sur une matrice, entre des arrays de mêmes tailles
ou avec un nombre :

```cesia
c * 2 -->
c > 4 -->
```

### Sommes le long d'une dimension

[list.Sum] avec `dim` additionne le long de cette dimension, que le résultat n'a plus : le long de la troisième
dimension d'un array de 2 sur 2 sur 2, on obtient une matrice de 2 sur 2. Sur une matrice, `dim = 1` donne la somme de
chaque colonne et `dim = 2` celle de chaque ligne, toutes deux sous forme de listes. [list.Mean] prend aussi `dim` :

```cesia
list.Sum(c, dim = 3) -->
list.Sum(m, dim = 1) -->
list.Sum(m, dim = 2) -->
list.Mean(c, dim = 1) -->
```

[matrix.Matmul] et [matrix.Transpose] restent réservées aux matrices. [json.Text] écrit un array de plus de dimensions
sous forme de listes dans des listes, la première position étant la plus extérieure.

## D'autres fonctions de std/list

| Pour | Utilisez |
|---|---|
| lire | [list.Second], [list.TakeLast], [list.DropLast], [list.TakeWhile], [list.DropWhile] |
| ajouter | [list.Prepend] au début, [list.Interleave] deux listes tour à tour, [list.Interpose] un séparateur entre les éléments, [list.Flatten] des listes de listes en une seule |
| fabriquer | [list.Repeatedly] les résultats d'une fonction, [list.Iterate] `x`, `f(x)`, `f(f(x))`... |
| changer | [list.MapIndexed] avec la position, [list.FlatMap] puis joindre, [list.Keep] les résultats qui ne sont pas `missing`, [list.Remove] les éléments qu'un test refuse |
| demander | [list.Any] sur une liste de booléens, [list.MinBy] selon une fonction, [list.Order] les positions qui la trient |

```cesia
use std/text
list.Prepend(0, [1, 2]) -->
list.Interpose(", ", ["a", "b", "c"]) -->
list.Flatten([[1, 2], [3]]) -->
list.Iterate(it * 2, 1, 5) -->
list.MapIndexed((k, x) -> "$k:$x", ["a", "b"]) -->
list.Keep(text.Number, ["1", "x", "3"]) -->
list.Order([30, 10, 20]) -->
list.Any([false, true]) -->
```

### Ce que coûte chaque opération

| Opération | Coût |
|---|---|
| `xs[k]`, `value.Len(xs)` | constant |
| `xs[k] = v`, [list.Append] sur une liste que rien d'autre ne garde | constant, amortized pour Append |
| les mêmes sur une liste partagée | une copie de la liste, une fois, puis constant |
| [list.Concat], [list.Take], [list.Skip], [list.Map], [list.Filter] | linéaire : une nouvelle liste |
| [list.Sort], [list.SortBy], [list.Order] | $O(n \log n)$, stable : les éléments égaux gardent leur ordre |
| `x in xs`, [list.IndexOf] | linéaire : une recherche depuis le début |

## La suite

Vous savez garder beaucoup de valeurs et calculer avec elles. Le chapitre suivant, [Choix et boucles](choices.md),
décide de ce qui s'exécute et combien de fois.
