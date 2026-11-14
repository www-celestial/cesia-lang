# Méthodes numériques

Dans ce chapitre, vous trouvez où une fonction s'annule, avec [optimize.Root], où elle est la plus petite, avec
[optimize.Minimize] et [optimize.Simplex], vous résolvez des équations différentielles, avec [ode.Solve], vous calculez
des intégrales, avec [quad.Integral], et vous résolvez des systèmes dont la matrice est sparse (presque toute faite de
zéros), avec [sparse.Solve] : ce que font `fzero`, `fminunc`, `fminsearch`, `ode45`, `integral` et `A \ b` dans MATLAB,
`brentq`, `minimize`, `solve_ivp`, `quad` et `spsolve` dans scipy. Chaque méthode vient d'un article, nommé ici avec ce
qu'elle promet ; les tests de Cesia vérifient chaque promesse, et la dernière partie de chaque section dit, mesures à
l'appui, comment elle se compare à scipy et à Octave.

## Le zéro d'une fonction

[optimize.Root] trouve un `x` où `f(x) = 0`, pour une fonction `f` d'un nombre qui donne un nombre. Donnez-lui un
*bracket* (un encadrement), deux nombres `a` et `b` où `f(a)` et `f(b)` sont de signes opposés : si `f` est continue,
elle s'annule quelque part entre les deux.

```cesia
use std/math
use std/optimize
use std/result
r = result.Unwrap(optimize.Root(x -> x ^ 3 - 2.0 * x - 5.0, [2.0, 3.0]))
r -->
```

`X` est le zéro, `F` est `f(X)`, et `Evaluations` compte les appels de `f`. La même chose en Python, R et MATLAB :

```python
from scipy.optimize import brentq
x, r = brentq(lambda x: x**3 - 2*x - 5, 2, 3, full_output=True)   # 2.094551481542327, r.function_calls 8
```

```r
uniroot(function(x) x^3 - 2*x - 5, c(2, 3), tol = 1e-15)$root   # 2.0945514815423265
```

```matlab
x = fzero(@(x) x^3 - 2*x - 5, [2 3])   % 2.094551481542327
```

Les réponses diffèrent par leur dernier chiffre : Cesia donne par défaut le float le plus proche du zéro,
2.0945514815423265 ; le `brentq` de scipy et `fzero`, lancé dans GNU Octave, s'arrêtent à un float de là avec leurs
réglages par défaut, et le `uniroot` de R a besoin de `tol` pour y arriver.

### À partir d'un seul départ

Avec un seul nombre au lieu d'un encadrement, Root cherche d'abord un encadrement : des points des deux côtés du départ,
à 2 % de celui-ci (0,02 pour 0), puis deux fois plus loin à chaque pas, au plus 60 pas, jusqu'à ce que `f` change de
signe. Un côté où `f` ne donne pas de nombre fini, comme `math.Log` d'un nombre négatif, s'arrête là, et l'autre
continue :

```cesia
optimize.Root(x -> math.Cos(x) - x, 1.0).Value.X -->
optimize.Root(x -> math.Log(x) - 1.0, 0.01).Value.X -->
math.Exp(1.0) -->
```

`fzero(f, x0)` cherche aussi un encadrement à partir d'un seul départ ; le `brentq` de scipy ne cherche pas, et a besoin
de l'encadrement.

### Ce qu'il promet

La méthode est celle de Brent (1973), que suivent le `fzero` de MATLAB, le `brentq` de scipy et le `uniroot` de R. Elle
garde un encadrement `[b, c]` où `f` change de signe, `b` étant le bout où `|f|` est le plus petit, et le resserre à
chaque pas. Le pas est l'un de ces trois :

- la *sécante* : le zéro de la droite qui passe par les deux derniers points ;
- l'*interpolation quadratique inverse* : la parabole en `y` qui passe par les trois derniers points, `x = p(y)`, en
  `y = 0` ;
- la *bissection* : le milieu de l'encadrement.

Les deux premiers sont rapides près d'un zéro simple : l'erreur baisse de façon superlinéaire, plus vite à chaque pas.
La bissection est lente mais sûre : elle coupe l'encadrement en deux à chaque fois. Brent ne fait un pas d'interpolation
que quand il tombe dans l'encadrement et le resserre assez vite, et coupe en deux sinon, si bien que, dit son livre, la
méthode « never converges much more slowly than bisection » (ne converge jamais beaucoup plus lentement que la
bissection). Elle s'arrête quand l'encadrement a une largeur d'au plus $2 \epsilon |X| + 2 \cdot \text{tol}$, où
$\epsilon = 2^{-52}$ est l'écart entre 1.0 et le float suivant : avec `tol = 0.0`, la valeur par défaut, `X` est l'un
des deux floats qui entourent le zéro. `tol` est une tolérance absolue : `tol = 1e-6` s'arrête plus tôt, à environ
`1e-6` du zéro.

La promesse vaut pour toute `f` continue qui change de signe dans l'encadrement : `X` est, à la largeur ci-dessus près,
un point où `f` change de signe. Une fonction avec plusieurs zéros dans l'encadrement en donne un. Les tests de Cesia le
vérifient sur les 154 problèmes d'Alefeld, Potra et Shi (1995), des fonctions choisies pour être difficiles pour de
telles méthodes : plates en leur zéro, raides, avec des pôles tout près ; sur des polynômes au zéro simple connu, tirés
au hasard ; et sur des zéros connus sous forme close, comme $\pi / 6$ pour $\sin x = 1/2$.

### Quand il n'y a pas de zéro

Root donne un `Err` de sorte `"optimize"`, avec `Best`, le point du plus petit `|f|` qu'il a rencontré, quand
l'encadrement n'a pas de changement de signe, quand la recherche n'en trouve pas, quand `f` donne un NaN, un infini ou
pas un nombre, ou quand `|f|` grandit pendant que l'encadrement se resserre : un *pôle*, où `f` part à l'infini, change
de signe lui aussi, mais n'est pas un zéro. Le `brentq` de scipy rend le pôle de `1 / (x - 0.3)`, 0.3000000000014551,
comme si c'était un zéro, et le `fzero` d'Octave rend 0.3 avec un avertissement.

```cesia
optimize.Root(x -> x * x + 1.0, [0.0, 1.0]).Error.Message -->
optimize.Root(x -> 1.0 / (x - 0.3), [0.0, 1.0]).Error.Message -->
```

Un encadrement qui n'est pas fait de deux nombres différents, ou un `tol` négatif, est un bug de l'appelant : une panic
(un arrêt du programme) qui le nomme.

### À côté de TOMS 748

Alefeld, Potra et Shi (1995) ont proposé TOMS 748, une méthode qui se sert d'interpolation cubique et prouve une
meilleure efficacité. Sur leurs propres 154 problèmes, Root fait 2 761 appels de `f` en tout à pleine précision ; le
`toms748` de scipy en fait 2 682, 2,9 % de moins, moins sur 88 problèmes et plus sur 46. À `tol = 5e-11` l'écart est de
2,1 %, à `5e-8` de 0,5 %. La méthode de Brent reste : le gain est petit, et pas sur chaque problème. Le `brentq` de
scipy fait 2 753 appels, puisqu'il s'arrête un float plus tôt.

### La vitesse de Root

Le zéro de $x^3 - 2x - 5$ sur `[2, 3]` jusqu'au dernier float, 20 000 fois dans une boucle : 7,1 µs par appel dans Cesia
(intervalle à 95 % de la médiane de 21 lancements : 6,9 à 7,5), 11,5 µs pour le `brentq` de scipy (11,3 à 12,0), chacun
avec 8 appels de `f`, mesurés comme le sont les résolutions de [La vitesse de Solve](#la-vitesse-de-solve). La boucle de
Root tourne dans l'interpréteur, puisque le JIT (le compilateur qui traduit le code en code machine pendant qu'il
tourne) ne fait pas encore de code machine d'une boucle qui appelle [math.Abs] ou [value.IsNumber].

## Le minimum d'une fonction

[optimize.Minimize] trouve un `x` où une fonction `f` d'un array de nombres (une suite de nombres rangés côte
à côte) est la plus petite, et [optimize.Simplex]
fait la même chose avec une autre méthode. La fonction de Rosenbrock est un test classique : une vallée étroite et
courbe dont le fond descend lentement vers son minimum, 0 en `[1, 1]`. Son *gradient*, l'array des pentes de `f` le long
de chaque coordonnée, peut être donné avec elle :

```cesia
use std/optimize
use std/result
rosen(x) = (1.0 - x[1]) ^ 2 + 100.0 * (x[2] - x[1] ^ 2) ^ 2
grad(x) = [-2.0 * (1.0 - x[1]) - 400.0 * x[1] * (x[2] - x[1] ^ 2), 200.0 * (x[2] - x[1] ^ 2)]
m = result.Unwrap(optimize.Minimize(rosen, [-1.2, 1.0], gradient = grad))
m -->
```

`X` est le point trouvé, `F` est `f(X)`, `Gradient` le gradient en ce point, `Steps` les pas faits et `Evaluations` les
appels de `f`. Sans `gradient`, Minimize le calcule à partir de `f` par différences, au prix de plus d'appels :

```cesia
optimize.Minimize(rosen, [-1.2, 1.0]).Value.Evaluations -->
s = result.Unwrap(optimize.Simplex(rosen, [-1.2, 1.0]))
s -->
```

`x` peut aussi être un nombre, pour une fonction d'un nombre, et alors `X` et `Gradient` sont des nombres. La même chose
en Python, R et MATLAB :

```python
from scipy.optimize import minimize
rosen = lambda x: (1 - x[0])**2 + 100 * (x[1] - x[0]**2)**2
grad = lambda x: [-2 * (1 - x[0]) - 400 * x[0] * (x[1] - x[0]**2), 200 * (x[1] - x[0]**2)]
m = minimize(rosen, [-1.2, 1.0], jac=grad, method="L-BFGS-B", options={"gtol": 1e-8, "ftol": 4 * 2.2e-16})
# m.nit 38, m.nfev 46
s = minimize(rosen, [-1.2, 1.0], method="Nelder-Mead", options={"adaptive": True, "xatol": 1e-8, "fatol": 1e-8})
# s.nfev 219, s.x equal to Simplex's X to 14 digits
```

```r
fr <- function(x) (1 - x[1])^2 + 100 * (x[2] - x[1]^2)^2
grr <- function(x) c(-2 * (1 - x[1]) - 400 * x[1] * (x[2] - x[1]^2), 200 * (x[2] - x[1]^2))
optim(c(-1.2, 1), fr, grr, method = "L-BFGS-B", control = list(factr = 1, pgtol = 1e-8))  # 49 calls
optim(c(-1.2, 1), fr, control = list(reltol = 1e-16))  # Nelder-Mead, without Gao and Han's coefficients: 251 calls
```

```matlab
rosen = @(x) (1 - x(1))^2 + 100 * (x(2) - x(1)^2)^2;
x = fminsearch(rosen, [-1.2 1], optimset('TolX', 1e-8, 'TolFun', 1e-8))  % 200 calls in GNU Octave
x = fminunc(@rosenAndGradient, [-1.2; 1], optimset('GradObj', 'on'))     % a file that gives f and its gradient
```

Lequel prendre :

| | Minimize | Simplex |
|---|---|---|
| `f` | lisse : elle a une pente partout | tout ce qui donne un nombre : avec des coudes, des marches ou du bruit |
| Vitesse | rapide, plus encore avec `gradient` ; fait pour des milliers de nombres | lent au-delà de quelques nombres : 550 à 2 500 appels à 4, 1 200 à 10 500 à 10 |
| Promesse | un point où le gradient est proche de 0 | aucune : il peut s'arrêter avant un minimum |
| MATLAB, scipy | `fminunc` ; `minimize(method = "L-BFGS-B")` | `fminsearch` ; `minimize(method = "Nelder-Mead")` |

Les deux sont déterministes : le même appel donne la même réponse, jusqu'au dernier bit, sur la même machine.

### Ce que promet Minimize

La méthode est L-BFGS, de Liu et Nocedal (1989), celle que prend le `L-BFGS-B` de scipy quand aucune borne n'est donnée.
Chaque pas suit une *direction de descente*, une direction dans laquelle `f` baisse, puis une *line search* (une
recherche le long d'une droite) choisit jusqu'où aller dans cette direction.

- **La direction.** Moins le gradient pointe vers le bas, mais dans une vallée courbe il pointe vers la paroi, et des
  pas qui le suivent font des zigzags. La méthode de Newton corrige cela avec la *hessienne*, la matrice des dérivées
  secondes de `f` : son inverse fois le gradient pointe vers le fond de la vallée. Une méthode *quasi-Newton* ne calcule
  jamais la hessienne : elle l'apprend de la façon dont le gradient a changé entre les pas (la méthode de Broyden,
  Fletcher, Goldfarb et Shanno, *BFGS*). L-BFGS, pour *limited memory* (mémoire limitée), ne garde que les 10 derniers
  pas `s` et les 10 derniers changements du gradient `y`, `20 n` nombres au lieu des `n × n` d'une matrice, et en tire
  la direction par les *deux boucles* de Nocedal (1980), en `4 · 10 · n` opérations. La première matrice de chaque pas
  est `(s'y / y'y)` fois l'identité, l'échelle de la dernière paire (le M3 de Liu et Nocedal). Une paire dont `s'y`
  n'est pas au-dessus de $\epsilon\, y'y$ est laissée de côté, puisqu'elle ferait pointer la direction vers le haut.
- **La line search.** Le long de la direction `d`, un pas `a` est bon quand `f` a baissé d'au moins $10^{-4}$ de ce que
  promettait sa pente, $f(x + a d) \le f(x) + 10^{-4} a\, g'd$ (la *décroissance suffisante*), et que sa pente s'est
  aplatie jusqu'à au plus 0,9 de ce qu'elle était, $|g(x + a d)'d| \le 0{,}9\, |g'd|$ (la *courbure*) : ensemble, les
  *conditions de Wolfe fortes*. La recherche de Moré et Thuente (1994) trouve un tel pas en ajustant des cubiques et des
  paraboles à `f` et à sa pente à l'intérieur d'un intervalle qui en contient un, et qui se resserre ; leur article
  prouve que ses pas d'essai convergent vers un tel pas et que, sauf dans des cas pathologiques, elle se termine après
  un nombre fini d'entre eux. Minimize lui accorde 20 évaluations de `f` par pas, comme le code de Liu et Nocedal et
  scipy, et essaie d'abord le pas 1, qui est souvent bon, sauf pour le premier pas le long du gradient, où il essaie
  `1 / |g|`.
- **La fin.** Minimize s'arrête avec un `Ok` quand chaque composante du gradient vaut au plus `tol · max(1, |F|)`,
  `tol = 1e-8` par défaut. Près d'un minimum, l'arrondi peut faire que `f` cesse de baisser avant cela : quand deux pas
  changent `f` de moins de $4 \epsilon |F|$, où $\epsilon = 2^{-52}$, ou quand une recherche échoue deux fois le long du
  gradient lui-même, Minimize s'arrête aussi, avec un `Ok` seulement si le gradient a diminué jusqu'à
  $\sqrt{\epsilon} \approx 1{,}5 \cdot 10^{-8}$ de sa plus grande composante au départ, ou de 1 : la limite des floats,
  ou du gradient par différences. Sinon `f` a cessé de baisser là où sa pente n'est pas petite, à un coude, à une paroi
  au-delà de laquelle `f` n'a pas de valeur finie, ou avec un gradient faux, et c'est un `Err`.

La promesse : pour une fonction deux fois dérivable dont la courbure est bornée en dessous et au-dessus par des nombres
positifs dans toutes les directions, une fonction *uniformément convexe*, Liu et Nocedal prouvent que L-BFGS converge
vers le minimum, et que l'écart au minimum diminue au moins géométriquement, $f_k - f_{\min} \le r^k (f_0 - f_{\min})$
pour un certain $r < 1$ après $k$ pas (la convergence *R-linéaire*). Pour les autres fonctions, il n'y a pas de tel
théorème : Minimize finit en un point où le gradient est proche de 0, le plus souvent un *minimum local*, plus bas que
tous les points proches mais pas toujours le plus bas de tous, celui vers lequel mène le départ. À partir d'un autre
départ, il peut en trouver un autre.

Sur la fonction de Rosenbrock étendue à 1 000 nombres, le gradient donné, Minimize et le `L-BFGS-B` de scipy à la même
tolérance donnent la même réponse jusqu'au dernier bit : `F = 1.2343201197106615e-22`, après 37 pas et 46 appels de `f`.

### Le gradient par différences

Sans `gradient`, la composante `i` du gradient est une *différence centrée*, $(f(x + h e_i) - f(x - h e_i)) / 2h$, avec
$h = \epsilon^{1/3} \max(1, |x_i|) \approx 6 \cdot 10^{-6} \max(1, |x_i|)$ (Nocedal et Wright, §8.1). Son erreur a deux
parts : celle de la formule, environ $h^2 |f'''| / 6$, qu'un `h` plus petit réduit, et celle de l'arrondi, environ
$\epsilon |f| / h$, qu'un `h` plus petit fait grandir ; ce `h` les équilibre, pour une erreur proche de
$\epsilon^{2/3} \approx 4 \cdot 10^{-11}$ de la taille du gradient sur une fonction d'échelle ordinaire. Chaque gradient
coûte `2n` appels de `f`, donc un pas coûte `2n + 1` là où le gradient donné coûte 1 : donnez-le quand vous l'avez sous
la main.

L'erreur compte là où `f` est raide ou mal mise à l'échelle. Sur le premier problème d'Osborne de Moré, Garbow et
Hillstrom, $e^{-t x_4}$ avec `t` jusqu'à 320 a une dérivée troisième proche de $10^8$, l'erreur des différences atteint
$10^{-6}$ du gradient, et `f` cesse de baisser $2 \cdot 10^{-6}$ au-dessus de son minimum, avec un gradient encore plus
grand que ce que permet la règle de la fin : un `Err` qui demande le gradient, qui atteint alors le minimum à
14 chiffres.

### Ce que promet Simplex

La méthode est celle de Nelder et Mead (1965), comme le `fminsearch` de MATLAB, avec les coefficients de Gao et Han
(2012). Elle déplace un *simplex*, `n + 1` points en `n` dimensions : un triangle dans le plan, un tétraèdre dans
l'espace. À chaque pas, elle prend le pire point, celui du plus grand `f`, et le *réfléchit* par le milieu des autres.
Si le nouveau point est le meilleur jusque-là, elle essaie d'aller deux fois plus loin, une *expansion* ; s'il n'est pas
meilleur que l'avant-dernier, elle essaie un point entre les deux, une *contraction* ; si cela échoue aussi, chaque
point se rapproche à mi-chemin du meilleur, un *rétrécissement*. Elle ne se sert jamais d'une pente, si bien que `f`
peut avoir des coudes, des marches ou du bruit.

Les coefficients de Gao et Han, pour `n` nombres, sont `1` pour la réflexion, `1 + 2/n` pour l'expansion,
`0.75 - 1/(2n)` pour la contraction et `1 - 1/n` pour le rétrécissement ; à `n = 2` ce sont ceux de Nelder et Mead
eux-mêmes, 1, 2, 1/2 et 1/2, et pour un `n` plus grand ils empêchent le simplex de s'aplatir, ce qui ralentit les
coefficients d'origine. Le premier simplex est `x` et, pour chaque composante, `x` avec cette composante plus grande de
5 %, ou 0.00025 pour un 0, comme dans `fminsearch`. Simplex finit quand les points sont à `tol · max(1, |X|)` du
meilleur dans chaque composante et leurs valeurs à `tol · max(1, |F|)` de `F`, `tol = 1e-8` par défaut. Sur Rosenbrock,
il fait les mêmes pas que le Nelder-Mead de scipy avec `adaptive = True`, les mêmes coefficients : 219 appels, et le
même `X` à 14 chiffres.

Il n'y a pas de promesse : Lagarias, Reeds, Wright et Wright (1998) prouvent que la méthode converge vers le minimum
d'une fonction strictement convexe d'un nombre, et n'ont que des résultats limités pour deux ; McKinnon (1998) donne des
fonctions strictement convexes de deux nombres, lisses, sur lesquelles elle converge vers un point qui n'est pas un
minimum. Sur la fonction de Box à trois nombres, depuis le départ de Moré, Garbow et Hillstrom, Simplex et scipy
s'arrêtent tous deux à `f = 0.0756`, là où le minimum vaut 0. Prenez donc Minimize pour une `f` lisse, et vérifiez ce
que trouve Simplex.

### Quand il n'y a pas de minimum

Les deux donnent un `Err` de sorte `"optimize"`, avec `Best`, la struct (la valeur aux champs nommés) du meilleur point
trouvé, quand `f` donne un NaN, un infini ou pas un nombre au départ, et quand les pas sont épuisés :

```cesia
optimize.Minimize(rosen, [-1.2, 1.0], steps = 3).Error.Message -->
optimize.Minimize(x -> x[1] - x[2], [0.0, 0.0]).Error.Message -->
optimize.Simplex(x -> x[1], [0.0]).Error.Message -->
```

Minimize en donne aussi un quand `f` baisse sans fin, au-delà de pas de $10^{10}$ fois la direction ; quand `f` cesse de
baisser là où sa pente n'est pas petite, comme ci-dessus ; et quand `f` monte le long de moins le gradient dès le
départ, ce que fait un gradient faux. Simplex en donne un quand ses points grandissent au-delà des plus grands floats.
Après le départ, un NaN ou un infini venant de `f` fait reculer la line search de Minimize, et compte dans Simplex comme
une valeur pire que toutes les autres : une fonction infinie au-delà d'une paroi est minimisée jusqu'à la paroi par
Simplex, et arrête Minimize à cet endroit avec un `Err`. Un mauvais argument, un `tol` négatif, un `steps` qui n'est pas
un nombre entier, un `x` qui n'est pas fait de nombres sur une ligne ou une colonne, est un bug de l'appelant : une
panic qui le nomme.

### Les vérifications

Les tests de Cesia font tourner les deux sur les 35 problèmes de Moré, Garbow et Hillstrom (1981), le jeu de référence
pour de telles méthodes, écrits à partir de leur article : des vallées courbes, des problèmes mal mis à l'échelle avec
des nombres de $10^{-6}$ à $10^6$, des régions plates, et des minima au fond de puits étroits, à partir des départs que
donne l'article, quatre d'entre eux à deux tailles, 39 cas en tout. Les valeurs au départ et le gradient en ce point
viennent d'une seconde transcription, en Python ; les minima, avec tous leurs chiffres, du Levenberg-Marquardt de
MINPACK, qui s'accordent avec les six chiffres de l'article.

- Minimize sans gradient atteint un minimum à $10^{-8}$ près (en relatif, ou en absolu pour 0) sur 36 cas, la vallée
  plate de Gulf à `tol = 1e-10` ; sur les 3 autres, celui de Meyer, le premier d'Osborne et celui de Watson à `n = 9`,
  l'erreur des différences l'arrête avant, jusqu'à $5 \cdot 10^{-4}$, et avec leur gradient il les atteint aussi.
- Le gradient par différences s'accorde avec le gradient exact à chaque départ à $10^{-7}$ près de sa plus grande
  composante, sauf sur les deux problèmes où la formule de l'erreur ci-dessus dit qu'il ne le peut pas : la fonction mal
  mise à l'échelle de Brown, où `f` vaut $10^{12}$ au départ, et le premier d'Osborne.
- Minimize évalue `f` et son gradient en 3 772 points sur les 39 cas, là où le `L-BFGS-B` de scipy avec le gradient
  exact en prend 2 956 : l'essentiel de l'écart est sur les problèmes de Meyer, celui de Powell mal mis à l'échelle et
  celui de Jennrich et Sampson, où scipy s'arrête loin du minimum (à 13 335 contre 87,9, $2 \cdot 10^{-7}$ contre 0, 214
  contre 124). Sur 33 des 36 autres, les deux font le même nombre de pas à un cinquième près ; Rosenbrock étendue à
  `n = 10` en fait 76 contre 38, l'erreur des différences ralentissant sa fin.
- Simplex atteint un minimum à $10^{-8}$ près sur 38 cas, celui de Box étant l'exception ci-dessus, en 88 705 appels de
  `f`, là où le Nelder-Mead de scipy avec les mêmes coefficients en fait 90 002.

### La vitesse de Minimize et de Simplex

Rosenbrock étendue à 1 000 nombres, le gradient donné, depuis `(-1.2, 1, -1.2, 1, ...)`, et Rosenbrock à 2 depuis
`(-1.2, 1)`, à `tol = 1e-8` : le temps d'un appel, à l'intérieur de chaque programme, la médiane de 21 lancements
alternés, et du 6e au 16e d'entre eux, un intervalle qui contient la vraie médiane 97 fois sur 100, sur la machine de
[Vitesse](speed.md#à-côté-des-géants), avec d'autres travaux qui y tournaient, le 2026-11-13.

| | Minimize, n = 1 000 | Simplex, n = 2 |
|---|---:|---:|
| **Cesia** | **7,77 ms** (7,73 à 8,01) | **0,337 ms** (0,331 à 0,340) |
| scipy 1.18.1, à la tolérance de Cesia | 6,47 ms (6,41 à 6,59) | 3,98 ms (3,90 à 4,03) |
| scipy 1.18.1, à ses réglages par défaut | 6,10 ms (6,04 à 6,16) | 2,88 ms (2,84 à 3,01), 159 appels, `X` à $4 \cdot 10^{-5}$ près |
| GNU Octave 11.3, `fminunc` et `fminsearch` | 32 s, 1 416 pas | 11,9 ms, 200 appels |

scipy gagne Minimize d'un cinquième : sa boucle est en Fortran et sa `f` en numpy, alors que la line search de Cesia
tourne dans l'interpréteur, et que chaque pas fait une douzaine d'arrays de 1 000 floats ; les deux boucles de la
direction, qui coûtent le plus, tournent en code natif, sans arrays faits à chaque pas. Le `fminunc` d'Octave garde une
matrice $n \times n$ entière. Simplex est 12 fois plus rapide que celui de scipy : ses pas sont quelques petites
opérations sur des arrays, là où ceux de scipy paient Python à chacune.

Un programme qui appelle Root démarre 0,5 ms plus tard qu'un programme qui affiche 1, 3,71 ms contre 3,19, les médianes
de 21 lancements une fois son code dans le [cache des packages chargés](internals.md#le-cache-des-packages-chargés) ; le
premier lancement, qui le remplit, 5 ms plus tard.

## Les équations différentielles

Une *équation différentielle* donne la vitesse de changement d'un état : $y' = f(t, y)$, la dérivée de `y` au temps `t`.
Avec l'état à un premier temps, `y0`, elle fixe l'état à chaque temps qui suit : une décroissance, une orbite, une
réaction, une population. [ode.Solve] le calcule. Voici une décroissance, $y' = -y$ depuis $y(0) = 1$, dont la solution
est $e^{-t}$ :

```cesia
use std/ode
s = result.Unwrap(ode.Solve((t, y) -> -y, [0.0, 1.0], 1.0))
s.At(0.5) -->
math.Exp(-0.5) -->
s.Stats -->
```

Un système a plusieurs composantes : `y` est un array, et `f` donne un array de même forme. Le système de Lorenz, un
modèle de convection dont les solutions ne se stabilisent jamais et ne se répètent jamais :

```cesia
use std/value
sigma = 10.0
rho = 28.0
beta = 8.0 / 3.0
lorenz(t, y) = [sigma * (y[2] - y[1]), y[1] * (rho - y[3]) - y[2], y[1] * y[2] - beta * y[3]]
l = result.Unwrap(ode.Solve(lorenz, [0.0, 50.0], [1.0, 1.0, 1.0]))
l.At(2.5) -->
value.Size(l.Y) -->
```

La même chose en Python, R et MATLAB, aux mêmes tolérances :

```python
from scipy.integrate import solve_ivp
sigma, rho, beta = 10.0, 28.0, 8.0 / 3.0
def lorenz(t, y):
    return [sigma * (y[1] - y[0]), y[0] * (rho - y[2]) - y[1], y[0] * y[1] - beta * y[2]]
sol = solve_ivp(lorenz, (0, 50), [1, 1, 1], rtol=1e-6, atol=1e-9, dense_output=True)
sol.sol(2.5)   # [-6.95961709, -7.27253256, 24.70314841]
```

```r
# deSolve, a package of CRAN: install.packages("deSolve"). Not run here: the machine that builds this page lacks it.
library(deSolve)
lorenz <- function(t, y, p) list(c(10 * (y[2] - y[1]), y[1] * (28 - y[3]) - y[2], y[1] * y[2] - 8 / 3 * y[3]))
out <- ode(c(1, 1, 1), c(0, 2.5, 50), lorenz, NULL, method = "ode45", rtol = 1e-6, atol = 1e-9)
out[2, ]
```

```matlab
sigma = 10; rho = 28; beta = 8 / 3;
lorenz = @(t, y) [sigma * (y(2) - y(1)); y(1) * (rho - y(3)) - y(2); y(1) * y(2) - beta * y(3)];
opts = odeset('RelTol', 1e-6, 'AbsTol', 1e-9);
[t, y] = ode45(lorenz, [0 2.5 50], [1 1 1], opts);
y(2, :)
```

### La solution

`Solve` donne un `Ok` d'une [ode.Solution] :

| Champ | Ce qu'il contient | MATLAB | scipy |
|---|---|---|---|
| `T` | les temps, une colonne | `t` | `sol.t` |
| `Y` | les états, une ligne pour chaque temps, une colonne pour chaque composante | `y` | `sol.y.T` |
| `s.At(t)` | l'état à n'importe quel temps `t` de la solution, ou une matrice comme `Y` pour un array de temps | `deval(sol, t)` | `sol.sol(t)` |
| `Events` | les événements rencontrés, dans l'ordre du temps | `te`, `ye`, `ie` | `sol.t_events`, `sol.y_events` |
| `Stats` | `Steps`, `Rejected`, `Evaluations`, et avec `stiff = true` `Jacobians` et `Factorizations`, 0 sinon | `sol.stats` | `sol.nfev`, `sol.njev`, `sol.nlu` |

Avec deux temps, `[t0, t1]`, `T` contient les temps des pas qu'a faits la méthode. Avec trois ou plus, croissants ou
décroissants, `T` contient ces temps et `Y` les états en ces temps, à partir des mêmes pas, si bien que `At` donne les
mêmes nombres dans les deux cas. Des temps qui décroissent résolvent en remontant le temps. Une colonne de `Y` est ce
que prend [plot.Line] : `plot.Line(s.T, s.Y[:, 1])`.

### Les tolérances

`rtol = 1e-6` et `atol = 1e-9` sont les valeurs par défaut : environ six chiffres justes, là où MATLAB et scipy en
prennent trois par défaut (`1e-3` et `1e-6`). `atol` est un nombre ou un array, un pour chaque composante, pour des
composantes d'échelles très différentes. `maxStep` borne la taille d'un pas, et `steps`, un million par défaut, borne
leur nombre, pas refusés compris.

Ce que promet une tolérance demande de l'attention. À chaque pas, la méthode estime l'erreur qu'elle fait dans ce pas,
l'*erreur locale*, et ne fait le pas que quand la moyenne quadratique de cette estimation, chaque composante divisée par
$\text{atol} + \text{rtol} \cdot |y|$, vaut au plus 1. L'erreur de la solution entière, l'*erreur globale*, additionne
les erreurs locales à mesure que l'équation les emporte : aucune méthode ne la borne en général. Ce qui vaut, et que
vérifient les tests de Cesia, c'est la *proportionnalité à la tolérance* : l'erreur globale baisse à peu près aussi vite
que la tolérance. Sur l'orbite de Kepler à une excentricité de 0,5, après trois tours, l'erreur de la position vaut 30 à
65 fois `rtol` de `1e-7` jusqu'à `1e-12`, 270 fois à `1e-5` et 320 fois à `1e-3`. Sur un système *chaotique*, comme
celui de Lorenz, une petite erreur grandit de façon exponentielle avec le temps : en `t = 12.5`, les trois solvers (les
codes qui résolvent l'équation) de cette page donnent `x` = -11.891, -11.889 et -11.893 à leurs réglages par défaut, et
la vraie valeur est -11.896. Un `rtol` plus petit repousse cet horizon plus tard, il ne le supprime pas.

### Les événements

Un [ode.Event] surveille une fonction `g(t, y)` le long de la solution et note chaque moment où elle passe par 0 : une
balle qui touche le sol, une planète qui traverse un plan. `stop = true` termine la solution à cet endroit ; `direction`
vaut `"both"`, `"up"` pour un `g` qui passe d'en dessous de 0 au-dessus, ou `"down"`.

```cesia
fall(t, y) = [y[2], -9.81]
ground = ode.Event((t, y) -> y[1], stop = true, direction = "down")
b = result.Unwrap(ode.Solve(fall, [0.0, 10.0], [10.0, 0.0], events = [ground]))
b.Events -->
math.Sqrt(20.0 / 9.81) -->
```

Après chaque pas, Solve compare le signe de chaque `g` aux deux bouts du pas ; un changement est localisé par
[optimize.Root] sur la sortie dense du pas, jusqu'aux derniers bits de `t`. Chaque événement donne `Event`, sa place
dans la liste, `T` et `Y`. Un `g` qui vaut 0 au premier temps n'est pas un événement, comme le conseillent Shampine et
Thompson (2000), pour qu'une résolution partie d'un événement ne s'arrête pas aussitôt. Deux passages du même `g` à
l'intérieur d'un pas s'annulent et sont manqués, comme dans MATLAB et scipy : `maxStep` rend les pas assez courts pour
les voir.

```python
def ground(t, y):
    return y[0]
ground.terminal = True
ground.direction = -1
b = solve_ivp(lambda t, y: [y[1], -9.81], (0, 10), [10, 0], events=ground, rtol=1e-6, atol=1e-9)
b.t_events[0][0]   # 1.4278431229270643
```

```matlab
function [value, isterminal, direction] = ground(t, y)
  value = y(1); isterminal = 1; direction = -1;
end
opts = odeset('RelTol', 1e-6, 'AbsTol', 1e-9, 'Events', @ground);
[t, y, te, ye, ie] = ode45(@(t, y) [y(2); -9.81], [0 10], [10 0], opts);
te   % 1.427843122927064
```

### Quand il échoue

Solve donne un `Err` de sorte `"ode"` avec `T`, le temps qu'il a atteint, `Message`, et `Partial`, la solution jusqu'à
`T`, qu'on peut encore tracer :

- le pas tombe sous $16 \epsilon |t|$ : la solution explose, ou a une singularité, à cet endroit ;
- `steps` est atteint ;
- `f` donne un NaN ou un infini : le pas est coupé en deux et réessayé, 10 fois, puis le message nomme la composante ;
- `f` donne une valeur d'une autre forme que `y0`, ou pas un nombre ;
- le problème a l'air *stiff*, plus bas ;
- avec `stiff = true`, `jacobian` donne une valeur qui n'est pas une matrice `n × n` de nombres finis, ou un jacobien
  par différences contient un NaN ou un infini, ou la matrice $I - h\gamma J$ d'un pas reste singulière alors que le pas
  est coupé en deux 10 fois.

$y' = y^2$ depuis $y(0) = 1$ vaut $1 / (1 - t)$, qui part à l'infini en $t = 1$ :

```cesia
blow = ode.Solve((t, y) -> y * y, [0.0, 2.0], 1.0)
blow.Error.T -->
p = match blow
  result.Ok(s) -> s
  result.Err(e) -> e.Partial
end
p.Stats.Steps -->
```

MATLAB et scipy donnent un avertissement et une solution qui finit tôt ; un programme qui ne lit que la solution le
manque.

Un mauvais argument, comme `rtol = 0.0`, des temps qui ne croissent pas ni ne décroissent, un `y0` avec un NaN, est un
bug de l'appelant : une panic qui le nomme. `s.At(t)` hors de la solution aussi.

### Les problèmes stiff

Certains systèmes mélangent des changements rapides et lents : une réaction chimique où une espèce réagit en
microsecondes et une autre en heures. Ils sont *stiff* (raides) : une fois le changement rapide éteint, la solution est
lisse, et pourtant une méthode comme celle-ci doit garder des pas aussi petits que le changement rapide, sans quoi ses
erreurs grandissent sans limite. Elle fait alors des millions de pas minuscules, chacun précis, comme si le problème
était difficile, alors que c'est la méthode qui ne lui convient pas. L'oscillateur de Van der Pol à $\mu = 1000$ est
l'exemple classique :

```cesia
vdp(t, y) = [y[2], 1000.0 * (1.0 - y[1] * y[1]) * y[2] - y[1]]
v = ode.Solve(vdp, [0.0, 3000.0], [2.0, 0.0])
v.Error.Message -->
v.Error.Partial.Stats.Steps -->
```

Le `ode45` de MATLAB et le `RK45` de scipy ne disent rien, et prennent des minutes. Solve y fait attention : le test de
Hairer et Wanner, d'après Shampine (1977), estime $h |\lambda|$, le pas fois la plus grande vitesse de changement le
long du pas, à partir des deux derniers étages du pas, qui sont au même temps. Au-delà de 3,25, le pas est à la limite
de ce que la méthode peut supporter sans que ses erreurs grandissent ; sur 15 tels pas, sans 6 pas calmes à la suite
entre eux, Solve s'arrête et le dit. Il fait le test tous les 1 000 pas, et à chaque pas dès qu'un pas l'a dépassé. Son
message dit quoi faire : `stiff = true`, une méthode faite pour les problèmes stiff, qui fait une centaine de pas là où
celle-ci en ferait des millions :

```cesia
w = result.Unwrap(ode.Solve(vdp, [0.0, 3000.0], [2.0, 0.0], stiff = true))
w.Stats -->
w.At(3000.0) -->
```

La même chose en Python, R et MATLAB, aux mêmes tolérances. Le `ode15s` et le `ode23s` de MATLAB, et le `Radau`, le
`BDF` et le `LSODA` de scipy, sont leurs méthodes pour les problèmes stiff ; Cesia en a une, choisie sur mesure,
ci-dessous.

```python
sol = solve_ivp(lambda t, y: [y[1], 1000 * (1 - y[0] ** 2) * y[1] - y[0]], (0, 3000), [2, 0], method="Radau",
                rtol=1e-6, atol=1e-9)
sol.y[:, -1]   # [-1.51060692e+00, 1.17838003e-03]
```

```r
library(deSolve)
vdp <- function(t, y, p) list(c(y[2], 1000 * (1 - y[1]^2) * y[2] - y[1]))
out <- ode(c(2, 0), c(0, 3000), vdp, NULL, method = "rodas", rtol = 1e-6, atol = 1e-9)
out[2, ]
```

```matlab
vdp = @(t, y) [y(2); 1000 * (1 - y(1)^2) * y(2) - y(1)];
opts = odeset('RelTol', 1e-6, 'AbsTol', 1e-9);
[t, y] = ode15s(vdp, [0 3000], [2 0], opts);
y(end, :)
```

### La méthode

Solve se sert de la méthode de Dormand et Prince (1980), celle du `ode45` de MATLAB et du `RK45` de scipy. C'est une
*méthode de Runge–Kutta* : chaque pas de $t$ à $t + h$ évalue $f$ en 7 *étages*,
$k_i = f(t + c_i h, y + h \sum_j a_{ij} k_j)$, et les combine en $y_1 = y + h \sum_i b_i k_i$, qui suit la série de
Taylor de la solution jusqu'à $h^5$ : elle est d'*ordre 5*. Les nombres $a$, $b$ et $c$ sont ceux de l'article. Une
autre combinaison, $z_1 = y + h \sum_i \beta_i k_i$, est d'ordre 4, et leur différence estime l'erreur du pas sans coût.
Le dernier étage est $f(t + h, y_1)$, le premier étage du pas suivant, si bien qu'un pas coûte 6 appels de `f`.

- **Le test de l'erreur**, tel que le donnent Hairer, Nørsett et Wanner (I, §II.4) :
  $\text{err} = \sqrt{\frac{1}{n} \sum_i ((y_{1,i} - z_{1,i}) / \text{sc}_i)^2}$ avec
  $\text{sc}_i = \text{atol}_i + \text{rtol} \cdot \max(|y_i|, |y_{1,i}|)$ ; le pas est fait quand $\text{err} \le 1$.
- **Le pas suivant**, par le contrôle PI de Gustafsson (1991) tel que l'a DOPRI5 :
  $h_\text{new} = h \cdot \min(10 ; \max(0{,}2 ; 0{,}9 \cdot \text{err}^{-0{,}17} \cdot \text{err}_{\text{prev}}^{0{,}04}))$,
  pas plus grand juste après un pas refusé. Le second facteur, venant de l'erreur du pas précédent, lisse la suite des
  pas ; Söderlind (2003) explique pourquoi.
- **Le premier pas**, par la règle de Gladwell, Shampine et Brankin (1987) : le pas sur lequel la méthode d'Euler
  déplace `y` de 1 % de son échelle, puis borné par une estimation de la dérivée seconde, à partir d'un appel de `f` de
  plus.
- **La sortie dense** de Shampine (1986) : un polynôme de degré 4 dans chaque pas, à partir des étages déjà calculés,
  qui rejoint les états du pas aux deux bouts ; `At` l'évalue, et l'erreur d'un état entre deux pas est de l'ordre de
  celle de la méthode elle-même. Elle a besoin des étages de chaque pas : $6n + 2$ floats par pas, 160 octets pour
  Lorenz.

Les tests de Cesia vérifient la méthode elle-même : les 17 conditions d'ordre 5 sur $b$ et les 8 d'ordre 4 sur
$\beta$, jusqu'aux derniers bits ; l'ordre 4 de la sortie dense en plusieurs points d'un pas ; le premier pas du solver
contre un pas calculé ici avec la table de l'article ; puis des problèmes aux solutions connues : la décroissance, une
rotation, l'équation logistique, les orbites de Kepler aux excentricités de 0,1 à 0,9, les invariants d'un solide en
rotation, l'orbite d'Arenstorf qui se referme après 17.0652165601579625588917206249, une résolution vers l'avant puis
vers l'arrière.

### La méthode pour les problèmes stiff

Avec `stiff = true`, Solve se sert de Rodas5P (Steinebach 2023), une *méthode de Rosenbrock* (Hairer et Wanner II,
§IV.7). Là où une méthode explicite comme celle de Dormand et Prince tire chaque étage des étages d'avant, une méthode
de Rosenbrock résout, à chaque étage, un système linéaire de matrice $W = I - h\gamma J$, où $J = f_y$ est le *jacobien*
de `f` au début du pas : la matrice $n \times n$ de la façon dont chaque composante de $f$ change avec chaque composante
de $y$. Une composante rapide, qui décroît à une vitesse $\lambda$ bien en dessous de 0, voit son changement divisé par
environ $1 - h\gamma\lambda$, si bien que son erreur s'éteint quel que soit le pas : la méthode est *L-stable*, son
facteur de croissance $R(z)$ vaut au plus 1 pour tout $z = h\lambda$ dont la partie réelle est sous 0, et 0 quand $z$
tend vers $-\infty$. Les pas ne suivent alors que la partie lente de la solution.

Sous la forme avec les étages $u_i$ que prend le code RODAS de Hairer et Wanner, pour un pas de $t$ à $t + h$, avec
$f_t$ la dérivée de $f$ en $t$ :

$$
(I - h\gamma J)\, u_i = h\gamma\, f(t + c_i h,\; y + \sum_{j<i} a_{ij} u_j) + h^2 \gamma\, d_i\, f_t + \gamma \sum_{j<i}
c_{ij} u_j
$$

Rodas5P a 8 étages et $\gamma = 0{,}21193756319429014$ ; ses nombres $a$, $c$ et $d$ sont ceux que publie Steinebach
avec le package Julia OrdinaryDiffEq.jl. $y_1 = y + \sum_j a_{8j} u_j + u_8$ est d'ordre 5 ; $y + \sum_j a_{8j} u_j$,
l'argument du dernier étage, est d'ordre 4, si bien que $u_8$ estime l'erreur du pas. Un pas coûte un jacobien, une
factorisation de $W$ par [num.Lu], 8 résolutions avec elle et 8 appels de `f`. Il n'y a pas d'itération de Newton, comme
dans les méthodes implicites (`ode15s`, `Radau`, `BDF`), donc pas d'itération qui puisse ne pas converger.

- **Le jacobien** : `jacobian = (t, y) -> J` le donne, une matrice `n × n`, ou un nombre pour un `y0` nombre. Sans lui,
  Solve calcule chaque colonne $j$ par une différence avant, à partir d'un appel de `f` de plus avec $y_j$ déplacé de
  $\delta_j = \sqrt{\epsilon} \max(|y_j|, \text{atol}_j)$ : la règle de Dennis et Schnabel (1996) pour les différences
  finies, avec $\text{atol}_j$ comme taille typique de $y_j$, sous laquelle le test de l'erreur ne voit pas de
  différence ($\sqrt{\epsilon}$ quand les deux valent 0). La règle du code RODAS,
  $\sqrt{\epsilon \max(|y_j|, 10^{-5})}$, déplace le $y_2$ du problème de Robertson, environ $10^{-13}$, de 400 fois sa
  propre taille : le jacobien sort 200 fois trop grand à un endroit, et la résolution fait 4 fois plus de pas, jusqu'à
  une réponse fausse de 15 %. $f_t$ vient d'une différence de plus, sur $\sqrt{\epsilon} |h|$, l'échelle que le pas
  distingue. Sans `jacobian`, un pas appelle `f` $n + 1$ fois de plus.
- **Le pas suivant** : $h_\text{new} = h \cdot \min(6 ; \max(0{,}2 ; 0{,}9 \cdot \text{err}^{-1/5}))$, ou plus petit par
  le *contrôle prédictif* de Gustafsson (1994), comme dans RODAS,
  $h \cdot 0{,}9 \cdot (h / h_\text{prev})^{-1} \cdot (\text{err}^2 / \text{err}_\text{prev})^{-1/5}$, qui suit la
  tendance des deux derniers pas. Sur l'oscillateur de Van der Pol à $\mu = 1000$, il refuse 23 pas au lieu de 176.
- **La sortie dense** : celle de Steinebach, un polynôme de degré 4 dans chaque pas, à partir de ses étages, qui rejoint
  les états aux deux bouts. Le test de l'erreur ne voit que ces bouts. Là où une décroissance rapide suit un forçage
  lent, comme dans $y' = \lambda (y - \cos t) - \sin t$ avec $\lambda = -10^6$ (Prothero et Robinson 1974), la méthode
  met chaque bout sur $\cos t$ quel que soit le pas : les pas grandissent jusqu'à 3,4 à `rtol = 1e-6`, et `At` entre eux
  est faux de 5 %. `maxStep` borne les pas là où les valeurs entre eux comptent : avec `maxStep = 0.05`, `At` est juste
  à `1e-8` près.
- **La taille** : `y0` a au plus 1 000 composantes avec `stiff = true` ; $J$, $W$ et ses facteurs sont des matrices
  $n \times n$, de 8 MB chacune à 1 000.

Les tests de Cesia vérifient la méthode elle-même : les deux tables, Rodas5P et Rodas4 (Hairer et Wanner 1996 :
6 étages, ordre 4), contre les conditions d'ordre sur chaque arbre enraciné jusqu'à l'ordre 5, telles que les liste la
table 2 de Steinebach pour les méthodes de Rosenbrock ; leurs méthodes emboîtées, d'un ordre de moins et pas davantage ;
leurs sorties denses ; les ordres observés quand le pas est coupé en deux, 4,0 et 5,9 ; le premier pas du solver contre
un pas calculé dans le test, et Rodas4, écrit dans le test, comme oracle (une référence sûre) ; puis la décroissance, le
problème de Prothero et Robinson, un système linéaire de vitesses $-1$, $-10^3$ et $-10^6$, les réactions de Robertson,
HIRES et OREGO (Hairer et Wanner II, §IV.10) contre des références calculées pour les tests par le `Radau` de scipy à
`rtol = 1e-13`, la proportionnalité à la tolérance, les événements, les formes et chaque erreur.

### Dans une cell

Dans un fichier de [cells](cells.md) (les morceaux d'un notebook, chacun avec son résultat), chaque cell tourne seule et
les graphiques s'affichent en dessous dans Cemacs. Un curseur sur `rho` referait la résolution et le graphique à mesure
qu'il bouge :

```cesia norun
use std/num
use std/ode
use std/plot
use std/result

(* %% Lorenz *)
sigma = 10.0
rho = 28.0
beta = 8.0 / 3.0
lorenz(t, y) = [sigma * (y[2] - y[1]), y[1] * (rho - y[3]) - y[2], y[1] * y[2] - beta * y[3]]
s = result.Unwrap(ode.Solve(lorenz, [0.0, 50.0], [1.0, 1.0, 1.0]))
s.Stats

(* %% Graph *)
ts = num.Linspace(0.0, 50.0, 5000)
ys = s.At(ts)
plot.Grid([plot.Of([plot.Line(ts, ys[:, 1])], x = "t", y = "x"),
           plot.Of([plot.Line(ys[:, 1], ys[:, 3])], x = "x", y = "z")], columns = 2)
```

Le même graphique, fait ici et dessiné en SVG :

```cesia
use std/num
use std/plot
ts = num.Linspace(0.0, 50.0, 5000)
ys = l.At(ts)
g = plot.Grid([plot.Of([plot.Line(ts, ys[:, 1])], x = "t", y = "x"), plot.Of([plot.Line(ys[:, 1], ys[:, 3])], x = "x", y = "z")], columns = 2)
plot.Svg(g) then result.IsOk() -->
```

### La vitesse de Solve

Le système de Lorenz sur `[0, 100]` à `rtol = 1e-8` et `atol = 1e-10`, et sur `[0, 50]` aux réglages par défaut, la
résolution seule, à l'intérieur de chaque programme : la médiane de 21 lancements de chacun, alternés, et l'intervalle à
95 % de cette médiane, sur la machine de [Vitesse](speed.md#à-côté-des-géants), avec d'autres travaux qui y tournaient,
le 2026-11-13. Les programmes sont dans le texte de cette section ; MATLAB n'a pas été mesuré, faute de MATLAB sous la
main.

| | `[0, 100]`, `1e-8` | `[0, 50]`, par défaut |
|---|---:|---:|
| **Cesia**, `cesia run` | **127 ms** (118 à 145) | **21,1 ms** (20,6 à 24,5) |
| **Cesia**, dans une cell d'une session | **125 ms** (121 à 139) | |
| scipy 1.18.1, `solve_ivp`, RK45 | 681 ms (624 à 761) | 138 ms (129 à 159) |
| GNU Octave 11.3, `ode45` | 8 827 ms (8 188 à 11 051) | 1 167 ms (1 142 à 1 530) |

Les trois prennent la même méthode, aux mêmes tolérances, et font à peu près le même travail : sur `[0, 100]`, Cesia
fait 11 412 pas et appelle `f` 69 002 fois, scipy 10 859 pas et 67 214 appels, Octave 12 855 pas et 77 593 appels.
Cesia est 5 fois plus rapide que scipy et 70 fois plus rapide qu'Octave. Sur cinq autres problèmes, les orbites
d'Arenstorf et de Kepler et l'oscillateur de Van der Pol à $\mu = 10$, Cesia appelle `f` aussi souvent que scipy à 6 %
près.

Chaque pas fait 6 appels de `f` et environ 58 opérations sur des arrays de 3 floats, et les deux tournent dans
l'interpréteur : le JIT de [Vitesse](speed.md#ce-qui-devient-du-code-machine) ne fait pas encore de code machine d'une
boucle qui fait des arrays, comme `[a, b, c]`, ou qui calcule sur des arrays entiers, comme `y + h * k`, si bien qu'une
`f` de premier niveau, une closure (une fonction qui garde les variables de l'endroit où elle est écrite) et la `f`
d'une cell coûtent toutes la même chose : environ 11 µs par pas, dont 1,5 dans les 6 appels de `f`, chaque opération sur
un array environ 75 ns. L'objectif pour la première résolution, 60 ms, attend un JIT qui descende ce code jusqu'au code
machine.

Avec `stiff = true`, mesuré de la même façon : le problème de Robertson sur `[0, 1e11]` à `rtol = 1e-6` et
`atol = 1e-10` fait 207 pas en **15,2 ms** (14,2 à 25,0), celui de Van der Pol à $\mu = 1000$ sur `[0, 3000]` à
`rtol = atol = 1e-6` 536 pas en **29,1 ms** (27,4 à 33,1) ; le `Radau` de scipy, à `atol = 1e-9`, fait 1 292 pas sur le
second. Résolu de nouveau dans le même programme, une fois que le JIT a rendu `f` native, un pas de Robertson coûte
environ 38 µs : le jacobien par différences, la factorisation de $W$ et ses 8 résolutions tournent en code natif en
environ 10 µs de celles-ci, et le reste est la boucle des étages dans l'interpréteur. Sur une diffusion en 1-D de
100 points, 53 pas prennent 70 ms avec `jacobian` donné, et 100 ms par différences, qui appellent `f` 100 fois de plus
par pas. La comparaison avec le `Radau`, le `BDF` et le `LSODA` de scipy et avec le `ode15s` d'Octave attend les mesures
faites avant chaque release.

`use std/ode` ajoute au démarrage d'un programme le temps de lire son code et celui de std/optimize et de std/num, dont
il se sert : 1,3 ms au plus rapide de 21 lancements (4,15 ms contre 2,86 pour un programme qui affiche 1, le
2026-11-13), plus sur une machine occupée ; `use std/optimize` seul ajoute 0,45 ms. Un programme qui ne se sert d'aucun
des deux démarre comme avant.

## Les intégrales

[quad.Integral] calcule l'*intégrale* d'une fonction `f` de `a` à `b` : l'aire sous sa courbe, comptée en négatif là où
la courbe est sous 0. C'est ce que fait `integral` dans MATLAB et `quad` dans scipy. Voici l'intégrale de
$x^{-1/2} \log(1/x)$ de 0 à 1, qui vaut 4, d'une fonction qui grandit sans limite en 0 :

```cesia
use std/quad
logRoot(x) = x ^ (-0.5) * math.Log(1.0 / x)
q = result.Unwrap(quad.Integral(logRoot, 0.0, 1.0))
q -->
```

`Value` est l'intégrale, `Error` l'estimation de son erreur, `Evaluations` les appels de `f`, et `Intervals` les
morceaux en lesquels l'intervalle a été coupé. `x -> ...` est une fonction écrite sur place :
`quad.Integral(x -> x * x, 0.0, 3.0)` revient à définir `square(x) = x * x` et à donner `square`. La même chose en
Python, R et MATLAB, aux mêmes tolérances :

```python
import math
from scipy.integrate import quad
y, err, info = quad(lambda x: x**-0.5 * math.log(1 / x), 0, 1, epsabs=1e-12, epsrel=1e-10, full_output=1)
# 4.000000000000071, 2.1582735598713043e-13, info['neval'] 315, info['last'] 8
```

```r
integrate(function(x) x^(-0.5) * log(1 / x), 0, 1, rel.tol = 1e-10, abs.tol = 1e-12)
# 4.0000000000000711, 8 subdivisions
```

```matlab
q = integral(@(x) x.^(-0.5) .* log(1 ./ x), 0, 1, 'RelTol', 1e-10, 'AbsTol', 1e-12)
% 3.999999999976525 in GNU Octave
```

Le `quad` de scipy et le `integrate` de R font tourner le propre code de QUADPACK, dont Cesia suit la méthode : la même
valeur jusqu'au dernier bit, à partir des mêmes 315 appels de `f`. L'`integral` de MATLAB est une autre méthode
(Shampine 2008), et celui de GNU Octave appelle `quadcc`, les règles de Clenshaw et Curtis que Gonnet (2010) a rendues
adaptatives, qui s'arrête ici à 2.3e-11 de 4.

| Cesia | MATLAB | scipy |
|---|---|---|
| `quad.Integral(f, a, b)` | `integral(f, a, b)` | `quad(f, a, b)` |
| `math.Inf`, `-math.Inf` comme borne | `Inf`, `-Inf` | `np.inf`, `-np.inf` |
| `rtol = 1e-10`, `atol = 1e-12`, les valeurs par défaut | `'RelTol', 1e-6`, `'AbsTol', 1e-10` | `epsrel=1.49e-8`, `epsabs=1.49e-8` |
| `points = [c1, c2]` | `'Waypoints', [c1 c2]` | `points=[c1, c2]` |
| `limit = 1000` morceaux | `'MaxIntervalCount', 650` | `limit=50` |
| `q.Value`, `q.Error` | `[q, errbnd] = quadgk(...)` | `y, abserr = quad(...)` |

`f` prend un nombre et donne un nombre, si bien que n'importe quelle fonction marche, une avec un `if` aussi ;
l'`integral` de MATLAB appelle plutôt `f` sur des arrays de points. `f` peut elle-même appeler Integral : une intégrale
double, ce sont deux appels imbriqués, ici l'aire du disque de rayon 1, $\pi$, l'intégrale de -1 à 1 de sa corde en $x$,
elle-même l'intégrale de 1 de $-\sqrt{1 - x^2}$ à $\sqrt{1 - x^2}$ :

```cesia
chord(x) = quad.Integral(y -> 1.0, -math.Sqrt(1.0 - x * x), math.Sqrt(1.0 - x * x)).Value.Value
quad.Integral(chord, -1.0, 1.0).Value.Value -->
```

`quad.Integral(...).Value` est ce que contient l'`Ok`, la struct, donc `.Value.Value` est l'intégrale elle-même ; dans
un programme, `result.Unwrap` ou `?` se lisent mieux.

### Les bornes infinies

Une borne peut être [math.Inf] ou `-math.Inf`, qui est `1.0 / 0.0` et son opposé :

```cesia
bell(x) = math.Exp(-x * x)
quad.Integral(bell, -math.Inf, math.Inf).Value -->
math.Sqrt(math.Pi) -->
quad.Integral(x -> math.Exp(-x), 0.0, math.Inf).Value.Value -->
```

Le changement de variable $x = a + (1 - t) / t$ envoie $[a, \infty)$ sur $(0, 1]$, avec $dx = -dt / t^2$ : l'intégrale
de $f(x)$ de $a$ à $\infty$ est l'intégrale de

$$
\frac{1}{t^2} f(a + \frac{1 - t}{t})
$$

de 0 à 1, et la méthode ci-dessous travaille sur $(0, 1]$, où elle n'évalue jamais $t = 0$. De $-\infty$ à $b$,
$x = b - (1 - t) / t$ ; de $-\infty$ à $\infty$, $f(x) + f(-x)$ à partir de 0. Une fonction qui décroît lentement, comme
$1/x^2$, devient une fonction avec une singularité en $t = 0$, dont l'extrapolation ci-dessous s'occupe. Une borne finie
très loin, comme `1e300`, n'est pas un infini : sur $[-10^{300}, 10^{300}]$, les 21 points de la première règle tombent
tous là où $e^{-x^2}$ vaut 0, et Integral donne 0 avec une `Error` de 0. Donnez `math.Inf` pour un intervalle infini.

### Les endroits où f saute

`points` liste les endroits entre `a` et `b` où `f` saute, a un coude, ou est singulière : les premiers morceaux y
finissent, et aucun d'eux n'a la difficulté à l'intérieur. Une marche en 0,3 :

```cesia
step(x) = if x < 0.3 1.0 else 2.0 end
quad.Integral(step, 0.0, 1.0).Value -->
quad.Integral(step, 0.0, 1.0, points = [0.3]).Value -->
```

Sans `points`, la méthode trouve le saut elle-même, en coupant les morceaux autour de plus en plus petits : 357 appels
de `f`. Avec eux, les deux morceaux sont exacts tout de suite : 42 appels. Des points hors de l'intervalle sont une
panic ; des points égaux à `a` ou à `b` sont laissés de côté, et un point donné deux fois compte une fois. Avec une
borne infinie, coupez l'intégrale en un point en deux appels.

### Ce qu'elle promet

`Integral` donne un `Ok` quand `Error` vaut au plus `max(atol, rtol |Value|)` : avec les valeurs par défaut, 10
chiffres, ou `1e-12` près de 0. `Error` est une estimation, venant du propre test de la méthode, pas une borne. Sur une
fonction lisse, elle est pessimiste : la vraie erreur est souvent bien plus petite. Elle peut être trompée par un détail
qu'aucun point de la règle ne voit, comme un pic plus étroit que les écarts entre eux, comme peut l'être toute méthode
qui ne fait qu'échantillonner `f`.

Les tests de Cesia la vérifient sur 42 intégrales des sortes sur lesquelles le livre de QUADPACK teste ses méthodes,
chacune contre sa forme close : $x^\alpha \log(1/x)$ et $x^{-1/2}$, singulières à un bout ; $|x - 1/3|^\alpha$,
singulière à l'intérieur, avec et sans `points` ; un pic de largeur $4^{-\alpha}$, $\alpha$ jusqu'à 8 ;
$(1 - x^2)^{-1/2} / (x + 1 + 2^{-\alpha})$, singulière aux deux bouts à côté d'un pôle ; $\sin^{\alpha - 1} x$ et
$\log(1/x)^{\alpha - 1}$, dont les intégrales sont des valeurs des fonctions [special.Beta] et [special.Gamma] ;
$x^\alpha e^{-x}$ et $e^{-x^2}$ sur des intervalles infinis ; une oscillation, $x \sin 30x \cos x$ sur $[0, 2\pi]$ ; un
saut ; des intervalles à l'envers. Sur chacune, la vraie erreur est dans la tolérance et dans `Error` ; et chacune fait
exactement autant d'appels de `f`, et autant de morceaux, que le `quad` de scipy aux mêmes tolérances, avec la même
valeur et la même `Error` jusqu'au dernier bit. L'`integral` de GNU Octave en manque 10 sur 42 de plus que la tolérance
demandée : sur $|x - 1/3|^{-0{,}8}$ de 0,0039, sur $(1 + x)^{-1} x^{-1/2}$ sur $[0, \infty)$ de 1,3e-8.

### Quand elle échoue

Un `Err` de sorte `"quad"` porte `Value` et `Error`, les meilleures estimations trouvées, et un message qui dit quoi
changer. Les propres tests de QUADPACK décident de chaque cas :

```cesia
quad.Integral(x -> 1.0 / x, 0.0, 1.0, limit = 20).Error.Message -->
quad.Integral(x -> x ^ (-1.1), 0.0, 1.0).Error -->
quad.Integral(x -> 1.0 / math.Abs(x - (1.0e10 + 1.0 / 3.0)), 1.0e10, 1.0e10 + 1.0).Error.Message -->
quad.Integral(x -> math.Sin(x), 0.0, math.Inf).Error.Message -->
```

- **La limite** : la somme des erreurs est encore au-dessus de la tolérance après `limit` morceaux.
- **L'arrondi** : couper un morceau en deux a changé son intégrale de moins de $10^{-5}$ de celle-ci sans que son erreur
  baisse, 10 fois, ou a fait grandir l'erreur, 20 fois : la tolérance est sous ce que les floats peuvent donner. `rtol`
  ne peut pas descendre sous 50 eps, $1{,}1 \cdot 10^{-14}$, avec `atol = 0.0`.
- **Un mauvais endroit** : un morceau est devenu si petit que ses deux moitiés ne se distinguent plus en floats, comme
  près de $10^{10} + 1/3$ ci-dessus, où les floats sont espacés de $2 \cdot 10^{-6}$ : $1/|x - s|$ n'y est pas
  intégrable.
- **L'extrapolation** : la table de l'algorithme epsilon continue de changer de plus que ses propres estimations, comme
  pour $\sin x$ sur $[0, \infty)$, dont l'intégrale n'a pas de limite.
- **La divergence** : la valeur extrapolée et la somme des morceaux diffèrent de plus d'un facteur 100, ou l'erreur est
  au-dessus de l'aire. L'intégrale de $x^{-1{,}1}$ de 0 à 1 est infinie ; l'extrapolation donne $-10 = 1 / (1 - 1{,}1)$,
  la valeur que prend $1 / (p + 1)$, l'intégrale de $x^p$ pour $p > -1$, en $p = -1{,}1$, et le test de divergence la
  refuse. scipy et R donnent le même $-10$ avec un avertissement.
- **Ce que donne `f`** : un NaN, un infini, un texte ou tout autre chose qu'un nombre est un `Err` qui nomme l'endroit :
  `f(0.5) is "a", not a finite number.` Une panic à l'intérieur de `f` reste une panic.

Toute fonction non intégrable n'est pas attrapée. Avec `points = [1.0 / 3.0]`, $1 / (x - 1/3)$ sur $[0, 1]$ donne un
`Ok` d'environ 0 : chaque côté diverge, et l'extrapolation de leur somme se pose sur un nombre, comme dans le code de
QUADPACK. N'intégrez que ce qui a une intégrale.

### La méthode d'Integral

Integral est le QAGS de QUADPACK (Piessens, de Doncker-Kapenga, Überhuber et Kahaner 1983), la méthode de de Doncker
(1978) ; avec `points`, QAGP ; avec une borne infinie, QAGI.

- **La règle** : sur un morceau $[a, b]$, la *règle de Gauss–Kronrod* à 21 points, $K = \sum_i w_i f(x_i)$. Dix de ses
  points sont ceux de la règle de Gauss $G$ à 10 points, la règle la plus précise sur 10 points : elle intègre
  exactement tout polynôme de degré 19 ou moins. Kronrod (1965) a ajouté 11 points pour que les 21 intègrent exactement
  tout polynôme de degré 31 ou moins, et $G$ vient gratuitement, à partir de 10 des mêmes valeurs de `f`. Les nouveaux
  points sont les zéros du *polynôme de Stieltjes* $E_{11}$, qui est orthogonal à $x^k P_{10}(x)$ pour
  $k = 0, \dots, 10$, $P_{10}$ étant le polynôme de Legendre dont les zéros sont les points de Gauss. Les points et les
  poids de Cesia ont été calculés pour elle à partir de $E_{11}$ en nombres rationnels exacts, ses zéros à 100 chiffres
  ; ses tests les recalculent par l'algorithme de Laurie (1997), comme les valeurs propres d'une matrice tridiagonale,
  et s'accordent à 2 eps près.
- **L'estimation de l'erreur** : $|K - G|$ serait une estimation de l'erreur de $G$ ; l'erreur de $K$ est bien plus
  petite. QUADPACK prend $E = I_\text{asc} \min(1, (200 |K - G| / I_\text{asc})^{3/2})$, où $I_\text{asc}$, l'intégrale
  de $|f - m|$ sur le morceau, $m$ la moyenne de `f` sur celui-ci, mesure à quel point `f` varie : la puissance $3/2$
  fait baisser $E$ plus vite que $|K - G|$ à mesure que la règle converge, et le facteur 200 la garde du côté sûr. $E$
  vaut au moins $50 \epsilon$ fois l'intégrale de $|f|$, ce que laisse l'arrondi. Les termes sont additionnés par
  paires, $f(c - h x) + f(c + h x)$, si bien qu'une `f` impaire sur un intervalle centré en 0 donne exactement 0.
- **La stratégie** : garder les morceaux dans l'ordre de leurs erreurs ; couper en deux celui qui a la plus grande ;
  s'arrêter quand la somme des erreurs vaut au plus la tolérance. Près d'une singularité, les morceaux deviennent de
  plus en plus petits, et leurs sommes convergent lentement.
- **L'extrapolation** : quand le morceau de plus grande erreur est l'un des plus petits, comme à côté d'une singularité,
  la méthode coupe d'abord les morceaux plus grands jusqu'à ce que leurs erreurs soient sous la tolérance, puis ajoute
  la somme de tous les morceaux à une suite $S_1, S_2, \dots$, un niveau de coupe plus près de la singularité à chaque
  fois, et estime sa limite par l'*algorithme epsilon* de Wynn (1956) : $\epsilon^{(n)}_{-1} = 0$,
  $\epsilon^{(n)}_0 = S_n$ et
  $\epsilon^{(n)}_{k+1} = \epsilon^{(n+1)}_{k-1} + \frac{1}{\epsilon^{(n+1)}_k - \epsilon^{(n)}_k}$. Ses colonnes paires
  $\epsilon_{2k}$ sont les transformées de Shanks de la suite : $\epsilon_2$ est le $\Delta^2$ d'Aitken, exact sur une
  suite dont l'erreur diminue du même facteur à chaque pas, et les colonnes plus hautes enlèvent plusieurs de ces termes
  à la fois. Près d'une singularité à un bout comme $x^\alpha$, chaque niveau de coupe divise l'erreur du morceau du
  bout par environ $2^{\alpha + 1}$ : une telle suite. Cesia construit les colonnes paires seules par la *règle de la
  croix* (cross rule) de Wynn (1966), comme le fait QUADPACK, garde au plus 50 sommes, et prend comme erreur de
  l'extrapolation la distance aux trois dernières valeurs extrapolées.
- **Les bornes infinies** : le changement de variable ci-dessus, et la règle de Gauss–Kronrod à 15 points (7 de Gauss),
  sur des morceaux de $(0, 1]$.

La méthode tourne en code natif qui rappelle `f`, chaque pas tel que le prend le code de QUADPACK, dans le même ordre :
la même méthode écrite en Cesia passait six fois plus de temps sur ses propres pas que sur `f`, et l'interpréteur ne
sait pas encore en faire du code machine.

Les tests de Cesia vérifient, en plus des 42 intégrales : les points et les poids de Laurie pour les deux règles ; les
degrés des règles, $x^k$ exact à 4 eps près jusqu'à $k = 31$ et pas à 32, et l'exactitude de $G$ jusqu'à 19 vue dans
l'estimation ; chaque `Err` ci-dessus ; ce que donne `f` ; la borne des appels de `f` par `limit`,
$21 (2\,\text{limit} - 1)$ ; chaque mauvais argument.

### Dans une cell

Dans un fichier de [cells](cells.md), l'aire sous une courbe et la courbe elle-même :

```cesia norun
use std/math
use std/num
use std/plot
use std/quad
use std/result

(* %% Integral *)
h(x) = math.Exp(-x * x)
q = result.Unwrap(quad.Integral(h, 0.0, 1.0))
q.Value

(* %% Graph *)
us = num.Linspace(0.0, 1.0, 100)
xs = num.Linspace(-0.5, 1.5, 200)
plot.Of([plot.Area(us, 0.0 * us, h(us), label = "$(q.Value) ± $(q.Error)"), plot.Line(xs, h(xs))])
```

`q.Value` affiche 0.7468241328124271, $\frac{\sqrt{\pi}}{2} \text{erf}(1)$. Le même graphique, fait ici et dessiné en
SVG :

```cesia
use std/special
h(x) = math.Exp(-x * x)
qh = result.Unwrap(quad.Integral(h, 0.0, 1.0))
math.Near(qh.Value, math.Sqrt(math.Pi) / 2.0 * special.Erf(1.0)) -->
us = num.Linspace(0.0, 1.0, 100)
xs = num.Linspace(-0.5, 1.5, 200)
plot.Svg(plot.Of([plot.Area(us, 0.0 * us, h(us), label = "$(qh.Value) ± $(qh.Error)"), plot.Line(xs, h(xs))])) then result.IsOk() -->
```

### La vitesse d'Integral

L'intégrale de $x^{-1/2} \log(1/x)$ de 0 à 1 aux valeurs par défaut, `rtol = 1e-10` et `atol = 1e-12`, 315 appels de `f`
dans chaque langage : la médiane de 21 lancements de chacun, alternés, et l'intervalle à 95 % de cette médiane, sur la
machine de [Vitesse](speed.md#à-côté-des-géants), avec d'autres travaux qui y tournaient, le 2026-11-13. Un premier
appel est le premier dans un programme tout neuf ; ensuite, la moyenne de 1 000 appels dans le même programme.

| | premier appel | ensuite, chaque appel |
|---|---:|---:|
| **Cesia** | 135 µs (129 à 144) | **46,7 µs** (45,3 à 47,7) |
| scipy 1.18.1, `quad` | **116 µs** (112 à 118) | 82,3 µs (80,0 à 85,6) |
| GNU Octave 11.3, `integral` | | 2 309 µs (2 283 à 2 330) |

Cesia est 1,8 fois plus rapide que scipy une fois son code lu, et 49 fois plus rapide qu'Octave, dont l'`integral`
s'arrête aussi plus loin de 4, à 2.3e-11. scipy gagne le premier appel : Cesia lit et prépare alors le code de std/quad.
Le temps part dans les appels de `f` : avec `math.Sqrt` comme `f`, son intégrale de 0 à 1 fait 231 appels en 21 µs,
environ 90 ns chacun pour l'appel et le propre travail de la méthode, et le propre travail de `f` vient en plus. MATLAB
n'a pas été mesuré, faute de MATLAB sous la main. `use std/quad` n'ajoute à son démarrage aucun temps qu'un programme
puisse mesurer, 2,84 ms contre 2,89 pour un programme qui affiche 1, et un programme qui ne s'en sert pas démarre comme
avant.

### La sécurité d'Integral

`f` est du code de l'appelant, donc Integral vérifie ce qu'elle donne : tout autre chose qu'un nombre fini est un `Err`
qui nomme l'endroit, jamais un NaN dans les sommes. Chaque boucle est bornée : `limit` borne les morceaux, si bien que
`f` est appelée au plus $21 (2\,\text{limit} - 1)$ fois, $15 (2\,\text{limit} - 1)$ avec une borne infinie et
$30 (2\,\text{limit} - 1)$ avec deux, et une fonction qui ne converge jamais finit sur l'`Err` de la limite, de
l'arrondi, du mauvais endroit ou de l'extrapolation ; la table de l'algorithme epsilon garde au plus 50 sommes. Garder
les morceaux dans l'ordre coûte jusqu'à `limit` pas chacun, si bien qu'une grande `limit` coûte un temps qui va comme
son carré : à 100 000, une fonction qui ne se stabilise jamais, $\sin(1/x)$, prend 3,4 secondes avant que l'arrondi
l'arrête. La mémoire grandit avec les morceaux, six nombres chacun, dans des arrays qui doublent quand ils sont pleins,
à partir de 16 : à la `limit` par défaut, 48 KB. Au-delà de la limite de mémoire du programme, le programme s'arrête
avec `Limit "memory" reached.`, comme tout programme. Le code natif compte son travail dans `--limit` à mesure qu'il
avance, et chaque appel de `f` est du code Cesia, si bien que `--limit` et [cells.Stop] arrêtent une longue intégrale en
quelques appels de `f`. Il ne lit que les nombres qu'Integral lui donne, ne garde aucun état hors d'un appel, si bien
que `f` peut rappeler Integral, et une panic dans `f` remonte comme une panic. Les mauvais arguments, une borne NaN, une
tolérance négative, des `points` hors de l'intervalle, sont des panics qui les nomment, avant que `f` soit appelée.

### Lectures sur les intégrales

- Robert Piessens, Elise de Doncker-Kapenga, Christoph W. Überhuber, David K. Kahaner. *QUADPACK: A Subroutine Package
  for Automatic Integration*. Springer, 1983. <https://doi.org/10.1007/978-3-642-61786-7>. QAGS, QAGP, QAGI, leurs
  règles et leurs tests ; la page du package lui-même : <https://www.netlib.org/quadpack/readme>.
- Elise de Doncker. "An adaptive extrapolation algorithm for automatic integration". *ACM SIGNUM Newsletter*
  13(2):12–18, 1978. <https://doi.org/10.1145/1053402.1053403>. La stratégie de QAGS.
- P. Wynn. "On a device for computing the $e_m(S_n)$ transformation". *Mathematical Tables and Other Aids to
  Computation* 10(54):91–96, 1956. <https://doi.org/10.2307/2002183>. L'algorithme epsilon.
- P. Wynn. "Upon systems of recursions which obtain among the quotients of the Padé table". *Numerische Mathematik*
  8:264–269, 1966. <https://doi.org/10.1007/BF02162562>. La règle de la croix.
- A. S. Kronrod. *Nodes and Weights of Quadrature Formulas: Sixteen-Place Tables*. Consultants Bureau, 1965. Les règles.
- Dirk P. Laurie. "Calculation of Gauss-Kronrod quadrature rules". *Mathematics of Computation* 66(219):1133–1145, 1997.
  <https://doi.org/10.1090/S0025-5718-97-00861-2>. Les règles comme valeurs propres, telles que les tests les calculent.
- L. F. Shampine. "Vectorized adaptive quadrature in MATLAB". *Journal of Computational and Applied Mathematics*
  211(2):131–140, 2008. <https://doi.org/10.1016/j.cam.2006.11.021>. L'`integral` de MATLAB.
- Pedro Gonnet. "Increasing the reliability of adaptive quadrature using explicit interpolants". *ACM Transactions on
  Mathematical Software* 37(3), 2010. <https://doi.org/10.1145/1824801.1824804>. Le `quadcc` de GNU Octave.

## Les matrices sparse

Une matrice *sparse* (creuse) a presque toutes ses cellules à 0 : la matrice d'une grille, où chaque point ne touche que
ses quelques voisins, d'un réseau, d'un circuit. [std/sparse] n'en garde que les non-zéros, colonne par colonne : pour
chaque colonne, les lignes de ses non-zéros dans l'ordre croissant et leurs valeurs, et l'endroit où chaque colonne
commence. C'est le format *compressed sparse columns* (CSC, les colonnes creuses compressées), celui de MATLAB et des
solvers de Davis (2006). Une grille 2-D de 300 × 300 points donne une matrice de 90 000 × 90 000 cellules, 8,1 milliards
en tout ; elle contient 448 800 non-zéros, qui prennent 8 MB au lieu de 65 GB.

```cesia
use std/sparse
a = sparse.Of([1, 2, 2, 3], [1, 1, 2, 3], [4.0, -1.0, 4.0, 2.0], 3, 3)
a.Nnz -->
sparse.Dense(a) -->
sparse.Mul(a, [1.0, 2.0, 3.0]) -->
sparse.Get(a, 2, 1) -->
```

| Cesia | MATLAB | scipy |
|---|---|---|
| `sparse.Of(i, j, v, rows, cols)`, des indices à partir de 1, les valeurs d'une même cellule additionnées | `sparse(i, j, v, m, n)` | `csc_array((v, (i, j)), shape = (m, n))`, à partir de 0 |
| `sparse.Eye(n)`, `sparse.Diags(values, offsets, n)` | `speye(n)`, `spdiags(B, d, n, n)` | `eye_array(n)`, `diags_array(values, offsets = d)` |
| `sparse.Kron(a, b)`, `sparse.Add(a, b)`, `sparse.Scale(c, a)` | `kron(A, B)`, `A + B`, `c * A` | `kron(A, B)`, `A + B`, `c * A` |
| `sparse.Mul(a, x)` | `A * x` | `A @ x` |
| `sparse.Transpose(a)`, `sparse.Dense(a)`, `sparse.Get(a, i, j)` | `A'`, `full(A)`, `A(i, j)` | `A.T`, `A.toarray()`, `A[i, j]` |
| `sparse.Solve(a, b)` | `A \ b` | `spsolve(A, b)` |
| `sparse.Read(path)` | (aucun) | `scipy.io.mmread(path)` |

Cesia n'a pas d'opérateurs sur les structs, donc là où MATLAB écrit `A * x` et `A + B`, Cesia écrit `sparse.Mul(a, x)`
et `sparse.Add(a, b)` : une fonction pour chacun, et pas de seconde façon.

### Construire une matrice sparse

[sparse.Of] prend trois arrays de même longueur, la ligne `i[k]`, la colonne `j[k]` et la valeur `v[k]` de chaque
non-zéro, puis la taille. Les valeurs données pour la même cellule sont additionnées, et une cellule dont la somme vaut
0.0 n'est pas gardée, comme le fait le `sparse` de MATLAB : `Nnz` compte les cellules qui ne valent pas 0. Un indice qui
n'est pas un nombre entier de 1 à `rows` ou à `cols` est une panic qui le nomme, comme `i[2] is 5`.

[sparse.Diags] met un nombre, ou un array, sur chaque diagonale : 0 est la diagonale principale, 1 celle du dessus, -1
celle du dessous. [sparse.Kron] est le produit de Kronecker, la matrice des blocs `a(i, j) b` : avec [sparse.Eye], il
change la matrice d'une ligne de points en celle d'une grille. Les différences secondes sur une ligne de `k` points,
puis sur une grille de `k × k` :

```cesia
k = 3
t = sparse.Diags([-1.0, 2.0, -1.0], [-1, 0, 1], k)
sparse.Dense(t) -->
a = sparse.Add(sparse.Kron(sparse.Eye(k), t), sparse.Kron(t, sparse.Eye(k)))
[a.Rows, a.Nnz] -->
```

### Résoudre a x = b

[sparse.Solve] résout `a x = b` pour une `a` carrée, comme le `A \ b` de MATLAB. `b` est un array de `a.Rows` nombres,
et `x` a sa forme, ou une matrice de `a.Rows` lignes, une colonne pour chaque second membre. La chaleur en chaque point
d'une plaque carrée dont le bord est tenu à 0, chauffée uniformément, est la solution de l'équation de Poisson, ici sur
une grille de 50 × 50 points :

```cesia
use std/list
use std/matrix
k = 50
t = sparse.Diags([-1.0, 2.0, -1.0], [-1, 0, 1], k)
a = sparse.Add(sparse.Kron(sparse.Eye(k), t), sparse.Kron(t, sparse.Eye(k)))
u = result.Unwrap(sparse.Solve(a, matrix.Ones(1, k * k) / ((k + 1.0) ^ 2)))
list.Max(u) -->
```

La même chose en Python, R et MATLAB :

```python
import numpy as np, scipy.sparse as sp, scipy.sparse.linalg as sla
k = 50
t = sp.diags_array([-1.0, 2.0, -1.0], offsets=[-1, 0, 1], shape=(k, k))
a = (sp.kron(sp.eye_array(k), t) + sp.kron(t, sp.eye_array(k))).tocsc()
u = sla.spsolve(a, np.ones(k * k) / (k + 1.0) ** 2)
u.max()   # 0.07360100807413761
```

```r
library(Matrix)
k <- 50
t <- bandSparse(k, k, -1:1, list(rep(-1, k - 1), rep(2, k), rep(-1, k - 1)))
a <- kronecker(Diagonal(k), t) + kronecker(t, Diagonal(k))
u <- solve(a, rep(1, k * k) / (k + 1)^2)
max(u)   # 0.07360101
```

```matlab
k = 50;
t = spdiags(ones(k, 1) * [-1 2 -1], -1:1, k, k);
a = kron(speye(k), t) + kron(t, speye(k));
u = a \ (ones(k * k, 1) / (k + 1)^2);
max(u)   % 0.073601
```

`Solve` donne un `Ok` de `x`, ou un `Err` de sorte `"sparse"` quand `a` est singulière, quand une colonne de sa
factorisation n'a pas d'autre pivot que 0, ou quand `a` ou `b` contient un NaN ou un infini :

```cesia
sparse.Solve(sparse.Of([1, 2], [1, 1], [1.0, 1.0], 2, 2), [1.0, 1.0]) -->
```

### Comment marche Solve

`Solve` *factorise* `a` : il l'écrit comme un produit de matrices triangulaires, puis résout deux systèmes
triangulaires, chacun en un temps proportionnel aux non-zéros de son facteur. Le facteur d'une matrice sparse contient
plus de non-zéros que la matrice : éliminer une inconnue relie tous ses voisins entre eux, et ces nouveaux non-zéros
sont le *fill* (le remplissage). L'ordre d'élimination décide du fill. Sur la grille de 300 × 300 points, dans l'ordre
de la grille, le facteur contiendrait 27 millions de non-zéros ; dans l'ordre que choisit `Solve`, 2,9 millions.

- **L'ordre** : le *degré minimum*, qui élimine d'abord l'inconnue qui a le moins de voisins, sous la forme approchée
  d'Amestoy, Davis et Duff (1996), AMD : il borne chaque degré au lieu de le compter, fusionne les inconnues dont les
  voisins sont les mêmes, et met en dernier une inconnue reliée à presque toutes les autres. Sur la grille de 300 × 300,
  son ordre donne exactement le fill de l'AMD de SuiteSparse, dont se servent MATLAB et GNU Octave : 2 928 059
  non-zéros.
- **Symétrique et définie positive**, comme la matrice de la grille : la factorisation de Cholesky, `a = L L'` (Davis
  2006, ch. 4). Son *arbre d'élimination* (Liu 1990), où le parent d'une colonne est la première ligne sous sa diagonale
  qu'elle remplit, donne la forme de `L` avant tout calcul : le compte de chaque colonne, puis ses *supernodes* (ses
  super-nœuds), des suites de colonnes de `L` qui partagent leur forme sous la diagonale (Liu, Ng et Peyton 1993). Un
  supernode fusionne avec son parent quand cela stocke peu de zéros, ce qui fait des blocs moins nombreux et plus grands
  : les supernodes *relaxés* d'Ashcraft et Grimes (1989), avec les seuils de CHOLMOD (Chen, Davis, Hager et Rajamanickam
  2008). Chaque supernode est un bloc dense de `L`, et la méthode *multifrontale* (Duff et Reid 1983 ; Liu 1992) le
  calcule : pour chaque supernode, des feuilles de l'arbre vers le haut, une matrice dense, son *front*, rassemble les
  cellules de `a` du supernode et les mises à jour que ses enfants ont laissées ; ses colonnes sont factorisées, et la
  mise à jour des lignes en dessous, le *complément de Schur*, attend le parent. Presque tout le calcul devient alors
  des produits de blocs denses, que BLAS (la bibliothèque standard des produits de matrices denses) fait à la vitesse du
  code dense (Ng et Peyton 1993 comparent de telles méthodes par blocs sur des processeurs avec caches). La taille de
  chaque bloc est comptée avant qu'aucun ne soit alloué : au-delà de la limite de mémoire, `Solve` donne un `Err` qui
  dit quelle taille aurait le facteur. Cholesky n'a pas besoin de pivot, et est stable à rebours (son résultat est la
  solution exacte d'un problème à peine changé).
- **Toute autre matrice carrée** : LU avec pivot partiel, `p a q = L U`. Quand la forme de `a` est presque symétrique,
  la moitié de ses cellules en miroir ou plus, sans 0 sur sa diagonale, l'ordre est AMD sur la forme de `a + a'`, et LU
  suit les supernodes de cette forme, avec des fronts qui contiennent les deux triangles, comme le fait la stratégie
  symétrique d'UMFPACK (Davis 2004). À l'intérieur d'un front, le pivot d'une colonne est sa cellule diagonale quand
  celle-ci vaut au moins 0,1 fois la plus grande cellule de la colonne, ce qui garde le fill de l'ordre ; sinon la plus
  grande cellule des lignes que le front contient entières, quand elle passe le même test. Quand aucune ligne du front
  ne passe, ou quand la forme de `a` est loin d'être symétrique, LU est plutôt calculée colonne par colonne, chaque
  colonne une résolution triangulaire sparse dont une recherche en profondeur trouve d'abord la forme, pour que le
  travail soit celui du calcul (Gilbert et Peierls 1988 ; Davis 2006, ch. 6) : son pivot peut venir de n'importe quelle
  ligne. L'ordre est alors AMD sur la forme de `a + a'` pour une `a` presque symétrique, sinon sur celle de `a' a`, avec
  chaque pivot le plus grand de sa colonne.

Comme le fait l'antislash de MATLAB, `Solve` essaie Cholesky sur une matrice symétrique dont la diagonale est au-dessus
de 0 ; un pivot qui n'est pas au-dessus de 0 montre qu'elle n'est pas définie positive, et LU prend le relais. Ensuite,
quand le résidu `|a x - b|` est au-dessus de `n eps |a| |x|`, un pas de *raffinement itératif* résout pour le résidu et
corrige `x`.

### Vérifier une solution

L'*erreur inverse* (backward error) de `x`, `|a x - b| / (|a| |x| + |b|)`, dans la norme de la plus grande cellule, dit
de combien `a` et `b` devraient changer pour que `x` soit exact : environ `eps`, 2.2e-16, veut dire que `x` est aussi
bon que les floats le permettent. L'erreur de `x` lui-même peut être plus grande, du *conditionnement* de `a`, qui
mesure de combien la solution de `a` bouge quand `a` bouge :

```cesia
use std/math
x = result.Unwrap(sparse.Solve(a, matrix.Ones(1, k * k)))
r = sparse.Mul(a, x) - matrix.Ones(1, k * k)
norm = list.Max(list.Sum(math.Abs(sparse.Dense(a)), dim = 2))
list.Max(math.Abs(r)) / (norm * list.Max(math.Abs(x)) + 1.0) < 1e-15 -->
```

Les tests de Cesia vérifient `Solve` contre des formes closes : la matrice de Poisson 1-D, dont la solution pour `b = 1`
est `i (n + 1 - i) / 2`, et celle en 2-D, dont les vecteurs propres `sin(p π i h) sin(q π j h)` donnent `b / λ` ; contre
l'élimination dense sur des matrices au hasard définies positives et non symétriques, avec des pivots hors de la
diagonale ; et sur des entrées singulières, indéfinies et mauvaises. Sur huit matrices de la collection Harwell-Boeing
(nos4, bcsstk01, bcsstk14, 1138_bus, gr_30_30, west0479, orsirr_1, sherman1), son erreur inverse vaut au plus 0,02
`n eps`, comme celles de scipy et d'Octave.

### Les fichiers Matrix Market

[sparse.Read] lit un fichier au format Matrix Market du NIST (Boisvert, Pozo et Remington 1996), celui de la
SuiteSparse Matrix Collection (Davis et Hu 2011) : une première ligne
`%%MatrixMarket matrix coordinate FIELD SYMMETRY`, des lignes de commentaires qui commencent par `%`, la ligne
`rows cols entries`, puis une ligne `i j value` pour chaque entrée. Le champ vaut `real`, `integer` ou `pattern` (pas de
valeurs : chacune vaut 1.0) ; un fichier `symmetric` contient le triangle du bas, mis en miroir à la lecture, et un
fichier `skew-symmetric` la partie sous la diagonale, mise en miroir avec le signe opposé. `laplace.mtx` :

```text
%%MatrixMarket matrix coordinate real symmetric
% A 3 x 3 matrix of a 1-D Laplacian: its lower triangle, the upper one is its mirror.
3 3 5
1 1 2.0
2 1 -1.0
2 2 2.0
3 2 -1.0
3 3 2.0
```

```cesia allow=read
sparse.Read("laplace.mtx") then result.MapOk(sparse.Dense) -->
```

Il a besoin de la permission de lecture. Le `mmread` de scipy lit les mêmes fichiers ; MATLAB et Octave n'ont pas de
lecteur à eux.

### Une plaque dans une cell

Dans un fichier de [cells](cells.md), la chaleur sur la plaque, dessinée comme une carte de couleurs sous la cell dans
Cemacs :

```cesia norun
use std/matrix
use std/plot
use std/result
use std/sparse

(* %% Poisson on a square *)
k = 300
t = sparse.Diags([-1.0, 2.0, -1.0], [-1, 0, 1], k)
a = sparse.Add(sparse.Kron(sparse.Eye(k), t), sparse.Kron(t, sparse.Eye(k)))
u = result.Unwrap(sparse.Solve(a, matrix.Ones(1, k * k) / ((k + 1.0) ^ 2)))
plot.Heatmap(matrix.Reshape([k, k], u))
```

### La vitesse des matrices sparse

Sur la machine de [Vitesse](speed.md#à-côté-des-géants), le 2026-11-14 : les temps de Cesia sont la médiane de
21 lancements, avec l'intervalle à 95 % de cette médiane ; ceux de scipy 1.18.1 et de GNU Octave 11.3, la médiane de
5 lancements, et un lancement de chacun pour la grille de 1000 × 1000. Le produit a été mesuré le 2026-11-13.

| | Cesia | scipy | Octave |
|---|---:|---:|---:|
| produit `a x`, Poisson 2-D, 300 × 300 points, 448 800 non-zéros | **1,32 ms** (1,31 à 1,35) | 0,62 ms | 2,2 ms |
| `Solve`, Poisson 2-D, 300 × 300 points, premier appel du programme | **315 ms** (311 à 317) | 805 ms | 330 ms |
| `Solve`, Poisson 2-D, 300 × 300 points, les appels suivants | **266 ms** (265 à 269) | | |
| `Solve`, Poisson 2-D, 1000 × 1000 points | **3,85 s** (3,82 à 3,88) | 33,7 s | 8,1 s |
| `Solve`, convection-diffusion, 300 × 300 points, LU | **360 ms** (357 à 362) | 801 ms | 563 ms |

Le produit de Cesia prend 2,9 ns par non-zéro, comme l'explique [Vitesse](speed.md#ce-qui-devient-du-code-machine) ; la
boucle de scipy lit ses lignes comme des entiers de 32 bits et n'en vérifie aucune. Pour `Solve`, le `\` d'Octave
appelle CHOLMOD, supernodal lui aussi, ses blocs factorisés par LAPACK et BLAS, et UMFPACK pour LU ; le `spsolve` de
scipy appelle SuperLU, qui factorise même une matrice symétrique comme une non symétrique. Avant les supernodes, la
factorisation de Cesia avançait une colonne à la fois et attendait la mémoire : 679 ms sur la grille de 300 × 300, 24,1
s sur celle de 1000 × 1000, 2,0 s pour la LU. Là où les géants gagnent encore : sur la grille de 300 × 300 points,
l'ordre par AMD prend maintenant environ un quart de `Solve`, 70 ms, là où celui de SuiteSparse prend 45 ms. Sur les
huit matrices Harwell-Boeing des tests, `Solve` prend de 0,33 ms (bcsstk01) à 15 ms (bcsstk14) : plus vite que scipy sur
bcsstk14 (43 ms) et orsirr_1 (4,4 ms contre 5,4), plus lentement sur les six autres, jusqu'à 3,2 fois (west0479, 0,68
ms) ; Octave est plus rapide sur chacune sauf orsirr_1, de 1,4 à 7 fois, surtout sur les plus petites, où les étapes de
`Solve` autour de la factorisation (la transposée, la vérification de la symétrie, le résidu) coûtent plus que la
factorisation. Un facteur qui reste très mince, comme celui du réseau électrique 1138_bus, paie ses fronts : chacun
passe à son parent une mise à jour aussi grande que lui, et `Solve` y prend 1,82 ms, contre 1,52 ms une colonne à la
fois avant.

BLAS fait les produits des fronts sur un seul thread (un fil d'exécution du système), et sur deux à partir de 2^27
multiplications-additions : l'OpenBLAS de la machine, construit avec OpenMP, prend ses 8 threads de lui-même, et sur une
machine occupée par d'autres programmes ils rendaient les produits moyens des fronts de 5 à 30 fois plus lents qu'un
seul thread. Sans BLAS, `Solve` fait les mêmes produits en OCaml, plusieurs fois plus lentement sur les grands fronts,
et donne les mêmes bits sur chaque machine ; avec, les derniers bits d'une grande factorisation peuvent changer d'une
bibliothèque à l'autre, comme ceux de `num.Solve`.

`use std/sparse` n'ajoute rien de mesurable au démarrage d'un programme, une fois son code dans le cache des packages
chargés.

### La sécurité des matrices sparse

Les arrays d'une `Matrix` sont privés : seul std/sparse les fait, à travers `Of`, qui vérifie chaque indice, chaque
valeur et les longueurs, et refuse une taille au-delà de 2^53 cellules. Une `Matrix` construite à la main, avec ses
champs remplis d'une autre façon, reçoit une panic à la première lecture qui ne tient pas, jamais une lecture hors d'un
array : le code natif de l'ordre et de LU vérifie chaque array qu'on lui donne avant de le lire, et chaque array de
Cesia vérifie ses indices.

Un fichier Matrix Market est une entrée non fiable. `Read` vérifie chaque ligne à son arrivée : les tailles, sans
dépassement ; chaque indice, de 1 à la taille ; chaque valeur, un nombre fini ; le triangle d'un fichier symétrique. Il
compte les entrées par rapport au nombre de la troisième taille, et ses arrays grandissent avec les entrées lues, jamais
avec ce que le fichier dit contenir. Une ligne d'entrées de plus de 1 024 octets, plus de 2^31 - 1 lignes ou colonnes,
ou tout ce qu'il ne connaît pas est un `Err` qui nomme le fichier et la ligne. Les tests lisent 20 000 fichiers faits en
changeant, en enlevant, en ajoutant et en répétant des octets d'un fichier valide : chacun a donné un `Ok` ou un `Err`,
jamais une panic.

Le travail est borné et compté : `Of`, `Kron` et `Add` prennent un temps et une mémoire proportionnels à leurs
non-zéros. Le facteur par supernodes, ses blocs, son plus grand front et les mises à jour qui attendent en chemin sont
comptés à partir de la forme avant que quoi que ce soit soit alloué, sans produit qui puisse déborder (chacun vaut au
plus `n²`, lui-même au plus 2^53) : quand cela seul dépasse `--limit memory`, `Solve` donne un `Err` qui dit combien de
mégaoctets il prendrait, comme `sparse.Solve: the factor of a would take 48 MB, more than the memory limit allows.` ; la
LU de Gilbert et Peierls grandit en doublant. Le code natif compte son travail dans `--limit` à mesure qu'il avance, un
bloc à la fois, si bien que [cells.Stop] et une limite de pas arrêtent une longue factorisation en une fraction de
seconde, et la mémoire qu'il prend est réservée d'abord : au-delà de la limite de mémoire, le programme s'arrête avec
`Limit "memory" reached.` avant d'allouer. Chaque bloc dense passé à BLAS est vérifié comme étant dans son array, avec
des tailles qui tiennent dans les entiers de 32 bits de BLAS, avant l'appel. `Dense` prend 8 octets par cellule, et
s'arrête de la même façon au-delà de la limite.

### Pour aller plus loin sur les matrices sparse

- Timothy A. Davis. *Direct Methods for Sparse Linear Systems*. SIAM, 2006. <https://doi.org/10.1137/1.9780898718881>.
  Les colonnes compressées, l'arbre d'élimination, la factorisation de Cholesky up-looking (qui calcule
  une ligne à partir de celles du dessus, ch. 4), la LU
  left-looking (qui calcule une colonne à partir de celles de gauche, ch. 6), les ordres (ch. 7).
- Patrick R. Amestoy, Timothy A. Davis, Iain S. Duff. "An Approximate Minimum Degree Ordering Algorithm". *SIAM Journal
  on Matrix Analysis and Applications* 17(4):886–905, 1996. <https://doi.org/10.1137/S0895479894278952>. AMD.
- John R. Gilbert, Tim Peierls. "Sparse Partial Pivoting in Time Proportional to Arithmetic Operations". *SIAM Journal
  on Scientific and Statistical Computing* 9(5):862–874, 1988. <https://doi.org/10.1137/0909058>. LU.
- Joseph W. H. Liu. "The Role of Elimination Trees in Sparse Factorization". *SIAM Journal on Matrix Analysis and
  Applications* 11(1):134–172, 1990. <https://doi.org/10.1137/0611010>.
- Iain S. Duff, John K. Reid. "The Multifrontal Solution of Indefinite Sparse Symmetric Linear Equations". *ACM
  Transactions on Mathematical Software* 9(3):302–325, 1983. <https://doi.org/10.1145/356044.356047>. Les fronts.
- Joseph W. H. Liu. "The Multifrontal Method for Sparse Matrix Solution: Theory and Practice". *SIAM Review*
  34(1):82–109, 1992. <https://doi.org/10.1137/1034004>.
- Joseph W. H. Liu, Esmond G. Ng, Barry W. Peyton. "On Finding Supernodes for Sparse Matrix Computations". *SIAM
  Journal on Matrix Analysis and Applications* 14(1):242–252, 1993. <https://doi.org/10.1137/0614019>.
- Cleve Ashcraft, Roger Grimes. "The Influence of Relaxed Supernode Partitions on the Multifrontal Method". *ACM
  Transactions on Mathematical Software* 15(4):291–309, 1989. <https://doi.org/10.1145/76909.76910>.
- Esmond G. Ng, Barry W. Peyton. "Block Sparse Cholesky Algorithms on Advanced Uniprocessor Computers". *SIAM Journal
  on Scientific Computing* 14(5):1034–1056, 1993. <https://doi.org/10.1137/0914063>.
- Fred G. Gustavson. "Recursion Leads to Automatic Variable Blocking for Dense Linear-Algebra Algorithms". *IBM Journal
  of Research and Development* 41(6):737–755, 1997. <https://doi.org/10.1147/rd.416.0737>. La factorisation dense
  d'un front, par moitiés de ses colonnes.
- Yanqing Chen, Timothy A. Davis, William W. Hager, Sivasankaran Rajamanickam. "Algorithm 887: CHOLMOD, Supernodal
  Sparse Cholesky Factorization and Update/Downdate". *ACM Transactions on Mathematical Software* 35(3):22, 2008.
  <https://doi.org/10.1145/1391989.1391995>.
- Timothy A. Davis. "A Column Pre-ordering Strategy for the Unsymmetric-pattern Multifrontal Method". *ACM Transactions
  on Mathematical Software* 30(2):165–195, 2004. <https://doi.org/10.1145/992200.992205>. UMFPACK.
- Ronald F. Boisvert, Roldan Pozo, Karin A. Remington. *The Matrix Market Exchange Formats: Initial Design*. NIST,
  1996. <https://math.nist.gov/MatrixMarket/formats.html>.
- Timothy A. Davis, Yifan Hu. "The University of Florida Sparse Matrix Collection". *ACM Transactions on Mathematical
  Software* 38(1):1–25, 2011. <https://doi.org/10.1145/2049662.2049663>. Aujourd'hui la SuiteSparse Matrix Collection.

## Sécurité

`f`, `g` et les fonctions données à Root sont du code de l'appelant, donc les méthodes vérifient ce qu'elles donnent :
une valeur de la mauvaise forme, un texte, un NaN ou un infini est un `Err` qui la nomme, jamais un plantage à
l'intérieur du solver. Chaque boucle est bornée : Root par ses 60 pas de recherche et par l'encadrement, qui se coupe en
deux au moins tous les quelques pas ; Solve par `steps`. Chaque boucle est du code Cesia, si bien que [cells.Stop]
arrête une longue résolution en un pas, et `--limit` s'applique, comme à tout programme. La mémoire d'une résolution
grandit avec ses pas, par blocs de 128 pas ; au-delà de la limite de mémoire du programme, le programme s'arrête avec
`Limit "memory" reached.`

Avec `stiff = true`, `jacobian` est aussi du code de l'appelant : ce qu'il donne doit être une matrice `n × n` de
nombres finis, et un jacobien par différences est vérifié de la même façon, si bien qu'un NaN n'atteint jamais la
factorisation. `y0` a au plus 1 000 composantes, si bien que ses trois matrices `n × n` restent sous 24 MB ; un plus
grand est une panic qui le dit, avant que quoi que ce soit soit alloué. L'élimination de [num.Lu] tourne en code natif,
qui compte son travail, environ $n^3 / 3$ opérations, dans `--limit` avant de commencer, et ne lit que des matrices de
nombres dont elle vérifie d'abord la forme ; une factorisation à $n = 1000$ prend moins d'une seconde, si bien que
`cells.Stop` répond encore en un pas.

Minimize et Simplex vérifient de la même façon ce que donnent `f` et `gradient` : un texte, ou un array de la mauvaise
forme, est un `Err` qui le nomme ; un NaN ou un infini est un `Err` au départ, et après lui un point d'où reculer, ou le
pire de tous. Une panic à l'intérieur de `f` est un bug de l'appelant et passe au travers, comme de n'importe quel
appel, en nommant sa ligne. Chaque boucle est bornée : Minimize par `steps`, 10 000 par défaut, avec au plus 20
évaluations de `f` dans une line search et `2n` appels de `f` dans un gradient par différences ; Simplex par `steps`,
avec au plus `n + 2` appels de `f` par pas. Chacun tourne en code Cesia sauf les trois natives de std/optimize, les deux
boucles de la direction, un produit scalaire et la plus grande composante d'un array, qui ne lisent que des arrays de
floats dont ils vérifient d'abord la sorte et la longueur, et comptent leur travail, au plus `4 · 10 · n` opérations,
dans `--limit` : si bien que [cells.Stop] arrête une longue minimisation en un pas, et que `--limit steps` arrête une
`f` qui ne finit jamais. Minimize garde 20 arrays aussi grands que `x`, ses pas et les changements de son gradient, et
quelques autres ; au-delà de la limite de mémoire du programme, le programme s'arrête avec `Limit "memory" reached.`
Aucun des deux ne tire de nombre au hasard : le même appel donne la même réponse.

## Pour aller plus loin

- Richard P. Brent. *Algorithms for Minimization without Derivatives*. Prentice-Hall, 1973; Dover, 2002. Chapitre 4 :
  le zéro d'une fonction. La page de l'auteur : <https://maths-people.anu.edu.au/~brent/pub/pub011.html>.
- Richard P. Brent. "An algorithm with guaranteed convergence for finding a zero of a function". *The Computer Journal*
  14(4):422–425, 1971. <https://doi.org/10.1093/comjnl/14.4.422>.
- G. E. Alefeld, F. A. Potra, Yixun Shi. "Algorithm 748: Enclosing Zeros of Continuous Functions". *ACM Transactions on
  Mathematical Software* 21(3):327–344, 1995. <https://doi.org/10.1145/210089.210111>. Leurs problèmes de test.
- Dong C. Liu, Jorge Nocedal. "On the limited memory BFGS method for large scale optimization". *Mathematical
  Programming* 45:503–528, 1989. <https://doi.org/10.1007/BF01589116>. L-BFGS, sa mise à l'échelle M3, et la preuve de
  sa convergence sur les fonctions uniformément convexes.
- Jorge Nocedal. "Updating quasi-Newton matrices with limited storage". *Mathematics of Computation* 35(151):773–782,
  1980. <https://doi.org/10.1090/S0025-5718-1980-0572855-7>. Les deux boucles.
- Jorge J. Moré, David J. Thuente. "Line search algorithms with guaranteed sufficient decrease". *ACM Transactions on
  Mathematical Software* 20(3):286–307, 1994. <https://doi.org/10.1145/192115.192132>. La line search.
- Jorge Nocedal, Stephen J. Wright. *Numerical Optimization*, deuxième édition. Springer, 2006.
  <https://doi.org/10.1007/978-0-387-40065-5>. Chapitre 7 : L-BFGS ; §8.1 : le pas d'une différence centrée.
- J. A. Nelder, R. Mead. "A simplex method for function minimization". *The Computer Journal* 7(4):308–313, 1965.
  <https://doi.org/10.1093/comjnl/7.4.308>.
- Fuchang Gao, Lixing Han. "Implementing the Nelder-Mead simplex algorithm with adaptive parameters". *Computational
  Optimization and Applications* 51(1):259–277, 2012. <https://doi.org/10.1007/s10589-010-9329-3>. Les coefficients.
- Jeffrey C. Lagarias, James A. Reeds, Margaret H. Wright, Paul E. Wright. "Convergence properties of the Nelder–Mead
  simplex method in low dimensions". *SIAM Journal on Optimization* 9(1):112–147, 1998.
  <https://doi.org/10.1137/S1052623496303470>. Ce qui est prouvé, et les règles pour les valeurs égales.
- K. I. M. McKinnon. "Convergence of the Nelder–Mead simplex method to a nonstationary point". *SIAM Journal on
  Optimization* 9(1):148–158, 1998. <https://doi.org/10.1137/S1052623496303482>.
- Jorge J. Moré, Burton S. Garbow, Kenneth E. Hillstrom. "Testing unconstrained optimization software". *ACM
  Transactions on Mathematical Software* 7(1):17–41, 1981. <https://doi.org/10.1145/355934.355936>. Les 35 problèmes des
  tests.
- J. R. Dormand, P. J. Prince. "A family of embedded Runge-Kutta formulae". *Journal of Computational and Applied
  Mathematics* 6(1):19–26, 1980. <https://doi.org/10.1016/0771-050X(80)90013-3>. La méthode, RK5(4)7M.
- Lawrence F. Shampine. "Some practical Runge-Kutta formulas". *Mathematics of Computation* 46(173):135–150, 1986.
  <https://doi.org/10.1090/S0025-5718-1986-0815836-3>. La sortie dense.
- Ernst Hairer, Syvert P. Nørsett, Gerhard Wanner. *Solving Ordinary Differential Equations I: Nonstiff Problems*,
  deuxième édition. Springer, 1993. <https://doi.org/10.1007/978-3-540-78862-1>. Le test de l'erreur, le premier pas, la
  sortie dense de DOPRI5, l'orbite d'Arenstorf.
- Ernst Hairer, Gerhard Wanner. *Solving Ordinary Differential Equations II: Stiff and Differential-Algebraic
  Problems*, deuxième édition. Springer, 1996. <https://doi.org/10.1007/978-3-642-05221-7>. Le contrôle PI de DOPRI5 et
  son test de raideur.
- Kjell Gustafsson. "Control theoretic techniques for stepsize selection in explicit Runge-Kutta methods". *ACM
  Transactions on Mathematical Software* 17(4):533–554, 1991. <https://doi.org/10.1145/210232.210242>.
- Gustaf Söderlind. "Digital filters in adaptive time-stepping". *ACM Transactions on Mathematical Software*
  29(1):1–26, 2003. <https://doi.org/10.1145/641876.641877>.
- I. Gladwell, L. F. Shampine, R. W. Brankin. "Automatic selection of the initial step size for an ODE solver". *Journal
  of Computational and Applied Mathematics* 18(2):175–192, 1987. <https://doi.org/10.1016/0377-0427(87)90015-X>.
- L. F. Shampine. "Stiffness and Nonstiff Differential Equation Solvers, II: Detecting Stiffness with Runge-Kutta
  Methods". *ACM Transactions on Mathematical Software* 3(1):44–53, 1977. <https://doi.org/10.1145/355719.355722>.
- L. F. Shampine, S. Thompson. "Event location for ordinary differential equations". *Computers & Mathematics with
  Applications* 39(5–6):43–54, 2000. <https://doi.org/10.1016/S0898-1221(00)00045-6>.
- Gerd Steinebach. "Construction of Rosenbrock–Wanner method Rodas5P and numerical benchmarks within the Julia
  Differential Equations package". *BIT Numerical Mathematics* 63:27, 2023.
  <https://doi.org/10.1007/s10543-023-00967-x>. Rodas5P, sa sortie dense, et l'endroit où ses nombres et ceux de Rodas4
  sont publiés. En accès libre.
- Ernst Hairer, Gerhard Wanner, comme ci-dessus, §IV.7 : les méthodes de Rosenbrock, leurs conditions d'ordre et la
  méthode Rodas4 ; §IV.10 : les problèmes de test stiff, celui de Robertson, HIRES et OREGO.
- Kjell Gustafsson. "Control-theoretic techniques for stepsize selection in implicit Runge-Kutta methods". *ACM
  Transactions on Mathematical Software* 20(4):496–517, 1994. <https://doi.org/10.1145/198429.198437>. Le contrôle
  prédictif du pas.
- J. E. Dennis Jr., Robert B. Schnabel. *Numerical Methods for Unconstrained Optimization and Nonlinear Equations*.
  SIAM, 1996 (publié d'abord chez Prentice-Hall, 1983). <https://doi.org/10.1137/1.9781611971200>. Le pas d'une
  différence avant.
- A. Prothero, A. Robinson. "On the stability and accuracy of one-step methods for solving stiff systems of ordinary
  differential equations". *Mathematics of Computation* 28(125):145–162, 1974.
  <https://doi.org/10.1090/S0025-5718-1974-0331793-2>. Leur problème de test.


## La suite

Vous savez trouver des zéros et des minima, résoudre des équations différentielles, calculer des intégrales et résoudre
des systèmes sparse. Le chapitre suivant, [Statistiques](statistics.md), travaille avec les lois de probabilité.
