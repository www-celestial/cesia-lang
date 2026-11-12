# Choix et boucles

Dans ce chapitre, vous décidez de ce que fait un programme : avec `if`, une partie ne s'exécute que quand une condition
est vraie. Avec `for` et `while`, une partie s'exécute de nombreuses fois. Et `match` choisit parmi des formes de
données.

## if

[if] exécute son corps quand sa condition est vraie, et `else` s'exécute sinon. Chaque partie finit à `end` :

```cesia
use std/io
temperature = 31
if temperature > 30
  io.Print("Hot")
else
  io.Print("Fine")
end
```

### else if

`else if` enchaîne d'autres conditions. La première qui est vraie l'emporte :

```cesia
grade = 72
if grade >= 90
  io.Print("A")
else if grade >= 70
  io.Print("B")
else
  io.Print("C")
end
```

## if donne une valeur

Un `if` est aussi une valeur : celle de la partie qui s'est exécutée. Dans les mots du métier, le `if` de Cesia est une
*expression*, un morceau de code qui donne une valeur, et pas seulement un *statement*, un morceau qui ne fait qu'agir.
Il tient sur une ligne, ce qui remplace l'*opérateur ternaire* `c ? a : b` du C, de Java et de JavaScript :

```cesia
use std/math
n = 4
kind = if math.Mod(n, 2) == 0 "even" else "odd" end
kind -->
```

Sans `else`, un `if` dont la condition est fausse donne `missing` :

```cesia
if 1 > 2 "never" end -->
```

### La forme courte : a if c else b

La valeur d'abord, puis la condition, comme en Python : `a if c else b` est une façon courte d'écrire
`if c a else b end`. Les deux donnent le même arbre dans le parser (la partie qui lit le texte du programme et en fait un
arbre) : l'interpréteur et le JIT (la partie qui change en code machine ce qui tourne souvent) ne voient donc aucune
différence, et la forme courte ne coûte rien quand elle s'exécute, aussi souvent qu'un programme l'utilise. Elle demande
son `else` : sans lui, le `if` placé après une valeur commence un statement à part, comme il l'a toujours fait, et le
code écrit avant la forme courte garde donc son sens.

```cesia
use std/math
n = 4
kind = "even" if math.Mod(n, 2) == 0 else "odd"
kind -->
size = "big" if n > 10 else "mid" if n > 3 else "small"
size -->
```

Les deux mêmes, dans la forme ordinaire : `if math.Mod(n, 2) == 0 "even" else "odd" end` et
`if n > 10 "big" else if n > 3 "mid" else "small" end`. Dans une liste construite avec `for`, la forme courte choisit
chaque valeur, et un `if` placé après la source de la liste n'en garde que certaines, comme en Python :

```cesia
[x * 2 if x > 0 else 0 for x in [1, -2, 3, 4] if x != 4] -->
```

Après la tête d'un bloc, `if c`, `while c`, `for x in xs` ou `match x`, un `if` commence le corps, jamais une forme
courte : `for x in xs if x > 0 ... end end` est une boucle dont le corps est un `if`.

## for

[for] exécute son corps une fois pour chaque élément d'une liste ou d'une range (la suite des entiers d'un nombre à un
autre), dans l'ordre :

```cesia
for fruit in ["apple", "pear", "fig"]
  io.Print("I like", fruit)
end
```

### Positions

Une range donne les positions, quand vous en avez besoin :

```cesia
use std/value
names = ["Ana", "Bo"]
for k in 1..value.Len(names)
  io.Print(k, names[k])
end
```

Un `for` sur une range, `for k in 1..n`, compte de `1` à `n` sans fabriquer la liste `1..n` en mémoire : une boucle d'un
milliard de tours ne prend donc pas plus de mémoire qu'une boucle de dix. Un nom que la boucle change garde sa dernière
valeur après la boucle :

```cesia
total = 0
for x in [5, 10, 15]
  total += x
end
total -->
```

### Construire une liste avec for

Entre crochets, un `for` construit une liste, une [comprehension](glossary.md#comprehension) : chaque élément est la
valeur placée avant le `for`. Un `if` après lui n'en garde que certains :

```cesia
[x * x for x in 1..5] -->
[x for x in 1..10 if math.Mod(x, 3) == 0] -->
```

Une liste construite ainsi est la forme courte de [list.Map], et, avec un `if`, de [list.Filter]. Le chapitre
[Fonctions](functions.md) montre les deux :

```cesia
use std/list
[x * x for x in 1..5] --> list.Map(x -> x * x, 1..5)
[x for x in 1..10 if math.Mod(x, 3) == 0] --> list.Filter(x -> math.Mod(x, 3) == 0, 1..10)
```

## while et break

[while] exécute son corps tant que sa condition est vraie. Il vérifie la condition avant chaque tour : un corps dont la
condition est fausse dès le départ ne s'exécute donc jamais :

```cesia
n = 1
while n < 100
  n *= 2
end
n -->
```

### break

[break] quitte la boucle tout de suite, depuis `for` ou `while`. Ici, la boucle s'arrête au premier nombre au-dessus de
10 :

```cesia
for x in [3, 8, 12, 5, 20]
  if x > 10
    io.Print("First over 10:", x)
    break
  end
end
```

### Sortir plus tôt : break if c et return x if c

`break if c` est une façon courte d'écrire `if c break end`, et `return x if c` en est une pour `if c return x end`,
comme en Ruby. Ce sont les mêmes arbres : ces formes ne coûtent donc rien de plus. Ici, la boucle additionne des nombres
tant que le total reste inférieur ou égal à 9 :

```cesia
total = 0
for x in [4, 4, 4]
  break if total + x > 9
  total += x
end
total -->
```

Et une fonction qui donne le premier nombre négatif d'une liste, ou `"none"` :

```cesia
defn firstNegative(xs)
  for x in xs
    return x if x < 0
  end
  "none"
end
firstNegative([3, -2, -7]) -->
```

Seuls `return` et `break` prennent après eux un `if` sans `else`, et seulement quand la condition finit la ligne :
`return x if c y end` sur une seule ligne reste `return x` suivi d'un `if` à part, comme avant.
`return if c a else b end` garde aussi son sens : il renvoie la valeur de ce `if`.

## match

[match] compare une valeur à des patterns (des formes de valeurs), dans l'ordre, et donne la valeur du premier qui lui
va : c'est le [pattern matching](glossary.md#pattern-matching). Un pattern peut être une valeur, et `else` prend ce
qu'aucun pattern n'a pris :

```cesia
day(n) = match n
  6 -> "Saturday"
  7 -> "Sunday"
  else -> "a weekday"
end
day(7) -->
day(3) -->
```

### Formes

Un pattern peut aussi être une forme. Il défait la valeur et donne des noms à ses morceaux, ce qui s'appelle le
[destructuring](glossary.md#destructuring). `[a, b]` va à une liste de deux éléments, et `{Name: n}` à un dictionnaire
qui a cette clé :

```cesia
describe(x) = match x
  [] -> "an empty list"
  [a, b] -> "a pair: $a and $b"
  {Name: n} -> "someone called $n"
  else -> "something else"
end
describe([1, 2]) -->
describe({Name: "Ana"}) -->
describe(42) -->
```

### Défaire une valeur avec =

Un pattern marche aussi à gauche de `=` : il donne d'un coup des noms aux morceaux d'une valeur. C'est la forme courte de
la lecture de chaque morceau, et il vérifie aussi la forme :

```cesia
pair = [3, 4]
[x, y] = pair
x --> pair[1]
y --> pair[2]
{Name: who} = {Name: "Ana", Age: 31}
who -->
```

Une valeur qui ne va pas au pattern arrête le programme, et le message dit pourquoi :

```cesia fails
[a, b] = [1, 2, 3]
```

### Conditions et _

Un `if` après un pattern ajoute une condition, et `_` va à n'importe quoi sans lui donner de nom :

```cesia
sign(n) = match n
  0 -> "zero"
  x if x < 0 -> "negative"
  _ -> "positive"
end
sign(-5) -->
sign(8) -->
```

Un nom dans un pattern prend toujours une nouvelle valeur : il ne se compare jamais à une variable du même nom. Pour
comparer à une variable, utilisez un `if`.

### Quand rien ne va

Quand aucun pattern ne va et qu'il n'y a pas de `else`, le programme s'arrête, et nomme la valeur que rien n'a prise. Un
cas oublié se voit tout de suite, au lieu de donner une mauvaise réponse plus tard. Cette vérification a lieu quand le
`match` s'exécute : un langage qui a des sum types (des types dont chaque valeur est l'un de quelques cas) vérifiés à la
compilation, comme Rust ou OCaml, dit avant que le programme tourne qu'un cas manque, ce que Cesia, dont les valeurs
n'ont pas de type déclaré, ne peut pas toujours savoir :

```cesia fails
match 7
  1 -> "one"
  2 -> "two"
end
```

`match` défait aussi les résultats du chapitre sur les erreurs : `result.Ok(value)` et `result.Err(e)` sont aussi des
patterns.

## La suite

Vous savez choisir et répéter. Le chapitre suivant, [Fonctions](functions.md), donne un nom à un travail, pour que vous
puissiez l'appeler à nouveau.
