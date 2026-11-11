# Valeurs et noms

Dans ce chapitre, vous découvrez les valeurs avec lesquelles un programme travaille : les nombres, les textes, true et
false, et `missing`. Vous leur donnez des noms, vous les changez, et vous voyez quels noms les autres fichiers peuvent
utiliser.

Dans les exemples de ce livre, une ligne qui finit par `-->` montre la valeur de ce qui est à sa gauche, telle que Cesia
l'affiche. Une ligne qui a une valeur après son `-->` la vérifie : la construction du livre s'arrêterait si `2 + 2` ne
valait pas `4`.

```cesia
2 + 2 --> 4
"Cesia" -->
```

## Nombres

Un nombre est un entier, comme `42`, ou un float (un nombre à virgule), écrit avec un point : `1.5`. Les opérateurs
habituels marchent sur les deux, et `^` est la puissance :

```cesia
2 + 3 * 4 -->
(2 + 3) * 4 -->
2 ^ 10 -->
```

### Les opérateurs comme fonctions

`+`, `-` et `*` sont aussi des fonctions, pour les fois où vous en passez une à une autre fonction : `2 + 3` est
[math.Add]`(2, 3)`, et [math.Sub] et [math.Mul] sont les deux autres.

```cesia
use std/math
math.Add(2, 3) --> 2 + 3
math.Sub(5, 2) --> 5 - 2
math.Mul(4, 5) --> 4 * 5
```

### Division

`/` donne toujours un float, même quand la division tombe juste. Pour la partie entière d'une division, [math.Div]
arrondit vers le bas, et [math.Mod] donne le reste :

```cesia
7 / 2 -->
10 / 2 -->
math.Div(7, 2) -->
math.Mod(7, 2) -->
```

### Entiers et floats

Un entier et un float se mélangent : le résultat est un float. C'est une [type coercion](glossary.md#type-coercion), une
valeur que le langage change lui-même en une valeur d'un autre type. Et ils se comparent par leur valeur :

```cesia
1 + 0.5 -->
1 == 1.0 -->
```

Un entier a 63 bits : de -4 611 686 018 427 387 904 à 4 611 686 018 427 387 903. Un résultat au-delà est une erreur, pas
un nombre faux, et son message dit d'utiliser un float. Un float est un nombre de 64 bits en *binary floating-point*
(virgule flottante en base 2), le `double` du C, tel que le définit la norme IEEE 754 : environ 15 à 17 chiffres
décimaux significatifs, jusqu'à environ $1{,}8 \times 10^{308}$. Il garde une fraction en base 2 : une fraction décimale
comme `0.1` est donc proche, pas exacte. [math.Round] et [math.Floor] redonnent des nombres entiers :

```cesia
0.1 + 0.2 -->
math.Round(2.5) -->
math.Floor(2.7) -->
```

Une division de floats par zéro suit aussi IEEE 754 : elle donne un infini, ou `nan`, *not a number* (pas un nombre),
pour `0.0 / 0.0`. `nan` n'est égal à rien, pas même à lui-même :

```cesia
1 / 0 -->
0.0 / 0.0 -->
math.Nan == math.Nan --> false
```

[math.Div] et [math.Mod] travaillent sur des entiers, et leur division par zéro est une erreur, comme le montre le
chapitre [Erreurs](errors.md).

## Textes

Un texte s'écrit entre guillemets doubles. Un `$` y met une valeur, ce qui s'appelle la
[string interpolation](glossary.md#string-interpolation) : un nom après le `$`, ou n'importe quelle expression dans
`$( )`.

```cesia
name = "Ana"
"Hello, $name" -->
"Two and two make $(2 + 2)" -->
```

Un `$` est la forme courte de [text.Str], qui joint les textes de ses arguments. Une telle forme courte s'appelle du
[syntax sugar](glossary.md#syntax-sugar), et ce livre montre chacune à côté de sa forme ordinaire :

```cesia
use std/text
"Hello, $name" --> text.Str("Hello, ", name)
```

Un texte ne s'additionne jamais à un nombre avec `+` : écrivez le nombre dans le texte, ou joignez les morceaux avec
[text.Str] :

```cesia
text.Str("Total: ", 3) -->
```

### Les escapes

Un `\` commence un escape, l'écriture d'un caractère qu'un texte ne peut pas contenir tel quel : `\"` est un guillemet,
`\n` une fin de ligne, `\t` une tabulation, et `\\` le `\` lui-même. Un `$` s'écrit deux fois :

```cesia
use std/io
use std/value
io.Print("She said \"yes\"")
io.Print("one\ttwo\nthree")
io.Print("It costs 5 $$")
value.Len("\"") -->
```

Le chapitre [Textes](texts.md) montre comment les couper, y chercher et les joindre.

## Vrai et faux

`true` et `false` viennent des comparaisons, et se combinent avec `and`, `or` et `not` :

```cesia
3 > 2 -->
3 != 3 -->
1 < 2 and not (2 < 1) -->
"apple" < "banana" -->
```

Les textes se comparent caractère par caractère, par leur numéro dans Unicode, le *code point* : toute majuscule vient
avant toute minuscule, et `é`, 233, vient après `z`, 122. C'est aussi l'ordre de [list.Sort].

```cesia
"Zoe" < "adam" -->
"été" > "zoo" -->
```

`and` et `or` s'arrêtent dès que la réponse est connue, ce qui s'appelle la
[short-circuit evaluation](glossary.md#short-circuit-evaluation) : dans `false and f()`, `f` n'est jamais appelée.

## Missing

`missing` veut dire qu'il n'y a pas de valeur, comme [null](glossary.md#null) dans d'autres langages : une clé qui n'est
pas dans un dictionnaire, un texte qui n'est pas un nombre. [value.IsMissing] pose la question, et [value.IsSome] pose
la question inverse :

```cesia
text.Number("12") -->
text.Number("twelve") -->
value.IsMissing(text.Number("twelve")) -->
```

### Missing dans les calculs

`missing` traverse les calculs : une somme qui a une partie manquante est manquante. Un total sur des données qui ont un
trou montre le trou, au lieu d'un nombre faux :

```cesia
1 + missing -->
missing > 1 -->
```

Une comparaison avec `missing` est `missing` elle aussi, et `if` ne prend que `true` ou `false` : un test sur un trou
arrête donc le programme à cette ligne, au lieu de choisir un côté au hasard. [value.IsMissing] est la façon de poser la
question.

### Demander ce qu'est une valeur

[value.IsInt], [value.IsFloat], [value.IsNumber], [value.IsBool], [value.IsText], [value.IsArray], [value.IsDict],
[value.IsStruct], [value.IsFunction] et [value.IsMissing] demandent de quelle sorte est une valeur, et [value.IsEmpty]
si un array (une liste de valeurs rangées par position), un texte ou un dictionnaire n'a aucun élément :

```cesia
value.IsInt(3) -->
value.IsNumber(2.5) -->
value.IsText("3") -->
value.IsArray([1]) -->
value.IsDict({A: 1}) -->
value.IsBool(missing) -->
value.IsFunction(value.Len) -->
value.IsEmpty("") -->
```

## Noms

`=` donne un nom à une valeur : c'est un [binding](glossary.md#binding), le lien entre un nom et une valeur. Le même nom
peut prendre plus tard une autre valeur, de n'importe quelle sorte. `+=`, `-=`, `*=` et `/=` changent un nombre à partir
de sa propre valeur :

```cesia
count = 1
count += 2
count *= 10
count -->
```

### Changer la valeur d'un nom

`count += 2` est la forme courte de `count = count + 2` :

```cesia
total = 10
total = total + 2
total --> 12
```

### Une valeur ne change jamais

Une valeur ne change jamais dans votre dos : Cesia a la [value semantics](glossary.md#value-semantics), où donner un
second nom à une valeur agit comme une copie. Quand deux noms gardent la même liste et que vous en changez un, l'autre
garde ce qu'il avait :

```cesia
a = [1, 2, 3]
b = a
b[1] = 100
a -->
b -->
```

Une fonction qui reçoit votre liste ne peut donc pas la changer : elle en rend une nouvelle. Le chapitre
[Listes et arrays](lists.md) y revient.

## Public et privé

La première lettre d'un nom dit qui peut le voir, comme en Go :

- Une majuscule le rend public : `Print`, `LineCount`, `Area`. Les autres fichiers peuvent l'utiliser.
- Une minuscule le rend privé à son package (le dossier de fichiers dont il fait partie) : `count`, `chunk`. Les noms
  locaux, les paramètres et les fichiers s'écrivent en minuscules.

Un nom joint ses mots par des majuscules : `byteLength` ou `ByteLength`, jamais `byte_length`. Le `_` seul veut dire
« n'importe quelle valeur » dans un pattern (une forme à laquelle on compare une valeur), comme le montre le chapitre
[Choix et boucles](choices.md).

## Commentaires

`(*` et `*)` entourent un commentaire, sur une ligne ou plusieurs, et un commentaire peut en contenir un autre : un
morceau de code qui contient des commentaires peut donc être mis de côté tout entier. `--` n'est pas un commentaire en
Cesia : c'est une erreur, qui dit d'écrire `(* *)`. `(**` ouvre un commentaire de documentation : il décrit le nom qu'il
suit ou celui qui est en dessous, et `cesia doc` l'affiche. La référence de ce site est faite de tels commentaires.

```cesia
(* A comment for the reader of the code. *)
double(x) = x * 2   (** Twice x. *)
double(21) -->
```

## La suite

Vous connaissez les valeurs et la façon dont les noms les gardent. Le chapitre suivant, [Textes](texts.md), défait les
textes et les remet ensemble.
