# Fibers

Dans ce chapitre, vous faites plusieurs choses à la fois : chercher des pages pendant que d'autres se chargent, servir
beaucoup de clients, empêcher une tâche lente de retenir une rapide. Une [fiber](glossary.md#fiber) est une fonction qui
tourne à côté du reste du programme, avec sa propre stack (la pile de ses appels en cours) : ce que Go appelle une
goroutine, Java 21 un virtual thread, et d'autres un *green thread*, un thread (un fil d'exécution) que le langage fait
tourner, et non le système. Les fibers sont légères, environ 2,1 KB chacune : un programme peut en faire tourner cent
mille. Elles tournent chacune à son tour sur un cœur : elles tournent
[en concurrence](glossary.md#concurrency-and-parallelism), pas en parallèle, et l'attente de l'une est du temps pour les
autres. Contrairement à `async` en Python ou en JavaScript, rien n'est marqué : n'importe quelle fonction peut attendre, et
le code qui l'appelle ne change pas.

## Spawn et Wait

[fiber.Spawn] lance une fonction dans une nouvelle fiber, et donne aussitôt une tâche. [fiber.Wait] attend que la tâche
finisse, et donne un `Ok` de ce que la fonction a donné :

```cesia
use std/sys
use std/fiber
defn slow(name, seconds)
  sys.Sleep(seconds)
  "$name is ready"
end

start = sys.Now()
bread = fiber.Spawn(() -> slow("bread", 0.2))
cake = fiber.Spawn(() -> slow("cake", 0.1))
fiber.Wait(bread) -->
fiber.Wait(cake) -->
sys.Now() - start < 0.3 --> true
```

Les deux attentes se chevauchent : le tout prend le temps de la plus longue, `0.2` seconde, pas leur somme, `0.3`.

## Ce qui attend

Une fiber qui attend laisse tourner les autres : [sys.Sleep], une lecture sur le réseau, un appel à [fiber.Wait],
[fiber.Receive] ou [fiber.Select], un [fiber.Send] sur un channel (un canal qui porte des valeurs d'une fiber à une autre)
plein, une base de données occupée.

### Un long calcul

Un long calcul ne retient pas non plus les autres : tous les millions de pas, un pas étant un appel ou un tour de boucle,
une fiber qui calcule cède la place aux autres fibers prêtes, ce qu'on appelle le
[preemptive scheduling](glossary.md#preemptive-scheduling) (l'ordonnancement préemptif) : personne n'écrit de yield
(l'instruction qui cède la main), comme dans Erlang, qui compte ses réductions. Un serveur continue donc de répondre à ses
autres clients pendant que l'un d'eux demande un gros rapport. Ce n'est pas la préemption d'un thread du système, qu'un
timer (une minuterie du système) peut arrêter n'importe où : une fonction de `std/` écrite en OCaml, comme un [list.Sort]
d'un million d'éléments, va jusqu'à sa fin avant qu'une autre fiber ait son tour. La fiber est ici une fonction sans nom
sur plusieurs lignes, de `defn ()` à `end`, comme l'a montré le chapitre [Fonctions](functions.md) :

```cesia
busy = fiber.Spawn(defn ()
  n = 0
  for k in 1..2000000
    n += k
  end
  n
end)
sys.Sleep(0.001)
"the program still runs" -->
fiber.Wait(busy) -->
```

## Attendre au plus, et arrêter une fiber

[fiber.Wait] peut attendre un temps au plus : passé ce temps, il donne un `Err` de sorte `"timeout"`, et la tâche continue
de tourner. [fiber.Cancel] l'arrête : la fiber s'arrête à sa prochaine attente, comme un [sys.Sleep], un [fiber.Receive]
ou un appel au réseau, ou au prochain checkpoint d'un long calcul, là où elle laisse tourner les autres. Alors
[fiber.Wait] donne un `Err` de sorte `"cancelled"`, qui dit le fichier et la ligne où était la fiber. Un serveur donne
ainsi un temps à chaque requête :

```cesia
stuck = fiber.Spawn(defn ()
  n = 0
  while true
    n += 1
  end
end)
fiber.Wait(stuck, timeout = 0.05).Error.Kind --> "timeout"
fiber.Cancel(stuck)
fiber.Wait(stuck).Error.Kind --> "cancelled"
```

La boucle n'attend jamais, et elle s'arrête quand même. Ce que la fiber devait faire après son attente, elle ne le fait
pas : du code qui doit finir tourne donc dans une fiber à lui, que rien d'autre ne peut arrêter. C'est ce que fait une
transaction de [sql.Transaction], qui se termine comme le dit sa fonction, même quand la fiber qui l'a commencée est
arrêtée.

## Pmap

[fiber.Pmap] est [list.Map] avec une fiber par élément. Il convient à une fonction qui attend, comme une fonction qui va
chercher une page pour chaque adresse :

```cesia
start = sys.Now()
fiber.Pmap(name -> slow(name, 0.1), ["bread", "cake", "tart"]) -->
sys.Now() - start < 0.3 --> true
```

Trois attentes de `0.1` seconde prennent ensemble environ `0.1` seconde, pas `0.3`. Les résultats arrivent dans l'ordre
de la liste, quel que soit l'ordre dans lequel les fibers finissent.

## Une panic dans une fiber

Un bug dans une fiber n'arrête que cette fiber. Son message est affiché, et [fiber.Wait] donne un `Err` avec le message :
le programme peut donc continuer, l'écrire dans un log, ou s'arrêter.

```cesia
use std/math
broken = fiber.Spawn(() -> math.Div(1, 0))
fiber.Wait(broken).Error.Message -->
```

Un serveur marche ainsi : une requête dont le handler (la fonction qui répond à la requête) a un bug reçoit un `500`, et
les autres requêtes continuent.

## Channels

Un channel porte des valeurs d'une fiber à une autre, dans l'ordre où elles ont été envoyées : c'est le
[message passing](glossary.md#message-passing) (le passage de messages). [fiber.Channel] en fait un, [fiber.Send] y met
une valeur, et [fiber.Receive] prend la plus ancienne, en attendant qu'il en vienne une s'il est vide. [fiber.Close] dit
que rien de plus ne viendra, et une boucle `for` sur un channel prend ses valeurs au fur et à mesure qu'elles arrivent,
jusqu'à ce qu'il soit fermé :

```cesia
use std/list
use std/result
orders = fiber.Channel()
baker = fiber.Spawn(defn ()
  for product in ["bread", "cake", "tart"]
    fiber.Send(product, orders)
  end
  fiber.Close(orders)
end)

made = []
for product in orders
  made = list.Append(product, made)
end
made -->
```

Les valeurs envoyées avant [fiber.Close] arrivent quand même ; un [fiber.Send] après lui est un bug, et arrête sa fiber.
La boucle `for` est du [syntax sugar](glossary.md#syntax-sugar) (une écriture plus courte d'une autre) pour une boucle de
[fiber.Receive], qui donne un `Err` de sorte `"closed"` une fois le channel fermé et vide :

```cesia
orders = fiber.Channel()
fiber.Spawn(defn ()
  fiber.Send("pie", orders)
  fiber.Close(orders)
end)

made = []
got = fiber.Receive(orders)
while result.IsOk(got)
  made = list.Append(got.Value, made)
  got = fiber.Receive(orders)
end
made -->
got.Error.Kind --> "closed"
```

### Une limite de temps

[fiber.Receive] peut aussi attendre un temps au plus, et donne alors un `Err` de sorte
`"timeout"` :

```cesia
fiber.Receive(fiber.Channel(), timeout = 0.05) -->
```

### Plusieurs channels à la fois

[fiber.Select] attend sur une liste de channels et reçoit du premier qui a une valeur, comme le `select` de Go. Il donne
un `Ok` du `Channel` et de la `Value`, un `Err` de sorte `"closed"` pour un channel fermé et vide, ou de sorte
`"timeout"`. Les channels sont essayés dans l'ordre de la liste : un worker (une fiber qui traite des travaux) peut donc
faire passer un arrêt avant son travail.

```cesia
jobs = fiber.Channel()
stop = fiber.Channel()
worker = fiber.Spawn(defn ()
  done = []
  got = fiber.Select([stop, jobs], timeout = 1)
  while result.IsOk(got)
    done = list.Append(got.Value.Value, done)
    got = fiber.Select([stop, jobs], timeout = 1)
  end
  done
end)
fiber.Send("wash", jobs)
fiber.Send("dry", jobs)
sys.Sleep(0)
fiber.Close(stop)
fiber.Wait(worker) -->
```

Le worker a pris les deux travaux au fur et à mesure, puis s'est arrêté quand `stop` a été fermé : un channel fermé n'a
pas de valeur, si bien que [fiber.Select] donne aussitôt son `Err`.

### Un channel d'une taille donnée

Un channel garde autant de valeurs qu'on lui en envoie, et un expéditeur rapide peut remplir la mémoire avant qu'un
destinataire lent le rattrape. Avec une taille, [fiber.Channel] garde au plus ce nombre de valeurs, et [fiber.Send] attend
tant qu'il est plein : l'expéditeur va au rythme de son destinataire. C'est ce qu'on appelle la
[backpressure](glossary.md#backpressure) :

```cesia
tray = fiber.Channel(size = 1)
start = sys.Now()
fiber.Spawn(defn ()
  for k in 1..3
    sys.Sleep(0.1)
    result.Unwrap(fiber.Receive(tray))
  end
end)
for k in 1..3
  fiber.Send(k, tray)
end
sys.Now() - start > 0.15 --> true
```

La première valeur tient ; la deuxième attend que le destinataire prenne la première, au bout de `0.1` seconde, et la
troisième qu'il prenne la deuxième. Une taille de `0` n'en garde aucune : [fiber.Send] attend qu'un destinataire prenne
sa valeur, si bien que les deux fibers se rencontrent.

### Le signal d'arrêt

[sys.Stops] donne un channel que le premier signal d'arrêt ferme : TERM, INT ou HUP. Une fiber qui attend dessus apprend
l'arrêt aussitôt, et termine son travail elle-même, comme le font les requêtes d'un serveur ; [fiber.Close] ferme de la
même façon un channel à vous :

```cesia norun
use std/io
stops = sys.Stops()
defn worker(jobs)
  while true
    if fiber.Receive(stops, timeout = 0).Error.Kind == "closed"
      return "stopped"
    end
    match fiber.Receive(jobs, timeout = 1)
      result.Ok(job) -> io.Print("done", job)
      else -> missing
    end
  end
end
```

### Quand toutes les fibers attendent

Quand chaque fiber attend une autre fiber, et qu'aucune n'attend l'horloge, le réseau ou un signal, rien ne peut jamais
les réveiller : c'est un *deadlock* (un blocage sans issue). Cesia arrête aussitôt le programme, avec la ligne de
l'attente, plutôt que de rester bloqué :

```cesia fails
lonely = fiber.Channel()
fiber.Receive(lonely)
```

### Des valeurs partagées

En Cesia, les valeurs ne changent jamais sur place, elles sont [immuables](glossary.md#immutability) : deux fibers ne
peuvent donc pas abîmer une valeur qu'elles partagent. Une fiber qui change une liste en fait une nouvelle, et l'autre
fiber garde ce qu'elle avait. Un channel est le moyen de passer la nouvelle. Il n'y a donc pas de *data races*, deux
threads qui écrivent une même mémoire en même temps, ni de locks à prendre (un lock réserve une donnée à un seul à la
fois) : une fiber tourne seule entre deux de ses attentes, sur un cœur.

## Pour aller plus loin

- C. A. R. Hoare, *Communicating Sequential Processes*, 1978 : les channels, et la rencontre d'un envoi et d'une réception
  qu'est un channel de taille 0.
- The Go Programming Language Specification : les buffered channels (les channels d'une taille donnée), `close` et
  `select`, que Cesia suit, sauf pour [fiber.Select], qui essaie ses channels dans l'ordre de sa liste, là où Go tire au
  hasard parmi ceux qui sont prêts.
- KC Sivaramakrishnan et al., *Retrofitting Effect Handlers onto OCaml*, 2021 : ce qu'est chaque fiber à l'intérieur.
- Joe Armstrong, *A History of Erlang*, 2007 : des processus qui se relaient au bout d'un nombre de pas compté.

Chacun avec son lien dans [Références](references.md#fibers-et-channels) ;
[Comment Cesia fonctionne](internals.md#les-fibers-et-le-scheduler) montre le scheduler (la partie qui décide quelle fiber
tourne ensuite), et [Vitesse](speed.md#les-fibers-à-côté-des-goroutines-dasync-et-des-virtual-threads) les fibers à côté
des goroutines, d'`async` et des virtual threads.

## La suite

Vos programmes font plusieurs choses à la fois. Le chapitre suivant, [SQLite](sqlite.md), garde leurs données dans une
base de données.
