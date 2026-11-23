# Cells

Un *notebook* (un cahier de calcul) est du code coupé en *cells* (des cellules), des morceaux qui tournent un par un,
chacun avec son résultat en dessous : Jupyter et Pluto.jl sont des notebooks. En Cesia, un notebook est un fichier `.ce`
normal, coupé par des commentaires, et [std/cells] le fait tourner : les cells qui dépendent d'une cell tournent de
nouveau quand elle tourne, comme dans un notebook *réactif* (qui suit de lui-même les changements). Le fichier reste un
programme : `cesia run` le lance depuis le haut, et donne ce que donnent les cells. Cemacs dessine les résultats sous
les cells ; cette page décrit le moteur en dessous, pour n'importe quel outil.

## Un fichier de cells

Une ligne qui ne contient qu'un commentaire commençant par `%%` commence une cell, et le reste du commentaire est son
titre. Les lignes avant la première forment la première cell, d'habitude celle des uses (les lignes `use` qui nomment
les packages, le code groupé sous un nom, dont le fichier se sert) :

```cesia norun
use std/io
use std/list

(* %% Data *)
n = 1000
xs = [i * i for i in 1..n]

(* %% Mean *)
mean = list.Mean(xs)
io.Print("mean of $n squares")
mean
```

Pour `cesia run`, `cesia check` et `cesia fmt`, un marqueur est un commentaire comme les autres : `cesia fmt` le laisse
sur sa ligne.

[cells.Parse] donne les cells d'une source, chacune avec son Title (son titre), sa première et sa dernière ligne, From
et To, comptées à partir de 1, et sa Source, le marqueur compris, de sorte que la ligne k d'une cell est la ligne
`From + k - 1` du fichier. Quand un marqueur ouvre le fichier, la première cell est vide, avec To = From - 1, de sorte
que la cell des uses est toujours la première :

```cesia
use std/cells
source = "use std/io\n(* %% Data *)\nn = 3\n(* %% Twice *)\nio.Print(n * 2)"
[[c.Title, c.From, c.To] for c in cells.Parse(source)] -->
```

## Ce qu'une cell lit et définit

Une cell *définit* ce que ses instructions de premier niveau nomment : `x = ...`, `[q, r] = ...`, ses fonctions, ses
structs et ses interfaces, et les noms de ses uses. Elle *lit* les noms que son code et le corps de ses fonctions
utilisent sans les définir ; un paramètre ou une variable locale d'une fonction n'est pas une lecture. [cesia.Reads] les
trouve, avec le propre resolver du compilateur, le code qui décide de ce qu'un nom veut dire quand un programme tourne :
il est exact par construction, et ses tests le comparent avec ce que `cesia check` dit de chaque programme de test de
Cesia, entier et coupé en deux.

```cesia
use std/cesia
[r.Name for r in cesia.Reads("defn f(a)\n  a * rate\nend\ntotal = f(k)").Value] -->
```

[cells.Analyse] donne, pour chaque cell, ses Defines (ce qu'elle définit), ses Reads (ce qu'elle lit) et ses Errors (ses
erreurs), chaque erreur avec sa Line et sa Column (sa ligne et sa colonne) dans le fichier. Trois règles font qu'un
fichier veut dire la même chose en cells et en programme :

1. Un nom n'est défini que par une seule cell. Deux cells qui définissent `x` sont toutes les deux en erreur, chacune
   nommant l'autre.
2. Une cell ne lit que des noms que les cells au-dessus d'elle définissent. Une cell qui lit un nom défini plus bas dit
   quelle cell remonter. Il n'y a donc pas de cycle : l'ordre du fichier est un ordre dans lequel les faire tourner.
3. Un nom qu'aucune cell ne définit est l'erreur `Name "k" doesn't exist.` là où il est lu, et un package de `std/`
   nommé
   sans son use dit quel use écrire dans la première cell.

Deux autres en découlent. Une méthode va dans la cell de sa struct, comme elle va dans le package de sa struct. Et une
boucle ou un bloc d'une cell qui donne une valeur à un nom qu'une autre cell définit est une erreur : sous `cesia run`,
le fichier entier est un seul scope (une seule portée des noms), et la boucle changerait ce nom pour les cells d'en
dessous. La variable d'une boucle `for`, et un nom auquel une cell ne donne une valeur que dans un bloc, restent dans
leur cell : une cell plus bas qui en lit un se voit dire de lui donner sa valeur en haut de sa cell.

```cesia
use std/cells
a = cells.Analyse(cells.Parse("(* %% A *)\nx = y + 1\n(* %% B *)\ny = 1"))
a[2].Errors[1].Message -->
```

## Ce qui tourne de nouveau

Après que la cell c a tourné, ou a été modifiée puis lancée, [cells.ToRun] donne les cells à faire tourner, dans l'ordre
du fichier : c, puis chaque cell qui lit, directement ou à travers d'autres cells, un nom que c définit. Les autres
gardent leurs résultats. La première cell, celle des uses, les fait toutes tourner de nouveau.

```cesia
use std/cells
a = cells.Analyse(cells.Parse("(* %% A *)\nx = 1\n(* %% B *)\ny = 2\n(* %% C *)\nz = x + y"))
cells.ToRun(a, 2) -->
cells.ToRun(a, 3) -->
```

C'est le modèle de Pluto.jl, dont le README dit : « When you change a variable, Pluto automatically re-runs the cells
that refer to it » (quand vous changez une variable, Pluto relance de lui-même les cells qui s'y réfèrent), et « deleted
code leaves no trace » (le code supprimé ne laisse aucune trace). Les noms d'une cell supprimée sont oubliés avec
[cells.Forget], et les cells qui les lisent montrent l'erreur de la troisième règle. Une différence : Pluto laisse les
cells dans n'importe quel ordre, et Cesia non, par la deuxième règle, pour que `cesia run` calcule ce que les cells
montrent.

Une cell qui tourne de nouveau répète ce qu'elle fait en plus de sa valeur : elle affiche de nouveau, elle écrit de
nouveau ses fichiers. Rien ne le cache : une cell qui doit écrire une seule fois gagne à ne tourner qu'une fois, exprès.

## La session

[cells.Session] démarre une session sur un fichier : un seul processus Cesia, `cesia run --cells file.ce`, qui ne lance
rien du fichier et attend des cells. [cells.Run] lui donne une cell et l'attend : un Ok avec Output, les lignes qu'elle a
affichées, Value, ce que montre sa dernière expression, Shown, ce que [cells.Show] a montré, Error, ou missing, avec la
Line du fichier et le Text de l'erreur tel que `cesia run` le montre, et Seconds, le temps qu'elle a tourné. Avant qu'une
cell tourne, les noms qu'elle définit sont oubliés, pour qu'une cell qui échoue ne laisse aucune ancienne valeur derrière
elle. Une cell dont le From vaut 0 est du code tapé à un prompt (une ligne où l'on tape du code à côté du programme) à côté
des cells, qu'aucune ligne du fichier ne contient : ses erreurs nomment `<prompt>`.

```cesia norun
use std/cells
use std/io
use std/result
use std/sys

defn Main()
  cs = cells.Parse(sys.Read("mean.ce")?)
  s = cells.Session("mean.ce")?
  for c in cs
    r = cells.Run(s, c)?
    io.Print(r.Output, " ", r.Value)
  end
  io.Print(cells.Variables(s)?)
  result.Ok(missing)
end
```

Une cell montre la valeur de sa dernière expression, et [cells.Show] en montre plus en chemin : un graphe, un tableau, une
matrice ou le texte de n'importe quelle valeur, à sa place parmi ce que la cell affiche, comme `display` dans Jupyter. Deux
graphes dans une cell :

```cesia norun
use std/cells
use std/io
use std/math
use std/plot

(* %% Sine and cosine *)
t = [k / 10.0 for k in 0..62]
cells.Show(plot.Line(t, [math.Sin(x) for x in t]))
io.Print("then the cosine")
plot.Line(t, [math.Cos(x) for x in t])
```

Sous la cell viennent le graphe du sinus, la ligne qu'elle a affichée (« then the cosine »), puis le graphe du cosinus.
Chaque partie de Shown est {After, Value} : After compte les lignes d'Output affichées avant elle, et Value est comme le
Value de la cell, un graphe avec sa propre Key pour [cells.Scene], ou de Kind `"error"`, avec Text, pour un graphe qui ne
peut pas être dessiné. `cells.Show(x)` rend x, pour tenir dans une ligne qui continue avec x ; hors d'une session, comme
sous `cesia run`, il ne montre rien et rend seulement x. La page de [cells.Html] montre les parties dans le même ordre.

Les cells tournent au niveau du fichier, comme le prompt de `cesia run --repl` fait tourner du code : chacune voit les
noms que les cells d'avant ont définis, et les uses écrits au-dessus d'elle. Elles tournent comme le ferait le
programme, pas sous le hook du debugger (le crochet qu'il pose sur chaque pas), qui coûte environ dix fois plus :
fib(35) dans une cell prend 56,8 ms, le même fichier sous `cesia run` 56,8 ms aussi (médianes de 21 lancements). Leurs
erreurs et les appels qui y mènent nomment le fichier et ses lignes. Une cell relancée qui définit une fonction avec le
même code qu'avant garde le code machine que le JIT a fait avec elle : la cell de résolution d'un notebook de Lorenz,
`lorenz` définie de nouveau et résolue de nouveau, prend 2,2 ms au lieu de 22,7, comme le dit
[Comment Cesia fonctionne](internals.md#les-appels-à-travers-une-valeur) ; une fonction qui a changé, qui lit un nom d'une
cell relancée depuis, comme `rho` une fois sa cell modifiée, ou qui appelle une autre fonction de sa cell, est refaite.

Une session n'a que les permissions de son `allow`, tel que `--allow` les prend :
`cells.Session("mean.ce", allow = ["read"])`. Le programme qui la démarre a besoin de la permission `exec` de ce
`cesia`, [cesia.Binary].

Ce que montre une valeur :

| Valeur | Montre |
|---|---|
| un graphique de [std/plot] | `{Kind: "graph", Scene, Key}` : sa scène, [plot.Scene] à la largeur que Run donne, 640 pixels par défaut, et 400 de haut ; un graphique que std/plot ne sait pas dessiner est l'erreur de la cell, avec le message de std/plot |
| une animation de [plot.Frames] | `{Kind: "graph", Scene, Key, Frames, Fps}` : la scène de sa première image, le nombre de ses images et leur rythme |
| un graphique 3D de [plot.Surface] ou [plot.Line3] | `{Kind: "graph", Scene, Key, View}` : sa scène, et `View`, le `[az, el]` de son code |
| un frame de [std/frame], une table de colonnes | `{Kind: "table", Columns, Rows, Count}` : ses 20 premières lignes, en textes, et son nombre de lignes |
| un array (une suite de nombres rangés côte à côte) ou une matrice | `{Kind: "array", Shape, Rows}` : sa forme et ses 10 × 10 premières valeurs, en textes |
| une struct d'au plus 20 champs, comme un `stats.Test` | `{Kind: "table", Columns, Rows, Count}` : une ligne par champ public, son nom et sa valeur en texte, `value.Text(v, 80)`, qui ne fait d'une longue liste que ses 80 caractères, de sorte qu'un modèle de $10^6$ lignes s'affiche tout de suite, et d'une matrice de plus de 1000 valeurs sa taille ; un `Ok` d'une struct montre la struct |
| tout le reste | `{Kind: "text", Text}` : son texte, tel que `io.Print` l'écrit, coupé à 20 000 caractères par `value.Text` |

Avant que chaque cell tourne, [std/random] repart du seed (le nombre dont part le générateur) de la session et du titre
de la cell, comme `cesia test` démarre chaque test : une cell qui tourne de nouveau tire les mêmes nombres, quoi qu'il
ait tourné avant elle, un changement dans une cell ne change les tirages d'aucune autre, et [cells.Html] donne les
nombres que Cemacs a montrés pour le même seed. Une cell renommée tire d'autres nombres ; `cesia run` sur le fichier, un
seul flux depuis le haut, tire d'autres nombres que ses cells.

Les valeurs restent dans la session : [cells.Variables] donne pour chaque nom son Name, son Type, sa Size (sa taille) et
sa Preview (un aperçu), quelques textes, et ne copie jamais un grand array : chaque texte est fait par
`value.Text(v, 80)`, qui s'arrête à 80 caractères, de sorte qu'une session qui garde un modèle de $10^6$ lignes répond
en un dixième de milliseconde. La session garde les 64 derniers graphiques que ses lancements ont montrés, et [cells.Scene] en
redessine un à une autre largeur, par sa Key (sa clé), pour un panneau qui a changé de largeur, une autre image d'une
animation, `frame = k`, ou un graphique 3D tourné vers une autre vue, `view = [az, el]` : un éditeur demande chaque image
au moment de la montrer, pour qu'une animation ne traverse jamais le pipe (le tuyau entre les deux processus) en entier,
et une image de la courbe de Lorenz, 5 000 points, revient en 10 ms environ ; il demande chaque vue quand un graphique 3D
tourne, et une surface de 100 par 100 quads revient en environ 14 ms, les places de ses points à l'écran, ses quads dans
l'ordre où les dessiner. La session lit ses réponses par morceaux et joint chaque ligne une seule fois, si bien qu'une
longue réponse coûte sa longueur, pas son carré. [cells.Rows] donne les
lignes d'un frame, d'une matrice ou d'une liste, de l'une à une autre, en textes, pour qu'un visualiseur lise une grande
valeur un écran à la fois.

[cells.Stop] arrête la cell qui tourne : sa fiber (un fil d'exécution léger de Cesia) est annulée à sa prochaine attente
ou à son prochain checkpoint (un point où le programme s'arrête un instant pour vérifier ce qu'on lui demande), son Run
donne l'erreur `Stopped.`, et la session et les noms définis avant restent. Une session qui ne répond pas dans les
2 secondes, comme une cell à l'intérieur d'un long appel natif, est arrêtée et une nouvelle démarre : la session que
donne Stop a alors Restarted à true, et les cells tournent de nouveau depuis le haut.

## Sliders

Un *slider* (un curseur) est une barre avec un bouton que l'on fait glisser pour changer un nombre. Dans une cell à lui,
chaque ligne `name = cells.Slider(value, min, max)` donne à un nom un nombre qu'un éditeur fait bouger : Cemacs dessine
le slider sous la ligne, et un mouvement écrit le nouveau nombre dans le fichier, puis ne relance que les cells qui
lisent ce nom.

```cesia norun
use std/cells
use std/ode
use std/result

(* %% Parameters *)
rho = cells.Slider(28.0, 0.0, 50.0, step = 0.5)
n = cells.Slider(3, 1, 10)

(* %% Lorenz *)
lorenz(t, y) = [10.0 * (y[2] - y[1]), y[1] * (rho - y[3]) - y[2], y[1] * y[2] - 8.0 / 3.0 * y[3]]
s = result.Unwrap(ode.Solve(lorenz, [0.0, 50.0], [1.0, 1.0, 1.0]))
```

Le fichier fait foi : après un mouvement, `cesia run`, la fenêtre et la page de [cells.Html] lisent le même nombre. Un
slider est un simple appel de fonction, et sous `cesia run`, [cells.Slider] vérifie ses nombres et donne la valeur :

```cesia
use std/cells
cells.Slider(28.0, 0.0, 50.0, step = 0.5) -->
cells.Slider(3, 1, 10) -->
```

Deux règles, en plus des trois des cells, font d'un slider quelque chose qu'un éditeur peut faire bouger sans deviner :

4. Une cell qui a un slider ne contient que des sliders, un par ligne, et des commentaires. Un slider posé à côté d'autre
   code ferait tourner sa cell de nouveau à chaque mouvement, et ce que ce code calcule deviendrait périmé.
5. Un slider prend des nombres écrits dans le fichier, négatifs aussi, comme `28.0`, `-1.5` ou `1e-3` : un éditeur
   réécrit le nombre de la valeur, et dessine le slider avant que rien ne tourne. `cells.Slider(1.0, 0.0, top)` est
   l'erreur `cells.Slider takes numbers written in the file, not expressions.`

[cells.Analyse] trouve les sliders par le nom que donne le `use std/cells` de la première cell, `cells` ou le nom après
`as`, et donne à chaque cell ses Sliders : chacun avec son Name (son nom), sa Line (sa ligne), la Column et la End (la
première et la dernière colonne) du nombre de la valeur sur cette ligne, comptées à partir de 1, sa Value, son Min, son
Max et son Step : des Ints (des nombres entiers) pour un slider d'Ints, sinon des Floats (des nombres à virgule), tels
que `cesia run` les lit.

```cesia
use std/cells
a = cells.Analyse(cells.Parse("use std/cells\n(* %% P *)\nrho = cells.Slider(28.0, 0.0, 50.0, step = 0.5)"))
a[2].Sliders[1] -->
cells.Analyse(cells.Parse("use std/cells\n(* %% P *)\nrho = cells.Slider(60.0, 0.0, 50.0)"))[2].Errors[1].Message -->
```

Les nombres sont vérifiés aux deux endroits, avec le même texte : [cells.Slider] fait une panic et [cells.Analyse] donne
l'erreur quand un nombre n'est pas fini, quand le min n'est pas sous le max, quand la valeur est en dehors, quand le min,
le max ou le step (le pas entre deux positions) a plus de 18 décimales (le texte d'une position a les leurs), quand
max - min est trop large pour un nombre (un Int tient sur 63 bits), quand le step n'est pas au-dessus de 0 ou est plus
large que max - min, et au-delà de $10^6$ steps. Le step vaut par défaut (max - min) / 100, avec deux décimales de plus
que min et max, de sorte que 0.0 à 0.7 avance par 0.007 ; ou 1 quand value, min et max sont des Ints, et un tel slider
donne des Ints. Une valeur écrite hors des steps reste telle quelle jusqu'à ce qu'elle bouge.

Les positions d'un slider sont min + k × step, pour k un nombre entier, calculées et jamais additionnées, et la dernière
est la plus grande qui ne dépasse pas max, comme dans un range input HTML (le champ en forme de barre d'une page web).
[cells.Snap] donne la position la plus proche d'un nombre, et avance de plus de steps quand on le lui demande : son Text
est ce que le fichier écrit, avec les décimales de min et du step, de sorte que des steps de 0.1 écrivent `0.3` et non
`0.30000000000000004`, et sa Value est le nombre que `cesia run` relit dans ce texte.

```cesia
use std/cells
s = {Value: 0.0, Min: 0.0, Max: 1.0, Step: 0.1}
cells.Snap(s, 0.31) -->
cells.Snap(s, 0.31, steps = 1).Text -->
```

[cells.Set] donne à un slider sa nouvelle valeur dans une session : ramenée au step le plus proche comme le fait Snap,
vérifiée contre le min et le max du slider, et donnée au nom **en place** (le nom garde sa place, sans être défini de
nouveau). Une cell qui tourne de nouveau oublie d'abord les noms qu'elle définit, si bien qu'une fonction d'une autre
cell qui lit l'un d'eux le trouverait sans valeur jusqu'à ce que sa cell ait tourné de nouveau ; Set change le nombre que
tient le nom, et la fonction lit le nouveau tout de suite. Le code machine d'une boucle qui le lit lit chaque nouveau
nombre dans un slot, si bien qu'il garde son code : un pas du slider de `rho` dans le notebook de Lorenz, Set puis la cell
de résolution relancée, prend 2,6 ms au lieu de 24, comme le dit
[Comment Cesia fonctionne](internals.md#les-appels-à-travers-une-valeur). Set donne la valeur, son Text, le nombre tel que le fichier
l'écrit, que Snap donne, et ToRun, les cells à relancer : celles qui lisent le nom, directement ou par d'autres cells, dans l'ordre du fichier. La cell du slider n'en fait jamais
partie, puisqu'elle ne contient rien d'autre.

```cesia norun
use std/cells
use std/io
use std/result
use std/sys

defn Main()
  cs = cells.Parse(sys.Read("lorenz.ce")?)
  a = cells.Analyse(cs)
  s = cells.Session("lorenz.ce")?
  for c in cs
    cells.Run(s, c)?
  end
  moved = cells.Set(s, a, "rho", 31.5)?
  for i in moved.ToRun
    cells.Run(s, cs[i])?
  end
  result.Ok(missing)
end
```

À côté d'un slider d'ipywidgets dans Jupyter, qui rappelle sa fonction à chaque mouvement, le `solve_ivp` de scipy
1.18.1 sur le même système, RK45 aux mêmes tolérances, résolu de nouveau au nouveau `rho` : 136,4 ms (135,6 à 138,9) par
pas, la résolution seule, contre **2,66 ms** (2,64 à 2,67) pour Set et la cell qu'il donne ; la moyenne de 20 pas après
un premier, à l'intérieur de chaque programme, la médiane de 101 lancements alternés et l'intervalle à 95 % de cette
médiane, sur la machine de [Vitesse](speed.md#à-côté-des-géants), le 2026-11-19.

Set est un Err pour un nom qui n'est pas un input de l'analyse, une valeur qui n'est pas un nombre fini ou qui sort du
min et du max du slider, et une session qui n'a pas encore de valeur pour le nom : la cell du slider tourne d'abord,
comme [cells.ToRun] la donne.

La page de [cells.Html] montre chaque slider sous sa cell, avec sa valeur telle que le fichier l'écrit, sur une barre
qui ne bouge pas : la page n'a pas de script, et rien n'y pourrait relancer ce qui lit le slider.

Un slider fait confiance à peu de chose. [cells.Analyse] lit le texte du fichier sans jamais faire de panic : les nombres
qu'un slider ne pourrait pas compter ou écrire sont des erreurs du fichier, comme plus haut. La session ne donne au nom d'un
slider qu'un nombre fini, et seulement quand ce nom tient déjà un nombre : jamais une fonction, dont les appels ont pu
être compilés avec ce nombre, ni un texte. [cells.Set] vérifie le nom, le nombre et l'intervalle avant de demander. Ce
qu'un éditeur écrit dans le fichier, c'est à l'éditeur de le vérifier : voir
[Cemacs](https://www-celestial.github.io/cemacs/cells.html).

## Inputs

Les autres *inputs* (les champs d'un formulaire) s'écrivent comme un slider : une liste où choisir, une case à cocher,
un champ où taper, et un jour. Chacun est un simple appel de fonction qui donne sa valeur sous `cesia run`, et Cemacs le
dessine sous sa ligne, dans des cases de la police du code, noir sur blanc :

```cesia norun
use std/cells

(* %% Place and day *)
year  = cells.Choice(2026, [2025, 2026, 2027])
zone  = cells.Choice("GMT-5", ["GMT-6", "GMT-5", "GMT-4"])
day   = cells.Date("2026-11-23")
place = cells.Field("40.76, -73.984")
high  = cells.Field(50)
rho   = cells.Slider(28.0, 0.0, 50.0, step = 0.5)
bold  = cells.Check(false, label = "Bold line")
```

```
year   [ 2026        v ]
zone   [ GMT-5       v ]
day    [ 2026-11-23  v ]
place  [ 40.76, -73.984           ]
high   [ 50                       ]
rho    ----------o--------  28.0
[ ] Bold line
```

| Fonction | Donne sous `cesia run` | Dans Cemacs |
|---|---|---|
| [cells.Choice] `(value, options)` | value, l'une des options : des textes ou des nombres finis, au plus 1 000 | Entrée ou un clic ouvre la liste, les flèches s'y déplacent, Entrée choisit |
| [cells.Check] `(value, label = missing)` | value, `true` ou `false` | Espace ou un clic écrit l'autre |
| [cells.Field] `(value)` | value telle qu'écrite : un texte, un Int ou un Float | ce qui est tapé dans la case est donné à Entrée ; un champ de nombre ne prend qu'un nombre |
| [cells.Date] `(value)` | la date de [std/date] d'un jour écrit `YYYY-MM-DD`, à minuit en UTC | les flèches changent l'année, le mois ou le jour sous le curseur, Entrée le donne |

```cesia
use std/cells
cells.Choice("GMT-5", ["GMT-6", "GMT-5", "GMT-4"]) -->
cells.Check(false, label = "Bold line") -->
cells.Field("40.76, -73.984") -->
cells.Field(50) -->
cells.Date("2026-11-23") -->
```

Un formulaire est le même notebook qu'avant : quand un input change, sa nouvelle valeur est écrite dans le fichier, à la
place de l'ancienne, et seules les cells qui lisent son nom sont relancées, tout de suite, comme après le mouvement d'un
slider ; une cell lourde montre qu'elle tourne, et `C-g` l'arrête. Un champ attend Entrée : aucune cell ne tourne à
chaque lettre tapée.

Les règles 4 et 5 valent pour tout input, un slider aussi : une cell qui a un input ne contient que des inputs, un par
ligne, et des commentaires, et un input prend des valeurs écrites dans le fichier, des nombres, des textes entre
guillemets, `true` et `false`, et pour les options d'un choix une liste de ces valeurs. Un texte écrit avec `$name` ou
`$(...)` dedans est du code, que `cesia run` calculerait : c'est l'erreur
`cells.Field takes values written in the file, not expressions.`, comme `cells.Choice(1, options)` et
`cells.Date(today)`. Sliders et autres inputs partagent une cell, comme plus haut.

Chaque fonction vérifie sa valeur, et [cells.Analyse] dit la même chose du fichier, avec les mêmes mots : une valeur qui
n'est pas parmi ses options, des options qui ne sont pas une liste de textes et de nombres finis, ou plus de 1 000 ; une
case à cocher qui n'est ni `true` ni `false`, ou un label (son libellé) qui n'est pas un texte ; un champ qui n'est ni un
texte ni un nombre fini ; un jour qui n'en est pas un, comme `"2026-02-30"`. Analyse refuse aussi deux inputs d'un même
nom dans une cell, et du code à côté d'eux :

```cesia
use std/cells
a = cells.Analyse(cells.Parse("use std/cells\n(* %% P *)\nday = cells.Date(\"2026-02-30\")\nnext = day"))
[e.Message for e in a[2].Errors] -->
```

Analyse donne à chaque cell ses Inputs, les sliders parmi eux, chacun avec son Name, son Kind (sa sorte : `"slider"`,
`"choice"`, `"check"`, `"field"` ou `"date"`), sa Line, la Column et l'End de sa valeur sur cette ligne, un texte avec ses
guillemets, et sa Value telle que `cesia run` la lit ; un slider a son Min, son Max et son Step, un choix ses Options et
une case à cocher son Label. Sliders reste ce qu'il était, les sliders seuls, si bien qu'un programme qui le lit lit la
même chose.

```cesia
use std/cells
a = cells.Analyse(cells.Parse("use std/cells\n(* %% P *)\nzone = cells.Choice(\"GMT-5\", [\"GMT-6\", \"GMT-5\"])"))
a[2].Inputs[1] -->
```

[cells.Snap] donne la valeur de tout input telle que le fichier l'écrit, son Text, et telle que `cesia run` la relit, sa
Value : l'option `steps` plus loin pour un choix, le jour `steps` jours plus loin pour une date, la valeur elle-même pour
une case à cocher ou un champ. Un texte s'écrit entre guillemets, ses `\`, ses `"`, ses fins de ligne, tabulations et
retours chariot écrits `\\`, `\"`, `\n`, `\t` et `\r`, et ses `$` écrits `$$`, si bien que, quoi qu'il contienne, le
fichier le relit comme le même texte, sur une ligne, et jamais comme du code :

```cesia
use std/cells
zone = {Kind: "choice", Value: "GMT-5", Options: ["GMT-6", "GMT-5", "GMT-4"]}
cells.Snap(zone, "GMT-5", steps = 1).Text -->
cells.Snap({Kind: "field", Value: ""}, "say \"hi\" $$(rm)\n").Text -->
```

[cells.Set] donne à tout input sa nouvelle valeur dans la session, en place, comme à un slider : à un choix l'une de ses
options, à une case à cocher `true` ou `false`, à un champ un texte, ou un nombre fini quand le fichier y écrit un
nombre, à une date une date de [std/date], dont il garde le jour. Il vérifie la valeur comme Analyse le ferait, et donne
Value, Text et ToRun ; un éditeur écrit Text sur les colonnes de l'ancienne valeur, de Column à End, si bien que rien
d'autre ne bouge dans le fichier.

```cesia norun
use std/cells
use std/io
use std/result
use std/sys

defn Main()
  cs = cells.Parse(sys.Read("form.ce")?)
  a = cells.Analyse(cs)
  s = cells.Session("form.ce")?
  for c in cs
    cells.Run(s, c)?
  end
  moved = cells.Set(s, a, "zone", "GMT-4")?
  io.Print(moved.Text)   (* "GMT-4", with its quotes, as the file writes it *)
  for i in moved.ToRun
    cells.Run(s, cs[i])?
  end
  result.Ok(missing)
end
```

Un input fait confiance à peu de chose. Analyse lit les valeurs du fichier comme le lecteur de Cesia lui-même, sans en
exécuter aucune. La session lit la valeur d'un set dans son texte comme Analyse, jamais comme du code, et ne la donne à
un nom que quand ce nom tient déjà une valeur de la même sorte, un texte pour un texte, `true` ou `false` pour une case à
cocher, une date pour une date, un nombre pour un nombre : jamais une fonction, ni une autre sorte, que le code compilé
avec ce nom pourrait ne pas attendre. La page de [cells.Html] montre chaque input sous sa cell tel que le fichier
l'écrit, dans une case qui ne change pas, ses textes échappés : une page n'a pas de session, et rien n'y tourne.

## Une page à partager

[cells.Html] fait tourner chaque cell d'un fichier dans une nouvelle session, depuis le haut, et donne une seule page
HTML : le titre de chaque cell, son code coloré comme la documentation le colore, ce qu'elle a affiché, sa valeur en
graphique SVG, en table ou en texte, ou son erreur. La page n'a besoin d'aucun autre fichier ni d'aucun script, et
montre ce que `cesia run` calcule, pas l'état d'un éditeur. Une animation démarre en pause sur sa première image, sous
une case *Play* qui la joue et la met en pause, par le CSS seul, comme le dit
[Graphiques](graphs.md#dans-une-page-web--des-images-en-css) : la case est une case à cocher, que Tab atteint et
qu'Espace coche. Un graphique 3D se montre à la vue de son code, et son SVG a un `<title>`, comme `Surface, 61 × 61
points, z from −0.301 to 0.584`, qu'un lecteur d'écran prononce.

```cesia norun
use std/cells
use std/result
use std/sys
sys.Write("mean.html", result.Unwrap(cells.Html("mean.ce")))
```
