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
module, compilés avec lui. Un nouveau build remplace les deux fichiers. `file.js` est du JavaScript simple de 80 lignes,
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

Une map est faite ici pour quelques clés, comme un enregistrement de champs : ses clés sont rangées à la suite, qu'une
nouvelle clé recopie et qu'une lecture parcourt depuis la première. Une map qui grandit clé par clé jusqu'à des milliers,
comme un dictionnaire de comptes, est lente pour l'instant : les 500 000 clés de `bench/maps.ce` n'avaient pas fini au
bout de 100 secondes, là où `cesia run` prend 255 ms ([Vitesse](speed.md#le-calcul)). Gardez ce travail dans
`cesia run`, ou dans un serveur que la page interroge, jusqu'à ce que la tranche suivante donne aux maps le hash trie de
`cesia run` (l'arbre de hachage qui range leurs clés).

De la bibliothèque standard, ceci compile : `io.Print` ; `math.Div`, `Mod`, `Abs`, `Floor`, `Ceil`, `Round`, `Sqrt`,
`Exp`, `Log`, `Sin`, `Cos`, `Tan`, `Asin`, `Acos` et `Atan` ; `list.Sum`, `Append`, `Concat`, `Take`, `Skip`, `Reverse`
et `Fill` ; `matrix.Zeros`, `Ones` et `Reshape` ; `value.Len`, `Text`, `Equal`, `Size` et les tests `IsInt` à
`IsMissing` ; et les packages écrits en Cesia, comme `std/result`, pour autant qu'ils n'utilisent que ce que ce tableau
compile.

## Comment ça marche

Le compilateur est un plugin de Cesia (un fichier de code chargé à la demande), `cesia_wasm.cmxs`, que seul `cesia build`
charge : `cesia run` ne le paie jamais. Il charge le programme comme `cesia run` le fait, puis compile chaque fonction
une fois pour chaque sorte d'arguments avec laquelle elle est appelée, comme le fait le JIT : là où les types sont connus,
un entier est un `i64` de WebAssembly, avec les vérifications des 63 bits de Cesia, et un float un `f64`, tous deux dans
les registres de la machine ; ailleurs, une valeur est une référence vers un objet de
[WasmGC](glossary.md#webassembly-and-wasmgc), le garbage collector (le ramasse-miettes, qui libère la mémoire que plus rien
ne tient) du navigateur lui-même, si bien que le module n'apporte pas de collector à lui. Un entier qui tient dans 31 bits
est un `i31ref`, une référence qui contient le nombre sans aucun objet derrière. Une map littérale partage ses clés avec
toutes les maps du même littéral, et chaque lecture d'un champ se souvient des clés qu'elle a rencontrées en dernier et de
la place du champ parmi elles : la lecture suivante d'une map aux mêmes clés prend la valeur aussitôt, comme un
[inline cache](references.md#le-jit) (une petite mémoire, à un endroit du code, de ce qu'il a rencontré là).

Chaque fonction du runtime, l'écriture d'un float ou l'arithmétique de deux valeurs de type inconnu, n'entre dans le
module qu'à sa première utilisation : un programme qui ne divise jamais n'a pas de division dans son module. Le module et
le loader sont écrits par Cesia lui-même, sans aucun outil de WebAssembly à installer.

## Vitesse et taille

Cinq programmes de [Vitesse](speed.md#le-calcul), `maps` mis à part (voir [Ce qu'il compile](#ce-quil-compile)),
compilés vers WebAssembly et lancés dans Node, à côté des mêmes programmes écrits en JavaScript, lancés dans le même
Node, et à côté de `cesia run` ; et `bench/points.ce`, 1 000 maps `{X, V}` déplacées chacune 2 000 fois et réécrites
dans leur liste, avec son jumeau `bench/points.js`. Une seule machine, un Intel Core i7-4720HQ de 2015, 8 cœurs logiques,
Linux 7.2, Node 26.13 (V8), le 2026-11-25, pendant que d'autres travaux tournaient dessus (charge de 5,5 à 6,7) :
millisecondes, médianes de 5 runs, les trois côtés pris à tour de rôle pour que la charge tombe sur chacun. *Seul* est le
temps du programme lui-même, une fois son module chargé ; *commande* la commande entière, démarrage de Node compris.

| Programme | WebAssembly, seul | JavaScript, seul | WebAssembly, commande | JavaScript, commande | `cesia run`, commande |
|---|---:|---:|---:|---:|---:|
| `fib` | **124** | 176 | 176 | 218 | 74 |
| `mandel` | 91 | **65** | 138 | 106 | 67 |
| `matmul` | 904 | **67** | 952 | 105 | 50 |
| `structs` | 923 | **184** | 980 | 226 | 48 |
| `dyn` | 1 103 | **155** | 1 152 | 206 | 74 |
| `points` | 148 | **37** | 189 | 75 | 47 |

**Là où WebAssembly gagne.** Sur les appels de fonctions sur des nombres : `fib`, 30 millions d'appels sur des entiers
de 63 bits vérifiés à chaque pas, tourne en 124 ms contre 176 pour JavaScript, dont les nombres sont des floats sans
aucune vérification.

**Là où JavaScript gagne, et pourquoi.** Partout ailleurs, de 1,4 fois sur `mandel` à 13,5 fois sur `matmul` ; et
`cesia run`, avec son JIT, gagne chaque ligne en commande entière :

- *Un long appel.* V8 compile d'abord un module avec un compilateur rapide, puis compile à nouveau avec son compilateur
  qui optimise les fonctions qui tournent souvent ; un appel déjà en cours continue dans le premier code. `matmul` est un
  seul appel de 27 millions de tours : avec `node --no-liftoff`, qui compile tout d'un coup avec le compilateur qui
  optimise, le même module a pris 414 ms là où il venait d'en prendre 1 567, un run de chaque, l'un après l'autre, sous
  une charge plus forte que celle du tableau. Le moteur de JavaScript fait passer une boucle en cours à son code rapide ;
  la tranche suivante découpe les boucles chaudes d'un long appel en fonctions à elles, que V8 optimise alors.
- *Une map faite à chaque pas.* `structs` et `points` font une nouvelle map à chaque tour et lisent ses champs par une
  fonction du runtime ; V8 donne à chaque objet de JavaScript une hidden class (la forme commune des objets aux mêmes
  champs), que son code lit sur place. La tranche suivante fait d'une map dont le compilateur connaît les clés une
  struct de WasmGC aux champs typés.
- *Un appel à travers une valeur.* `dyn` appelle à travers une liste de deux fonctions, ses floats mis dans des objets à
  chaque appel, là où le compilateur qui optimise de V8 peut mettre en ligne les fonctions qu'un appel rencontre.
- Le WebAssembly de `points` écrit à la main pour la conception de ce compilateur, avec chaque valeur en `i64` et les
  mêmes vérifications, a pris 47 ms seul : ce que le compilateur peut atteindre une fois qu'il connaît les types des
  champs d'une map. Rust ou C compilés vers WebAssembly, sans vérification de dépassement, n'ont pas été mesurés ici.

**Taille.** Ce qu'envoie un serveur, en octets, tel quel et compressé par Brotli à sa qualité 11, comme un serveur
compresse les fichiers une fois à l'avance :

| Programme | Module | Module, Brotli | Source JavaScript, Brotli |
|---|---:|---:|---:|
| hello world, `io.Print("Hello from Cesia")` | 431 | 321 | |
| `fib` | 2 615 | 1 173 | 79 |
| `mandel` | 2 928 | 1 409 | 238 |
| `matmul` | 11 194 | 3 243 | 210 |
| `structs` | 13 448 | 4 393 | 250 |
| `dyn` | 11 461 | 4 053 | 199 |
| `points` | 11 754 | 4 271 | 196 |
| `loan.ce` de ce chapitre | 18 988 | 5 762 | |

Le loader, `NAME.js`, ajoute environ 3 820 octets, 1 525 avec Brotli. Un programme qui affiche une liste, une map ou une
valeur d'un type que le compilateur ne connaît pas apporte l'écriture de toutes les valeurs, la plus grande part des
11 Ko ci-dessus ; le `points` écrit à la main faisait 469 octets. La source JavaScript reste plus petite, puisque son
moteur est déjà dans le navigateur.

## Pour aller plus loin

- Andreas Haas et d'autres, *Bringing the Web up to Speed with WebAssembly*, 2017 : la conception de WebAssembly, ses
  types et sa validation.
- Wasm 3.0 et sa proposition de garbage collection, 2025 : les structs, les tableaux et les `i31ref` dont sont faites les
  valeurs de Cesia.
- L. Peter Deutsch et Allan M. Schiffman, *Efficient Implementation of the Smalltalk-80 System*, 1984 : l'inline cache,
  que garde chaque lecture d'un champ.

Chacun avec son lien dans [Références](references.md#webassembly) et [Le JIT](references.md#le-jit).

## La suite

Le chapitre suivant, [C et C++](c.md), appelle les bibliothèques du système depuis Cesia.
