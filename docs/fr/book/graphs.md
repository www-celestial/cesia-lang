# Graphiques

Dans ce chapitre, vous dessinez des données avec [std/plot] : des courbes, des points, des barres, des histogrammes, des
heatmaps (des cartes de chaleur), des densités et des bandes, des textes et des règles, des graphiques en cercle, des
surfaces et des courbes en 3D, et des animations de tout cela. Un graphique est une valeur, comme un nombre ou une liste
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
navigateur web ouvre et qui reste net à tous les zooms. Il est noir sur blanc : les deux courbes sont noires, la première
en trait plein et la seconde en tirets, et les textes sont en JetBrains Mono, la police du code dans Cemacs, qui dessine
le graphique de la même façon. La légende s'affiche parce que les layers ont un label (une étiquette).

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
| [plot.Surface] `(z, x, y, colors)` | une surface en 3D, la hauteur `z[i, j]` au-dessus de `(x[j], y[i])` |
| [plot.Text] `(x, y, texts, color, size, anchor, dx, dy)` | des textes à côté de points des données |
| [plot.Rule] `(x, y, label, dash, color)` | une ligne de repère à travers le tracé |
| [plot.Line3] `(x, y, z, label, color, width, dash)` | une courbe en 3D |
| [plot.Of] `(layers, title, x, y, xscale, yscale, xlim, ylim, legend, size, z, zlim, view, note, noteAt, xticks, xlabels, yticks, ylabels, polar)` | des layers sur des axes communs |
| [plot.Grid] `(graphs, columns)` | des graphiques côte à côte |
| [plot.Frames] `(graphs, fps)` | des graphiques l'un après l'autre : une animation |
| [plot.Svg] `(g)`, [plot.Save] `(g, path)`, [plot.Scene] `(g, width, height, frame, view)` | le dessin |

Une couleur s'écrit `"#rrggbb"`, le rouge, le vert et le bleu d'une couleur en deux chiffres hexadécimaux chacun, comme
en CSS. Un layer sans couleur est noir, comme le dit [Couleurs](#couleurs) : les courbes se distinguent par leur trait,
les points par leur forme, les barres par leur nuance de gris. Tout layer prend une couleur à lui, chacun la sienne, pour
distinguer des courbes par la couleur ou en mettre une en avant.

### Courbes et points

[plot.Line] relie les points dans l'ordre donné. Un NaN, *not a number* (pas un nombre), ou un infini dans `x` ou `y`
coupe la courbe : elle y laisse un trou, comme le fait matplotlib, pour qu'une mesure manquante ne dessine pas un faux
segment. Une courbe a 1 pixel de large, sauf si `width` dit autre chose. `dash` (le tireté) vaut `"dashed"`, `"dotted"`
ou `"dashdot"`, avec les motifs du style par défaut de matplotlib mis à l'échelle de la largeur : 3,7 tracé et 1,6 vide,
1 et 1,65, et 6,4, 1,6, 1, 1,6 largeurs.

[plot.Points] dessine un marqueur à chaque point, `"circle"`, `"square"`, `"triangle"`, `"diamond"`, `"cross"` ou
`"plus"`, de `size` pixels de large ; sans `shape`, la suivante du tour de [Couleurs](#couleurs). Un point avec un NaN ou un infini est laissé de côté, et la scène le compte dans
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
l'étendue d'un axe sous la forme `[low, high]` ; `legend = false` pour cacher la légende, `legend = "ends"` pour nommer
chaque courbe à son bout ; `size = [width, height]` en pixels, 640 sur 400 par défaut, 100 sur 80 au moins ; `note` et
`noteAt`, une boîte de texte dans un coin ; `xticks`, `xlabels`, `yticks` et `ylabels`, des ticks à vous ;
`polar = true`, un graphique en cercle. Les sections qui suivent montrent chacune. Les options d'un [plot.Of] donné comme
layer sont laissées de côté : celles du plus extérieur s'appliquent. Un graphique 3D prend aussi `z`, `zlim` et `view`,
comme le montre [3D](#3d) ; sur un graphique 2D, elles sont une erreur.

### Textes et règles

[plot.Text] écrit des textes sur le graphique, chacun à côté de son point des données : `texts[i]` en `(x[i], y[i])`,
décalé de `dx` pixels vers la droite et `dy` vers le bas, 4 et -4 par défaut, pour qu'il se pose au-dessus et à droite
d'un marqueur. `anchor` (l'ancre) est le côté du texte posé à cet endroit, `"left"`, `"middle"` ou `"right"` ; `size` est
en pixels, 11 par défaut, de 4 à 96. C'est un layer comme les autres : il suit les axes, un texte dont le point est
au-delà de `xlim` est laissé de côté, et il n'a pas d'entrée dans la légende. Au plus 100 000 textes, pour qu'une scène
reste assez petite pour Cemacs ; au-delà, un `Err` dit combien.

```cesia
hour = [7, 8, 9, 10, 11]
height = [5.0, 14.0, 21.0, 26.0, 28.0]
morning = plot.Of([plot.Line(hour, height), plot.Points(hour, height, size = 4), plot.Text(hour, height, ["$h h" for h in hour])])
[x.Text for x in result.Unwrap(plot.Scene(morning, 640, 400)).Items if x.Kind == "text" and x.Role == "data"] -->
```

Les textes sont une liste en compréhension, `["$h h" for h in hour]`, la forme courte de [list.Map]`(h -> "$h h", hour)`.

[plot.Rule] (une règle) trace une ligne de repère à travers le tracé : `x = 180` debout à 180, `y = 0` en travers à 0,
exactement l'un des deux. Elle est grise sauf si `color` dit autre chose, prend un `dash` comme une courbe, et écrit son
`label` à son bout, dans le tracé. L'étendue de son axe grandit pour la contenir, comme pour les données ; l'autre axe
est laissé aux autres layers.

```cesia
noon = plot.Of([plot.Line([0, 90, 180, 270, 360], [0, 30, 60, 30, 0]), plot.Rule(x = 180, label = "S"), plot.Rule(y = 0, label = "horizon", dash = "dashed")])
[x.Text for x in result.Unwrap(plot.Scene(noon, 640, 400)).Items if x.Kind == "text" and x.Role == "data"] -->
```

### Une note, et des noms aux bouts

`note` pose une boîte de texte dans un coin du tracé, une ligne pour chaque ligne du texte, comme le nom, le lieu et la
date de ce qui est dessiné ; `noteAt` vaut `"top left"`, par défaut, `"top right"`, `"bottom left"` ou `"bottom right"`.
La boîte n'a pas de cadre : ses lignes sont de l'encre des axes, sur le *paper* (le papier), le fond, qui cache la grille
derrière elles. Les espaces sont gardés, pour que les deux-points des lignes puissent se tenir l'un sous l'autre :

```cesia
place = plot.Of([plot.Line(hour, height)], note = "name: essai\n  lat: 40.76\n  lon: -73.984")
[x.Text for x in result.Unwrap(plot.Scene(place, 640, 400)).Items if x.Role == "info" and x.Kind == "text"] -->
```

`legend = "ends"` nomme chaque courbe à son bout, à la place de la boîte de la légende : son label à droite de son
dernier point dans le tracé, de sa couleur, comme un graphique imprimé nomme ses courbes. Deux labels qui se
chevaucheraient sont écartés d'une ligne, par une passe depuis le haut, puis par une passe depuis le bas pour ceux qui
sortiraient du tracé : une mise en page gloutonne, la plus simple qui garde les labels dans l'ordre des courbes. La
marge de droite grandit pour les contenir. Les points et les bandes sont nommés à leur dernier point aussi ; les barres
et les histogrammes n'ont pas de bout, et avec `"ends"` ils sont un `Err`.

```cesia
three = plot.Of([plot.Line(hour, height * k, label = "×$k") for k in [1, 2, 3]], legend = "ends")
[x.Text for x in result.Unwrap(plot.Scene(three, 640, 400)).Items if x.Role == "legend"] -->
```

### Des ticks à vous

`xticks` et `yticks` donnent les ticks d'un axe à la place de ceux de la recherche que décrit [Les ticks](#les-ticks) :
une liste de nombres, croissants, au plus 1 000 ; ceux qui sont dans l'étendue de l'axe sont dessinés, chacun avec sa
ligne de la grille. `xlabels` et `ylabels` donnent leurs labels, autant de textes que de ticks, sinon un `Err` ; sans
eux, les nombres s'écrivent comme les ticks calculés, chacun le plus court décimal qui se relit en lui. Un axe log prend
des ticks au-dessus de 0. Sans ces options, rien ne change.

```cesia
use std/list
compass = plot.Of([plot.Line([0, 90, 180, 270, 360], [1, 3, 2, 4, 1])], xticks = list.Range(0, 360, step = 90), xlabels = ["N", "E", "S", "W", "N"])
[x.Text for x in result.Unwrap(plot.Scene(compass, 640, 400)).Items if x.Role == "xlabel"] -->
```

[list.Range]`(0, 360, step = 90)` vaut `[0, 90, 180, 270, 360]` ; `0..360`, sa forme courte sans pas, serait chaque
entier.

### Les graphiques polaires

`polar = true` dessine le graphique dans un cercle, comme une boussole ou la course du soleil : `x` est un angle en
degrés, 0 en haut, tournant dans le sens des aiguilles d'une montre, si bien que 90 est à droite, comme l'est sur une
carte ; `y` est la distance au centre. `ylim` vaut `[center, rim]` (le centre, le bord), dans l'un ou l'autre ordre :
`[90, 0]` met 90 au centre et 0 sur le bord, comme la hauteur du soleil, à la verticale à 90 et sur l'horizon à 0. Sans
elle, 0, ou le plus petit `y` en dessous, est au centre, et le plus grand `y` et 5 % de plus sur le bord. Des cercles se
tiennent aux ticks de `y`, écrits le long du rayon de 0, et des rayons aux ticks de `x`, tous les 30 degrés sauf si
`xticks` les donne, écrits hors du bord avec un signe degré, comme les écrivent les axes polaires de matplotlib.

```cesia
dome = plot.Of([plot.Line([60, 120, 180, 240, 300], [0, 40, 60, 40, 0])], polar = true, ylim = [90, 0])
[x.Text for x in result.Unwrap(plot.Scene(dome, 500, 500)).Items if x.Role == "ylabel"] -->
```

Un graphique polaire est carré, son disque au milieu de la place que laissent les textes. Il dessine [plot.Line],
[plot.Points], [plot.Text] et [plot.Rule], une règle en `x` comme un rayon et en `y` comme un cercle. Une courbe relie
ses points par des segments droits, comme les relient les axes polaires de matplotlib, et est coupée là où elle traverse
le bord, la traversée calculée pour que la courbe finisse dessus ; les points et les textes hors du disque sont laissés
de côté. Une courbe qui finit à droite du bord est nommée, avec `"ends"`, au-delà des labels des angles. Avec un
graphique 3D, un axe log ou `xlim`, `polar` est un `Err`.

### La taille d'un graphique

Un graphique fait 640 pixels sur 400 sauf si `size = [width, height]` donne la sienne, et un graphique polaire 500 sur
500, autant de place que 640 sur 400 dans un carré ; [plot.Svg] et [plot.Save] l'écrivent à cette taille. Sous une
cellule, Cemacs le dessine aussi large que le panneau, jamais plus large que le graphique lui-même, et aussi haut que le
demande la forme de sa taille : un graphique de 640 sur 400 dans un panneau de 500 pixels fait 500 sur 313, et un
graphique polaire reste carré. [plot.Scene] donne cette taille à un back-end quand sa hauteur manque :

```cesia
[result.Unwrap(plot.Scene(dome, 900, missing)).Width, result.Unwrap(plot.Scene(waves, 500, missing)).Height] -->
```

## La course du soleil, avec des formules simples

La page *position du soleil* de SunEarthTools dessine la course du soleil dans le ciel d'un lieu, une courbe pour le 21
de chaque mois, le jour d'aujourd'hui parmi elles en orange avec ses heures, son nom, son lieu et sa date dans un coin,
et chaque courbe nommée à son bout : sur une grille plate et dans un cercle. Cette section dessine un graphique dans son
esprit, avec des jours inventés et lisses plutôt qu'avec l'astronomie. Un jour est ici trois nombres : l'azimut où le
soleil se lève, à l'est du nord, sa hauteur à midi, plein sud, et ses heures de jour. Le soleil tourne d'un pas égal de
son lever à son coucher en `360 - rise`, sa hauteur une demi-sinusoïde :

```cesia allow=read,write
defn sun(rise, noon, light, t)
  (** The sun of an invented day at the times t, in hours: its azimuth and its height, in degrees. *)
  f = (t - (12.0 - light / 2.0)) / light
  {Az: rise + (360.0 - 2.0 * rise) * f, El: noon * math.Sin(math.Pi * f)}
end
day(rise, noon, light) = sun(rise, noon, light, num.Linspace(12.0 - light / 2.0, 12.0 + light / 2.0, 61))
days = [day(58, 72.6, 15.0), day(61, 69.5, 14.6), day(74, 61, 13.4), day(90, 49.2, 12.1), day(106, 38, 10.9), day(118, 29.5, 9.8), day(122, 25.8, 9.3)]
names = ["21 Jun solstice", "21 May-Jul", "21 Apr-Aug", "21 Mar-Sep equinox", "21 Feb-Oct", "21 Jan-Nov", "21 Dec solstice"]
today = day(117, 28, 9.6)
clock = 8..16
hours = sun(117, 28, 9.6, clock)
orange = "#e07000"
where = "name: essai\n  lat: 40.76\n  lon: -73.984\n date: 23/11/2026"
flat = plot.Of(list.Concat([plot.Line(days[k].Az, days[k].El, label = names[k]) for k in 1..7],
  [plot.Line(today.Az, today.El, color = orange, label = "23/11/2026"), plot.Points(hours.Az, hours.El, color = orange, size = 4),
   plot.Text(hours.Az, hours.El, ["$h" for h in clock], color = orange), plot.Rule(x = 180, label = "S")]),
  x = "azimuth", y = "elevation", xlim = [0, 360], ylim = [0, 90], xticks = list.Range(0, 360, step = 45),
  xlabels = ["N", "NE", "E", "SE", "S", "SW", "W", "NW", "N"], yticks = list.Range(0, 90, step = 10), note = where,
  size = [760, 420], title = "Sun path")
plot.Save(flat, "sunpath.svg") -->
```

Les sept jours sont noirs, distingués par leur trait ; aujourd'hui seul a une couleur, comme sur la page. Ses heures sont
un [plot.Text] à côté d'un [plot.Points] : `clock` vaut `8..16`, la forme courte de [list.Range]`(8, 16)`, et les textes
`["$h" for h in clock]` celle de [list.Map]`(h -> "$h", clock)`. La légende est la boîte : les jours finissent tous sur
l'horizon, où des noms à leurs bouts s'entasseraient.

Dans un cercle, l'azimut est l'angle et la hauteur la distance au bord, `ylim = [90, 0]`. Chaque jour est lu de son
coucher à son lever, pour qu'il finisse à l'est, à droite du disque, où `legend = "ends"` écrit son nom, au-delà des
labels du bord :

```cesia allow=read,write
east(d) = {Az: list.Reverse(d.Az), El: list.Reverse(d.El)}
dial = plot.Of(list.Concat([plot.Line(east(days[k]).Az, east(days[k]).El, label = names[k]) for k in 1..7],
  [plot.Line(east(today).Az, east(today).El, color = orange, label = "23/11/2026"), plot.Points(hours.Az, hours.El, color = orange, size = 4),
   plot.Text(hours.Az, hours.El, ["$h" for h in clock], color = orange), plot.Rule(x = 180, label = "S")]),
  polar = true, ylim = [90, 0], xticks = list.Range(0, 350, step = 10), yticks = list.Range(0, 90, step = 10),
  legend = "ends", note = where, size = [760, 560], title = "Sun path")
plot.Save(dial, "sundial.svg") -->
[x.Text for x in result.Unwrap(plot.Scene(dial, 760, 560)).Items if x.Role == "legend"] -->
```

La page dessine une image faite sur son serveur ; ici le graphique est une valeur, dessinée de la même façon par
[plot.Save] et par Cemacs, dans la police du code, noir sur blanc avec la seule couleur qui dit quelque chose.

## Animations

[plot.Frames] fait une *animation* : des graphiques montrés l'un après l'autre, `fps` par seconde (*frames per second*,
des images par seconde), du premier au dernier, puis de nouveau. Ici une onde avance vers la droite, 60 images à 30 par
seconde, deux secondes en tout :

```cesia allow=read,write
use std/text
x = num.Linspace(0.0, 10.0, 200)
wave = plot.Frames([plot.Of([plot.Line(x, math.Sin(x - t))], title = "t = $(text.Decimals(1, t))") for t in num.Linspace(0.0, 6.0, 60)], fps = 30)
plot.Save(wave, "wave.svg") -->
```

La liste des images s'écrit en *list comprehension* (une liste décrite par sa règle), `[f(t) for t in ts]`, la forme
courte de [list.Map] :

```cesia
use std/list
plain = plot.Frames(list.Map(t -> plot.Of([plot.Line(x, math.Sin(x - t))], title = "t = $(text.Decimals(1, t))"), num.Linspace(0.0, 6.0, 60)), fps = 30)
plot.Svg(plain) == plot.Svg(wave) -->
```

Une animation est un graphique : [plot.Svg] et [plot.Save] l'écrivent entière, et [plot.Scene] dessine une de ses
images, `frame` à partir de 1, avec deux champs de plus dans la scène, `Frames`, leur nombre, et `Fps` :

```cesia
one = result.Unwrap(plot.Scene(wave, 640, 400, frame = 30))
[one.Frames, one.Fps, [item.Text for item in one.Items if item.Role == "title"]] -->
```

### Ce qu'une image change

Les images partagent un seul jeu d'axes, pour que les axes ne sautent jamais pendant la lecture. [plot.Frames] vérifie
chaque image une fois, quand elle est faite, et garde l'étendue de chaque layer sur toutes : chaque image est dessinée
sur la réunion de ces étendues, les couleurs d'une heatmap aussi, sauf si `xlim` et `ylim` donnent les axes. Une image
ne change que ses données et son titre ; ses layers, en sorte et en nombre, leurs options, comme une couleur ou un label,
et les options de [plot.Of] sont celles de la première image, sinon l'animation est un `Err` qui nomme la première image
qui diffère :

```cesia
plot.Svg(plot.Frames([plot.Line([1, 2], [1, 2]), plot.Line([1, 2], [2, 1], color = "#000000")])) -->
```

Une animation contient de 1 à 300 images, 10 secondes à 30 par seconde, et `fps` va de 1 à 60. Toutes les images sont en
mémoire : ce sont des valeurs, faites une fois, qui se jouent à leur propre rythme quel que soit leur coût de calcul. Une
image n'est ni une grille ni une animation, et une animation ne va dans aucun [plot.Of] ni aucun [plot.Grid].

### Dans une page web : des images en CSS

*CSS*, Cascading Style Sheets (les feuilles de style), est le langage du style d'une page web, que tout navigateur
applique sans script. Le SVG d'une animation écrit les axes une fois, puis les données et le titre de chaque image dans
un groupe à part. Une règle de CSS cache chaque groupe, et une *animation CSS*, un changement de style au fil du temps,
montre chacun à son tour :

```css
.a60-200000 { visibility: hidden; animation: s60 2000ms step-end infinite; }
@keyframes s60 { 0% { visibility: visible; } 1.6667% { visibility: hidden; } }
```

La boucle dure $N / fps$ secondes, ici 60 images à 30 par seconde, 2 secondes. Chaque groupe est visible pendant les
premiers $100 / N$ pour cent de la boucle, arrondis vers le haut à la quatrième décimale pour qu'une image se voie
toujours, et commence après un délai de $(k - 1) / fps$ secondes, `style="animation-delay:33.33ms"` pour l'image 2 :
l'image $k$ se voit de $(k - 1) / fps$ à $k / fps$ de chaque boucle. `step-end` fait de chaque changement un saut, pas
un fondu. Les noms des règles ne contiennent que des nombres, le nombre d'images et la durée de la boucle, pour que deux
animations d'une même page gardent chacune les leurs, et aucun texte d'un graphique ne va dans le CSS.

Un SVG seul, ouvert dans un navigateur, se joue tout de suite et en boucle ; pour un lecteur qui a demandé moins de
mouvement à son système, le réglage `prefers-reduced-motion`, il reste sur l'image 1. La page d'un fichier de cells,
[cells.Html], la démarre en pause sur l'image 1, sous une case *Play*, une case à cocher de la page que la souris, ou Tab
puis Espace, coche ; voir [Une page à partager](cells.md#une-page-à-partager). Cela suit WCAG 2.2, les règles du W3C pour
des pages accessibles, dont le critère 2.2.2 demande que ce qui bouge plus de 5 secondes puisse se mettre en pause. Un
test vérifie dans Chromium et dans Firefox que l'image $k$ seule se voit sur son intervalle, qu'une page démarre sur
l'image 1, et que la case d'une animation laisse les autres immobiles ; Safari n'est pas vérifié.

Un SVG garde au plus 8 Mo d'images, pour qu'une page se charge vite : au-delà, il garde une image sur $k$, $k$ le plus
petit qui tienne, à $fps / k$ par seconde pour qu'elle dure autant, et une note sous le graphique le dit,
`100 of 300 frames kept`. 300 images d'une onde de 500 points prennent 2,1 Mo ; 300 images de la courbe de Lorenz de
5 000 points prendraient 20 Mo, donc son SVG en garde 100. Cemacs n'en retire jamais : il demande chaque image quand il
la montre.

### Comparé à matplotlib, plotly et MATLAB

| | Cesia | matplotlib `FuncAnimation` | plotly | MATLAB, Octave |
|---|---|---|---|---|
| images | des valeurs, faites une fois, 300 au plus | faites par une fonction à chaque image, autant qu'on veut, sans fin pour `frames=None` | une liste d'images dans la figure | des captures d'écran faites par `getframe` |
| axes | la réunion de toutes les images, calculée | ceux que la fonction et la figure fixent | Plotly Express « will not automatically compute the union of all x/y/color ranges » : on les donne à la main | ceux de la figure à chaque capture |
| lecture | Cemacs, et une page sans script | une fenêtre, ou `to_jshtml`, une page avec un script | dans le navigateur, avec plotly.js et les boutons et le curseur qu'il dessine | `movie(M, n, fps)`, 12 par seconde par défaut |
| fichiers | SVG, 8 Mo au plus | des vidéos et des GIF : `save` avec FFmpeg ou Pillow | du HTML avec son script | `VideoWriter` : Motion JPEG AVI, MPEG-4 et d'autres |

Là où ils gagnent : tous les trois écrivent des fichiers vidéo ou GIF, ce que Cesia ne fait pas ; matplotlib calcule
les images pendant la lecture, donc une animation n'a ni durée ni limite ; plotly passe d'une image à la suivante par
une transition douce, pour ses nuages de points et ses barres, et sa page peut aller à n'importe quelle image avec un
curseur, grâce à un script. Là où Cesia gagne : les axes sont partagés tout seuls, une image qui change plus que ses
données est une erreur qui la nomme, et la page se joue sans script.

## 3D

[plot.Surface] dessine une *surface*, une hauteur au-dessus d'une grille : `z[i, j]` est la hauteur au-dessus du point
`(x[j], y[i])`, donc les lignes de la matrice vont le long de y et ses colonnes le long de x, comme les prend le `surf` de
MATLAB. [plot.Line3] dessine une courbe par des points de l'espace, comme [plot.Line] dans le plan. Voici une ride,
$\sin(2r) / (1 + r)$ à la distance $r$ du milieu, sur une grille de 61 par 61 points :

```cesia allow=read,write
use std/matrix
x = num.Linspace(-3.0, 3.0, 61)
across = matrix.Matmul(matrix.Ones(61, 1), matrix.Reshape([1, 61], x))
r = math.Sqrt(across * across + matrix.Transpose(across) * matrix.Transpose(across))
ripple = plot.Of([plot.Surface(math.Sin(2.0 * r) / (1.0 + r), x = x, y = x)], x = "x", y = "y", z = "height")
plot.Save(ripple, "ripple.svg") -->
```

`across` contient `x[j]` dans chaque colonne $j$, et sa transposée `y[i]` dans chaque ligne $i$ : la grille des deux,
comme la donne `meshgrid` dans MATLAB et numpy. [plot.Of] donne trois options de plus à un graphique 3D : `z`, le nom de
son troisième axe, `zlim`, son étendue, et `view`, l'endroit d'où on le regarde. Un graphique 3D contient une seule
[plot.Surface], ou des couches [plot.Line3], jamais les deux et jamais une couche 2D ; ses axes sont linéaires.

### La vue

Une *vue* (*view*) est faite de deux angles en degrés, `view = [az, el]`, comme les prend le `view` de MATLAB.
L'*azimut* `az` tourne autour de l'axe vertical : 0 regarde depuis le côté de $-y$, vers $+y$, et l'azimut grandit dans le
sens inverse des aiguilles d'une montre vu d'en haut. L'*élévation* `el`, de $-90$ à $90$, est l'angle de l'œil au-dessus
du plan de x et y : 90 regarde d'en haut à la verticale, $-30$ d'en dessous. Sans vue, un graphique prend celle de MATLAB,
`[-37.5, 30]` :

```cesia
result.Unwrap(plot.Scene(ripple, 640, 400)).View -->
result.Unwrap(plot.Scene(ripple, 640, 400, view = [0, 90])).View -->
```

[plot.Scene] prend aussi une `view`, qui tourne le graphique sans le changer : c'est ainsi que Cemacs tourne un graphique,
et le code garde sa propre vue. Les données vont dans une boîte de 1 par 1 par 0,75, comme celle de matplotlib : chaque
axe couvre exactement les données, ou son `xlim`, `ylim` ou `zlim`, et son étendue prend tout le côté de la boîte. La boîte
est vue de très loin, sans perspective, une projection *orthographique*, celle de MATLAB par défaut : des droites
parallèles dans l'espace restent parallèles à l'écran. Avec $p$ un point de la boîte, mesuré depuis son centre, l'œil
regarde le long de $v$, et la droite et le haut de l'écran sont $e_1$ et $e_2$ :

$$v = (\cos el \sin az, -\cos el \cos az, \sin el),\quad e_1 = (\cos az, \sin az, 0),\quad e_2 = (-\sin el \sin az, \sin el \cos az, \cos el)$$

Le point est dessiné en $c + s\,(p \cdot e_1, -p \cdot e_2)$, depuis le centre $c$ du tracé, à $s$ pixels par unité, et sa
profondeur, sa proximité, vaut $p \cdot v$. La boîte tourne dans la sphère qui l'entoure, de rayon
$\sqrt{0.5^2 + 0.5^2 + 0.375^2} \approx 0.8004$, et $s$ fait tenir cette sphère dans le tracé, avec de la place pour les
labels : la boîte garde donc sa taille à chaque vue, comme `axis vis3d` la garde dans MATLAB, et un graphique ne gonfle
pas et ne rétrécit pas quand il tourne. Un test met les 8 coins de la boîte là où ces formules les mettent, à 6 vues.

Les axes sont trois arêtes de la boîte, sur son contour, avec leurs ticks et leurs labels, trouvés comme en 2D par la
recherche de Talbot, Lin et Hanrahan pour la longueur que montre chaque arête : x et y sur les arêtes les plus basses, z
sur l'arête la plus à gauche. Un axe qui pointe vers l'œil ne montre pas de labels, comme z vu d'en haut à la verticale.
Les trois faces du fond de la boîte sont teintées en clair, avec la grille des ticks, comme les dessine matplotlib ; un
test vérifie à 72 vues et 3 tailles que deux textes ne se touchent jamais et que tous restent dans le graphique.

### L'ordre des quads

Une surface est dessinée en *quads* (des quadrilatères), les morceaux à quatre côtés entre quatre points voisins de la
grille, chacun rempli d'une couleur. Peints l'un sur l'autre, le plus proche doit venir en dernier : c'est l'*algorithme
du peintre* (*painter's algorithm*), de Newell, Newell et Sancha (1972), qui dessine les polygones du plus loin au plus
proche. matplotlib trie les polygones par leur profondeur moyenne, et sa propre FAQ dit pourquoi cela échoue : la
« reduction of 3D data down to 2D + z-order scalar », une seule profondeur pour tout un polygone, si bien que « from some
viewing angles » un objet « would appear in front of another object, even though it is physically behind it ».

Une surface n'a besoin d'aucun tri. Ses quads sont posés sur une grille dont x et y sont chacun croissants ou chacun
décroissants, et vue sans perspective, la trace d'un rayon de l'œil sur le plan de x et y est une droite, le long de
laquelle la profondeur croît dans un seul sens. Cette droite coupe les colonnes de la grille dans l'ordre, et les lignes
dans l'ordre. Ainsi, les quads dessinés ligne après ligne depuis le côté du fond, et dans chaque ligne colonne après
colonne depuis le côté du fond, mettent avant lui chaque quad qu'un rayon rencontre derrière un autre :

1. les lignes par y croissant quand $v_y (y_{last} - y_{first}) \ge 0$, sinon par y décroissant ;
2. les colonnes de même, avec $v_x$ et x.

C'est le cas d'une seule nappe de l'ordre de McMillan (1995), qui calcule la visibilité sans profondeur ; Anderson (1982)
parcourt une grille de la même façon pour les lignes cachées. Cet ordre ne coûte rien : le tri qu'il remplace prend
3,3 ms pour 100 par 100 quads et 14 ms pour 200 par 200. Un test dessine des surfaces au hasard, irrégulières en x et en y,
croissantes ou décroissantes, à des vues au hasard et aux vues sur les axes, et vérifie, en des points de l'écran que
couvrent deux quads ou plus, que le quad peint en dernier est le plus proche : 10 grilles dans la boucle de changement,
1 500 dans les tests lents, et 10 500 une fois, sans un échec. La même vérification du tri de matplotlib trouvait de
0,6 % à 29 % de ces points faux, d'une surface plate à une surface rugueuse.

### Couleurs, trous et grandes surfaces

Un quad prend la couleur de la moyenne de ses quatre hauteurs, comme le `plot_surface` de matplotlib les colore, parmi
les 256 de viridis, ou de `colors = "diverging"` comme pour [plot.Heatmap], et une barre de couleurs à côté dit quelle
hauteur est chaque couleur. Il n'y a ni lumière ni arêtes : la couleur seule dit la hauteur, comme dans le `surf` de
MATLAB, dont les couleurs « vary according to the heights ». Un NaN retire les quatre quads qui l'entourent, un *trou*, et
[plot.Scene] le compte dans `Dropped` ; un infini est une erreur qui nomme sa place :

```cesia
plot.Svg(plot.Surface([1, 2; 3, 1.0 / 0.0])) -->
```

Un quad dont un coin dépasse `xlim`, `ylim` ou `zlim` est retiré lui aussi, comme l'`axlim_clip` de matplotlib cache les
« patches with a vertex outside the axes view limits » ; une [plot.Line3] est coupée en un point qui les dépasse, comme
en un NaN.

Une surface dessine jusqu'à 200 par 200 quads exactement. Au-delà de 200 dans une direction, ses points deviennent les
moyennes de blocs de $k$ par $k$ points, $k$ le plus petit qui tienne, x, y et z chacun la moyenne de son bloc, les NaN
mis de côté ; une note sous le graphique le dit :

```cesia
big = matrix.Ones(1000, 300)
[item.Text for item in result.Unwrap(plot.Scene(plot.Surface(big), 640, 400)).Items if item.Role == "note"] -->
```

matplotlib garde par défaut 50 points par direction, « downsampled (by slicing) » : une ligne sur $k$, qui peut enjamber
un pic étroit ; une moyenne en garde une trace, lissée. [plot.Surface] vérifie sa matrice et prend ces moyennes une fois,
quand elle est faite, si bien qu'un graphique tourné encore et encore ne les paie qu'une fois.

### Courbes 3D

[plot.Line3] prend x, y et z, et le label, la couleur, l'épaisseur et le tiret de [plot.Line]. Plusieurs partagent un
graphique, dessinées dans leur ordre, la suivante par-dessus : à la différence d'une surface, deux courbes qui se croisent
en profondeur sont dessinées dans l'ordre des couches, une limite de cette version. Voici le système de Lorenz, résolu par
[std/ode], comme le montre [Méthodes numériques](numerical.md) :

```cesia allow=read,write
use std/ode
lorenz(t, y) = [10.0 * (y[2] - y[1]), y[1] * (28.0 - y[3]) - y[2], y[1] * y[2] - 8.0 / 3.0 * y[3]]
ys = result.Unwrap(ode.Solve(lorenz, [0.0, 50.0], [1.0, 1.0, 1.0])).At(num.Linspace(0.0, 50.0, 5000))
plot.Save(plot.Of([plot.Line3(ys[:, 1], ys[:, 2], ys[:, 3])], x = "x", y = "y", z = "z"), "lorenz.svg") -->
```

### Dans Cemacs et dans une page

Cemacs tourne un graphique 3D d'une cellule ou de `*repl*` quand on le fait glisser à la souris, ou avec les flèches après
`C-c e f` : chaque vue est dessinée par la session, par [cells.Scene] avec `view`, et seules les places des points de la
surface reviennent ; le code garde sa vue. La page de [cells.Html] montre chaque graphique à la vue de son code, et son SVG
a un `<title>` qu'un lecteur d'écran prononce, comme `Surface, 61 × 61 points, z from −0.301 to 0.584`.

### Comparé à matplotlib, plotly et MATLAB

| | Cesia | `mplot3d` de matplotlib | `go.Surface` de plotly | `surf` de MATLAB, d'Octave |
|---|---|---|---|---|
| dessin | des quads du fond vers l'avant, un ordre exact pour une surface, sans tri | des polygones triés par une profondeur chacun, faux à certaines vues selon sa propre FAQ | WebGL (le dessin 3D des navigateurs), un *depth buffer* (la profondeur de chaque pixel, gardée pour ne peindre que le plus proche) | le *depth buffer* de la carte graphique |
| plusieurs surfaces, une courbe sur une surface | non : une surface, ou des courbes 3D | oui, avec les défauts de son tri | oui | oui |
| couleurs | la hauteur moyenne d'un quad, viridis ; ni lumière ni arêtes | une seule couleur ombrée par une lumière par défaut, ou une palette | une échelle de couleurs, et une lumière : ambient 0,8, diffuse 0,8 | la hauteur, `FaceColor` flat, des arêtes sombres par défaut |
| grandes surfaces | des moyennes de blocs au-delà de 200 par 200 quads, dites sous le graphique | 50 points par direction par défaut, en tranches | tous les points | tous les points |
| tourner | Cemacs, par la session ; la page montre la vue du code | une fenêtre | la page, avec plotly.js | une fenêtre, `rotate3d` |

Là où ils gagnent : plotly tourne son graphique dans la page elle-même, avec un script, montre la valeur sous la souris et
dessine des contours sur la surface ; MATLAB, Octave et plotly dessinent plusieurs surfaces qui se croisent, avec lumière
et transparence, comme le fait un *depth buffer* ; tous trois offrent la perspective. Là où Cesia gagne : son image est exacte à chaque vue sans
carte graphique, la même dans Cemacs et dans le SVG, et une grande surface est lissée par des moyennes, dites sous le
graphique, pas coupée en tranches.

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
JetBrains Mono 2.304, la police de son code. Elle est *monospaced* (à chasse fixe) : chacun de ses 1 363 caractères fait
avancer la plume de 0,6 *em*, la taille de la police, sauf les diacritiques combinants, qui ne la font pas avancer, si
bien qu'un label de 12 pixels fait 7,2 pixels par caractère. [std/plot] compte un texte ainsi, en *colonnes*, comme un
terminal les compte, selon les règles du `wcwidth` de Markus Kuhn : une colonne par caractère, aucune pour un
diacritique combinant, un trait d'union conditionnel ou un caractère de largeur nulle, deux pour un caractère large
d'Asie de l'Est, que la police n'a pas et qu'une autre police dessine large d'environ un em. Un test mesure les
caractères des graphiques avec SDL3_ttf, la bibliothèque de texte de Cemacs, et les trouve tous à moins d'un pixel près.

Le SVG nomme d'abord JetBrains Mono, puis la police monospace du navigateur : un lecteur sans JetBrains Mono dessine les
textes dans une autre police à chasse fixe, comme DejaVu Sans Mono, Menlo ou Consolas, dont les caractères sont aussi
larges, 0,6 em ou un peu moins, si bien que la mise en page tient. Un caractère que JetBrains Mono n'a pas, comme le
moins en exposant de `10⁻³`, est dessiné par une autre police, Noto Sans Medium dans Cemacs.

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

Un graphique est noir sur blanc, la grille d'un gris clair, `#d0d0d0`, de 1 pixel de large, comme le cadre et les
courbes. Les layers sans couleur sont noirs, l'encre des axes, et se distinguent par ce que le noir et blanc garde :

| Layers sans couleur | Tour à tour |
|---|---|
| [plot.Line], [plot.Line3], sans `dash` | trait plein, tirets, pointillés, tiret-point |
| [plot.Points], sans `shape` | cercle, carré, triangle, croix |
| les séries de [plot.Bars], [plot.Histogram] | noir, puis l'encre à 60, 40 et 30 % : les gris du style `grayscale` de matplotlib |
| [plot.Area] | l'encre à 30 %, un gris |

Le cinquième d'un genre recommence le tour. Un layer avec une `color` garde un trait plein ou un cercle et ne prend pas
de tour : une couleur se donne là où elle dit quelque chose, pour distinguer des courbes ou en mettre une en avant, comme
le jour d'aujourd'hui parmi les autres. Le même graphique s'imprime et se photocopie en noir et blanc sans perdre une
courbe.

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
chacun un dictionnaire avec un `Kind` (une sorte) et un `Role` (un rôle) ; la scène d'une image d'une animation a aussi
`Frames` et `Fps`, et la scène d'un graphique 3D `View`, le `[az, el]` d'où il est vu :

| Kind | Champs |
|---|---|
| `"line"` | `Xs`, `Ys`, `Color`, `Width`, `Dash` (missing, ou les longueurs tracées et vides) |
| `"area"` | `Xs`, `Ys` autour de la bande, `Color`, `Opacity` |
| `"rect"` | `X`, `Y`, `W`, `H`, `Color`, `Opacity` |
| `"marks"` | `Xs`, `Ys`, les centres, `Shape`, `Size`, `Color` |
| `"cells"` | `Xs` et `Ys`, les bords des colonnes et des lignes, `Colors` ligne après ligne, missing pour une cellule vide |
| `"mesh"` | les quads d'une surface : `Rows` et `Columns`, leurs nombres ; `Xs` et `Ys`, les places des `(Rows + 1) × (Columns + 1)` points, colonne par colonne, au centième de pixel ; `Palette`, ses couleurs ; `Colors`, pour chaque quad colonne par colonne, sa place dans `Palette` à partir de 0, ou -1 pour un trou ; `Order`, `[rowStep, columnStep]`, chacun 1 ou -1 |
| `"text"` | `X`, `Y` sur la ligne de base, `Text`, `Size`, `Color`, `Anchor` (`"start"`, `"middle"` ou `"end"`), `Angle` (0 ou -90), `Width` |

Les coordonnées sont en pixels depuis le coin en haut à gauche. Les éléments des données ont `Clip`, le rectangle
`[x, y, width, height]` du tracé auquel ils sont coupés. Une `Color` vaut `"#rrggbb"`, ou `"ink"` et `"grid"` pour le
cadre, les ticks et les textes, qu'un back-end peint dans les couleurs de son thème, comme il peint `"ink"` pour les
layers sans couleur et `"paper"` pour ce qui cache la grille derrière un texte ; [plot.Svg] les peint en `#000000`,
`#d0d0d0` et `#ffffff`. Le `Role` dit ce qu'est un élément : `"grid"`, `"data"`, `"frame"`, `"tick"`, `"xlabel"`,
`"ylabel"` et `"zlabel"` pour les labels des ticks, `"factor"` pour la puissance de dix ou l'offset d'un axe, `"title"`,
`"xtitle"`, `"ytitle"`, `"ztitle"`, `"legend"`, `"colorbar"`, `"note"`, une ligne sous le graphique, ou `"info"`, la
boîte de l'option `note`, son papier et ses lignes ; en 3D, `"pane"` pour les faces du fond de la boîte et `"axis"` pour
les arêtes qui portent les labels. Un graphique polaire a les mêmes rôles : ses rayons et ses cercles sont `"grid"`, son
bord `"frame"`, les labels de ses angles `"xlabel"` et ceux de ses cercles `"ylabel"`. Les labels de `legend = "ends"`
ont le rôle `"legend"`.

Un back-end dessine un mesh (un maillage) selon son `Order` : les lignes depuis la première quand `rowStep` vaut 1, depuis
la dernière quand il vaut -1, et dans chaque ligne les colonnes de même ; chaque quad est le chemin par ses points
$(i, j)$, $(i + 1, j)$, $(i + 1, j + 1)$ et $(i, j + 1)$, où le point $(i, j)$ est le numéro $(j - 1)(Rows + 1) + i$ de `Xs`
et `Ys`. [plot.Svg] écrit chaque quad comme un chemin de sa couleur dans un groupe avec `shape-rendering="crispEdges"`,
pour qu'aucun fil clair ne se voie entre deux quads ; Cemacs coupe chacun en deux triangles de sa couleur. À une vue
rasante, un quad replié sur lui-même peut différer d'un pixel ou deux entre les deux, dans sa propre couleur.

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
le tracé ; en 3D, une surface de moins de 2 par 2 points, un infini dedans, un x ou un y qui ni ne croît ni ne décroît,
une vue qui n'est pas `[az, el]` avec `el` de -90 à 90, un graphique 3D qui contient plus d'une surface ou un layer 2D, et
`z`, `zlim` ou `view` sur un graphique 2D :

```cesia
plot.Svg(plot.Of([plot.Surface([1, 2; 3, 4]), plot.Line3([1, 2], [1, 2], [1, 2])])) -->
```

## Vitesse

Un programme qui ne se sert pas de [std/plot] démarre aussi vite qu'avant : 2,8 ms pour `io.Print(1)`. `use std/plot`
charge ses 3 000 lignes en environ 11 ms la première fois, avant que le cache des packages chargés les garde ; une fois
qu'il les garde, un premier graphique, du début du programme à son SVG, prend 7 ms.
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

Une animation de 300 images d'une onde de 500 points se fait en 21 ms, la vérification de chaque image et de leurs
étendues communes, et s'écrit en SVG en 0,43 s, 2,1 Mo. Une image de la courbe de Lorenz, 5 000 points, se dessine en
scène en 1,2 ms ; son SVG de 300 images, réduit à 100, prend 2,8 s. Dans Cemacs, une de ses images revient de la session
en 10 ms environ, et elle se joue à 29 ou 30 images par seconde.

Une surface de 100 par 100 quads est vérifiée et ses quads colorés une seule fois, quand [plot.Surface] la fait, en
6,2 ms ; ensuite une scène d'elle à une nouvelle vue prend 2,9 ms, les places de ses 10 201 points et les axes,
et son JSON 3,4 ms, 192 Ko ; son SVG prend 38 ms, 855 Ko. Une surface de 1 000 par 1 000 points se fait en
119 ms, les moyennes de ses blocs de 5 par 5 comprises, puis se dessine aussi vite qu'une de 200 par 200. Dans Cemacs,
une surface de 100 par 100 quads tourne en 30 ms par pas, de la touche à la frame qui montre la nouvelle vue.

### À côté de matplotlib

Les mêmes graphes par matplotlib 3.11.2 sur Agg (son moteur de dessin en pixels), sur la machine de
[Vitesse](speed.md#à-côté-des-géants), le 2026-11-19 : chacun mesuré à l'intérieur de son programme, après un premier
graphe dessiné et non mesuré, pour que le temps soit celui du dessin et non du chargement ; la médiane de 101 lancements
alternés, et l'intervalle à 95 % de cette médiane :

| | Cesia | matplotlib 3.11.2 |
|---|---:|---:|
| une ligne de 1 000 000 de points, en SVG | **28,2 ms** (28,1 à 28,2) | 113,1 ms (112,8 à 113,4) |
| une surface de 100 sur 100 quads, une nouvelle vue | **3,17 ms** (3,15 à 3,18), une scène | 75,27 ms (74,98 à 75,46), `view_init` et un dessin |
| la même surface, en SVG | **33,9 ms** (33,8 à 34,1) | 804,1 ms (801,2 à 809,5) |

matplotlib dessine la ligne avec sa simplification des chemins, active par défaut, et la surface avec chaque point,
`rstride = cstride = 1`, comme Cesia dessine chaque quad ; avec son réglage par défaut de 50 points par direction, il en
dessinerait le quart. Une vue n'est pas le même travail chez les deux : celle de Cesia est une scène, les formes en
pixels que Cemacs peint ensuite, la moyenne de 20 vues ; celle de matplotlib est un dessin de la figure sur Agg, ses
pixels peints, ce que fait une fenêtre de `mplot3d` à chaque glissement de la souris, la moyenne de 20 vues aussi.
matplotlib ne gagne aucune des trois ; sa vue donne des pixels prêts à montrer, là où Cesia laisse la peinture à Cemacs.

## Limites

- Du SVG seulement, pour l'instant ; le PNG viendra avec un rasterizer (le code qui change un dessin en pixels) choisi
  sur mesure.
- Une seule police est mesurée, JetBrains Mono ; une autre police à chasse fixe dessine aussi large ou un peu plus
  étroit, une police proportionnelle plus étroit.
- La légende et la barre de couleurs sont à droite du tracé, ou les noms aux bouts des courbes ; les barres sont debout ;
  un graphique contient un seul [plot.Bars].
- Un graphique polaire dessine des courbes, des points, des textes et des règles, sur des axes linéaires, un tour entier ;
  pas encore de barres ni de bandes dans un cercle.
- Une courbe dont le x va et vient garde tous ses points ; au-delà de 200 000 marqueurs, prenez [plot.Density].
- Pas de zoom dans cette version. Une animation contient au plus 300 images, toutes en mémoire, et s'écrit en SVG, pas
  en vidéo ni en GIF.
- En 3D : une surface par graphique, ou des courbes, jamais les deux ; ni perspective, ni lumière, ni arêtes, ni
  transparence, ni contours sur la surface, ni points ni échelles logarithmiques en 3D ; les courbes 3D sont dessinées
  dans l'ordre de leurs layers ; une grille ou une animation de graphiques 3D les montre à la vue de leur code, et Cemacs
  ne les tourne pas ; une page montre la vue du code.

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
- Stéfan van der Walt, Nathaniel Smith. "matplotlib colormaps", la page des cartes de couleurs qu'ils ont conçues pour
  être celles de matplotlib par défaut, avec leur exposé à SciPy 2015. <https://bids.github.io/colormap/>. Viridis,
  d'après la table de matplotlib 3.11.
- Mark Harrower, Cynthia A. Brewer. "ColorBrewer.org: An Online Tool for Selecting Colour Schemes for Maps". *The
  Cartographic Journal* 40(1):27–37, 2003. <https://doi.org/10.1179/000870403235002042>. RdBu.
- J. E. Bresenham. "Algorithm for computer control of a digital plotter". *IBM Systems Journal* 4(1):25–30, 1965.
  <https://doi.org/10.1147/sj.41.0025>. Les pixels d'une ligne, dans le test de M4.
- W3C. *CSS Animations Level 1*. <https://www.w3.org/TR/css-animations-1/>. Les keyframes (les étapes d'une animation
  CSS), les délais et `step-end` des images d'une animation.
- W3C. *Media Queries Level 5*, `prefers-reduced-motion`. <https://www.w3.org/TR/mediaqueries-5/#prefers-reduced-motion>.
  L'animation qui reste sur l'image 1.
- W3C. *Web Content Accessibility Guidelines (WCAG) 2.2*, critère de succès 2.2.2, Pause, Stop, Hide.
  <https://www.w3.org/TR/WCAG22/#pause-stop-hide>. La page qui démarre en pause.
- Martin E. Newell, Richard G. Newell, Tom L. Sancha. "A solution to the hidden surface problem". *Proceedings of the
  ACM Annual Conference*, 443–450, 1972. <https://doi.org/10.1145/800193.569954>. L'algorithme du peintre.
- Leonard McMillan. *Computing Visibility Without Depth*. Rapport technique TR95-047, University of North Carolina at
  Chapel Hill, 1995. L'ordre d'une grille projetée, une seule nappe sans perspective.
- Peter R. Anderson. "Hidden Line Elimination in Projected Grid Surfaces". *ACM Transactions on Graphics*
  1(4):274–288, 1982. <https://doi.org/10.1145/357311.357313>. Une grille parcourue dans l'ordre, pour les lignes cachées.
- MathWorks. *view*, la documentation de la ligne de visée de la caméra de MATLAB.
  <https://www.mathworks.com/help/matlab/ref/view.html>. L'azimut, l'élévation et la vue `[-37.5, 30]`.
- L'équipe de développement de Matplotlib. *mplot3d FAQ*, "My 3D plot doesn't look right at certain viewing angles",
  et `Axes3D.plot_surface`. <https://matplotlib.org/stable/api/toolkits/mplot3d/faq.html>. Le tri de matplotlib, son
  sous-échantillonnage et `axlim_clip`.
- Markus Kuhn. *wcwidth*, les largeurs des caractères d'Unicode dans un terminal, 2007.
  <https://www.cl.cam.ac.uk/~mgk25/ucs/wcwidth.c>. Les colonnes d'un texte : aucune, une ou deux.
- JetBrains. *JetBrains Mono*, version 2.304, SIL Open Font License 1.1. <https://www.jetbrains.com/lp/mono/>. La police
  des textes, chacun de ses caractères large de 600 millièmes d'em.

## La suite

Vous savez dessiner ce que vous calculez. Le chapitre suivant, [Méthodes numériques](numerical.md), trouve les zéros et
les minima des fonctions, résout les équations différentielles et les systèmes sparse (dont la matrice est presque toute
faite de zéros), et calcule des intégrales.
