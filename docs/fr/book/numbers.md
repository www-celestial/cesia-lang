# Nombres et algorithmes

Dans ce chapitre, vous découvrez les bibliothèques de calcul : [std/math] pour un nombre seul, [std/num] pour les arrays
(les listes et les matrices de nombres), les matrices et les statistiques, [std/lapack] pour les grandes matrices,
[std/algo] pour les algorithmes classiques, et trois structures à côté des listes et des dictionnaires : les sets (des
ensembles sans doublon), les queues (des files) et les heaps (des tas, qui rendent d'abord la plus petite clé). Chaque
fonction est dans la référence, avec ses exemples ; ce chapitre montre à quoi sert chaque bibliothèque, et ce qu'elle
coûte.

> [!NOTE]
> Les exemples de std/math et de std/num ont des onglets : le même calcul en Python avec numpy, en R et en MATLAB.
> Chaque onglet tourne quand le livre est vérifié, et affiche ce que montre la version Cesia ; les onglets MATLAB
> tournent dans GNU Octave. Voir [Onglets dans d'autres langages](tests.md#onglets-dans-dautres-langages).

## Un nombre : std/math

[std/math] contient les opérateurs sous forme de fonctions, [math.Add], [math.Sub], [math.Mul], [math.Div] et [math.Mod],
et [math.Inc] et [math.Dec] ; les arrondis, [math.Round], [math.Floor] et [math.Ceil] ; [math.Abs] et [math.Sign] ; les
racines, les puissances et les logarithmes, [math.Sqrt], [math.Exp] et [math.Log] ; la trigonométrie en radians,
[math.Sin], [math.Cos], [math.Tan], [math.Asin], [math.Acos], [math.Atan], et [math.Atan2] pour l'angle d'un point ; les
constantes [math.Pi], [math.Nan] et [math.Inf], `1.0 / 0.0` ; et les tests [math.IsZero], [math.IsPos], [math.IsNeg],
[math.IsEven] et [math.IsOdd]. Chaque fonction d'un seul nombre marche aussi sur un array, élément par élément. Les
sections après les bits ajoutent les autres logarithmes et racines, les fonctions hyperboliques, les angles en degrés,
le journal d'un capteur nettoyé avec elles, les bords des floats et les constantes physiques de [std/constants].

```cesia
use std/math
math.Ceil(2.1) -->
math.Sign(-3) -->
math.Atan2(1.0, 1.0) * 4 -->
math.Log(math.Exp(2.0)) -->
math.Sqrt([4, 9]) -->
math.IsEven(10) -->
```

```python
import numpy as np
print(np.ceil(2.1))
print(np.sign(-3))
print(np.arctan2(1.0, 1.0) * 4)
print(np.log(np.exp(2.0)))
print(np.sqrt([4, 9]))
print(10 % 2 == 0)
```

```r
print(ceiling(2.1))
print(sign(-3))
print(atan2(1, 1) * 4)
print(log(exp(2)))
print(sqrt(c(4, 9)))
print(10 %% 2 == 0)
```

```matlab
disp(ceil(2.1))
disp(sign(-3))
disp(atan2(1, 1) * 4)
disp(log(exp(2)))
disp(sqrt([4 9]))
disp(mat2str(mod(10, 2) == 0))
```

[math.Div] arrondit vers le bas, vers moins l'infini, et [math.Mod] a le signe du diviseur : `math.Mod(-7, 3)` vaut donc
`2`, et `math.Div(-7, 3) * 3 + math.Mod(-7, 3)` redonne `-7`. C'est la *floored division* (la division arrondie vers le
bas) de Python, pas la division *tronquée* (arrondie vers zéro) du C et de Java, où `-7 % 3` vaut `-1`.

```cesia
math.Div(-7, 3) -->
math.Mod(-7, 3) -->
```

```python
print(-7 // 3)
print(-7 % 3)
```

```r
print(-7 %/% 3)
print(-7 %% 3)
```

```matlab
disp(floor(-7 / 3))
disp(mod(-7, 3))
```

### Les bits

[math.BitAnd], [math.BitOr], [math.BitXor] et [math.BitNot] travaillent sur les bits des entiers, et [math.BitShift] les
décale vers la gauche pour un nombre de positions positif, vers la droite pour un nombre négatif. Un décalage à droite
garde le signe, comme en Python et en Go ; un décalage à gauche travaille sur les 63 bits d'un entier, et les bits qui en
sortent sont perdus :

```cesia
math.BitAnd(12, 10) -->
math.BitOr(12, 10) -->
math.BitXor(12, 10) -->
math.BitShift(1, 4) -->
math.BitShift(16, -2) -->
math.BitShift(-8, -1) -->
```

```python
print(12 & 10)
print(12 | 10)
print(12 ^ 10)
print(1 << 4)
print(16 >> 2)
print(-8 >> 1)
```

```r
print(bitwAnd(12L, 10L))
print(bitwOr(12L, 10L))
print(bitwXor(12L, 10L))
print(bitwShiftL(1L, 4L))
print(bitwShiftR(16L, 2L))
print(-8L %/% 2L)
```

```matlab
disp(bitand(12, 10))
disp(bitor(12, 10))
disp(bitxor(12, 10))
disp(bitshift(1, 4))
disp(bitshift(16, -2))
disp(floor(-8 / 2))
```

### Logarithmes, racines et fonctions hyperboliques

À côté de [math.Log] et [math.Exp], [math.Log10] et [math.Log2] sont les logarithmes en base 10 et 2 ; [math.Log1p] est
`log(1 + x)` et [math.Expm1] est `exp(x) - 1`, qui gardent leurs chiffres pour un petit `x`, là où `1 + x` les a déjà
perdus. [math.Cbrt] est la racine cubique de tout nombre, négatif aussi, et [math.Hypot] est `sqrt(x^2 + y^2)`, la
longueur du grand côté d'un triangle rectangle, sans l'overflow (le dépassement du plus grand float) des carrés.
[math.Sinh], [math.Cosh] et [math.Tanh] sont les fonctions hyperboliques, et [math.Asinh], [math.Acosh] et [math.Atanh]
leurs inverses. Chacune marche sur un nombre et sur un array, élément par élément.

```cesia
math.Log10(1000) -->
math.Log2(1024) -->
math.Log1p(1e-12) -->
math.Log(1 + 1e-12) -->
math.Expm1(1e-12) -->
math.Cbrt([27, -8, 1000]) -->
math.Hypot(3, 4) -->
math.Hypot(1e200, 1e200) -->
math.Tanh(0.5) -->
math.Atanh(0.6) -->
```

```python
import numpy as np
print(np.log10(1000))
print(np.log2(1024))
print(np.log1p(1e-12))
print(np.log(1 + 1e-12))
print(np.expm1(1e-12))
print(np.round(np.cbrt([27, -8, 1000]), 12))
print(np.hypot(3, 4))
print(np.hypot(1e200, 1e200))
print(np.tanh(0.5))
print(np.arctanh(0.6))
```

```r
print(log10(1000))
print(log2(1024))
print(sprintf("%.16g", log1p(1e-12)))
print(sprintf("%.16g", log(1 + 1e-12)))
print(sprintf("%.16g", expm1(1e-12)))
x <- c(27, -8, 1000)
print(sign(x) * round(abs(x)^(1/3), 12))
print(Mod(complex(real = 3, imaginary = 4)))
print(Mod(complex(real = 1e200, imaginary = 1e200)))
print(tanh(0.5))
print(atanh(0.6))
```

```matlab
disp(log10(1000))
disp(log2(1024))
disp(sprintf('%.16g', log1p(1e-12)))
disp(sprintf('%.16g', log(1 + 1e-12)))
disp(sprintf('%.16g', expm1(1e-12)))
disp(nthroot([27 -8 1000], 3))
disp(hypot(3, 4))
disp(hypot(1e200, 1e200))
disp(tanh(0.5))
disp(atanh(0.6))
```

`math.Log(1 + 1e-12)` est faux dès son cinquième chiffre : `1 + 1e-12` est arrondi au float le plus proche avant que le
logarithme ne le voie. [math.Cbrt] est correctly rounded (arrondie correctement : le float le plus proche de la vraie
racine), si bien que `math.Cbrt(27)` vaut `3.0` : le `np.cbrt(27.0)` de numpy vaut `3.0000000000000004`, venu de la
bibliothèque C, et l'onglet Python l'arrondit pour montrer les mêmes nombres.

### Les angles en degrés

[math.Radians] change des degrés en radians, et [math.Degrees] des radians en degrés. [math.SinDegrees],
[math.CosDegrees] et [math.TanDegrees] prennent eux-mêmes des degrés, et réduisent d'abord l'angle exactement, si bien
que le sinus de 180 degrés vaut `0.0` et celui de 30 degrés `0.5`, là où le sinus des radians, arrondis, s'écarte un
peu :

```cesia
math.SinDegrees([30, 90, 180]) -->
math.Sin(math.Radians([30, 90, 180])) -->
math.CosDegrees(90) -->
math.TanDegrees(45) -->
math.Degrees(math.Atan(1.0)) -->
```

```python
import numpy as np
print(np.round(np.sin(np.radians([30, 90, 180])), 15))
print(np.sin(np.radians([30, 90, 180])))
print(round(np.cos(np.radians(90)), 15))
print(round(np.tan(np.radians(45)), 15))
print(np.degrees(np.arctan(1.0)))
```

```r
print(sinpi(c(30, 90, 180) / 180))
print(sprintf("%.17g", sin(c(30, 90, 180) * pi / 180)))
print(cospi(90 / 180))
print(tanpi(45 / 180))
print(atan(1) * 180 / pi)
```

```matlab
disp(sind([30 90 180]))
disp(sprintf('%.17g ', sin(deg2rad([30 90 180]))))
disp(cosd(90))
disp(tand(45))
disp(rad2deg(atan(1)))
```

Les fonctions arc en degrés sont [math.Degrees] des fonctions arc : le `asind(x)` de MATLAB est
`math.Degrees(math.Asin(x))`.

### Le journal d'un capteur, nettoyé

Une station météo écrit une ligne toutes les dix minutes : la température en °C, l'humidité en %, d'où vient le vent en
degrés et sa vitesse en m/s, et la pluie en mm. En voici huit lignes, telles qu'un capteur les donne : une température
manque, la ligne perdue, et une autre est NaN (not a number, le float qui n'est pas un nombre), `0.0 / 0.0`, une
division par un compte nul dans le firmware (le logiciel embarqué) de la station ; deux humidités sortent de 0..100, et
le vent tourne autour du nord.

```cesia
use std/list
use std/num
use std/value
temp = [12.4, 12.9, missing, 13.8, 0.0 / 0.0, 14.6, 15.1, 15.3]
humidity = [81.0, 79.5, 78.2, 104.3, 76.0, -2.0, 74.1, 73.0]
direction = [350.0, 10.0, 20.0, 355.0, 5.0, 15.0, 0.0, 345.0]
speed = [3.1, 2.8, 4.0, 3.5, 2.2, 3.9, 4.4, 3.0]
rain = [0.0, 0.0, 0.2, 1.5, 12.0, 0.4, 0.0, 30.0]
```

**1. Trouver les trous.** [math.IsNan] trouve le NaN, et `value.IsMissing` la valeur missing (absente) : ce n'est pas la
même chose, un nombre qui a mal tourné et pas de nombre du tout, mais les deux sont des trous. numpy et MATLAB n'ont que
NaN pour les deux, et R a les deux, `NaN` et `NA`, que `is.na` trouve ensemble ; l'onglet MATLAB de l'étape 2 remplit
par indices, `fillmissing` étant dans un paquet d'Octave. [math.IsFinite] garde les nombres qui ne sont ni l'un ni
l'autre, et l'infini d'un capteur cassé partirait avec eux :

```cesia
holes = [value.IsMissing(x) or math.IsNan(x) for x in temp]
holes -->
list.Sum(holes) -->
good = [x for x in temp if math.IsFinite(x)]
list.Mean(good) -->
```

```python
import numpy as np
temp = np.array([12.4, 12.9, np.nan, 13.8, np.nan, 14.6, 15.1, 15.3])
holes = np.isnan(temp)
print(holes)
print(holes.sum())
good = temp[np.isfinite(temp)]
print(good.mean())
```

```r
temp <- c(12.4, 12.9, NA, 13.8, NaN, 14.6, 15.1, 15.3)
holes <- is.na(temp)
print(holes)
print(sum(holes))
good <- temp[is.finite(temp)]
print(mean(good))
```

```matlab
temp = [12.4 12.9 NaN 13.8 NaN 14.6 15.1 15.3];
holes = isnan(temp);
disp(mat2str(holes))
disp(sum(holes))
good = temp(isfinite(temp));
disp(mean(good))
```

**2. Les remplir.** [num.ReplaceNan] met une valeur à la place de chaque NaN et de chaque valeur missing : ici la
moyenne des bonnes températures, et pas de pluie pour une mesure que le pluviomètre a perdue,
`num.ReplaceNan(0.0, rain)`.

```cesia
filled = num.ReplaceNan(list.Mean(good), temp)
filled -->
```

```python
import numpy as np
temp = np.array([12.4, 12.9, np.nan, 13.8, np.nan, 14.6, 15.1, 15.3])
good = temp[np.isfinite(temp)]
filled = np.nan_to_num(temp, nan=good.mean())
print(filled)
```

```r
temp <- c(12.4, 12.9, NA, 13.8, NaN, 14.6, 15.1, 15.3)
good <- temp[is.finite(temp)]
filled <- replace(temp, is.na(temp), mean(good))
print(filled)
```

```matlab
temp = [12.4 12.9 NaN 13.8 NaN 14.6 15.1 15.3];
good = temp(isfinite(temp));
filled = temp;
filled(isnan(filled)) = mean(good);
disp(filled)
```

**3. Écrêter ce qui ne peut pas être.** Une humidité va de 0 à 100 % : [math.Clamp] garde chaque mesure dans cet
intervalle, et une borne qu'elle dépasse devient la borne elle-même.

```cesia
math.Clamp(0, 100, humidity) -->
```

```python
import numpy as np
humidity = np.array([81.0, 79.5, 78.2, 104.3, 76.0, -2.0, 74.1, 73.0])
print(np.clip(humidity, 0, 100))
```

```r
humidity <- c(81.0, 79.5, 78.2, 104.3, 76.0, -2.0, 74.1, 73.0)
print(pmin(pmax(humidity, 0), 100))
```

```matlab
humidity = [81.0 79.5 78.2 104.3 76.0 -2.0 74.1 73.0];
disp(mat2str(min(max(humidity, 0), 100)))
```

**4. Faire la moyenne du vent.** La moyenne des directions vaut 137.5 degrés, sud-est, pour un vent qui souffle du nord
tout du long : 350 et 10 sont à 20 degrés l'un de l'autre, pas à 340. Le vent moyen est la moyenne de ses vecteurs, est
et nord, avec [math.SinDegrees] et [math.CosDegrees] ; un vent venu d'une direction souffle vers le côté opposé, d'où
les signes moins. [math.Atan2] redonne la direction du vecteur moyen, et [math.Hypot] sa vitesse :

```cesia
list.Mean(direction) -->
east = -speed * math.SinDegrees(direction)
north = -speed * math.CosDegrees(direction)
math.Degrees(math.Atan2(-list.Mean(east), -list.Mean(north))) -->
math.Hypot(list.Mean(east), list.Mean(north)) -->
```

```python
import numpy as np
direction = np.array([350.0, 10.0, 20.0, 355.0, 5.0, 15.0, 0.0, 345.0])
speed = np.array([3.1, 2.8, 4.0, 3.5, 2.2, 3.9, 4.4, 3.0])
print(direction.mean())
east = -speed * np.sin(np.radians(direction))
north = -speed * np.cos(np.radians(direction))
print(np.degrees(np.arctan2(-east.mean(), -north.mean())))
print(np.hypot(east.mean(), north.mean()))
```

```r
direction <- c(350, 10, 20, 355, 5, 15, 0, 345)
speed <- c(3.1, 2.8, 4.0, 3.5, 2.2, 3.9, 4.4, 3.0)
print(mean(direction))
east <- -speed * sinpi(direction / 180)
north <- -speed * cospi(direction / 180)
print(atan2(-mean(east), -mean(north)) * 180 / pi)
print(Mod(complex(real = mean(east), imaginary = mean(north))))
```

```matlab
direction = [350 10 20 355 5 15 0 345];
speed = [3.1 2.8 4.0 3.5 2.2 3.9 4.4 3.0];
disp(mean(direction))
east = -speed .* sind(direction);
north = -speed .* cosd(direction);
disp(rad2deg(atan2(-mean(east), -mean(north))))
disp(hypot(mean(east), mean(north)))
```

Le vent moyen vient de 3.1 degrés, un peu à l'est du nord, à 3.3 m/s : un peu moins que la moyenne des vitesses, car le
vent n'a pas soufflé d'une seule direction tout du long.

**5. Mettre la pluie sur une échelle log.** La pluie vaut 0 la plupart du temps et 30 mm dans un orage : sur un
graphique, l'orage cache le reste. Un logarithme les étale, mais `math.Log10(0)` vaut `-math.Inf` ; [math.Log1p],
`log(1 + x)`, vaut 0 en 0, reste proche de `x` pour une petite pluie, et croît comme le logarithme pour une grande :

```cesia
math.Log10(rain) -->
math.Log1p(rain) -->
```

```python
import numpy as np
rain = np.array([0.0, 0.0, 0.2, 1.5, 12.0, 0.4, 0.0, 30.0])
with np.errstate(divide="ignore"):
    print(np.log10(rain))
print(np.log1p(rain))
```

```r
rain <- c(0.0, 0.0, 0.2, 1.5, 12.0, 0.4, 0.0, 30.0)
print(log10(rain))
print(log1p(rain))
```

```matlab
rain = [0.0 0.0 0.2 1.5 12.0 0.4 0.0 30.0];
disp(log10(rain))
disp(log1p(rain))
```

```cesia allow=read,write
use std/plot
times = list.Range(0, 70, step = 10)
rainPlot = plot.Of([plot.Line(times, math.Log1p(rain), label = "log1p(rain)"), plot.Points(times, math.Log1p(rain))],
  title = "Rain on a log scale: math.Log1p keeps the dry readings at 0", x = "minutes", y = "log(1 + mm)", size = [640, 340])
plot.Save(rainPlot, "numbers-rain.svg") -->
```

**6. Un interrupteur.** Le chauffage du boîtier de la station s'allume sous 14 °C : [math.Step] vaut 0 sous 0 et 1
au-dessus, la marche de Heaviside, et `zero` sa valeur en 0 même, 0.5 quand on ne la donne pas, comme le `heaviside`
de MATLAB.

```cesia
math.Step(14 - filled, zero = 0) -->
```

```python
import numpy as np
temp = np.array([12.4, 12.9, np.nan, 13.8, np.nan, 14.6, 15.1, 15.3])
filled = np.nan_to_num(temp, nan=temp[np.isfinite(temp)].mean())
print(np.heaviside(14 - filled, 0))
```

```r
temp <- c(12.4, 12.9, NA, 13.8, NaN, 14.6, 15.1, 15.3)
filled <- replace(temp, is.na(temp), mean(temp[is.finite(temp)]))
print(as.numeric(14 - filled > 0))
```

```matlab
temp = [12.4 12.9 NaN 13.8 NaN 14.6 15.1 15.3];
filled = temp;
filled(isnan(filled)) = mean(temp(isfinite(temp)));
disp(double(14 - filled > 0))
```

### Les bords des floats

Un float a 53 bits : [math.Epsilon] est l'écart entre un nombre et le float suivant au-dessus, si bien que
`math.Epsilon(1.0)` est le machine epsilon (l'écart entre 1 et le float suivant), et [math.NextAfter] est ce float
suivant. [math.MaxFloat] est le plus grand float, [math.MinFloat] le plus petit float normal, [math.MaxInt] et
[math.MinInt] les bornes des entiers de Cesia sur 63 bits, et [math.E] la base du logarithme naturel. [math.IsInf]
trouve les infinis que laisse un overflow, et [math.LogSumExp] est `log(sum(exp(xs)))` sans cet overflow, le
dénominateur du softmax (la fonction qui change des scores en probabilités) du machine learning (l'apprentissage
automatique) :

```cesia
math.Epsilon(1.0) -->
math.Epsilon(1e9) -->
math.NextAfter(1.0, 2.0) -->
math.MaxFloat -->
math.MinFloat -->
math.E -->
math.IsInf(math.Exp([700.0, 710.0])) -->
math.LogSumExp([1000.0, 1001.0, 1002.0]) -->
```

```python
import numpy as np
import scipy.special
print(np.finfo(float).eps)
print(np.spacing(1e9))
print(np.nextafter(1.0, 2.0))
print(np.finfo(float).max)
print(np.finfo(float).tiny)
print(np.e)
with np.errstate(over="ignore"):
    print(np.isinf(np.exp([700.0, 710.0])))
print(scipy.special.logsumexp([1000.0, 1001.0, 1002.0]))
```

```r
print(sprintf("%.16g", .Machine$double.eps))
print(sprintf("%.16g", 2^(floor(log2(1e9)) - 52)))
print(sprintf("%.17g", 1 + .Machine$double.eps))
print(sprintf("%.17g", .Machine$double.xmax))
print(sprintf("%.17g", .Machine$double.xmin))
print(sprintf("%.16g", exp(1)))
print(is.infinite(exp(c(700, 710))))
x <- c(1000, 1001, 1002)
print(sprintf("%.16g", max(x) + log(sum(exp(x - max(x))))))
```

```matlab
disp(sprintf('%.16g', eps))
disp(sprintf('%.16g', eps(1e9)))
disp(sprintf('%.17g', 1 + eps))
disp(sprintf('%.17g', realmax))
disp(sprintf('%.17g', realmin))
disp(sprintf('%.16g', exp(1)))
disp(mat2str(isinf(exp([700 710]))))
x = [1000 1001 1002];
disp(sprintf('%.16g', max(x) + log(sum(exp(x - max(x))))))
```

### Constantes physiques : std/constants

[std/constants] contient les 355 constantes de CODATA 2022, les valeurs que publie le NIST, par leurs noms dans sa
table : [constants.Value] donne la valeur, [constants.Unit] l'unité, [constants.Uncertainty] l'incertitude type, 0 pour
les constantes exactes, et [constants.Find] les noms qui contiennent un mot. L'énergie d'un photon de lumière verte,
532 nm, vaut `h c / lambda` :

```cesia
use std/constants
constants.Find("Planck") -->
planck = constants.Value("Planck constant")
light = constants.Value("speed of light in vacuum")
planck * light / 532e-9 -->
planck * light / 532e-9 / constants.Value("elementary charge") -->
constants.Unit("Newtonian constant of gravitation") -->
constants.Uncertainty("Newtonian constant of gravitation") -->
```

```python
import scipy.constants as sc
print(sc.find("Planck"))
h = sc.value("Planck constant")
c = sc.value("speed of light in vacuum")
print(h * c / 532e-9)
print(h * c / 532e-9 / sc.value("elementary charge"))
print(sc.unit("Newtonian constant of gravitation"))
print(sc.physical_constants["Newtonian constant of gravitation"][2])
```

### Ce qu'elles promettent

Chaque fonction a tourné sur 100 000 entrées, ses bords parmi elles, à côté de numpy 2.5, R 4.6 et GNU Octave 11 (pour
MATLAB), et a été comparée à mpmath sur 300 bits pour 20 000 d'entre elles : le nombre de résultats qui ne sont pas le
float le plus proche de la valeur exacte, et la plus grande erreur, en ulps (units in the last place : l'écart entre
deux floats voisins).

| Fonction | Cesia | numpy | R | MATLAB (Octave) |
|---|---|---|---|---|
| [math.Cbrt] | 0 | 10 055, 3 ulps | 15 888, 120 ulps | 10 055, 3 ulps |
| [math.Sinh], [math.Cosh], [math.Asinh], [math.Acosh], [math.Atanh] | 0 | 0 | 0 | 0 |
| [math.Tanh] | 0 | 2 578, 1 ulp | 0 | 0 |
| [math.Log2] | 34, 1 ulp | pareil | pareil | pareil |
| [math.Log1p] | 41, 1 ulp | pareil | 130, 1 ulp | pareil |
| [math.Expm1] | 541, 1 ulp | pareil | 606, 1 ulp | pareil |
| [math.Log10] | 2 868, 2 ulps | pareil | pareil | pareil |
| [math.Hypot] | 16, 1 ulp | pareil | pareil | pareil |
| [math.SinDegrees] | 3 128, 1 ulp | 14 669 | 14 982 | 10 980 |
| [math.CosDegrees] | 2 851, 1 ulp | 14 356 | 14 383 | 9 146 |
| [math.TanDegrees] | 6 816, 2 ulps | 17 083 | 17 411 | 17 661 |

Cesia appelle la bibliothèque C, ici glibc 2.44, comme numpy, R et Octave, pour toutes sauf [math.Cbrt], la sienne, et
donne les mêmes bits que numpy là où numpy l'appelle aussi. La racine cubique de la bibliothèque C s'écarte jusqu'à
3 ulps ; celle de Cesia prend le float le plus proche de la vraie racine à partir d'un polynôme dont le cube est rendu
exact, et tranche les rares cas proches du milieu de deux floats par le signe exact d'une somme (les expansions de
Shewchuk) : elle ne se trompe jamais, et va aussi vite. Le `tanh` de numpy est le sien, plus rapide et faux de 1 ulp
une fois sur huit. Les degrés de numpy, R et Octave sont faux aux multiples de 180 et de 90 : le sinus de 180 degrés y
vaut 1.2e-16 au lieu de 0, une erreur d'une infinité d'ulps ; la réduction de Cesia les rend exacts, et se trompe d'au
plus 1 ulp ailleurs, là où les radians sont arrondis une fois. [math.Log10] est le point faible de la bibliothèque C,
2 ulps près de 1, partout.


### Les mêmes bits sur chaque système

Un float que Cesia calcule a les mêmes bits sous Linux, macOS, Windows et en WebAssembly, sur x86-64 comme sur arm64,
quand il ne vient que de ceux-ci :

| Exact sur chaque système | Pourquoi |
|---|---|
| `+`, `-`, `*`, `/` et [math.Sqrt] | IEEE 754 arrondit chacune correctement, sur chaque processeur |
| [math.Cbrt], [math.Radians], [math.Degrees], [math.Round], [math.Floor], [math.Ceil], [math.Abs], [math.Clamp], [math.Step], [math.Epsilon], [math.NextAfter] | celles de Cesia, faites de ces opérations |
| [math.SinDegrees], [math.CosDegrees] et [math.TanDegrees] aux multiples de 30 et de 45 | la réduction exacte de Cesia |
| [math.Pi] et [math.E] | écrites en entier |
| le texte d'un float, tel que `io.Print` l'écrit | celui de Cesia, les chiffres les plus courts qui se relisent (Ryu) |

Les autres sont celles de la bibliothèque C du système, comme dans numpy, R et MATLAB : [math.Exp], [math.Log],
[math.Log10], [math.Log2], [math.Log1p], [math.Expm1], [math.Sin], [math.Cos], [math.Tan], [math.Asin], [math.Acos],
[math.Atan], [math.Atan2], [math.Sinh], [math.Cosh], [math.Tanh], [math.Asinh], [math.Acosh], [math.Atanh],
[math.Hypot], [math.LogSumExp], `x ^ y` d'un float, les degrés hors de leurs points exacts, et ce qui calcule avec elles
: [std/special], les lois de [std/stats], [std/quad] et [std/optimize] sur une telle fonction, et les tirages de
[num.Normal]. IEEE 754-2019, dans sa clause 9.2, recommande ces fonctions correctement arrondies (correctly rounded : le
float le plus proche de la valeur exacte), mais aucune bibliothèque C ne le promet pour toutes : le manuel de la glibc,
dans sa section 19.7, dit qu'elle ne le vise pas, seulement « quelques ulps », et que ses tests ne signalent une erreur
qu'au-delà de 9 ulps (l'analyse qu'il cite, « Accuracy of Mathematical Functions in Single, Double, Double Extended, and
Quadruple Precision » de Gladman, Innocente, Mather et Zimmermann, mesure chacune). Leurs derniers bits diffèrent donc
d'un système à l'autre : [math.Sinh] de 710 vaut 1.1169973830808555e308, le float le plus proche, avec la glibc 2.44, et
1.1169973830808557e308 avec la glibc 2.35, celle d'Ubuntu 22.04 ; `math.Degrees(math.Asin(0.5))` vaut 30.000000000000004
avec la glibc et 29.999999999999996 sous macOS. Elles s'accordent là où la valeur exacte est un float
(`math.Log10(1000)`, `math.Hypot(3, 4)`), aux points spéciaux de l'annexe F du C (`math.Sinh(-0.0)` vaut -0.0,
`math.Tanh(math.Inf)` vaut 1), là où le résultat déborde (overflow), et là où un x minuscule revient tel quel.

Les exemples de la référence et les tests de Cesia comparent les autres avec [math.Near] : à 1e-15 près de la valeur
pour un appel de la bibliothèque C, 4.5 ulps ou plus ; à 1e-13 près pour [std/special], [std/stats], [std/quad] et
[std/optimize], dont les méthodes font beaucoup d'appels ; un nombre d'appels, ou de morceaux d'une intégrale, à ce
qu'un ulp de plus ou de moins y change près. Ils tiennent avec la glibc 2.44 telle quelle, et avec chacun de ses
résultats décalé d'un ulp vers le haut, puis vers le bas.

Le processeur lui-même ajouterait une différence. Sur arm64, OCaml 5.5 compile un produit de floats écrit dans une
addition ou une soustraction en une seule instruction fusionnée (fused), fmadd, fmsub ou fnmsub, qui arrondit une fois
là où x86-64 et WebAssembly arrondissent deux fois (asmcomp/arm64/selection.ml, lignes 184 à 196 de ses sources) : `x *
x - 2.0`, dans les instructions de l'interpréteur qui font deux opérations d'un coup, donnait d'autres derniers bits sur
un Mac. Le code de Cesia lie chaque produit par un `let` avant son addition, ce qui les garde séparés : sans flambda, le
`let` d'un nom est Strict (lambda/matching.ml, ligne 4246), ce que Simplif garde (lambda/simplif.ml, ligne 578) ;
Closure le garde pour ce qui n'est pas une constante (middle_end/closure/closure.ml, lignes 1020 à 1033), Cmm aussi
(asmcomp/cmmgen.ml, lignes 1273 et 1289) ; et la sélection des instructions le calcule d'abord dans un registre
(asmcomp/selectgen.ml, lignes 615 à 618), si bien que l'addition voit une variable. tests/fusion_test.ml lit chaque
fichier OCaml de src/ et échoue sur un produit écrit dans une addition ou une soustraction ; il échoue aussi avec un
OCaml qui a flambda sur arm64, dont Un_anf remet un `let` utilisé une fois à sa place d'usage
(middle_end/flambda/un_anf.ml, lignes 696 à 707). Le C de Cesia, celui de MIR compris, et le SQLite des releases sont
compilés avec `-ffp-contract=off`, pour la même raison : GCC fusionne par défaut sur arm64, et Clang dans une
expression. Sur x86-64, l'un et l'autre donnent les mêmes instructions qu'avant, ou moins, dans un autre ordre au plus.

### Ce qu'elles coûtent

Sur un million de floats, en nanosecondes par élément, médianes de 5 passes alternées avec numpy 2.5 et R 4.6 (Intel
Core i7-4720HQ, 4 cœurs, load average, la charge moyenne du système, de 2.1 à 2.6) : l'appel de Cesia sur l'array, sur
tous les cœurs et sur un seul, et une boucle de code machine qui appelle la fonction sur chaque élément.

| Fonction | Cesia, 4 cœurs | Cesia, 1 cœur | boucle | numpy | R |
|---|---|---|---|---|---|
| [math.Log10] | 5.7 | 11.3 | 12.4 | 9.7 | 17.0 |
| [math.Log1p] | 6.0 | 11.8 | 12.5 | 9.8 | 16.0 |
| [math.Expm1] | 6.5 | 13.8 | 15.3 | 12.1 | 17.0 |
| [math.Cbrt] | 6.1 | 21.3 | 55.6 | 20.4 | 35.0 |
| [math.Tanh] | 6.3 | 18.4 | 19.0 | 16.3 | 20.0 |
| [math.Asinh] | 6.9 | 24.6 | 26.2 | 23.6 | 26.0 |
| [math.SinDegrees] | 7.0 | 23.7 | 29.1 | 14.1 | 23.0 |
| [math.Radians] | 1.9 | 1.7 | 3.9 | 1.8 | 6.0 |
| [math.Hypot] | 3.2 | 9.2 | 12.6 | 8.8 | 29.0 |
| [math.Clamp] | 2.1 | 1.9 | 76.6 | 1.5 | 7.0 |
| [math.IsNan] | 3.1 | 6.0 | 3.5 | 0.6 | 2.0 |
| [num.ReplaceNan] | 3.4 | 3.5 | 44.3 | 5.6 | 4.0 |
| [math.LogSumExp] | 8.9 | 8.8 | | 24.5 | 12.0 |

Sur un cœur, Cesia prend 1.04 à 1.21 fois le temps de numpy pour les fonctions de la bibliothèque C, que les deux
appellent, et autant pour [math.Cbrt], la sienne et correctly rounded ; sur quatre, il passe devant. [math.LogSumExp]
va trois fois plus vite que celle de scipy, qui fait l'array des différences, puis celui de leurs exponentielles, avant
de les sommer. numpy en gagne trois : son `isnan` écrit un octet par élément, là où l'array de booléens de Cesia tient
un mot de 8 octets ; son `clip` prend les instructions SIMD (une instruction qui traite plusieurs nombres à la fois) du
processeur ; et `np.sin(np.radians(x))` saute la réduction exacte de [math.SinDegrees], dont `fmod` et `round`
prennent 10 de ses 24 ns, au prix de `0.0` pour le sinus de 180 degrés. Une boucle qui appelle [math.Cbrt],
[math.Clamp], [num.ReplaceNan], [math.Step], [math.Epsilon] ou [math.LogSumExp] reste dans l'interpréteur, car le code
machine n'appelle aucune fonction écrite en OCaml ; donnez-lui l'array en un seul appel.

## Arrays et statistiques : std/num

[std/num] fait du calcul numérique dans l'esprit de numpy : un array est une liste ou une matrice de floats (de nombres à
virgule), et les opérateurs du langage agissent déjà dessus élément par élément. Il ajoute le reste.

| Pour | Utilisez |
|---|---|
| faire des arrays | [num.Linspace] des floats régulièrement espacés, [num.Eye] la matrice identité, [num.Diag] une matrice diagonale |
| tirer des arrays au hasard | [num.Uniform] de 0 à 1, [num.Normal] selon la loi normale de moyenne 0 et d'écart type 1, tous deux avec le générateur de [std/random] |
| décrire | [num.Median], [num.Percentile], [num.Variance], [num.Std], [num.Covariance], [num.Correlation], [num.Histogram] |
| cumuler le long d'un array | [num.Cumsum] la somme cumulée, [num.Diff] les différences, [num.Trapezoid] l'aire sous des points |
| ajuster | [num.Polyfit] un polynôme passant par des points, [num.Polyval] sa valeur, [num.Interpolate] entre des points, [num.LeastSquares] le meilleur `x` de `a * x = b` |
| algèbre linéaire | [num.Dot], [num.Norm], [num.Det], [num.Solve], [num.Inverse], [num.Qr], [num.Eigen] |
| signaux | [num.Fft] et [num.Ifft], la transformée de Fourier et son inverse |

```cesia
use std/num
num.Linspace(0.0, 1.0, 5) -->
num.Percentile(90, 1..10) -->
num.Correlation([1.0, 2.0, 3.0], [2.0, 4.0, 6.5]) -->
num.Cumsum([1, 2, 3]) -->
num.Trapezoid([0.0, 1.0, 2.0], [0.0, 1.0, 4.0]) -->
num.Solve([2.0, 1.0; 1.0, 3.0], [3.0; 5.0]) -->
num.Det([1.0, 2.0; 3.0, 4.0]) -->
```

```python
import numpy as np
print(np.linspace(0.0, 1.0, 5))
print(np.percentile(np.arange(1, 11), 90))
print(np.corrcoef([1.0, 2.0, 3.0], [2.0, 4.0, 6.5])[0, 1])
print(np.cumsum([1, 2, 3]))
print(np.trapezoid([0.0, 1.0, 4.0], [0.0, 1.0, 2.0]))
print(np.linalg.solve([[2.0, 1.0], [1.0, 3.0]], [3.0, 5.0]))
print(np.linalg.det([[1.0, 2.0], [3.0, 4.0]]))
```

```r
print(seq(0, 1, length.out = 5))
print(quantile(1:10, 0.9, names = FALSE))
print(cor(c(1, 2, 3), c(2, 4, 6.5)))
print(cumsum(c(1, 2, 3)))
x <- c(0, 1, 2)
y <- c(0, 1, 4)
print(sum(diff(x) * (head(y, -1) + tail(y, -1)) / 2))
print(solve(matrix(c(2, 1, 1, 3), 2), c(3, 5)))
print(det(matrix(c(1, 3, 2, 4), 2)))
```

```matlab
disp(linspace(0, 1, 5))
x = 1:10;                      % the 90th percentile, linear between ranks, as numpy and R
h = (numel(x) - 1) * 0.9 + 1;
disp(x(floor(h)) + (h - floor(h)) * (x(ceil(h)) - x(floor(h))))
r = corrcoef([1 2 3], [2 4 6.5]);
disp(r(1, 2))
disp(cumsum([1 2 3]))
disp(trapz([0 1 2], [0 1 4]))
disp([2 1; 1 3] \ [3; 5])
disp(det([1 2; 3 4]))
```

[num.Trapezoid] relie les points par des segments et additionne les aires des trapèzes sous eux :

```cesia allow=read,write
use std/plot
tx = [0.0, 1.0, 2.0]
ty = [0.0, 1.0, 4.0]
area = plot.Of([plot.Area(tx, 0.0 * tx, ty, label = "area $(num.Trapezoid(tx, ty))"), plot.Line(tx, ty), plot.Points(tx, ty)],
  title = "num.Trapezoid: the area under lines through the points", x = "x", y = "y", size = [640, 340])
plot.Save(area, "numbers-trapezoid.svg") -->
```

### Comment il calcule

- [num.Solve], [num.Det] et [num.Inverse] utilisent l'*élimination de Gauss avec pivot partiel* : à chaque colonne, la
  ligne qui a la plus grande valeur passe en premier, ce qui garde les erreurs d'arrondi petites. Une matrice dont le
  pivot tombe sous $10^{-14}$ est *singulière* : elle n'a pas d'inverse, et donne un `Err` de sorte `"math"`.
- [num.Eigen] prend une matrice symétrique et la rend diagonale par des *rotations de Jacobi*, dont chacune annule une
  valeur hors de la diagonale ; la diagonale qui reste contient les *valeurs propres*, les nombres $\lambda$ pour lesquels
  $a v = \lambda v$ a une solution $v$, son *vecteur propre*.
- [num.LeastSquares] résout les *équations normales*, $a^T a x = a^T b$. C'est rapide, mais cela élève au carré le
  *nombre de conditionnement* de $a$, qui dit de combien une erreur dans les données grossit dans la réponse : un $a$
  presque singulier perd donc des chiffres. [num.Qr] donne les facteurs d'une méthode plus stable.
- [num.Fft] est la *transformée de Fourier rapide* en base 2 de Cooley et Tukey, en $O(n \log n)$, quand la longueur est
  une puissance de deux, et la somme directe, en $O(n^2)$, sinon.

### Grandes matrices : BLAS et LAPACK

*BLAS* est l'interface standard des opérations de base de l'algèbre linéaire, comme le produit de matrices, et *LAPACK*
celle de la résolution, de la factorisation et des valeurs propres, écrite sur BLAS ; OpenBLAS et Accelerate d'Apple en
sont des versions rapides, réglées pour chaque processeur. Une release de Cesia (une version publiée) apporte OpenBLAS
sur Linux et Windows, et utilise Accelerate sur macOS. [num.Backend] et [lapack.Name] disent laquelle sert, ou `missing`.
[matrix.Matmul], [num.Solve], [num.Det], [num.Qr] et [num.Eigen] l'appellent pour une grande matrice, à partir de
l'ordre 32, ou à partir de $32 \times 32 \times 32$ multiplications pour un produit, et utilisent le code de Cesia lui-même
en dessous, ou quand aucune bibliothèque n'est là ; ce code donne les mêmes bits sur toutes les machines. [std/lapack]
l'appelle directement, et donne `missing` là où il ne le peut pas : [lapack.Solve], [lapack.Det], [lapack.Qr] et
[lapack.Eigen]. `CESIA_BLAS=none` ne fait tourner que le code de Cesia, pour comparer.

## Algorithmes : std/algo

[std/algo] contient les algorithmes classiques, écrits en Cesia, avec les fonctions en premiers arguments et la collection
en dernier.

| Pour | Utilisez |
|---|---|
| chercher dans un array trié | [algo.BinarySearch] la position d'une valeur, [algo.LowerBound] la première position dont la valeur n'est pas plus petite, en $O(\log n)$ |
| couper et combiner | [algo.Chunk] des morceaux de `n`, [algo.Windows] des fenêtres glissantes de `n`, [algo.Partition] selon un test, [algo.Combinations], [algo.Permutations] |
| entiers | [algo.Gcd] et [algo.Lcm] (PGCD et PPCM), [algo.IsPrime] par divisions successives, [algo.Primes] par le crible d'Ératosthène |
| textes | [algo.Levenshtein], l'*edit distance* : le plus petit nombre d'insertions, de suppressions et de remplacements d'un caractère pour passer d'un texte à l'autre |
| graphes | [algo.Bfs] en largeur d'abord et [algo.Dfs] en profondeur d'abord, [algo.Dijkstra] les plus courtes distances, [algo.TopologicalSort] un ordre où chaque nœud vient après ceux dont il a besoin |

```cesia
use std/algo
algo.BinarySearch(7, [1, 3, 7, 9]) -->
algo.Chunk(2, [1, 2, 3, 4, 5]) -->
algo.Windows(2, [1, 2, 3]) -->
algo.Gcd(84, 36) -->
algo.Primes(20) -->
algo.Levenshtein("kitten", "sitting") -->
```

Un *graphe* est ici une fonction qui donne les voisins d'un nœud : aucune structure n'a donc à être construite d'abord.

```cesia
roads = {a: [{Node: "b", Weight: 4}, {Node: "c", Weight: 1}], c: [{Node: "b", Weight: 2}], b: []}
algo.Dijkstra(n -> roads[n], "a") -->
algo.Bfs(n -> [e.Node for e in roads[n]], "a") -->
needs = {app: ["lib", "log"], lib: ["log"], log: []}
algo.TopologicalSort(n -> needs[n], ["app", "lib", "log"]) -->
```

[algo.Dijkstra] garde les nœuds à visiter dans un [std/heap], selon leur distance trouvée jusque-là : il prend donc
$O(E \log E)$ pour $E$ arêtes ; ses poids ne doivent pas être négatifs. [algo.TopologicalSort] parcourt le graphe en
profondeur d'abord, et donne un `Err` de sorte `"cycle"` quand un nœud a besoin de lui-même à travers d'autres.

## Sets, queues et heaps

Trois structures persistantes, comme les listes et les dictionnaires : un changement donne une nouvelle valeur, et
l'ancienne reste.

- Un *set*, [std/set], contient des nombres et des textes, chacun une seule fois, dans l'ordre : [set.Of], [set.Empty],
  [set.Add], [set.Remove], [set.Has], [set.Items], [set.Union], [set.Intersection], [set.Difference] et [set.IsSubset].
  C'est un dictionnaire dont les clés sont ses éléments : un test ou un changement coûte donc ce que coûte celui d'un
  dictionnaire, $O(\log_{32} n)$ ; [set.Items] les trie, en $O(n \log n)$.
- Une *queue*, [std/queue], est ouverte aux deux bouts, une *deque* : [queue.Push] ajoute à l'arrière et
  [queue.PushFront] à l'avant, [queue.Pop] et [queue.PopBack] retirent, [queue.First] et [queue.Last] lisent les bouts,
  [queue.Items] donne tous les éléments, [queue.Of] et [queue.Empty] en font une, [queue.IsEmpty] demande si elle est
  vide ; [queue.Queue] est sa struct (sa forme déclarée, aux champs nommés). C'est un dictionnaire des positions vers les
  éléments : chaque opération est donc en $O(\log_{32} n)$, comme pour un dictionnaire.
- Un *heap*, [std/heap], rend la plus petite clé en premier, une *priority queue* : [heap.Insert] ajoute une valeur sous
  une clé, [heap.Peek] lit la plus petite, [heap.Pop] la retire, [heap.Merge] réunit deux heaps, [heap.Items] les donne
  toutes dans l'ordre, puis [heap.Empty] et [heap.IsEmpty]. C'est un *leftist heap*, tiré du livre d'Okasaki : sa branche
  la plus courte est toujours à droite, si bien qu'une insertion, un retrait ou une fusion se fait en $O(\log n)$.

```cesia
use std/set
use std/queue
use std/heap
set.Items(set.Union(set.Of([3, 1]), set.Of([2, 3]))) -->
set.IsSubset(set.Of([1]), set.Of([1, 2])) -->
q = queue.Of([1, 2]) then queue.Push(3) then queue.PushFront(0)
queue.Items(q) -->
queue.First(queue.Pop(q)) -->
h = heap.Empty() then heap.Insert(5, "low") then heap.Insert(1, "urgent")
heap.Peek(h) -->
heap.Items(heap.Pop(h)) -->
```

## Pour aller plus loin

- E. Anderson et al., *LAPACK Users' Guide*, 1999 ; Cooley et Tukey, *An Algorithm for the Machine Calculation of
  Complex Fourier Series*, 1965 ; Charles R. Harris et al., *Array programming with NumPy*, 2020.
- E. W. Dijkstra, *A note on two problems in connexion with graphs*, 1959 ; V. I. Levenshtein, *Binary codes capable of
  correcting deletions, insertions, and reversals*, 1966.
- Chris Okasaki, *Purely Functional Data Structures*, 1998 : le leftist heap et les structures persistantes.
- Jonathan Richard Shewchuk, *Adaptive Precision Floating-Point Arithmetic and Fast Robust Geometric Predicates*,
  1997 : le signe exact des rares cas de [math.Cbrt] ; Pierre Blanchard, Desmond J. Higham et Nicholas J. Higham,
  *Accurately computing the log-sum-exp and softmax functions*, 2021 : [math.LogSumExp] ; Charles F. F. Karney,
  *Algorithms for geodesics*, 2013 : la réduction de [math.SinDegrees] ; CODATA 2022, les constantes de [std/constants].

Chacun avec son lien dans [Références](references.md#données-et-nombres).

## La suite

Vous savez calculer avec des nombres et des structures. Le chapitre suivant, [Graphiques](graphs.md), dessine ce que
vous calculez.
