# Graphiques

Dans ce chapitre, vous dessinez des données avec [std/plot] : des courbes, des points, des barres, des histogrammes, des
heatmaps (des cartes de chaleur), des densités et des bandes. Un graphique est une valeur, comme un nombre ou une liste
: vous le faites, en mettez plusieurs sur des axes communs, et le dessinez dans un fichier SVG, ou Cemacs le dessine sur
son écran. Chaque étape des données jusqu'aux pixels suit une méthode publiée, nommée ici avec son article, et les tests
de Cesia vérifient ce que promet chaque étape.

> [!NOTE]
> Les premiers graphiques ont des onglets : le même graphique en Python avec matplotlib et en R avec ses propres
> graphiques. Chaque onglet tourne quand le livre est vérifié et doit bien se terminer, en affichant ce que montre la
> version Cesia : ici rien, comme le dit `Ok(missing)`. Ils n'ont pas encore d'onglet MATLAB. Voir
> [Onglets dans d'autres langages](tests.md#onglets-dans-dautres-langages).

## Un premier graphique

[plot.Line] fait une courbe qui passe par des points, [plot.Of] met plusieurs layers (des calques, les couches d'un
graphique) sur des axes communs avec un titre et les noms des axes, et [plot.Save] écrit le graphique dans un fichier :

```cesia allow=read,write
use std/plot
use std/num
use std/math
use std/result
t = num.Linspace(0.0, 10.0, 200)
waves = plot.Of([plot.Line(t, math.Sin(t), label = "sin"), plot.Line(t, math.Cos(t), label = "cos", dash = "dashed")],
  title = "Two waves", x = "time (s)", y = "value")
plot.Save(waves, "waves.svg") -->
```

```python
import numpy as np
import matplotlib.pyplot as plt
t = np.linspace(0.0, 10.0, 200)
fig, ax = plt.subplots(figsize=(6.4, 4.0))
ax.plot(t, np.sin(t), label="sin")
ax.plot(t, np.cos(t), label="cos", linestyle="dashed")
ax.set(title="Two waves", xlabel="time (s)", ylabel="value")
ax.legend()
fig.savefig("waves.svg")
```

```r
t <- seq(0, 10, length.out = 200)
svg("waves.svg", width = 6.4, height = 4)
plot(t, sin(t), type = "l", main = "Two waves", xlab = "time (s)", ylab = "value")
lines(t, cos(t), lty = "dashed")
legend("topright", legend = c("sin", "cos"), lty = c("solid", "dashed"))
invisible(dev.off())
```

`waves.svg` est une image de 640 pixels sur 400 en *SVG*, Scalable Vector Graphics, le format de dessins que tout
navigateur web ouvre et qui reste net à tous les zooms. La légende s'affiche parce que les layers ont un label (une
étiquette).

## Un graphique est une valeur

Rien n'est dessiné quand un graphique est fait. [plot.Line] donne un [plot.Graph] d'un seul layer, et un layer seul est
un graphique : il s'affiche avec ses propres axes. [plot.Of] réunit les layers des graphiques qu'on lui donne, les
derniers par-dessus ; [plot.Grid] place des graphiques côte à côte, chacun avec ses propres axes, comme le fait
`subplot` dans MATLAB. Trois fonctions dessinent un graphique : [plot.Svg] donne son texte SVG, [plot.Save] écrit ce
texte dans un fichier, et [plot.Scene] donne les formes dont il est fait, en pixels, que Cemacs dessine, comme le montre
[Des scènes](#des-scènes-pour-un-back-end). Voici les labels des ticks de l'axe du temps ci-dessus :

```cesia
scene = result.Unwrap(plot.Scene(waves, 640, 400))
[item.Text for item in scene.Items if item.Role == "xlabel"] -->
```

| Fonction | Ce qu'elle dessine |
|---|---|
| [plot.Line] `(x, y, label, color, width, dash)` | une courbe qui passe par les points, coupée à chaque NaN |
| [plot.Points] `(x, y, label, color, size, shape)` | un marqueur à chaque point, jusqu'à 200 000 |
| [plot.Bars] `(names, heights, label, color)` | une barre pour chaque nom, ou un groupe de barres avec une liste de listes |
| [plot.Histogram] `(values, bins, label, color)` | les valeurs comptées dans des bins (des classes) |
| [plot.Heatmap] `(values, x, y, colors)` | une matrice en cellules colorées, avec une barre de couleurs |
| [plot.Density] `(x, y, bins)` | des points en nombre quelconque comptés par cellule, un histogramme 2D |
| [plot.Area] `(x, low, high, label, color)` | la bande entre deux courbes |
| [plot.Of] `(layers, title, x, y, xscale, yscale, xlim, ylim, legend, size)` | des layers sur des axes communs |
| [plot.Grid] `(graphs, columns)` | des graphiques côte à côte |
| [plot.Svg] `(g)`, [plot.Save] `(g, path)`, [plot.Scene] `(g, width, height)` | le dessin |

Une couleur s'écrit `"#rrggbb"`, le rouge, le vert et le bleu d'une couleur en deux chiffres hexadécimaux chacun, comme
en CSS. Un layer sans couleur prend la suivante de la palette de [Couleurs](#couleurs).

### Courbes et points

[plot.Line] relie les points dans l'ordre donné. Un NaN, *not a number* (pas un nombre), ou un infini dans `x` ou `y`
coupe la courbe : elle y laisse un trou, comme le fait matplotlib, pour qu'une mesure manquante ne dessine pas un faux
segment. `dash` (le tireté) vaut `"dashed"`, `"dotted"` ou `"dashdot"`, avec les motifs du style par défaut de
matplotlib mis à l'échelle de la largeur : 3,7 tracé et 1,6 vide, 1 et 1,65, et 6,4, 1,6, 1, 1,6 largeurs.

[plot.Points] dessine un marqueur à chaque point, `"circle"`, `"square"`, `"triangle"`, `"diamond"`, `"cross"` ou
`"plus"`, de `size` pixels de large. Un point avec un NaN ou un infini est laissé de côté, et la scène le compte dans
`Dropped`. Au plus 200 000 points sont dessinés un par un : au-delà, un nuage de marqueurs cache sa propre forme, et le
fichier grossit d'environ 20 octets par point, si bien que [plot.Points] donne un `Err` qui nomme [plot.Density], qui
compte n'importe quel nombre de points par cellule.

```cesia
noisy = plot.Points([1, 2, 3, 4], [2.0, math.Nan, 3.5, 1.0], shape = "diamond")
result.Unwrap(plot.Scene(noisy, 640, 400)).Dropped -->
```

### Barres et histogrammes

[plot.Bars] dessine une barre de 0 à chaque hauteur, une pour chaque nom. Avec une liste de listes, les barres d'un nom
se tiennent côte à côte, une série pour chaque liste, et `label` et `color` sont des listes, une pour chaque série :

```cesia norun
plot.Bars(["north", "south", "west"], [[12, 9, 4], [14, 7, 6]], label = ["2025", "2026"])
```

```python
import numpy as np
import matplotlib.pyplot as plt
names = ["north", "south", "west"]
x = np.arange(len(names))
fig, ax = plt.subplots()
ax.bar(x - 0.2, [12, 9, 4], width=0.4, label="2025")
ax.bar(x + 0.2, [14, 7, 6], width=0.4, label="2026")
ax.set_xticks(x, names)
ax.legend()
fig.savefig("bars.svg")
```

```r
svg("bars.svg")
barplot(rbind(c(12, 9, 4), c(14, 7, 6)), beside = TRUE, names.arg = c("north", "south", "west"),
  legend.text = c("2025", "2026"))
invisible(dev.off())
```

Un graphique contient un seul [plot.Bars]. D'autres layers peuvent partager ses axes : le premier nom est à `x = 1`, le
deuxième à `x = 2`, et ainsi de suite, si bien qu'une courbe qui passe par `[1, 2, 3]` croise les barres en leur milieu.
Un nom trop large pour sa barre met son label à la verticale.

[plot.Histogram] compte des valeurs dans des *bins*, des intervalles côte à côte, et dessine une barre pour chacun.
`bins` vaut missing pour la règle de Freedman et Diaconis, un nombre pour autant de bins de même largeur de la plus
petite valeur à la plus grande, ou une liste de bords, croissants. Un bin contient les valeurs de son bord gauche,
inclus, à son bord droit, exclu, et le dernier bin contient aussi son bord droit, comme le fait numpy. Les NaN, les
infinis et les valeurs hors des bords sont laissés de côté.

La règle de Freedman et Diaconis (1981) fait des bins de largeur $h = 2 \cdot IQR \cdot n^{-1/3}$, où $n$ est le nombre
de valeurs et l'IQR, l'*interquartile range* (l'écart interquartile), est la distance entre le premier quartile, la
valeur sous laquelle se trouve un quart des valeurs, et le troisième, sous lequel se trouvent les trois quarts. Leur
article montre que l'erreur d'un histogramme comme estimation de la densité des valeurs, mesurée en $L^2$, est la plus
petite pour des bins d'une largeur qui diminue comme $n^{-1/3}$, et propose $2 \cdot IQR$ pour le facteur : l'IQR
empêche la largeur de suivre quelques valeurs lointaines. Le nombre de bins est $\lceil (\max - \min) / h \rceil$, au
plus 10 000. Quand l'IQR vaut 0, comme quand la plupart des valeurs sont égales, la largeur vaudrait 0, et la règle de
Sturges (1926), $\lceil \log_2 n \rceil + 1$ bins, prend sa place. Les quartiles interpolent entre les deux valeurs
triées les plus proches, le *type 7* de Hyndman et Fan, que numpy et R prennent par défaut. Les comptes viennent des
valeurs triées, par une recherche dichotomique pour chaque bord.

### Heatmaps et densités

[plot.Heatmap] colore chaque cellule d'une matrice selon sa valeur, et met à côté une *barre de couleurs*, l'échelle qui
va des couleurs aux valeurs. `x` donne la valeur de chaque colonne et `y` celle de chaque ligne, croissantes ; une
cellule s'étend jusqu'à mi-chemin de ses voisines. Sans `y`, la ligne 1 est en haut, comme la matrice s'écrit, et les
lignes sont numérotées vers le bas. Un NaN laisse sa cellule vide.

```cesia norun
m = [-2.0, 0.5, 1.0; 1.5, -0.5, 3.0]
plot.Heatmap(m, colors = "diverging")
```

```python
import numpy as np
import matplotlib.pyplot as plt
m = np.array([[-2.0, 0.5, 1.0], [1.5, -0.5, 3.0]])
fig, ax = plt.subplots()
cells = ax.imshow(m, cmap="RdBu_r", vmin=-3.0, vmax=3.0)
fig.colorbar(cells)
fig.savefig("heatmap.svg")
```

```r
m <- matrix(c(-2, 0.5, 1, 1.5, -0.5, 3), nrow = 2, byrow = TRUE)
svg("heatmap.svg")
image(t(m[nrow(m):1, ]), col = hcl.colors(21, "Blue-Red"), zlim = c(-3, 3), axes = FALSE)
invisible(dev.off())
```

[plot.Density] est un *histogramme 2D* : il découpe l'étendue des points en `bins` sur `bins` cellules, 100 sur 100 par
défaut, compte les points de chaque cellule, et colore les cellules selon leur compte. Chaque point est compté, aucun
n'est échantillonné, si bien qu'un nuage de dix millions de points s'affiche tel qu'il est. Une cellule vide reste vide.

Un tracé de 640 pixels ne peut pas montrer 1 000 colonnes : au-delà d'une cellule par pixel le long d'un axe, les
cellules fusionnent par blocs, autant qu'il en faut pour tenir, par leur moyenne pour une heatmap et leur somme pour une
densité, pour qu'aucune cellule ne soit sautée. Une heatmap sans NaN fusionne par deux produits de matrices,
$a \cdot m \cdot b$, où $a$ et $b$ contiennent un 1 pour chaque ligne ou colonne d'un bloc.

### Bandes

[plot.Area] remplit la bande de `low` à `high` le long de `x`, à 30 % d'opacité pour que ce qui est dessous se voie au
travers : un intervalle de confiance, l'enveloppe d'un signal. Un NaN dans l'un des trois coupe la bande.

```cesia norun
mean = math.Sin(t)
spread = 0.2 + 0.1 * math.Cos(t)
plot.Of([plot.Area(t, mean - spread, mean + spread, label = "±1 σ"), plot.Line(t, mean, label = "mean")])
```

```python
import numpy as np
import matplotlib.pyplot as plt
t = np.linspace(0.0, 10.0, 200)
mean = np.sin(t)
spread = 0.2 + 0.1 * np.cos(t)
fig, ax = plt.subplots()
ax.fill_between(t, mean - spread, mean + spread, alpha=0.3, label="±1 σ")
ax.plot(t, mean, label="mean")
ax.legend()
fig.savefig("band.svg")
```

```r
t <- seq(0, 10, length.out = 200)
middle <- sin(t)
spread <- 0.2 + 0.1 * cos(t)
band <- adjustcolor("steelblue", alpha.f = 0.3)
svg("band.svg")
plot(t, middle, type = "n", ylim = range(middle - spread, middle + spread), xlab = "", ylab = "")
polygon(c(t, rev(t)), c(middle - spread, rev(middle + spread)), col = band, border = NA)
lines(t, middle)
legend("topright", legend = c("±1 σ", "mean"), fill = c(band, NA), border = NA, lty = c(NA, 1))
invisible(dev.off())
```

### Les options d'un graphique

[plot.Of] prend les options des axes : `title` ; `x` et `y`, les noms des axes ; `xscale` et `yscale`, `"linear"` ou
`"log"` pour un axe logarithmique en base 10, où chaque puissance de dix prend la même longueur ; `xlim` et `ylim`,
l'étendue d'un axe sous la forme `[low, high]` ; `legend = false` pour cacher la légende ; `size = [width, height]` en
pixels, 640 sur 400 par défaut, 100 sur 80 au moins. Les options d'un [plot.Of] donné comme layer sont laissées de côté
: celles du plus extérieur s'appliquent.

## Des données aux pixels

### L'étendue d'un axe

Un axe couvre les données de ses layers, plus 5 % de cette étendue de chaque côté, comme le font matplotlib et ggplot2,
pour qu'aucun point ne soit posé sur le cadre ; sur un axe logarithmique, les 5 % sont pris de l'étendue des
logarithmes. Les barres et les histogrammes partent de 0, si bien que leur axe ne descend pas sous 0 quand aucune valeur
n'y descend. Les cellules d'une heatmap ou d'une densité couvrent leur axe exactement. `xlim` et `ylim` donnent
l'étendue exactement, et les données au-delà sont coupées au cadre. Quand toutes les valeurs sont une seule valeur,
l'axe en couvre 10 % de chaque côté, ou 1 autour de 0, ou une demi-puissance de dix sur un axe logarithmique. Un axe
logarithmique avec une valeur à 0 ou en dessous est un `Err` qui nomme le layer et la première de ces valeurs.

### Les ticks

Les *ticks* sont les graduations le long d'un axe, avec leurs labels. [std/plot] les place par l'algorithme de Wilkinson
étendu de Talbot, Lin et Hanrahan (2010). Il essaie des pas de $q \cdot 10^z$, avec $q$ parmi 1, 5, 2, 2,5, 4 et 3, le
premier plus simple, met un label à chaque $j$-ième multiple du pas, de 3 à 12 labels, et note chaque ensemble de labels
par quatre mesures :

- la *simplicité*, $1 - \frac{i - 1}{5} - j + v$, où $i$ est la place de $q$ dans la liste et $v$ vaut 1 quand 0 est un
  label ;
- la *couverture*,
  $1 - \frac{1}{2} \cdot \frac{(d_{max} - l_{max})^2 + (d_{min} - l_{min})^2}{(0{,}1 (d_{max} - d_{min}))^2}$ : quelle
  part de l'étendue de l'axe $[d_{min}, d_{max}]$ les labels $[l_{min}, l_{max}]$ couvrent ;
- la *densité*, $2 - \max(r / r_t, r_t / r)$, où $r$ est le nombre de labels par unité et $r_t$ la cible, un label pour
  100 pixels le long de x et pour 60 le long de y ;
- la *lisibilité* : moins l'infini quand deux labels se toucheraient, à moins de 6 pixels l'un de l'autre le long de x,
  ou à moins d'une ligne et 2 pixels le long de y ; 1 sinon.

La note est $0{,}25 s + 0{,}2 c + 0{,}5 d + 0{,}05 l$, les poids de l'article, et la recherche arrête une branche dès
que la meilleure note qu'elle pourrait encore atteindre est sous la meilleure trouvée. Un changement par rapport à
l'article : l'étendue de l'axe est fixée d'abord, comme le dit la section au-dessus, et seuls les ensembles de labels à
l'intérieur sont essayés, si bien que chaque tick est sur l'axe. Quand aucun ensemble ne tient, les labels s'écrivent
plus courts, avec une puissance de dix, et quand aucun ne tient encore, sur un axe trop court pour trois labels, le
meilleur ensemble est pris tel quel.

Un label est le décimal le plus court qui se relit en son tick : `0.5`, `2`, `−1.5`, avec le vrai signe moins, U+2212.
Il est écrit à partir d'entiers, $n \cdot 10^e$ pour chaque tick, jamais à partir du float binaire, si bien que
`0.30000000000000004` ne peut pas s'afficher. Au-delà de $10^6$, ou sous $10^{-4}$, les labels comptent en une puissance
de dix, montrée une fois au bout de l'axe : `1`, `2`, `3` et `×10⁷`. Quand les ticks partagent 4 premiers chiffres ou
plus, comme des temps en secondes depuis 1970, ils comptent à partir d'un *offset* (un décalage), un nombre rond montré
là aussi : `2`, `4`, `6` et `+1.7314×10⁹`. Ce sont les deux façons de matplotlib, avec des seuils à nous.

Un axe logarithmique met ses ticks aux puissances de dix, écrites `10ⁿ` : toutes, ou une sur deux, trois, cinq ou plus,
pour qu'il en tienne de 3 à 12. Avec moins de 3 puissances de dix dans son étendue, il ajoute 2 et 5 fois chaque
puissance ; avec encore moins de 3 ticks, il les place comme le ferait un axe linéaire.

### Le texte, et la taille de chaque label

Les marges autour du tracé sont mesurées, pas devinées : la largeur de chaque label est la somme des *advance widths*
(les chasses) de ses caractères, de combien chacun fait avancer la plume, dans la police avec laquelle Cemacs dessine,
Noto Sans Medium. [std/plot] garde ces largeurs pour les lettres latines, Latin-1 et Latin Extended-A, le grec, et la
ponctuation, les exposants, les indices et le signe moins des nombres et des unités, lues dans le fichier de la police
par `tools/plot-font.ce`. Un test mesure chacune d'elles avec SDL3_ttf, la bibliothèque de texte de Cemacs, et les
trouve toutes à moins d'un pixel près. Un caractère hors de celles-ci, comme un caractère chinois, compte pour un *em*
entier, la taille de la police, aussi large que n'importe lequel de ces glyphes sauf `‰`, pour qu'aucun label ne
chevauche ou ne soit coupé, au prix d'un peu de place. Le trait d'union conditionnel ne compte rien, puisque la mise en
forme le cache.

Les textes sont dessinés sans *kerning* (le crénage), les petits déplacements entre des paires de lettres comme `AV`,
pour que les largeurs mesurées soient les largeurs dessinées. Le SVG nomme d'abord Noto Sans, puis la police sans-serif
du navigateur : un lecteur sans Noto Sans dessine les textes dans une autre police, un peu plus large ou plus étroite
que ce qui a été mesuré. L'encre de quelques lettres, comme un `f` ou un `î` au bout d'un label, va jusqu'à environ 0,2
em au-delà de sa chasse, 2 pixels à 12 ; l'espace gardé entre les labels, 6 pixels, le couvre.

Les largeurs connues, la mise en page réserve le titre, les labels des ticks, les noms des axes, la légende et la barre
de couleurs, et donne au tracé ce qui reste. Un label au bout d'un axe peut dépasser du tracé : la marge grandit pour le
contenir. Les tests vérifient, sur des graphiques de données au hasard et de tailles au hasard, que chaque texte est
dans l'image et que deux labels d'un axe ne se chevauchent jamais.

### Les longues courbes : M4

Une courbe de dix millions de points dessinée sur 600 pixels met des milliers de points dans chaque colonne de pixels.
*M4*, de Jugel, Jerzak, Hackenbroich et Markl (2014), garde quatre points de chaque colonne : le premier, le dernier, le
plus bas et le plus haut. Les pixels allumés sont les mêmes qu'avec tous les points : le premier et le dernier relient
les colonnes comme le faisaient tous les points, et le plus bas et le plus haut couvrent la colonne comme le faisaient
tous les points. L'article le prouve pour une courbe d'un pixel de large, dessinée sans anti-aliasing (le lissage des
bords) à la taille pour laquelle les points ont été groupés ; un test de [std/plot] dessine des courbes de 60 000 points
des deux façons avec l'algorithme de Bresenham (1965), la façon classique de dessiner une ligne sur une grille de
pixels, et compare chaque pixel. Une courbe lissée ou plus large, comme Cemacs et les navigateurs en dessinent, peut
différer d'une nuance au bord d'une colonne.

[std/plot] se sert de M4 quand x ne décroît jamais le long de la courbe et qu'il y a plus de 4 points par colonne du
tracé. Une courbe dont le x va et vient, comme un cercle, garde tous ses points.

### Couleurs

Les layers prennent tour à tour les huit couleurs d'Okabe et Ito (2008), choisies pour rester distinctes pour les formes
courantes de daltonisme : bleu `#0072b2`, vermillon `#d55e00`, vert bleuté `#009e73`, pourpre rougeâtre `#cc79a7`, bleu
ciel `#56b4e9`, orange `#e69f00`, jaune `#f0e442` et noir `#000000`. Le noir vient en dernier, puisqu'il disparaît sur
un fond sombre.

Les heatmaps et les densités prennent *viridis*, de van der Walt et Smith (2015) : sa luminosité croît régulièrement de
la plus petite valeur à la plus grande, si bien que des pas égaux des données ont l'air de pas égaux de couleur, une
carte *perceptuellement uniforme*, et elle reste dans l'ordre en gris et pour des yeux daltoniens. Une valeur prend
l'une de ses 256 couleurs, celles de la table de matplotlib, le numéro
$\lfloor 256 (v - v_{min}) / (v_{max} - v_{min}) \rfloor$, la dernière pour la plus grande. `colors = "diverging"` prend
le RdBu de ColorBrewer, de Harrower et Brewer (2003), pour des données autour de 0 : bleu foncé pour la plus négative,
blanc à 0, rouge foncé pour la plus positive, ses 11 couleurs reliées par des segments, et la même distance des deux
côtés de 0. Les thèmes de Cemacs changent les axes et les textes, jamais les couleurs des données.

## Des scènes, pour un back-end

[plot.Scene] donne ce dont un graphique est fait, pour qu'un autre programme qu'un navigateur puisse le dessiner (un
back-end, la partie qui dessine) : `{Width, Height, Items, Dropped}`, ses éléments dans l'ordre où ils sont dessinés,
chacun un dictionnaire avec un `Kind` (une sorte) et un `Role` (un rôle) :

| Kind | Champs |
|---|---|
| `"line"` | `Xs`, `Ys`, `Color`, `Width`, `Dash` (missing, ou les longueurs tracées et vides) |
| `"area"` | `Xs`, `Ys` autour de la bande, `Color`, `Opacity` |
| `"rect"` | `X`, `Y`, `W`, `H`, `Color`, `Opacity` |
| `"marks"` | `Xs`, `Ys`, les centres, `Shape`, `Size`, `Color` |
| `"cells"` | `Xs` et `Ys`, les bords des colonnes et des lignes, `Colors` ligne après ligne, missing pour une cellule vide |
| `"text"` | `X`, `Y` sur la ligne de base, `Text`, `Size`, `Color`, `Anchor` (`"start"`, `"middle"` ou `"end"`), `Angle` (0 ou -90), `Width` |

Les coordonnées sont en pixels depuis le coin en haut à gauche. Les éléments des données ont `Clip`, le rectangle
`[x, y, width, height]` du tracé auquel ils sont coupés. Une `Color` vaut `"#rrggbb"`, ou `"ink"` et `"grid"` pour le
cadre, les ticks et les textes, qu'un back-end peint dans les couleurs de son thème ; [plot.Svg] les peint en `#222222`
et `#e6e6e6` sur du blanc. Le `Role` dit ce qu'est un élément : `"grid"`, `"data"`, `"frame"`, `"tick"`, `"xlabel"` et
`"ylabel"` pour les labels des ticks, `"factor"` pour la puissance de dix ou l'offset d'un axe, `"title"`, `"xtitle"`,
`"ytitle"`, `"legend"` ou `"colorbar"`.

## Erreurs

Chaque erreur dans un graphique donne un `Err` de sorte `"plot"` de la part de [plot.Svg], [plot.Save] et [plot.Scene],
qui nomment le layer et disent quoi faire ; faire le graphique n'échoue jamais, si bien qu'un graphique est vérifié une
seule fois, quand il est dessiné :

```cesia
plot.Svg(plot.Of([plot.Line([1, 2, 3], [1, 2]), plot.Points([1], [1], shape = "star")])) -->
plot.Svg(plot.Of([plot.Line([1, 10], [0, 5], label = "rate")], yscale = "log")) -->
```

Les vérifications : les longueurs de `x` et `y`, une valeur qui n'est pas un nombre, aucune valeur finie du tout, un axe
logarithmique avec une valeur à 0 ou en dessous, plus de 200 000 points, un nombre de bins sous 1 ou des bords qui ne
croissent pas, une couleur, une forme, un tireté, une échelle ou une étendue mal écrits, et une taille trop petite pour
le tracé.

## Vitesse

Un programme qui ne se sert pas de [std/plot] démarre aussi vite qu'avant : 2,8 ms pour `io.Print(1)`. `use std/plot`
charge ses 2 000 lignes en environ 6,5 ms, et un premier graphique, du début du programme à son SVG, prend 15 ms.
Ensuite [plot.Svg] prend, en médiane de 21 lancements sur un ordinateur de bureau de 8 cœurs :

| Graphique | Temps |
|---|---|
| une courbe de 1 000 points | 2,0 ms |
| une courbe de 100 000 points | 7,4 ms |
| une courbe de 1 000 000 de points | 37 ms |
| une courbe de 10 000 000 de points | 324 ms |
| une heatmap de 100 sur 100 | 17 ms |
| une heatmap de 1 000 sur 1 000 | 298 ms |

Tout est en Cesia, rendu rapide par le JIT (le compilateur qui traduit le code en code machine pendant qu'il tourne) ;
pour une longue courbe, le passage sur les points qui trouve leur étendue et le passage de M4 prennent l'essentiel du
temps.

## Limites

- Du SVG seulement, pour l'instant ; le PNG viendra avec un rasterizer (le code qui change un dessin en pixels) choisi
  sur mesure.
- Une seule police est mesurée, Noto Sans Medium ; les autres polices dessinent un peu plus large ou plus étroit.
- La légende et la barre de couleurs sont à droite du tracé ; les barres sont debout ; un graphique contient un seul
  [plot.Bars].
- Une courbe dont le x va et vient garde tous ses points ; au-delà de 200 000 marqueurs, prenez [plot.Density].
- Ni 3D, ni animation, ni zoom dans cette version.

## Pour aller plus loin

- Justin Talbot, Sharon Lin, Pat Hanrahan. "An Extension of Wilkinson's Algorithm for Positioning Tick Labels on Axes".
  *IEEE Transactions on Visualization and Computer Graphics* 16(6):1036–1043, 2010.
  <https://doi.org/10.1109/TVCG.2010.130>. La recherche des ticks et ses quatre notes.
- Uwe Jugel, Zbigniew Jerzak, Gregor Hackenbroich, Volker Markl. "M4: A Visualization-Oriented Time Series Data
  Aggregation". *Proceedings of the VLDB Endowment* 7(10):797–808, 2014. <https://doi.org/10.14778/2732951.2732953>. Les
  quatre points par colonne de pixels d'une longue courbe.
- David Freedman, Persi Diaconis. "On the histogram as a density estimator: L2 theory". *Zeitschrift für
  Wahrscheinlichkeitstheorie und verwandte Gebiete* 57(4):453–476, 1981. <https://doi.org/10.1007/BF01025868>. La
  largeur des bins.
- Herbert A. Sturges. "The Choice of a Class Interval". *Journal of the American Statistical Association*
  21(153):65–66, 1926. <https://doi.org/10.1080/01621459.1926.10502161>. Le nombre de bins quand l'IQR vaut 0.
- Rob J. Hyndman, Yanan Fan. "Sample Quantiles in Statistical Packages". *The American Statistician* 50(4):361–365,
  1996. <https://doi.org/10.1080/00031305.1996.10473566>. Les quartiles, par son type 7.
- Masataka Okabe, Kei Ito. "Color Universal Design (CUD): How to make figures and presentations that are friendly to
  Colorblind people". J*Fly, 2002, revu en 2008. <https://jfly.uni-koeln.de/color/>. Les couleurs des layers.
- Stéfan van der Walt, Nathaniel Smith. "matplotlib colormaps", la page des cartes de couleurs qu'ils ont conçues pour
  être celles de matplotlib par défaut, avec leur exposé à SciPy 2015. <https://bids.github.io/colormap/>. Viridis,
  d'après la table de matplotlib 3.11.
- Mark Harrower, Cynthia A. Brewer. "ColorBrewer.org: An Online Tool for Selecting Colour Schemes for Maps". *The
  Cartographic Journal* 40(1):27–37, 2003. <https://doi.org/10.1179/000870403235002042>. RdBu.
- J. E. Bresenham. "Algorithm for computer control of a digital plotter". *IBM Systems Journal* 4(1):25–30, 1965.
  <https://doi.org/10.1147/sj.41.0025>. Les pixels d'une ligne, dans le test de M4.
- Microsoft et Adobe. *OpenType specification* : les tables cmap, hmtx et head.
  <https://learn.microsoft.com/typography/opentype/spec/>. Comment `tools/plot-font.ce` lit les largeurs de la police.

## La suite

Vous savez dessiner ce que vous calculez. Le chapitre suivant, [Méthodes numériques](numerical.md), trouve les zéros et
les minima des fonctions, résout les équations différentielles et les systèmes sparse (dont la matrice est presque toute
faite de zéros), et calcule des intégrales.
