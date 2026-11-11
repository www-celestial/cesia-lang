# Maps

Dans ce chapitre, vous gardez des valeurs sous des noms : une personne avec un nom et un âge, un compte pour chaque mot
d'un texte. Une telle map (des valeurs rangées sous des clés), Cesia l'appelle un dictionnaire. Vous le lisez, vous y
ajoutez, vous en retirez, et vous le parcourez.

## Un dictionnaire

Un dictionnaire s'écrit entre accolades : chaque entrée est une clé, deux-points, et une valeur. Une clé qui est un
simple nom, `Name`, est le texte `"Name"` :

```cesia
person = {Name: "Ana", Age: 31}
person -->
{Name: "Ana"} --> {"Name": "Ana"}
```

Une clé est un texte ou un nombre : une liste, un dictionnaire ou `missing` ne peuvent pas en être une. Une clé peut être
un texte avec n'importe quels caractères :

```cesia
{"first name": "Ana", 2: "two"} -->
```

`1` et `1.0` sont une seule clé, comme ils sont un seul nombre : `{1: "one"}[1.0]` vaut `"one"`.

## Lire

Un point lit la valeur d'une clé. C'est la forme courte de la clé entre crochets, qui marche aussi avec une clé gardée
dans une variable :

```cesia
person.Name -->
person["Name"] --> person.Name
key = "Age"
person[key] -->
```

### Une clé qui n'y est pas

Une clé qui n'y est pas arrête le programme : une faute de frappe se voit tout de suite.

```cesia fails
person.City
```

Quand une clé peut manquer, [dict.Get] donne `missing` à la place, [dict.GetOr] donne une valeur par défaut, et
[dict.Has] pose la question. `in` la pose aussi : `"Age" in person` est la forme courte de `dict.Has("Age", person)`.

```cesia
use std/dict
dict.Get("City", person) -->
dict.GetOr("City", "unknown", person) -->
dict.Has("Age", person) -->
"Age" in person --> dict.Has("Age", person)
```

## Changer

Un point ou des crochets à gauche de `=` donnent une valeur à une clé. Comme pour une liste, seul ce nom voit le
changement : un dictionnaire est une valeur, avec la [value semantics](glossary.md#value-semantics) (donner un second
nom à une valeur agit comme une copie), et un autre nom qui le gardait garde ce qu'il avait.

```cesia
other = person
other.City = "Lyon"
other -->
person -->
```

### Put, Drop et Merge

Donner une valeur à une clé est la forme courte de [dict.Put], qui donne un nouveau dictionnaire. Le nouveau partage le
reste de sa mémoire avec l'ancien, qui reste tel qu'il était : c'est une
[persistent data structure](glossary.md#persistent-data-structure). [dict.Drop] en donne un sans une clé, et
[dict.Merge] en joint deux : pour une clé présente dans les deux, le second l'emporte.

```cesia
dict.Put("City", "Lyon", person) --> other
dict.Drop("Age", person) -->
dict.Merge(person, {Age: 32, Job: "baker"}) -->
```

## Ordre

Un dictionnaire garde ses clés dans l'ordre où elles sont arrivées. Donner une valeur à une clé déjà présente lui garde
sa place. Deux dictionnaires sont égaux quand ils contiennent les mêmes entrées, quel que soit leur ordre :

```cesia
{A: 1, B: 2} == {B: 2, A: 1} -->
dict.Keys(dict.Put("A", 10, {A: 1, B: 2})) -->
```

## Parcourir

[dict.Keys] donne les clés dans leur ordre, [dict.Values] les valeurs, et [dict.Pairs] les deux : chaque paire est une
struct (une valeur dont les champs sont déclarés une fois) avec un champ `Key` et un champ `Value`. Un `for` parcourt
l'une de ces listes : un dictionnaire lui-même n'est pas une liste.

```cesia
use std/io
for k in dict.Keys(person)
  io.Print(k, "is", person[k])
end
```

```cesia
for p in dict.Pairs(person)
  io.Print(p.Key, "->", p.Value)
end
```

### Toutes les valeurs d'un coup

[dict.MapValues] change chaque valeur avec une fonction, et garde les clés :

```cesia
use std/value
dict.MapValues(v -> value.Text(v), person) -->
```

## Compter

Le dictionnaire est l'outil pour compter. Ici, chaque mot d'un texte reçoit son compte. Un mot vu pour la première fois
part de 0 :

```cesia
use std/text
counts = {}
for word in text.Split(" ", "the cat and the dog and the bird")
  counts[word] = dict.GetOr(word, 0, counts) + 1
end
counts -->
```

### Fréquences

C'est assez courant pour avoir sa propre fonction, [list.Frequencies] :

```cesia
use std/list
list.Frequencies(text.Split(" ", "the cat and the dog and the bird")) --> counts
```

### Combiner des dictionnaires

[dict.Update] applique une fonction à la valeur d'une clé, [dict.MergeWith] joint deux dictionnaires et combine avec une
fonction les valeurs d'une clé présente dans les deux, [dict.SelectKeys] garde les clés d'une liste, et [dict.Invert]
échange les clés et les valeurs :

```cesia
use std/math
dict.Update("Age", math.Inc, person) -->
dict.MergeWith(math.Add, {bread: 2, cake: 1}, {bread: 3}) -->
dict.SelectKeys(["Name"], person) -->
dict.Invert({a: "x", b: "y"}) -->
```

## Des dictionnaires imbriqués

Une valeur peut être elle-même un dictionnaire. [dict.GetIn] lit au bout d'un chemin de clés, et [dict.PutIn] y écrit,
en créant les dictionnaires en chemin :

```cesia
config = {Server: {Port: 8080, Host: "127.0.0.1"}}
config.Server.Port -->
dict.GetIn(["Server", "Port"], config) --> config.Server.Port
dict.PutIn(["Log", "Level"], "info", config) -->
dict.UpdateIn(["Server", "Port"], it + 1, config).Server.Port -->
```

## À partir de listes

[dict.Dict] construit un dictionnaire à partir d'une liste d'entrées, chacune avec `Key` et `Value`, la forme que donne
[dict.Pairs]. [dict.Zipmap] en construit un à partir d'une liste de clés et d'une liste de valeurs :

```cesia
dict.Dict([{Key: "a", Value: 1}, {Key: "b", Value: 2}]) -->
dict.Zipmap(["a", "b"], [1, 2]) -->
```

## Comment un dictionnaire est rangé en mémoire, et ce qu'il coûte

Jusqu'à 32 clés, un dictionnaire est un seul bloc : ses clés dans leur ordre, à côté de leurs hashes (le nombre calculé à
partir de chaque clé pour la retrouver vite), et ses valeurs ; tant qu'elles sont toutes des floats (des nombres à
virgule), comme dans `{X: 1.0, Y: 2.5}`, les valeurs sont gardées comme de simples doubles, sans rien autour, une
[storage strategy](glossary.md#storage-strategy) que le programme ne voit jamais : 11 mots machine pour quatre floats au
lieu de 25, et du code machine qui les lit et les écrit sur place. Au-delà de 32, tant qu'un seul nom le garde, c'est une
[hash table](glossary.md#hash-table) dans l'ordre d'insertion, comme le `dict` de Python : une lecture ou une écriture
prend en moyenne un temps constant, et la table est changée sur place. Dès qu'il est partagé puis écrit, comme par
[dict.Put], il devient, une fois pour toutes, un [hash array mapped trie](glossary.md#hash-array-mapped-trie) de la
sorte appelée [CHAMP](glossary.md#champ) : un arbre dont les niveaux se choisissent par 5 bits du hash de chaque clé à
la fois, chaque nœud gardant les clés qui sont seules sur leurs 5 bits ; une lecture ou une écriture prend donc environ
$\log_{32} n$ pas, 3 pour 30 000 clés, et une écriture ne copie que les quelques petits nœuds du chemin vers sa clé.
C'est ainsi que [dict.Put] peut donner un nouveau dictionnaire et garder l'ancien, pour un petit coût ; le changement de
forme coûte environ 0,25 s pour un million de clés, une seule fois. Le hash prend une seed (une valeur de départ) tirée
au hasard à chaque exécution : personne ne peut donc envoyer à un serveur des clés choisies pour entrer en collision.
[Comment Cesia fonctionne](internals.md#maps-une-hash-table-puis-un-hash-trie) montre les détails.

Un dictionnaire que rien d'autre ne garde est changé sur place : la boucle de [Compter](#compter) ne copie donc rien.
500 000 clés de texte écrites puis lues prennent 0,28 s, contre 0,41 s pour le `dict` de Python, 0,27 s pour la map de
Go et 0,22 s pour le `HashMap` de Java, comme le mesure [Vitesse](speed.md#le-calcul).

## Pour aller plus loin

- Le `dict` compact de Python 3.6, d'après une conception de Raymond Hettinger : la hash table d'un dictionnaire qu'un
  seul nom garde.
- Phil Bagwell, *Ideal Hash Trees*, 2001 : le hash array mapped trie ; Michael J. Steindorfer et Jurgen J. Vinju,
  *Optimizing Hash-Array Mapped Tries for Fast and Lean Immutable JVM Collections*, 2015 : CHAMP, ses nœuds.
- Rich Hickey, *A History of Clojure*, 2020 : les maps persistantes comme dictionnaire de tous les jours d'un langage.
- James R. Driscoll et d'autres, *Making data structures persistent*, 1989 ; Chris Okasaki, *Purely Functional Data
  Structures*, 1998.
- Scott A. Crosby et Dan S. Wallach, *Denial of Service via Algorithmic Complexity Attacks*, 2003 : pourquoi le hash
  prend une seed.

Chacun avec son lien dans [Références](references.md#values-and-maps).

## La suite

Vous savez garder des valeurs sous des noms. Un dictionnaire prend n'importe quelle clé, ce qui convient aux données qui
viennent de l'extérieur. Pour des données dont vous connaissez les champs à l'avance, le chapitre suivant,
[Structs](structs.md), les nomme une fois et les vérifie.
