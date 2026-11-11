# Textes

Dans ce chapitre, vous défaites des textes, vous y cherchez, et vous en construisez de nouveaux : le travail de tous les
jours d'un script (un petit programme qu'on lance tel quel) qui lit des fichiers et écrit des rapports.

Un texte est une valeur comme un nombre, [immutable](glossary.md#immutability) : aucune fonction ne le change, chacune
donne un nouveau texte. Dans chaque fonction de ce chapitre, le texte sur lequel vous travaillez vient en dernier. La
partie qui dit quoi faire vient en premier.

## Longueur et casse

[value.Len] compte les caractères d'un texte, accents compris. [text.Upper] et [text.Lower] changent la casse
(majuscules ou minuscules), et [text.Trim] enlève les espaces et les fins de ligne aux deux bouts :

```cesia
use std/text
use std/value
value.Len("café") -->
text.Upper("hello") -->
text.Lower("SHOUT") -->
text.Trim("   padded   ") -->
```

## Couper

[text.Split] coupe un texte à chaque séparateur, et donne la liste des morceaux. Deux séparateurs à la suite laissent un
morceau vide entre eux :

```cesia
text.Split(",", "red,green,blue") -->
text.Split(",", "a,,b") -->
```

### Lignes

[text.Lines] donne les lignes d'un texte, sans leurs fins de ligne. Une fin de ligne tout à la fin n'ouvre pas de ligne
vide, et une fin de ligne de Windows compte pour une seule :

```cesia
text.Lines("first\nsecond\n") -->
text.Lines("one\r\ntwo") -->
```

### Caractères

[text.Slice] prend les caractères d'une position à une autre, toutes deux comprises, en comptant à partir de 1.
[text.Chars] donne chaque caractère sous forme de texte :

```cesia
text.Slice(1, 4, "Cesia is small") -->
text.Chars("abc") -->
```

## Joindre

[text.Join] met un séparateur entre les textes d'une liste. [text.Repeat] écrit un texte plusieurs fois. Et [text.Str]
joint des valeurs de n'importe quelle sorte, ce qui est commode pour les nombres :

```cesia
text.Join(", ", ["red", "green", "blue"]) -->
text.Repeat(3, "ab") -->
text.Str("page ", 3, " of ", 10) -->
```

### Avec $

La plupart du temps, c'est un texte avec `$` qui se lit le mieux :

```cesia
done = 3
total = 10
"page $done of $total" -->
```

### Le padding

[text.PadLeft] et [text.PadRight] font le padding d'un texte : elles le remplissent jusqu'à une largeur, pour des colonnes
bien alignées :

```cesia
text.PadLeft(5, "0", "42") -->
text.PadRight(8, ".", "name") -->
```

## Chercher

[text.Contains], [text.StartsWith] et [text.EndsWith] répondent oui ou non. [text.Find] donne la position d'une partie,
à partir de 1, ou `missing` quand elle n'y est pas :

```cesia
text.Contains("ell", "hello") -->
text.StartsWith("http", "https://example.com") -->
text.EndsWith(".csv", "data.csv") -->
text.Find("lo", "hello") -->
text.Find("z", "hello") -->
```

[text.Count] dit combien de fois une partie apparaît, sans chevauchement : une fois qu'elle est trouvée, la recherche
reprend après elle, donc `"aa"` apparaît deux fois dans `"aaaa"`, pas trois. C'est le nombre de morceaux que donnerait
[text.Split], moins un, sans les fabriquer :

```cesia
text.Count("\n", "one\ntwo\nthree\n") -->
text.Count("aa", "aaaa") -->
```

Une partie d'un seul octet, comme une fin de ligne, se compte huit octets à la fois, une astuce appelée *SWAR*, SIMD
within a register (le SIMD, une même opération sur plusieurs données à la fois, fait ici dans un seul registre du
processeur) : les huit octets sont lus comme un seul mot de 64 bits, et quelques opérations sur ce mot trouvent d'un
coup tous les octets égaux à la partie. Compter les 2,9 millions de fins de ligne d'un texte de 100 MB prend 35 ms, là
où `value.Len(text.Split("\n", s)) - 1` prend 790 ms, car cette expression fabrique chaque ligne (médianes de 3 runs, des exécutions mesurées, sur la
machine de [Vitesse](speed.md#à-côté-des-géants)).

### Remplacer

[text.Replace] change chaque occurrence d'une partie :

```cesia
text.Replace("cat", "dog", "cat and cat") -->
```

Pour des patterns (des formes de texte), comme « chaque nombre de ce texte », [std/regex] a les regular expressions :
voyez la section [Regular expressions](#regular-expressions) plus bas.

## Nombres et textes

[text.Number] lit un nombre dans un texte : un entier ou un float (un nombre à virgule). Elle donne `missing` pour un
texte qui n'est pas un nombre : le programme décide alors quoi faire, au lieu de s'arrêter :

```cesia
text.Number("42") -->
text.Number("3.5") -->
text.Number("12 apples") -->
```

### Le texte d'une valeur

[value.Text] fait le chemin inverse : le texte de n'importe quelle valeur, tel que [io.Print] l'affiche.

```cesia
value.Text(42) -->
value.Text([1, 2]) -->
```

### Décimales

[text.Decimals] écrit un nombre avec tant de chiffres après le point décimal, arrondi au plus proche, pour un prix ou une
mesure. Une moitié s'arrondit en s'éloignant de zéro, comme le fait [math.Round] :

```cesia
text.Decimals(2, 3.14159) -->
text.Decimals(2, 42) -->
text.Decimals(0, 2.5) -->
"$(text.Decimals(1, 1155.25)) hours" -->
```

## Un petit rapport

Ensemble, ces fonctions changent des lignes brutes en quelque chose de lisible. Ici, chaque ligne d'un texte contient un
nom et un score :

```cesia
use std/io
raw = "ana,12\nbo,7\ncyril,15\n"
for line in text.Lines(raw)
  parts = text.Split(",", line)
  io.Print(text.PadRight(8, " ", parts[1]), text.PadLeft(3, " ", parts[2]))
end
```

`for` exécute son corps une fois pour chaque ligne ; le chapitre [Choix et boucles](choices.md) le montre en entier.
`parts[1]` est le premier morceau : les listes commencent à 1.

## Regular expressions

Une *regular expression*, une regex, est un petit texte qui décrit un ensemble de textes : `\d+` veut dire « un chiffre
ou plus », donc elle correspond à `42` dans `"aisle 42"`. [std/regex] cherche avec elles. [regex.Test] demande si un
pattern correspond quelque part, [regex.Find] donne la première correspondance, avec son `Text`, son `Start` et son
`Stop` en caractères à partir de 1, et les `Groups`, les parties que les parenthèses du pattern ont capturées ;
[regex.FindAll] donne toutes les correspondances, de gauche à droite, sans chevauchement :

```cesia
use std/regex
regex.Find("(\\d+)-(\\d+)", "call 555-1234 now") -->
value.Len(regex.FindAll("\\w+", "one two, three")) --> 3
regex.Test("^b", "abc") -->
```

Un pattern est un texte de Cesia : son `\` s'écrit donc `\\`, et le pattern `\d+` est le texte `"\\d+"`.
[regex.Replace] change chaque correspondance, `$1` à `$9` tenant lieu des groupes et `$$` d'un dollar, et
[regex.Split] coupe à chaque correspondance :

```cesia
regex.Replace("(\\w+)@(\\w+)", "$2 at $1", "ana@home") -->
regex.Split("\\s*;\\s*", "a ; b;c") -->
```

### Ce qu'un pattern peut dire

| Pattern | Correspond à |
|---|---|
| `a`, `é` | ce caractère ; `\.`, `\(`, `\\`... le caractère qui suit le `\`, pour ceux qui veulent dire quelque chose |
| `.` | n'importe quel caractère sauf une fin de ligne ; absolument n'importe lequel avec `(?s)` |
| `[abc]`, `[a-z]`, `[^0-9]` | un caractère de l'ensemble, d'une range (un intervalle de caractères), ou hors de l'ensemble |
| `\d`, `\w`, `\s` | un chiffre `0-9` ; une lettre, un chiffre ou `_` de l'ASCII ; un espace, une tabulation ou une fin de ligne. `\D`, `\W`, `\S` sont tous les autres |
| `\n`, `\t`, `\r` | une fin de ligne, une tabulation, un retour chariot |
| `^`, `$` | le début et la fin du texte ; de chaque ligne avec `(?m)` |
| `\b`, `\B` | une limite entre un caractère de mot et un caractère qui n'en est pas un, ou pas de limite |
| `x*`, `x+`, `x?` | `x` 0 fois ou plus, 1 fois ou plus, 0 ou 1 fois, autant de fois que possible |
| `x{3}`, `x{2,}`, `x{2,5}` | `x` 3 fois, 2 fois ou plus, de 2 à 5 fois |
| `x*?`, `x+?`, `x??`, `x{2,5}?` | la même chose, aussi peu de fois que possible : ils sont *lazy* (paresseux) |
| `x\|y` | `x` ou `y` |
| `(x)` | `x`, capturé comme groupe ; `(?:x)` groupe sans capturer |
| `(?i)`, `(?m)`, `(?s)` | placés n'importe où dans le pattern, pour le pattern entier : la casse ignorée de A à Z, `^` et `$` à chaque ligne, `.` prend les fins de ligne |

```cesia
regex.Find("a{2,3}", "aaaa").Text -->
regex.Find("a+?", "aaa").Text -->
regex.Test("(?i)hello", "Say HELLO") -->
regex.Test("(?m)^b", "a\nb") -->
```

Un pattern faux, comme `"(a"`, est un bug, et son message dit ce qui ne va pas : `Bad pattern: a parenthesis isn't
closed.` (le pattern est faux : une parenthèse n'est pas fermée). Un nombre de répétitions vaut au plus 1 000, les
groupes sont au plus 1 000, et un pattern a au plus 100 niveaux d'imbrication.

### Pourquoi aucun pattern ne peut bloquer un programme

Beaucoup de moteurs de regex essaient l'une après l'autre les façons dont un pattern peut correspondre, c'est le
*backtracking* (revenir en arrière pour essayer la façon suivante), et un pattern comme `(a+)+$` sur une longue ligne de
`a` prend alors un temps qui double à chaque lettre : un serveur qui applique un pattern à ce qu'envoie un utilisateur
peut être bloqué par une seule requête. [std/regex] est une *Pike machine* : elle suit en même temps toutes les façons
dont le pattern peut avancer, pas à pas le long du texte, comme le fait la méthode de Ken Thompson de 1968, et ne garde
chaque état qu'une fois. Son temps est au plus la taille du pattern multipliée par la longueur du texte : il est
*linéaire* en la longueur du texte, quel que soit le pattern. Le prix : pas de *backreference*, `\1` dans un pattern pour
« encore le même texte que le groupe 1 », qu'aucun moteur linéaire ne peut avoir, et pas de *lookahead* ni de
*lookbehind*, `(?=...)` et `(?<=...)` (regarder ce qui suit ou ce qui précède sans le prendre). Chaque octet parcouru
compte comme des pas d'exécution : `--limit steps` borne donc aussi une recherche.

## Octets

En dessous, un texte est une suite d'octets en [UTF-8](glossary.md#utf-8) (la façon d'écrire chaque caractère d'Unicode
en un à quatre octets), où `é` en prend deux. La plupart des programmes ne les voient jamais : [value.Len],
[text.Slice] et [text.Find] comptent des caractères. Pour un format de fichier ou un protocole réseau,
[text.ByteLength], [text.ByteSlice] et [text.Bytes] travaillent octet par octet :

```cesia
value.Len("é") -->
text.ByteLength("é") -->
text.Bytes("é") -->
```

[text.Byte] donne un octet, par sa position à partir de 1, [text.ByteFind] la position en octets d'une partie, en
cherchant à partir d'un octet donné, et [text.FromBytes] le texte d'une liste d'octets. [text.Code] donne le code point
d'un caractère, son numéro dans Unicode, et [text.Char] le caractère d'un code point :

```cesia
text.Byte(1, "é") -->
text.ByteFind("b", 1, "abc") -->
text.FromBytes([195, 169]) -->
text.Code("é") -->
text.Char(233) -->
```

Un programme lit un texte en octets quand un format les compte, comme le fait le `content-length` de HTTP : une position
en octets se trouve tout de suite, là où une position en caractères doit parcourir le texte depuis son début, puisque
UTF-8 donne à chaque caractère de un à quatre octets.

### Chercher des octets, avec ou sans la casse

`fold = true` fait que [text.ByteFind] accepte les lettres ASCII dans les deux casses, dans la partie et dans le texte,
comme la recherche d'un éditeur qui ignore la casse ; les autres octets, comme les deux de `é`, ne correspondent qu'à
eux-mêmes :

```cesia
text.ByteFind("world", 1, "Hello World", fold = true) -->
text.ByteFind("é", 1, "É and é", fold = true) -->
```

La recherche cherche d'abord l'octet le plus *rare* de la partie, d'après une table de la fréquence de chaque octet dans
un texte anglais et dans du code (`z` avant `e`, une majuscule ou un chiffre avant toute minuscule), huit octets à la
fois comme le fait [text.Count] ([SWAR](glossary.md#swar)), puis elle compare la partie entière à chaque endroit où se
trouve cet octet. Avec `fold`, quand cet octet est une lettre, les huit octets passent d'abord par un or bit à bit avec
32, `0x20` : une majuscule et sa minuscule ne diffèrent que par ce seul bit, les deux deviennent donc la minuscule, et
aucun autre octet ne devient cette minuscule. Une partie de 32 octets ou plus est cherchée par la méthode de Knuth,
Morris et Pratt, dont le temps est linéaire en la longueur du texte, quelle que soit la partie. Un mot à la fin d'un
texte de 100 MB est trouvé en 39 ms, 41 ms avec `fold`, contre 317 ms pour une copie du texte en minuscules suivie
d'une recherche ; [Vitesse](speed.md#textes-et-fichiers) met ces temps à côté de Python, Node et Go.

Une recherche compte dans `--limit steps` les octets qu'elle a lus, de son point de départ jusqu'à la fin de ce qu'elle a
trouvé : chercher la fin de ligne suivante d'un grand texte, ligne après ligne, coûte chaque ligne une fois, pas le texte
entier à chaque fois.

### UTF-8 valide

Un texte écrit dans un programme est toujours de l'UTF-8 valide, mais un texte lu dans un fichier ou sur le réseau
contient les octets qu'on lui a envoyés, quels qu'ils soient, et [text.FromBytes] en fabrique de n'importe lesquels.
[text.IsUtf8] dit si un texte est de l'UTF-8 valide au sens où le définit la [RFC 3629](references.md#textes-et-formats).
Un caractère prend de un à quatre octets ; le premier dit combien en suivent, et chacun de ceux qui suivent commence par
les bits `10`. Un texte est invalide s'il contient un octet qui ne peut ni commencer ni continuer un caractère, un
caractère coupé avant sa fin, un caractère écrit avec plus d'octets qu'il ne lui en faut (une *overlong form*, comme `0xC0
0x80` pour le caractère 0, qui peut tromper les programmes qui vérifient les textes octet par octet), un des
*surrogates* U+D800 à U+DFFF, que UTF-16 garde pour lui, ou un nombre au-delà de U+10FFFF, le dernier d'Unicode :

```cesia
text.IsUtf8("héllo") -->
text.IsUtf8(text.FromBytes([0xC3, 0xA9])) -->
text.IsUtf8(text.FromBytes([0xC0, 0x80])) -->
text.IsUtf8(text.FromBytes([0xED, 0xA0, 0x80])) -->
text.IsUtf8(text.FromBytes([0xE9, 0x74, 0xE9])) -->
```

Le dernier est `été` en Latin-1, un encodage plus ancien d'un octet par caractère, comme en contiennent de vieux
fichiers. La vérification lit huit octets d'ASCII à la fois, par un seul test de leurs bits de poids fort, et ne décode
un caractère que là où un octet n'est pas de l'ASCII : 26 ms pour un texte de 100 MB d'ASCII, 46 ms quand un caractère
sur 33 a un accent, contre 116 ms pour `String.is_valid_utf_8`, la fonction d'OCaml lui-même, qui décode chaque octet
(médianes de 3 runs, même machine).

## Pour aller plus loin

- F. Yergeau, *UTF-8, a transformation format of ISO 10646*, RFC 3629, 2003 : ce qu'est l'UTF-8 valide. Randall J.
  Fisher et Henry G. Dietz, *Compiling for SIMD Within a Register*, 1999, et Henry S. Warren, *Hacker's Delight*, 2013,
  section 6–1 : le travail sur huit octets à la fois de [text.Count], [text.IsUtf8] et [text.ByteFind]. Donald E.
  Knuth, James H. Morris et Vaughan R. Pratt, *Fast Pattern Matching in Strings*, 1977 : la recherche d'une longue
  partie.
- Ken Thompson, *Regular expression search algorithm*, 1968, et Russ Cox, *Regular Expression Matching Can Be Simple
  And Fast*, 2007, et *the Virtual Machine Approach*, 2009 : la méthode de [std/regex]. Voyez
  [Références](references.md#textes-et-formats).

## La suite

Vous savez couper et construire des textes. Le chapitre suivant, [Listes et arrays](lists.md), travaille avec beaucoup
de valeurs à la fois.
