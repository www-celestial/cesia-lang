# Données

Dans ce chapitre, vous travaillez sur beaucoup d'enregistrements à la fois : vous calculez une valeur pour chacun, vous en
gardez certains, vous les groupez, vous les comptez et vous les classez. Puis vous chargez un fichier CSV dans une table de
colonnes et vous posez les mêmes questions en quelques lignes. Les données sont les ventes d'une boulangerie sur quatre
jours, dans `sales.csv`.

> [!NOTE]
> Les exemples de std/frame et de std/num ont des onglets : le même calcul en Python avec pandas et numpy, et en R.
> Chaque onglet tourne quand le livre est vérifié, et affiche ce que montre la version Cesia. Ils n'ont pas d'onglet
> MATLAB : GNU Octave, qui vérifie les onglets MATLAB, n'a pas de tables. Voir
> [Onglets dans d'autres langages](tests.md#onglets-dans-dautres-langages).

## Des enregistrements dans une liste

Une liste de dictionnaires est la table la plus simple : un dictionnaire par ligne, avec les mêmes clés dans chacun.

```cesia
use std/value
sales = [
  {City: "Lyon", Product: "bread", Units: 12, Price: 1.25},
  {City: "Paris", Product: "bread", Units: 30, Price: 1.5},
  {City: "Lyon", Product: "cake", Units: 3, Price: 8.0},
  {City: "Paris", Product: "cake", Units: 5, Price: 9.0},
  {City: "Lille", Product: "bread", Units: 8, Price: 1.25}
]
value.Len(sales) -->
```

## Comprehensions

Une [comprehension](glossary.md#comprehension) construit une liste à partir d'une autre : la valeur pour chaque élément,
puis `for`, puis, si vous le voulez, `if` et une condition.

```cesia
[s.Units * s.Price for s in sales] -->
[s.City for s in sales if s.Units > 6] -->
```

Une comprehension est la forme courte de [list.Map] et de [list.Filter] :

```cesia
use std/list
[s.City for s in sales if s.Units > 6] --> list.Map(s -> s.City, list.Filter(s -> s.Units > 6, sales))
```

## Sommes, comptes et classements

Les fonctions du chapitre sur les listes travaillent sur les valeurs que donne une comprehension. [list.Frequencies] compte
chaque valeur, [list.Unique] garde la première de chacune, et [list.Top] donne les plus grandes, ici selon une clé :

```cesia
list.Sum([s.Units for s in sales]) -->
list.Frequencies([s.City for s in sales]) -->
list.Unique([s.Product for s in sales]) -->
list.Top(2, sales, by = it.Units) -->
```

### MaxBy et Scan

[list.MaxBy] donne l'élément pour lequel une fonction a sa plus grande valeur, et [list.Scan] chaque étape d'un total
cumulé :

```cesia
list.MaxBy(s -> s.Units * s.Price, sales) -->
list.Scan((total, s) -> total + s.Units, 0, sales) -->
```

## Groupes

[list.Group] réunit les éléments qui ont la même clé, dans l'ordre où les clés apparaissent pour la première fois. Chaque
groupe a sa `Key`, et les `Values` qui ont cette clé :

```cesia
list.Group(it.City, sales) then list.Map(g -> {City: g.Key, Rows: value.Len(g.Values)}) -->
```

### Une valeur par groupe

Avec un `summary`, chaque groupe devient une seule valeur : un total par ville tient donc en une ligne.

```cesia
list.Group(it.City, sales, summary = rows -> list.Sum([s.Units for s in rows])) -->
```

### Zip et Zipmap

[list.Zip] met deux listes en paires, élément par élément, et [dict.Zipmap] fait de deux listes un dictionnaire :

```cesia
use std/dict
list.Zip(["Lyon", "Paris"], [15, 35]) -->
dict.Zipmap(["Lyon", "Paris"], [15, 35]) -->
```

## Une table à partir d'un fichier CSV

Pour plus de lignes, [std/frame] garde une table en colonnes, ce qu'on appelle des
[columnar data](glossary.md#columnar-data) : une liste par colonne, et une colonne de nombres rangée sans boxes (sans un
bloc de mémoire à part pour chaque nombre), pour que les sommes et les filtres traitent des colonnes entières d'un coup.
[frame.FromCsv] lit le texte d'un fichier CSV dont la première ligne nomme les colonnes. Une cellule vide vaut `missing`,
et un nombre est lu comme un nombre. Voici `sales.csv` :

```text
day,city,product,units,price
2026-10-01,Lyon,bread,12,1.25
2026-10-01,Paris,bread,30,1.5
2026-10-01,Lyon,cake,3,8.0
2026-10-02,Paris,cake,5,9.0
2026-10-02,Lille,bread,8,1.25
2026-10-02,Lyon,bread,15,1.25
2026-10-03,Paris,bread,22,1.5
2026-10-03,Lille,cake,2,7.5
2026-10-03,Lyon,cake,4,8.0
2026-10-04,Paris,cake,6,9.0
```

Il se lit en une ligne :

```cesia allow=read
use std/sys
use std/frame
use std/io
use std/result
df = frame.FromCsv(result.Unwrap(sys.Read("sales.csv")))
frame.RowCount(df) -->
frame.Columns(df) -->
io.Print(frame.Show(frame.Head(3, df)))
```

```python
import pandas as pd
df = pd.read_csv("sales.csv")
print(len(df))
print(list(df.columns))
print(df.head(3).to_string(index=False))
```

```r
df <- read.csv("sales.csv")
print(nrow(df))
print(names(df))
print(head(df, 3), row.names = FALSE)
```

Une frame est une valeur, comme tout en Cesia : chaque fonction en donne une nouvelle, et `df` reste ce qu'il était.
C'est la *data frame* de pandas en Python et de R, une table de colonnes nommées, toutes de la même longueur ;
[std/frame] en est une petite, écrite en Cesia sur [std/columns], dont les boucles sur des colonnes entières sont en OCaml
et tournent sur plusieurs cœurs pour une grande colonne.

## Interroger une table

[frame.WithColumn] ajoute une colonne calculée à partir de chaque ligne, [frame.Where] garde les lignes qu'une fonction
accepte, et [frame.Select] garde certaines colonnes :

```cesia allow=read
withTotal = frame.WithColumn("total", r -> r.units * r.price, df)
lyon = frame.Where(r -> r.city == "Lyon", withTotal)
io.Print(frame.Show(frame.Select(["day", "product", "total"], lyon)))
```

```python
import pandas as pd
df = pd.read_csv("sales.csv")
with_total = df.assign(total=df["units"] * df["price"])
lyon = with_total[with_total["city"] == "Lyon"]
print(lyon[["day", "product", "total"]].to_string(index=False))
```

```r
df <- read.csv("sales.csv")
with_total <- transform(df, total = units * price)
lyon <- subset(with_total, city == "Lyon", select = c(day, product, total))
print(lyon, row.names = FALSE)
```

### Des groupes de lignes

[frame.GroupBy] fait une ligne par valeur de ses colonnes, et une colonne pour chaque [frame.Agg] : un nouveau nom, la
colonne qu'elle lit, et la fonction à appliquer à ses valeurs. [frame.SortBy] trie les lignes :

```cesia allow=read
byCity = frame.GroupBy(["city"], [frame.Agg("units", "units", list.Sum), frame.Agg("rows", "day", value.Len)], df)
io.Print(frame.Show(frame.SortBy("units", byCity, descending = true)))
```

```python
import pandas as pd
df = pd.read_csv("sales.csv")
by_city = df.groupby("city", sort=False).agg(units=("units", "sum"), rows=("day", "size")).reset_index()
print(by_city.sort_values("units", ascending=False).to_string(index=False))
```

```r
df <- read.csv("sales.csv")
city <- factor(df$city, levels = unique(df$city))
by_city <- data.frame(city = levels(city), units = as.vector(tapply(df$units, city, sum)), rows = as.vector(table(city)))
print(by_city[order(-by_city$units), ], row.names = FALSE)
```

### Des colonnes entières

Une colonne est une liste, et les opérateurs du langage agissent sur une liste entière d'un coup, une
[vectorized operation](glossary.md#vectorized-operation) : `units * 2` double chaque élément, et
`units > 10` donne une liste de `true` et de `false` dont [frame.WhereMask] se sert pour garder des lignes :

```cesia allow=read
units = frame.Column("units", df)
units * 2 -->
list.Mean(units) -->
frame.RowCount(frame.WhereMask(units > 10, df)) -->
```

```python
import pandas as pd
df = pd.read_csv("sales.csv")
units = df["units"]
print((units * 2).tolist())
print(units.mean())
print(len(df[units > 10]))
```

```r
df <- read.csv("sales.csv")
units <- df$units
print(units * 2)
print(mean(units))
print(nrow(df[units > 10, ]))
```

### Retour au CSV

[frame.ToCsv] réécrit une frame en texte CSV, pour [sys.Write] :

```cesia allow=read
frame.ToCsv(frame.Head(2, byCity)) -->
```

```python
import pandas as pd
df = pd.read_csv("sales.csv")
by_city = df.groupby("city", sort=False).agg(units=("units", "sum"), rows=("day", "size")).reset_index()
print(by_city.head(2).to_csv(index=False), end="")
```

```r
df <- read.csv("sales.csv")
city <- factor(df$city, levels = unique(df$city))
by_city <- data.frame(city = levels(city), units = as.vector(tapply(df$units, city, sum)), rows = as.vector(table(city)))
write.csv(head(by_city, 2), stdout(), row.names = FALSE, quote = FALSE)
```

### Joindre deux tables

[frame.JoinOn] met à côté de chaque ligne d'une table les colonnes des lignes d'une autre table qui ont la même valeur dans
une colonne : un *join* (une jointure), comme `JOIN` en SQL. C'est un *hash join* : les clés de la seconde table vont
d'abord dans une hash table (une table qui range chaque clé à une place calculée à partir de la clé elle-même, et l'y
retrouve en un pas), si bien que chaque ligne de la première trouve aussitôt les lignes qui lui correspondent, et le tout
coûte à peu près la somme des deux tailles, pas leur produit. Avec `how = "left"`, une ligne sans correspondance reste,
avec ses nouvelles colonnes à `missing` : un *left join*.

```cesia allow=read
cities = frame.Of({city: ["Lyon", "Paris"], region: ["Rhône", "Île-de-France"]})
joined = frame.JoinOn("city", df, cities)
frame.RowCount(joined) -->
frame.Columns(joined) -->
frame.RowCount(frame.JoinOn("city", df, cities, how = "left")) -->
```

```python
import pandas as pd
df = pd.read_csv("sales.csv")
cities = pd.DataFrame({"city": ["Lyon", "Paris"], "region": ["Rhône", "Île-de-France"]})
joined = df.merge(cities, on="city")
print(len(joined))
print(list(joined.columns))
print(len(df.merge(cities, on="city", how="left")))
```

```r
df <- read.csv("sales.csv")
cities <- data.frame(city = c("Lyon", "Paris"), region = c("Rhône", "Île-de-France"))
joined <- merge(df, cities, by = "city")[, c(names(df), "region")]
print(nrow(joined))
print(names(joined))
print(nrow(merge(df, cities, by = "city", all.x = TRUE)))
```

### Le reste de std/frame

| Pour | Utilisez |
|---|---|
| faire une frame | [frame.Of] à partir d'un dictionnaire de colonnes, [frame.Table] à partir de noms et de colonnes, [frame.FromRecords] à partir de dictionnaires, [frame.Empty] sans aucune ligne |
| lire des lignes | [frame.Row] une seule, [frame.Records] toutes, comme dictionnaires ; [frame.Tail] les dernières |
| changer des colonnes | [frame.SetColumn] en remplace ou en ajoute une, [frame.DropColumn] en retire une, [frame.Rename] en renomme une |
| garder des lignes | [frame.WhereColumn] selon la valeur d'une colonne, [frame.DropMissing] celles qui n'ont aucun trou |
| remplir les trous | [frame.FillMissing] remplace chaque `missing`, [frame.Present] donne les valeurs d'une colonne qui ne manquent pas |
| joindre | [frame.Append] met les lignes d'une frame après celles d'une autre |
| décrire | [frame.Kinds] la sorte de chaque colonne, [frame.ValueCounts] combien de lignes tiennent chaque valeur, [frame.Describe] le nombre de valeurs, la moyenne, le minimum et le maximum de chaque colonne de nombres |

```cesia allow=read
frame.Kinds(df) -->
frame.Records(frame.ValueCounts("city", df)) -->
io.Print(frame.Show(frame.Describe(df)))
frame.Row(1, frame.Tail(1, df)) -->
```

## Nombres

Pour le calcul numérique, [std/num] ajoute ce que numpy donne en Python : des statistiques comme [num.Median] et
[num.Std], de l'algèbre linéaire comme [num.Solve], et des ajustements de courbes comme [num.Polyfit].

```cesia allow=read
use std/num
num.Median(units) -->
num.Std(units) -->
num.Polyfit(1, [1.0, 2.0, 3.0], [3.0, 5.0, 7.0]) -->
```

```python
import numpy as np
import pandas as pd
units = pd.read_csv("sales.csv")["units"].to_numpy()
print(np.median(units))
print(np.std(units))
print(np.polynomial.polynomial.polyfit([1.0, 2.0, 3.0], [3.0, 5.0, 7.0], 1))
```

```r
units <- read.csv("sales.csv")$units
print(median(units))
print(sqrt(mean((units - mean(units))^2)))   # the deviation of the whole: sd() divides by n - 1
print(unname(coef(lm(c(3, 5, 7) ~ c(1, 2, 3)))))
```

## Des tirages au hasard

[std/random] tire des nombres pour des échantillons, des jeux et des simulations. [random.Int] donne un nombre entier
entre deux bornes, toutes deux comprises, [random.Float] un float (un nombre à virgule) de 0 jusqu'à 1, 1 exclu,
[random.Pick] un élément d'une liste, et [random.Shuffle] la liste dans un autre ordre :

```cesia
use std/random
roll = random.Int(1, 6)
roll >= 1 and roll <= 6 -->
random.Float() < 1 -->
random.Pick(["tea", "coffee"]) in ["tea", "coffee"] -->
list.Sort(random.Shuffle([3, 1, 2])) -->
```

### Les mêmes nombres une seconde fois

Chaque exécution prend au système un nouveau [seed](glossary.md#seed) (le nombre dont part le générateur, et dont il tire
toute sa suite de nombres), et tire donc d'autres nombres. [random.Seed] donne le seed d'une exécution, et
`cesia run --seed N` relance le programme avec le seed N, donc avec les mêmes nombres : une simulation qui a mal tourné
peut être rejouée. Un seed donne les mêmes nombres sur tous les systèmes et dans toutes les versions de Cesia.

```cesia norun
(* dice.ce: how many rolls of two dice until a double six *)
use std/random
use std/io
use std/list
use std/text

defn rolls()
  n = 1
  while random.Int(1, 6) + random.Int(1, 6) != 12
    n = n + 1
  end
  n
end

games = [rolls() for k in 1..10000]
io.Print("seed $(random.Seed()): $(text.Decimals(2, list.Mean(games))) rolls on average")
```

```bash
cesia run dice.ce             # seed 712762694: 35.57 rolls on average
cesia run --seed 42 dice.ce   # the same numbers at each run
```

Ces nombres servent aux échantillons et aux jeux, jamais aux secrets : un mot de passe ou une clé vient de [std/crypto].

## La suite

Vous savez maintenant interroger vos données. Le chapitre suivant, [Nombres et algorithmes](numbers.md), calcule avec des
arrays (des listes de nombres sur lesquelles on calcule d'un coup), des matrices, des graphes et les structures voisines
des listes ; puis [JSON et CSV](json.md) lit les données d'autres programmes et en écrit pour eux, et vérifie ce qui
arrive.
