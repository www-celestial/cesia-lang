# Résoudre un vrai problème

Dans ce chapitre, vous résolvez un problème que presque tout le monde a sur son ordinateur : un dossier de
téléchargements ou de photos plein de copies. `photo.jpg` et `photo (1).jpg`, un fichier enregistré deux fois, une
sauvegarde remise dans le dossier. La question est courte : *quels fichiers de ce dossier sont des doublons ?*

Vous le résolvez comme la recherche résout un problème, en sept étapes, et chaque étape nomme sa méthode et d'où elle
vient :

1. dire exactement ce que *résolu* veut dire, sous la forme d'une propriété qu'un programme peut vérifier ;
2. mesurer avant de rien changer ;
3. faire une supposition qu'une expérience peut réfuter, et faire l'expérience ;
4. trouver ce qui est déjà connu ;
5. écrire la plus petite solution ;
6. prouver que c'est résolu : par des tests, par une borne, par des temps à côté de Python ;
7. dire ce qui reste.

Chaque bloc de Cesia de cette page a tourné quand le livre a été construit. Les temps viennent de runs (des exécutions
mesurées) sur une seule machine, avec la méthode écrite à côté. Les articles et les documents sont dans
[Références](references.md#résoudre-un-problème).

## 1. Le problème, énoncé avec précision

*How to Solve It* (1945) de George Pólya commence chaque problème par les mêmes questions : quelle est l'inconnue,
quelles sont les données, quelle est la condition ? Ici, les données sont un dossier ; l'inconnue, les groupes de ses
fichiers qui sont des copies les uns des autres ; la condition, ce qui fait de deux fichiers des copies. Le
[Heilmeier catechism](glossary.md#heilmeier-catechism), les questions que la DARPA pose à un projet de recherche, ajoute
celle qui compte le plus à la fin : quel est l'examen qui dit la réussite ?

Deux fichiers sont des *doublons* quand ils contiennent les mêmes octets, quels que soient leurs noms, leurs dates ou
leurs dossiers. La réponse est une liste de groupes de chemins. Elle est juste quand elle a deux propriétés, et chacune
est une vérification qu'un programme peut faire :

- *complète* : deux fichiers aux mêmes octets sont dans le même groupe ;
- *correcte* : deux fichiers du même groupe ont les mêmes octets, et chaque groupe contient deux fichiers ou plus.

« Contient les mêmes octets » est une [relation d'équivalence](glossary.md#equivalence-relation) : chaque fichier contient
ses propres octets ; si `a` contient les octets de `b`, `b` contient ceux de `a` ; et une copie d'une copie est une
copie. Une telle relation découpe les fichiers en *classes*, les ensembles de fichiers qui sont des copies les uns des
autres, et la réponse est faite des classes de deux fichiers ou plus.

En dehors du problème : les photos qui se ressemblent mais diffèrent par leurs octets, comme une photo et sa version
réduite, qui sont un autre problème, les *quasi*-doublons ; effacer quoi que ce soit, puisque le programme ne fait que
dire ; et les fichiers hors du dossier.

Un dossier sur lequel travailler. Un *chemin* nomme un fichier à partir d'un dossier, comme
`downloads/photos/IMG_0001.jpg` :

```cesia allow=read,write
use std/sys
sys.Mkdir("downloads/photos")
sys.Write("downloads/cat.jpg", "meow meow")
sys.Write("downloads/cat (1).jpg", "meow meow")
sys.Write("downloads/photos/IMG_0001.jpg", "meow meow")
sys.Write("downloads/notes.txt", "buy bread")
sys.Write("downloads/notes copy.txt", "buy bread")
sys.Write("downloads/todo.txt", "buy milk!")
sys.Write("downloads/report.pdf", "%PDF-1.7 report")
sys.Walk("downloads") -->
```

La bonne réponse a deux groupes : `cat.jpg`, `cat (1).jpg` et `photos/IMG_0001.jpg`, puis `notes.txt` et
`notes copy.txt`. `todo.txt` a 9 octets, comme `notes.txt` et `cat.jpg`, mais pas leurs octets : il n'appartient à aucun
groupe, pas plus que `report.pdf`.

## 2. Mesurer avant de rien changer

La première façon qui vient à l'esprit est la définition elle-même : comparer chaque fichier avec chacun de ceux qui le
suivent, octet par octet. [sys.Walk] donne chaque chemin sous un dossier, [sys.Stat] distingue un fichier d'un dossier
ou d'un lien, et [sys.Read] donne les octets d'un fichier sous la forme d'un texte :

```cesia
use std/list
use std/value
use std/result

defn plainFiles(folder)
  (** Each regular file under a folder, at any depth, as {Path, Size}: no folder, no link, no device. *)
  out = []
  for p in sys.Walk(folder)?
    info = sys.Stat(p)?
    if info.IsFile and not info.IsLink
      out = list.Append({Path: p, Size: info.Size}, out)
    end
  end
  result.Ok(out)
end

sorted(groups) = list.SortBy(g -> g[1], [list.Sort(g) for g in groups])   (** Each group in order, then the groups by their first path. *)

defn naive(folder, read = sys.Read)
  (** The groups of copies under a folder, the first way that comes to mind: each file against each one after it, byte
      by byte, each read with read. *)
  paths = [f.Path for f in plainFiles(folder)?]
  n = value.Len(paths)
  taken = list.Fill(false, n)
  groups = []
  for i in 1..n
    if not taken[i]
      group = [paths[i]]
      for j in (i + 1)..n
        if not taken[j] and read(paths[i])? == read(paths[j])?
          group = list.Append(paths[j], group)
          taken[j] = true
        end
      end
      if value.Len(group) > 1
        groups = list.Append(group, groups)
      end
    end
  end
  result.Ok(sorted(groups))
end

naive("downloads") -->
```

Elle est juste, puisqu'elle fait ce que dit la définition, et elle servira de réponse sûre, à laquelle une façon plus
rapide sera comparée. Son coût : $n$ fichiers font $n(n - 1)/2$ paires, et chaque paire lit ses deux fichiers, si bien
qu'un dossier sans copies est lu $n(n - 1)$ fois en tout, chaque fichier $n - 1$ fois. Ce coût est *quadratique* : deux
fois plus de fichiers, quatre fois plus de lectures. Dans la [notation grand O](glossary.md#big-o-notation), il est en
$O(n^2)$.

### Comment on a mesuré

Combien de temps cela fait-il, en secondes ? Une supposition n'est pas une mesure, donc le premier temps mesuré est la
[baseline](glossary.md#baseline) (la mesure de départ), celle à laquelle chaque changement est comparé. Chaque temps de ce
chapitre est mesuré de la même façon, comme l'enseigne *The Art of Computer Systems Performance Analysis* (1991) de Raj
Jain :

- La même tâche pour chaque programme : le même dossier, la même réponse, vérifiée à chaque run contre le premier run du
  premier programme.
- Chaque temps est celui du processus entier, de son début à sa fin : ce qu'attend un utilisateur.
- 11 runs de chaque programme, les programmes à tour de rôle, et leur ordre décalé à chaque tour, pour qu'une minute plus
  lente de la machine tombe sur tous. Andy Georges, Dries Buytaert et Lieven Eeckhout ont montré en 2007 qu'un seul run,
  ou le meilleur de quelques-uns, peut faire paraître plus rapide le mauvais programme ; Tomas Kalibera et Richard
  Jones, en 2013, que les runs doivent être répétés au niveau où se trouve le bruit, ici le processus.
- La *médiane* des 11 runs, celui du milieu, et son [confidence interval](glossary.md#confidence-interval) à 95 %, tiré
  des [order statistics](glossary.md#order-statistic) : les temps mis en ordre, le 2e et le 10e. Cet intervalle contient
  la vraie médiane avec une probabilité d'au moins 95 %, quelle que soit la forme des temps, d'après le théorème 2.1 de
  *Performance Evaluation of Computer and Communication Systems* (2010) de Jean-Yves Le Boudec. Il ne suppose pas que
  les temps suivent une courbe en cloche, ce que des temps font rarement.
- Le pic de mémoire est la plus grande taille résidente (la mémoire vive que le processus occupe vraiment) que le
  système compte pour le processus. Il part des 13 MB du programme qui mesure, que le système compte pour le processus
  qu'il démarre, si bien qu'un programme qui affiche un nombre montre 13,2 MB en Cesia comme en Python : sous 16 MB, un
  pic ne veut guère dire plus que cela.

La probabilité vient d'un compte : la vraie médiane est hors de l'intervalle quand au moins 10 des 11 runs tombent d'un
même côté d'elle, et chaque run tombe d'un côté ou de l'autre avec une chance sur deux :

```cesia
defn choose(n, k)
  (** How many ways there are to pick k things among n. *)
  out = 1
  for i in 1..k
    out = out * (n - k + i) / i
  end
  out
end

defn coverage(n, j)
  (** The probability that the true median lies between the j-th and the (n + 1 - j)-th of n times in order. *)
  1 - 2 * list.Sum([choose(n, i) for i in 0..j - 1]) / 2 ^ n
end

coverage(11, 2) -->
coverage(11, 3) -->
```

Le 2e et le 10e des 11 l'encadrent avec une probabilité de 98,8 % ; le 3e et le 9e seulement de 93,5 %, trop peu pour
95 %.

La machine est celle de [Vitesse](speed.md#à-côté-des-géants) : un Intel Core i7-4720HQ de 2015, 8 cœurs logiques,
11 GB de mémoire, Linux, un SSD en SATA avec btrfs ; Cesia dans son build de ce dépôt, Python 3.14.9. Les dossiers
viennent de `bench/dupes-folder.py`, avec le seed 1 (le nombre dont part le générateur de nombres au hasard) : des
fichiers d'octets au hasard, de 4 KiB à 1 MiB, répartis également sur une échelle logarithmique, comme le sont les photos
et les téléchargements, dans dix dossiers ; un fichier sur dix est une copie d'un fichier précédent.

### La baseline

Médianes de 11 runs, et leur intervalle à 95 %, en millisecondes ; les dossiers de photos, tels que le cache les tient
après une première lecture (un [page cache](glossary.md#page-cache) *warm* : la copie des fichiers que le système garde
en mémoire tient déjà leurs octets), mesurés le 2026-11-08, charge 1,0 :

| Fichiers | Leurs octets | Paires | `naive` | Intervalle à 95 % |
|---:|---:|---:|---:|---:|
| 100 | 24,4 MB | 4 950 | 1 107 | 1 094 à 1 126 |
| 200 | 41,9 MB | 19 900 | 3 204 | 3 172 à 3 391 |
| 400 | 80,7 MB | 79 800 | 16 087 | 15 989 à 16 231 |

Deux fois plus de fichiers, trois à cinq fois plus de temps. Ce n'est pas exactement quatre parce que les dossiers
diffèrent par la taille moyenne de leurs fichiers : chaque fichier est lu $n - 1$ fois, donc la façon naïve lit environ
2,4 GB, 8,3 GB et 32,2 GB, entre 2,0 et 2,6 GB par seconde. À ce rythme, un dossier de 10 000 photos prendrait 625 fois
les 16 secondes de 400, environ trois heures.

## 3. Une hypothèse qu'on peut réfuter

Une *hypothèse* vaut quelque chose quand une expérience peut la réfuter : elle est
[falsifiable](glossary.md#falsifiable), selon le mot de *The Logic of Scientific Discovery* (1934) de Karl Popper.
« Le programme est lent » n'en est pas une. « Le temps passe à lire les mêmes fichiers encore et encore » en est une,
puisqu'elle prédit ce que montrera une expérience : lire chaque fichier une fois, le garder en mémoire, comparer les mêmes
paires dans le même ordre, et presque tout le temps doit disparaître, puisque chaque fichier est alors lu une fois au
lieu de $n - 1$ fois. Si le temps passait plutôt à comparer des octets, à parcourir le dossier ou à démarrer Cesia, il
bougerait à peine.

Une expérience ne change qu'une chose. `naive` prend sa façon de lire un fichier comme un paramètre, `read`, qui vaut
[sys.Read] sauf indication contraire ; `readOnce` donne une autre façon, qui lit chaque fichier une fois au début, puis
le sert depuis la mémoire :

```cesia
defn readOnce(folder)
  (** A way to read the files of a folder from memory, where each was read once at the start. *)
  kept = {}
  for f in plainFiles(folder)?
    kept[f.Path] = sys.Read(f.Path)?
  end
  result.Ok(p -> result.Ok(kept[p]))
end

naive("downloads", read = result.Unwrap(readOnce("downloads"))) --> naive("downloads")
```

Les mêmes dossiers, la même méthode :

| Fichiers | `naive` | `naive`, chaque fichier lu une fois | Son pic de mémoire |
|---:|---:|---:|---:|
| 100 | 1 107 (1 094 à 1 126) | 32,3 (31,6 à 32,5) | 44 MB |
| 200 | 3 204 (3 172 à 3 391) | 54,2 (53,1 à 59,4) | 68 MB |
| 400 | 16 087 (15 989 à 16 231) | 112,6 (111,0 à 113,8) | 131 MB |

La prédiction a tenu. À 400 fichiers, les mêmes comparaisons, dans le même ordre, prennent 113 ms au lieu de 16,1 s :
99,3 % du temps de la façon naïve passait à relire les mêmes fichiers. L'hypothèse aurait pu échouer, et ne l'a pas
fait : elle tient donc. Lire une seule fois n'est pas pour autant une solution : cela garde tout le dossier en mémoire à
la fois, 131 MB pour 81 MB de fichiers, et cela compare encore chaque paire.

### Un raccourci, réfuté

Une deuxième hypothèse vient aussitôt, et elle épargnerait toutes les lectures : *les fichiers d'une même taille sont des
copies*. [sys.Stat] donne la taille sans lire un octet, et [list.Group] réunit les éléments qui partagent une clé :

```cesia
defn bySize(folder)
  (** The shortcut: files of one size taken as copies, without reading them. *)
  groups = [[f.Path for f in g.Values] for g in list.Group(it.Size, plainFiles(folder)?) if value.Len(g.Values) > 1]
  result.Ok(sorted(groups))
end

bySize("downloads") -->
```

Le dossier de cette page la réfute déjà : `todo.txt` atterrit parmi les photos d'un chat. Sur un dossier qu'on ne
connaît pas, un [property-based test](glossary.md#property-based-testing) (un test qui vérifie une règle sur beaucoup de
cas générés) trouve un tel cas tout seul : il fabrique des dossiers au hasard, avec des copies qu'il connaît, et vérifie
la réponse sur chacun. Le test de l'[étape 6](#des-propriétés-sur-des-dossiers-générés), avec le seed 1, échoue sur le
raccourci à son 4e dossier, puis fait le [shrinking](glossary.md#shrinking) de ce dossier (il le réduit tant qu'il échoue
encore), et donne le plus petit qu'il trouve : deux fichiers de deux octets, `aa` et `ba`. Andreas Zeller et Ralf
Hildebrandt ont rendu cette idée systématique en 2002, sous le nom de [delta debugging](glossary.md#delta-debugging) : une
entrée qui fait échouer, rendue plus petite pas à pas, montre la cause de l'échec. Ici, la cause est évidente : une
taille, deux textes.

La taille ne peut donc pas décider seule. Mais elle peut écarter : deux fichiers de tailles différentes ne sont jamais des
copies, et demander une taille ne lit rien.

## 4. La recherche

Ce genre de problème est ancien, et sa réponse est connue. Trois résultats la font.

**D'abord une clé bon marché.** Une *clé* est une valeur calculée à partir d'un fichier, et une clé qui ne dépend que
des octets ne sépare jamais deux copies : des octets égaux donnent des clés égales. Grouper par une telle clé garde entier
chaque groupe de copies, donc la réponse reste complète ; elle peut seulement mettre trop de fichiers dans un groupe. Une
clé bon marché, la taille, découpe d'abord les fichiers ; une plus chère, calculée seulement dans les groupes de deux
fichiers ou plus, découpe de nouveau ceux-ci. C'est un [partition refinement](glossary.md#partition-refinement) : chaque
étape découpe les groupes de l'étape d'avant, et aucune ne les réunit de nouveau. Un fichier dont aucun autre fichier
n'a la taille n'est jamais lu.

**Un hash cryptographique.** La clé plus chère est une [fonction de hash](glossary.md#hash-function) : un digest (une
empreinte) d'une longueur fixe, calculé à partir de tous les octets d'un fichier. BLAKE2b, de Jean-Philippe Aumasson,
Samuel Neves, Zooko Wilcox-O'Hearn et Christian Winnerlein (2013), en est une cryptographique, aussi rapide que MD5 et
construite pour que personne ne sache trouver deux textes de même digest. Sa forme de 256 bits, BLAKE2b-256, a une
*sécurité contre les collisions* de $2^{128}$, d'après la RFC 7693 : trouver deux textes de même digest demande environ
$2^{128}$ essais du hash, l'attaque générique. [cesia.Fingerprint] donne ce digest, celui que `cesia.lock` garde pour
chaque fichier. Il ne demande aucune permission, là où [crypto.Blake2b] appelle libsodium ; les deux donnent les mêmes 32
octets.

**La birthday bound.** Deux fichiers différents de même taille peuvent quand même recevoir le même digest, par hasard :
une *collision*. Quelle en est la probabilité ? Pour $k$ fichiers différents, il y a $k(k - 1)/2$ paires. Si les digests
se comportent comme des tirages au hasard parmi les $N = 2^{256}$ possibles, chaque paire entre en collision avec la
probabilité $1/N$, et la probabilité qu'au moins une paire le fasse est au plus la somme sur les paires, d'après
l'[union bound](glossary.md#union-bound) :

$$
P(\text{au moins une collision parmi } k \text{ fichiers}) \le \frac{k(k - 1)}{2} \times 2^{-256}
$$

C'est la [birthday bound](glossary.md#birthday-bound) (la borne des anniversaires), nommée d'après la surprise classique
qu'il suffit de 23 personnes pour que deux d'entre elles aient le même anniversaire plus d'une fois sur deux ; le
*Handbook of Applied Cryptography* de Menezes, van Oorschot et Vanstone (1996) donne la probabilité exacte, son
Fact 2.27. L'[étape 6](#la-borne-calculée) calcule le nombre.

### Comment font les outils établis

Les outils dont on se sert pour ce problème font les mêmes étapes, d'après leur documentation :

- **fdupes** : « Such files are found by comparing file sizes and MD5 signatures, followed by a byte-by-byte
  comparison », dit sa page de manuel : les fichiers sont trouvés en comparant leurs tailles et leurs signatures MD5,
  puis octet par octet.
- **jdupes**, dérivé de fdupes 1.51 : les fichiers de tailles différentes ne sont pas comparés ; les 4 premiers KiB sont
  hashés et comparés, puis les fichiers entiers, avec xxHash ; « finally, actual file data is compared to verify that
  they are duplicates » (enfin, les données mêmes des fichiers sont comparées pour vérifier que ce sont des doublons),
  dit son README. Son `-Q` saute cette dernière étape, avec un warning (un avertissement) : il « may delete
  non-duplicates » (peut effacer des fichiers qui ne sont pas des doublons).

Les deux comparent les octets à la fin, et pour une raison : MD5 est cassé, depuis que Xiaoyun Wang et Hongbo Yu ont
montré en 2005 comment fabriquer deux textes d'un même MD5, et xxHash n'est pas un hash cryptographique, il est fait pour
la vitesse, avec 64 bits dans jdupes (XXH64, dans sa source). Avec 64 bits, la borne pour un million de fichiers est
$2{,}7 \times 10^{-8}$, et n'importe qui peut fabriquer exprès deux fichiers d'un même xxHash. Avec BLAKE2b-256, la borne est
$2^{192}$ fois plus petite, environ $6 \times 10^{57}$ fois, et fabriquer deux fichiers d'un même digest demande les $2^{128}$
essais de l'attaque générique. Ce chapitre fait donc l'autre choix : aucune comparaison d'octets, une seule lecture de
chaque fichier dont un autre fichier a la taille, et la borne comme preuve qu'aucun groupe n'est faux.

Ce qui ne s'applique pas : jdupes hashe les 4 premiers KiB d'un fichier avant le fichier entier, ce qui évite de lire
presque tout un grand fichier qui diffère tôt. [sys.Read] lit un fichier en entier, donc cette étape lirait autant que le
hash complet.

## 5. La plus petite solution

La taille, puis le digest, parmi les fichiers d'une même taille :

```cesia
use std/cesia

defn Duplicates(folder)
  (** The groups of files under a folder that hold the same bytes, two or more to a group: by size first, then, among
      the files of one size, by their BLAKE2b-256. *)
  groups = []
  for same in list.Group(it.Size, plainFiles(folder)?)
    if value.Len(same.Values) > 1
      hashed = []
      for f in same.Values
        hashed = list.Append({Path: f.Path, Hash: cesia.Fingerprint(sys.Read(f.Path)?)}, hashed)
      end
      for g in list.Group(it.Hash, hashed)
        if value.Len(g.Values) > 1
          groups = list.Append([h.Path for h in g.Values], groups)
        end
      end
    end
  end
  result.Ok(sorted(groups))
end

Duplicates("downloads") -->
Duplicates("downloads") --> naive("downloads")
```

Dix-neuf lignes. Chaque fichier est lu au plus une fois, et seulement si un autre fichier a sa taille : ici six des sept,
puisque six ont 9 octets. Dans un dossier de photos, dont les tailles se rencontrent rarement, il lit à peine plus que
les copies.

## 6. La preuve que c'est résolu

### Un test qui échoue avant et passe après

Le dossier que le shrinking a trouvé devient un test qui reste : il échoue sur le raccourci, l'« avant », et passe sur
`Duplicates`, l'« après ». `finds` fabrique un dossier à partir d'une liste de textes, un fichier par texte, et vérifie
une façon de trouver les copies contre les groupes qu'il connaît :

```cesia
(* dupes.test.ce *)
use std/test
use std/gen
use std/math

defn written(contents, dir)
  (** The folder dir, emptied, then with one file per text, spread over three folders. *)
  sys.Mkdir(dir)?
  for p in sys.Walk(dir)?
    sys.Remove(p)?
  end
  for k in 1..value.Len(contents)
    sys.Mkdir("$dir/d$(math.Mod(k, 3))")?
    sys.Write("$dir/d$(math.Mod(k, 3))/f$k", contents[k])?
  end
  result.Ok(dir)
end

defn copies(contents, dir)
  (** The groups that the folder of written must give, known from the texts it was made of. *)
  at(k) = "$dir/d$(math.Mod(k, 3))/f$k"
  sorted([[at(k) for k in g.Values] for g in list.Group(k -> contents[k], 1..value.Len(contents)) if value.Len(g.Values) > 1])
end

defn finds(way, contents, dir)
  (** Does a way of finding copies give the groups of a folder made of these texts? *)
  written(contents, dir)?
  value.Equal(way(dir)?, copies(contents, dir))
end

folders = gen.List(gen.Text(max = 3, chars = "ab"), max = 12)   (** The texts of a folder: short, so that many have one size. *)

isSizeEnough() = test.ForAll(cs -> finds(bySize, cs, "$(test.Temp())/case"), folders)
isNaiveRight() = test.ForAll(cs -> finds(naive, cs, "$(test.Temp())/case"), folders)
isDuplicatesRight() = test.ForAll(cs -> finds(Duplicates, cs, "$(test.Temp())/case"), folders)
isOneSizeTwoTexts() = finds(Duplicates, ["aa", "ba"], "$(test.Temp())/case")

finds(bySize, ["aa", "ba"], "case") -->
finds(Duplicates, ["aa", "ba"], "case") -->
finds(naive, ["aa", "ba"], "case") -->
```

### Des propriétés sur des dossiers générés

Les quatre fonctions dont le nom commence par `is` sont les tests de `dupes.test.ce` : ce fichier, après les fonctions
des étapes précédentes. Trois d'entre elles sont des propriétés : [test.ForAll] fabrique 100 dossiers avec le générateur
`folders`, chacun une liste d'au plus 12 textes courts faits de `a` et de `b`, pour que beaucoup de textes aient une même
taille et que beaucoup soient égaux, le texte vide aussi ; puis il vérifie la façon sur chacun, contre les groupes connus
à partir des textes. C'est la méthode de QuickCheck, de Koen Claessen et John Hughes (2000), comme le montre le chapitre
[Tests](tests.md#les-propriétés). `cesia test` les lance, et le dépôt de Cesia lance ce fichier à chacune de ses
vérifications, sur les deux chemins du moteur :

```text
$ cesia test --seed 1 dupes.test.ce
dupes.test.ce:102: isSizeEnough failed at case 4 of 100, shrunk from 17 draws to 13:
  cs = ["aa", "ba"]
  finds(bySize, cs, "$(test.Temp())/case")
  | bySize = function bySize
  | cs = ["aa", "ba"]
  | test.Temp() = "/tmp/cesia-test-3563511-9b43ea/1-isSizeEnough"
  saved, tried first next time; these cases again: cesia test dupes.test.ce --seed 1
  Its Temp folder is kept: /tmp/cesia-test-3563511-9b43ea/1-isSizeEnough
3 passed, 1 failed, seed 1
```

Le raccourci échoue, comme il le doit : cet échec est la preuve que le test peut voir l'erreur. Avec les seeds 1 à 8, il
échoue chaque fois, du 4e au 14e dossier, et est réduit chaque fois à deux fichiers d'une même taille : `a` et `b`, dans
un ordre ou dans l'autre, `aa` et `ba`, ou `aaa` et `aba`. La première façon et `Duplicates` tiennent sur les 100
dossiers de chacun des seeds 1 à 50, 5 000 dossiers pour chacune, et aussi sur les seeds 1 à 20 avec `--no-spec`, le
moteur sans ses versions par type. Le test a aussi trouvé une erreur à lui pendant qu'on l'écrivait : une liste vide de
textes ne fabriquait aucun dossier, et [sys.Walk] échouait dessus, ce qui explique pourquoi `written` crée d'abord le
dossier.

### La borne calculée

```cesia
bound(k, bits) = k * (k - 1) / 2 / 2.0 ^ bits   (** The birthday bound, for k different files and a digest of bits bits. *)
bound(1000000, 256) -->
bound(1000000, 64) -->
bound(1000000000, 256) -->
bound(1000000, 256) * 1e9 * 3600 * 24 * 365.25 * 1000 -->
```

Pour un million de fichiers différents d'une même taille, la probabilité que BLAKE2b-256 en mette deux dans un même
groupe est au plus de $4{,}3 \times 10^{-66}$ ; pour un milliard, de $4{,}3 \times 10^{-60}$. Lancé un milliard de fois par seconde
pendant mille ans, sur un million de fichiers chaque fois, la probabilité qu'un run se trompe un jour est au plus la
somme sur les runs, l'union bound encore : $1{,}4 \times 10^{-46}$. La borne repose sur une seule supposition : que les
digests de fichiers que personne n'a fabriqués contre BLAKE2b se comportent comme des tirages au hasard. Face à des
fichiers fabriqués exprès, la garantie est la sécurité contre les collisions de $2^{128}$.

### La vitesse, avant et après, à côté de Python

`bench/dupes.py` fait la même chose en Python, comme l'écrit un programmeur Python : `os.walk`, puis un groupement par
taille, puis `hashlib.file_digest` avec BLAKE2b de 32 octets, qui lit chaque fichier par morceaux. On vérifie que sa
sortie est la même que celle de Cesia, ligne pour ligne. Le côté Cesia est `bench/dupes.ce`, qui contient les fonctions
de ce chapitre :

```text
(** The ways of the chapter "Solving a real problem" of the book, timed on a folder:
      cesia run --allow read bench/dupes.ce naive|memory|duplicates FOLDER
    Each prints the groups of copies, one on a line, its paths cut by tabs, as bench/dupes.py does. memory is naive with
    each file read once, then kept in memory. *)
use std/sys
use std/io
use std/text
use std/list
use std/value
use std/result
use std/cesia

defn main()
  way = sys.Args[1]
  folder = sys.Args[2]
  groups = if way == "naive"
    naive(folder)?
  else if way == "memory"
    naive(folder, read = readOnce(folder)?)?
  else
    Duplicates(folder)?
  end
  for g in groups
    io.Print(text.Join("\t", g))
  end
  result.Ok(missing)
end

(* plainFiles, sorted, naive, readOnce and Duplicates, as above *)

result.Unwrap(main())
```

Médianes de 11 runs et leur intervalle à 95 %, en millisecondes, avec un cache warm ; en gras, le plus rapide de
`Duplicates` et de Python, quand leurs intervalles ne se touchent pas et qu'ils diffèrent de plus de 2 % :

| Dossier de photos | `naive`, avant | `Duplicates`, après | Python |
|---:|---:|---:|---:|
| 100 fichiers | 1 107 (1 094 à 1 126) | **17,2** (17,0 à 17,4) | 27,4 (26,8 à 27,9) |
| 200 fichiers | 3 204 (3 172 à 3 391) | **25,6** (25,0 à 26,0) | 32,6 (31,8 à 33,1) |
| 400 fichiers | 16 087 (15 989 à 16 231) | 40,3 (39,8 à 40,6) | 41,0 (40,7 à 41,5) |
| 1 000 fichiers, 192 MB | | 94,3 (93,6 à 97,1) | **70,4** (69,8 à 70,9) |

De 16,1 s à 40 ms à 400 fichiers : 400 fois plus rapide, et l'écart grandit avec le dossier, puisqu'un coût est en
$O(n^2)$ et l'autre environ en $O(n)$. `Duplicates` y lit 59 des 400 fichiers, 13,2 MB sur 80,7 : les copies, puisque
deux photos différentes de ces dossiers n'avaient jamais la même taille. Son pic de mémoire, tel que le système le
compte, reste sous 16 MB, comme celui de Python : le plus gros fichier qu'il tient fait 1 MiB.

Le pire cas pour la taille, et un cache cold. Sur 1 000 fichiers d'exactement 64 KiB, la taille ne dit rien et chaque
fichier est hashé. *Cold* veut dire qu'avant chaque run, chaque fichier du dossier est retiré du page cache (avec
`posix_fadvise`, et `fincore` montre qu'il ne reste aucune de leurs pages), pour que ses octets viennent du disque :

| Dossier | Cache | `Duplicates` | Python |
|---|---|---:|---:|
| 1 000 photos | cold | 341 (326 à 371) | 319 (295 à 335) |
| 1 000 fichiers de 64 KiB | warm | 161,5 (161,0 à 166,3) | **129,2** (128,3 à 131,0) |
| 1 000 fichiers de 64 KiB | cold | 1 126 (1 045 à 1 293) | 1 118 (1 066 à 1 210) |

Où chacun gagne, et pourquoi, mesuré plutôt que deviné :

- Sur un petit dossier, Cesia gagne, 17 ms contre 27 à 100 fichiers : il démarre en 3,2 ms là où Python en prend 14,4,
  les médianes de 21 runs d'un programme qui affiche un nombre.
- Au-delà de 400 fichiers, Python gagne, d'un tiers sur 1 000 photos et d'un quart sur 1 000 fichiers d'une même taille.
  La cause est le hash : BLAKE2b-256 de 64 MiB tenus en mémoire prend 75,6 ms en Python et 107,2 ms en Cesia, les
  médianes de 11 essais, soit 867 MB/s contre 612. Python 3.14 prend son BLAKE2b dans HACL*, une bibliothèque
  cryptographique dont le code est prouvé correct par une machine, dans une version pour AVX2, les instructions
  vectorielles de 256 bits des processeurs Intel, que celui-ci possède : son module en contient 1 681. Celui de Cesia est
  le C portable du runtime d'OCaml (ce qui accompagne un programme OCaml pendant qu'il tourne), dont la fonction de
  compression, désassemblée, fait son arithmétique sans aucune. Sur 1 000 fichiers d'une même taille, cet écart fait
  31,6 ms des 32,3 qui les séparent. Le parcours et les tailles coûtent la même chose dans les deux, 3,5 ms pour 1 000
  fichiers une fois le démarrage retiré : 6,7 ms pour Cesia et 17,9 pour Python, démarrage compris, les médianes de 21
  runs. Donc, sur 1 000 fichiers d'une même taille, Cesia gagne 11 ms au démarrage, en perd 32 dans le hash, et 12 de
  plus dans la lecture et le groupement, que ce chapitre n'a pas décomposés davantage : Python lit chaque fichier par
  morceaux dans un seul buffer (une zone de mémoire de travail), là où Cesia fabrique un texte de chaque fichier entier.
- Avec un cache cold, le disque décide : les deux intervalles se chevauchent, donc aucune différence entre eux n'est
  démontrée.

En bref, à côté de Python : Cesia est plus rapide sur les petits dossiers, ils sont à égalité à 400 fichiers, et le hash
de Python le rend plus rapide sur les plus grands, jusqu'à ce que le disque les rende égaux. Une version vectorielle de
BLAKE2b dans Cesia comblerait l'écart : elle est dans [ce qui reste](#7-ce-qui-reste).

fdupes et jdupes ne sont pas installés sur cette machine : ils ne sont donc comparés ici que par leur documentation,
plus haut, et non par un temps.

### Les threats to validity

Une mesure peut être fausse sans aucune erreur en vue : Todd Mytkowicz, Amer Diwan, Matthias Hauswirth et Peter F.
Sweeney ont montré en 2009 que la taille des variables d'environnement, ou l'ordre de l'édition de liens d'un programme
(l'étape qui assemble ses morceaux compilés), peut changer son temps assez pour renverser une conclusion. Une *threat to
validity* (une menace sur la validité) est une telle cause, qui pourrait rendre la preuve fausse. Chacune ici, et ce qui
a été fait contre elle :

- **Les autres programmes de la machine.** D'autres travaux tournaient dessus, sous un lock partagé (ce qui réserve la
  machine à une seule tâche lourde à la fois et fait attendre les autres) ; la charge moyenne était d'environ 1 pendant
  les runs. Les programmes passaient à tour de rôle, pour qu'une minute plus lente tombe sur tous, et les intervalles
  montrent le bruit qui restait : chaque intervalle warm tient à 6 % de sa médiane sauf un, à 10 %, et les cold à 15 %,
  le disque ajoutant le sien.
- **L'écriture des dossiers.** La première série de runs a commencé juste après l'écriture des dossiers, pendant que le
  système les écrivait encore sur le disque, et ses temps à 100 fichiers s'étalaient de 17 à 267 ms. Cette série a été
  jetée : les nombres ci-dessus viennent d'une deuxième, qui a attendu `sync`, avec 60 kB restant à écrire.
- **Un cache warm ou cold.** Un utilisateur qui lance le programme deux fois obtient les temps warm ; le premier run après
  un redémarrage obtient les temps cold, tous deux mesurés. Cold ne vise ici que les octets des fichiers : les noms et
  les tailles du dossier restent en mémoire, si bien qu'un premier run après un redémarrage paierait aussi le parcours sur
  le disque. Un disque à plateaux, qui déplace sa tête pour chaque fichier, rendrait chaque temps cold plus long ; il n'a
  pas été mesuré, puisque les dossiers sont sur un SSD.
- **La forme du dossier.** Elle décide de ce qui est lu. Les photos partagent rarement une taille, donc `Duplicates` ne
  lit à peu près que les copies ; les fichiers d'une même taille sont le pire cas, et les deux ont été mesurés. Un vrai
  dossier se trouve entre les deux, et sa part de copies, une sur dix ici, change la lecture en proportion.
- **Des octets au hasard.** Une lecture et BLAKE2b prennent le même temps quels que soient les octets, et le système de
  fichiers ici ne compresse rien, donc des octets au hasard tiennent lieu de photos, qui sont déjà compressées. Les
  dossiers sont refaits, à l'identique, à partir du même seed, par `bench/dupes-folder.py`.
- **Le démarrage d'un processus.** Chaque temps le contient, quelques millisecondes pour Cesia et plus pour Python : ce
  qu'attend un utilisateur, et la raison de la plus grande part de l'écart à 100 fichiers, dite plus haut.
- **Le dispositif lui-même.** L'environnement et l'ordre de l'édition de liens n'ont pas été variés, donc un biais du
  genre de celui que Mytkowicz et ses coauteurs ont trouvé peut rester dans chaque nombre. Les conclusions reposent sur
  des rapports de 1,25 à 400 ; la seule comparaison serrée, Cesia et Python à 400 fichiers, à 2 % l'un de l'autre, est
  appelée une égalité, pas une victoire.
- **La même réponse.** Chaque run a affiché les mêmes groupes que le premier run du premier programme, ligne pour ligne ;
  une réponse différente aurait arrêté la mesure.

## 7. Ce qui reste

La solution répond à la question pour les dossiers sur lesquels elle a été prouvée. Ses limites, dites simplement :

- **Les hard links.** Un [hard link](glossary.md#hard-and-symbolic-links) est un deuxième nom du même fichier, pas une
  copie : effacer un nom ne libère aucune place. [sys.Stat] ne dit pas à quel fichier mène un nom, donc deux noms d'un
  même fichier sont donnés comme des doublons. Ils contiennent bien les mêmes octets, donc la réponse reste correcte,
  mais elle peut tromper qui efface. fdupes et jdupes traitent par défaut ces noms comme des non-doublons.
- **Les symbolic links** (de petits fichiers qui tiennent un chemin, que le système suit) sont laissés de côté : un lien
  n'est pas une copie, et en suivre un pourrait sortir du dossier ou tourner en boucle.
- **Les fichiers qui changent pendant qu'on les lit.** La taille vient de [sys.Stat], les octets de [sys.Read] plus
  tard : un fichier qui grandit entre les deux est hashé tel qu'il est au moment de sa lecture. La réponse ne décrit le
  dossier à aucun instant précis ; pour un dossier en usage, relancez le programme, ou comparez la taille lue avec la
  taille vue.
- **Les permissions.** Un fichier que Cesia n'a pas le droit de lire, ou que le système refuse, arrête le programme avec
  un `Err` qui le nomme : `?` le transmet. Une version qui saute ces fichiers et les liste à la fin ne coûte que quelques
  lignes de plus.
- **La mémoire.** [sys.Read] tient un fichier entier en mémoire, donc un film de 4 GB demande 4 GB d'un coup.
  `file_digest` de Python lit par morceaux. Cesia n'a pas encore de lecture d'un fichier par morceaux ; avec elle, le
  hash lirait un morceau à la fois, et les 4 premiers KiB de jdupes s'appliqueraient aussi.
- **La vitesse du hash.** Le BLAKE2b de Cesia, le C portable du runtime d'OCaml, hashe 612 MB par seconde sur cette
  machine, là où celui de Python, avec AVX2, atteint 867 : au-delà de quelques centaines de fichiers, Python est d'un
  quart à un tiers plus rapide. Une version avec des instructions vectorielles comblerait cet écart.
- **Les fichiers vides** sont des doublons les uns des autres, d'après la définition, et sont groupés. jdupes les laisse
  de côté sauf si on le demande, avec `-z` ; fdupes les garde sauf si on le demande, avec `-n`.
- **Les fichiers d'un attaquant.** Face à des fichiers fabriqués pour entrer en collision, la preuve n'est plus la borne
  mais la sécurité de BLAKE2b contre les collisions ; comparer les octets de chaque groupe à la fin, comme le fait
  fdupes, la rendrait inconditionnelle, pour une lecture de plus de chaque copie.
- **Les quasi-doublons**, une photo et sa version réduite, sont un autre problème, mis en dehors dès l'étape 1.

## Pour aller plus loin

- George Pólya, *How to Solve It*, 1945, et le Heilmeier catechism de la DARPA : énoncer un problème ; Karl Popper, *The
  Logic of Scientific Discovery*, 1934 : une hypothèse qui peut être réfutée.
- Raj Jain, *The Art of Computer Systems Performance Analysis*, 1991 ; Andy Georges, Dries Buytaert et Lieven Eeckhout,
  *Statistically Rigorous Java Performance Evaluation*, 2007 ; Tomas Kalibera et Richard Jones, *Rigorous Benchmarking in
  Reasonable Time*, 2013 ; Jean-Yves Le Boudec, *Performance Evaluation of Computer and Communication Systems*, 2010 :
  mesurer.
- Andreas Zeller et Ralf Hildebrandt, *Simplifying and Isolating Failure-Inducing Input*, 2002 : réduire un échec
  jusqu'à sa cause.
- Jean-Philippe Aumasson et d'autres, *BLAKE2: Simpler, Smaller, Fast as MD5*, 2013, et la RFC 7693 ; Menezes, van
  Oorschot et Vanstone, *Handbook of Applied Cryptography*, 1996 ; Xiaoyun Wang et Hongbo Yu, *How to Break MD5 and
  Other Hash Functions*, 2005 : le hash et sa borne ; Jean-Karim Zinzindohoué et d'autres, *HACL\*: A Verified Modern
  Cryptographic Library*, 2017 : le BLAKE2b de Python.
- Todd Mytkowicz et d'autres, *Producing Wrong Data Without Doing Anything Obviously Wrong!*, 2009 : les threats to
  validity.
- La page de manuel de fdupes et le README de jdupes.

Chacun avec son lien dans [Références](references.md#résoudre-un-problème).

## La suite

Vous savez aller d'un problème à la preuve qu'il est résolu. Le chapitre suivant,
[Comment Cesia fonctionne](internals.md), regarde à l'intérieur de Cesia lui-même.
