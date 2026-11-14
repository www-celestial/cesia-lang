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
rien du fichier et attend des cells. [cells.Run] lui donne une cell et l'attend : un Ok avec Output, les lignes qu'elle
a affichées, Value, ce que montre sa dernière expression, Error, ou missing, avec la Line du fichier et le Text de
l'erreur tel que `cesia run` le montre, et Seconds, le temps qu'elle a tourné. Avant qu'une cell tourne, les noms
qu'elle définit sont oubliés, pour qu'une cell qui échoue ne laisse aucune ancienne valeur derrière elle. Une cell dont
le From vaut 0 est du code tapé à un prompt (une ligne où l'on tape du code à côté du programme) à côté des cells,
qu'aucune ligne du fichier ne contient : ses erreurs nomment `<prompt>`.

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

Les cells tournent au niveau du fichier, comme le prompt de `cesia run --repl` fait tourner du code : chacune voit les
noms que les cells d'avant ont définis, et les uses écrits au-dessus d'elle. Elles tournent comme le ferait le
programme, pas sous le hook du debugger (le crochet qu'il pose sur chaque pas), qui coûte environ dix fois plus :
fib(35) dans une cell prend 56,8 ms, le même fichier sous `cesia run` 56,8 ms aussi (médianes de 21 lancements). Leurs
erreurs et les appels qui y mènent nomment le fichier et ses lignes.

Une session n'a que les permissions de son `allow`, tel que `--allow` les prend :
`cells.Session("mean.ce", allow = ["read"])`. Le programme qui la démarre a besoin de la permission `exec` de ce
`cesia`, [cesia.Binary].

Ce que montre une valeur :

| Valeur | Montre |
|---|---|
| un graphique de [std/plot] | `{Kind: "graph", Scene, Key}` : sa scène, [plot.Scene] à la largeur que Run donne, 640 pixels par défaut, et 400 de haut ; un graphique que std/plot ne sait pas dessiner est l'erreur de la cell, avec le message de std/plot |
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
en un dixième de milliseconde. La session garde les graphiques de ses 64 derniers lancements, et [cells.Scene] en
redessine un à une autre largeur, par sa Key (sa clé), pour un panneau qui a changé de largeur. [cells.Rows] donne les
lignes d'un frame, d'une matrice ou d'une liste, de l'une à une autre, en textes, pour qu'un visualiseur lise une grande
valeur un écran à la fois.

[cells.Stop] arrête la cell qui tourne : sa fiber (un fil d'exécution léger de Cesia) est annulée à sa prochaine attente
ou à son prochain checkpoint (un point où le programme s'arrête un instant pour vérifier ce qu'on lui demande), son Run
donne l'erreur `Stopped.`, et la session et les noms définis avant restent. Une session qui ne répond pas dans les
2 secondes, comme une cell à l'intérieur d'un long appel natif, est arrêtée et une nouvelle démarre : la session que
donne Stop a alors Restarted à true, et les cells tournent de nouveau depuis le haut.

## Une page à partager

[cells.Html] fait tourner chaque cell d'un fichier dans une nouvelle session, depuis le haut, et donne une seule page
HTML : le titre de chaque cell, son code coloré comme la documentation le colore, ce qu'elle a affiché, sa valeur en
graphique SVG, en table ou en texte, ou son erreur. La page n'a besoin d'aucun autre fichier ni d'aucun script, et
montre ce que `cesia run` calcule, pas l'état d'un éditeur.

```cesia norun
use std/cells
use std/result
use std/sys
sys.Write("mean.html", result.Unwrap(cells.Html("mean.ce")))
```
