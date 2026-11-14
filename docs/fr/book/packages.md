# Packages

Dans ce chapitre, vous découpez un programme en dossiers, vous utilisez les bibliothèques livrées avec Cesia, et vous
prenez du code à d'autres projets. Vous découvrez aussi `cesia.toml`, le fichier qui décrit un projet : son nom, ses
tâches, et ce qu'il utilise.

## use

[use] fait venir un [package](glossary.md#package), un module de code, dans un fichier. Son nom dans le code est la
dernière partie de son chemin, suivie d'un point :

```cesia
use std/encode
encode.Hex("hi") -->
encode.Base64("hi") -->
```

### as

`as` donne un autre nom au package, ce qui aide quand deux packages auraient le même nom, ou quand un nom est long :

```cesia
use std/set as sets
s = sets.Of([3, 1, 3, 2])
sets.Items(s) -->
sets.Has(2, s) -->
```

### D'où vient le code

La première partie du chemin dit d'où vient le code :

| Un use | Prend |
|---|---|
| `use std/csv` | ce qui est livré avec Cesia : ses bibliothèques et les modules du binaire |
| `use src/geometry` | un dossier de votre projet, depuis sa racine |
| `use deps/someone/project/src/x` | un dossier d'un autre projet, depuis la racine de ce projet |

Un use ne prend ni `./`, ni `../`, ni guillemets. La référence liste tout ce qui est sous `std/` : [std/sys],
[std/json], [std/http], [std/sql] et les autres.

## Un package est un dossier

Un package est l'ensemble des fichiers `.ce` d'un dossier, comme en Go. Il n'y a pas de ligne `package`, ni d'import
d'un seul fichier. Voici un projet avec deux packages à lui :

```text
shop/
  cesia.toml
  src/
    main.ce
    prices/
      tax.ce
      round.ce
```

Les deux fichiers de `src/prices/` sont un seul package. Les voici, l'un après l'autre : `tax.ce` appelle `cents`, un
nom en minuscules de `round.ce`, sans `use`.

```cesia
(* src/prices/tax.ce *)
WithTax(price) = cents(price * 1.2)

(* src/prices/round.ce *)
use std/math
cents(x) = math.Round(x * 100) / 100

WithTax(10.25) -->
```

`src/main.ce` écrit `use src/prices`, et appelle `prices.WithTax(10.25)`.

- Un nom avec une majuscule, `WithTax`, est public : les autres packages l'atteignent sous la forme `prices.WithTax`. Un
  nom avec une minuscule, `cents`, reste dans son dossier.
- Un sous-dossier est un autre package : `src/prices/old/` s'utilise par `use src/prices/old`, et s'appelle `old` dans
  le code.

### Pas de nom sans use

Aucun nom n'est vu par tous les fichiers : un fichier voit les noms de son package, les noms des packages qu'il utilise,
et les mots du langage. Afficher, c'est [io.Print], de `std/io` ; [list.Map] est dans `std/list`, [text.Split] dans
`std/text`, [result.Ok] dans `std/result`. Un nom écrit sans son package dit de quel use il a besoin :

```cesia fails
Print(1)
```

Un package peut donc donner à une fonction le même nom qu'un autre package : [set.Has] demande si un set (un ensemble de
valeurs, chacune une seule fois) contient un élément, et [dict.Has] si un dictionnaire contient une clé. Dans un
fichier, aucune variable, aucun paramètre, aucune fonction ni aucun pattern ne prend le nom d'un package que le fichier
utilise : avec `use std/text`, `text = "hi"` cacherait `std/text`, et c'est donc refusé au chargement du fichier. Donnez
un autre nom à la variable, comme `s` ou `line`.

### Les noms privés

Vu de l'extérieur, un nom privé n'est pas un nom du package, et le message le dit :

```cesia fails
use std/encode
encode.hexDigit
```

## cesia.toml

`cesia new shop` crée un projet : un `cesia.toml`, `src/main.ce`, un `.gitignore`, `std/`, une copie des bibliothèques
de Cesia pour ce projet, et `cesia.lock`, qui garde leurs fingerprints (les empreintes de leurs fichiers, qui changent si
un seul octet change). `cesia.toml` dit ce qu'est le projet :

```toml
[project]
name = "shop"
cesia = "1.0"     # the oldest Cesia it needs
src = ["src"]     # the folders of its code: the default

[tasks.run]
file = "src/main.ce"

[tasks.serve]
file = "src/server.ce"
allow = ["read=data", "net=:8080"]
```

### Tâches

Une tâche est un programme avec ses permissions, que le chapitre [Permissions](permissions.md) explique. `cesia do`
liste les tâches, et `cesia do serve` en lance une et montre la commande exacte : vous pouvez donc la taper vous-même :

```bash
cesia do
cesia do serve
```

La racine d'un projet est le dossier du `cesia.toml` le plus proche au-dessus du programme. S'il n'y en a pas, c'est le
dossier du fichier qui tourne.

## Du code d'autres projets

Tout projet qui a un `cesia.toml` peut donner ses packages à d'autres, comme [dépendance](glossary.md#dependency) de ces
projets : il n'y a pas de registry, pas de serveur central de packages comme PyPI pour Python ou npm pour Node. Comme
avec les modules de Go, une dépendance est un dépôt git et un *tag*, un nom donné à un commit (un état enregistré du
dépôt), comme `v1.2.0`. Une table `[deps]` nomme le dépôt, un tag, et les packages que vous prenez :

```toml
[deps.geometry]
from = "github.com/someone/geometry"
version = "v1.2.0"
take = ["src/shapes"]
```

Le code du projet écrit alors `use deps/someone/geometry/src/shapes`, et l'appelle `shapes`.

### cesia pkg

`cesia pkg add` écrit cette table pour vous, et va chercher le code. `cesia pkg install` met dans `std/` et `deps/` ce
que disent `cesia.toml` et `cesia.lock`, par exemple après un clone (une copie d'un dépôt git) :

```bash
cesia pkg add github.com/someone/geometry@v1.2.0 src/shapes
cesia pkg install
cesia pkg
```

- git va chercher chaque tag une seule fois, dans un cache (un dossier qui garde ce qui a déjà été téléchargé) : un autre
  projet qui le prend n'a pas besoin du réseau.
- Un projet qui n'a pas encore de tag se prend à un commit : `version` est alors le hash entier du commit, 40 chiffres
  hexadécimaux, comme `cesia pkg add github.com/someone/geometry@3f9c…` l'écrit. Un commit ne bouge jamais, comme un tag
  le peut ; git va chercher ce seul commit. Deux projets qui demandent le même à un commit doivent demander le même
  commit : des commits ne viennent dans aucun ordre, il n'y a donc pas de plus haut à prendre.
- `cesia.lock`, le [lock file](glossary.md#lock-file), garde le commit de chaque tag et un fingerprint de chaque fichier.
  Le code dans `std/` et `deps/` est en lecture seule : Cesia vérifie chaque fichier la première fois qu'il le lit, et un
  changement fait à la main arrête donc le programme.
- Pour changer le package de quelqu'un, faites-en un fork (votre propre copie de son dépôt), puis laissez
  `cesia pkg move` diriger le projet vers votre fork.
- `cesia run`, `cesia do` et `cesia test` n'utilisent jamais le réseau.
- Copier dans le projet le code dont il dépend, ici `std/` et `deps/`, s'appelle le *vendoring* : le programme tourne
  exactement sur ce code, et une release d'une dépendance (une nouvelle version publiée) ne change rien tant que
  `cesia pkg update` ne la demande pas.

### Ce qu'une dépendance a le droit de faire

Les permissions appartiennent au programme, pas à un package : le code d'une dépendance tourne avec toutes les
permissions que donne la ligne de commande, comme en Python, en Node ou en Go. Lisez le code que vous prenez, ou gardez
étroit le `--allow` de son programme, comme le montre le chapitre suivant.

## La suite

Vos programmes ont des parties, et peuvent utiliser les parties des autres. Le chapitre suivant,
[Permissions](permissions.md), dit ce qu'un programme a le droit de toucher hors de lui-même, et combien de ressources il
peut utiliser.
