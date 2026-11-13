# Tests

Dans ce chapitre, vous vérifiez que votre code fait ce qu'il doit, et continue de le faire à mesure que vous le changez.
Cesia a deux sortes de tests : des exemples écrits dans la documentation d'une fonction, et des fonctions de test dans des
fichiers `.test.ce`, qui peuvent essayer une règle sur beaucoup de cas générés et comparer une valeur à un snapshot gardé
(une copie de la valeur, rangée à côté du test). `cesia test` les lance tous. Puis vous documentez votre code, et vous en
construisez un site comme celui-ci.

## Des exemples dans la documentation

Un commentaire qui commence par `(**` documente ce à quoi il appartient. Dans un `defn`, il vient en premier. Un exemple
qu'il contient, indenté, avec `-->` et la valeur qu'il doit donner, est un test, un [doctest](glossary.md#doctest) :

```cesia
use std/math
defn WithTax(price Number) Number
  (** The price with 20% of tax, to the cent.

        WithTax(10.0) --> 12.0
        WithTax(0.99) --> 1.19 *)
  cents(price * 1.2)
end

cents(x) = math.Round(x * 100) / 100
WithTax(0.99) -->
```

### Quand un exemple échoue

L'exemple dit au lecteur ce que fait la fonction, et `cesia test` vérifie qu'elle le fait toujours. Quand la valeur n'est
pas celle qui est écrite, `cesia test` nomme le fichier, la ligne, et ce qu'il a obtenu :

```text
src/prices/tax.ce:7: WithTax(0.99) --> 1.2, got 1.19
3 passed, 1 failed
```

`--> error` dit que l'appel doit s'arrêter sur une erreur.

## Les fonctions de test

Une fonction de test a un nom qui commence par `is` et une majuscule, aucun paramètre, et donne `true` quand tout va bien.
Elle est privée : elle reste donc dans son package (son dossier de fichiers .ce). Les fonctions de test se trouvent dans un
fichier dont le nom finit par `.test.ce`, à côté du code qu'elles testent : `tax.ce` et `tax.test.ce`. Un tel fichier voit
les noms privés de son package, et ne fait pas partie du programme.

```cesia
use std/bug
isZeroStaysZero() = WithTax(0) == 0
defn isRoundsToCents()
  bug.Assert(WithTax(1.234) == 1.48, "1.234 rounds down")
  WithTax(1.235) == 1.48
end
isZeroStaysZero() -->
isRoundsToCents() -->
```

Un test qui donne `false` échoue, et un test qui s'arrête aussi : un [bug.Assert] qui est faux, un bug. [bug.Assert] avec
un message dit quelle partie d'un long test a mal tourné.

### Quand un test échoue

Un test qui a échoué montre ce qu'il a comparé, et la valeur de chaque appel, de chaque champ et de chaque variable qu'il
contient, tels qu'ils étaient pendant cette exécution. Un test dont les parties sont jointes par `and`, `or`, `not` ou
[list.All] nomme la partie qui a échoué :

```text
src/shop/cart.test.ce:4: isTotal failed
  shop.Total(cart) == 30
  | shop.Total(cart) = 27.0
  | cart = Cart(Items = [{Price: 10, Qty: 3}], Discount = 0.1)
src/shop/cart.test.ce:6: isReceipt failed, part 2 of 3
  r.Tax == 2.7
  | r.Tax = 2.6999999999999997
  | the same float but for its last bits: math.Near(r.Tax, 2.7)?
```

Deux listes, maps (des valeurs rangées sous des clés) ou structs (des formes déclarées, aux champs nommés) qui diffèrent
montrent où elles diffèrent d'abord, comme `first difference: [3]: 6 vs 7` ou `first difference: .B.C: 2 vs 3` (la
première différence), et deux textes le caractère où ils se séparent. Un test qui s'arrête dit où, avec les appels qui y
ont mené. Un test peut utiliser `?` : l'Err d'un `?` le fait échouer, et la ligne de ce `?` est nommée.

### Near

Les floats (les nombres à virgule) sortent rarement exactement comme ils sont écrits : `0.1 + 0.2` n'est pas `0.3`.
[math.Near] compare avec une tolérance, la plus grande de deux : `rel` fois le plus grand des deux nombres, ou `abs` ; il
compare élément par élément pour les arrays, les maps et les structs. Contre 0, seul `abs` aide :

```cesia
use std/math
math.Near(0.1 + 0.2, 0.3) -->
math.Near([1.0, 2.0], [1.0, 2.0 + 1e-12]) -->
math.Near(1e-12, 0) -->
math.Near(1e-12, 0, abs = 1e-9) -->
```

Elle appartient à std/math : un programme peut donc s'en servir aussi, comme une boucle qui s'arrête quand une valeur se
stabilise.

## Les propriétés

Une fonction de test vérifie les cas auxquels vous avez pensé. Une propriété vérifie une règle sur beaucoup de cas que Cesia
fabrique, ce qu'on appelle le *property-based testing* (le test par propriétés) : QuickCheck l'a lancé en Haskell en 2000,
et Hypothesis l'a apporté à Python. [test.ForAll] prend la règle, une fonction qui donne `true`, et un générateur de
std/gen, qui fabrique les cas. Une solution rapide comparée à une solution lente et sûre est la plus utile de toutes les
règles :

```cesia norun
use std/test
use std/gen
use std/list
use std/value
radixSort(xs) = list.Sort(xs)   (* stands for your fast solution *)
isSortAgrees() = test.ForAll(xs -> value.Equal(radixSort(xs), list.Sort(xs)), gen.List(gen.Int()))
```

Il essaie 100 cas, les petits d'abord. Quand l'un échoue, Cesia le rend plus petit tant qu'il échoue encore, et montre le
plus petit : c'est le *shrinking* (la réduction). Un cas est fabriqué à partir des nombres que son générateur a tirés, sa
*tape* (la bande de ses tirages), et Cesia réduit la tape, moins de tirages et de plus petits, puis refait le cas à partir
d'elle, comme le fait Hypothesis : le cas plus petit vient toujours du même générateur, c'est donc toujours un cas que le
générateur aurait pu fabriquer, et une struct dont les champs ont des règles reste valide pendant qu'elle se réduit.

```text
src/shop/sort.test.ce:6: isSortAgrees failed at case 41 of 100, shrunk from 33 draws to 9:
  xs = [-1, -2]
  value.Equal(radixSort(xs), list.Sort(xs))
  | radixSort(xs) = [-1, -2]
  | list.Sort(xs) = [-2, -1]
  | first difference: [1]: -1 vs -2
  saved, tried first next time; these cases again: cesia test src/shop/sort.test.ce --seed 4127
```

L'échec est gardé dans `.cesia/failures/`, que `cesia new` tient hors de git, et essayé en premier à l'exécution suivante,
jusqu'à ce qu'il passe. Chaque exécution essaie de nouveaux cas à partir d'un nouveau [seed](glossary.md#seed) (le nombre
dont part le générateur) ; `--seed` redonne les cas d'une exécution, et les nombres de
[std/random](data.md#les-mêmes-nombres-une-seconde-fois) aussi, puisqu'ils viennent du même seed.

Les générateurs de std/gen sont [gen.Int] et [gen.Float] avec leurs bornes, [gen.Bool], [gen.Text], [gen.List],
[gen.Dict], [gen.Pick] d'une liste, [gen.Map] d'une fonction, [gen.Then], et [gen.Of], qui fabrique une struct à partir des
types de ses champs, ou une map ou une liste à partir de générateurs :

```cesia norun
use std/test
use std/gen
use std/list
total(lines) = list.Sum([l.Qty * l.Price for l in lines])
orders = gen.List(gen.Of({Item: gen.Text(), Qty: gen.Int(1, 99), Price: gen.Float(0, 100)}))
isNeverNegative() = test.ForAll(os -> total(os) >= 0, orders)
```

Pour une struct dont les champs ont des types, comme `Item Text`, `Qty Int` et `Price Float`, `gen.Of(Order)` suffit, et
`gen.Of(Order, with = {Qty: gen.Int(1, 99)})` donne le générateur d'un champ par son nom.

## Les snapshots

Certains résultats sont longs à écrire à la main : une page, un rapport. [test.Snapshot] garde le texte d'une valeur à côté
du test, dans `page.test.snap` pour `page.test.ce`, et compare la valeur à ce texte à chaque exécution :

```cesia norun
use std/test
page(name) = "<h1>$name</h1>\n<p>Total: 3</p>\n"
isPage() = test.Snapshot(page("Ana"))
```

C'est le *snapshot testing*, comme Jest le fait pour JavaScript, ou un *golden test* quand le texte est une sortie
entière. Un nouveau snapshot échoue et montre son texte : lisez-le, puis `cesia test --update` l'accepte. Un snapshot
changé montre les lignes qui ont changé. Le fichier `.snap` va dans git, où une review (la relecture d'un changement par
quelqu'un d'autre) voit chaque changement.

## Ce qu'un test peut faire

Un test lit les fichiers de son projet, et n'écrit que dans le dossier que lui donne [test.Temp] : supprimé quand le test
passe, gardé et nommé quand il échoue. Il peut écouter sur cette machine, et ne se connecter qu'à ses propres listeners
(les sockets qui acceptent les connexions) : le test d'un serveur démarre donc le serveur lui-même, sur un port libre :

```cesia norun
use std/net
use std/http
use std/fiber
defn isHello()
  l = net.Listen(0)?
  fiber.Spawn(() -> http.Serve(http.App() then http.AnyMethod("*", r -> {Status: 200, Body: "hi"}), listener = l))
  reply = http.Fetch("http://localhost:$(net.Port(l))/")?
  reply.Status == 200 and reply.Body == "hi"
end
```

C'est la permission `net=own`. Un test n'atteint que les listeners qu'il a ouverts, et seulement tant qu'ils sont ouverts :
une fois qu'il en ferme un, son port est hors d'atteinte, puisqu'un autre programme peut le prendre. Il les nomme par une
adresse de cette machine écrite en entier, comme `127.0.0.1` ou `::1`, ou par `localhost`, et il ne fait résoudre aucun
autre nom (demander son adresse au DNS), puisqu'une résolution envoie déjà le nom hors de la machine. Un test qui a besoin
d'un serveur du réseau l'obtient par son nom dans le `allow` de `[test]`, comme `net=example.com:443`.

Un test a 10 secondes, et ses fibers, ses sockets et ses serveurs s'arrêtent avec lui, comme les programmes qu'il a
lancés avec [sys.Start] ou [sys.Run] : à sa fin, qu'il ait réussi, échoué ou dépassé son temps, chacun de ceux qui
tournent encore reçoit le signal TERM, puis KILL une seconde plus tard. `[test]` dans `cesia.toml` change les 10 secondes
pour tout le projet :

```toml
[test]
allow = ["exec=git"]
timeout = "30"
serial = ["tests/db"]
skip = ["tests/e2e"]
```

`allow` ajoute des permissions, comme le fait `--allow` ; `timeout` est en secondes, écrit comme un texte ; `serial` nomme
les fichiers et les dossiers qui partagent quelque chose, comme une base de données, et qui tournent seuls, après les
autres ; `skip` nomme ceux que `cesia test` laisse de côté, sauf si son chemin est dans l'un d'eux, comme des tests de
bout en bout qui ont besoin d'un serveur lancé avant : `cesia test` lance les autres, et `cesia test tests/e2e` ceux-là.

## cesia test

`cesia test` lance chaque exemple et chaque fonction de test du projet, et laisse de côté `std/` et `deps/`. Avec un
chemin, il lance ceux d'un dossier ou d'un fichier, et `file.ce:isName` lance un seul test ; un nom qu'aucun test du
fichier ne porte est alors un échec, pour qu'une faute de frappe ne puisse pas passer :

```bash
cesia test
cesia test src/prices
cesia test src/prices/tax.test.ce
cesia test src/prices/tax.test.ce:isRoundsToCents
```

Il affiche chaque échec avec sa place, puis combien de tests sont passés et combien ont échoué, et termine avec le code 1
quand l'un a échoué : un script ou une CI (un service qui lance les tests à chaque changement poussé) peut donc s'arrêter
dessus. Un test qui appelle [sys.Exit], à travers le code qu'il teste, échoue avec son propre message, et l'exécution des
tests continue : un test dit son verdict par sa valeur, et seule l'exécution entière termine le programme. Chaque dossier
est un package : ses exemples et ses tests tournent donc ensemble. Les fichiers et les packages tournent côte à côte,
chacun dans un processus à lui : un crash ou un test qui ne finit pas n'arrête que le sien, et il est nommé.

| Option | Ce qu'elle fait |
|---|---|
| `--seed N` | redonne les cas et les nombres au hasard d'une exécution précédente |
| `--cases N` | combien de cas chaque propriété essaie, 100 par défaut |
| `--update` | accepte les snapshots nouveaux et changés |
| `--allow LIST` | des permissions de plus, au-delà de ce qu'un test peut faire par défaut |

### Sans les versions par type

`cesia test --no-spec` les relance sans les versions de chaque fonction que Cesia fabrique pour les types qu'il voit. Les
résultats doivent être les mêmes : une différence est un bug de Cesia, qui vaut la peine d'être signalé.

## Documenter votre code

Le premier `(** *)` d'un fichier, avant tout code, dit à quoi sert son package. Une définition courte a son texte au bout
de sa ligne, un champ ou un paramètre aussi :

```cesia
use std/list
struct Item
  (** A line of an order. *)
  Product Text    (** what is sold *)
  Units Int       (** how many *)
end

Total(items) = list.Sum([i.Units for i in items])   (** How many units an order holds. *)
Total([Item("bread", 2), Item("cake", 1)]) -->
```

Chaque nom public demande son texte : un nom avec une majuscule est une promesse faite au code qui l'utilise.

### Lire les textes

`cesia doc` montre les textes depuis la ligne de commande, et [cesia.Doc] fait de même depuis un programme :

```bash
cesia doc src/prices
cesia doc prices.WithTax
```

```cesia
use std/cesia
cesia.Doc(Total) -->
```

## Un site pour votre projet

`cesia doc --site` construit un site du projet, comme celui-ci : une page pour chaque module et chaque nom public, avec
une recherche. La référence contient aussi les modules de `std/`, et le bandeau du haut nomme le Cesia qui a fait le
site : le mot Cesia et sa version (le site de Cesia lui-même montre la version seule). Avec `--open`, il ouvre le site
dans le navigateur. Ses pages sont écrites dans `site/`, que `cesia new`
tient hors de git.

```bash
cesia doc --site --open
```

### Les livres

Un projet peut aussi avoir des livres, dans `docs/` : chaque dossier de pages Markdown qui s'y trouve est un livre, dont
l'`index.md` mène à ses chapitres dans leur ordre. `docs/book/` est l'accueil du site, et un autre dossier, comme
`docs/guides/`, est un livre à côté. Un dossier `files/` dans un livre contient les fichiers que lisent ses exemples.
Chaque bloc `cesia` d'une page tourne quand le site est construit, et ce qu'il affiche est écrit en dessous. Les blocs
d'une page forment un seul programme, dans leur ordre : un nom donné dans un bloc est donc connu dans le suivant.

Les mots qui suivent `cesia` sur la première ligne d'un bloc changent ce qu'on en fait :

| Mot | Ce qu'il fait |
|---|---|
| `norun` | montre le bloc sans le lancer : un serveur, un programme qui attend une entrée. Il est tout de même vérifié, et des blocs norun qui se suivent forment un seul programme : un nom donné dans l'un est donc connu dans le suivant |
| `fails` | le bloc doit s'arrêter sur une erreur, dont le message est montré en dessous ; un bloc qui n'échoue pas arrête le build (la construction du site) |
| `allow=read,write,net,net=own,net=:PORT,ffi=m` | lance le bloc avec ces permissions ; aucune autre n'est donnée |
| `output=md` | ce qu'affiche le bloc est du Markdown, montré comme une partie de la page |
| `fold=code`, `fold=output` | le code, ou ce qu'il a affiché, est replié, et s'ouvre d'un clic |
| `hide=code`, `hide=output` | le code, ou ce qu'il a affiché, n'est pas montré |

Un bloc `toml` doit être un `cesia.toml` valide, sauf s'il porte lui aussi `norun` : c'est alors le fichier d'un autre
programme, comme celui d'un serveur.

Ce livre est construit ainsi, si bien que ses exemples ne peuvent pas s'écarter du langage : un bloc qui donne une autre
valeur arrête le build. Chaque page tourne comme un programme du projet, depuis `.cesia/site/`, que `cesia new` tient hors
de git : ses blocs peuvent utiliser les packages de `src/` et de `deps/`, où que le site soit écrit.

```text
docs/
  book/
    index.md
    first-steps.md
    files/
  guides/
    index.md
```

### Tabs in other languages

A block of `python`, `r` or `matlab` right after a `cesia` block, with nothing between them, is the same example in that
language: the site shows it as a tab beside the Cesia one, Cesia | Python | R | MATLAB, which a click or the arrow keys
switch, with no script. The tabs follow their block in that order, each once, with no word after the language, and a
block marked `fails` has none. This source:

````markdown
```cesia
use std/math
math.Sqrt(2.0) -->
```

```python
import math
print(math.sqrt(2.0))
```
````

with an `r` and a `matlab` block after it, shows:

```cesia
use std/math
math.Sqrt(2.0) -->
```

```python
import math
print(math.sqrt(2.0))
```

```r
print(sqrt(2))
```

```matlab
disp(sqrt(2))
```

Each tab of Cesia's own book runs, and must print what its cesia block shows: the value of each `-->` and what the block
prints, in their order. `tools/check.sh` and the CI of the site run `tools/tabs.ce`, which compares the two one value at a
time: texts exactly, `True` and `true` alike, and numbers to the digits the tab shows. A number Cesia shows is exact,
the shortest text of its float; a number the tab prints stands for those it rounds, and Cesia's must be one of them, give
or take 1e-14 of its size. So R's `1.414214` and Octave's `1.4142` are `1.4142135623730951`, `0.54` is not `0.5`, and
`3.0` is `3`. Python runs with numpy, scipy,
pandas and matplotlib, R with its base packages, and the MATLAB tab in GNU Octave, which runs MATLAB code with no licence.
Each tab runs alone, with the files of its book, so it holds its imports and its data; with no network, at most 1 GiB of
memory and 30 seconds.

### Formules

Une formule s'écrit en TeX entre deux `$` dans une ligne, ou entre deux lignes qui ne contiennent que `$$`, comme un
paragraphe à part : c'est aussi la syntaxe que GitHub affiche. Le build l'écrit en MathML (la façon d'écrire une formule
dans une page web, que les navigateurs affichent eux-mêmes, sans script), dans la police STIX Two Math, que seule une page
qui contient une formule télécharge. Cette source :

```markdown
A search in a sorted array of $n$ keys costs $O(\log n)$, and the birthday bound is

$$
P(\text{some collision among } k \text{ files}) \le \frac{k(k - 1)}{2} \times 2^{-256}
$$
```

donne, ici en français : une recherche dans un array trié de $n$ clés coûte $O(\log n)$, et la birthday bound (la borne
des anniversaires) est

$$
P(\text{une collision parmi } k \text{ fichiers}) \le \frac{k(k - 1)}{2} \times 2^{-256}
$$

Le `$` qui ouvre une formule n'a pas d'espace après lui ; le `$` suivant la ferme, sans espace avant lui ni chiffre après
lui, sur la même ligne, et sans backtick (l'accent grave qui entoure le code) entre les deux. Ainsi « ça coûte $5 et $6 »
ne contient aucune formule, `\$` écrit un dollar, et un `$` dans du code reste du code. Les commandes sont celles du
tableau ; toute autre, ou un caractère comme ≤ écrit tel quel, arrête le build en donnant sa place et ce qu'il faut écrire :
`docs/book/values.md:12: ≤ is no part of a formula: write \le`.

| Sorte | Commandes |
|---|---|
| relations | `\le` `\ge` `\ne` `\approx` `\equiv` `\sim` `\in` `\notin` `\ni` `\subset` `\subseteq` `\to` |
| opérateurs | `\times` `\cdot` `\pm` `\cup` `\cap` `\bmod`, et `+ - = < > / ! , ; : .` |
| parenthèses | `( ) [ ] \|`, `\lceil` `\rceil` `\lfloor` `\rfloor`, `\{` `\}` |
| grec | `\alpha` à `\omega`, `\Gamma` `\Delta` `\Theta` `\Lambda` `\Xi` `\Pi` `\Sigma` `\Phi` `\Psi` `\Omega` |
| fonctions | `\log` `\ln` `\exp` `\min` `\max` `\sin` `\cos`, avec les espaces fines de TeX : $n \log n$ |
| sommes et produits | `\sum` `\prod`, leurs bornes avec `_` et `^`, à côté d'eux dans une ligne, au-dessus et en dessous dans une formule seule sur ses lignes |
| structures | `x_i`, `2^{31}`, `f'`, `\frac{a}{b}`, `\sqrt{x}` |
| mots et noms | `\text{some words}`, en romain ; `\mathit{vlo}`, un nom de plusieurs lettres en italique |
| autres | `\dots` `\infty` `\emptyset` ; les espaces `\,` `\;` `\quad` et `\ ` ; `1{,}000` pour une virgule dans un nombre |

La police est une partie de STIX Two Math 2.13 (du STIX Fonts Project, sous SIL Open Font License 1.1), réduite aux
caractères qu'une formule peut contenir : 74 KB. Le site la garde à côté de sa licence, `math-OFL.txt`.

### Remarques et avertissements

Une citation dont la première ligne est l'une des alertes de GitHub, `[!NOTE]`, `[!TIP]`, `[!IMPORTANT]`, `[!WARNING]` ou
`[!CAUTION]`, est montrée dans la couleur de sa sorte, sous son nom, en français sur le site français (Remarque, Astuce,
Important, Attention, Prudence) :

```markdown
> [!TIP]
> `cesia doc --site --open` builds the site and opens it.
```

donne, ici en français :

> [!TIP]
> `cesia doc --site --open` construit le site et l'ouvre.

### Couleurs

La `color` de la table `[site]` de `cesia.toml` est la couleur du projet, comme `"#3b5bdb"`. Le build en tire les couleurs
des liens, des titres, du bandeau du haut, de la page ouverte dans la colonne de côté, des en-têtes et d'une ligne sur deux
des tableaux, et du code dans une ligne, dans l'apparence claire et dans la sombre. Chaque texte atteint 4,5:1 face à son
fond, le niveau AA des WCAG 2.2 (les règles d'accessibilité du web), d'après la luminance relative qu'elles définissent ; une
couleur qui ne le peut pas, trop claire ou trop pâle, arrête le build en donnant la paire et son rapport. Sans `color`, le
site prend `"#2b5fd9"`.

### Le README

Le `README.md` du projet (le fichier qui le présente, à la racine du dépôt) est une page du site, refaite à partir de lui à
chaque build et montrée dans la colonne de côté : ses liens vers les pages de `docs/`, ou vers un de ses dossiers pour son
index, mènent aux pages du site. Tout autre lien vers un fichier du projet, comme `LICENSE`, ne mène à aucune page du site et
arrête le build : écrivez-le avec son URL complète. Ses blocs `cesia` sont montrés en couleur, jamais lancés.

### Les ids des titres

L'id d'un titre (le nom de sa place dans la page, que donne un lien après son signe #) est celui que GitHub lui donne : en
minuscules, sans ponctuation, chaque espace changée en `-`, et `-1`, `-2` après un titre qui revient. « What's new? »
donne `whats-new`, si bien qu'un lien `page.md#whats-new` mène au même endroit sur GitHub et sur le site. L'id que le site
lui donnait avant, `what-s-new`, ses lettres et ses chiffres joints par des `-`, reste lui aussi sur le titre : un lien
écrit à l'époque y mène toujours.

### Un site en français

`docs/fr/` contient le français des livres, sous les mêmes chemins : `docs/fr/book/values.md` est le français de
`docs/book/values.md`, et `README.fr.md`, à côté de `README.md`, celui du README. Le site a alors une partie française sous
`fr/`, en `<html lang="fr">` : les mêmes pages, les mots propres au site en français, une recherche à elle, et sur chaque
page un choix entre EN et FR qui reste sur la même page. Une page pas encore traduite montre l'anglaise, sous une note qui
le dit. La référence, tirée du code, est en anglais des deux côtés : le site français y renvoie sous le nom « Référence
(en anglais) ».

Une page française garde la structure de sa page anglaise, et le build le vérifie : les mêmes titres, aux mêmes niveaux,
dans le même ordre ; les mêmes blocs de code, octet pour octet, puisque le code s'écrit en anglais ; et les mêmes liens, un
lien vers un titre nommant le titre à la même place de sa page, puisque les ids français sont ceux des titres français. Une
page qui s'en écarte arrête le build en donnant sa place : un changement du texte anglais montre ainsi où le français doit
suivre. Il en va de même d'une page de `docs/fr/` qui n'est le français d'aucune page anglaise. Les blocs étant les mêmes,
ils tournent une fois, pour la page anglaise, et la page française montre ce qu'ils ont affiché sur ses propres lignes.

## Pour aller plus loin

- Koen Claessen et John Hughes, *QuickCheck*, 2000 : des propriétés sur des cas au hasard.
- David R. MacIver et Alastair F. Donaldson, *Test-Case Reduction via Test-Case Generation*, 2020 : réduire les tirages,
  comme le fait [test.ForAll].
- Guy L. Steele Jr., Doug Lea et Christine H. Flood, *Fast Splittable Pseudorandom Number Generators*, 2014 : SplitMix64,
  le générateur derrière les cas et [std/random].

Chacun avec son lien dans [Références](references.md#tests).

## La suite

Vous savez tester et documenter votre code. Le chapitre suivant, [Le prompt et le debugger](debug.md), regarde à
l'intérieur d'un programme pendant qu'il tourne.
