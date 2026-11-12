# Types

Dans ce chapitre, vous écrivez la sorte de valeur que garde un nom : une masse qui est un `Float`, un nom qui est un
`Text` ou `missing`, un paramètre qui doit être une forme. Les types sont un plus en Cesia, ce qui s'appelle
l'[optional typing](glossary.md#optional-typing). Vous pouvez les omettre partout, et le code sans eux tourne tout aussi
vite. Là où vous en écrivez un, Cesia le vérifie chaque fois qu'une valeur arrive, et le type dit au lecteur ce qui va
là.

## Un type après un nom

Un type vient après le nom d'un champ ou d'un paramètre. Le type du résultat d'une fonction vient après ses paramètres,
comme en Go :

```cesia
struct Car
  Mass Float
  Speed Float = 0.0   (** metres per second *)
end

Half(x Float) Float = x / 2

defn Describe(c Car, unit Text = "kg") Text
  "$(c.Mass) $unit"
end

Describe(Car(1200.5)) -->
Half(3.0) -->
```

Les types sont `Int`, `Float`, `Number` pour un `Int` ou un `Float`, `Bool`, `Text`, `Array`, `Dict`, `Function`, vos
structs, et les interfaces plus bas.

## Vérifié quand une valeur arrive

Cesia vérifie un type écrit *pendant que le programme tourne*, à l'endroit où une valeur arrive, et `cesia check` ajoute
ce qu'il peut dire avant : une valeur qui ne peut sûrement pas convenir. Ce n'est aucune des deux façons courantes. Les
type hints de Python (des types écrits à titre d'indication) ne sont jamais vérifiés quand le programme tourne, seulement
par un outil à part comme mypy, et TypeScript efface ses types avant que le code tourne ; Java, Go et OCaml vérifient
chaque type avant que le programme tourne, le *static typing*, et refusent un programme dont ils ne peuvent pas prouver
les types. Les types de Cesia sont plus proches des *contracts* de Racket : une promesse vérifiée à la frontière où elle
est écrite.

Un champ est vérifié quand la struct est construite et chaque fois que le champ est écrit. Un paramètre est vérifié à
chaque appel, et un résultat chaque fois que la fonction en donne un. Une valeur du mauvais type est un bug : le
programme s'arrête et dit quel nom voulait quoi.

```cesia fails
Half("ten")
```

```cesia fails
c = Car(1000.0)
c.Mass = "heavy"
```

```cesia fails
defn label(n Int) Text
  n * 2
end
label(4)
```

### Un type qui ne nomme rien

Un type qui ne nomme rien est repéré avant que le programme démarre :

```cesia fails
weigh(c Cr) = c.Mass
```

## Un Int devient un Float

Un `Int` là où un `Float` est attendu devient un `Float`, une [type coercion](glossary.md#type-coercion) (une valeur que
le langage change lui-même en une valeur d'un autre type) : `Car(1500)` n'a donc pas besoin de `.0`. `Number` garde l'un
comme l'autre :

```cesia
Car(1500).Mass -->
Half(3) -->
Twice(x Number) Number = x * 2
Twice(3) -->
Twice(1.5) -->
```

## Peut-être missing

Un `?` après un type accepte aussi `missing`, le [null](glossary.md#null) de Cesia (la valeur qui veut dire « pas de
valeur »). Un champ d'un tel type, sans valeur par défaut, est `missing` quand la valeur l'omet :

```cesia
struct Person
  Name Text
  Nickname Text?
end
Person("Ana") -->
Person("Bo", "Bobby").Nickname -->
```

### Un résultat qui peut être missing

Une fonction qui peut finir sans valeur donne alors `missing` : le type de son résultat demande donc le `?` :

```cesia
use std/value
defn position(x, xs Array) Int?
  for k in 1..value.Len(xs)
    if xs[k] == x
      return k
    end
  end
end
position("b", ["a", "b"]) -->
position("z", ["a", "b"]) -->
```

## Un résultat qui peut être un Err : Int!

Comme `?` dit qu'un résultat peut être `missing`, `!` après un type de résultat dit qu'il peut être un `Err`, celui du
chapitre [Erreurs](errors.md) : `Int!` se lit « un `Int`, ou une erreur ». Une telle fonction donne `result.Ok` d'un
`Int`, ou un `result.Err`, comme le fait [sys.Read], et la vérification à sa sortie regarde dans le `Ok` :

```cesia
use std/result
defn half(x) Float!
  if x < 0
    return result.Err("negative")
  end
  result.Ok(x / 2)
end
half(3) -->
half(-1) -->
```

Sans le `!`, le même `Err` arrête le programme, puisqu'un `Float` était promis :

```cesia fails
defn third(x) Float
  if x < 0
    return result.Err("negative")
  end
  x / 3
end
third(-1)
```

## Les données venues de l'extérieur

`From`, du chapitre [Structs](structs.md), vérifie aussi les types. L'`Err` nomme le champ et ce qu'il a trouvé : un
corps JSON avec un champ faux est donc refusé avant que votre code le lise :

```cesia
Car.From({Mass: 900}) -->
Car.From({Mass: "heavy"}) -->
```

## Interfaces

Une interface liste des méthodes, sans code. Une valeur la satisfait quand elle a chacune de ces méthodes : rien ne le
déclare, comme en Go. C'est le [structural typing](glossary.md#structural-typing). Une interface est un type comme les
autres :

```cesia
interface Shape
  (** Something with an area and a perimeter. *)
  Area()
  Perimeter()
end

struct Rect { Width Number, Height Number }
(r Rect) Area() = r.Width * r.Height
(r Rect) Perimeter() = 2 * (r.Width + r.Height)

Measured(s Shape) = s.Area() + s.Perimeter()
Measured(Rect(2, 3)) -->
```

### Un dictionnaire la satisfait aussi

Un dictionnaire dont les clés gardent des fonctions satisfait aussi une interface, ce qui convient à une valeur de test
vite écrite :

```cesia
Measured({Area: () -> 2, Perimeter: () -> 6}) -->
```

### Une méthode qui manque

Une valeur à qui il manque une méthode arrête le programme, et le message nomme la méthode :

```cesia fails
struct Circle { R Float }
(c Circle) Area() = 3.14 * c.R * c.R
Measured(Circle(1.0))
```

### Une méthode pour chaque Shape

Une méthode écrite pour une interface appartient à chaque valeur qui la satisfait :

```cesia
(s Shape) Describe() = "area $(s.Area()), perimeter $(s.Perimeter())"
Rect(1, 2).Describe() -->
```

## Quand écrire des types

- Sur les champs d'une struct qui garde des données que vous conservez : ils disent ce qu'est chaque champ, et `From`
  vérifie d'après eux les données reçues.
- Sur les paramètres d'une fonction publique : sa page dans la référence les montre, et un mauvais appel s'arrête à
  l'appel.
- Pas sur chaque nom local : Cesia n'en a pas besoin, et un type ne rend jamais le code plus rapide.

## Vérifier sans exécuter : cesia check

`cesia check` lit le code et dit ce qui ne va pas, sans en exécuter la moindre partie : des noms qui n'existent pas, des
appels avec de mauvais arguments, des valeurs qui ne peuvent pas convenir à un type, et des résultats laissés sans
traitement. Sans chemin, il lit les dossiers de sources de `cesia.toml` ; il peut aussi prendre des fichiers et des
dossiers. Les [commandes](commands.md#cesia-check) listent ses options. Un éditeur lance
`cesia check --json --stdin file.ce` sur un buffer pas encore enregistré (le texte que l'éditeur garde en mémoire), et
montre chaque erreur sur sa ligne.

```bash
cesia check
```

```text
src/main.ce:7:22: warning: sys.Read gives a result, used here as a plain value.
  7 |   io.Print(value.Len(sys.Read(path)))
    |                      ^^^^^^^^
  An Err would pass for a value: add ?, match it, or Unwrap it.
check: 0 errors, 1 warning, in 3 files.
```

Une erreur est ce qui arrêterait sûrement le programme ; un warning (un avertissement) est ce qui peut être une faute, et
ne change pas l'exit code (le nombre que la commande rend en finissant). Les warnings portent sur les résultats :

- un résultat utilisé comme une simple valeur, comme ci-dessus : `value.Len` d'un `Err` compte ses champs, et un fichier
  qui manque a donc une longueur de 1. `?`, `match`, [result.Unwrap] ou le fait de le garder dans une variable ne donnent
  pas de warning, pas plus que [io.Print], qui l'affiche, et [fiber.Send], qui le fait suivre ;
- un résultat jeté : `sys.Write(path, text)` seul perd son `Err`. `_ = sys.Write(path, text)` le jette exprès ;
- une fonction typée qui peut donner un `Err` sans `!` : un `defn size(path) Int` qui contient un `?` reçoit le conseil
  d'écrire `Int!`.

## La suite

Votre code dit ce qu'il attend. Le chapitre suivant, [Packages](packages.md), découpe un programme en dossiers, utilise
du code d'autres projets, et décrit un projet dans `cesia.toml`.
