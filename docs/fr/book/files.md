# Fichiers

Dans ce chapitre, votre programme travaille avec la machine : il lit et écrit des fichiers, crée et liste des dossiers,
défait leurs chemins, prend des arguments et des flags (des options) sur sa ligne de commande, lance d'autres programmes,
et lit l'horloge. L'essentiel est dans [std/sys]. Chacune de ces actions est un [side effect](glossary.md#side-effect),
un changement hors du programme : chaque fonction dit donc la permission dont elle a besoin. Les exemples tournent avec
`--allow read,write`, dans un dossier qui contient `todo.txt` :

```text
buy bread
call Bo
water the plants
```

## Lire un fichier

[sys.Read] donne le texte d'un fichier dans un `Ok`, ou un `Err` si elle ne peut pas : le fichier n'est pas là, ou c'est
un dossier.

```cesia allow=read
use std/sys
sys.Read("todo.txt") -->
sys.Read("nothing.txt") -->
```

### Dans une fonction

Un script (un petit programme qu'on lance tel quel) écrit au premier niveau de son fichier ne peut pas utiliser `?`, qui
sort d'une fonction. Dans une fonction, `?` fait suivre l'erreur, comme l'a montré le chapitre [Erreurs](errors.md) :

```cesia allow=read
use std/result
use std/text
defn tasks(file)
  body = sys.Read(file)?
  result.Ok(text.Lines(body))
end
tasks("todo.txt") -->
```

Pour un fichier livré avec votre programme, où un `Err` serait un bug, [result.Unwrap] suffit :

```cesia allow=read
use std/value
value.Len(text.Lines(result.Unwrap(sys.Read("todo.txt")))) -->
```

## Écrire

[sys.Write] remplace le contenu d'un fichier, et crée le fichier s'il n'est pas là. [sys.Append] ajoute à sa fin. Les
deux donnent `Ok(missing)` quand tout s'est bien passé, puisqu'il n'y a rien de plus à dire :

```cesia allow=read,write
sys.Write("done.txt", "buy bread\n") -->
sys.Append("done.txt", "call Bo\n") -->
text.Lines(result.Unwrap(sys.Read("done.txt"))) -->
```

Un texte de plusieurs lignes s'écrit tel quel : finissez chaque ligne par `\n`, ou joignez-les avec [text.Join].

### Remplacer un fichier sans risque

[sys.Write] vide le fichier, puis écrit le texte. Si le programme ou la machine s'arrête entre les deux, le fichier reste
coupé avant sa fin. Pour remplacer un fichier qu'on ne doit jamais voir à moitié écrit, comme une configuration ou un
état enregistré, écrivez le nouveau texte dans un autre fichier, puis renommez-le par-dessus l'ancien avec
[sys.Rename] : sur Linux et macOS, un renommage dans un même file system (la façon dont un disque range ses fichiers) est
*atomique*, fait d'un seul coup : un lecteur trouve donc soit l'ancien fichier, soit le nouveau, jamais un mélange.

```cesia allow=read,write
sys.Write("todo.txt.new", "buy bread\ncall Bo\nwater the plants\n") -->
sys.Rename("todo.txt.new", "todo.txt") -->
```

### Survivre à une coupure de courant

Un renommage est atomique pour les programmes qui tournent, mais pas encore sur le disque : le système garde en mémoire
ce qu'un programme écrit, dans son [page cache](glossary.md#page-cache), et l'écrit plus tard sur le disque, Linux dans
les 30 secondes environ par défaut. Une coupure de courant pendant ce temps peut le perdre, même après que [sys.Write] et
[sys.Rename] ont dit `Ok` : on peut trouver le fichier vide ou coupé avant sa fin. Avec `sync = true`, [sys.Write] ne
donne son `Ok` qu'une fois le texte sur le disque. Elle appelle [fsync](glossary.md#fsync), l'appel système qui ne rend
la main qu'une fois que le disque tient les données d'un fichier, sur le fichier, puis sur le dossier, qui garde le nom
du fichier (sur Windows, celui du fichier suffit). Un enregistrement qui doit survivre à une coupure de courant écrit
ainsi le nouveau fichier, puis le renomme :

```cesia allow=read,write
sys.Write("todo.txt.new", "buy bread\ncall Bo\nwater the plants\n", sync = true) -->
sys.Rename("todo.txt.new", "todo.txt") -->
```

Après une coupure de courant, le nouveau texte entier est dans `todo.txt`, ou encore dans `todo.txt.new` à côté de
l'ancien `todo.txt` quand le renommage n'a pas atteint le disque : jamais une partie de ce texte, sur les file systems à
*journaling* d'aujourd'hui (ext4, XFS, btrfs, APFS, NTFS), qui écrivent d'abord chaque changement d'un dossier dans un
journal, pour qu'il soit fait en entier ou pas du tout. Le prix est le temps que prend le disque : sur la machine de
[Vitesse](speed.md#textes-et-fichiers), 2,6 ms pour un fichier d'une ligne contre 0,04 ms sans, et 44 ms pour 16 MB
contre 3,5, les mêmes temps que Python, Node et Go avec leur propre fsync, puisque tous attendent le même disque. Un crash
du programme seul, sans `sync`, ne perd rien : ce qu'il a écrit est dans la mémoire du système, qui continue vers le
disque ; seule une panne du système ou du courant peut le perdre.

## Dossiers

[sys.Mkdir] crée un dossier et les dossiers au-dessus de lui. [sys.List] donne les noms d'un dossier, triés.
[sys.Rename] déplace un fichier ou un dossier, et [sys.Remove] supprime un fichier ou un dossier vide :

```cesia allow=read,write
sys.Mkdir("archive/2026") -->
sys.Rename("done.txt", "archive/2026/done.txt") -->
sys.List(".") -->
sys.List("archive/2026") -->
sys.Remove("archive/2026/done.txt") -->
```

### Exists et Stat

[sys.Exists] demande si un chemin existe, et [sys.Stat] en dit plus : la taille en octets, l'heure du dernier
changement, et s'il s'agit d'un dossier, d'un fichier ou d'un lien.

```cesia allow=read
sys.Exists("todo.txt") -->
info = result.Unwrap(sys.Stat("todo.txt"))
info.Size -->
info.IsDir -->
```

## Chemins

[std/path] défait un chemin sans toucher au disque : [path.Base] est sa dernière partie, [path.Dir] le dossier qui le
contient, [path.Ext] l'extension avec son point, [path.Stem] la dernière partie sans elle. [path.Join] met un nom après
un dossier :

```cesia
use std/path
path.Base("photos/2026/beach.JPG") -->
path.Dir("photos/2026/beach.JPG") -->
path.Ext("photos/2026/beach.JPG") -->
path.Stem("photos/2026/beach.JPG") -->
path.Join("photos/2026", "beach.jpg") -->
```

Un chemin s'écrit avec `/`, sur Windows aussi, qui l'accepte aussi bien que `\`. [path.IsAbsolute] distingue un chemin
qui part du sommet, `/` ou un lecteur comme `C:`, d'un chemin relatif au dossier courant :

```cesia
path.IsAbsolute("/tmp/a.txt") -->
path.IsAbsolute("photos/a.jpg") -->
```

### Tous les fichiers sous un dossier

[sys.List] donne les noms d'un seul dossier. [sys.Walk] descend dans les dossiers qu'il contient, et donne le chemin de
chaque fichier, dans l'ordre. Un lien symbolique est listé, jamais suivi : un lien ne peut donc pas le faire tourner en
rond :

```cesia allow=read,write
use std/list
sys.Write("archive/2026/june.txt", "sold 3\n") -->
sys.Walk("archive") -->
list.Filter(p -> path.Ext(p) == ".txt", result.Unwrap(sys.Walk("."))) -->
```

Ensemble, ces fonctions renomment un arbre entier. Celle-ci donne à chaque photo d'un dossier l'extension `.jpg`, en
minuscules :

```cesia norun
use std/path
use std/sys
use std/text
use std/list
defn renamePhotos(folder)
  for p in list.Filter(p -> text.Lower(path.Ext(p)) == ".jpeg", sys.Walk(folder)?)
    sys.Rename(p, path.Join(path.Dir(p), "$(path.Stem(p)).jpg"))?
  end
  result.Ok(missing)
end
```

## Arguments

[sys.Args] contient les mots écrits après le fichier sur la ligne de commande, sous forme de textes :

```bash
cesia run --allow read count.ce todo.txt done.txt
```

```cesia norun
(* count.ce *)
use std/sys
use std/io
use std/result
use std/text
use std/value

for file in sys.Args
  n = value.Len(text.Lines(result.Unwrap(sys.Read(file))))
  io.Print(file, n)
end
```

### Flags

Les flags d'une ligne de commande, `-v` ou `--max 5`, se lisent avec [flags.Parse]. Elle prend les valeurs par défaut,
qui disent ce que prend chaque flag, et les mots ; elle donne les flags et les autres mots. `false` en fait un
interrupteur, un flag présent ou absent, un nombre ou un texte prend une valeur, et un flag que les valeurs par défaut ne
nomment pas est un `Err` qui dit quels flags existent :

```cesia
use std/flags
args = ["-i", "--max", "2", "bread", "todo.txt"]
a = result.Unwrap(flags.Parse({i: false, max: 0}, args))
a.Flags -->
a.Words -->
flags.Parse({i: false, max: 0}, ["--min", "2"]) -->
```

Un nom d'une lettre s'écrit avec un tiret, un nom plus long avec deux : `maxCount` est `--max-count`, ce que donne
[flags.Name] : `flags.Name("maxCount")` vaut `"--max-count"`. Dans un programme, les mots sont [sys.Args] :
`flags.Parse({i: false, max: 0}, sys.Args)`.

## La standard input et l'exit code

[sys.ReadInput] donne tout ce que le programme reçoit sur sa
[standard input](glossary.md#standard-input-and-output) (le texte qu'il lit, depuis le terminal ou un pipe), pour qu'il
puisse se placer dans un pipe du shell (un tuyau qui relie la sortie d'un programme à l'entrée d'un autre) ;
`sys.ReadInput(10)` ne donne que les 10 octets suivants, pour un programme qui répond à chaque message dès qu'il arrive.
[sys.Exit] termine le programme tout de suite avec un [exit code](glossary.md#exit-code) : 0 dit que tout s'est bien
passé, un autre nombre que quelque chose a échoué, pour le shell ou le script qui l'a lancé.

```bash
cat sales.csv | cesia run lines.ce
```

```cesia norun
(* lines.ce: how many lines came in, and code 1 when none did *)
use std/sys
use std/io
use std/result
use std/text
use std/value

input = result.Unwrap(sys.ReadInput())
n = value.Len(text.Lines(input))
io.Print(n, "lines")
if n == 0
  io.PrintError("lines: nothing came in")
  sys.Exit(1)
end
```

[io.PrintError] écrit comme [io.Print], mais sur la [standard error](glossary.md#standard-input-and-output), une seconde
sortie pour ce qui n'a pas marché : ce qui a mal tourné arrive à l'écran même quand la sortie va dans un fichier ou un
pipe, comme dans `cesia run lines.ce < sales.csv > count.txt`.

## L'environnement

[sys.Env] lit une variable d'environnement, ou donne `missing`. Elle demande `--allow env`, ou `env=PORT` pour cette
variable seule :

```cesia norun
use std/text
use std/value
given = sys.Env("PORT")
port = if value.IsMissing(given) 8080 else text.Number(given) end
```

## Les autres programmes

[sys.Run] lance un programme jusqu'à sa fin et donne son exit code, ce qu'il a écrit, et ses erreurs. Elle demande
`--allow exec`, ou `exec=git` pour un seul programme. Les arguments sont une liste : aucun shell ne les lit, donc un nom
qui contient un espace ou un `;` reste un seul argument. Cela exclut la *shell injection* : avec un shell, comme le
`os.system` de Python, un fichier nommé `x; touch owned` donné en argument lancerait le `touch`, une seconde commande que
personne n'a écrite.

```cesia norun
use std/io
use std/result
r = result.Unwrap(sys.Run("git", args = ["log", "--oneline", "-3"]))
if r.Code == 0
  io.Print(r.Out)
else
  io.Print("git failed:", r.Err)
end
```

### Les programmes qui continuent de tourner

`input` donne au programme un texte à lire, `dir` le dossier où il tourne, et `timeout` l'arrête après un nombre de
secondes, avec chaque programme qu'il a lancé, comme les commandes d'un shell. Un programme nommé par son chemin, comme
`./build.sh`, est celui du dossier de ce programme-ci, celui que permet `exec=./build.sh`, même quand `dir` nomme un
autre dossier. Pour un programme qui continue de tourner, un serveur ou un shell, [sys.Start] donne un processus (un
programme en cours d'exécution) dans lequel écrire et qu'on lit pendant qu'il tourne, avec [sys.WriteInput],
[sys.ReadOutput] et [sys.WaitExit] ; [sys.CloseInput] ferme son entrée, comme la fin d'un fichier, et [sys.Stop] lui
demande de finir, avec le signal TERM. Son `dir` est le dossier où il tourne, comme pour [sys.Run].

Les programmes lancés ainsi suivent leur programme quand celui-ci reçoit un signal d'arrêt. TERM, qu'un gestionnaire de
services envoie à ce programme seul, est transmis à chacun d'eux. INT et HUP viennent d'un terminal, qui les envoie à
chaque programme qu'il fait tourner : ils atteignent d'eux-mêmes les programmes lancés, mais un [sys.Run] avec un
`timeout`, qui tourne à part, les reçoit de Cesia. Un programme qui ne fait pas tourner de serveur finit alors tout de
suite, comme s'il n'avait lancé aucun programme ; un programme qui en fait tourner un s'arrête comme le dit le chapitre
[HTTP](http.md#arrêter).

Avec `--watch`, un programme qui doit enregistrer son état avant de finir prend lui-même les signaux :
[sys.TakeStops]`(true)` fait que TERM et INT ne le terminent plus, et [sys.StopAsked] dit si l'un d'eux est arrivé
depuis son dernier appel, pour que le programme finisse de lui-même ; [sys.TakeStops]`(false)` les rend.

## L'horloge

[sys.Now] donne l'heure en secondes depuis 1970, en UTC, sous forme d'un float (un nombre à virgule) avec les
microsecondes : la *wall clock* du système (l'heure du jour), que le système peut avancer ou reculer, comme quand il se
corrige par le réseau. La différence de deux de ces valeurs chronomètre un morceau de code, tant que l'horloge n'est pas
réglée entre-temps. [sys.Sleep] attend, et laisse pendant ce temps tourner les autres fibers (les fonctions qui tournent
à côté des autres dans le même programme) :

```cesia
start = sys.Now()
sys.Sleep(0.05)
sys.Now() - start >= 0.05 -->
```

### Dates

Pour les dates, [std/date] a une struct [date.Date] (une valeur aux champs déclarés), en UTC sauf si son `Offset` dit
autre chose, et les fonctions qui vont avec :

```cesia
use std/date
d = date.Date(2026, 11, 6, 14, 30)
date.Format(d) -->
date.Weekday(d) -->
date.AddDays(30, d) then date.FormatDate() -->
date.DaysBetween(d, date.Date(2026, 12, 25)) -->
date.Parse("2026-12-25") -->
```

### Ici et maintenant

[date.Local] donne la date d'un instant sur l'horloge de cette machine, avec l'`Offset` de son fuseau horaire, en
secondes d'avance sur UTC ; [date.Format] l'écrit, et [date.Parse] la relit. [date.Utc] donne le même instant en UTC, et
[date.ToUnix] des deux est le même :

```cesia
here = date.Local(sys.Now())
date.Format(here) -->
date.ToUnix(here) == date.ToUnix(date.Utc(here)) -->
date.Parse("2026-11-06T14:30:00+03:00") then result.MapOk(date.Utc) then result.MapOk(date.Format) -->
```

Le fuseau horaire est celui du système : `TZ=Asia/Tokyo cesia run app.ce` fait tourner un programme à l'heure de Tokyo.

[date.FromUnix] donne la date en UTC d'un nombre de secondes depuis 1970, [date.AddSeconds] déplace une date d'un nombre
de secondes sur sa propre horloge, [date.DaysInMonth] et [date.IsLeap] répondent pour le calendrier. Le calendrier est
le calendrier *grégorien proleptique*, les règles d'aujourd'hui prolongées avant 1582, avec les jours comptés par les
algorithmes de Howard Hinnant :

```cesia
date.FromUnix(86400) then date.FormatDate() -->
date.AddSeconds(90, date.Date(2026, 1, 1)).Minute -->
date.DaysInMonth(2024, 2) -->
date.IsLeap(1900) -->
```

## La suite

Vos programmes lisent et écrivent les fichiers de la machine. Le chapitre suivant, [Données](data.md), travaille sur
beaucoup de valeurs à la fois : des listes d'enregistrements, des groupes, des comptes, des tables de colonnes.
