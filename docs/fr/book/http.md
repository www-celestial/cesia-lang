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
reçoivent aussi le premier signal, comme le dit le chapitre [Fichiers](files.md#programs-that-keep-running).

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

Mesuré le 7 novembre 2026 sur la machine de [Vitesse](speed.md#à-côté-des-géants), en une exécution de
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
53 000 avec [http.Metrics], mesuré le 7 novembre 2026. Avec `--workers`, chaque worker compte ses propres requêtes, et un
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

## Le reste de std/http

| Pour | Utilisez |
|---|---|
| ajouter une route | [http.Get], [http.Post], [http.Put], [http.Delete], [http.AnyMethod] pour n'importe quelle méthode, [http.Route] pour une méthode donnée par son nom ; un `*` final dans un chemin en prend le reste, dans `r.Params["*"]` |
| servir des fichiers | [http.Static] sert un dossier sous un préfixe, et aucun chemin ne peut sortir du dossier ; [http.FileResponse] envoie un fichier, avec son type d'après son extension |
| répondre | [http.Plain], [http.Json], [http.Html], [http.Redirect], [http.NotFound] ; [http.WithHeader] ajoute un header, [http.SetCookie] un cookie ; [http.Reason] est le texte d'un statut |
| lire une requête | [http.BodyJson] son corps en JSON, [http.Form] comme formulaire, [http.HeaderValue] un header par son nom en minuscules ; [http.ParseUrl] décompose une URL |
| envelopper | [http.Logger], [http.Metrics], et [http.Cors], qui laisse les pages d'une autre origine (d'un autre site) lire les réponses |
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
Prometheus, et les pages de Linux sur `epoll` : voir [Références](references.md#the-server-and-the-network).

## La suite

Vos programmes servent le web et l'interrogent. Le chapitre suivant, [Cryptographie](crypto.md), garde leurs secrets ;
puis [Fibers](fibers.md) fait plusieurs choses à la fois : les requêtes d'un serveur, les pages d'un crawler (un programme
qui parcourt le web de lien en lien), une tâche lente à côté d'une rapide.
