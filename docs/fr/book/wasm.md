# Compiler vers WebAssembly

Dans ce chapitre, vous compilez un programme Cesia vers WebAssembly et vous le lancez dans une page web et dans Node, avec
la même sortie, les mêmes erreurs et les mêmes nombres que `cesia run`. [WebAssembly](glossary.md#webassembly-and-wasmgc)
est un format de code que tous les navigateurs actuels exécutent, près de la vitesse du code machine, dans la
[sandbox](glossary.md#sandbox) de la page (l'enceinte d'où le code ne peut pas sortir). `cesia build` compile le programme
[ahead of time](glossary.md#ahead-of-time-compilation), c'est-à-dire avant qu'il tourne : la page contient votre
programme et les quelques fonctions du runtime (le code de soutien qui accompagne tout programme) dont il se sert, et
aucun interpréteur.

C'est une première tranche : les nombres, les textes, les listes, les maps, les fonctions et les closures, `if`, `match`
et les boucles, les résultats, `?` et `!`, et les erreurs. Ce qu'elle ne compile pas encore est une erreur au build, à sa
place : voir [Ce qu'il compile](#ce-quil-compile).

## La commande

```bash
cesia build --target wasm file.ce
```

Elle écrit deux fichiers à côté de `file.ce` : `file.wasm`, le module, et `file.js`, son loader (le petit script qui va
chercher le module, le démarre et écrit ce qu'il affiche). Un programme qui utilise des packages les reçoit dans le même
module, compilés avec lui. Un nouveau build remplace les deux fichiers. `file.js` est du JavaScript simple de 70 lignes,
sans package à installer ni étape après lui.

Quand quelque chose ne peut pas encore être compilé, le build s'arrête à sa place, n'écrit aucun fichier, et donne
l'exit code 1 :

```text
fib.ce:3:10: std/fiber.Spawn isn't compiled to WebAssembly yet.
  3 | t = fiber.Spawn(() -> 1 + 1)
    |          ^
  cesia run runs it; cesia build --target wasm compiles part of Cesia for now.
```

Une erreur du programme lui-même, une erreur de syntaxe ou un nom qui n'existe pas, est l'erreur que donne `cesia run`,
au build. Un `file.js` du même nom que `cesia build` n'a pas écrit reste tel qu'il est : le build s'arrête avec l'exit
code 2, et dit de le déplacer ou de compiler un fichier d'un autre nom.

## Un premier programme dans une page

Le programme calcule la mensualité d'un prêt, puis, pour les premiers mois, ce que chaque mensualité paie d'intérêts et
ce qui reste dû. Un prêt de rien est un `Err`, que le programme écrit comme tel :

```cesia
(* loan.ce *)
use std/io
use std/result
use std/math
use std/list

(* The monthly payment of a loan, by the classic formula of annuities: p × r / (1 − (1 + r)^−n). *)
defn payment(principal, yearly, years)
  if principal <= 0 or years <= 0
    return result.Err("a loan needs an amount and a number of years above 0")
  end
  r = yearly / 12
  n = years * 12
  result.Ok(principal * r / (1 - (1 + r) ^ -n))
end

cents(x) = math.Round(x * 100) / 100

defn schedule(principal, yearly, years, months)
  pay = payment(principal, yearly, years)?
  owed = principal
  rows = []
  for m in 1..months
    interest = owed * yearly / 12
    owed = owed - (pay - interest)
    rows = list.Append({Month: m, Interest: cents(interest), Owed: cents(owed)}, rows)
  end
  result.Ok({Payment: cents(pay), Rows: rows})
end

defn show(s)
  io.Print("Each month: $(s.Payment)")
  for row in s.Rows
    io.Print("Month $(row.Month): $(row.Interest) of interest, $(row.Owed) still owed")
  end
end

for loan in [{Amount: 200000.0, Years: 25}, {Amount: 0, Years: 25}]
  match schedule(loan.Amount, 0.04, loan.Years, 3)
    result.Ok(s) -> show(s)
    result.Err(e) -> io.Print("No schedule: $e")
  end
end
```

Enregistrez-le sous `loan.ce` dans un dossier à lui, et compilez-le :

```bash
cesia build --target wasm loan.ce
```

Le dossier contient maintenant `loan.wasm` et `loan.js`. Dans Node 22 ou plus récent, le loader lance aussitôt le
programme, et affiche les mêmes lignes que `cesia run loan.ce` :

```bash
node loan.js
```

Dans une page, le loader est un module script (un script chargé avec `type="module"`). Enregistrez ceci sous
`index.html` à côté d'eux :

```html
<!doctype html>
<meta charset="utf-8">
<title>Loan</title>
<p>The schedule is on the console: press F12.</p>
<script type="module" src="loan.js"></script>
```

Un navigateur ne lance un module script que depuis un serveur, jamais depuis un fichier ouvert sur le disque.
[http.Static] sert les fichiers d'un dossier, si bien que le serveur tient en deux lignes de Cesia. Enregistrez-les sous
`serve.ce` :

```cesia norun
(* serve.ce: the files of this folder, on port 8080 of this machine. *)
use std/http
http.Serve(http.App() then http.Static("", "."))
```

Lancez-le, avec le droit de lire le dossier et d'écouter sur le port, puis ouvrez <http://127.0.0.1:8080/index.html> :

```bash
cesia run --allow read=.,net=:8080 serve.ce
```

La console de la page (F12) montre les cinq lignes qu'affiche `cesia run loan.ce`, un message chacune. Cette page a
tourné ainsi dans Chrome 158, et `node loan.js` dans Node 26, tous deux pareils à `cesia run loan.ce`, octet pour octet.

## La sortie et les erreurs

`io.Print` écrit sur la sortie standard dans Node, et dans la console de la page, un appel de `console.log` par ligne.
Une erreur écrit ce qu'écrit `cesia run`, le message, sa ligne avec la marque dessous, le conseil et les appels qui y ont
mené, sur la sortie d'erreur dans Node, qui sort alors avec le code 1, et par `console.error` dans une page. Puis le
programme s'arrête : rien de ce qui suit l'erreur ne tourne. Dans `typo.ce`, le second appel donne à `cents` un texte là
où un nombre était voulu :

```text
(* typo.ce *)
use std/io
use std/math

cents(x) = math.Round(x * 100) / 100
io.Print(cents(1055.666))
io.Print(cents("1055.666"))
```

`node typo.js` écrit, octet pour octet comme `cesia run typo.ce` :

```text
1055.67
typo.ce:4:25: Can't multiply the text "1055.666" by the number 100.
  4 | cents(x) = math.Round(x * 100) / 100
    |                         ^
  To put a value in a text, write "...$x" or value.Text(x).
  in cents (typo.ce:4)
```

Le message vient de la même table que celui de l'interpréteur, et le module garde les places de ses erreurs dans une
section à lui, `cesia.sites`, que le loader ne lit que quand une erreur arrive.

Les limites sont celles de `cesia run` : 10 000 appels de profondeur au plus, puis l'erreur `Limit "depth" reached.`, à
la même place, avec les mêmes appels nommés.

## Ce qu'il compile

| Compilé | Pas encore |
|---|---|
| les entiers de 63 bits, vérifiés comme `cesia run` les vérifie ; les floats ; true, false et missing | les fibers et les channels |
| les textes en UTF-8, `$` dans les textes, leur comparaison | les méthodes, les interfaces |
| les listes, les tableaux de floats et d'entiers, les ranges, les comprehensions, `x[i]` et `x[i] = v` | les slices, `x[a..b]` |
| les maps écrites en littéraux, leurs champs, `m["key"]`, `m.Name = v` | les types déclarés sur les paramètres et les résultats |
| les fonctions, les closures, les fonctions comme valeurs, la récursion | `dict.Put`, `dict.Dict` et la plus grande part de la bibliothèque standard |
| `if`, `match` et ses patterns, `for`, `while`, `return` | |
| `result.Ok`, `result.Err`, `?`, `!`, `bug.Panic` et les erreurs | |

Une map garde ses clés dans l'ordre d'insertion. Au-delà de 8 clés, elle les trouve par une table de leurs hashes (un
nombre tiré de chaque clé, qui dit où la ranger), comme la table d'une map de `cesia run` que rien d'autre ne tient
([Comment Cesia marche](internals.md#maps--une-hash-table-puis-un-hash-trie)), chaque table avec un seed (une graine)
tiré au hasard, pour que personne de l'extérieur ne puisse choisir des clés qui tombent ensemble, et tiré à nouveau
quand des clés tombent ensemble malgré tout. Les 500 000 clés de `bench/maps.ce`, écrites une à une puis lues chacune
une fois, prennent 413 ms dans Node, contre 342 pour `cesia run` ([Vitesse et taille](#vitesse-et-taille)). Une écriture
dans une map qu'une autre variable tient la recopie en entier, là où le trie de `cesia run` recopie une seule branche :
une map de beaucoup de clés qu'une fonction reçoit, écrit et rend coûte une copie à chaque appel.

De la bibliothèque standard, ceci compile : `io.Print` ; `math.Div`, `Mod`, `Abs`, `Floor`, `Ceil`, `Round`, `Sqrt`,
`Exp`, `Log`, `Sin`, `Cos`, `Tan`, `Asin`, `Acos` et `Atan` ; `list.Sum`, `Append`, `Concat`, `Take`, `Skip`, `Reverse`
et `Fill` ; `matrix.Zeros`, `Ones` et `Reshape` ; `value.Len`, `Text`, `Equal`, `Size` et les tests `IsInt` à
`IsMissing` ; et les packages écrits en Cesia, comme `std/result`, pour autant qu'ils n'utilisent que ce que ce tableau
compile.

## Comment ça marche

Le compilateur est un plugin de Cesia (un fichier de code chargé à la demande), `cesia_wasm.cmxs`, que seul
`cesia build` charge : `cesia run` ne le paie jamais. Il charge le programme comme `cesia run` le fait, puis compile
chaque fonction une fois pour chaque sorte d'arguments avec laquelle elle est appelée, comme le fait le JIT : là où les
types sont connus, un entier est un `i64` de WebAssembly, avec les vérifications des 63 bits de Cesia, et un float un
`f64`, tous deux dans les registres de la machine ; ailleurs, une valeur est une référence vers un objet de
[WasmGC](glossary.md#webassembly-and-wasmgc), le garbage collector (le ramasse-miettes, qui libère la mémoire que plus
rien ne tient) du navigateur lui-même, si bien que le module n'apporte pas de collector à lui. Un entier qui tient dans
31 bits est un `i31ref`, une référence qui contient le nombre sans aucun objet derrière. Une map littérale partage ses
clés avec toutes les maps du même littéral, et chaque lecture d'un champ se souvient des clés qu'elle a rencontrées en
dernier et de la place du champ parmi elles : la lecture suivante d'une map aux mêmes clés prend la valeur aussitôt,
comme un [inline cache](references.md#le-jit) (une petite mémoire, à un endroit du code, de ce qu'il a rencontré là).

Trois choses rendent ce code rapide dans les moteurs des navigateurs :

- *Chaque boucle dans une fonction à elle.* V8 et SpiderMonkey, les moteurs de Chrome et de Firefox, compilent une
  fonction d'abord avec un compilateur rapide, puis, une fois qu'elle a tourné un moment, à nouveau avec celui qui
  optimise ; un appel en cours reste dans son premier code. Alors chaque `for` et chaque `while` est une fonction à lui,
  un chunk (un morceau), qui fait au plus 16 384 tours par appel et qui est appelé à nouveau tant que la boucle
  continue : son appel suivant tourne dans le code optimisé. Les variables de la boucle entrent et reviennent, un
  `return` ou un `?` à l'intérieur sort par l'appelant, et un tableau de floats que la boucle ne fait que lire est pris
  une seule fois.
- *Les maps typées.* Une map littérale dont les clés sont écrites dans le code, et dont le compilateur connaît la sorte
  des valeurs, comme `{X: i * 1.0, N: i}`, est une struct de WasmGC avec un champ de chaque sorte, un `f64` pour un
  float, un `i64` pour un entier, sans rien dans un objet à part. Tout le reste, `Print`, `==`, un pattern,
  `m.Name = v`, voit une map.
- *Des paris, testés d'abord.* Une instruction qui lit `p.X` d'une variable `p`, où `p` peut tenir une map typée, la
  seule dont les clés contiennent chaque champ que la fonction lit de `p`, a deux versions : la première teste que `p`
  tient cette map, un seul test, puis lit ses champs comme les nombres qu'ils sont ; la seconde, pour quand le test
  échoue, est le code général. Une variable que la fonction ne met jamais qu'à des floats, comme une somme, est pariée
  de la même façon. Un mauvais pari coûte un test, jamais un autre résultat : la version générale tourne.

Chaque fonction du runtime, l'écriture d'un float ou l'arithmétique de deux valeurs de type inconnu, n'entre dans le
module qu'à sa première utilisation : un programme qui ne divise jamais n'a pas de division dans son module, et seuls
les types que son code utilise sont écrits. Les textes des messages sont des octets d'un data segment (un bloc d'octets
du module), un octet chacun. Le module et le loader sont écrits par Cesia lui-même, sans aucun outil de WebAssembly à
installer.

## Vitesse et taille

Les six programmes de [Vitesse](speed.md#le-calcul), `maps` parmi eux, et `bench/points.ce`, 1 000 maps `{X, V}`
déplacées chacune 2 000 fois et réécrites dans leur liste, compilés vers WebAssembly et lancés dans Node 26.13 (V8),
dans Chrome 158 (V8) et dans Firefox 160 (SpiderMonkey), tous deux headless (sans fenêtre), à côté des mêmes programmes
écrits en JavaScript, lancés dans le même moteur, et à côté de `cesia run`. Une seule machine, un Intel Core i7-4720HQ
de 2015, 8 cœurs logiques, Linux 7.2, le 2026-11-25, pendant que d'autres travaux tournaient dessus (charge de 2,0 à
3,0) : millisecondes, médianes de 5 runs, les côtés pris à tour de rôle pour que la charge tombe sur chacun, un nouveau
processus pour chaque run dans Node et un nouveau navigateur pour chaque tour. Les temps sont ceux du programme seul,
une fois son module chargé ; celui de `cesia run` est la commande entière, son démarrage d'environ 5 ms compris. Le plus
rapide de chaque moteur est en gras.

| Programme | Node, WebAssembly | Node, JavaScript | Chrome, WebAssembly | Chrome, JavaScript | Firefox, WebAssembly | Firefox, JavaScript | `cesia run` |
|---|---:|---:|---:|---:|---:|---:|---:|
| `fib` | **121** | 141 | **116** | 120 | **146** | 187 | 63 |
| `mandel` | 58 | **57** | 58 | **54** | 107 | **56** | 64 |
| `matmul` | 171 | **61** | 198 | **62** | 231 | **84** | 48 |
| `structs` | 151 | **142** | 138 | **112** | 314 | **109** | 42 |
| `dyn` | 310 | **137** | 260 | **129** | 385 | **116** | 64 |
| `points` | 53 | **34** | 41 | **29** | 98 | **37** | 54 |
| `maps` | **413** | 583 | **349** | 414 | 517 | **479** | 342 |

La première tranche de ce compilateur prenait, dans Node, 124 ms pour `fib`, 91 pour `mandel`, 904 pour `matmul`, 923
pour `structs`, 1 103 pour `dyn` et 148 pour `points`, et `maps` n'avait pas fini au bout de 100 secondes.

**Là où WebAssembly gagne.** Sur les appels de fonctions sur des nombres : `fib`, 30 millions d'appels sur des entiers
de 63 bits vérifiés à chaque pas, dans les trois moteurs, contre JavaScript, dont les nombres sont des floats sans
aucune vérification. Sur une map de beaucoup de clés : `maps`, 500 000 clés de texte, dans Node et Chrome. Et `mandel`
et `structs` arrivent à 2 à 24 % de JavaScript dans Node et Chrome.

**Là où JavaScript gagne, et pourquoi.**

- *Les vérifications de `matmul`.* Chacun de ses 27 millions de tours lit deux cases de tableaux : Cesia vérifie chaque
  indice contre le nombre de cases du tableau, puis WebAssembly le vérifie à nouveau contre son stockage, et chaque
  `i * n + k + 1` est vérifié contre les 63 bits des entiers de Cesia. V8 sait par la boucle que l'indice reste dans son
  tableau et additionne sur 32 bits : 2,7 à 3,2 fois.
- *Un appel à travers une valeur.* `dyn` appelle une de deux fonctions prises dans une liste à chacun de ses 10 millions
  de tours : l'appel teste que la valeur est une fonction de cette arité, compte la profondeur des appels, et rend son
  float dans un objet à lui. V8 voit les deux fonctions que l'appel rencontre, met leur code dans la boucle et garde le
  float dans un registre : 2,0 à 3,3 fois. Une entrée de la valeur de fonction pour les sortes qu'ont ses arguments au
  run prendrait le float sans objet ; elle n'est pas encore faite.
- *Une nouvelle map à chaque tour.* `points` fait une map à chacun de ses 2 millions de tours, une struct de WasmGC
  désormais, et l'écrit dans sa liste, ce qui teste que rien d'autre ne tient la liste et que la case est dedans ; V8
  écrit son objet sur place : 1,4 à 2,6 fois.
- *Firefox.* SpiderMonkey fait tourner ces modules 1,2 à 2,4 fois plus lentement que Chrome, là où son JavaScript suit
  celui de V8 : une page qui doit être rapide se mesure aussi dans Firefox. Des boucles dans des fonctions à elles,
  Firefox n'a gagné que sur `matmul`, de 1 069 ms à 439 dans ses propres mesures, comme s'il faisait tourner les autres
  dans son code optimisé dès le départ ; pourquoi ce code est plus lent sur ces modules n'a pas été trouvé dans cette
  tranche.
- Rust ou C compilés vers WebAssembly, sans vérification de dépassement, n'ont pas été mesurés ici.

Et `cesia run`, avec son JIT, gagne chaque ligne sauf `points` et `mandel` face à WebAssembly, bien que son temps
contienne son démarrage.

**Taille.** Ce qu'envoie un serveur, en octets, tel quel et compressé par Brotli à sa qualité 11, comme un serveur
compresse les fichiers une fois à l'avance, à côté de la première tranche de ce compilateur :

| Programme | Module | Module, Brotli | Première tranche | Première tranche, Brotli | Source JavaScript, Brotli |
|---|---:|---:|---:|---:|---:|
| hello world, `io.Print("Hello from Cesia")` | 322 | 244 | 431 | 321 |  |
| `fib` | 2 277 | 1 061 | 2 615 | 1 173 | 79 |
| `mandel` | 3 249 | 1 499 | 2 928 | 1 409 | 238 |
| `matmul` | 10 879 | 3 138 | 11 194 | 3 243 | 210 |
| `structs` | 13 100 | 4 725 | 13 448 | 4 393 | 250 |
| `dyn` | 10 571 | 3 958 | 11 461 | 4 053 | 199 |
| `points` | 10 576 | 4 344 | 11 754 | 4 271 | 196 |
| `maps` | 9 480 | 4 214 | 10 934 | 4 122 | 135 |
| `loan.ce` de ce chapitre | 20 258 | 6 609 | 18 988 | 5 762 |  |

Le loader, `NAME.js`, ajoute 3 149 octets, 1 313 avec Brotli, là où il en ajoutait 3 820 et 1 525 : il vient sans les
commentaires de sa source. Un module ne contient que les types que son code utilise, et le texte d'un message prend un
octet par octet. Une boucle dans une fonction à elle, et une instruction en deux versions, rendent plus gros un
programme de boucles, comme `loan.ce`. Un programme qui affiche une liste, une map ou une valeur d'un type que le
compilateur ne connaît pas apporte l'écriture de toutes les valeurs ; la source JavaScript reste plus petite, puisque
son moteur est déjà dans le navigateur.

## Pour aller plus loin

- Andreas Haas et d'autres, *Bringing the Web up to Speed with WebAssembly*, 2017 : la conception de WebAssembly, ses
  types et sa validation.
- Wasm 3.0 et sa proposition de garbage collection, 2025 : les structs, les tableaux et les `i31ref` dont sont faites les
  valeurs de Cesia.
- L. Peter Deutsch et Allan M. Schiffman, *Efficient Implementation of the Smalltalk-80 System*, 1984 : l'inline cache,
  que garde chaque lecture d'un champ.
- Craig Chambers, David Ungar et Elgin Lee, *An Efficient Implementation of SELF*, 1989 : les maps, la disposition
  partagée par les objets d'une même forme, que V8 appelle hidden classes ; les maps typées de Cesia dans une page.
- Le compact dict de Python 3.6, d'après Raymond Hettinger, et Donald E. Knuth, *The Art of Computer Programming*,
  volume 3, section 6.4 : la table d'une map au-delà de 8 clés, et ce que coûtent ses probes (les essais d'une case à la
  suivante).
- Guy L. Steele Jr., Doug Lea et Christine H. Flood, *Fast Splittable Pseudorandom Number Generators*, 2014 :
  SplitMix64, qui tire le seed de chaque table.

Chacun avec son lien dans [Références](references.md#webassembly), [Le JIT](references.md#le-jit),
[Valeurs et maps](references.md#valeurs-et-maps) et [Tests](references.md#tests).

## La suite

Le chapitre suivant, [C et C++](c.md), appelle les bibliothèques du système depuis Cesia.
