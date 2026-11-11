# Fonctions

Dans ce chapitre, vous écrivez vos propres fonctions, courtes et longues, et vous leur donnez des valeurs par défaut et
des arguments nommés. Puis vous passez des fonctions à d'autres fonctions, des
[higher-order functions](glossary.md#higher-order-function) (des fonctions qui prennent ou rendent des fonctions) : c'est
ainsi que Cesia travaille sur les listes, avec [list.Map], [list.Filter] et [list.Reduce].

## La forme courte

Une fonction qui tient sur une ligne s'écrit comme une équation : son nom, ses paramètres, `=`, et la valeur qu'elle
donne.

```cesia
double(x) = x * 2
area(width, height) = width * height
double(21) -->
area(3, 4) -->
```

On appelle une fonction avec ses arguments entre parenthèses, dans l'ordre de ses paramètres. Un nom qui commence par une
minuscule est privé au package de son fichier (le dossier dont ce fichier fait partie) ; une majuscule le rend public,
comme pour tout nom.

## La forme longue

[defn] commence une fonction de plusieurs lignes, qui finit à `end`. Elle donne la valeur de sa dernière ligne. La forme
courte est la même chose sur une ligne : `double(x) = x * 2` est `defn double(x) x * 2 end`.

```cesia
use std/math
defn describe(n)
  kind = if math.Mod(n, 2) == 0 "even" else "odd" end
  "$n is $kind"
end
describe(7) -->
```

### return

[return] donne une valeur tout de suite, et quitte la fonction. Il convient à une recherche qui peut s'arrêter tôt :

```cesia
use std/value
defn firstLong(words)
  for w in words
    if value.Len(w) > 4
      return w
    end
  end
  missing
end
firstLong(["a", "tree", "forest", "sea"]) -->
firstLong(["a"]) -->
```

### Une fonction qui s'appelle elle-même

Une fonction peut s'appeler elle-même, ce qui s'appelle la *récursion* :

```cesia
factorial(n) = if n <= 1 1 else n * factorial(n - 1) end
factorial(10) -->
```

Chaque appel attend celui qu'il a fait : les appels s'empilent donc, 10 000 au plus par défaut, la limite `depth` de
[Permissions](permissions.md#--limit), au-delà de laquelle le programme s'arrête à la ligne de l'appel. Un appel dont le
résultat est le résultat même de la fonction, sans rien qui reste à faire après lui, est en *tail position* (en position
finale) : `countDown(n - 1)` ci-dessous. Une fonction qui s'appelle elle-même à cet endroit tourne comme une boucle, dans
une seule frame (la place d'un appel en cours, avec ses variables), et n'a donc pas de limite de profondeur. Dans
`factorial`, le `n * ...` reste à faire après l'appel : cet appel n'est donc pas en tail position.

```cesia
countDown(n) = if n == 0 "done" else countDown(n - 1) end
countDown(1000000) -->
```

## Les noms dans une fonction

Un nom qui reçoit une valeur dans une fonction lui appartient : un nom qui s'écrit pareil au-dehors garde sa valeur. Une
fonction voit ses paramètres, ses propres noms et les noms de son fichier, ceux qui sont écrits autour d'elle : cela
s'appelle le [lexical scope](glossary.md#lexical-scope). Un `if` ou un `for` ne crée pas de scope (de portée) à lui.

```cesia
kind = "none"
describe(4) -->
kind -->
```

Une fonction qui ne fait que calculer à partir de ses arguments, comme `double`, est une
[pure function](glossary.md#pure-function) : les mêmes arguments donnent toujours la même valeur.

## Valeurs par défaut et arguments nommés

Un paramètre peut avoir une valeur par défaut, utilisée quand l'appel l'omet. Un appel peut aussi nommer ses arguments,
dans n'importe quel ordre : un appel qui en a beaucoup reste ainsi lisible.

```cesia
greet(name, greeting = "Hello") = "$greeting, $name!"
greet("Ana") -->
greet("Bo", greeting = "Hi") -->
greet(greeting = "Welcome", name = "Cyril") -->
```

## Les fonctions comme valeurs

Une fonction est une valeur : vous pouvez la nommer, la garder dans une liste, et la passer à une autre fonction.
`x -> x + 1` est une fonction sans nom, une [anonymous function](glossary.md#anonymous-function). Ses paramètres viennent
avant `->`, et sa valeur après :

```cesia
inc = x -> x + 1
inc(4) -->
add = (a, b) -> a + b
add(2, 3) -->
```

### Plusieurs lignes

Une fonction sans nom peut contenir plusieurs lignes : `defn`, ses paramètres entre parenthèses, et ses lignes jusqu'à
`end`. C'est la forme longue de `->`, comme `defn` est la forme longue de `=` :

```cesia
longInc = defn (x)
  y = x + 1
  y
end
longInc(4) --> inc(4)
```

### Closures

Une fonction créée dans une autre garde les noms qu'elle y voyait, avec les valeurs qu'ils avaient : c'est une
[closure](glossary.md#closure). Ici, `adder` crée des fonctions qui retiennent chacune leur `n` :

```cesia
adder(n) = x -> x + n
addTen = adder(10)
addTen(5) -->
adder(100)(1) -->
```

Une closure garde les *valeurs* de ces noms, telles qu'elles étaient quand elle a été créée, ce qui s'appelle la
*capture by value* (la capture par valeur). Un nom qui reçoit plus tard une autre valeur ne change pas la closure. En
JavaScript et en Python, une closure capture la *variable* elle-même, et voit ses valeurs suivantes : là-bas, la dernière
ligne ci-dessous donnerait 2.

```cesia
count = 1
show = () -> count
count = 2
show() --> 1
```

## Map, Filter et Reduce

Ces trois fonctions prennent une fonction en premier, et la liste en dernier. [list.Map] applique la fonction à chaque
élément, [list.Filter] garde les éléments pour lesquels elle donne true, et [list.Reduce] replie la liste en une seule
valeur, à partir d'une valeur de départ :

```cesia
use std/list
numbers = [1, 2, 3, 4, 5]
list.Map(double, numbers) -->
list.Filter(x -> x > 2, numbers) -->
list.Reduce((total, x) -> total + x, 0, numbers) -->
```

### D'autres encore

Beaucoup d'autres marchent de la même façon : [list.SortBy], [list.Count], [list.FindFirst], [list.Group],
[list.TakeWhile]. Chacune a sa page dans la référence.

```cesia
list.Count(x -> x > 2, numbers) -->
list.FindFirst(x -> x > 2, numbers) -->
```

### Des fonctions de fonctions

[std/fn] fabrique des fonctions à partir de fonctions. [fn.Compose] les enchaîne, la dernière d'abord ; [fn.Complement]
donne le contraire d'un test ; [fn.Juxt] donne les résultats de plusieurs fonctions sur une même valeur ;
[fn.Constantly] crée une fonction qui donne une seule valeur quel que soit son argument, et [fn.Identity] rend son
argument :

```cesia
use std/fn
fn.Compose(math.Inc, it * 2)(3) --> math.Inc(3 * 2)
list.Filter(fn.Complement(math.IsOdd), numbers) -->
fn.Juxt(list.Min, list.Max)(numbers) -->
list.Map(fn.Constantly(0), numbers) -->
fn.Identity(5) -->
```

## it

Pour une fonction courte d'un seul paramètre, [it] évite de l'écrire, comme le fait `it` en Kotlin : un argument qui
contient `it` est une fonction de `it`. `list.Map(it * 2, numbers)` est la forme courte de
`list.Map(x -> x * 2, numbers)` :

```cesia
list.Map(it * 2, numbers) -->
list.Map(it * 2, numbers) --> list.Map(x -> x * 2, numbers)
list.Filter(it > 3, numbers) --> list.Filter(x -> x > 3, numbers)
```

## then

[then] passe la valeur à sa gauche à l'appel à sa droite : c'est un *pipeline operator*, comme `|>` en F#, Elixir et
OCaml. La valeur prend la place d'un argument qui est `it` seul ; quand il n'y en a pas, elle devient le dernier
argument. Comme la liste vient en dernier dans ces fonctions, une étape ne nomme que ce qu'il faut faire : `it` seul
n'est donc nécessaire que là où la valeur ne va pas en dernier :

```cesia
numbers then list.Filter(math.IsOdd) then list.Map(it * 10) then list.Sum() -->
100 then math.Div(it, 7) --> math.Div(100, 7)
```

Une chaîne d'étapes se lit de gauche à droite, dans l'ordre où elles ont lieu. C'est la forme courte d'appels dans des
appels, qui se lisent de l'intérieur vers l'extérieur :

```cesia
numbers then list.Filter(math.IsOdd) then list.Map(it * 10) then list.Sum() --> list.Sum(list.Map(x -> x * 10, list.Filter(math.IsOdd, numbers)))
```

## Un petit programme

Les fonctions construisent un programme à partir de petites parties. Ici, quelques lignes de scores deviennent un
classement :

```cesia
use std/io
use std/text
raw = "ana 12\nbo 7\ncyril 15\ndee 9"
defn parse(line)
  parts = text.Split(" ", line)
  {Name: parts[1], Score: text.Number(parts[2])}
end
players = list.Map(parse, text.Lines(raw))
best = list.SortBy(p -> -p.Score, players)
for p in list.Take(3, best)
  io.Print(text.PadRight(6, " ", p.Name), p.Score)
end
```

Les accolades dans `parse` créent un dictionnaire avec les clés `Name` et `Score`, et `p.Score` lit une de ses clés : le
chapitre suivant en parle.

## La suite

Vous savez écrire des fonctions et les faire circuler. Le chapitre suivant, [Maps](maps.md), garde des valeurs sous des
noms : `{Name: "Ana", Age: 31}`.
