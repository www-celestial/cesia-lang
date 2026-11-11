# Le prompt et le debugger

Deux façons de regarder à l'intérieur d'un programme pendant qu'il tourne, bâties sur un même moteur : exécuter ce code
ici, où ici est le programme qui tourne, ou l'endroit où il s'est arrêté. Le prompt est une *REPL*, une boucle read, eval,
print (lire, évaluer, afficher), comme celle de Python ou de Node, avec une différence : il tourne à l'intérieur d'un
programme en marche, comme le fait la REPL d'une image Lisp ou Smalltalk (le programme entier gardé en mémoire, qu'on
modifie pendant qu'il tourne), et il peut remplacer ses fonctions pendant qu'il tourne. Le debugger est un
*source-level debugger* (un debugger qui travaille sur les lignes du code source), comme pdb pour Python ou gdb pour C : il
arrête le programme à un *breakpoint*, une ligne où vous lui avez demandé de s'arrêter, et vous laisse lire chaque
variable, avancer dans le code pas à pas (*step*), une instruction à la fois, et regarder la *call stack*, les appels en
cours, chacun dans sa *frame* (les cases de ses variables).

## Le prompt

`cesia run --repl` lance un programme et ouvre un prompt à côté de lui, à l'intérieur du package de son fichier principal.
Prenez ce `shop.ce` :

```cesia norun
use std/io

defn Price(n)
  n * 2
end

stock = 3
io.Print("start $(Price(stock))")
```

```bash
cesia run --repl shop.ce
```

```text
start 6
> Price(4)
8
> stock + 1
4
> "stock: $stock"
"stock: 3"
```

Une expression montre sa valeur comme l'écrit `-->`, un texte avec ses guillemets. Le prompt voit ce que voit le fichier
principal : ses fonctions, ses variables, ses structs et les packages qu'il utilise, ici `io`. Ce que vous définissez au
prompt reste pour les lignes suivantes :

```text
> rate = 1.5
> Price(rate)
3.0
```

Une définition d'une fonction du programme la remplace dans le programme qui tourne, qui continue avec la nouvelle, comme
le fait un [reload](commands.md#cesia-run) (un rechargement du code) :

```text
> defn Price(n)
.   n * 10
. end
> Price(4)
40
```

Une erreur ne ferme pas le prompt, et elle se montre comme toute erreur de Cesia : sa place, son message, et la ligne avec
un `^` sous l'endroit. Dans ce que vous tapez, la place est `<prompt>`, avec la ligne et la colonne dans ce que vous avez
tapé ; dans une fonction du programme, c'est la place dans le fichier, telle que le programme la montrerait, avec les
appels qui y ont mené. Puis le prompt attend la ligne suivante :

```text
> stok + 1
<prompt>:1:1: Name "stok" doesn't exist.
  1 | stok + 1
    | ^
> Price("two")
shop.ce:4:5: Can't multiply the text "two" by the number 2.
  4 |   n * 2
    |     ^
  To put a value in a text, write "...$x" or value.Text(x).
  in Price (shop.ce:4)
> 2 + 2
4
```

Un bug dans le fichier principal lui-même se montre aussi, et le prompt s'ouvre sur ce qui a tourné avant lui, avec
l'exit code (le nombre que le programme rend à celui qui l'a lancé) 1 à la fin.

Un bloc lit des lignes jusqu'à son `end`, et une liste ou une expression coupée au milieu lit aussi la ligne suivante : le
prompt montre `.` pendant qu'il attend la suite. Un `use` au prompt vaut pour les lignes qui le suivent.

Le programme tourne pendant que le prompt attend : un serveur continue de servir, une boucle continue de boucler, et une
fonction que vous redéfinissez prend effet à son prochain appel. Quand le fichier principal a fini, le prompt reste jusqu'à
ce que vous le quittiez avec Ctrl-D, sur une ligne vide. `cesia run --repl` seul, sans fichier, est un prompt sur un
programme vide.

Sur un terminal, les touches éditent la ligne : les flèches, Home et End, Ctrl-A et Ctrl-E pour le début et la fin, Ctrl-K
et Ctrl-U pour couper jusqu'à la fin ou jusqu'au début, Ctrl-W pour le mot d'avant ; haut et bas parcourent les lignes
tapées avant. Ctrl-C efface la ligne, et sur une ligne vide arrête le programme, comme partout.

Le code tapé au prompt tourne avec les permissions du programme, pas plus : `--allow` les donne, comme pour le programme
lui-même. `--repl` n'ajoute que la permission `debug`, pour le prompt.

## Le debugger

`cesia run --debugger debugger app.ce` lance le programme sous le debugger qui vient avec Cesia. Il s'arrête avant la
première ligne, et à chaque arrêt il dit où est le programme et lit des commandes :

```cesia norun
use std/io

defn Total(n)
  sum = 0
  for i in 1..n
    sum = sum + Half(i)
  end
  sum
end

defn Half(i)
  i / 2
end

io.Print(Total(4))
```

```bash
cesia run --debugger debugger total.ce
```

```text
stopped at total.ce:15 (start)
(debug) break total.ce 12 if i > 2
breakpoint total.ce:12 if i > 2
(debug) continue
stopped at total.ce:12 (break)
(debug) print i * 10
i * 10 = 30
(debug) up
  Half (total.ce:12)
> Total (total.ce:6)
  <file> (total.ce:15)
(debug) print sum
sum = 1.5
```

| Commande | Ce qu'elle fait |
|---|---|
| `break FILE LINE` | s'arrête à cette ligne chaque fois que le programme l'atteint |
| `break FILE LINE if CONDITION` | ne s'y arrête que quand la condition est vraie : une expression des variables de cet endroit ; une condition qui donne une erreur arrête le programme sur cette erreur |
| `clear FILE LINE` | retire le breakpoint de cette ligne |
| `breaks` | liste les breakpoints |
| `print EXPRESSION` | la valeur de n'importe quelle expression, dans la frame courante : ses variables, son package, les modules qu'il utilise |
| `vars` | chaque variable de la frame courante qui a une valeur |
| `watch EXPRESSION` | montre cette expression à chaque arrêt ; `unwatch EXPRESSION` arrête de la montrer |
| `where` | les frames, depuis la plus intérieure, la frame courante marquée par `>` |
| `up`, `down` | passe à la frame de l'appelant, ou revient |
| `continue` | tourne jusqu'au prochain arrêt |
| `step` | exécute une instruction, en entrant dans un appel |
| `next` | exécute une instruction, un appel comptant pour une seule |
| `out` | tourne jusqu'à ce que la fonction courante rende la main |

La frame courante est la plus intérieure à chaque arrêt. Une expression ne fait que lire : ce que calcule `print` ne change
jamais le programme.

### Les arrêts sur erreur

Un [bug](errors.md) arrête le programme là où il se produit, avec chaque variable encore là, avant que l'erreur soit
montrée :

```text
stopped at app.ce:7 (error)
  Index 3 is outside this array of 2 elements.
(debug) print xs
xs = [1, 2]
```

Après `continue`, l'erreur suit son cours comme elle le ferait sans le debugger. Un bug dans une [fiber](fibers.md) (une
fonction qui tourne à côté du reste du programme) arrête aussi le programme, et l'arrêt dit quelle fiber :
`stopped at app.ce:4 (error) in fiber 1` (arrêté à la ligne 4 de app.ce, sur une erreur, dans la fiber 1). Les autres
attendent pendant que le programme est arrêté.

### Fix and continue

Pendant que le programme est arrêté, changez le code dans son fichier et enregistrez-le. Quand le programme reprend, par
`continue`, `step`, `next` ou `out`, le debugger recharge les fichiers qui ont changé et le dit :

```text
(debug) continue
reloaded total.ce
```

C'est le *fix and continue* (corriger, puis continuer), que Smalltalk, Lisp et les debuggers de Java appellent hot
swapping (l'échange du code à chaud) : le programme ne redémarre jamais, si bien qu'un bug trouvé après une heure
d'exécution se corrige sans perdre cette heure. La fonction en cours continue avec le code avec lequel elle a commencé ;
son prochain appel exécute le nouveau code. Un fichier qui a une erreur ne se recharge pas : le debugger montre l'erreur et
reste arrêté, pour que vous puissiez la corriger et taper `continue` à nouveau.

## Votre propre debugger

Le debugger est un fichier écrit en Cesia, `src/tools/debugger.ce`, et `--debugger` en prend aussi un autre, un fichier
de votre projet : `cesia run --debugger mydebug.ce app.ce`. Il a une fonction `OnStop(stop)`, qui tourne à chaque arrêt et
donne ce qu'il faut faire ensuite : `"continue"`, `"step"`, `"next"` ou `"out"`.

```cesia norun
use std/debug
use std/io

defn OnStop(stop)
  io.Print("$(stop.File):$(stop.Line) $(stop.Reason)")
  if stop.Reason == "start"
    debug.SetBreak("app.ce", 12, "n > 100")
  else
    io.Print(debug.Eval("n * 2", stop.Frames[1]))
  end
  "continue"
end
```

Un arrêt contient :

| Champ | Ce que c'est |
|---|---|
| `File`, `Line` | où le programme s'est arrêté |
| `Reason` | `"start"`, `"break"`, `"step"`, `"error"`, ou `"condition"` pour un breakpoint dont la condition donne une erreur |
| `Frames` | les frames, depuis la plus intérieure : chacune a `Function`, `File`, `Line` et `Vars`, chaque variable un `Name` et une `Value` |
| `Fiber` | 0 pour le programme principal, sinon le numéro de la fiber qui s'est arrêtée |
| `Error` | le message de l'erreur pour un arrêt sur une erreur ou sur une condition, sinon missing |

Les fonctions de [std/debug] font le reste : [debug.SetBreak], [debug.ClearBreak] et [debug.Breaks] pour les
breakpoints, [debug.Watch], [debug.Unwatch] et [debug.Watches] pour les watches (les expressions montrées à chaque arrêt),
qui vivent avec le programme d'un arrêt au suivant ; [debug.Eval] exécute du code dans une frame ou au niveau du fichier du
package principal, et c'est aussi le moteur du prompt ; [debug.Reload] recharge ce qui a changé ; [debug.ReadLine] lit une
ligne, éditée sur un terminal, et [debug.IsComplete] dit si du code est complet. Elles demandent la permission `debug`, que
`--debugger` et `--repl` donnent d'eux-mêmes.

Le debugger tourne à l'intérieur du programme, avant lui, et son propre code ne s'arrête jamais. Un debugger n'est pas une
bibliothèque : il ne se charge qu'avec `--debugger`, et un programme lancé sans lui ne paie rien pour lui.

## Vitesse

Seule une ligne qui a un breakpoint, et chaque ligne pendant que vous avancez pas à pas, passe par le debugger, mais un
programme sous le debugger tourne quand même plus lentement : chaque instruction passe un hook, un test pour savoir s'il
faut s'y arrêter. Mesuré le 2026-11-08, `bench/fib.ce`, `fib(35)`, 5 runs (des exécutions mesurées) de chaque en alternance, médiane :
86 ms sans le debugger, 870 ms sous `--debugger debugger`, avec `continue` dès le premier arrêt, et 448 ms dans
l'interpréteur seul, sans le JIT (la partie qui change en code machine le code qui tourne souvent). Le code qui boucle sur
des nombres le paie le plus ; le code qui attend le réseau ou le disque, comme un serveur, le voit à peine. Comme au prompt
et sous `--watch`, une fonction du programme peut être redéfinie pendant qu'un appel à elle tourne, avec des résultats
d'un autre type : le code qui utilise ses résultats reste donc dans l'interpréteur, qui accepte une valeur de n'importe
quel type. Le code hot (qui tourne souvent) devient quand même du code natif, appels compris ; une fonction dont le code
contient un breakpoint reste dans l'interpréteur, et à chaque arrêt le code natif revient à l'interpréteur et redevient
natif une fois hot : les résultats sont donc les mêmes que sans le debugger. Un arrêt sur une erreur dans du code natif
montre les variables de la frame qui l'exécute, mais pas celles des appels que le code natif a faits en elle.

## La suite

Vous savez regarder à l'intérieur d'un programme qui tourne. Le chapitre suivant, [Vitesse](speed.md), dit ce qui devient
du code machine pendant l'exécution.
