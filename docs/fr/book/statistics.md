# Statistiques

Dans ce chapitre, vous travaillez avec les lois de probabilité, grâce à [std/stats] : la loi normale, celle de Student,
celle du khi-deux, celle de Fisher, la loi uniforme, l'exponentielle, la loi gamma, la loi bêta, la binomiale et celle
de Poisson, chacune une valeur avec sa densité, sa fonction de répartition, ses quantiles et ses tirages au hasard, ce
que donnent `pnorm` et `qt` dans R et `norm` et `t` dans scipy, et la moyenne de tirages au hasard avec son intervalle,
une estimation de Monte-Carlo. En dessous se trouvent les fonctions spéciales de [std/special] : les fonctions gamma et
bêta, la fonction d'erreur, et les rapports gamma et bêta incomplets. Chacune vient d'une méthode publiée, nommée ici
avec ce qu'elle promet, et la dernière partie de chaque section dit à quel point elle s'en approche, mesurée contre des
valeurs calculées à 70 chiffres et contre R et scipy.

## Les lois de probabilité

Une loi est une valeur. `stats.Normal(100, 15)` est la loi normale de moyenne 100 et d'écart type 15, et ses méthodes
répondent aux questions d'un cours ou d'un article : la probabilité d'une valeur sous 130, d'une valeur au-dessus, la
valeur sous laquelle tombent 95 % d'entre elles, la densité en trois points.

```cesia
use std/stats
d = stats.Normal(100, 15)
d.Cdf(130) -->
d.Cdf(130, upper = true) -->
d.Quantile(0.95) -->
d.Pdf([85, 100, 115]) -->
```

Chaque loi a les quatre mêmes méthodes :

| Cesia | Ce qu'elle donne | R | Python, `scipy.stats` | MATLAB |
|---|---|---|---|---|
| `d.Pdf(x)` | la densité en `x`, ou pour une loi de comptes la probabilité de `x` | `dnorm(x, 100, 15)` | `d.pdf(x)`, `d.pmf(x)` | `normpdf(x, 100, 15)` |
| `d.Cdf(x)` | $P(X \le x)$ | `pnorm(x, 100, 15)` | `d.cdf(x)` | `normcdf(x, 100, 15)` |
| `d.Cdf(x, upper = true)` | $P(X > x)$, calculée directement | `pnorm(x, 100, 15, lower.tail = FALSE)` | `d.sf(x)` | `normcdf(x, 100, 15, 'upper')` |
| `d.Quantile(p)` | le `x` où $P(X \le x) = p$ | `qnorm(p, 100, 15)` | `d.ppf(p)` | `norminv(p, 100, 15)` |
| `d.Quantile(p, upper = true)` | le `x` où $P(X > x) = p$ | `qnorm(p, 100, 15, lower.tail = FALSE)` | `d.isf(p)` | `norminv(1 - p, 100, 15)` |
| `d.Sample()`, `d.Sample(n)` | un tirage, ou un array de `n` | `rnorm(1, 100, 15)`, `rnorm(n, 100, 15)` | `d.rvs()`, `d.rvs(n)` | `normrnd(100, 15, 1, n)` |

`Pdf` est la densité (*probability density function*), `Cdf` la fonction de répartition (*cumulative distribution
function*), la probabilité d'une valeur inférieure ou égale à `x`. `x` et `p` sont un nombre ou un array (une suite ou
une matrice de nombres) de n'importe quelle forme, et la réponse a cette forme. Les lois, et leurs champs :

| Cesia | Ses champs | R | scipy.stats | MATLAB |
|---|---|---|---|---|
| `stats.Normal(Mean, Sd)` | `Sd > 0` | `norm(mean, sd)` | `norm(loc, scale)` | `norm…(mu, sigma)` |
| `stats.StudentT(Df)` | `Df > 0`, infini pour la loi normale | `t(df)` | `t(df)` | `t…(nu)` |
| `stats.ChiSquared(Df)` | `Df > 0` | `chisq(df)` | `chi2(df)` | `chi2…(nu)` |
| `stats.FisherF(Df1, Df2)` | les deux `> 0` | `f(df1, df2)` | `f(dfn, dfd)` | `f…(v1, v2)` |
| `stats.Uniform(Low, High)` | `Low < High` | `unif(min, max)` | `uniform(loc = Low, scale = High - Low)` | `unif…(a, b)` |
| `stats.Exponential(Rate)` | `Rate > 0` | `exp(rate)` | `expon(scale = 1 / Rate)` | `exp…(1 / Rate)`, une moyenne |
| `stats.Gamma(Shape, Rate)` | les deux `> 0` | `gamma(shape, rate)` | `gamma(a, scale = 1 / Rate)` | `gam…(a, 1 / Rate)` |
| `stats.Beta(A, B)` | les deux `> 0` | `beta(shape1, shape2)` | `beta(a, b)` | `beta…(a, b)` |
| `stats.Binomial(N, P)` | `N` un nombre entier de 0 ou plus, `P` dans `[0, 1]` | `binom(size, prob)` | `binom(n, p)` | `bino…(n, p)` |
| `stats.Poisson(Lambda)` | `Lambda >= 0` | `pois(lambda)` | `poisson(mu)` | `poiss…(lambda)` |

Dans la colonne MATLAB, `…` vaut `pdf`, `cdf`, `inv` ou `rnd` : `tcdf(x, nu)`, `chi2inv(p, nu)`. MATLAB et scipy
prennent l'échelle des lois exponentielle et gamma, le temps moyen entre deux événements, là où R et Cesia prennent le
taux : l'`Exponential(2)` de Cesia est l'`exp…(0.5)` de MATLAB.

Une loi est une struct (une valeur dont les champs sont déclarés une fois), donc `d.Mean` lit un champ et une loi se
passe à une fonction comme n'importe quelle valeur. Elle est faite sans vérification ; son premier appel de méthode
vérifie ses champs, et un champ hors de son domaine est un bug de l'appelant, une panic (un arrêt du programme) qui
nomme la loi, le champ et la valeur :

```cesia fails
stats.Normal(0, -1).Cdf(0)
```

### Les deux queues

Une queue est la probabilité au-delà d'un point. `upper = true` calcule directement la queue du haut. `1 - d.Cdf(x)` le
ferait en principe, mais quand la Cdf est proche de 1, la soustraction ne garde aucun des chiffres de la réponse :

```cesia
1.0 - stats.Normal(0, 1).Cdf(9) -->
stats.Normal(0, 1).Cdf(9, upper = true) -->
```

Une p-value de $10^{-40}$, la probabilité d'un résultat au moins aussi éloigné quand seul le hasard est à l'œuvre, garde
ses chiffres de cette façon, tout comme un quantile à `upper = true` pour un petit `p`.

### Les quantiles

Un quantile est l'inverse de la Cdf : `d.Quantile(0.975)` est le `x` sous lequel tombent 97,5 % de la loi. Les deux
valeurs critiques d'un cours, le quantile de Student d'un intervalle à 95 % avec 9 degrés de liberté et le quantile du
khi-deux d'un test à 5 % avec 4 :

```cesia
stats.StudentT(9).Quantile(0.975) -->
stats.ChiSquared(4).Quantile(0.05, upper = true) -->
```

Pour une loi de comptes, la binomiale et celle de Poisson, le quantile est le plus petit entier `k` tel que
$P(X \le k) \ge p$, ou $P(X > k) \le p$ avec `upper`, comme dans R : `p` se déplace d'abord de $64 \epsilon$ vers la
réponse, pour que l'arrondi d'une Cdf qui vaut exactement `p` ne pousse pas la réponse un cran trop loin.

```cesia
b = stats.Binomial(20, 0.3)
b.Cdf(5) -->
b.Quantile(0.5) -->
stats.Poisson(4).Pdf([0, 1, 2]) -->
```

Hors du support, là où la loi n'a pas de masse, `Pdf` vaut 0 et `Cdf` 0 ou 1 ; la `Pdf` d'une loi de comptes vaut 0 en
un nombre qui n'est pas entier. Un `p` hors de `[0, 1]` donne NaN, comme le fait `math.Log(-1.0)`, et un NaN donné est
un NaN rendu.

### La même chose en Python, R et MATLAB

```python
from scipy import stats
d = stats.norm(100, 15)
d.cdf(130), d.sf(130), d.ppf(0.95), d.pdf([85, 100, 115])
stats.t(9).ppf(0.975), stats.chi2(4).isf(0.05), stats.binom(20, 0.3).cdf(5), stats.poisson(4).pmf([0, 1, 2])
```

```r
pnorm(130, 100, 15); pnorm(130, 100, 15, lower.tail = FALSE); qnorm(0.95, 100, 15); dnorm(c(85, 100, 115), 100, 15)
qt(0.975, 9); qchisq(0.05, 4, lower.tail = FALSE); pbinom(5, 20, 0.3); dpois(0:2, 4)
```

```matlab
normcdf(130, 100, 15), normcdf(130, 100, 15, 'upper'), norminv(0.95, 100, 15), normpdf([85 100 115], 100, 15)
tinv(0.975, 9), chi2inv(0.95, 4), binocdf(5, 20, 0.3), poisspdf(0:2, 4)
```

### Ce que promet chaque méthode

- **Cdf.** Celle de la loi normale vient des approximations de Cody pour `erf` et `erfc`, comme `special.Erf`, avec
  $e^{-z^2/2}$ pris à partir de $z$ lui-même : diviser d'abord $z$ par $\sqrt 2$, comme le fait `erfc(-z / sqrt 2) / 2`,
  coûterait $z^2 \epsilon$ dans les queues lointaines. Les autres sont les rapports incomplets de std/special :
  $P(T > |t|) = I_x(\nu/2, 1/2)/2$, $x = \nu / (\nu + t^2)$, pour Student ; $P(\nu / 2, x / 2)$ pour le khi-deux ;
  $I_u(d_1/2, d_2/2)$, $u = d_1 x / (d_1 x + d_2)$, pour la loi F ; $1 - I_p(k + 1, n - k)$ pour la binomiale ;
  $Q(k + 1, \lambda)$ pour celle de Poisson. De $x$ et $1 - x$, celui qu'on donne au rapport est celui qui garde ses
  chiffres, calculé directement à partir des arguments, jamais comme 1 moins l'autre.
- **Quantile.** Celui de la loi normale est le PPND16 de Wichura, comme `special.ErfInv`. Les lois gamma et du khi-deux,
  bêta et F, et celle de Student à travers la loi bêta de sa queue, $t^2 = \nu (1 - x) / x$, sont résolues : un pas de
  Newton sur la queue, en logarithmes tant que la queue est loin de sa cible et avec la correction de Halley près
  d'elle, à l'intérieur d'un encadrement que chaque pas resserre, avec une bissection quand un pas en sort, au plus
  100 pas ; la variable résolue est celle du petit côté, $x$ ou $1 - x$, pour que la réponse garde ses chiffres dans les
  deux queues. Le départ est l'approximation de Wilson–Hilferty pour la loi gamma, une estimation normale pour la loi
  bêta, et le premier terme de la série de chaque queue là où elle est petite. Pour $\nu = 1$ et $\nu = 2$, le quantile
  de Student a ses formes closes. Là où la réponse passe sous le plus petit float (un underflow), le premier terme de la
  série est la réponse.
- **Pdf.** Les densités dont les paramètres sont grands, une binomiale de $10^6$ essais, une loi gamma de forme 1 000,
  sont calculées à travers $\lambda = x / a$ et la série de Stirling,
  $\sqrt{a / 2\pi}\, e^{a(\log\lambda - \lambda + 1)} / \Gamma^{\text{*}}(a)$, pour que deux grands logarithmes ne
  s'annulent jamais : les facteurs des rapports incomplets de std/special.

### À côté de R

Sur 300 points au hasard pour chaque loi, ses paramètres répartis de $e^{-3}$ à $e^{8}$, `x` autour du gros de la loi et
jusque dans les queues, et `p` de $10^{-200}$ à 1, les réponses de Cesia sont à moins de 2 $\epsilon$ de celles de R
4.6.2 en médiane, pour chaque méthode de chaque loi. Là où elles diffèrent davantage, les valeurs à 70 chiffres ont été
calculées, et c'est Cesia qui était la plus proche, de loin :

| R 4.6.2 | Cesia | La valeur exacte |
|---|---|---|
| `pbeta(0.14303666358300993, 380.44661739092425, 34.46702297684653)` : 6.27888829438920e-275 | 6.27625470304679e-275 | 6.27625470304513e-275 |
| `qgamma(1.16e-14, 0.1966, lower.tail = FALSE)` à $1{,}2 \times 10^{-10}$ près dans sa queue | à $8 \times 10^{-16}$ près | |
| `qchisq(5.13e-14, 2668.04, lower.tail = FALSE)` à $2{,}3 \times 10^{-8}$ près | à $2{,}3 \times 10^{-14}$ près | |
| `qf(0.996, 0.5516, 1.8333, lower.tail = FALSE)` à $1{,}8 \times 10^{-11}$ près | à $10^{-18}$ près | |
| `dpois(19102, 18785.69)` à $1{,}7 \times 10^{-12}$ près | à $10^{-16}$ près | |
| `qt(8.93e-71, 0.434)` : $-\infty$ pour la queue du haut | $1{,}8195 \times 10^{160}$ | |

Les queues sont données par l'erreur relative de la queue en la réponse, $|F(x) - p| / p$, la mesure d'un quantile. R a
raison sur tous les autres, et il est plus proche que Cesia sur quelques-uns : là où un paramètre est sous environ
$10^{-2}$, `pbeta` garde tous ses chiffres là où le `BetaInc` de Cesia en perd jusqu'à quelques centaines d'$\epsilon$.

### Les tirages au hasard

`d.Sample()` tire un nombre d'une loi, `d.Sample(n)` un array de `n`, à partir de l'unique générateur de [std/random],
pour que `cesia run --seed N` redonne les mêmes nombres à partir du seed N (le nombre dont part le générateur), et que
chaque test de `cesia test` ait les siens. Dans un fichier de [cells](cells.md) (les morceaux d'un notebook), le
générateur repart avant chaque cell, du seed de la session et du titre de la cell, comme `cesia test` le fait pour
chaque test : une cell qui tourne de nouveau tire les mêmes nombres, quoi qu'il ait tourné avant elle, et modifier une
cell ne change les tirages d'aucune autre.

```cesia
use std/value
xs = stats.Normal(0, 1).Sample(1000)
value.Size(xs) -->
stats.Poisson(4).Sample(5) then value.Len() -->
```

| Loi | Comment un tirage est fait |
|---|---|
| Normal | Box et Muller (1958), le cosinus de deux uniformes : `stats.Normal(0, 1).Sample(n)` est `num.Normal(n)` |
| Uniform | `Low + (High - Low) u`, `u` venant de `random.Float`, de 53 bits |
| Exponential | l'inversion, $-\log(1 - u) / \text{Rate}$, pour que $1 - u$ soit dans $(0, 1]$ |
| Gamma | le squeeze (la méthode de rejet à compression) de Marsaglia et Tsang (2000) à partir d'une normale et d'une uniforme ; pour une forme sous 1, $G(a + 1) U^{1/a}$, du même article |
| ChiSquared | deux fois un tirage gamma de forme `Df / 2` |
| Beta | $G_a / (G_a + G_b)$, deux tirages gamma |
| StudentT | $Z / \sqrt{X / \nu}$, un tirage normal puis un du khi-deux |
| FisherF | $(X_1 / d_1) / (X_2 / d_2)$, deux tirages du khi-deux |
| Binomial, Poisson | l'inversion : le plus petit `k` dont la probabilité cumulée dépasse `u`, dans une table de la loi de 40 écarts types sous la moyenne à 40 au-dessus, qui en contient tout sauf moins de $10^{-300}$ ; un tirage seul, ou une loi dont la table dépasserait 65 536 comptes, par `Quantile(u)`, la même inversion sans la table |

Chaque méthode est exacte en loi, si les uniformes sont exactes. Les algorithmes sont figés avec les seeds : un seed
donne les mêmes nombres dans chaque version, donc une meilleure méthode viendrait plus tard sous un nouveau nom, jamais
comme un changement. Les dix premiers tirages de chaque loi pour le seed 42 sont fixés par les tests de Cesia, et 2 000
tirages de chacune passent un test de Kolmogorov–Smirnov ou du khi-deux contre la propre Cdf de la loi. R et numpy ont
d'autres générateurs, si bien que le même seed y donne d'autres nombres : comparez leurs statistiques, pas leurs
tirages.

## Le modèle linéaire

[stats.Lm] ajuste une droite, ou un plan, à des points par les moindres carrés : le `lm` de R, sans formule. La colonne
à expliquer vient d'abord, puis les colonnes qui l'expliquent, puis le frame (la table de colonnes de std/frame) :

```cesia
use std/frame
use std/result
cars = frame.Of({"mpg": [21.0, 22.8, 21.4, 18.7, 18.1, 14.3, 24.4, 22.8, 19.2, 17.8],
                 "wt": [2.62, 2.32, 3.215, 3.44, 3.46, 3.57, 3.19, 3.15, 3.44, 3.44],
                 "hp": [110, 93, 110, 175, 105, 245, 62, 95, 123, 123]})
fit = result.Unwrap(stats.Lm("mpg", ["wt", "hp"], cars))
fit.Coefficients -->
fit.Sigma -->
fit.RSquared -->
fit.F.PValue -->
```

`fit.Coefficients` est le `coef(summary(fit))` de R sous forme de frame : une ligne pour chaque terme, son estimation,
son erreur standard, sa valeur t et la p-value de ce t. Les autres champs du `Model` :

| Cesia | R | Python, statsmodels |
|---|---|---|
| `stats.Lm("mpg", ["wt", "hp"], cars)` | `lm(mpg ~ wt + hp, data = cars)` | `smf.ols("mpg ~ wt + hp", cars).fit()` |
| `stats.Lm("y", ["x"], df, intercept = false)` | `lm(y ~ x - 1)` | `smf.ols("y ~ x - 1", df)` |
| `fit.Coefficients` | `coef(summary(fit))` | `res.params`, `res.bse`, `res.tvalues`, `res.pvalues` |
| `fit.Sigma`, `fit.Df` | `summary(fit)$sigma`, `fit$df.residual` | `np.sqrt(res.scale)`, `res.df_resid` |
| `fit.RSquared`, `fit.AdjustedRSquared` | `summary(fit)$r.squared`, `$adj.r.squared` | `res.rsquared`, `res.rsquared_adj` |
| `fit.F`, un `stats.Test` | `summary(fit)$fstatistic` | `res.fvalue`, `res.f_pvalue` |
| `fit.Confint(level = 0.95)` | `confint(fit)` | `res.conf_int()` |
| `fit.Predict(new)` | `predict(fit, new)` | `res.predict(new)` |
| `fit.Band(new, kind = "prediction")` | `predict(fit, new, interval = "prediction")` | `res.get_prediction(new).summary_frame()` |
| `fit.Fitted`, `fit.Residuals`, `fit.Rows`, `fit.Rank` | `fitted(fit)`, `resid(fit)`, `nobs(fit)`, `fit$rank` | `res.fittedvalues`, `res.resid`, `res.nobs` |

Une colonne de nombres est prise telle quelle. Une colonne de textes devient une colonne indicatrice pour chacun de ses
niveaux sauf le premier dans l'ordre trié, nommée `name[level]`, le codage par traitement de R :

```cesia
cars = frame.SetColumn("cyl", ["6", "4", "6", "8", "6", "8", "4", "4", "6", "6"], cars)
frame.Column("term", result.Unwrap(stats.Lm("mpg", ["wt", "cyl"], cars)).Coefficients) -->
```

Un produit ou une puissance est une colonne que vous faites d'abord,
`frame.SetColumn("wt2", frame.Column("wt", cars) ^ 2, cars)`, là où R écrit `I(wt^2)` dans sa formule : une seule façon
de faire une colonne, pas deux. Une colonne avec une valeur manquante est un `Err` qui nomme la colonne et la ligne ;
`frame.DropMissing(frame.Select([...], df))` enlève ces lignes. `Predict` et `Band` donnent NaN pour une ligne avec une
valeur manquante, et font une panic pour un niveau d'une colonne de textes que l'ajustement n'a pas vu, comme le
« factor has new levels » de R.

Le même modèle en Python, R et MATLAB :

```python
import statsmodels.formula.api as smf
res = smf.ols("mpg ~ wt + hp", cars).fit()
res.summary()
```

```r
fit <- lm(mpg ~ wt + hp, data = cars)
summary(fit)
```

```matlab
mdl = fitlm(cars, 'mpg ~ wt + hp')
```

### Comment il est calculé

Lm factorise $[X | y]$, les colonnes du modèle puis $y$, par les réflexions de Householder (Golub et Van Loan, 2013,
chapitre 5), comme le fait le `lm` de R avec le `dqrdc2` de LINPACK et LAPACK avec `dgeqrf`. Son triangle supérieur $R$
donne les estimations par substitution arrière, sa dernière colonne contient $Q^T y$ et la norme des résidus, donc $Q$
n'est jamais formée ; les erreurs standard sont $\sigma \sqrt{((R^T R)^{-1})_{jj}}$ à partir de l'inverse de $R$, avec
$\sigma^2 = \text{RSS} / (n - \text{rank})$. Les équations normales $X^T X b = X^T y$, que résout `num.LeastSquares`,
mettent au carré le conditionnement de $X$, le facteur par lequel une erreur des données grandit dans la réponse, et
perdent deux fois plus de chiffres ; la QR ne les perd qu'une fois.

Une colonne dont la norme, au-delà des colonnes d'avant, est sous `tol` fois sa propre norme est une combinaison de
celles-ci, comme le veut la règle de R : elle est enlevée, son estimation vaut `missing`, le `NA` de R, et le modèle
continue sans elle. `tol = 1e-7` est celui de R.

### Ce qu'il promet

Les Statistical Reference Datasets du NIST, l'institut américain des normes, ont des valeurs certifiées à 15 chiffres
pour des régressions de difficulté basse, moyenne et haute. Mesuré en nombre de chiffres qui s'accordent avec elles
(McCullough, 1998), le plus petit sur les estimations, leurs erreurs standard, $\sigma$ et $R^2$ :

| Jeu de données | Difficulté | Cesia | R 4.6.2 |
|---|---|---:|---:|
| Norris | basse | 13,3 | 12,5 |
| Pontius | basse | 12,4 | 12,7 |
| NoInt1, NoInt2 | moyenne | 14,7 ; 15,0 | 14,4 ; 15,0 |
| Longley | haute | 12,9 | 13,0 |
| Wampler1, 2, 3 | haute | 9,7 ; 12,7 ; 9,3 | 9,8 ; 13,6 ; 9,3 |
| Wampler4, 5 | haute | 7,8 ; 5,8 | 7,5 ; 5,5 |
| Filip, un polynôme de degré 10, `tol = 1e-10` | haute | 7,2 | 7,0 |

Avec le `tol` de R, la dixième puissance de Filip est enlevée, dans R comme dans Cesia ; les tests de Cesia le vérifient
aussi. Les chiffres perdus sur Wampler et Filip viennent de leurs données : un polynôme de degré 5 ou 10 en $x$ fait des
colonnes presque dépendantes, et une méthode stable perd en chiffres le logarithme de leur conditionnement, quoi qui le
calcule.

## Les tests

Un test dit si une différence dans des données pourrait venir du seul hasard. Chaque test de std/stats donne un `Ok`
d'un `stats.Test`, les champs du `htest` de R, ou un `Err` pour des données qu'il ne peut pas tester : une valeur
manquante, trop peu de valeurs, des valeurs toutes égales là où la statistique a besoin qu'elles varient.

```cesia
x = [0.7, -1.6, -0.2, -1.2, -0.1, 3.4, 3.7, 0.8, 0.0, 2.0]
y = [1.9, 0.8, 1.1, 0.1, -0.1, 4.4, 5.5, 1.6, 4.6, 3.4]
t = result.Unwrap(stats.TTest2(x, y))
t.PValue -->
t.Interval -->
t -->
```

`Method` nomme le test, `Statistic` est son nombre, `Df` ses degrés de liberté, `PValue` la probabilité d'une
statistique au moins aussi éloignée de l'hypothèse nulle quand seul le hasard est à l'œuvre, `Estimate` le nombre que
`Interval` encadre au niveau `Level`, et `Alternative` le côté du test : `"two-sided"`, `"less"` ou `"greater"`. Dans
une cell, une struct s'affiche comme une table de ses champs, un par ligne, si bien que le test se lit comme R
l'affiche.

| Cesia | R | Python, scipy.stats |
|---|---|---|
| `stats.TTest(x, mu = 0.0)` | `t.test(x, mu = 0)` | `ttest_1samp(x, 0)` |
| `stats.TTest(x - y)`, le test apparié | `t.test(x, y, paired = TRUE)` | `ttest_rel(x, y)` |
| `stats.TTest2(x, y)`, celui de Welch | `t.test(x, y)` | `ttest_ind(x, y, equal_var = False)` |
| `stats.TTest2(x, y, equal = true)`, celui de Student | `t.test(x, y, var.equal = TRUE)` | `ttest_ind(x, y)` |
| `stats.WilcoxonTest(x - y)`, des rangs signés | `wilcox.test(x, y, paired = TRUE)` | `wilcoxon(x, y)` |
| `stats.WilcoxonTest2(x, y)`, de la somme des rangs | `wilcox.test(x, y)` | `mannwhitneyu(x, y)` |
| `stats.KsTest(x, stats.Normal(0, 1))`, toute loi de std/stats | `ks.test(x, "pnorm", 0, 1, exact = TRUE)` | `kstest(x, "norm")` |
| `stats.ChiSquaredTest(counts, p = probs)` | `chisq.test(counts, p = probs)` | `chisquare(counts, f_exp)` |
| `stats.ChiSquaredTest(table)`, une matrice | `chisq.test(table)` | `chi2_contingency(table)` |
| `stats.CorTest(x, y)`, celui de Pearson | `cor.test(x, y)` | `pearsonr(x, y)` |

Chacun prend `alternative = "two-sided"`, et ceux qui ont un intervalle `level = 0.95`. Les tests appariés sont les
tests à un échantillon des différences, une seule façon de les écrire.

La variance d'un échantillon, dont les tests se servent, divise par $n - 1$ : le `var(x)` et le `sd(x)` de R.
[num.Variance] et [num.Std] divisent par $n$ par défaut, comme le fait numpy, et `sample = true` donne ceux de R :
`num.Std(x, sample = true)` est `sd(x)`, et `num.Covariance(x, y, sample = true)` est `cov(x, y)`.

```python
from scipy import stats
stats.ttest_ind(x, y, equal_var=False)
```

```r
t.test(x, y)
```

```matlab
[h, p, ci, st] = ttest2(x, y, 'Vartype', 'unequal')
```

### Ce que calcule chaque test

- **Tests t** : Student (1908) ; Welch (1947) avec les degrés de liberté de Satterthwaite (1946) ; la moyenne et la
  variance en deux passages, la moyenne puis les carrés des distances à elle, corrigés par la somme des distances que
  l'arrondi laisse (Chan, Golub et LeVeque, 1983).
- **Wilcoxon** : le test des rangs signés (Wilcoxon, 1945) enlève les zéros et donne aux ex aequo leur rang moyen ; le
  test de la somme des rangs (Mann et Whitney, 1947) donne $W$, leur $U$. Exact quand il y a moins de 50 valeurs, chaque
  échantillon pour la somme des rangs, comme R 4.6 : la loi de la statistique connaissant les rangs, ex aequo compris,
  en comptant les sous-ensembles des rangs ; sans ex aequo, les comptes de la somme des rangs sont ceux du coefficient
  $q$-binomial, par sa règle de Pascal. Au-delà de 50, l'approximation normale, avec ses corrections pour les ex aequo
  et, avec `correct`, pour la continuité.
- **Kolmogorov–Smirnov** : $D = \max |F_n - F|$, $F_n$ la loi empirique de l'échantillon ; exact jusqu'à 16 000 valeurs
  sans ex aequo par la méthode de Marsaglia, Tsang et Wang (2003), dont l'article y donne de 13 à 15 chiffres. Au-delà
  de $n D^2 = 7{,}24$, là où leur article quitte la matrice pour une formule de la queue, $p < 10^{-6}$ et
  $1 - P(D < d)$ perdrait ses chiffres : là, $p$ vaut deux fois la queue d'un seul côté, puisque $D^+$ et $D^-$ tous
  deux au-delà de $d$ sont environ $e^{-6 n D^2}$ fois aussi probables, moins de $10^{-18}$ de celle-ci. La série limite
  de Kolmogorov au-delà de 16 000 valeurs, ou avec des ex aequo ; d'un seul côté par la somme exacte de Birnbaum et
  Tingey (1951). R prend la limite dès 100 valeurs : ses réponses y diffèrent de celles de Cesia sauf si on lui donne
  `exact = TRUE`.
- **Khi-deux** : Pearson (1900), les comptes attendus à partir des marges d'une table, et la correction de Yates (1934)
  pour une table $2 \times 2$, comme R par défaut.
- **Corrélation** : $t = r \sqrt{(n - 2) / (1 - r^2)}$ à $n - 2$ degrés de liberté ; son intervalle par le
  $z = \text{atanh}\, r$ de Fisher (1915), pour 4 valeurs ou plus.

Sur des données au hasard pour chaque test, et les deux alternatives, les statistiques, les degrés de liberté et les
intervalles s'accordent avec ceux de R 4.6.2 à $10^{-15}$ près et les p-values à $10^{-13}$ près ; les tests de Cesia
vérifient les propres exemples de R, et les lois exactes des statistiques de rangs contre tous leurs cas, comptés un par
un.

## Les fonctions spéciales

`std/special` contient les onze fonctions sous les lois, pour qui en a besoin seules : l'`erf` d'un physicien, un
`LogGamma`. Chacune prend des nombres ; son dernier argument peut aussi être un array, de n'importe quelle forme, et la
réponse est alors un array de même forme, élément par élément :

```cesia
use std/special
special.Gamma(5) -->
special.LogGamma(100) -->
special.Erf([0.0, 0.5, 1.0, 2.0]) -->
special.GammaInc(3, 2.5) -->
special.BetaInc(2, 3, 0.4) -->
```

| Cesia | Ce que c'est | R | Python | MATLAB |
|---|---|---|---|---|
| `special.Gamma(x)` | $\Gamma(x)$, $(n - 1)!$ en un entier $n$ | `gamma(x)` | `scipy.special.gamma(x)` | `gamma(x)` |
| `special.LogGamma(x)` | le $\log$ de la valeur absolue de $\Gamma(x)$, fini là où $\Gamma$ déborde | `lgamma(x)` | `gammaln(x)` | `gammaln(x)` |
| `special.Beta(a, b)` | $B(a, b) = \Gamma(a) \Gamma(b) / \Gamma(a + b)$ | `beta(a, b)` | `beta(a, b)` | `beta(a, b)` |
| `special.LogBeta(a, b)` | $\log B(a, b)$ | `lbeta(a, b)` | `betaln(a, b)` | `betaln(a, b)` |
| `special.Erf(x)` | $2 P(0 < Z < x \sqrt 2)$ pour une normale centrée réduite $Z$ | `2 * pnorm(x * sqrt(2)) - 1` | `erf(x)` | `erf(x)` |
| `special.Erfc(x)` | $1 - \text{erf}(x)$, calculée directement | `2 * pnorm(-x * sqrt(2))` | `erfc(x)` | `erfc(x)` |
| `special.Erfcx(x)` | $e^{x^2} \text{erfc}(x)$ | | `erfcx(x)` | `erfcx(x)` |
| `special.ErfInv(y)` | le $x$ où $\text{erf}(x) = y$ | `qnorm((y + 1) / 2) / sqrt(2)` | `erfinv(y)` | `erfinv(y)` |
| `special.ErfcInv(y)` | le $x$ où $\text{erfc}(x) = y$ | `qnorm(y / 2, lower.tail = FALSE) / sqrt(2)` | `erfcinv(y)` | `erfcinv(y)` |
| `special.GammaInc(a, x)` | $P(a, x)$, la fonction gamma incomplète inférieure régularisée | `pgamma(x, a)` | `gammainc(a, x)` | `gammainc(x, a)` |
| `special.GammaInc(a, x, upper = true)` | $Q(a, x) = 1 - P(a, x)$, calculée directement | `pgamma(x, a, lower.tail = FALSE)` | `gammaincc(a, x)` | `gammainc(x, a, 'upper')` |
| `special.BetaInc(a, b, x)` | $I_x(a, b)$, la fonction bêta incomplète régularisée | `pbeta(x, a, b)` | `betainc(a, b, x)` | `betainc(x, a, b)` |
| `special.BetaInc(a, b, x, upper = true)` | $1 - I_x(a, b)$, calculée directement | `pbeta(x, a, b, lower.tail = FALSE)` | `betaincc(a, b, x)` | `betainc(x, a, b, 'upper')` |

R n'a pas d'`erf` : les lignes ci-dessus l'écrivent avec la loi normale, ce que font les utilisateurs de R. MATLAB met
`x` en premier dans `gammainc` et `betainc` ; Cesia met en dernier l'argument qui peut être un array, comme le fait
scipy.

Les rapports incomplets sont des probabilités : $P(a, x)$ est la probabilité qu'une variable gamma de forme $a$ tombe
sous $x$, et $I_x(a, b)$ la probabilité qu'une variable bêta tombe sous $x$. Chaque loi des sections suivantes repose
sur eux : le khi-deux, la loi gamma et celle de Poisson sur $P$, celle de Student, la loi F, la loi bêta et la binomiale
sur $I$.

### Les deux queues

Une queue d'une loi est la probabilité au-delà d'un point, en dessous ou au-dessus. `upper = true` calcule directement
celle du haut. `1 - P` le ferait en principe, mais quand $P$ est proche de 1, la soustraction ne garde aucun des
chiffres de la petite réponse :

```cesia
1.0 - special.GammaInc(100, 200) -->
special.GammaInc(100, 200, upper = true) -->
```

La première garde un chiffre : $P$ est un float proche de 1, et ses derniers bits sont tout ce qui reste de $Q$. La
seconde est $Q(100, 200)$ à 15 chiffres.

### Hors du domaine

Un domaine est l'endroit où une fonction est définie. En dehors, la réponse est NaN, comme le donne `math.Log(-1.0)` :
`GammaInc(a, x)` avec un `a` ou un `x` négatif, `BetaInc(a, b, x)` avec `x` hors de `[0, 1]`, `ErfInv(y)` avec
`|y| > 1`. Un NaN donné est un NaN rendu. $\Gamma$ est infinie en 0, avec le signe du zéro, et NaN aux entiers négatifs,
où elle a des pôles ; `LogGamma` y est infinie. Un argument qui n'est pas un nombre, ou un array qui contient un texte
ou un `missing`, est un bug de l'appelant : une panic qui le nomme.

```cesia
special.Gamma(-0.5) -->
special.Gamma(0.0) -->
special.ErfInv(1.5) -->
```

```cesia fails
special.Gamma([1.0, missing])
```

### La même chose en Python, R et MATLAB

```python
from scipy import special
special.gamma(5), special.gammaln(100), special.erf([0.0, 0.5, 1.0, 2.0])
special.gammainc(3, 2.5), special.betainc(2, 3, 0.4), special.gammaincc(100, 200)
```

```r
gamma(5); lgamma(100); 2 * pnorm(c(0, 0.5, 1, 2) * sqrt(2)) - 1
pgamma(2.5, 3); pbeta(0.4, 2, 3); pgamma(200, 100, lower.tail = FALSE)
```

```matlab
gamma(5), gammaln(100), erf([0 0.5 1 2])
gammainc(2.5, 3), betainc(0.4, 2, 3), gammainc(200, 100, 'upper')
```

### Ce que promet chacune

Chaque fonction suit une méthode publiée ; sa précision est ce que mesurent les tests de Cesia, en unités de
$\epsilon = 2^{-52}$, l'écart entre 1.0 et le float suivant : une erreur de 1 $\epsilon$ est une erreur relative de
$2{,}2 \times 10^{-16}$, environ 16 chiffres justes, 45 $\epsilon$ environ 14 chiffres.

- **`LogGamma` et `Gamma`.** Sur $[1{,}5 ; 2{,}5]$, $\log \Gamma(2 + z)$ est sa série de Taylor en 2,
  $(1 - \gamma) z + \sum_{k \ge 2} (-1)^k (\zeta(k) - 1) z^k / k$ (Abramowitz et Stegun, 6.1.33), 27 termes, dont les
  coefficients ont été calculés à 60 chiffres avec l'arithmétique décimale de Python ; sous 1,5 et jusqu'à 10, la
  récurrence $\Gamma(x + 1) = x \Gamma(x)$ y amène $x$ ; à partir de 10, la série de Stirling, avec huit de ses termes ;
  sous 0, la réflexion $\Gamma(x) \Gamma(1 - x) = \pi / \sin \pi x$, avec $\sin \pi x$ à partir de $x$ moins l'entier le
  plus proche, une différence qui est exacte. Près de 1 et de 2, où $\log \Gamma$ vaut 0, la série garde aussi la
  précision relative.
- **`Erf`, `Erfc`, `Erfcx`.** Les approximations rationnelles de Cody (1969), avec les coefficients de son SPECFUN
  (1993), sur $|x| \le 0{,}46875$, jusqu'à 4 et au-delà. Pour un grand $x$, $e^{-x^2}$ multiplie l'erreur de $x^2$ par
  $x^2$ : $x$ est coupé en un nombre de seizièmes, dont le carré est exact, et le reste, pour que $\text{erfc}$ garde
  ses chiffres jusqu'à $10^{-308}$, en $x = 26{,}5$.
- **`ErfInv`, `ErfcInv`.** Le quantile normal PPND16 de Wichura (1988), des approximations rationnelles dans trois
  régions, « accurate to about 1 part in $10^{16}$ » (précis à environ une part sur $10^{16}$, dit l'article), puisque
  $\text{erfc}(x) = 2 P(Z > x \sqrt 2)$ pour $Z$ de loi normale. `ErfcInv` garde ses chiffres pour un petit `y`,
  jusqu'au plus petit float.
- **`GammaInc`.** Les régions de DiDonato et Morris (1986) : près de $x = a$ pour $a \ge 20$, de $0{,}6 a$ à $1{,}4 a$,
  le développement asymptotique uniforme de Temme (Temme 1979 ; DLMF 8.12), dont les 142 coefficients viennent de la
  récurrence de DLMF 8.12.12, calculés exactement en rationnels ; en dessous, la série entière de $P$ ; au-dessus, la
  partie paire de la fraction continue de Legendre pour $Q$ (DLMF 8.9.2), évaluée vers l'avant par la méthode de Lentz
  modifiée (Thompson et Barnett, 1986) ; pour $a < 1$ et $x \le 1{,}5$, une série de $Q$ elle-même, dont les trois
  termes sont chacun de la taille de $a$, pour que $Q$ garde ses chiffres quand $a$ tend vers 0. Le facteur
  $x^a e^{-x} / \Gamma(a)$ est calculé avec `pow` et `exp` là où aucun des deux ne déborde, et sinon à travers
  $\lambda = x / a$ : $\sqrt{a / 2\pi} \, e^{a (\log \lambda - \lambda + 1)} / \Gamma^{\text{*}}(a)$, avec
  $\log(1 + t) - t$ calculé sans annulation pour un petit $t$.
- **`BetaInc`.** C'est la plus petite queue qui est calculée : celle qui est sous la moyenne $a / (a + b)$, par la
  symétrie $I_x(a, b) = 1 - I_{1 - x}(b, a)$ (DLMF 8.17.4) ; pour un petit $x$ par la série entière, sinon par la partie
  paire de la fraction continue de DLMF 8.17.22. Près de la moyenne, les premiers termes de cette fraction sont des
  différences de grands nombres qui s'annulent : ils sont écrits avec $\lambda = a (1 - x) - b x$, qui y garde les
  chiffres. Le facteur $x^a (1 - x)^b / B(a, b)$ est calculé pour $a, b \ge 10$ à travers la série de Stirling, comme le
  font DiDonato et Morris (1992), pour que rien de grand ne s'annule.

Les tests comparent chaque fonction avec des valeurs calculées à 70 chiffres, à partir du float exact de chaque
argument, avec l'arithmétique décimale de Python, et avec les données de test publiées de Boost.Math, calculées par ses
auteurs à 100 chiffres. Sur les valeurs à 70 chiffres, quelques milliers de points répartis sur chaque domaine :

| Fonction | Points | Plus grande erreur | Erreur moyenne |
|---|---:|---:|---:|
| `LogGamma`, $x$ de $10^{-13}$ à $10^{13}$, loin de 1 et de 2 | 992 | 3,3 $\epsilon$ | 0,33 $\epsilon$ |
| `LogGamma`, à moins de 0,25 de 1 ou de 2 | 208 | 2,4 $\epsilon$ | 0,36 $\epsilon$ |
| `Gamma`, $0 < x < 171$ | 962 | 2,4 $\epsilon$ | 0,31 $\epsilon$ |
| `Gamma`, $-170 < x < 0$ | 600 | 3,3 $\epsilon$ | 0,72 $\epsilon$ |
| `Erf`, $-6 < x < 6$ | 1 200 | 2,0 $\epsilon$ | 0,34 $\epsilon$ |
| `ErfInv` et le quantile normal, $p$ jusqu'à $10^{-300}$ | 300 | 2,0 $\epsilon$ | 0,58 $\epsilon$ |

Sur les données de Boost, à côté de R 4.6.2 et de scipy 1.18.1 sur les mêmes points :

| Données de Boost | Cesia, plus grande / moyenne | R | scipy |
|---|---|---|---|
| `igamma_small_data`, $Q$ | 3,3 / 0,50 $\epsilon$ | 13,8 / 0,87 | 61,4 / 4,02 |
| `igamma_med_data`, $P$ | 5,4 / 0,52 $\epsilon$ | 6,2 / 0,75 | 398,6 / 25,1 |
| `igamma_med_data`, $Q$ | 9,7 / 0,54 $\epsilon$ | 11,8 / 0,70 | 556,5 / 17,4 |
| `igamma_big_data`, $P$ | 199,6 / 2,30 $\epsilon$ | 25,7 / 0,41 | 3 093,8 / 35,2 |
| `igamma_big_data`, $Q$ | 214,2 / 1,83 $\epsilon$ | 51,7 / 0,75 | 11 588,5 / 57,0 |
| `igamma_int_data`, $Q$ | 4,8 / 0,64 $\epsilon$ | 19,0 / 0,61 | 136,8 / 8,90 |
| `ibeta_small_data`, $I$ | 22,9 / 1,80 $\epsilon$ | 22,9 / 1,70 | 8,3 / 1,31 |
| `ibeta_data`, $I$ | 384,7 / 10,6 $\epsilon$ | 232,1 / 11,0 | 106,0 / 8,25 |
| `ibeta_data`, $1 - I$ | 389,2 / 12,4 $\epsilon$ | 204,1 / 11,3 | 0,4 / 0,14 |
| `ibeta_large_data`, $I$ | 578,8 / 11,0 $\epsilon$ | 573,6 / 13,2 | 1 239,4 / 10,2 |
| `ibeta_int_data`, $I$ | 74,0 / 3,74 $\epsilon$ | 62,0 / 4,33 | 3,9 / 0,42 |
| `erf_data`, `erfc` | 2,5 / 0,30 $\epsilon$ | 75,5 / 6,67 | 3,6 / 0,45 |
| `erf_large_data`, `erfc` | 1,2 / 0,38 $\epsilon$ | 837,6 / 222,7 | 2,5 / 0,63 |

**Là où les autres gagnent.** R est plus proche sur les plus grandes lois gamma, `igamma_big_data`, avec $a$ jusqu'à
$10^5$ : là, le facteur $e^{a(\log\lambda - \lambda + 1)}$ a un exposant de quelques centaines, et R le calcule en deux
floats, une somme qui garde environ 30 chiffres, là où Cesia en prend un seul. Le `betaincc` de scipy, qui est le code
de Boost, est plus proche sur les propres données bêta de Boost, à un demi-$\epsilon$ près.

Les plus grandes erreurs des rapports incomplets se trouvent dans leurs queues lointaines, là où la fonction elle-même
change d'un grand facteur pour un petit changement de ses arguments : un changement relatif de $\epsilon$ en $x$ change
$P(a, x)$ d'environ $c \, \epsilon$, avec $c = |x \, P'| / P$, $P'$ la pente de $P$ en $x$, qui y atteint des milliers ;
les tests à 70 chiffres de Cesia y acceptent $16 (1 + c) \, \epsilon$, et $4 \epsilon$ pour `LogGamma`, `Gamma`,
`LogBeta`, `Erf` et `Erfc`. DiDonato et Morris appellent cela l'*inherent error* (l'erreur inhérente) : leurs codes
promettent 14 chiffres « when precision is not restricted by inherent error » (quand la précision n'est pas limitée par
l'erreur inhérente). Là où un argument est sous environ $10^{-3}$, `BetaInc` perd jusqu'à environ 2 500 $\epsilon$ dans
la queue près de $x = 1$, là où R garde tous ses chiffres.

### La vitesse des fonctions spéciales

Sur la machine de [Vitesse](speed.md#à-côté-des-géants), un appel sur un nombre coûte environ 0,4 µs pour `LogGamma`,
1 µs pour `GammaInc` et `BetaInc`, l'appel lui-même pour l'essentiel ; le calcul à l'intérieur est du code machine fait
par le JIT (le compilateur qui traduit le code en code machine pendant qu'il tourne) : `special.Erf` sur un array de
$10^6$ floats prend environ 70 ms, 70 ns par élément.

## Monte-Carlo

[stats.MonteCarlo] estime une moyenne en tirant au hasard : une intégrale comme la moyenne d'une fonction en des points
uniformes, une probabilité comme la moyenne d'un test, l'espérance d'une simulation comme la moyenne de ses lancements.
Il donne la moyenne des tirages, son *erreur standard*, qui dit à quelle distance cette moyenne peut être de la vraie,
et un *intervalle* qui contient la vraie moyenne avec la probabilité `level`, 0,95 par défaut. Avec numpy et
`scipy.stats.t.interval`, ou le `mean` et le `tinv` de MATLAB, cela prend quelques lignes, et une boucle à vous pour
tirer jusqu'à ce que l'intervalle soit assez étroit.

`f()` donne un tirage, un nombre, ou un *batch* (un lot) de tirages, un array ; `true` et `false` comptent pour 1 et 0,
pour que la moyenne d'un test soit sa probabilité. Donnez `n`, le nombre de tirages, ou `tol`, la demi-largeur que
l'intervalle doit atteindre :

```cesia
use std/math
use std/num
use std/random
mc = result.Unwrap(stats.MonteCarlo(() -> math.Exp(-num.Uniform(100000) ^ 2), tol = 1e-3))
mc.Interval[2] - mc.Mean <= 1e-3 -->
math.Abs(mc.Mean - special.Erf(1) * math.Sqrt(math.Pi) / 2) < 5 * mc.StdError -->
p = result.Unwrap(stats.MonteCarlo(() -> random.Float() < 0.25, n = 10000))
p.N -->
```

Le premier estime l'intégrale de $e^{-x^2}$ de 0 à 1, $\sqrt{\pi}\, \text{erf}(1) / 2 = 0{,}746824132812427$, comme la
moyenne de $e^{-u^2}$ pour $u$ uniforme sur $[0, 1)$, par batches de 100 000 tirages, jusqu'à ce que la demi-largeur de
l'intervalle soit de $10^{-3}$ ou moins ; un lancement a donné `Mean = 0.747162`, `StdError = 0.000449` et l'intervalle
`[0.746283, 0.748042]`, à partir de `N = 200000` tirages. Le second est la probabilité qu'un tirage uniforme soit sous
0,25, à partir de 10 000 tirages un par un. Ce qu'il donne est un `stats.Estimate` :

| Champ | Ce qu'il contient |
|---|---|
| `Mean` | la moyenne des tirages |
| `StdError` | $s / \sqrt{N}$, $s$ l'écart type des tirages, sur $N - 1$ |
| `Interval` | `[Mean - t StdError, Mean + t StdError]`, $t$ le quantile de la loi de Student à $N - 1$ degrés de liberté en $(1 + \text{Level}) / 2$ |
| `N` | le nombre de tirages |
| `Level` | le niveau demandé |

Un batch fait par des opérations sur des arrays coûte bien moins qu'autant d'appels d'une fonction qui donne un seul
tirage, comme le montre [Vitesse](#vitesse). Avec `n`, le dernier batch est coupé, pour que exactement `n` tirages
servent. Avec `tol`, le test est fait après chaque batch, ou tous les 1 000 tirages un par un, à partir de 1 000 tirages
; `most`, $10^9$ par défaut, borne les tirages.

| Cesia | Python, numpy et scipy | MATLAB | R |
|---|---|---|---|
| `stats.MonteCarlo(f, n = 100000)`, `f()` un batch | `x = f()`, puis `stats.t.interval(0.95, x.size - 1, x.mean(), stats.sem(x))` | `x = f()`, puis `mean(x) + tinv([0.025 0.975], numel(x) - 1) * std(x) / sqrt(numel(x))` | `x <- f()`, puis `t.test(x)$conf.int` |
| `stats.MonteCarlo(f, n = 100000)`, `f()` un tirage | `x = np.fromiter((f() for _ in range(n)), float, n)`, puis la même chose | `x = arrayfun(@(k) f(), 1:n)`, puis la même chose | `x <- replicate(n, f())`, puis la même chose |
| `stats.MonteCarlo(f, tol = 1e-3)` | une boucle à vous | une boucle à vous | une boucle à vous |

```python
import numpy as np
from scipy import stats
rng = np.random.default_rng()
x = np.exp(-rng.random(200000) ** 2)
stats.t.interval(0.95, x.size - 1, loc=x.mean(), scale=stats.sem(x))
```

```matlab
x = exp(-rand(200000, 1) .^ 2);
mean(x) + tinv([0.025 0.975], numel(x) - 1) * std(x) / sqrt(numel(x))
```

```r
x <- exp(-runif(200000)^2)
t.test(x)$conf.int
```

`tinv` fait partie de la Statistics Toolbox de MATLAB, et du package statistics d'Octave.

### Dans une cell

Dans un fichier de [cells](cells.md), l'estimation s'affiche comme une table de ses champs, et un histogramme d'un batch
montre comment les tirages se répartissent. Chaque cell tire à partir d'un seed à elle, fait de celui de la session et
du titre de la cell, si bien qu'une cell qui tourne de nouveau donne le même intervalle, quoi qu'il ait tourné avant
elle, comme le dit [Les tirages au hasard](#les-tirages-au-hasard) :

```cesia norun
use std/math
use std/num
use std/plot
use std/stats

(* %% Monte Carlo *)
mc = stats.MonteCarlo(() -> math.Exp(-num.Uniform(100000) ^ 2), tol = 1e-4)
mc

(* %% One batch *)
plot.Of([plot.Histogram(math.Exp(-num.Uniform(100000) ^ 2))], x = "e^(-u^2)", y = "draws")
```

À `tol = 1e-4`, la première cell fait 15,6 millions de tirages, presque tout son temps passé dans `f`, comme le montre
[Vitesse](#vitesse). Le même histogramme, fait ici et dessiné en SVG :

```cesia
use std/plot
g = plot.Of([plot.Histogram(math.Exp(-num.Uniform(100000) ^ 2))], x = "e^(-u^2)", y = "draws")
result.IsOk(plot.Svg(g)) -->
```

### Comment il est calculé

Les tirages ne sont jamais gardés. Ils sont réduits 1 000 à la fois, ceux d'un batch ou 1 000 tirages un par un
rassemblés dans un array : pour chaque bloc de $k$ tirages $x_i$, l'*algorithme à deux passages corrigé* de Chan, Golub
et LeVeque (1983) prend leur moyenne $m$, puis les distances $d_i = x_i - m$, dont la somme $c$ est la part de la
moyenne que l'arrondi a laissée hors de $m$ :

$$
\text{mean} = m + \frac{c}{k}, \quad q = \sum_i d_i^2 - \frac{c^2}{k}
$$

$q$ étant la somme des carrés des distances à la moyenne. Les deux valent pour n'importe quel $m$ ; un $m$ proche de la
moyenne garde leurs chiffres. Les blocs sont fusionnés par leur formule, pour deux ensembles de $n_a$ et $n_b$ tirages
de moyennes $m_a$ et $m_b$ :

$$
q_{ab} = q_a + q_b + \frac{n_a n_b}{n_a + n_b} (m_b - m_a)^2
$$

dont la mise à jour de Welford (1962) est le cas $n_b = 1$, un tirage à la fois. Ces identités ont été vérifiées ici en
arithmétique rationnelle exacte, sur un millier d'ensembles au hasard. La somme courante des tirages et le $q$ courant
gardent chacun à côté d'eux les erreurs d'arrondi de leurs additions, par la somme compensée de Neumaier (1974) : la
`Mean` est à quelques unités de la dernière place près de la moyenne exacte des tirages, qu'ils soient venus un par un
ou par batches de n'importe quelle taille. Sur des tirages uniformes, exponentiels et décalés, donnés un à la fois et
par batches de 7, 1 000, 4 096 et tous à la fois, elle était à 0 ou 1 unité de la moyenne exacte, et jusqu'à 4 sur des
tirages de 0 et 1, là où `list.Mean` des mêmes tirages était à 20 à 57 unités. La `StdError` des mêmes tirages s'accorde
à $10^{-15}$ près quels que soient les batches, ou à environ $\kappa \epsilon$ près quand la moyenne vaut $\kappa$ fois
l'écart type : la distance entre deux moyennes que la fusion met au carré est connue à $\epsilon$ fois la moyenne près.

Ensuite

$$
\text{StdError} = \frac{s}{\sqrt{N}}, \quad s^2 = \frac{q}{N - 1}, \quad \text{Interval} = \text{Mean} \pm t_{N-1} \,
\text{StdError}
$$

avec $t_{N-1}$ le quantile de la loi de Student (1908) à $N - 1$ degrés de liberté en $(1 + \text{level}) / 2$, comme le
calcule `stats.TTest` : sur les mêmes valeurs, les deux donnent le même intervalle à $10^{-15}$ près.

Avec `tol`, les tirages continuent selon la règle de Chow et Robbins (1965) : s'arrêter au premier $N \ge 1000$ où
$t_{N-1} \, s / \sqrt{N} \le \text{tol}$. Leur règle, pour une demi-largeur $d$, s'arrête au premier $n \ge n_0$ tel que
$n \ge a_n^2 (s_n^2 + 1/n) / d^2$, où $a_n$ est n'importe quelle suite qui tend vers $a$, le quantile normal du niveau.
Celle de Cesia prend $n_0 = 1000$ et $a_n = t_{n-1}$, et laisse de côté leur $1/n$ : un terme dans les unités des
tirages au carré, qui pour des tirages de taille $10^{-6}$ demandés à un `tol` de $10^{-9}$ demanderait
$a / \text{tol}$, $2 \times 10^9$ tirages, quelle que soit leur dispersion. Les 1 000 empêchent la règle de s'arrêter
sur un petit échantillon malchanceux. Le test est fait après chaque batch, pas après chaque tirage : pour des batches
d'une taille bornée, c'est leur règle sur la suite des fins des batches, dont le rapport de l'une à la suivante tend
vers 1, comme le demande leur lemme. Le quantile de Student coûte une résolution de la loi bêta, environ 60 µs ; le
quantile normal, qui est en dessous, est testé d'abord, pour que la résolution ne tourne que près de la fin.

### Ce qu'il promet

- **Avec `n`.** Pour des tirages normaux, l'intervalle contient la vraie moyenne avec une probabilité `level` exactement
  (Student, 1908). Pour des tirages de n'importe quelle loi de variance finie, la probabilité tend vers `level` quand
  `n` grandit, par le théorème central limite. À un `n` donné, elle peut être moindre, d'autant plus que la loi est
  asymétrique : pour un tirage de 1 avec une probabilité de 0,01 et 0 sinon, elle vaut 94,62 % à $n = 10\,000$ et 94,99
  % à 5 000, calculées exactement en sommant la loi binomiale.
- **Avec `tol`.** La demi-largeur de l'intervalle est au plus `tol` : c'est le test. Chow et Robbins ont prouvé, pour
  des tirages d'une loi dont la variance $\sigma^2$ est finie et au-dessus de 0, que quand `tol` tend vers 0, la
  probabilité que l'intervalle contienne la vraie moyenne tend vers `level`, et que $N$ tend vers
  $(a \sigma / \text{tol})^2$, le nombre de tirages qu'on choisirait en connaissant $\sigma$, sa moyenne aussi ;
  Mukhopadhyay et Datta (1996) énoncent ainsi le théorème. Pour une loi dont des valeurs ont une probabilité à elles,
  comme le vrai et le faux d'un test, les 1 000 premiers tirages peuvent tous être égaux, avec une certaine probabilité
  $p_0$, $0{,}99^{1000} = 4{,}3 \times 10^{-5}$ pour un événement de probabilité 0,01 : la règle s'arrête alors à 1 000
  tirages avec une `StdError` de 0, et la limite est `level` moins au plus $p_0$. À un `tol` donné, rien n'est promis :
  la couverture tend vers `level` quand `tol` diminue, pas avant.
- **Jamais.** Pour des tirages sans variance finie, comme ceux de Cauchy, la moyenne des tirages ne se stabilise pas et
  l'intervalle ne veut rien dire ; les tirages ne peuvent pas le dire à coup sûr.
- **Des tirages tous égaux** donnent une `StdError` de 0 et un intervalle d'un seul point : un événement trop rare pour
  se montrer dans les tirages a cet air-là.

Mesuré : 1 000 lancements pour chaque loi, chacun comptant les intervalles qui contiennent la vraie moyenne. Les comptes
d'une loi binomiale de 1 000 essais à 0,95 se trouvent entre 926 et 971 avec une probabilité de 99,9 % : chaque compte y
est, ceux de `tol` un peu plus bas, comme peut l'être une règle qui s'arrête quand l'échantillon a l'air étroit par
hasard.

| Tirages, vraie moyenne | `n = 10000` | `tol`, et le `N` moyen des lancements |
|---|---:|---:|
| uniformes sur $[0, 1)$, 0,5 | 950 | 944, `tol = 0.005`, 13 028 |
| exponentiels de taux 1, 1 | 942 | 945, `tol = 0.02`, 10 061 |
| 1 avec une probabilité de 0,01, sinon 0 ; 0,01 | 950 | 943, `tol = 0.002`, 9 915 |

Les tests de Cesia les refont avec le seed 42, et vérifient les tirages un par un contre des batches de toutes les
tailles, l'intervalle contre `stats.TTest`, et l'intégrale de $e^{-x^2}$ contre sa valeur.

### Quand il échoue

Un `Err` de sorte `"stats"`, dont le `Partial` est l'`Estimate` des tirages d'avant le mauvais, ou `missing` sous 2 :
quand `f` donne NaN ou un infini, le message nommant l'appel ou l'élément d'un batch ; quand il donne une valeur qui
n'est ni un nombre, ni `true` ni `false`, un array vide, un array après des nombres ou un nombre après des arrays ;
quand les carrés des tirages dépassent le plus grand float, environ $1{,}8 \times 10^{308}$ ; et avec `tol`, quand
`most` tirages passent avant que l'intervalle soit assez étroit, `Partial` contenant alors l'intervalle atteint.

```cesia
r = stats.MonteCarlo(() -> [1.0, 0.0 / 0.0], n = 10)
r.Error.Message -->
```

Une panic dans `f` passe au travers, comme tout bug. Un mauvais argument est une panic qui le nomme : un `f` qui n'est
pas une fonction, ni `n` ni `tol` ou les deux, un `n` qui n'est pas un entier de 2 à `most`, un `tol` qui n'est pas un
nombre fini au-dessus de 0, un `level` hors de $(0, 1)$, un `most` sous 2, ou sous 1 000 avec `tol`.

## Vitesse

Sur la machine de [Vitesse](speed.md#à-côté-des-géants), avec d'autres travaux qui y tournaient, le 2026-11-13 : la
médiane de 21 lancements de chacun, alternés, et l'intervalle à 95 % de cette médiane ; Cesia dans son build `release`,
R 4.6.2, et scipy 1.18.1 avec numpy 2.5.4. Chaque temps est pris à l'intérieur du programme, autour du travail seul.

| | Cesia | R 4.6.2 | scipy 1.18.1 |
|---|---:|---:|---:|
| `Normal(0, 1).Quantile(p)`, un appel dans une boucle | 1,13 µs (1,10 à 1,20) | `qnorm` 1,39 µs | `norm.ppf` 88 µs ; `special.ndtri` 0,35 µs |
| `Normal(0, 1).Cdf(xs)`, $10^6$ points | 70,5 ms (69,2 à 74,1) | `pnorm` 60 ms | `norm.cdf` 45 ms |
| `StudentT(10).Quantile(p)` | 61,7 µs (60,2 à 65,0) | `qt` 2,65 µs | `t(10).ppf` 77,9 µs |
| `ChiSquared(10).Quantile(p)` | 23,4 µs (22,5 à 24,3) | `qchisq` 2,55 µs | `chi2(10).ppf` 78,7 µs |
| `Beta(2, 3).Quantile(p)` | 36,7 µs (36,1 à 38,8) | `qbeta` 3,2 µs | `beta(2, 3).ppf` 82,6 µs |
| `Lm` de $10^6$ lignes sur 10 colonnes, avec sa table | 559 ms (546 à 619) | `lm` et `summary` 1 279 ms | `linalg.lstsq` et la QR des erreurs 656 ms |

**Là où Cesia gagne.** Le modèle linéaire prend moins de la moitié du temps de R, et moins que celui de scipy : les
réflexions de Householder, colonne par colonne, sont du code machine. Un seul quantile normal coûte moins que le `qnorm`
de R appelé dans une boucle de R.

**Là où les autres gagnent.** R est de 10 à 23 fois plus rapide sur les quantiles de Student, du khi-deux et de la loi
bêta : chaque pas de leur solver (le code qui résout l'équation) appelle `special.GammaInc` ou `special.BetaInc`, une
fonction avec un paramètre par défaut qui vérifie la sorte de ses arguments, et le JIT ne fait pas encore de code
machine d'un tel appel, si bien que le solver tourne dans l'interpréteur, environ 10 µs par pas pour cinq ou six pas.
numpy est plus rapide sur un array entier de cdf normales, avec ses boucles en C.

**Monte-Carlo.** Sur la même machine, le 2026-11-14 : les temps de Cesia sont les médianes de 21 lancements et
l'intervalle à 95 % de chacune ; numpy 2.5.4 avec scipy 1.18.1, et Octave 11.3.0, les médianes de 5 lancements, dans la
même session. Chaque temps est pris à l'intérieur du programme, autour du travail seul. Le `tinv` d'Octave fait partie
de son package statistics, pas installé ici : son quantile vient du `betaincinv` du cœur d'Octave, comme le calcule
`tinv`.

| | Cesia | numpy et scipy | Octave 11.3 |
|---|---:|---:|---:|
| $10^6$ tirages en un batch, et leur intervalle | 9,2 ms (9,1 à 9,6) | 10,1 ms | 33,1 ms |
| dont les tirages, `num.Uniform`, `rng.random`, `rand` | 4,4 ms (4,0 à 4,6) | 4,7 ms | 11,3 ms |
| l'intervalle de $10^6$ tirages déjà faits | 19,4 ms la première fois, le JIT chargé et compilant ; 4,0 ms après | 5,4 ms | 38,5 ms |
| $10^7$ tirages par batches de $10^5$, le travail de `MonteCarlo` seul | 40,2 ms (39,3 à 42,0) | | |
| $10^6$ tirages un par un, un appel de `f()` chacun, et leur intervalle | 24,8 ms (23,8 à 25,6) | 149 ms, `np.fromiter` | 6 714 ms, `arrayfun` |
| la cell ci-dessus, `tol = 1e-4` : 15,6 millions de tirages de $e^{-u^2}$ par batches de $10^5$ | 676 ms (665 à 708) | 244 ms | 1 035 ms |

Le travail de `MonteCarlo` seul a été mesuré sur un batch fait une fois et redonné par `f`, pour qu'aucun tirage ne soit
fait.

**Là où Cesia gagne.** Les tirages uniformes : `num.Uniform` remplit son array en une seule boucle d'OCaml, le pas de
SplitMix64 comme celui de `random.Float`, environ 3,5 ns par tirage, aussi vite que le générateur de numpy. Les tirages
un par un : `f()` et le tirage de `random.Float()` qu'il contient sont du code machine, si bien qu'un appel de `f` pour
chacun coûte un sixième du générateur de Python et un 270e de l'`arrayfun` d'Octave. Le travail de `MonteCarlo`
lui-même, ses deux passages sur chaque bloc en code machine, environ 4 ns par tirage, coûte moins que la moyenne et
l'écart type de numpy. Et ni numpy ni Octave n'ont la boucle de `tol`.

**Là où les autres gagnent.** La cell prend 2,8 fois le temps de numpy, même si elle bat Octave : un tirage de
$e^{-u^2}$ coûte 33 ns dans Cesia, 15 dans numpy, sur des batches de $10^5$ qu'un seul cœur prend. L'essentiel vient de
`x ^ 2`, qui appelle le `pow` de la bibliothèque C pour chaque élément, 23 ns, là où numpy met au carré, `x * x`, en 0,5
ns. `pow` donne à chaque élément les bits que `^` donne à ce nombre seul ; un carré par `x * x`, arrondi une seule fois,
diffère du `pow(x, 2)` de la glibc dans le dernier bit d'environ un double au hasard sur 2 300. `math.Exp` prend 7,2 ns
par élément, l'`exp` de numpy 6,2. Avant le 2026-11-14, `num.Uniform` était une boucle de Cesia qui appelait
`random.Float` pour chaque nombre, 40 ns chacun, `x ^ 2` mettait chaque élément dans une box (un bloc de mémoire à
part), 110 ns, `-` et `math.Exp` le mettaient dans une box à l'entrée et à la sortie d'une closure (une fonction qui
garde les variables de l'endroit où elle est écrite), et un appel `f()` restait dans l'interpréteur : la cell prenait 2
912 ms, les tirages un par un 118 ms, $10^6$ tirages 50 ms, les médianes de 21 lancements du binaire de main à côté de
ceux-ci.

`use std/stats` ajoute 1,2 ms au démarrage d'un programme une fois que le cache des packages chargés le contient (4,2 ms
contre 3,0 pour un programme qui affiche 1), 11,8 ms la première fois (14,8 ms) : ses 3 100 lignes, et celles de
std/special, std/frame et std/num, dont il se sert ; 4,21 ms contre 4,20 pour le binaire de main avant `MonteCarlo`, et
14,85 contre 14,59 la première fois, dans le bruit. Un programme sans lui démarre comme avant : 3,03 ms contre 3,08 pour
le binaire de main. Ce sont les médianes de 21 lancements, alternés, le 2026-11-13.

## Sécurité

Les fonctions et les méthodes ne lisent que leurs arguments : aucun fichier, aucun réseau ni aucune permission n'est
touché. Chaque boucle est bornée : les séries et les fractions continues s'arrêtent à un nombre fixe de termes (2 000 à
20 000) même si elles n'ont pas convergé, un quantile après 100 pas de son solver, un quantile discret une fois son
encadrement fermé, un tirage gamma par son rejet, qui accepte plus de 95 % de ses essais ; aucun argument ne peut faire
tourner un appel sans fin. Un NaN traverse chaque formule jusqu'à un NaN, un infini jusqu'à la bonne limite. Un texte,
un `missing` ou une autre valeur là où un nombre est attendu est une panic qui le nomme, avant tout calcul ; un champ
d'une loi hors de son domaine est une panic qui nomme la loi, le champ et la valeur ; une valeur manquante dans les
données d'un test ou d'un modèle est un `Err` qui nomme sa place. La taille d'un `Sample` est vérifiée avant que quoi
que ce soit soit fait, et son array, comme tout array, compte dans la limite de mémoire du programme : au-delà, le
programme s'arrête avec son message. Aucun paramètre ne fait grandir une table ou une matrice sans limite : une loi de
comptes tire à travers son quantile dès que sa table dépasserait 65 536 comptes, et la matrice exacte de
Kolmogorov–Smirnov reste d'au plus 681 × 681 (elle sert jusqu'à $n D^2 = 7{,}24$, avec $n \le 16\,000$).

`stats.MonteCarlo` ne lit que ce que `f` donne. Ses tirages sont bornés : `n` est vérifié contre `most` avant le premier
appel, et avec `tol` les tirages s'arrêtent à `most`, $10^9$ par défaut, avec un `Err` qui contient l'estimation
atteinte, si bien qu'aucun `tol` ne peut le faire tourner sans fin ; `cells.Stop` l'arrête en un bloc de tirages, comme
toute boucle de code Cesia. Il ne garde aucun tirage : les tirages un par un passent par un array de 1 000 floats, et un
batch est lu là où `f` l'a fait, sans copie, si bien que sa mémoire est celle de `f`. Chaque tirage un par un est testé
à son arrivée, si bien que `f` n'est plus appelé après une valeur qui n'est pas un nombre ; un NaN ou un infini est
trouvé par les sommes de son bloc et nommé, comme le sont un array vide, qui ne finirait jamais les tirages, et une
somme de carrés au-delà du plus grand float. Une panic dans `f` passe au travers telle quelle.

## Pour aller plus loin

- Student. "The probable error of a mean". *Biometrika* 6(1):1–25, 1908. <https://doi.org/10.2307/2331554>.
- B. L. Welch. "The generalization of 'Student's' problem when several different population variances are involved".
  *Biometrika* 34(1–2):28–35, 1947. <https://doi.org/10.1093/biomet/34.1-2.28>.
- F. E. Satterthwaite. "An approximate distribution of estimates of variance components". *Biometrics Bulletin*
  2(6):110–114, 1946. <https://doi.org/10.2307/3002019>.
- Frank Wilcoxon. "Individual comparisons by ranking methods". *Biometrics Bulletin* 1(6):80–83, 1945.
  <https://doi.org/10.2307/3001968>.
- H. B. Mann, D. R. Whitney. "On a test of whether one of two random variables is stochastically larger than the
  other". *The Annals of Mathematical Statistics* 18(1):50–60, 1947. <https://doi.org/10.1214/aoms/1177730491>.
- George Marsaglia, Wai Wan Tsang, Jingbo Wang. "Evaluating Kolmogorov's distribution". *Journal of Statistical
  Software* 8(18), 2003. <https://doi.org/10.18637/jss.v008.i18>.
- Z. W. Birnbaum, Fred H. Tingey. "One-sided confidence contours for probability distribution functions". *The Annals
  of Mathematical Statistics* 22(4):592–596, 1951. <https://doi.org/10.1214/aoms/1177729550>.
- Karl Pearson. "On the criterion that a given system of deviations from the probable in the case of a correlated
  system of variables is such that it can be reasonably supposed to have arisen from random sampling". *Philosophical
  Magazine* 50(302):157–175, 1900. <https://doi.org/10.1080/14786440009463897>.
- F. Yates. "Contingency tables involving small numbers and the chi-squared test". *Supplement to the Journal of the
  Royal Statistical Society* 1(2):217–235, 1934. <https://doi.org/10.2307/2983604>.
- R. A. Fisher. "Frequency distribution of the values of the correlation coefficient in samples from an indefinitely
  large population". *Biometrika* 10(4):507–521, 1915. <https://doi.org/10.2307/2331838>.
- Tony F. Chan, Gene H. Golub, Randall J. LeVeque. "Algorithms for computing the sample variance: analysis and
  recommendations". *The American Statistician* 37(3):242–247, 1983. <https://doi.org/10.1080/00031305.1983.10483115>.
- B. P. Welford. "Note on a method for calculating corrected sums of squares and products". *Technometrics*
  4(3):419–420, 1962. <https://doi.org/10.1080/00401706.1962.10490022>.
- A. Neumaier. "Rundungsfehleranalyse einiger Verfahren zur Summation endlicher Summen". *Zeitschrift für Angewandte
  Mathematik und Mechanik* 54(1):39–51, 1974. <https://doi.org/10.1002/zamm.19740540106>. La somme compensée de
  `stats.MonteCarlo`.
- Y. S. Chow, Herbert Robbins. "On the asymptotic theory of fixed-width sequential confidence intervals for the mean".
  *The Annals of Mathematical Statistics* 36(2):457–462, 1965. <https://doi.org/10.1214/aoms/1177700156>.
- Nitis Mukhopadhyay, Sujay Datta. "On sequential fixed-width confidence intervals for the mean and second-order
  expansions of the associated coverage probabilities". *Annals of the Institute of Statistical Mathematics*
  48(3):497–507, 1996. <https://doi.org/10.1007/BF00050850>. La règle et le théorème de Chow et Robbins,
  réénoncés dans son introduction.
- Gene H. Golub, Charles F. Van Loan. *Matrix Computations*, quatrième édition. Johns Hopkins University Press, 2013.
  Chapitre 5, la QR de Householder et les moindres carrés.
- B. D. McCullough. "Assessing the reliability of statistical software: Part I". *The American Statistician*
  52(4):358–366, 1998. <https://doi.org/10.1080/00031305.1998.10480597>. Le LRE, les chiffres qui s'accordent.
- NIST, Statistical Reference Datasets, la régression linéaire : <https://www.itl.nist.gov/div898/strd/lls/lls.shtml>.
- J. W. Longley. "An appraisal of least squares programs for the electronic computer from the point of view of the
  user". *Journal of the American Statistical Association* 62(319):819–841, 1967.
  <https://doi.org/10.1080/01621459.1967.10500896>.
- E. B. Wilson, M. M. Hilferty. "The distribution of chi-square". *Proceedings of the National Academy of Sciences*
  17(12):684–688, 1931. <https://doi.org/10.1073/pnas.17.12.684>. Le départ du quantile gamma.
- George Marsaglia, Wai Wan Tsang. "A simple method for generating gamma variables". *ACM Transactions on Mathematical
  Software* 26(3):363–372, 2000. <https://doi.org/10.1145/358407.358414>.
- G. E. P. Box, Mervin E. Muller. "A note on the generation of random normal deviates". *The Annals of Mathematical
  Statistics* 29(2):610–611, 1958. <https://doi.org/10.1214/aoms/1177706645>.
- Milton Abramowitz, Irene A. Stegun, éditeurs. *Handbook of Mathematical Functions*. National Bureau of
  Standards, 1964. La formule 6.1.33, la série de $\log \Gamma$.
- W. J. Cody. "Rational Chebyshev approximations for the error function". *Mathematics of Computation* 23(107):631–637,
  1969. <https://doi.org/10.1090/S0025-5718-1969-0247736-4>.
- Michael J. Wichura. "Algorithm AS 241: The percentage points of the normal distribution". *Applied Statistics*
  37(3):477–484, 1988. <https://doi.org/10.2307/2347330>.
- Armido R. DiDonato, Alfred H. Morris. "Computation of the incomplete gamma function ratios and their inverse". *ACM
  Transactions on Mathematical Software* 12(4):377–393, 1986. <https://doi.org/10.1145/22721.23109>.
- Armido R. DiDonato, Alfred H. Morris. "Algorithm 708: Significant digit computation of the incomplete beta function
  ratios". *ACM Transactions on Mathematical Software* 18(3):360–373, 1992. <https://doi.org/10.1145/131766.131776>.
- N. M. Temme. "The asymptotic expansion of the incomplete gamma functions". *SIAM Journal on Mathematical Analysis*
  10(4):757–766, 1979. <https://doi.org/10.1137/0510071>.
- NIST Digital Library of Mathematical Functions, chapitre 8, *Incomplete Gamma and Related Functions* : §8.9 (les
  fractions continues), §8.12 (les développements uniformes), §8.17 (la fonction bêta incomplète).
  <https://dlmf.nist.gov/8>.
- I. J. Thompson, A. R. Barnett. "Coulomb and Bessel functions of complex arguments and order". *Journal of
  Computational Physics* 64(2):490–509, 1986. <https://doi.org/10.1016/0021-9991(86)90046-X>. La méthode de Lentz
  modifiée pour les fractions continues.
- David Goldberg. "What every computer scientist should know about floating-point arithmetic". *ACM Computing Surveys*
  23(1):5–48, 1991. <https://doi.org/10.1145/103162.103163>. Le théorème 4, $\log(1 + x)$ sans annulation.
- Boost.Math, ses données de test pour les fonctions spéciales : <https://github.com/boostorg/math/tree/develop/test>.


## La suite

Le chapitre suivant, [JSON et CSV](json.md), lit les données d'autres programmes et les écrit pour eux.
