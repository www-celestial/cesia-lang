# Messages d'erreur

Chaque message que Cesia peut afficher, tel qu'il l'affiche, rangé selon l'endroit d'où il vient. Un `…` tient la place
de ce que le message remplit : un nom, une valeur, un nombre. La seconde colonne donne le hint que Cesia affiche sur la
ligne sous le message, quand il y en a un (les mots qui disent comment corriger l'erreur), puis ce qu'il faut faire, là
où ni le message ni le hint ne le disent. Tous vivent dans une seule table du source, `src/lib/messages.ml`, donc une
même erreur se lit toujours de la même façon.

Le message d'un bug montre d'abord son fichier, sa ligne et sa colonne, puis la ligne elle-même, avec une marque sous
l'endroit :

```text
shop.ce:3:9: Index 5 is outside this array of 3 elements.
  3 | io.Print(names[5])
    |         ^
```

## Lire le code

Le lexer (qui découpe le texte en mots) et le parser (qui en fait un arbre), au chargement d'un fichier : rien du fichier
n'a encore tourné. `cesia check` les montre aussi, avec leur ligne et leur colonne.

| Message | Hint, ou ce qu'il faut faire |
|---|---|
| `This file is not valid UTF-8.` | Enregistrez le fichier en UTF-8 dans votre éditeur. |
| `Unexpected character ….` | Retirez le caractère, ou mettez-le dans un texte. |
| `This text is not closed: a closing " is missing.` |  |
| `Two quotes in a row end a text and start another.` | `A quote inside a text is written \": "say \"hi\"".` |
| `This comment is not closed: a closing *) is missing.` |  |
| `Comments are written (* ... *).` |  |
| `--> shows a value only in an example: in a documentation comment (** *), or in a book.` | `In a program, io.Print(x) prints it.` |
| `The number … doesn't fit in 63 bits.` | `Write it as a float: ….0.` |
| `Expected …, found ….` | Le parser nomme ce que la grammaire attend à cet endroit : souvent un `end`, une `)` ou une `,` qui manque. |
| `This code is nested too deeply.` | Découpez l'expression avec des noms, ou augmentez --limit nesting. |
| `A range is written with two dots, as in 1..n, which is list.Range(1, n), and a method is reached with one dot.` |  |
| `Only a variable can be assigned here.` | Affectez un nom, un champ `x.F`, un élément `xs[i]` ou une clé `d[k]`. |
| `break can only be used inside a loop.` | Utilisez break dans un for ou dans un while. |
| `return can only be used inside a function.` | Au premier niveau d'un fichier, hors des fonctions, le programme finit à sa dernière ligne : sys.Exit le termine plus tôt. |
| `A name can't hold a _: "…".` | `Join the words with capitals: …, or … when it is public.` |
| `? must follow its value, with no space.` | Écrivez `x?`, le `?` collé à sa valeur. |
| `Two ; in a row: an array written in the code has rows and columns only.` | `An array of more dimensions comes from matrix.Reshape: [1 3; 2 4;;; 5 7; 6 8] is matrix.Reshape([2, 2, 2], 1..8).` |
| `A struct can only be defined at the top of a file.` | Déplacez la struct (une valeur à champs nommés, déclarée une fois) au premier niveau du fichier. |
| `Only fields can be written inside a struct.` | `One per line: a name, its type if it has one, and = with a default. The struct ends with end.` |
| `In the block form of a struct, each field has its own line.` | Mettez chaque champ de la forme en bloc sur sa propre ligne. |
| `The parameters of a lambda can't have types.` | `Write the function with defn to give them some.` |
| `An interface can only be defined at the top of a file.` | Déplacez l'interface au premier niveau du fichier. |
| `Only methods can be written inside an interface.` | `A method is a name and its parameters in parentheses, as Area() or Scaled(by Number).` |
| `A method of an interface has no body.` | `A method written apart, as (s Shape) Describe() = ..., is a method of every value that meets the interface.` |
| `In the block form of an interface, each method has its own line.` | Mettez chaque méthode sur sa propre ligne. |
| `A parameter of an interface has no default.` | Retirez la valeur par défaut : la méthode qui satisfait l'interface donne la sienne. |
| `A method can only be defined at the top of a file.` | Déplacez la méthode au premier niveau du fichier. |
| `Only the result of a function can end with !.` | `Int! says that a function gives an Ok of an Int, or an Err: defn Size(path) Int!.` |
| `use can only be used at the top of a file.` | Déplacez le use en haut du fichier. |
| `A use takes no quotes: it names a package of the project.` | `Write use ….` |
| `A use starts in src/ or at the root of the project, with no ./ and no ../.` | `Write the whole path: use geometry/shapes.` |
| `"it" is a reserved name and can't be assigned.` | Donnez un autre nom à la variable. |

## Les noms et les packages

Le resolver (qui décide ce que veut dire chaque nom) et le loader (qui charge les fichiers), au chargement d'un fichier :
un nom qui ne mène nulle part, un use qui ne trouve aucun package (un dossier de fichiers .ce). Rien n'a encore tourné.

| Message | Hint, ou ce qu'il faut faire |
|---|---|
| `Name "…" doesn't exist.` | Vérifiez l'orthographe, ou définissez le nom ; un nom de std/ demande son use. |
| `Name "…" doesn't exist.` | `… is a package of std/: write use std/… first.` |
| `… is in std/…: write use std/… and ….….` | Ajoutez le use que nomme le message, et écrivez le nom avec son package. |
| `… is a package this file uses: choose another name here.` | Renommez la variable, par exemple `s` pour un texte quand le fichier utilise std/text. |
| `Module "…" has no name "…".` | Vérifiez le nom dans la page du module, dans la référence. |
| `The field or method "…" is private to the package that declares it.` | `A field or a method is public when its first letter is a capital.` |
| `There is no struct "…" here.` | `A pattern names a struct of this package, as Point(x, y), or of a package in use, as geo.Point(x, y).` |
| `A method belongs to a struct or an interface declared in the same package: this one can't be reached from here.` | Écrivez la méthode dans le package qui déclare la struct. |
| `There is no struct or interface "…" in this package.` | `A method belongs to a struct or an interface declared in the same package.` |
| `"…" is also defined at …:….` | Deux fichiers d'un même package définissent le nom : renommez-en un, ou retirez-le. |
| `… has an instance method and a static method named "…".` | `A struct has one method of a name.` |
| `The method "…" has the name of a field of ….` | Renommez la méthode ou le champ. |
| `The function "…" is defined twice.` | Renommez l'une des deux fonctions. |
| `"…" is a function of this file and can't be assigned.` | Donnez un autre nom à la variable. |
| `"…" has no value yet.` | `Give it a value before reading it.` |
| `This use creates a cycle between modules.` | Deux packages s'utilisent l'un l'autre : déplacez ce qu'ils partagent dans un troisième. |
| `The folder "…" holds no .ce file.` | Un package est un dossier de fichiers .ce : vérifiez le chemin. |
| `"…" already names …, at line ….` | `Give one of them another name with as.` |
| `Can't read the module "…".` | Vérifiez les permissions du fichier. |
| `Module "…" doesn't exist.` | Vérifiez le chemin depuis la racine du projet. |
| `What comes with Cesia is used through std/: write use std/….` | Écrivez use std/ et le nom. |
| `A use is the path of a folder from the root of the project: write use ….` |  |
| `… names no package: a use of deps/ is deps/OWNER/REPO then the path of a folder from its root, as the [deps] of cesia.toml bring it.` |  |
| `Package … doesn't load: ….` | Corrigez l'erreur que donne le message, dans ce package. |
| `A running program can't load a new module. Restart it to use this one.` | Relancez le programme. |
| `The source folder "…" doesn't exist.` | Corrigez src de [project], ou créez le dossier. |
| `The source folder "…" is outside the project.` | Gardez les dossiers de source dans le projet. |
| `This project needs Cesia … or later, and this is …: run cesia upgrade.` | Lancez cesia upgrade. |
| `… was changed by hand: run cesia pkg install.` | Lancez cesia pkg install : std/ et deps/ sont en lecture seule. |
| `… isn't installed: run cesia pkg install.` | Lancez cesia pkg install. |

## Les valeurs et les opérations

Un bug, quand la ligne tourne : une opération sur une valeur qu'elle ne peut pas prendre. Le programme s'arrête à cette
ligne, ou c'est la fiber (une fonction qui tourne à côté des autres) qui s'arrête.

| Message | Hint, ou ce qu'il faut faire |
|---|---|
| `Can't … … … ….` | `To put a value in a text, write "...$x" or value.Text(x).` |
| `The integer result of … … … doesn't fit in 63 bits.` | `Integers have 63 bits. To go further, use a float: 1.0 * x.` |
| `The integer result of -(…) doesn't fit in 63 bits.` | `Integers have 63 bits. To go further, use a float: 1.0 * x.` |
| `…: division by zero.` | Vérifiez le diviseur avant la division ; une division de floats (des nombres à virgule) par zéro donne un infini à la place. |
| `Can't take the opposite of ….` | `-` prend un nombre ou un array (un tableau) de nombres. |
| `Can't compare … … ….` | `<` et `>` prennent deux nombres ou deux textes ; `==` prend deux valeurs quelconques. |
| `A condition must be true or false, not ….` | `if`, `while` et `and`/`or` prennent true ou false : comparez avec `==`, ou demandez value.IsMissing. |
| `Can't call …: it is not a function.` | La valeur appelée n'est pas une fonction : vérifiez le nom, ou un `.` qui manque avant une méthode. |
| `… takes …, not ….` | Donnez les arguments que prend la fonction ; sa page dans la référence les liste. |
| `… takes … arguments, not ….` | Donnez moins d'arguments ; sa page dans la référence les liste. |
| `… needs the argument "…".` | Donnez cet argument, par position ou par nom. |
| `… has no argument named "…".` | Vérifiez le nom de l'argument dans la page de la fonction. |
| `… received the argument "…" twice.` | Donnez l'argument une seule fois. |
| `… needs a whole number, not ….` | Arrondissez d'abord le float, avec math.Floor, math.Ceil ou math.Round. |
| `… needs numbers, not ….` | `When the value is "function <anonymous>": "it" belongs to the nearest call. Write x -> ... to use it further out.` |
| `… needs a count of 0 or more, not ….` | Donnez un nombre entier, 0 ou plus. |
| `… needs a text, not ….` | Donnez un texte ; value.Text en fait un à partir de n'importe quelle valeur. |
| `… needs true or false, not ….` | Un paramètre optionnel, comme `fold` de text.ByteFind ou `sync` de sys.Write, prend true ou false ; l'omettre veut dire false. |
| `… needs an array, not ….` | Donnez une liste ou un array. |
| `… needs a dictionary, not ….` | Donnez un dictionnaire. |
| `… needs a dictionary, not ….` | `dict.Fields(x) gives the public fields of a struct as a dictionary.` |
| `… needs a text that isn't empty.` | Donnez un texte d'au moins un caractère. |
| `… of an empty array.` |  |
| `A range needs whole numbers, not ….` | `To get a whole number, use math.Floor(...), math.Ceil(...) or math.Round(...).` |
| `This range has too many elements.` | Une range (la suite des entiers d'un nombre à un autre, comme 1..n) est gardée en mémoire quand elle n'est pas la range d'un for : raccourcissez-la, ou faites une boucle dessus. |
| `An index must be a whole number, not ….` | `To get a whole number, use math.Floor(...), math.Ceil(...) or math.Round(...).` |
| `Index … is outside this array of … elements.` | Les positions vont de 1 à value.Len(xs) ; list.First et list.Last donnent missing pour une liste vide. |
| `Index […, …] is outside this array of … rows and … columns.` | Vérifiez la ligne et la colonne avec value.Size. |
| `Index […] is outside this array of … by ….` | Vérifiez chaque position avec value.Size. |
| `An array of … dimensions takes a whole number for each index, not a slice.` | Donnez un nombre entier pour chaque index d'un array de trois dimensions ou plus. |
| `This array has … dimensions: use … indexes, or one.` | Donnez un index par dimension, ou un seul pour l'ordre des éléments. |
| `Only one element can be written at a time.` | Écrivez les éléments un par un, dans une boucle. |
| `Can't index ….` | Seuls les arrays, les textes et les dictionnaires prennent des crochets. |
| `This mask has … elements, the array has ….` | Faites le masque à partir du même array, comme `xs > 0`. |
| `Can't loop over ….` | `for` parcourt un array, une range ou un channel (une file de valeurs entre fibers) ; pour un dictionnaire, dict.Keys, dict.Values ou dict.Pairs. |
| `Can't look inside … with "in".` | `in` cherche dans un array, un dictionnaire ou un texte. |
| `The rows of this array have different lengths.` | Donnez à chaque ligne de la matrice le même nombre d'éléments. |
| `… needs a size, not ….` | Donnez un nombre entier, 0 ou plus. |
| `The method len of … must give an integer for value.Len, not ….` | Faites donner un entier à la méthode len. |
| `Can't reshape … elements into ….` | Le produit des tailles doit être égal au nombre d'éléments. |
| `Reshape needs its shape as a list of sizes, not ….` | `Write the sizes in a list: matrix.Reshape([2, 3], xs).` |
| `…'s dimension must be 1 or 2, not ….` | Donnez une dimension que l'array possède. |
| `An array has at most 32 dimensions, not ….` | Utilisez 32 dimensions au plus. |
| `… works on arrays of 2 dimensions, not ….` | Donnez une matrice ; matrix.Reshape en fait une. |
| `Can't combine an array of … with an array of ….` | Donnez des arrays de mêmes tailles, ou un nombre et un array. |
| `Matmul can't multiply … by … with … by …: the columns of the first must equal the rows of the second.` | Transposez l'une des deux, ou vérifiez les tailles avec value.Size. |
| `text.Decimals needs a count of decimals from 0 to 20, not ….` | Donnez de 0 à 20 décimales. |
| `Can't sort … with ….` | Triez des nombres ou des textes, ou donnez à list.SortBy une fonction qui en donne un. |
| `… needs a text with a character.` | Donnez un texte d'au moins un caractère. |
| `FromBytes needs integers from 0 to 255, not ….` | Donnez des entiers de 0 à 255. |
| `Char needs a code point, not ….` | Donnez un code point (le numéro d'un caractère dans Unicode) de 0 à 1 114 111, et non un surrogate (un des numéros qu'UTF-16 garde pour lui). |
| `… needs a number of bytes within the text, not ….` | Donnez un nombre d'octets qui reste dans le texte. |
| `A dictionary key is a number or a text, not ….` | Prenez un nombre ou un texte comme clé. |
| `This dictionary has no key: ….` | Demandez d'abord dict.Has, ou lisez avec dict.Get ou dict.GetOr, qui donnent missing ou une valeur par défaut. |
| `A dictionary takes one key between its brackets.` | Donnez une seule clé : d[k]. |
| `Dict needs structs with a Key and a Value, not ….` | Donnez à dict.Dict une liste de {Key, Value}. |
| `No branch of this match accepts ….` | Ajoutez le cas qui manque, ou un else. |
| `This pattern takes … elements, the value has ….` | Donnez au pattern (la forme à laquelle match compare la valeur) autant de noms que la liste a d'éléments. |
| `This pattern needs a struct, not ….` | La valeur n'est pas une struct : passez-la d'abord par un match. |
| `This pattern needs an array, not ….` | La valeur n'est pas un array : passez-la d'abord par un match. |
| `This pattern needs …, not ….` | La valeur n'a pas la forme du pattern : utilisez match, avec un else. |
| `? can only be used inside a function, which it leaves with the Err.` | `At the top of a file, write result.Unwrap(...) where an Err would be a bug, or match on the result.` |
| `? needs an Ok or an Err, not ….` | `Return a result from the function you call.` |
| `Assertion failed.` | La condition de bug.Assert était fausse. |
| `date.Local can't place … seconds since 1970: it takes a time less than 10^15 seconds from 1970, about 31 million years.` | Donnez un temps à moins d'environ 31 millions d'années de 1970. |
| `random.Int needs a low that is at most its high, and a range that fits in 63 bits: … to ….` | Donnez à random.Int un low au plus égal à son high. |
| `sys.Exit takes a code from 0 to 255, not ….` | Donnez un code de 0 à 255. |
| `Near needs … to be a number of 0 or more, not ….` | Donnez à rel et à abs une valeur de 0 ou plus. |
| `JSON can't hold ….` | JSON tient des nombres, des textes, des booléens, missing, des listes et des dictionnaires : dict.Fields change une struct en dictionnaire. |

## Les structs, les interfaces et les types

La plupart, quand une valeur arrive : une struct construite, un champ écrit, un appel, un résultat. Un type qui ne nomme
rien est trouvé au chargement du fichier.

| Message | Hint, ou ce qu'il faut faire |
|---|---|
| `This struct has no field "…".` | Comparez l'orthographe aux champs de la struct. |
| `… has no field "…".` | Comparez l'orthographe aux champs de la struct. |
| `Can't read the field "…" of ….` | Il n'y a que les structs et les dictionnaires qui aient des champs : vérifiez la valeur. |
| `"…" is a method of …: it must be called.` | `Write x.…(). On an array: list.Map(it.…(), xs).` |
| `"…" is a static method of ….` | `Write ….…(...).` |
| `"…" needs a ….` | `Write x.…(), with x a ….` |
| `… has no static method "…".` | Vérifiez le nom, ou écrivez-la comme une fonction du package. |
| `… has no field or method "…".` | Comparez l'orthographe aux champs et aux méthodes de la struct. |
| `….From is a static method of every struct: it can't be defined.` | `Another name, as FromRow, can build a struct its own way.` |
| `… needs a field that is private to its package.` | From ne remplit que les champs publics : donnez une valeur par défaut au champ privé, ou construisez la struct dans son package. |
| `Fields needs a struct, not ….` | Donnez une struct à dict.Fields. |
| `… needs the field "…".` | Donnez la clé dans le dictionnaire, ou une valeur par défaut au champ. |
| `… gets its field "…" from two keys: "…" and "…".` | Gardez l'une des deux clés. |
| `There is no type "…".` | `A type is Int, Float, Number, Bool, Text, Array, Dict, Function, a struct or an interface.` |
| `… is an interface: it can't be called.` | `A value meets it by having its methods. To check one, write the interface after a parameter or a field: s ….` |
| `Both … and … have a method "…", and … meets both.` | `A field or a method of the value itself would win over theirs.` |
| `…: … must be …, found ….` | Donnez une valeur du type écrit, ou changez le type. |
| `… needs a struct, not ….` | Donnez une struct. |

## Les warnings de cesia check

Les warnings (des avertissements) ne sont pas des erreurs : `cesia check` les montre, et ils ne changent pas son exit
code (le nombre qu'une commande rend à celui qui l'a lancée).

| Message | Hint, ou ce qu'il faut faire |
|---|---|
| `… gives a result, used here as a plain value.` | `An Err would pass for a value: add ?, match it, or Unwrap it.` |
| `… gives a result, which is dropped here.` | `Its Err would go unseen: add ?, match it, or write _ = before it to drop it on purpose.` |
| `… can give an Err, which … doesn't say: write …!.` | Écrivez le `!` après le type de résultat que nomme le message. |

## Les permissions et les limites

Quand le programme demande ce que sa ligne de commande ne lui a pas donné, ou dépasse une limite : voir
[Permissions](permissions.md).

| Message | Hint, ou ce qu'il faut faire |
|---|---|
| `Permission "…" denied. Run again with --allow ….` |  |
| `Permission "…" denied for ….` | `Run again with --allow …=…, or a folder that holds it.` La permission la plus étroite qui suffirait : le fichier, le port, l'hôte, la commande, la variable ou la bibliothèque ; « , or a folder that holds it » pour read et write seulement. |
| `Permission "net" denied for listening on …, which other machines can reach.` | `Run again with --allow net=…; net=:… listens on this machine only.` |
| `Permission "net" denied for …: net=own reaches only the listeners this program has open, at an address of this machine written out or localhost.` | `Run again with --allow net=…; for cesia test, "net=…" in allow of [test] in cesia.toml does it too.` |
| `Limit "…" reached.` | Trouvez la boucle ou les données qui grandissent ; augmentez la limite avec --limit si le programme est juste. |

## Les fibers et les channels

Ils viennent de std/fiber. Ceux qui ont une sorte ne sont pas des bugs mais l'`Err` d'un résultat, comme `"timeout"` ;
les autres arrêtent la fiber.

| Message | Hint, ou ce qu'il faut faire |
|---|---|
| `… needs a task, not ….` | Donnez à fiber.Wait ou à fiber.Cancel ce qu'a donné fiber.Spawn. |
| `All fibers are waiting and nothing can wake them.` | Une fiber doit envoyer, fermer ou finir : cherchez un channel que personne ne ferme. |
| `… needs a channel, not ….` | Donnez ce qu'a donné fiber.Channel. |
| `Select needs a list of channels, not ….` | Donnez une liste de channels. |
| `The size of a channel is a whole number, 0 or more, not ….` | Donnez une taille de 0 ou plus, ou aucune. |
| `A timeout is a number of seconds, 0 or more, not ….` | Donnez un nombre de secondes, 0 ou plus. |
| `Nothing came on the channel before the timeout.` | Une Err de sorte "timeout" : rien n'est arrivé à temps. |
| `The task didn't end before the timeout.` | Une Err de sorte "timeout" : la tâche continue de tourner. |
| `Nothing came on the channels before the timeout.` | Une Err de sorte "timeout". |
| `The fiber was cancelled here.` | Une Err de sorte "cancelled" : fiber.Cancel l'a arrêtée. |
| `The channel is closed, and nothing is left in it.` | Une Err de sorte "closed" : tout ce qui a été envoyé a été pris. |
| `Send to a closed channel: Close said that nothing more comes.` | Envoyez avant Close, ou n'envoyez plus après. |
| `This channel is closed already.` | Fermez un channel une seule fois. |

## Les fichiers, les processus et le réseau

Ils viennent de std/sys et de std/net, et du supervisor de `--workers` (le processus qui lance les workers et les
surveille), qui affiche ses lignes sur la sortie d'erreur standard.

| Message | Hint, ou ce qu'il faut faire |
|---|---|
| `Can't … …: ….` | La raison que donne le système lui-même termine le message : un fichier absent, un dossier non vide, plus de place sur le disque. |
| `… needs a finite duration of 0 or more, not ….` | Donnez un nombre de secondes, 0 ou plus. |
| `This process has ended.` | Relancez le programme avec sys.Start. |
| `… needs a process, not ….` | Donnez ce qu'a donné sys.Start. |
| `The input of this process is closed.` | On ne peut plus rien y écrire après sys.CloseInput. |
| `… needs a socket, not ….` | Donnez ce qu'a donné net.Listen, net.Accept ou net.Connect. |
| `A port is a number from 0 to 65535, not ….` | Donnez un port de 0 à 65 535 ; 0 laisse le système en choisir un. |
| `This socket is closed.` | Ouvrez une nouvelle connexion. |
| `This system can't watch more sockets.` | Sur macOS et Windows, un programme surveille au plus 1 000 sockets : fermez-en, ou servez sur Linux. |
| `The server is stopping.` | Le programme a reçu un signal d'arrêt : il n'y a rien à faire. |
| `Worker … ended with code …: another starts.` | Le supervisor lance un autre worker (un des processus qui servent) ; regardez sa sortie pour savoir pourquoi il s'est terminé. |
| `A worker ended with code … before it could accept: the program can't start, the workers stop.` | Lancez le programme sans --workers pour voir son erreur. |
| `A new worker ended with code … before it could accept: the running workers stay.` | La nouvelle version a un bug : les anciens workers continuent de servir ; corrigez-le et envoyez de nouveau HUP. |
| `The new workers didn't accept in time: the running workers stay.` | La nouvelle version a mis plus de 30 secondes à accepter : les anciens workers continuent de servir. |

## Les logs et les métriques

Ils viennent de std/log, qui écrit les logs (une ligne par événement), et de std/metrics.

| Message | Hint, ou ce qu'il faut faire |
|---|---|
| `The fields of a log line are a struct or a dictionary, not ….` | Donnez une struct ou un dictionnaire, comme {Order: 7}. |
| `The labels of a metric are a struct or a dictionary, not ….` | Donnez une struct ou un dictionnaire, comme {method: "GET"}. |
| `"…" isn't a name Prometheus takes: letters, digits and _, not first a digit.` | Utilisez des lettres, des chiffres et _, sans chiffre en premier. |
| `The metric … is a …: it can't be another kind too.` | Donnez à l'histogramme un autre nom que celui du compteur. |
| `A counter only grows: metrics.Add takes 0 or more, not ….` | Un compteur ne fait que monter : utilisez un histogramme pour une valeur qui peut baisser. |

## JSON

Le `Message` de l'`Err` de [json.Parse] : chacun finit par l'octet où le texte cesse d'être valide, comme
`Expected a value, at byte 7`.

| Message | Hint, ou ce qu'il faut faire |
|---|---|
| `Unexpected text` |  |
| `A \u escape is too short` |  |
| `A \u escape needs four hex digits` |  |
| `A surrogate is alone` |  |
| `A text is not closed` |  |
| `A bad escape` |  |
| `A control character in a text` |  |
| `A number needs digits` |  |
| `A number is too large` |  |
| `Too deep` |  |
| `Expected a value` |  |
| `Expected a comma or ]` |  |
| `A key needs a text` |  |
| `Expected a colon` |  |
| `Expected a comma or }` |  |
| `Text after the value` |  |

## Regular expressions

Ils viennent de std/regex, quand un pattern (une regular expression, un petit texte qui décrit un ensemble de textes)
est compilé.

| Message | Hint, ou ce qu'il faut faire |
|---|---|
| `Bad pattern: ….` | Corrigez le pattern à l'endroit que dit le message ; voyez la table des patterns dans Textes. |

## Le SQL et les colonnes

Ils viennent de std/sql, std/sqlite3 et std/columns. Les erreurs de SQLite lui-même sont des `Err` avec le code que SQL
leur donne, comme le montre [SQLite](sqlite.md).

| Message | Hint, ou ce qu'il faut faire |
|---|---|
| `SQLite can't take … with a zero byte.` | Retirez l'octet zéro. |
| `… needs a …, not ….` | Donnez ce qu'a donné sql.Open ou une transaction. |
| `This connection or cursor is closed.` | Ouvrez de nouveau la base de données. |
| `This database is closed.` | Ouvrez-la de nouveau. |
| `SQLite's pragmas temp_store_directory and data_store_directory are refused: they would put its files where read= and write= don't reach.` | Gardez les fichiers de SQLite là où les permissions vont. |
| `Can't load SQLite's plugin cesia_sqlite.cmxs: ….` | La release (la version publiée de Cesia) est incomplète : installez-la de nouveau. |
| `The text holds no statement.` | Donnez un seul statement SQL (une instruction). |
| `One statement per call: sql.Script runs several, without parameters.` | Découpez le texte en plusieurs appels, ou utilisez sql.Script pour un schéma. |
| `Parameter … is …: SQL takes missing, a Bool, an Int, a Float or a Text.` | Donnez missing, un Bool, un Int, un Float ou un Text : json.Text pour une liste ou un dictionnaire. |
| `The statement has … placeholders, given … values: one value for each ?.` | Donnez une valeur pour chaque ?. |
| `A batch needs a count of rows above 0, not ….` | Donnez un nombre supérieur à 0. |
| `The column … holds an integer past 63 bits: read it with cast(… as text).` | Lisez-la comme un texte, comme le dit le message. |
| `No connection was free for … seconds. Inside a transaction, use its tx, not db.` | Augmentez max de sql.Open, ou gardez les transactions courtes. |
| `A pool holds 1 connection or more, not ….` | Donnez à max une valeur de 1 ou plus. |
| `… is a URI: SQLite takes the path of a file here, or :memory:.` | Donnez le chemin du fichier. |
| `The columns … and … both give the key …: rename one with as.` | Renommez l'une des colonnes avec as, dans le SQL. |
| `… cells don't make whole rows of … names.` | Donnez un nombre de cellules égal au nombre de noms fois le nombre de lignes. |
| `These columns have … and … rows.` | Donnez des colonnes de même longueur. |
| `Split needs the result of Groups, not ….` | Donnez à Split ce qu'a donné columns.Groups. |
| `… is SQLite, which programs reach through std/sql only.` | Utilisez std/sql. |

## C

Ils viennent de std/c : voir [C et C++](c.md).

| Message | Hint, ou ce qu'il faut faire |
|---|---|
| `Can't load …: ….` | Installez la bibliothèque, ou donnez son chemin exact ; la raison du système termine le message. |
| `This library has no function ….` | Vérifiez le nom dans le header de la bibliothèque (le fichier .h qui déclare ses fonctions). |
| `… isn't a C type.` | Utilisez un type de la table de C et C++. |
| `void can't be an argument.` | Une fonction sans argument prend []. |
| `slow takes a function of at most 6 numbers, pointers or texts, which doesn't call back.` | La lier sans slow. |
| `… slow C calls already wait for a place: this one can't wait too.` | Trop d'appels à la fois : refuser plus tôt, comme par une limite de connexions par client. |
| `A C function takes at most 60 arguments, not ….` | Une fonction C prend ici 60 arguments au plus. |
| `This needs libffi, which isn't installed.` | Installez libffi, pour plus de 6 arguments, les structures passées par valeur, les fonctions variadiques et les callbacks (des fonctions de votre programme que le C appelle). |
| `libffi refuses this signature.` | Vérifiez les types avec le header C. |
| `A structure needs a block, not ….` | Donnez un bloc de c.Alloc. |
| `This block has … bytes, and the structure takes ….` | Allouez la taille de la structure. |
| `callback needs a callback, not ….` | Donnez ce qu'a fait c.Callback. |
| `c.Callback needs a function, not ….` | Donnez une fonction. |
| `c.Struct needs at least one field.` | Donnez au moins un champ à c.Struct. |
| `… can't be a field of a structure.` | Utilisez un type de nombre ou ptr. |
| `Field … is outside this structure of … fields.` | Comptez les champs à partir de 1. |
| `… needs a structure type, not ….` | Donnez ce qu'a fait c.Struct. |
| `… can't be a variadic argument: C promotes it. Use i32 or f64.` |  |
| `… can't go through a callback.` | Utilisez des nombres et ptr dans un callback. |
| `c.Fn needs a library, not ….` | Donnez ce qu'a donné c.Open. |
| `c.Open needs a version as an integer or a text, not ….` | Donnez une version comme 6 ou "1.2". |
| `… doesn't fit in ….` | Donnez une valeur dans l'intervalle du type C. |
| `This … doesn't fit in an integer.` | Utilisez un type plus petit, ou lisez la valeur en deux moitiés. |
| `… needs an integer, not ….` | Donnez un entier. |
| `… needs a number, not ….` | Donnez un nombre. |
| `bool needs true or false, not ….` | Donnez true ou false. |
| `ptr needs a pointer, a block or missing, not ….` | Donnez un bloc, un pointeur ou missing. |
| `text needs a text or missing, not ….` | Donnez un texte ou missing. |
| `c.Alloc needs a size of 1 or more, not ….` | Donnez une taille de 1 ou plus. |
| `Offset … is outside this block of … bytes for … ….` | Gardez l'offset (la position en octets depuis le début du bloc) à l'intérieur du bloc. |
| `An offset is an integer, not ….` | Donnez un entier. |
| `… can't be … a block.` | Lisez ou écrivez le type que tient le bloc. |
| `c.… needs a block, not ….` | Donnez ce qu'a donné c.Alloc. |
| `c.Text needs a pointer, not ….` | Donnez un pointeur. |
| `This block was freed.` | N'utilisez pas un bloc après c.Free. |
| `Nothing of C runs before a library is open: structures, pointers and calls wait for c.Open.` | `Call c.Open first: it checks the ffi permission for the whole of std/c.` |
| `This text has a zero byte, which C would read as its end.` | Retirez l'octet zéro, ou passez les octets dans un bloc. |

## Les packages natifs

La table `[native]` du `cesia.toml` d'un package, et le moteur que Cesia charge au premier appel d'une native (une
fonction écrite en OCaml, dans le moteur du package) : voir [Packages natifs](native.md).

| Message | Hint, ou ce qu'il faut faire |
|---|---|
| `[native] needs package, the folder of a package of the project, and natives, an array of the names of its natives.` | Donnez les deux clés dans la table `[native]`. |
| `[native] natives: … isn't a private name, as a native of a package is: a small first letter, no _.` | Renommez la native ; la fonction publique du package l'enveloppe. |
| `native/ has no engine for …: build the engine of this project.` | Faites le build du moteur pour ce système et ce Cesia ; la parenthèse liste les moteurs que le dossier contient. |
| `… has no engine for …: run cesia pkg install.` | La dépendance n'a pas de moteur pour ce système et ce Cesia : installez-la de nouveau, ou demandez-en un à son auteur. |
| `The engine … didn't load: ….` | La raison après les deux-points dit ce qui a échoué : le fichier, son fingerprint (son empreinte) ou une vérification. |
| `it needs …, which this Cesia doesn't hold` | Une raison du message ci-dessus : le moteur utilise un module OCaml que le binaire de ce Cesia n'inclut pas, comme `Stdlib__Dynarray`. Son auteur refait son build sans ce module. |
| `… changed since this Cesia loaded it: run the program again.` | Le fichier du moteur a été remplacé pendant que le programme tournait : relancez le programme. |
| `The engine … doesn't give the natives of its cesia.toml: it lacks …; it adds ….` | Le moteur et la liste `natives` de `[native]` doivent nommer les mêmes natives. |
| `Cesia_v1.…, by a native package.` | Le moteur a mal appelé une fonction de `Cesia_v1` (par exemple `register` deux fois, ou hors du domain de Cesia, son fil d'exécution d'OCaml) : c'est un bug du package. |
| `… raised …: a bug of its native package.` | La native a levé une exception OCaml : signalez-le à l'auteur du package. |
| `… needs …, not ….` | Une native a reçu une valeur de la mauvaise sorte : donnez la sorte que nomme le message. |

## Le debugger et les outils

Ils viennent de std/debug et des outils que lance `cesia`. Un debugger est un programme qui exécute le vôtre et peut
l'arrêter, pour montrer ses variables.

| Message | Hint, ou ce qu'il faut faire |
|---|---|
| `The debugger has no function OnStop(stop).` | Un debugger donné à --debugger définit OnStop(stop). |
| `This tool has no function Main().` | Un outil définit Main(). |
| `The debugger's engine didn't load: ….` |  |
| `Eval needs a frame of a stop, as stop.Frames[1], not ….` | Donnez à Eval une frame de l'arrêt (les variables d'un appel en cours), comme stop.Frames[1]. |
| `OnStop must return "continue", "step", "next" or "out", not ….` | Rendez l'un des quatre mots. |

## Les tests

Ce qu'affiche `cesia test`, et les bugs de std/test : voir [Tests](tests.md).

| Message | Hint, ou ce qu'il faut faire |
|---|---|
| `std/test and std/gen work under cesia test, in a test function of a .test.ce file or a tests folder.` | Déplacez le code dans une fonction de test d'un fichier .test.ce. |
| `at case … of …` |  |
| `on the case an earlier run saved` |  |
| `, shrunk from … draws to …:` |  |
| `it stopped: …` |  |
| `…: no test is named …; its tests are ….` |  |
| `it called sys.Exit(…), which would end the whole run.` |  |
| `saved, tried first next time; these cases again: cesia test … --seed …` |  |
| `… passed, … failed, seed …` |  |
| `…, part … of …` |  |
| `… at the ? of line …` |  |
| `the same float but for its last bits: math.Near(…, …)?` |  |
| `rel can't help at 0: give abs` |  |
| `== compares element by element: value.Equal(a, b)?` |  |
| `The test ran past its … s.` | `timeout of [test] in cesia.toml gives a test more time.` |
| `Its Temp folder is kept: …` |  |
| `new snapshot …: review it, then cesia test --update` |  |
| `snapshot … changed: cesia test --update keeps the new text` |  |
| `cesia test needs its plugin, cesia_testing.cmxs, beside the binary: …` |  |

## La ligne de commande

Ils viennent de `cesia` lui-même, avant qu'un programme tourne : la commande finit avec le code 2, ou 3 pour une erreur
interne.

| Message | Hint, ou ce qu'il faut faire |
|---|---|
| `cesia: can't read …` |  |
| `cesia: unknown permission: …` |  |
| `cesia: invalid permission: …` |  |
| `cesia: invalid size: …` |  |
| `cesia: invalid limit: …` |  |
| `cesia: unknown limit: …` |  |
| `invalid seed: …, a whole number` |  |
| `invalid number of workers: …, a whole number from 1, or cores` |  |
| `--workers and --watch don't go together: --watch reloads one process` |  |
| `--workers needs Linux or macOS: on Windows, a program serves on one core` |  |
| `cesia: nothing is documented under …` |  |
| `cesia: … is in std/…: cesia doc ….….` |  |
| `Internal error: …` |  |

## cesia.toml, cesia do et cesia new

Ils viennent du lecteur de `cesia.toml`, chacun précédé de `cesia.toml:LINE:`, et de `cesia do` et de `cesia new`.

| Message | Hint, ou ce qu'il faut faire |
|---|---|
| `This line is not valid UTF-8.` |  |
| `Control characters aren't allowed here.` |  |
| `… aren't supported in this file.` |  |
| `Arrays hold strings only in this file.` |  |
| `Expected ….` |  |
| `This string is not closed.` |  |
| `This array is not closed.` |  |
| `The escape \… isn't supported in this file.` |  |
| `… is defined twice.` |  |
| `No cesia.toml in this folder.` |  |
| `cesia.toml has no name in [project].` |  |
| `cesia.toml has no task.` |  |
| `Unknown table […].` |  |
| `Unknown field … outside any table.` |  |
| `… has an unknown field ….` |  |
| `…: … needs ….` |  |
| `Task …: run needs at least one word.` |  |
| `Task … has both run and file.` |  |
| `Task … has … without file.` |  |
| `Task … needs …, which doesn't exist.` |  |
| `Task … needs itself, through ….` |  |
| `(needs …)` |  |
| `A project name holds letters, digits, - and _, not ….` |  |
| `… already exists.` |  |
| `Created …. Run it: cd … && cesia do run` |  |
| `No task named ….` |  |
| `Task … runs no program of its own, so it takes no words after its name.` | Donner les mots à une tâche qui a run ou file. |
| `Can't start …: ….` |  |

## La suite

Les [Commandes](commands.md) donnent l'exit code de chaque sorte d'erreur.
