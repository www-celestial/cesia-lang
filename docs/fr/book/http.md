# HTTP

Dans ce chapitre, vous faites un site, puis vous en appelez un. Vous écrivez un serveur web, avec des routes, des
paramètres dans le chemin, du JSON en entrée et en sortie, et un log de chaque requête (une ligne écrite pour chacune) ;
vous le testez sans le réseau ; vous le servez ; et vous l'interrogez avec le client, depuis le même programme. Tout cela
est dans [std/http].

## Une application

[http.App] démarre une application sans aucune route. Chaque [route](glossary.md#route) en ajoute une : une méthode, un
chemin et un [handler](glossary.md#handler), la fonction qui prend la requête et donne la réponse. [http.Get] ajoute une
route pour `GET`, [http.Post] une pour `POST`, comme [http.Put] et [http.Delete] le font pour les leurs. [http.Plain] fait
une réponse en texte simple, et [http.Json] une réponse en JSON :

```cesia
use std/http
app = http.App()
  then http.Get("/", r -> http.Plain("Welcome"))
  then http.Get("/hello/:name", r -> http.Plain("Hello, $(r.Params.name)!"))
  then http.Get("/stock", r -> http.Json({bread: 40, cake: 6}))
```

### Des mots dans le chemin

Une partie d'un chemin qui commence par `:` prend n'importe quel mot, et le handler le trouve dans `r.Params`.
L'application est une valeur : chaque route en donne une nouvelle, et [then] les enchaîne.

### Un handler de plusieurs lignes

Un handler de plusieurs lignes s'écrit après sa route, comme un [do block](functions.md#do-blocks), avec `_` à la place
du handler : le chemin vient en premier. Sans le `_`, le bloc prendrait la première place, celle du chemin.

```cesia
use std/text
app = app
  then http.Get("/shout/:word", _) do r
    word = text.Upper(r.Params.word)
    http.Plain("$(word)!")
  end
```

La même route, avec le handler écrit dans les parenthèses, à l'ancienne :

```cesia
same = http.App()
  then http.Get("/shout/:word", defn (r)
    word = text.Upper(r.Params.word)
    http.Plain("$(word)!")
  end)
```

## L'essayer sans le réseau

[http.Handler] donne la fonction que le serveur appelle pour chaque requête. Vous pouvez l'appeler vous-même, avec une
requête sous forme de dictionnaire : c'est ainsi qu'on teste un serveur.

```cesia
use std/io
handle = http.Handler(app)
ask(path) = handle({Method: "GET", Path: path, Query: "", Headers: [], Body: ""})
ask("/hello/Ana").Body -->
ask("/shout/hey").Body -->
ask("/stock").Status -->
io.Print(ask("/stock").Body)
ask("/nowhere").Status -->
```

Un chemin qu'aucune route ne prend reçoit un `404`.

## Comment une requête trouve sa route

La première route ajoutée qui prend le chemin, puis la méthode, répond. Une partie écrite d'un motif ne prend qu'elle-même,
une partie avec `:` n'importe quel mot, et un `*` final le reste du chemin. Une route de `:id` ajoutée avant celle de `me`
prendrait aussi `/users/me` ; ajoutée après, comme ici, elle prend les autres mots :

```cesia
users = http.App()
  then http.Get("/users/me", r -> http.Plain("you"))
  then http.Get("/users/:id", r -> http.Plain("user $(r.Params.id)"))
askUsers(method, path) = http.Handler(users)({Method: method, Path: path, Query: "", Headers: [], Body: ""})
askUsers("GET", "/users/me").Body -->
askUsers("GET", "/users/7").Body -->
askUsers("HEAD", "/users/7").Status -->
askUsers("DELETE", "/users/7").Status -->
```

Le chemin vient d'abord : un chemin que seules des routes d'autres méthodes prennent reçoit un `405`, Method Not Allowed
(méthode non permise), et un `HEAD` la route de son `GET`, dont le serveur laisse le corps de côté.

[http.Handler] range les routes, une fois, dans un [trie](glossary.md#trie) des parties de leurs chemins, un arbre où
chaque niveau est choisi par une partie : chaque partie écrite mène à une branche à elle, trouvée par une table de
hachage, et les parties `:` d'une même place partagent une branche. Une requête suit les parties de son propre chemin dans
l'arbre, si bien que trouver sa route coûte autant parmi 500 routes que parmi 5. Chaque route garde sa place dans l'ordre
où elles ont été ajoutées, et la marche laisse de côté une branche dont toutes les routes viennent après celle déjà
trouvée : la réponse est toujours celle que donneraient les routes essayées une à une, ce que `tests/lang/http-routes.ce`
vérifie sur des ensembles de routes tirés au hasard.

Une API de 200 routes, 40 ressources avec leur liste, leur création, un élément, son changement et sa suppression :

```cesia
defn api(resources)
  a = http.App()
  for name in resources
    a = a
      then http.Get("/api/v1/$name", r -> http.Json([]))
      then http.Post("/api/v1/$name", r -> http.Json({Made: true}, status = 201))
      then http.Get("/api/v1/$name/:id", r -> http.Json({Id: r.Params.id}))
      then http.Put("/api/v1/$name/:id", r -> http.Json({Changed: r.Params.id}))
      then http.Delete("/api/v1/$name/:id", r -> http.Plain("", status = 204))
  end
  a
end
shopApi = http.Handler(api(["res$i" for i in 1..40]))
askApi(method, path) = shopApi({Method: method, Path: path, Query: "", Headers: [], Body: ""})
askApi("GET", "/api/v1/res40/7").Body -->
askApi("PATCH", "/api/v1/res40/7").Status -->
```

Ce que cela coûte, mesuré le 2026-11-25 sur la machine de [Vitesse](speed.md#à-côté-des-géants) : le handler appelé avec
une requête et sans réseau, donc la route, ses params et la réponse du handler, en microsecondes, les médianes de 5
lancements alternés avec la version d'avant l'arbre, qui essayait les routes une à une, et à côté du `ServeMux` de Go
1.26.3 qui fait la même chose, son `ServeHTTP` appelé directement.

| Routes, et celle demandée | Une à une | L'arbre | Le `ServeMux` de Go |
|---|---:|---:|---:|
| 10, la première | 3,0 | 3,1 | 0,32 |
| 10, la dernière | 6,7 | 2,8 | 0,30 |
| 100, la dernière | 44,8 | 2,8 | 0,28 |
| 500, la dernière | 235 | 2,9 | 0,33 |
| 500, un chemin qu'aucune ne prend : un `404` | 243 | 0,84 | 1,48 |
| l'API ci-dessus, son dernier élément | 159 | 3,5 | 0,36 |

Go est de 8 à 12 fois plus rapide sur une route qui répond, puisque son handler est compilé là où celui de Cesia tourne
dans l'interpréteur : une requête qu'aucune route ne prend ne lance aucun handler, et reçoit son `404` de Cesia en
0,84 µs, plus vite que Go. L'arbre coûte une fois ce que les routes essayées une à une ne coûtaient pas : 91 µs à
construire pour les 200 routes de l'API, quand [http.Handler] est appelé, au démarrage d'un serveur.

## Du JSON en entrée

[http.BodyJson] lit le corps d'une requête comme du JSON. Avec `From`, le corps est vérifié avant que votre code s'en
serve, et un corps faux reçoit un `400` qui dit ce qui ne va pas :

```cesia
use std/result
struct Purchase
  Product Text
  Units Int
end

defn addPurchase(request)
  match http.BodyJson(request) then result.AndThen(Purchase.From)
    result.Ok(order) -> http.Json({Product: order.Product, Units: order.Units, Total: order.Units * 1.25}, status = 201)
    result.Err(e) -> http.Json({Error: e.Message}, status = 400)
  end
end

shop = app then http.Post("/orders", addPurchase)
post(body) = http.Handler(shop)({Method: "POST", Path: "/orders", Query: "", Headers: [], Body: body})
io.Print(post("{\"Product\": \"bread\", \"Units\": 4}").Body)
io.Print(post("{\"Product\": \"bread\", \"Units\": \"four\"}").Body)
io.Print(post("not json").Body)
```

## Middleware

Un [middleware](glossary.md#middleware) se place devant les routes : il voit chaque requête, et la réponse qui revient.
[http.Logger] écrit une ligne par requête, comme le dit [Logs et métriques](#logs-et-métriques). [http.Wrap] place un
middleware devant une application :

```cesia
logged = http.Wrap(http.Logger, shop)
http.Handler(logged)({Method: "GET", Path: "/stock", Query: "", Headers: [], Body: ""}).Status -->
```

### Un middleware à vous

Un middleware à vous est une fonction de `next` et de la requête, qui appelle `next(request)` pour continuer. `servedBy`
ajoute à chaque réponse un header (une ligne d'en-tête, un nom et une valeur) qui dit ce qui l'a servie :

```cesia
defn servedBy(next, request)
  response = next(request)
  http.WithHeader("x-served-by", "cesia", response)
end
http.Handler(http.Wrap(servedBy, shop))({Method: "GET", Path: "/", Query: "", Headers: [], Body: ""}).Headers -->
```

![Une requête GET / passe par le middleware servedBy, qui appelle next(request), puis par les routes de shop, où la première qui convient, GET /, mène à son handler, qui donne 200 et Welcome ; la réponse revient par servedBy, qui ajoute le header x-served-by, et repart avec 2 headers.](../../book/images/http-middleware.svg)

## Servir

[http.Serve] sert une application jusqu'à ce que le programme reçoive un signal d'arrêt, comme Ctrl-C : voir
[Arrêter](#arrêter). Il écoute sur le port 8080, sauf si `port` dit autrement, et sur `127.0.0.1`, cette machine
seulement, sauf si `host` dit autrement. Il lui faut la permission d'écouter sur son port. Voici un petit `shop.ce` :

```cesia norun
(* shop.ce: one route, served on port 8080 *)
use std/http

hello = http.App()
  then http.Get("/hello/:name", r -> http.Plain("Hello, $(r.Params.name)!"))
http.Serve(http.Wrap(http.Logger, hello))
```

Lancez-le, et interrogez-le depuis un autre terminal :

```bash
cesia run --allow net=:8080 shop.ce
curl localhost:8080/hello/Ana
```

Chaque réponse qu'il envoie a un en-tête `Date`, l'heure de la réponse dans la forme de la RFC 9110 (section 5.6.7), comme
`date: Wed, 25 Nov 2026 13:40:00 GMT`, puisqu'un serveur qui a une horloge doit en envoyer un (section 6.6.1) : les caches
et les clients y lisent l'âge d'une réponse. Le serveur récrit la ligne quand la seconde change, pas à chaque réponse. Un
handler qui met sa propre `Date`, par [http.WithHeader], la garde ; les réponses de [http.Handler], qu'aucun réseau ne
porte, n'en ont pas.

### Arrêter

Un signal d'arrêt arrête proprement un serveur : TERM, que systemd, Docker et Kubernetes envoient, INT, qu'envoie Ctrl-C,
ou HUP, qu'un terminal envoie en se fermant. Le serveur n'accepte plus de connexions, et les requêtes en cours se
terminent, chacune avant son échéance, avec une réponse qui dit à son client que la connexion se ferme, pour que le client
redemande ailleurs. Puis [http.Serve] donne `Ok`, et le programme continue jusqu'à sa fin, ce qui donne l'exit code (le
nombre que le programme rend à celui qui l'a lancé) 0, sauf s'il en décide autrement. Un second signal n'attend pas : le
programme s'arrête aussitôt, avec 128 plus le numéro du signal, 143 pour TERM et 130 pour INT, comme les donne un shell
(le programme qui lit vos commandes dans le terminal). Les programmes qu'il a démarrés avec [sys.Start] ou [sys.Run]
reçoivent aussi le premier signal, comme le dit le chapitre [Fichiers](files.md#les-programmes-qui-continuent-de-tourner).
Lancé par `cesia do serve`, le serveur reste un seul processus : la dernière tâche prend la place de `cesia do`, comme le
dit le chapitre Commandes, si bien que le TERM d'un superviseur lui arrive une seule fois, et que son arrêt est propre.

### Tous les cœurs

Un serveur tourne sur un cœur. `--workers` en fait tourner plusieurs, qui servent ensemble le même port, autant que `N`, ou
un par cœur avec `cores` :

```bash
cesia run --workers cores --allow net=:8080 shop.ce
```

Le premier processus exécute le programme jusqu'à son listener (la socket qui accepte les connexions), l'ouvre, et devient
le supervisor : il démarre les workers (les processus qui servent) et ne sert rien lui-même. Chaque worker exécute le
programme depuis son début, et prend ses connexions sur ce même listener, que le supervisor garde ouvert. Les workers ne
partagent rien d'autre que le port : chacun a sa mémoire, ses fibers (des fonctions qui tournent côte à côte dans le même
programme) et ses valeurs, comme des programmes à part, et ce qu'ils doivent partager va dans une base de données. Le
supervisor redémarre un worker qui s'arrête, et TERM ou Ctrl-C les arrête tous, chacun comme le dit [Arrêter](#arrêter) ;
il termine avec 0 quand ils l'ont tous fait. Un programme qui ne peut pas démarrer, comme un programme qui a une erreur,
s'arrête aussitôt, avec le code de son premier worker. `--workers` demande Linux ou macOS : sous Windows, un programme sert
sur un seul cœur. C'est le modèle *pre-fork* de nginx : des processus, pas des threads (des fils d'exécution d'un même
processus, qui partagent sa mémoire), si bien qu'un bug dans un worker ne peut pas toucher la mémoire d'un autre, et que le
supervisor en démarre un nouveau ; [Comment Cesia fonctionne](internals.md#sur-chaque-cœur) le montre en détail.

Mesuré le 2026-11-07 sur la machine de [Vitesse](speed.md#à-côté-des-géants), en une exécution de
`tools/http-bench.sh`, le serveur sur deux cœurs physiques et leurs deux hyperthreads, et le client de charge sur les
quatre autres ; en requêtes par seconde :

| Charge | 1 processus | `--workers 2` | `--workers 4` | Go, 4 cœurs |
|---|---:|---:|---:|---:|
| route minimale, 100 connexions gardées ouvertes | 57 215 | 116 982 | 94 978 | 98 479 |
| route minimale, 1 000 connexions gardées ouvertes | 34 752 | 67 890 | 84 188 | 89 337 |
| route JSON, 100 connexions gardées ouvertes | 41 340 | 80 020 | 72 132 | 78 988 |
| une nouvelle connexion par requête, 100 | 28 674 | 45 850 | 38 690 | 29 750 |

```cesia allow=read,write
use std/plot
workers = plot.Bars(["tiny 100", "tiny 1,000", "JSON 100", "new 100"], [[57215, 34752, 41340, 28674],
  [116982, 67890, 80020, 45850], [94978, 84188, 72132, 38690], [98479, 89337, 78988, 29750]],
  label = ["1 process", "--workers 2", "--workers 4", "Go, 4 cores"], color = ["#9aaae8", "#3a5ad9", "#1d2d6c", "#000000"])
cores = plot.Of([workers], title = "Requests per second on four cores, one run",
  x = "route, connections", y = "requests per second", size = [640, 360])
plot.Save(cores, "http-workers.svg") -->
```

Deux workers font le double d'un seul processus. Quatre ne gagnent qu'à 1 000 connexions, puisque la machine a quatre
cœurs physiques, dont deux faisaient tourner le client.

### Une nouvelle version sans pause

HUP remplace les workers d'un serveur lancé avec `--workers` : les nouveaux démarrent à partir des fichiers tels qu'ils
sont maintenant, et dès que chacun d'eux accepte des connexions, les anciens s'arrêtent comme sur TERM, chacun après ses
requêtes en cours. Le listener ne se ferme jamais : aucune connexion n'est refusée ni perdue entre-temps, et aucune requête
n'échoue. Une nouvelle version qui ne peut pas démarrer, comme une version qui a une erreur, laisse tranquilles les workers
qui tournent :

```bash
kill -HUP $(pgrep -o -f "cesia run --workers")
```

Sous systemd, `ExecReload=/bin/kill -HUP $MAINPID` le fait avec `systemctl reload`. Sans `--workers`, HUP arrête le
serveur, comme TERM.

### Logs et métriques

[std/log] écrit une ligne de JSON pour chaque événement, avec son heure en UTC, son niveau et son message, puis les champs
donnés : des outils comme jq, Loki ou Datadog les lisent au fur et à mesure. [log.Info], [log.Warn] et [log.Error] donnent
le niveau :

```cesia
use std/log
log.Info("order placed", {Order: 7, Total: 12.5})
```

[http.Logger] écrit une de ces lignes pour chaque requête, avec sa méthode, son chemin, son statut et les millisecondes
qu'elle a prises. [std/metrics] compte : [metrics.Add] ajoute à un compteur, [metrics.Observe] range une valeur, comme les
secondes qu'a prises une requête, dans un histogramme, et [metrics.Text] les donne toutes dans le format texte que lit
Prometheus, pour une route du programme. [http.Metrics] compte chaque requête par méthode et par statut, avec sa durée :

```cesia
use std/metrics
use std/text
counted = shop then http.Get("/metrics", r -> http.Plain(metrics.Text())) then http.Wrap(http.Metrics)
http.Handler(counted)({Method: "GET", Path: "/stock", Query: "", Headers: [], Body: ""}).Status -->
text.Contains("http_requests_total{method=\"GET\",status=\"200\"} 1", metrics.Text()) -->
```

Rien n'est écrit dans le log ni compté sauf si le programme le demande. Une ligne de log coûte environ 5 microsecondes et
un comptage environ 3, ce que voit un serveur qui répond en 17 : sur un cœur, à 100 connexions gardées ouvertes, une route
minimale répondait à 57 000 à 60 000 requêtes par seconde sans eux, 44 000 à 49 000 avec [http.Logger], et 50 000 à
53 000 avec [http.Metrics], mesuré le 2026-11-07. Avec `--workers`, chaque worker compte ses propres requêtes, et un
scrape (la lecture des compteurs par Prometheus) lit les comptes du worker qui lui répond ; leurs lignes de log ne se
coupent pas les unes les autres.

### OpenTelemetry

[std/otel] envoie ce que fait un serveur à un *collector* d'[OpenTelemetry](https://opentelemetry.io/) (le programme
qui reçoit ces données, puis les garde ou les fait suivre ; OpenTelemetry est le standard ouvert de ces données), par
son protocole, OTLP sur HTTP, en protobuf (le défaut, une forme binaire compacte) ou en JSON : les **traces**,
l'histoire de chaque requête, un *span* pour son tout et un pour chaque appel qu'elle fait à l'intérieur, chacun avec
son début, sa durée et ses *attributes* (ses attributs : ce qu'il concernait) ; les **métriques**, celles de
[std/metrics] relues, une seule source de nombres pour Prometheus et pour OTLP ; les **logs**, chaque ligne de
[std/log] avec la trace dans laquelle elle a été écrite. Tout collector qui prend l'OTLP les montre : Jaeger, Grafana
Tempo, l'OpenTelemetry Collector, et les services de Datadog, Honeycomb ou Elastic.

[otel.Start] donne un tracer (ce qui crée les spans) ; [otel.Server] ouvre le span d'une requête, nommé par sa méthode
et sa route (son motif, jamais son chemin, qui ferait un nom par requête), et lit le header `traceparent` du W3C (la
ligne d'en-tête qui porte les numéros de la trace) qu'envoie un appelant ; [otel.Begin] ouvre un span à l'intérieur du
span en cours, [otel.End] termine l'un ou l'autre. Ici, le collector est une fonction du programme (`send`), pour voir
ce qui part :

```cesia
use std/json
use std/otel
use std/result
keep(path, body, headers) = result.Ok({Status: 200, Headers: []})
t = otel.Start(service = "shop", protocol = "json", send = keep)!
defn stock(r)
  span = otel.Server(t, r.Method, "/stock", r.Headers)
  inner = otel.Begin("count the cakes")
  otel.End(inner)
  otel.End(span, attributes = {"http.response.status_code": 200})
  http.Json({Cakes: 12})
end
http.Handler(http.App() then http.Get("/stock", stock))({Method: "GET", Path: "/stock", Query: "", Headers: [], Body: ""}).Status -->
otel.Flush(t)
otel.Counts(t).Spans -->
```

Le span de la fiber est son **contexte** : une fiber qu'elle lance commence dedans, une ligne de [std/log] écrite
dedans porte son `trace_id` et son `span_id`, [otel.Headers] donne le `traceparent` qu'une requête sortante porte pour
continuer la trace, et chaque appel d'un moteur natif fait dedans, comme le `cepheus.Get` de Cepheus, est un span à lui
seul (`db.system.name` cepheus). Un `traceparent` venu du dehors est celui de n'importe qui : par défaut
(`trust = "restart"`), [otel.Server] commence une nouvelle trace qui a un *link* (un lien) vers lui, pour que personne
au dehors ne choisisse la trace ni son *sampling* (l'échantillonnage : le tri qui ne garde qu'une part des traces) ;
`trust = "trust"` continue avec lui, pour un service placé derrière un autre service à soi.

`sample` est la part des traces gardées (1 : toutes) ; une trace non gardée ne crée aucun span, elle fait seulement
suivre ses ids, ce qui coûte 2,7 µs par requête ; `always` garde quand même le span d'une requête qui a échoué, ou qui
a pris plus de `slow` secondes. Les spans attendent dans une file qui ne fait jamais attendre une requête : au-delà de
`queue` (2 048), ils sont jetés et comptés dans `otel_dropped_total` ; une fiber les envoie par *batches* (des lots)
toutes les `every` secondes, et réessaie un collector occupé ou parti après une pause tirée au hasard sous une borne
qui double (le *full jitter*), ou après son `Retry-After`, cinq fois. Ils attendent déjà encodés, tels qu'ils partiront :
une file pleine de 2 048 spans prend 1,2 Mo en protobuf, 2,3 en JSON. Une métrique de [std/metrics] tient au plus
2 000 séries, les autres comptées dans une seule, `otel_metric_overflow="true"`, comme le conseille OpenTelemetry : un
label (une étiquette qui découpe une métrique en séries, comme `method`) fait de ce qu'envoie un client, comme une
méthode, ne peut pas remplir la mémoire.

Un span gardé coûte environ 15 µs de son début au collector, en protobuf comme en JSON ; protobuf envoie 2,4 fois moins
d'octets, environ 210 pour le span d'une requête et 140 pour un span à l'intérieur, JSON 500 et 360.
`compression = "gzip"` (zlib, avec la permission `ffi=z`) les réduit encore, pour un collector de l'autre côté d'un
réseau. Centauri trace chaque requête de cette façon avec un seul réglage, `APP_OTEL=on`, et les clics de ses pages
avec elles ([la Télémétrie de Centauri](https://github.com/www-celestial/centauri/blob/main/docs/book/telemetry.md)).

```go
// Go: go.opentelemetry.io/otel, its SDK, its exporter of OTLP over HTTP and otelhttp, wired at the start
tp := sdktrace.NewTracerProvider(sdktrace.WithBatcher(exp), sdktrace.WithResource(res))
otel.SetTracerProvider(tp)
http.Handle("/stock", otelhttp.NewHandler(http.HandlerFunc(stock), "GET /stock"))
```

### Servir et interroger dans un seul programme

Le bloc ci-dessous sert la boutique sur un port et l'interroge avec le client, [http.Fetch], dans un seul programme.
[fiber.Spawn] fait tourner le serveur à côté du reste du programme, comme l'explique le chapitre [Fibers](fibers.md), et
[sys.Sleep] le laisse démarrer. `net=own` est la permission pour cela : le programme écoute sur cette machine, et ne se
connecte qu'à ses propres listeners.

```cesia allow=net=own
use std/sys
use std/fiber
fiber.Spawn(() -> http.Serve(logged, port = 18761))
sys.Sleep(0)
r = http.Fetch("http://127.0.0.1:18761/hello/Bo")
r.Value.Status -->
r.Value.Body -->
sent = http.Fetch("http://127.0.0.1:18761/orders", method = "POST", body = "{\"Product\": \"cake\", \"Units\": 2}")
io.Print(sent.Value.Body)
```

Le programme se termine quand sa dernière ligne est faite, et le serveur avec lui.

### Ce que tient un serveur

Un serveur fait face à des clients lents, gourmands ou cassés, et continue de servir les autres :

- Chaque requête a `timeout` secondes, 60 sauf si [http.Serve] dit autrement, pour arriver et recevoir sa réponse. Un
  client qui envoie un octet à la fois est fermé à son échéance. Pour un handler qui prend plus longtemps, son client
  reçoit un `503`, et le handler continue de tourner seul ; [fiber.Wait] avec un `timeout` est la façon dont le serveur
  l'attend.
- Une tête de requête (la ligne de la requête et ses headers) de plus de 16 KB reçoit un `431`, un corps plus grand que
  `maxBody`, 1 MB sauf si [http.Serve] dit autrement, un `413`.
- Les corps lus en même temps prennent au plus un quart de la limite de mémoire, que fixe `--limit memory=` et qui vaut
  sinon 80 % de la RAM : au-delà, une requête avec un corps reçoit aussitôt un `503`, au lieu que le serveur atteigne la
  limite.
- Un handler qui s'arrête sur une panic (l'arrêt net sur un bug) vaut un `500` à son client, comme un handler qui prend plus de mémoire
  que la limite : seule sa requête échoue.

### Un corps en morceaux

Une réponse est faite en entier avant de partir, ce qu'un export d'une grande table ne peut pas se permettre.
[http.Stream] envoie son corps en morceaux à mesure qu'ils sont faits, chacun un *chunk* (un morceau) de HTTP/1.1
(RFC 9112, section 7.1) : `send(piece)` en donne un au client, et le corps finit quand la fonction rend la main.

```cesia norun
use std/csv
use std/result
invoices(page) = [["INV-$page", "paid", 120]]   (* a page of the table, as a database gives it *)
defn export(send)
  for page in 1..100
    send(csv.Text(invoices(page)))?
  end
  result.Ok(missing)
end
app = http.App() then http.Get("/invoices.csv", r -> http.Stream(export, headers = [{Name: "content-type", Value: "text/csv"}]))
```

- `send` donne un `Err` dès que le client est parti, ou quand un morceau a pris plus de `timeout` secondes à venir ou à
  être pris : un client qui cesse de lire tient la fiber du serveur un timeout, et un morceau en mémoire, pas plus. Le
  `?` après `send` arrête alors l'export.
- Une panic au milieu, ou un `Err` que donne la fonction, coupe le corps avant son dernier chunk, si bien que le client
  voit une erreur plutôt qu'un corps qui a l'air entier.
- `HEAD` reçoit la tête seule, et la fonction ne tourne pas ; un client de HTTP/1.0, qui ne connaît pas les chunks,
  reçoit les morceaux tels quels, et la connexion finit avec le corps.

Mesuré le 2026-11-13, un export de 100 000 lignes de 7 cellules, 6 MB de CSV, les lignes faites à mesure qu'on les
demande, comme une base de données les donne (`bench/export.ce`) : le pic de la mémoire du serveur a grandi de 77 MB
pour le corps entier, de 32 MB par morceaux de 1 000 lignes, surtout ce que le ramasse-miettes (le collector) n'avait
pas encore repris des pages d'avant.

### Un corps qui arrive en morceaux

Le corps d'une requête est lu en entier avant que son handler tourne, `maxBody` octets au plus : un fichier envoyé au
serveur n'y tient pas. Une route à qui l'on donne `stream`, le plus d'octets que son corps peut tenir, reçoit en morceaux
un corps trop grand pour une seule lecture, à mesure que le handler les lit : `r.Body` vaut `""`, `r.Size` donne sa
longueur, et `r.Read()` donne un `Ok` du morceau suivant, `""` une fois tout lu, ou un `Err` quand le client cesse
d'envoyer.

```cesia norun
use std/result
use std/text
defn upload(r)
  (* stores a scan as it comes; a small one came whole, in r.Body *)
  n = 0
  piece = r.Read()?
  while piece != ""
    n += text.ByteLength(piece)   (* write it where it goes: a part of a file of the database *)
    piece = r.Read()?
  end
  http.Plain("$n bytes")
end
app = http.App() then http.Route("POST", "/scans", upload, stream = 10485760)
```

- Le corps n'est lu que quand le handler le demande, un morceau à la fois (ce qu'apporte une lecture du socket, 64 Kio
  au plus) : le serveur ne le tient jamais en entier, quelle que soit sa taille.
- Un corps plus grand que `stream` reçoit un `413` avant que le handler tourne ; une tête à deux lignes `Content-Length`
  un `400`, comme toute requête.
- Un client qui a envoyé `Expect: 100-continue`, comme curl pour un grand corps, n'est invité à continuer qu'au premier
  `Read` : un handler qui refuse d'abord la requête (un `401`, un type qu'il ne prend pas) répond avant que le client ait
  envoyé son corps.
- Le handler a le `timeout` de la requête, plus une seconde par tranche de 64 Kio du corps, et chaque morceau doit
  arriver dans les `timeout` secondes qui suivent le précédent : un client qui envoie un octet par minute est fermé, un
  client sur une ligne lente ne l'est pas.
- La connexion se ferme après la réponse.
- Un corps arrivé en entier, assez petit pour une seule lecture, est dans `r.Body`, et `r.Read` manque : un handler qui
  prend les deux cherche `Read` avec `dict.Has("Read", r)`.

## Le reste de std/http

| Pour | Utilisez |
|---|---|
| ajouter une route | [http.Get], [http.Post], [http.Put], [http.Delete], [http.AnyMethod] pour n'importe quelle méthode, [http.Route] pour une méthode donnée par son nom ; un `*` final dans un chemin en prend le reste, dans `r.Params["*"]` |
| servir des fichiers | [http.Static] sert un dossier sous un préfixe, et aucun chemin ne peut sortir du dossier ; [http.FileResponse] envoie un fichier, avec son type d'après son extension |
| répondre | [http.Plain], [http.Json], [http.Html], [http.Redirect], [http.NotFound], [http.Stream] pour un corps en morceaux ; [http.WithHeader] ajoute un header, [http.SetCookie] un cookie ; [http.Reason] est le texte d'un statut |
| lire une requête | [http.BodyJson] son corps en JSON, [http.Form] comme formulaire, [http.HeaderValue] un header par son nom en minuscules ; `r.Peer` est l'adresse du client, sans son port, telle que [net.Peer] la donne, pour limiter un client ; [http.ParseUrl] décompose une URL |
| passer des données | un middleware met une clé dans la requête, comme la personne connectée, et le handler l'y trouve : voir [http.Wrap] |
| envelopper | [http.Logger], [http.Metrics], [http.Cors], qui laisse les pages d'une autre origine (d'un autre site) lire les réponses, et [http.SameOrigin], qui refuse les requêtes d'un autre site : voir plus bas |
| écrire du HTML | [http.Escape] échappe une valeur pour une page, [http.Template] remplit `{{name}}` avec des valeurs échappées |
| les valeurs par défaut | [http.DefaultTimeout] vaut 60 secondes, [http.DefaultMaxBody] 1 048 576 octets |

```cesia
files = http.App() then http.Route("PATCH", "/files/*", r -> http.Plain(r.Params["*"]))
http.Handler(files)({Method: "PATCH", Path: "/files/a/b.txt", Query: "", Headers: [], Body: ""}).Body -->
http.Redirect("/login").Headers -->
http.Reason(404) -->
http.Template("<p>Hello, {{name}}!</p>", {name: "<Ana>"}) -->
```

### Échapper

[http.Template] et [http.Escape] écrivent `<` comme `&lt;`, `&` comme `&amp;` et les guillemets comme `&quot;` et `&#39;` :
ils échappent la valeur, c'est-à-dire qu'ils écrivent ses caractères spéciaux pour qu'ils s'affichent tels quels. Sans
cela, un nom tapé par un visiteur, comme `<script>...</script>`, s'exécuterait comme du code dans la page de tous les
autres visiteurs : c'est le *cross-site scripting*, XSS. Une valeur entre dans une page échappée, comme une valeur entre
dans du SQL par `?`.

### Des requêtes d'un autre site

Une page d'un autre site peut faire envoyer au navigateur d'un visiteur une requête à votre application, avec les
cookies du visiteur : un formulaire qui poste vers `/pay`, une WebSocket qui s'ouvre. C'est la *cross-site request
forgery*, CSRF (la falsification d'une requête par un autre site). [http.SameOrigin], un middleware, répond `403` à
une telle requête quand elle peut changer quelque chose : toute méthode sauf `GET`, `HEAD` et `OPTIONS`, et le `GET`
qui ouvre une WebSocket.

```cesia
pay = http.Handler(http.App() then http.Post("/pay", r -> http.Plain("paid")) then http.Wrap(http.SameOrigin))
pay({Method: "POST", Path: "/pay", Query: "", Headers: [{Name: "sec-fetch-site", Value: "cross-site"}], Body: ""}).Status -->
pay({Method: "POST", Path: "/pay", Query: "", Headers: [{Name: "sec-fetch-site", Value: "same-origin"}], Body: ""}).Status -->
```

Il lit ce qu'écrit le navigateur, qu'aucune page ne peut changer :

- `Sec-Fetch-Site`, que tous les navigateurs envoient depuis 2023 (W3C, Fetch Metadata) : `same-origin` passe, et
  `none`, une adresse que la personne a tapée ; `same-site`, un hôte voisin comme `blog.shop.example`, et `cross-site`
  reçoivent le `403`.
- Sans lui, l'`Origin` d'un navigateur plus ancien, `scheme://host:port`, doit être `http://` ou `https://` suivi du
  `Host` de la requête, son port compris. Les lettres A à Z se valent en majuscule et en minuscule, tout autre octet ne
  vaut que lui-même : un navigateur écrit un nom international en Punycode, en ASCII (RFC 6454), donc aucun changement
  de casse ne fait de deux hôtes un seul.
- Une requête sans l'un ni l'autre ne vient d'aucun navigateur, donc des cookies d'aucun visiteur : elle passe, et
  l'application vérifie qui l'a envoyée, par un cookie ou un token.

Ce sont les étapes de `http.CrossOriginProtection` dans Go 1.25, avec leur limite : par l'`Origin` seul, le scheme
(`http` ou `https`) n'est pas vérifié, puisque le `Host` n'en a pas ; un navigateur ancien laisse donc une page de
`http://shop.example`, qu'une machine sur le chemin peut falsifier, poster vers `https://shop.example`. HSTS, le header
`Strict-Transport-Security`, ferme cette porte : le navigateur n'ouvre jamais la page `http://`. [live.Route] vérifie
ses WebSockets de la même façon.

## WebSocket

Une *WebSocket*, RFC 6455, est une connexion qui reste ouverte après une requête HTTP et porte des messages dans les deux
sens, pour un chat ou une page en direct. [http.Websocket] ajoute une route pour en servir une : `onMessage(text, send)`
tourne pour chaque message, et `send(text)` répond. Le handshake (l'échange qui ouvre la connexion), l'*upgrade* de la
requête (son passage de HTTP à WebSocket), donne le statut `101` ; [std/websocket] fait le reste, avec
[websocket.Accept], une connexion silencieuse fermée au bout de [websocket.DefaultIdle] secondes, et une frame (un message
tel qu'il passe sur la connexion) plus grande que [websocket.MaxFrame] refusée :

```cesia
chat = http.Handler(http.App() then http.Websocket("/chat", (m, send) -> send(m)))
handshake = [{Name: "upgrade", Value: "websocket"}, {Name: "sec-websocket-key", Value: "dGhlIHNhbXBsZSBub25jZQ=="}]
chat({Method: "GET", Path: "/chat", Query: "", Headers: handshake, Body: ""}).Status -->
chat({Method: "GET", Path: "/chat", Query: "", Headers: [], Body: ""}).Status -->
```

### Un client

[websocket.Dial] ouvre une connexion vers un serveur, comme le fait un navigateur : il se connecte à une URL `ws://` et
fait le handshake, la requête HTTP par laquelle le client demande au serveur de passer la connexion en WebSocket. Il
donne un `Ok` d'une [websocket.Conn], dont le champ `Messages` est un channel de [std/fiber] : chaque message du serveur
y arrive entier, dans l'ordre, et le channel se ferme quand la connexion finit. [websocket.Send] envoie un message texte,
et [websocket.Close] ferme la connexion et dit comment elle a fini :

```cesia allow=net=own
use std/websocket
use std/net
use std/fiber
listener = net.Listen(0).Value
fiber.Spawn(() -> http.Serve(http.App() then http.Websocket("/echo", (m, send) -> send(m)), listener = listener))
c = websocket.Dial("ws://127.0.0.1:$(net.Port(listener))/echo").Value
websocket.Send("hi", c) -->
fiber.Receive(c.Messages, timeout = 1) -->
websocket.Close(c) -->
```

`headers`, une liste de `{Name, Value}` comme celle que prend [http.Fetch], part avec le handshake : un cookie, pour un
serveur qui reconnaît ses visiteurs par un cookie, ou un `Origin`, pour un serveur qui vérifie d'où vient une page,
comme le fait [http.SameOrigin]. Un nom qui n'est pas un *token* de la RFC 9110, fait de lettres, de chiffres et de
signes comme `-` et `_`, un nom que le handshake écrit lui-même (`Host`, `Upgrade`, `Connection`, `Content-Length`,
`Transfer-Encoding`, et ceux qui commencent par `Sec-WebSocket-`), ou un retour à la ligne ou un octet nul dans une
valeur, donne un `Err` avant toute connexion : une valeur venue d'un visiteur ne peut pas ajouter un header à elle,
ce qui serait une *header injection* (l'injection d'un header).

```cesia allow=net=own
websocket.Dial("ws://127.0.0.1:1/", headers = [{Name: "Cookie", Value: "sid=1\r\nX-Admin: 1"}]) -->
```

Recevoir n'a pas de fonction à soi : c'est le channel, donc tout ce que les [Fibers](fibers.md) font d'un channel marche
avec lui : une boucle `for`, qui est [fiber.Receive] encore et encore jusqu'à ce que le channel se ferme, une limite de
temps, [fiber.Select]. La connexion vient en dernier dans [websocket.Send],
comme le channel dans [fiber.Send] : une connexion porte des messages comme un channel. Plusieurs fibers peuvent envoyer
en même temps ; chaque message part entier.

```cesia norun
for m in c.Messages
  io.Print(m)
end
got = fiber.Select([sys.Stops(), c.Messages], timeout = 30)
```

Ce que le client fait pour la RFC 6455, pour qu'un programme n'ait jamais à le faire :

- Chaque frame qu'il envoie, un en-tête de quelques octets puis les octets du message, est *masquée* (*masked*) : ses
  octets sont combinés par un ou exclusif (*xor*) avec une clé de 4 octets, neuve pour chaque frame, tirée de la source
  d'aléa du système (§5.3). Un proxy entre les deux, un programme qui fait passer les octets, ne voit ainsi jamais des
  octets que le programme a choisis, et on ne peut pas lui faire garder dans son cache une réponse falsifiée (§10.3).
- Il répond à chaque *ping*, une frame par laquelle le serveur vérifie que le client est toujours là, par un *pong* des
  mêmes octets (§5.5.2), et il recolle les *fragments* d'un message, les frames en lesquelles un serveur peut le couper,
  une seule fois, à sa fin (§5.4).
- Il refuse ce que la RFC refuse, et ferme avec le *close code* (le code de fermeture), un nombre qui dit pourquoi :
  1002, une erreur de protocole, pour une frame masquée venue du serveur, un bit ou un opcode (le numéro du genre de
  frame) réservés, ou une frame de contrôle de plus de 125 octets (§5.1, §5.2, §5.5) ; 1007 pour un texte qui n'est pas
  de l'UTF-8 (§8.1) ; 1009 pour un message de plus de `maxMessage` octets, [websocket.DefaultMaxMessage] (64 Mio) si
  `Dial` ne dit pas autre chose, refusé dès l'en-tête de sa frame, avant que ses octets soient lus (§10.4).
  [websocket.Close] donne alors le code, comme `1009: message too big`.
- [websocket.Close] envoie le code 1000, une fermeture normale, et attend au plus une seconde la fermeture du serveur,
  et que le serveur ferme la connexion TCP le premier (§7.1.1) ; puis il ferme lui-même.

`Messages` contient 64 messages. Tant qu'il est plein, le client ne lit plus rien du réseau, et TCP fait attendre le
serveur : c'est la [backpressure](glossary.md#backpressure) (la contre-pression) d'un channel qui a une taille. Les
messages déjà dans `Messages` arrivent encore après [websocket.Close] ; ceux qui arrivent après lui sont jetés, comme un
navigateur les jette.

Seulement `ws://` pour l'instant : `wss://`, WebSocket sur TLS, donne un `Err` qui le dit. Des messages texte seulement :
un message binaire reçu arrive comme un texte, puisqu'un texte de Cesia est fait d'octets, mais on ne peut pas encore en
envoyer. [websocket.Dial] demande la permission `net` de l'hôte, comme [http.Fetch] : `net=127.0.0.1:9222`, ou
`net=own` pour un serveur du programme lui-même. Chaque fois que le client change, et une fois par semaine, la CI joue
contre le client les cas d'Autobahn|Testsuite, la suite de référence de la RFC 6455 : tous, sauf ceux des messages
binaires à envoyer et de la compression (RFC 7692), qu'il ne fait pas.

Mesuré sur une machine, face à un même serveur d'écho écrit en Go avec gorilla/websocket 1.5.3, en
[médiane](glossary.md#median) de 11 essais : une connexion s'ouvre en 0,54 ms, un message de 100 octets fait l'aller et
le retour en 34 µs, et un de 1,4 Mo, la capture d'écran d'une page en Base64, en 4,7 ms. Le client de Go,
gorilla/websocket, est plus rapide : 0,47 ms, 23 µs et 3,3 ms. La WebSocket de Node 26 prend 55 µs et 6,5 ms, et 56 ms
pour sa première connexion, parce qu'elle charge alors son client. Un programme ne lit le client que s'il le nomme : un
serveur de [std/http] démarre comme avant.

## Live screens : std/live

Un *live screen*, un écran en direct, est une page dont les données changent d'elles-mêmes, à mesure que d'autres les
changent, sans que la page redemande rien : les factures impayées d'un client, un tableau de bord, un chat. Sans lui, la
façon habituelle est le *polling* (redemander sans cesse) : la page redemande toute la liste toutes les quelques
secondes, si bien qu'un changement apparaît jusqu'à autant de secondes plus tard, et le serveur répond de nouveau à
chaque page même quand rien n'a changé. [std/live] le fait plutôt avec une [WebSocket](#websocket) par page, et dans les
deux sens :

- l'application donne à chaque page ses *shows* (ce que la page montre) : un nom, et un channel de [std/fiber] dont les
  messages sont un résultat puis ses changements. La page reçoit le résultat, puis chaque changement, poussé vers elle
  dès qu'il arrive.
- la page demande à l'application des *actions* : un nom et les valeurs de la page, que fait tourner une fonction de
  l'application, dont la réponse revient à la page. La page montre aussitôt l'effet de sa propre action, avant la
  réponse, et la réponse le confirme ou l'annule : une [optimistic update](glossary.md#optimistic-update), une mise à
  jour optimiste.

Dans les deux exemples ci-dessous, l'application garde ses données derrière des fonctions à elle : `clientOf(r)`, le
client d'où vient une requête ; `unpaid(c)`, les factures impayées d'un client ; `addInvoice(c, a)`, qui en ajoute une ;
et, pour le live screen, `watchUnpaid(c, ended)`, un channel du résultat puis de ses changements, jusqu'à ce que `ended`
se ferme. Avec Cepheus, la dernière est `cepheus.Watch(1, unpaidOf(c), db, until = ended)?.Changes` : un watch de
Cepheus (une requête qu'il tient à jour) donne exactement ces messages.

```cesia norun hide=code
clientOf(r) = 1
unpaid(c) = []
addInvoice(c, a) = result.Ok(1)
watchUnpaid(c, ended) = fiber.Channel()
```

Avant, une page qui fait du polling :

```cesia norun
app = http.App()
  then http.Get("/unpaid", r -> http.Json(unpaid(clientOf(r))))
  then http.Post("/invoice", r -> http.Json(addInvoice(clientOf(r), http.BodyJson(r)?)))
```
```js
setInterval(async () => draw(await (await fetch("/unpaid")).json()), 2000)   // all again, every 2 s
```

Après, un live screen : [live.Route] sert les écrans d'un chemin, et le côté de la page, `live.js`, au chemin suivi de
`/live.js` :

```cesia norun
use std/live
screen(s) = [live.Show("unpaid", watchUnpaid(clientOf(s.Request), s.Ended))]
app = http.App() then live.Route("/live", screen, actions = {AddInvoice: (s, a) -> addInvoice(clientOf(s.Request), a)})
```
```js
import { connect } from "/live/live.js"
const live = await connect("/live")
live.show("unpaid", rows => draw(rows))          // at once, then at each change
add.onclick = () => live.act("AddInvoice", {Total: 90},
  {unpaid: rows => [...rows, {Invoice: null, Total: 90}]})   // drawn at once; the reply confirms or undoes it
```

`a then live.Route(pattern, screen)` est `live.Route(pattern, screen, a)`, comme pour [http.Get] : `then` passe son côté
gauche comme dernier argument.

### Un écran

`screen(s)` tourne quand une page se connecte. `s` est `{Request, Ended}` : la requête HTTP de la page, avec ses headers
et ses cookies, pour savoir qui elle est, comme le fait une route ; et un channel qui se ferme quand la page s'en va. La
fonction donne une liste de [live.Show], chacun un nom et un channel, ou un `Err`, que la page reçoit comme une erreur.
Chaque message du channel d'un show est d'abord le résultat, `{Group, Rows}` : ses lignes au groupe `Group`, un nombre
qui grandit à chaque changement ; puis chaque changement, `{Group, Added, Removed}` : les lignes arrivées et les lignes
parties avec ce groupe ; ou de nouveau le résultat entier. Un watch de Cepheus donne exactement ces messages, et
`until = s.Ended` le termine avec la page. Un channel à vous marche aussi :

```cesia allow=net=own
use std/live
use std/websocket
use std/json
use std/net
use std/fiber
defn counter(s)
  ch = fiber.Channel()
  fiber.Send({Group: 0, Rows: [{N: 0}]}, ch)
  fiber.Send({Group: 1, Added: [{N: 1}], Removed: [{N: 0}]}, ch)
  [live.Show("count", ch)]
end
listener = net.Listen(0).Value
fiber.Spawn(() -> http.Serve(http.App() then live.Route("/live", counter), listener = listener))
page = websocket.Dial("ws://127.0.0.1:$(net.Port(listener))/live").Value
websocket.Send(json.Text({Hello: 1}), page) -->
answer = json.Parse(fiber.Receive(page.Messages, timeout = 1).Value).Value[1]
[answer.Show, answer.Group, answer.Rows] -->
change = json.Parse(fiber.Receive(page.Messages, timeout = 1).Value).Value[1]
[change.Group, change.Added, change.Removed] -->
websocket.Close(page) -->
```

Dans un navigateur, la page est `live.js` ; ici, c'est le client de [std/websocket], qui montre ce qui passe sur la
connexion : la page dit `{"Hello": 1}`, puis chaque frame de l'application est une liste JSON de messages, chacun avec
`At`, l'heure de l'horloge de l'application, en microsecondes, au moment où elle a lu le message de son show.

Chaque écran a une [fiber](fibers.md) à lui, qui lit ses shows et n'écrit qu'à sa page : une page qui ne lit rien ne
retient aucune autre. Tant que sa page est lente, un écran attend sur sa connexion, et ne lit plus rien ; la source d'un
show, elle, n'attend donc jamais l'écran : elle donne à chaque écran un channel à lui, et quand l'un d'eux en contient
trop, elle jette ce qu'il contient et renvoie le résultat entier. Un watch de Cepheus le fait de lui-même, avec sa
`size` (64 messages sauf si on dit autrement) : une page trop en retard reçoit de nouveau le résultat entier plutôt que
chaque changement qu'elle a manqué, et la mémoire d'un écran ne grandit jamais avec une page lente.

### Les actions

`actions` associe des noms à des fonctions `(s, args)`, `args` étant les valeurs que la page a envoyées. La valeur d'une
action revient à la page comme sa réponse : la valeur d'un `Ok`, ou toute valeur qui n'est pas un `Err`, confirme
l'action, et un `Err` l'annule. Les actions d'une page tournent l'une après l'autre, dans l'ordre où elle les a
demandées, chacune dans une fiber à elle : une panic dans l'une est écrite dans [std/log], et la page apprend seulement
que l'action a échoué. Une action que l'écran n'a pas, une page qui envoie autre chose que ce qu'envoie `live.js`, sont
refusées. Les valeurs qu'envoie une page viennent de la page, et rien ne garantit ce qu'elles contiennent : une action
les vérifie, comme une route vérifie un formulaire.

Sur la page, `live.act(name, args, effects)` envoie l'action et donne une `Promise` (la promesse d'une valeur à venir)
de sa réponse. `effects` associe des noms de shows à des fonctions qui donnent les lignes avec l'effet de l'action : la
page dessine chaque show comme les lignes de l'application, avec par-dessus l'effet de chaque action encore sans
réponse, dans l'ordre où elles ont été demandées, et de nouveau à chaque changement. C'est ainsi que les jeux montrent
aussitôt les coups d'un joueur, et Replicache les écritures d'une page : la *client-side prediction* (la prédiction du
côté du client), puis la *reconciliation* (la réconciliation) quand l'état du serveur arrive. Une réponse retire
l'effet : aussitôt sur un `Err` ; sur un `Ok`, de chaque show qui a reçu un message depuis que l'action a été demandée,
et des autres à leur message suivant, au plus 100 ms plus tard, pour que la ligne de l'action ne soit dessinée ni deux
fois ni pas du tout, que son changement ou sa réponse arrive en premier. Pendant qu'une action tourne, l'écran retient
les changements de ses shows, au plus 0,1 s, et les envoie avec la réponse dans une seule frame. Une page dessine chaque
show au plus une fois par image de l'affichage, à `requestAnimationFrame`.

### Le côté de la page

`live.js` est servi au chemin de la route suivi de `/live.js` : un module de 383 lignes, sans rien à installer :

| | |
|---|---|
| `connect(url, options)` | ouvre l'écran : une `Promise` de l'écran, ou un refus quand aucun écran ne s'ouvre à `url` ; `options`, les réglages de la connexion propres à la page (plus bas), par-dessus ceux de l'application |
| `live.show(name, draw)` | `draw(rows)` avec les lignes d'un show, aussitôt si elles sont là, puis à chaque changement |
| `live.act(name, args, effects, base)` | une action : une `Promise` de sa réponse, ses effets dessinés aussitôt ; gardée tant que la page est coupée, envoyée à son retour |
| `live.onStatus(f)` | `f(status)` maintenant et à chaque changement de la connexion : `{State, Waiting, Retry, Last, Offline, Error}` |
| `live.onError(f)` | `f(error)` pour une erreur de l'écran, comme un `Err` de `screen` ou un show qui a pris fin |
| `live.now()`, `live.again()` | réessayer tout de suite pendant une coupure ; revenir après une erreur qui a fermé l'écran, comme une reconnexion du compte |
| `live.close()` | ferme l'écran, et le dit à l'application, qui le lâche aussitôt |

### Quand la connexion tombe

Une coupure de la connexion n'est pas une fin : un wifi perdu, un téléphone qui passe du wifi à la 4G avec une autre
adresse, un portable en veille, l'application redémarrée ou redéployée, un proxy qui coupe les connexions restées
muettes. Pour une coupure de quelques secondes à quelques minutes, la page revient d'elle-même et reprend là où elle
s'était arrêtée, une seule fois, comme le font la *connection state recovery* de Socket.IO (la reprise de l'état de la
connexion) et le *stateful reconnect* de SignalR (la reconnexion qui garde l'état) ; rien à écrire, d'un côté comme de
l'autre.

- **La page revient d'elle-même**, après une attente tirée au hasard entre 0 et une borne qui double à chaque échec,
  de `ReconnectFirst` (500 ms) à `ReconnectMax` (30 s) : le *full jitter* (l'attente entièrement tirée au hasard ; Marc
  Brooker, « Exponential Backoff And Jitter », AWS Architecture Blog, 2015), pour que mille pages coupées ensemble par
  un redémarrage ne reviennent pas toutes au même instant. Elle réessaie tout de suite quand le navigateur dit qu'il a
  de nouveau le réseau, et quand son onglet se montre de nouveau.
- **Un réseau muet est une coupure aussi** : un routeur tombé ou un câble débranché ne ferme rien, et TCP met des
  minutes à abandonner. La page envoie un ping (un petit message qui ne sert qu'à prouver que l'autre côté entend)
  toutes les `PingEvery` secondes (15), et aucune trame pendant `DeadAfter` secondes (30) est une coupure : les valeurs
  du `KeepAliveInterval` et du `ServerTimeout` de SignalR. Le `offline` du navigateur est une coupure aussitôt.
- **L'application garde l'écran** : une page qui dit `{"Hello": 2}` reçoit un écran qui survit à sa connexion, gardé
  `resume` secondes (120, le `maxDisconnectionDuration` de Socket.IO), ses shows continuant, les trames qu'il envoie
  numérotées (`{"Seq": n}` en tête) et gardées jusqu'à ce que la page dise qu'elle les a (`{"Got": n}`, au plus une
  seconde plus tard), `buffer` octets au plus (1 Mio ; SignalR en garde 100 000). La page revient avec son jeton
  (*token*) et la dernière trame qu'elle a : l'application lui envoie chaque trame d'après, une fois, et la page
  continue. *Rien de manqué, rien en double.*
- **Au-delà** (l'application redémarrée, un autre serveur, trop longtemps, trop de manqué), la page reçoit un nouvel
  écran, dont les premiers messages sont les résultats entiers : ses lignes sont remplacées, ses données rechargées,
  pas la page, et `onStatus` le dit (`Last: "reloaded"`).
- **Les actions attendent, dans l'ordre, chacune avec sa clé.** Une action demandée pendant la coupure est gardée,
  dans l'ordre des demandes, avec une clé faite au moment de la demande ; celle envoyée quand la connexion a lâché est
  gardée aussi, avec sa clé. De retour sur l'écran gardé, la page renvoie seulement celles que l'écran n'a pas
  entendues (`Heard`) ; sur un nouvel écran, toutes, chacune avec sa clé : `s.Key` dans l'action, qu'une application
  donne à son handler comme `Idempotency-Key` (la clé qui fait qu'une requête envoyée deux fois ne tourne qu'une fois),
  pour qu'elle tourne une seule fois (Centauri le fait). Au plus `OutboxCount` (100) et `OutboxBytes` (1 Mio)
  attendent ; au-delà, la suivante est refusée tout de suite ; celle qui a attendu `OutboxWait` secondes (une heure)
  échoue, en disant si elle a jamais été envoyée.
- **Les actions d'un autre compte ne partent jamais** : avec `who`, l'application donne à chaque écran une étiquette de
  son compte ; la page en marque chaque action, abandonne celles d'un autre compte quand elle revient connectée sous
  quelqu'un d'autre, et l'application refuse une action dont l'étiquette n'est pas celle de l'écran.
- **Ce que la page a vu part avec son changement** : `base`, les valeurs que la page a vues de ce que change une action,
  lui arrive en `s.Base`, pour que l'application refuse le changement d'une chose qui a changé entre-temps plutôt que
  de l'écraser.

```cesia norun hide=code
screen(s) = []
acts = {}
sameAccount(old, new) = true
accountTag(r) = "w"
```
```cesia norun
app = http.App() then live.Route("/live", screen, actions = acts,
  resume = 120, buffer = 1048576,                      (* the screen kept through a break, and its frames *)
  same = (old, new) -> sameAccount(old, new),          (* who may come back to it: by default the same cookies and query *)
  who = s -> accountTag(s.Request),                    (* the tag that stamps the page's actions *)
  client = {PingEvery: 15, DeadAfter: 30, OutboxCount: 100})   (* the page's settings, sent with its screen *)
```
```js
const live = await connect("/live")
live.onStatus(s => line.textContent = s.State === "down" ? `Offline — ${s.Waiting} waiting` : s.State)
```

Le fil, version 2 (une page de version 1, `{"Hello": 1}`, reçoit l'écran d'avant, qui finit avec sa connexion) :

| de | message | ce qu'il dit |
|---|---|---|
| page | `{"Hello": 2}`, ou `{"Hello": 2, "Token": t, "Got": n}` | un nouvel écran, ou de nouveau l'écran `t` après la trame `n` |
| application | `[{"Token": t, "Resumed": r, "Heard": h, "Who": w, "Client": c}]` | sans numéro : le jeton de l'écran, si c'est celui que la page avait, la dernière action qu'il a entendue |
| application | `[{"Seq": n}, ...]` | une trame, numérotée, gardée jusqu'à ce que la page l'ait |
| page | `{"Got": n}`, `{"Ping": t, "Got": n}` | les trames que la page a |
| page | `{"Act": a, "Id": i, "Args": x, "Key": k, "Base": b, "Who": w}` | une action, lancée une fois par son `Id` sur son écran et par sa `Key` dans l'application |
| page | `{"Bye": 1}` | la page s'en va (envoyé en fermant) : l'écran finit aussitôt |

Une reprise appartient à son écran : la requête de la page qui revient doit être celle de l'écran (le `same` de Route) ;
un jeton d'un autre compte ou d'une autre query reçoit un nouvel écran, et l'écran du jeton continue.

Une page d'une autre origine que celle de l'application reçoit un `403`, comme en décide [http.SameOrigin] : aucun autre site
n'ouvre un écran avec les cookies de ses visiteurs, ce qu'une WebSocket permettrait sinon, puisqu'un navigateur ne la
tient pas à la [same-origin rule](glossary.md#same-origin-check) (la règle de la même origine) comme il y tient `fetch`
(RFC 6455 §10.2).

### Le temps des changements d'une page

`live.js` mesure combien de temps chaque changement met pour aller de l'application à la page : de `At` à son arrivée,
avec l'écart entre les deux horloges tiré des pings de la page (de petits messages qui font l'aller-retour), toutes les
30 s, celui de l'aller-retour le plus court, comme le fait NTP, le protocole qui met à l'heure les horloges d'Internet.
Chaque minute, une page envoie son p50 et son p99, les temps que la moitié et 99 sur 100 de ses changements n'ont pas
dépassés, et l'application les garde dans [std/metrics] en deux histogrammes, `live_delay_p50_seconds` et
`live_delay_p99_seconds`, qu'une route montre à Prometheus avec `metrics.Text()`. Le nombre d'écrans ouverts est
`live_screens_total`.

### Ce que ça coûte

Mesuré sur une machine de 8 cœurs, l'application sur 4 d'entre eux et les pages sur les 4 autres (un client de charge
qui ouvre les écrans, puis publie à un rythme régulier des changements d'une ligne de 48 octets, chacun chronométré de
sa publication à son arrivée sur chaque page), 21 runs alternés avec un hub (un point central qui relaie chaque message
à tous) écrit à la main sur [std/websocket] dans la version d'avant : une seule fiber qui envoie le texte de chaque
changement à toutes les connexions, sans renvoyer le résultat entier à une page lente. La médiane des p50 des runs, avec
son intervalle à 95 % :

| écrans | changements par seconde | hub écrit à la main | std/live | p99 de std/live |
|---|---|---|---|---|
| 1 | 50 | 0,44 ms (0,43 à 0,44) | 0,58 ms (0,56 à 0,60) | 0,74 ms |
| 100 | 50 | 1,25 ms (1,17 à 1,27) | 2,67 ms (2,40 à 2,84) | 7,5 ms |
| 1 000 | 50 | 5,7 ms (5,6 à 5,9) | 12,3 ms (11,8 à 13,3) | 40 ms |
| 10 000 | 5 | 42 ms (42 à 44) | 294 ms (285 à 318) | 612 ms |

```cesia allow=read,write
screens = [1, 100, 1000, 10000]
delays = plot.Of([plot.Line(screens, [0.44, 1.25, 5.7, 42], label = "hub, p50", dash = "dashed"),
  plot.Line(screens, [0.58, 2.67, 12.3, 294], label = "std/live, p50", color = "#3a5ad9"),
  plot.Line(screens, [0.74, 7.5, 40, 612], label = "std/live, p99", color = "#3a5ad9", dash = "dotted")],
  title = "From a change to each screen: ms, median of 21 runs", x = "screens (log scale)", y = "milliseconds (log scale)",
  xscale = "log", yscale = "log", note = "50 changes a second, 5 at 10,000 screens", size = [640, 380])
plot.Save(delays, "http-live.svg") -->
```

Un écran de std/live prend environ deux fois le temps du hub. Il en fait plus : chaque écran est une fiber à lui qui
écrit lui-même les messages de sa page, si bien qu'une page qui ne lit rien ne retient aucune autre, là où le hub
l'attend. À 10 000 écrans et 50 000 changements par seconde à envoyer, std/live en envoie 47 600 par seconde, le hub
51 200 : std/live prend du retard, et ses temps grandissent pendant le run. Un écran ouvert prend 29,2 KB de mémoire, la
connexion du hub 23,2 KB. Un programme qui n'utilise pas [std/live] démarre comme avant : 2,92 ms (2,88 à 2,97) contre
2,90 (2,85 à 2,94) pour `io.Print(1)`, 21 runs alternés.

## TCP : std/net

Sous [std/http] se trouve [std/net], le TCP brut : [net.Listen] ouvre un listener, [net.Accept] attend une connexion,
[net.Connect] en ouvre une, [net.Read] et [net.Write] font passer du texte, [net.Close] ferme, et [net.Port] dit le port
que le système a choisi pour `net.Listen(0)`. Chaque attente ne suspend que sa fiber. Un texte vide venu de [net.Read] veut
dire que l'autre côté a fermé :

```cesia allow=net=own
use std/net
server = net.Listen(0).Value
client = net.Connect("127.0.0.1", net.Port(server)).Value
peer = net.Accept(server).Value
net.Write(client, "ping") -->
net.Read(peer) -->
net.Close(client)
net.Read(peer) -->
```

## Le client

[http.Fetch] envoie une requête, un `GET` sauf si `method` dit autrement, avec un `body` et des `headers` si vous les
donnez. Il donne un `Ok` de la réponse, avec son `Status`, ses `Headers` et son `Body`, ou un `Err` quand le serveur ne
peut pas être atteint. Un `404` est une réponse, pas une erreur : regardez `Status`.

```cesia allow=net
http.Fetch("http://127.0.0.1:1/") -->
```

Un programme qui interroge une adresse qu'on lui a donnée, comme un serveur qui rappelle l'adresse d'un partenaire, ne
doit pas atteindre sa propre machine ou son réseau pour le compte de qui la lui a donnée (*server-side request forgery*,
SSRF : la falsification de requêtes côté serveur) : `peer`, une fonction de l'adresse que la connexion a atteinte, telle
que [net.Peer] la donne, tourne une fois la connexion ouverte et avant qu'aucun octet parte, ceux de TLS compris ; un
`Err` qu'elle donne ferme la connexion, et `Fetch` donne cet `Err`. Un hôte donné par son nom est ainsi vérifié à
l'adresse même où il a été trouvé : une seconde recherche du nom, à laquelle un serveur de noms pourrait répondre
autrement (*DNS rebinding*, le changement d'adresse entre deux recherches), n'a jamais lieu.

```cesia norun
use std/result
mine(address) = if address == "127.0.0.1" or address == "::1" result.Err({Kind: "http", Message: "This address is of this machine."}) else result.Ok(missing) end
http.Fetch("http://localhost:8080/", peer = mine)   (* Err: This address is of this machine. *)
```

### https

Pour `https`, [std/tls] donne au client son chiffrement, par OpenSSL. Il lui faut la permission de le charger, et celle
d'atteindre l'hôte :

```cesia norun
(* page.ce *)
use std/http
use std/io
use std/result
use std/tls
api = tls.Open()!
page = http.Fetch("https://example.com/", secure = tls.Client(api))
io.Print(page!.Status)
```

```bash
cesia run --allow net=example.com,ffi=ssl,ffi=crypto page.ce
```

Le certificat du serveur doit être signé par une autorité à laquelle le système fait confiance, et nommer l'hôte ;
`ca`, le chemin d'un fichier PEM d'autorités, fait confiance à celles-là à la place, comme celle d'une entreprise :
`tls.Client(api, ca = "/etc/ssl/company.pem")`.

Un serveur sert `https` de la même façon : `wrap = tls.Server(certificate, key, api)?` donné à [http.Serve], avec les
chemins de son certificat et de sa clé, venus d'une *certificate authority* (une autorité de certification, qui garantit
qu'une clé est bien celle d'un nom) comme Let's Encrypt. [std/tls] garde les sockets avec [std/net] et ne donne à OpenSSL
que des buffers en mémoire (des zones de mémoire où passent les octets), si bien qu'un handshake suspend sa fiber, jamais
le serveur entier.

## HTTP/3

*HTTP/3* (RFC 9114) porte les mêmes requêtes sur *QUIC* (RFC 9000), un transport sur UDP au lieu de TCP : UDP envoie
des paquets un par un, sans connexion ni ordre, et QUIC fait lui-même le reste. Trois choses changent pour un client
lointain ou sur un mauvais réseau :

- **Le handshake prend un aller-retour, pas deux.** Le handshake de TCP, puis celui de TLS, prennent deux allers-retours
  avant la première requête ; le handshake de QUIC *est* celui de TLS 1.3 (RFC 9001), si bien que la requête part après
  un seul : 200 ms de moins sur une ligne de 100 ms dans chaque sens.
- **Un paquet perdu ne retient que sa propre requête.** Sur TCP, les octets de toutes les requêtes d'une connexion
  arrivent dans un seul ordre, et un paquet perdu les arrête toutes jusqu'à ce qu'il arrive de nouveau : le
  *head-of-line blocking* (le blocage par la tête de la file). QUIC porte chaque requête sur un *stream* à elle (un
  flux : une suite d'octets qui a son propre ordre), et une perte n'arrête que ce stream.
- **Il est chiffré jusqu'au bout**, ses numéros de paquets et ses accusés de réception aussi : une machine sur le chemin
  ne peut ni les lire ni les changer.

[std/http3] sert la même application que HTTP/1.1, à côté de lui : donnez à [http.Serve] un `http3`, le listener que
[http3.Server] ouvre sur un port UDP, par défaut le même numéro que le port TCP de HTTPS, puisque c'est là que les
navigateurs le cherchent. Les routes ne changent pas, ni le middleware, ni les handlers : une requête est le même
`{Method, Path, Query, Headers, Body, Peer}`, et une route qui prend son corps en morceaux (`stream`) le reçoit en
morceaux par HTTP/3 aussi.

```cesia norun
(* site.ce *)
use std/http
use std/http3
use std/quic
use std/result
use std/tls
app = http.App() then http.Get("/", r -> http.Plain("hi"))
h3 = http3.Server("cert.pem", "key.pem", quic.Open()!, port = 8443)!
http.Serve(app, port = 8443, wrap = tls.Server("cert.pem", "key.pem", tls.Open()!)!, http3 = h3)!
```

```bash
cesia run --allow net,ffi=ssl,ffi=crypto site.ce
curl --http3-only https://localhost:8443/
```

![TCP, TLS et HTTP/1.1 face à QUIC et HTTP/3 : le handshake de TCP, puis celui de TLS, puis la requête, deux allers-retours avant elle ; le handshake de QUIC porte celui de TLS, un aller-retour ; sur TCP, un paquet perdu arrête les trois requêtes de la connexion, sur QUIC seulement le stream auquel il appartenait.](../../book/images/http3-stack-fr.svg)

### Comment un navigateur le trouve

Un navigateur demande d'abord par TCP : il ne peut pas savoir qu'un serveur parle HTTP/3 avant de lui avoir demandé.
Chaque réponse de TCP le dit donc, `alt-svc: h3=":8443"; ma=86400` (*Alt-Svc*, RFC 7838, un header qui annonce un autre
chemin vers le même site) : les requêtes suivantes passent par QUIC pendant un jour. Là où UDP ne passe pas, comme dans
certains réseaux d'entreprise, le navigateur reste de lui-même sur TCP. Un enregistrement DNS de type `HTTPS`
(RFC 9460) le dit avant la première requête, `example.com. 3600 IN HTTPS 1 . alpn="h3,http/1.1"`, ce qui évite ce
premier passage par TCP.

### Le client

[http.Fetch] fait comme un navigateur avec `http3 = http3.Client(api)` : il retient l'`Alt-Svc` de chaque origine,
demande ensuite par HTTP/3, sur une seule connexion gardée ouverte, et revient aussitôt à TCP quand QUIC échoue ; cette
origine n'est alors plus essayée par QUIC pendant 5 minutes. Mais une requête qui a pu atteindre le serveur et qui
n'est pas idempotente (RFC 9110, section 9.2.2 : toute méthode sauf GET, HEAD, OPTIONS, PUT et DELETE ; idempotente
veut dire qu'on peut la répéter sans autre effet) rend son erreur au lieu de repartir par TCP, où un paiement serait
payé deux fois. `peer` vérifie aussi l'adresse que QUIC atteint.

```cesia norun
api = tls.Open()!
h3 = http3.Client(quic.Open()!)
first = http.Fetch("https://example.com/", secure = tls.Client(api), http3 = h3)   (* over TCP: it hears Alt-Svc *)
next = http.Fetch("https://example.com/", secure = tls.Client(api), http3 = h3)    (* over HTTP/3 *)
```

### WebTransport

*WebTransport* (draft-ietf-webtrans-http3, un projet de norme de l'IETF) donne à une page ce que donne une WebSocket,
mais sur HTTP/3 : une *session* qu'une page ouvre avec `new WebTransport(url)`, dont les streams vont dans les deux
sens. Avec `webtransport = true`, les routes de [std/live] prennent une session sur leur propre chemin, et l'écran est
le même, avec ses trames, ses actions et leur reprise : seul le transport change. `live.js` et la glue d'une page
compilée en WebAssembly (le code JavaScript qui la relie au navigateur) *font la course* entre les deux, comme les
navigateurs entre IPv6 et IPv4 (*Happy Eyeballs*, RFC 8305 : essayer deux chemins à la fois et garder le premier prêt) :
ils ouvrent les deux, prennent WebTransport quand il est prêt le premier ou moins de 300 ms après la WebSocket, et
ferment l'autre. Une session qui échoue marque l'origine pendant 10 minutes, et seule la WebSocket y va entre-temps :
une page n'attend jamais un réseau qui jette l'UDP. Une session ne porte aucun cookie (le WebTransport du W3C fait ses
requêtes sans eux), et un écran est souvent celui de son utilisateur par un cookie : la page demande donc d'abord
`/live/ticket` (le chemin de la route, puis `/ticket`) avec ses cookies, et ouvre sa session avec `?ticket=` ; l'écran
reçoit les cookies de cette requête, une fois, dans les 30 s, et un ticket déjà servi, forgé ou en retard reçoit 403.
Une page ne demande WebTransport que si elle le dit, par `<meta name="webtransport" content="on">` : un serveur qui ne
le met pas n'est jamais sollicité. Le certificat d'un serveur qu'aucune autorité n'a signé, comme celui des tests ou
d'une machine à soi, est reconnu par son hash (son empreinte, un résumé court calculé à partir de ses octets) :
`connect(url, {CertificateHashes: [le base64 de son SHA-256]})`, pour un certificat de 14 jours au plus, comme le
demandent les navigateurs.

### Ce qu'a le QUIC d'OpenSSL, et ce qu'il n'a pas encore

[std/quic] est le QUIC d'OpenSSL, atteint par [std/c] comme [std/tls] atteint son TLS : OpenSSL garde la socket UDP,
les paquets, leurs pertes et leurs timers (les minuteries qui disent quand renvoyer ou abandonner) ; une seule fiber le
fait tourner et attend un datagram (un paquet UDP) ou le prochain timer d'OpenSSL, si bien qu'aucune fiber n'en attend
une autre. QUIC demande OpenSSL 3.6 ou plus récent, qui donne à un serveur l'adresse de chaque client (le `Peer` d'une
requête, sur lequel comptent les limites par adresse) ; la 3.5 a le serveur, pas cette adresse.

| | OpenSSL 3.6, 4.0, 4.1 | Ce que cela veut dire |
|---|---|---|
| Les streams, le *flow control* (le débit réglé sur ce que l'autre côté peut prendre), la reprise des paquets perdus (RFC 9000, RFC 9002) | oui | |
| Le *congestion control* (RFC 9002, section 7 : le débit réglé sur ce que le réseau laisse passer) | NewReno seul, sans *pacing* (l'envoi des paquets étalé sur l'aller-retour), des paquets de 1 200 octets | un gros téléchargement sur un lien qui perd des paquets est plus lent que sur TCP : [Ce que ça coûte](#ce-que-ça-coûte) |
| Retry, la vérification qu'un client est bien à son adresse (RFC 9000, section 8.1) | oui, actif par défaut | `validate = false` épargne un aller-retour, seulement pour les tests |
| La *connection migration* (section 9) : une connexion qui continue quand l'adresse du client change, du wifi à la 4G | non | le client ouvre une nouvelle connexion : [Quand la connexion tombe](#quand-la-connexion-tombe) reprend l'écran là où il était |
| Le 0-RTT (RFC 9001, section 4.6) : une requête dans le premier paquet d'une connexion qui reprend | non | aucune requête n'est jamais prise dans les *early data* (les données envoyées avant la fin du handshake) |
| Les datagrams (RFC 9221) | non | Chrome demande à un serveur WebTransport de dire qu'il les a ; il le dit, et aucun n'arrive jamais |

Derrière un proxy qui prend les early data de TLS, comme nginx avec `ssl_early_data on` ou un CDN (un réseau de serveurs
placés devant un site, près de ses visiteurs), une requête qui changerait quelque chose reçoit `425 Too Early`
(RFC 8470), en HTTP/1.1 comme en HTTP/3 : le proxy marque une telle requête `Early-Data: 1`, un attaquant pourrait
l'envoyer de nouveau, et un paiement rejoué serait payé deux fois ; le client la renvoie après le handshake. GET, HEAD
et OPTIONS passent.

| Système | Son OpenSSL | HTTP/3 |
|---|---|---|
| Arch Linux (2026-11) | 4.1.0, et 3.5.9 à côté | oui, par la 4.1 |
| Ubuntu 22.04, 24.04 | 3.0 | non : Serve ne sert que TCP |
| Les versions de Cesia publiées pour macOS et Windows | 3.5.9, livrée avec elles | non, tant qu'elles n'apportent pas la 3.6 ou plus récente |

### Ce que tente un attaquant

Chaque ligne est un cas de `tests/quic/threats.ce`, mesuré.

| Attaque | Ce qui l'arrête | Mesuré |
|---|---|---|
| L'amplification : des paquets envoyés au nom d'une autre adresse, pour que le serveur l'inonde (RFC 9000, section 8) | au plus 3 fois ce qui est venu d'une adresse tant qu'elle n'a pas prouvé qu'elle est bien la sienne ; Retry d'abord | 4 Initials de 1 200 octets en 3 s : 4 837 octets envoyés sans Retry (1,01 fois) ; 273 à 364 avec (0,08 fois) |
| Un flot de handshakes | Retry ne garde aucun état pour une adresse pas encore prouvée | 2 000 Initials (les premiers paquets d'un handshake), 2,4 Mo, depuis 2 000 ports : des Retry en retour, 100 à 119 Ko (0,05 fois), 0,2 Mo de mémoire en plus au plus, un vrai client servi aussitôt |
| Suivre un client à ses connection ids (les numéros qui désignent sa connexion dans chaque paquet) | les ids du serveur sont aléatoires, de 8 octets, nouveaux pour chaque connexion | 5 connexions, 5 ids de 8 octets aléatoires |
| Un paquet d'une connexion rejoué depuis une autre adresse, pour l'y déplacer | pas de migration : le paquet est jeté | 34 octets envoyés depuis un nouveau port : rien en retour, la connexion continue |
| La table de QPACK (la compression des headers de HTTP/3) remplie pour prendre la mémoire (RFC 9204, section 2.2.3) | la table fait 0 octet : aucune insertion, aucune référence à elle | une insertion ou une référence termine la connexion ; une tête de 20 Kio reçoit un 431 avant tout décodage de Huffman (le code qui raccourcit le texte des headers) |
| Des streams par milliers | OpenSSL en laisse tourner 100 à la fois (MAX_STREAMS), chaque tête dans le timeout | 1 000 à la fois : les 1 000 ont leur réponse ; une tête jamais finie, lâchée après le timeout |
| Une requête rejouée dans des early data | pas de 0-RTT ; un 425 derrière un proxy qui les prend | `tests/quic/http3.ce` |

### Ce que ça coûte

Mesuré avec `bench/http3` (`setup.sh` construit ce qu'il faut, `all.sh` et `stacks.sh` mesurent, `flights.sh` dessine ce
que reçoit un client) : une seule machine, chaque serveur sur deux cœurs et le client sur deux autres, chaque lien dans
un *network namespace* (un réseau à part, propre à ces programmes) où `netem` ajoute le délai et les pertes d'un vrai
chemin. Chaque nombre est la médiane des tours, puis [le plus petit, le plus grand]. Les géants : quic-go 0.66, Caddy 2
(sur quic-go), nginx 1.27 avec HTTP/3, et ngtcp2 1.26 (le QUIC de curl).

Sur un lien propre, les géants gagnent partout, et HTTP/3 coûte plus que HTTP/1.1 à tous :

| lien propre | Cesia HTTP/1.1 | Cesia HTTP/3 | les géants, HTTP/3 | les géants, HTTP/1.1 |
|---|---|---|---|---|
| requêtes par seconde (GET /, 16 connexions, 7 tours) | 20 513 [18 759, 22 014] | 5 929 [4 369, 6 296] | 11 168 (Caddy) à 15 595 (nginx) | 24 761 à 26 663 |
| un téléchargement de 1 Mo sur une nouvelle connexion | 19,8 ms | 24,7 ms | 8,9 (quic-go) à 12,5 ms (nginx) | 5,9 à 7,9 ms |
| la mémoire d'une connexion inactive (200 à la fois) | 118 Ko | 91 Ko | 57 (quic-go) à 116 Ko (nginx) | 23 à 29 Ko |

Une requête en HTTP/3 coûte à Cesia trois fois et demie ce qu'elle coûte en HTTP/1.1, aux géants environ deux fois :
QUIC chiffre et accuse réception de chaque paquet de 1 200 octets dans le programme lui-même, là où TCP laisse ce
travail au noyau.

Sur un lien de 25 ms dans chaque sens où 1 % des paquets se perdent, l'aller-retour borne tous les serveurs, près de 300
requêtes par seconde avec 16 connexions, et deux choses diffèrent :

- **Les petites requêtes les plus lentes arrivent plus tôt en HTTP/3** : le 1 % le plus lent (le p99) prend 179 ms par
  le HTTP/3 de Cesia, 128 à 191 ms par celui des géants, contre 305 à 398 ms par TCP ; sur 100 ms dans chaque sens et
  5 % perdus, un mauvais réseau mobile, 664 ms par le HTTP/3 de Cesia contre 990 ms par son TCP (601 à 626 par le
  HTTP/3 de quic-go et de Caddy, 1 079 par celui de nginx, 879 à 1 012 par TCP). Une requête dont un paquet se perd
  attend la sonde de QUIC (le *probe*, un paquet renvoyé pour vérifier), environ 1,5 aller-retour, là où TCP attend
  son timer de retransmission, 200 ms au moins. C'est ce qu'apporte HTTP/3 aujourd'hui : la queue des petites requêtes
  sur un mauvais réseau, celui d'un téléphone.
- **Un gros téléchargement est plus lent en HTTP/3, à cause du QUIC d'OpenSSL** : 1 Mo prend 4,7 s par le HTTP/3 de
  Cesia, 1,8 s par son TCP, 0,9 s par quic-go, 0,5 s par ngtcp2 avec BBR. Sur 100 ms dans chaque sens et 5 % perdus,
  42 s par le HTTP/3 de Cesia, 41 s par celui de nginx, 19 s par celui de quic-go et de Caddy, 28 s par le TCP de
  Cesia (3 téléchargements chacun : des chiffres approchés).

![Un téléchargement de 1 Mo sur 25 ms dans chaque sens et 1 % perdu, 21 tours : Cesia en HTTP/3 4,71 s, le QUIC d'OpenSSL 4.1 seul 5,00 s, OpenSSL des deux côtés 4,88 s, ngtcp2 avec Reno 2,34 s, avec CUBIC 1,43 s, avec BBR 0,47 s, quic-go 0,86 s, Cesia sur TCP 1,81 s.](../../book/images/http3-lossy-fr.svg)

Le temps est celui d'OpenSSL, pas celui de Cesia : le QUIC d'OpenSSL seul, un petit serveur en C dans sa propre boucle
(`bench/http3/openssl`), prend le même temps (5,0 s contre 4,7 s, test de Mann-Whitney p = 0,13 sur 21 tours chacun :
aucune différence). Le journal du client (le *qlog*) dit pourquoi : OpenSSL envoie une rafale à chaque aller-retour,
puis plus rien jusqu'au retour de ses accusés de réception, et sa fenêtre, les octets qu'il peut avoir en route, reste
entre 4 et 12 paquets de 1 200 octets. Son *congestion control* n'est que NewReno (RFC 9002, section 7), et il ne grandit
cette fenêtre que d'un paquet tous les 2 à 5 allers-retours, là où NewReno la grandit à chaque aller-retour : OpenSSL ne
compte un paquet reçu que tant que les octets en route restent à moins de 3 paquets de la fenêtre, et les accusés de
réception d'une rafale arrivent ensemble, si bien que seuls les trois premiers de chaque aller-retour comptent
(`cc_newreno.c`, `newreno_on_data_acked`). Le même NewReno dans ngtcp2, qui étale ses paquets et décide à l'envoi de
chacun si la fenêtre était pleine, prend moitié moins de temps (2,3 s, p = 3,5e-6) ; son CUBIC (RFC 9438) et son BBR
prennent 1,4 et 0,47 s. Rien dans l'API d'OpenSSL 4.1 n'y change quoi que ce soit : ses réglages sont les fenêtres du
flow control, le délai des accusés de réception, l'*idle timeout* et le buffer d'écriture.

![Ce que le client reçoit par 50 ms (un aller-retour) d'un téléchargement avec pertes : quic-go jusqu'à 70 paquets, étalés sur l'aller-retour ; OpenSSL seul et Cesia une rafale de 4 à 12 paquets, puis rien pendant un aller-retour, pendant 4 à 5 secondes.](../../book/images/http3-flights-fr.svg)

Un vrai chemin a un *goulot*, son lien le plus lent, qui espace les paquets d'une rafale. À travers un goulot de 20
Mbit/s (`stacks.sh d25l1r20` : les mêmes 25 ms et 1 %), les accusés de réception reviennent étalés sur l'aller-retour,
OpenSSL en compte davantage, et son NewReno ne diffère plus de celui de ngtcp2 : 1 Mo prend 3,1 s par le QUIC d'OpenSSL
seul et 2,6 s par le Reno de ngtcp2 (p = 0,21), 1,9 s par le HTTP/3 de Cesia (face à OpenSSL seul, p = 0,23 : le même).
Ce qui reste, c'est NewReno lui-même, qui divise sa fenêtre par deux à chaque perte et ne la regrandit que d'un paquet
par aller-retour : le CUBIC de ngtcp2 prend 1,3 s, quic-go 1,4 s, le TCP de Cesia, où Linux fait tourner CUBIC, 1,2 s,
et BBR, qui mesure le chemin au lieu de lire chaque perte comme une congestion, 0,78 s. Sur un tel chemin, le HTTP/3 de
Cesia prend encore 1,7 fois le temps de son TCP (p = 0,012). 21 tours, la charge moyenne de la machine (le *load
average*) à 4,1 [1,7 ; 7,4], d'autres travaux tournant à côté.

![Un téléchargement de 1 Mo sur 25 ms dans chaque sens, 1 % perdu et 20 Mbit/s au plus, 21 tours : Cesia en HTTP/3 1,95 s, le QUIC d'OpenSSL 4.1 seul 3,14 s, ngtcp2 avec Reno 2,58 s, avec CUBIC 1,31 s, avec BBR 0,78 s, quic-go 1,36 s, Cesia sur TCP 1,15 s.](../../book/images/http3-bottleneck-fr.svg)

Quand l'adresse du client change au milieu d'un téléchargement de 10 Mo (`migrate.sh`), le QUIC de Cesia, sans migration,
ouvre une nouvelle connexion et demande le reste, comme TCP :

| l'adresse change après 2 Mo | du changement à l'octet suivant, lien propre | le même, 25 ms + 1 % |
|---|---|---|
| quic-go, migration | 0,5 ms | 101 ms |
| quic-go, une nouvelle connexion QUIC | 2,3 ms | 103 ms |
| Cesia, une nouvelle connexion QUIC (Retry, puis le handshake) | 22 ms | 171 ms |
| Cesia, une nouvelle connexion TCP | 9,1 ms | 223 ms |

Le chemin TCP ne paie rien pour HTTP/3. Face au Cesia d'avant lui (`ab.sh` : le même fichier de serveur, GET / en HTTPS
avec 16 connexions, 21 tours alternés), celui-ci sert 21 825 requêtes par seconde [13 895, 25 581], celui-là 19 457 [12
557, 24 071] : 1,13 fois par tour [0,82 ; 1,61], test des rangs signés de Wilcoxon p = 0,085, aucune différence. Avec
HTTP/3 allumé à côté (`h3off.sh`, 21 tours), les requêtes de TCP vont aussi vite qu'avec lui éteint : 22 066 [15 931, 24
345] contre 21 628 [6 124, 24 632], 1,05 fois par tour, p = 0,66. La ligne `Alt-Svc` que porte chaque réponse de TCP est
faite une fois, au démarrage : ajoutée à chaque réponse comme un header, elle coûtait 11 % (p = 0,006). La charge
moyenne de la machine était de 5,1 à 5,4 en médiane, d'autres travaux tournant à côté, d'où les bornes larges.

HTTP/3 est donc un réglage, jamais un remplacement : allumé pour une application dont les utilisateurs sont sur des
téléphones et de mauvais réseaux et font de petites requêtes, éteint là où il ne ferait que coûter, comme pour les gros
téléchargements, tant que Cesia ne parle pas un QUIC dont le congestion control suit (voir
[Références](references.md#le-serveur-et-le-réseau) pour la RFC 9002 et les articles).

## Pour aller plus loin

Les RFC 9110 et RFC 9112 pour HTTP, les RFC 9000, RFC 9001, RFC 9114 et RFC 9204 pour QUIC et HTTP/3,
draft-ietf-webtrans-http3 pour WebTransport, la RFC 6455 pour WebSocket, la RFC 9846 pour TLS 1.3, le format
d'exposition de Prometheus, et les pages de Linux sur `epoll` : voir
[Références](references.md#le-serveur-et-le-réseau).

## La suite

Vos programmes servent le web et l'interrogent. Le chapitre suivant, [Cryptographie](crypto.md), garde leurs secrets ;
puis [Fibers](fibers.md) fait plusieurs choses à la fois : les requêtes d'un serveur, les pages d'un crawler (un programme
qui parcourt le web de lien en lien), une tâche lente à côté d'une rapide.
