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

## L'essayer sans le réseau

[http.Handler] donne la fonction que le serveur appelle pour chaque requête. Vous pouvez l'appeler vous-même, avec une
requête sous forme de dictionnaire : c'est ainsi qu'on teste un serveur.

```cesia
use std/io
handle = http.Handler(app)
ask(path) = handle({Method: "GET", Path: path, Query: "", Headers: [], Body: ""})
ask("/hello/Ana").Body -->
ask("/stock").Status -->
io.Print(ask("/stock").Body)
ask("/nowhere").Status -->
```

Un chemin qu'aucune route ne prend reçoit un `404`.

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

### Arrêter

Un signal d'arrêt arrête proprement un serveur : TERM, que systemd, Docker et Kubernetes envoient, INT, qu'envoie Ctrl-C,
ou HUP, qu'un terminal envoie en se fermant. Le serveur n'accepte plus de connexions, et les requêtes en cours se
terminent, chacune avant son échéance, avec une réponse qui dit à son client que la connexion se ferme, pour que le client
redemande ailleurs. Puis [http.Serve] donne `Ok`, et le programme continue jusqu'à sa fin, ce qui donne l'exit code (le
nombre que le programme rend à celui qui l'a lancé) 0, sauf s'il en décide autrement. Un second signal n'attend pas : le
programme s'arrête aussitôt, avec 128 plus le numéro du signal, 143 pour TERM et 130 pour INT, comme les donne un shell
(le programme qui lit vos commandes dans le terminal). Les programmes qu'il a démarrés avec [sys.Start] ou [sys.Run]
reçoivent aussi le premier signal, comme le dit le chapitre [Fichiers](files.md#les-programmes-qui-continuent-de-tourner).

### Tous les cœurs

Un serveur tourne sur un cœur. `--workers` en fait tourner plusieurs, qui servent ensemble le même port, autant que `N`, ou
un par cœur avec `cores` :

```bash
cesia run --workers cores --allow net=0.0.0.0:8080 shop.ce
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

`live.js` est servi au chemin de la route suivi de `/live.js` : un module de 211 lignes, sans rien à installer :

| | |
|---|---|
| `connect(url)` | ouvre l'écran : une `Promise` de l'écran, ou un refus quand aucun écran ne s'ouvre à `url` |
| `live.show(name, draw)` | `draw(rows)` avec les lignes d'un show, aussitôt si elles sont là, puis à chaque changement |
| `live.act(name, args, effects)` | une action : une `Promise` de sa réponse, ses effets dessinés aussitôt |
| `live.onError(f)` | `f(error)` pour une erreur de l'écran, comme un `Err` de `screen` ou un show qui a pris fin |
| `live.close()` | ferme l'écran |

Quand la connexion se coupe, la page se reconnecte d'elle-même, après 0,25 s, puis deux fois plus longtemps à chaque
fois, jusqu'à 8 s ; le nouvel écran commence par les résultats. Une action demandée avant la coupure et encore sans
réponse reçoit une erreur qui le dit : elle a pu tourner ou non, et les nouveaux résultats montrent lequel des deux.

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

### https

Pour `https`, [std/tls] donne au client son chiffrement, par OpenSSL. Il lui faut la permission de le charger, et celle
d'atteindre l'hôte :

```cesia norun
use std/tls
use std/result
api = result.Unwrap(tls.Open())
page = http.Fetch("https://example.com/", secure = tls.Client(api))
```

```bash
cesia run --allow net=example.com,ffi=ssl,ffi=crypto page.ce
```

Un serveur sert `https` de la même façon : `wrap = tls.Server(certificate, key, api)?` donné à [http.Serve], avec les
chemins de son certificat et de sa clé, venus d'une *certificate authority* (une autorité de certification, qui garantit
qu'une clé est bien celle d'un nom) comme Let's Encrypt. [std/tls] garde les sockets avec [std/net] et ne donne à OpenSSL
que des buffers en mémoire (des zones de mémoire où passent les octets), si bien qu'un handshake suspend sa fiber, jamais
le serveur entier.

## Pour aller plus loin

Les RFC 9110 et RFC 9112 pour HTTP, la RFC 6455 pour WebSocket, la RFC 9846 pour TLS 1.3, le format d'exposition de
Prometheus, et les pages de Linux sur `epoll` : voir [Références](references.md#le-serveur-et-le-réseau).

## La suite

Vos programmes servent le web et l'interrogent. Le chapitre suivant, [Cryptographie](crypto.md), garde leurs secrets ;
puis [Fibers](fibers.md) fait plusieurs choses à la fois : les requêtes d'un serveur, les pages d'un crawler (un programme
qui parcourt le web de lien en lien), une tâche lente à côté d'une rapide.
