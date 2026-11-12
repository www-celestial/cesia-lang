# Structs

Dans ce chapitre, vous déclarez une fois la forme de vos données : un point avec `X` et `Y`, un utilisateur avec un nom
et un âge. Une struct nomme ses champs, donne à certains une valeur par défaut, et repère un champ mal écrit. Puis vous
lui donnez des méthodes.

## Déclarer une struct

[struct] nomme une forme et ses champs, ce que d'autres langages appellent un [record](glossary.md#struct). Un champ peut
avoir une valeur par défaut, utilisée quand la valeur l'omet :

```cesia
struct Point { X, Y = 0 }
Point(1, 2) -->
Point(5) -->
Point(Y = 4, X = 3) -->
```

### La forme en bloc

Pour plus de champs, ou un commentaire sur chacun, la forme en bloc a un champ par ligne, jusqu'à `end`. Les deux formes
créent les mêmes valeurs :

```cesia
struct User
  (** Someone who signed up. *)
  Name
  Age = 0   (** in years *)
end
User("Ana", 31) -->
```

## Champs

Un point lit un champ. Donner une valeur à un champ ne change que la valeur de ce nom, comme pour toute valeur de Cesia :

```cesia
p = Point(1, 2)
p.X -->
q = p
q.X = 10
p -->
q -->
```

### Un mauvais champ

Un champ que la struct n'a pas est une erreur, comme un appel avec trop de valeurs. Un dictionnaire prendrait n'importe
quelle clé sans rien dire ; une struct dit ce qui ne va pas.

```cesia fails
p.Z
```

```cesia fails
Point(1, 2, 3)
```

## Méthodes

Une méthode est une fonction attachée à une struct. Une méthode d'instance nomme son receiver, la valeur sur laquelle on
l'appelle, entre parenthèses avant le nom : `(r Rect) Area()`, comme en Go
([method and receiver](glossary.md#method-and-receiver)). Une méthode statique a le nom de la struct avant le sien,
`Rect.Square`, et crée des valeurs. Un point appelle les deux :

```cesia
struct Rect { Width, Height }

defn Rect.Square(side)
  Rect(side, side)
end

defn (r Rect) Area()
  r.Width * r.Height
end

(r Rect) Scaled(k) = Rect(r.Width * k, r.Height * k)

r = Rect.Square(3)
r.Area() -->
r.Scaled(2).Area() -->
```

### La forme courte

Une méthode d'une ligne a la forme courte d'une fonction : `(r Rect) Scaled(k) = Rect(r.Width * k, r.Height * k)` est
`defn (r Rect) Scaled(k) Rect(r.Width * k, r.Height * k) end`. Une méthode donne une nouvelle valeur : `Scaled` laisse
`r` tel qu'il était.

```cesia
r.Scaled(2) --> Rect(6, 6)
r -->
```

### Les méthodes comme valeurs

Une méthode statique est une fonction comme une autre : on peut donc la passer à une autre fonction. Une méthode
d'instance s'appelle sur une valeur ; pour en passer une à [list.Map], écrivez l'appel avec `it` :

```cesia
use std/list
list.Map(Rect.Square, [1, 2]) -->
list.Map(it.Area(), [Rect(1, 2), Rect(3, 4)]) -->
```

Une méthode dont le nom commence par une minuscule est privée à son package (le dossier de fichiers dont elle fait
partie), comme tout nom.

## Les structs dans les patterns

Une struct est un pattern (une forme à laquelle on compare une valeur) de [match] : `Point(x, y)` défait un point, dans
l'ordre de ses champs. Un dictionnaire ne va pas au pattern d'une struct, même avec les mêmes clés :

```cesia
describe(v) = match v
  Point(x, y) -> "a point at $x, $y"
  else -> "not a point"
end
describe(Point(3, 4)) -->
describe({X: 3, Y: 4}) -->
```

## D'un dictionnaire, et retour

Les données venues de l'extérieur, comme du JSON, arrivent sous forme de dictionnaires. Chaque struct a `From`, qui en
construit une à partir d'un dictionnaire et la vérifie : un `Ok` de la valeur, ou un `Err` qui nomme la clé en trop ou
le champ manquant.

```cesia
User.From({Name: "Bo", Age: 20}) -->
User.From({Name: "Bo", Agee: 20}) -->
User.From({Age: 3}) -->
```

### Retour à un dictionnaire

[dict.Fields] fait le chemin inverse, d'une struct vers un dictionnaire :

```cesia
use std/dict
dict.Fields(User("Ana", 31)) -->
```

Le chapitre [Erreurs](errors.md) montre comment utiliser le `Ok` et le `Err` que donne `From`.

## Struct ou dictionnaire

| | Struct | Dictionnaire |
|---|---|---|
| Clés | déclarées une fois | n'importe lesquelles, à tout moment |
| Un nom faux | une erreur tout de suite | une erreur ; [dict.Get] donne `missing` |
| Méthodes | oui | non |
| Pour | les données que vous concevez | les données qui viennent de l'extérieur |

Les deux se lisent de la même façon. Une struct garde sa *forme* (shape), la liste des noms de ses champs, partagée par
toutes les structs de sa sorte, et un array de ses valeurs ; un dictionnaire de 32 clés au plus écrit dans le code garde
un array de clés partagé par tous les dictionnaires créés à cet endroit. Une lecture de champ garde, à sa ligne, la
dernière forme qu'elle a rencontrée et la place du champ dans celle-ci : dans une boucle, elle coûte donc une
comparaison et un chargement depuis la mémoire. Voyez [Comment Cesia fonctionne](internals.md#des-caches-à-chaque-site). Une
struct est aussi vérifiée : ses champs sont connus, donc une faute de frappe est une erreur, et un type écrit sur un
champ est vérifié à chaque écriture.

Une struct est un type *nominal* : une valeur est un `Point` parce que `Point` l'a créée, pas parce qu'elle a un `X` et
un `Y`. Un dictionnaire qui a les mêmes clés ne va donc pas au pattern `Point(x, y)`. Les interfaces, dans
[Types](types.md#interfaces), font l'inverse : elles sont *structurelles*, et tout ce qui a leurs méthodes les
satisfait.

## La suite

Vos données ont une forme. Le chapitre suivant, [Erreurs](errors.md), traite de ce qui va mal : un fichier qui n'est pas
là, un nombre qui ne se lit pas, un utilisateur que `From` refuse.
