# C et C++

Dans ce chapitre, vous appelez une bibliothèque écrite en C : vous l'ouvrez, vous liez ses fonctions par leurs types, et
vous lui passez des nombres, des textes, de la mémoire et des callbacks (des fonctions de Cesia que C appellera). C'est la
[foreign function interface](glossary.md#foreign-function-interface) de Cesia (la façon dont un langage appelle des
fonctions écrites dans un autre). Les propres modules de Cesia pour la cryptographie et TLS sont construits ainsi, sur
libsodium et OpenSSL. Le C++ passe par une petite couche C que Cesia écrit et compile pour vous.

## Une confiance totale

Une bibliothèque C tourne en dehors de Cesia : elle ignore chaque permission et chaque limite, et un type faux dans un
binding (la déclaration qui lie une fonction C à Cesia) peut faire planter le programme. Un programme demande donc
`--allow ffi=NAME` pour chaque bibliothèque qu'il ouvre, et vous ne la donnez qu'aux bibliothèques auxquelles vous faites
confiance :

```bash
cesia run --allow ffi=m geometry.ce
```

## Ouvrir une bibliothèque et lier une fonction

[c.Open] charge une bibliothèque par son nom court, `m` pour la bibliothèque mathématique du C, en essayant les noms de
fichier qu'utilise chaque système. [c.Fn] lie une de ses fonctions : son nom, les types de ses arguments, le type de son
résultat. Il donne une fonction de Cesia :

```cesia allow=ffi=m
use std/c
use std/result
m = result.Unwrap(c.Open("m", version = 6))
cos = result.Unwrap(c.Fn("cos", ["f64"], "f64", m))
pow = result.Unwrap(c.Fn("pow", ["f64", "f64"], "f64", m))
cos(0.0) -->
pow(2.0, 10.0) -->
```

`version = 6` est le numéro majeur dans le nom du fichier de la bibliothèque : `libm.so.6` sur Linux. Les noms qui ont ce
numéro sont essayés d'abord, puis ceux qui ne l'ont pas.

### Des arguments et des noms faux

Un `Int` là où C attend un float (un nombre à virgule) en devient un, comme pour un paramètre typé. Un nom que la
bibliothèque n'a pas donne une `Err` :

```cesia allow=ffi=m
cos(0) -->
c.Fn("cosine", ["f64"], "f64", m) -->
```

## Types

| Type | En C | En Cesia |
|---|---|---|
| `i8`, `i16`, `i32`, `i64`, et `u8` à `u64` | des entiers de cette taille | `Int` |
| `f32`, `f64` | `float`, `double` | `Float` |
| `bool` | `bool` | `Bool` |
| `text` | `const char *` | `Text` |
| `ptr` | un pointeur | un bloc, ou `missing` pour `NULL` |
| `callback` | un pointeur de fonction | une fonction faite par [c.Callback] |
| `void` | pas de résultat | `missing` |
| une [c.Struct] | une structure passée par valeur | un bloc |

## Mémoire et structures

[c.Alloc] donne un bloc de mémoire en dehors de celle de Cesia, mis à zéro, pour une fonction C qui écrit dans un buffer
(une zone de mémoire où passent les octets) ou qui prend une structure. [c.Set] et [c.Get] écrivent et lisent un nombre à
un offset (une position en octets), [c.Store] et [c.Load] des octets de texte. [c.Free] libère le bloc :

```cesia allow=ffi=m
point = c.Struct(["f64", "f64", "i32"])
c.Size(point) -->
c.Offset(3, point) -->
p = c.Alloc(c.Size(point))
c.Set("f64", c.Offset(2, point), 2.5, p)
c.Get("f64", c.Offset(2, point), p) -->
c.Store("hi", 16, p)
c.Load(16, 2, p) -->
c.Free(p)
```

[c.Struct] dispose ses champs comme le fait C, avec le même padding (les octets vides que C laisse pour aligner un champ) :
ici, le `i32` commence après les deux floats, à l'octet 16. Un bloc utilisé après [c.Free] arrête le programme, au lieu de
lire de la mémoire qui n'est plus la sienne.

## Callbacks

Certaines fonctions C prennent une fonction à appeler : une comparaison, un handler d'événements (la fonction appelée à
chaque événement). [c.Callback] fait un pointeur de fonction C à partir d'une fonction de Cesia et des types avec lesquels
C l'appellera :

```cesia norun
use std/result
lib = result.Unwrap(c.Open("mylib"))
applyTwice = result.Unwrap(c.Fn("apply_twice", ["callback", "i64"], "i64", lib))
triple = c.Callback(x -> x * 3, ["i64"], "i64")
applyTwice(triple, 2)
```

Une panique dans un callback revient au code de Cesia qui a appelé C. Une fonction C qui garde un callback et l'appelle plus
tard, depuis une autre de ses fonctions, le dit quand elle est liée, avec `callsBack = true`.

### Les fonctions variadiques

Une fonction comme `printf` prend une *variable argument list* (une liste d'arguments de longueur variable), dont elle ne
déclare pas les types. [c.Variadic] en lie une : les types de ses arguments fixes, puis ceux des arguments que donne un
appel. C promeut (agrandit) un petit entier ou un `float` donné à cet endroit, si bien qu'ils sont refusés : écrivez `i32`
ou `f64`.

```cesia norun
use std/c
use std/result
libc = result.Unwrap(c.Open("c", version = 6))
snprintf = result.Unwrap(c.Variadic("snprintf", ["ptr", "u64", "text"], ["i32"], "i32", libc))
```

## Comment un appel atteint C

Un appel d'au plus 6 arguments, chacun un entier ou un float, avec un résultat de cette sorte, passe par une fonction C
faite pour sa *forme* (shape), les sortes de ses arguments et de son résultat : il y en a 254, écrites par
`src/gen/gen_calls.ml` quand Cesia est construit. Plus d'arguments, une structure passée par valeur, une fonction
variadique ou un callback passent par *libffi*, une bibliothèque qui construit un appel de n'importe quelle signature C
pendant que le programme tourne ; Cesia la trouve sur le système au premier appel de ce genre, et n'a donc rien de plus à
lier.

Mesuré le 8 novembre 2026, `bench/ccall.ce` : 10 millions d'appels de la fonction `abs` du C dans une boucle,
5 exécutions de chaque en alternance, la médiane et la plage, du minimum au maximum :

| | Appels par seconde |
|---|---:|
| Cesia, `std/c` | 11,8 millions (10,7 à 12,3) |
| Python, `ctypes`, `bench/ccall.py` | 2,0 millions (1,97 à 2,06) |
| LuaJIT, sa FFI, `bench/ccall.lua` | 818 millions (509 à 868) |

Un appel coûte à Cesia environ 85 nanosecondes, 6 fois moins que `ctypes` de Python, et 70 fois plus que LuaJIT, dont le
JIT (la partie qui change en code machine le code qui tourne souvent) compile l'appel dans le code machine de la boucle. Un
appel à C vaut la peine pour un travail qui prend plus que cela, comme tout un calcul d'une bibliothèque, pas pour un petit
pas dans une boucle.

## C++

Le C++ n'a pas de forme binaire stable, pas d'[ABI](glossary.md#abi) (la façon dont le code compilé passe ses arguments
et range ses données) : [std/cpp] décrit donc ce qu'il faut atteindre, écrit une petite couche C pour cela, la compile une
fois avec le compilateur C++, et la charge. [cpp.Wrap] donne un dictionnaire de fonctions, avec `"Class.new"`,
`"Class.delete"` et `"Class.method"` pour une classe :

```cesia norun
(* demo.ce *)
use std/cpp
use std/io
use std/result

spec = {
  Name: "demo",
  Include: ["<vector>", "<numeric>"],
  Classes: [cpp.Class("Numbers", "std::vector<int>", [
    cpp.Method("push", ["i32"], "void", call = "push_back"),
    cpp.Method("count", [], "u64", call = "size")
  ])],
  Functions: [cpp.Fn("gcd", ["i64", "i64"], "i64", call = "std::gcd<long, long>")]
}

defn main()
  m = cpp.Wrap(spec, folder = "build", compiler = "g++")?
  xs = m["Numbers.new"]()
  m["Numbers.push"](xs, 5)
  io.Print(m["Numbers.count"](xs), m["gcd"](12, 18))
  m["Numbers.delete"](xs)
  result.Ok(missing)
end

result.Unwrap(main())
```

### Le lancer

[cpp.Wrap] crée le dossier `build` s'il n'existe pas, y écrit la couche C, lance le compilateur, qui écrit la bibliothèque
à côté, et charge la bibliothèque. Le programme demande donc `exec` pour le compilateur, `read` et `write` sur `build`, et
`ffi` pour la bibliothèque qu'il a faite, par son chemin exact : `lib` et le `Name` de la spec (la description de ce qu'il
faut atteindre), puis `_cesia.so` :

```bash
cesia run --allow exec=g++,read=build,write=build,ffi=build/libdemo_cesia.so demo.ce
```

```text
1 6
```

[result.Unwrap] à la fin arrête le programme avec le message d'une `Err`, si le compilateur ou la bibliothèque échoue.

Il ne recompile que ce qui a changé. Une exception C++ devient une panique avec son message. [cpp.Source] donne le texte de
la couche C sans la compiler, pour lire ce que [cpp.Wrap] construirait.

## La suite

Vos programmes peuvent utiliser les bibliothèques du système. Le chapitre suivant, [Packages natifs](native.md), apporte du
nouveau code natif en OCaml, compilé une fois par l'auteur d'un package.
