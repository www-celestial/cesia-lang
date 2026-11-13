# Proj

Un tout petit projet, avec [un livre](docs/fr/book/index.md), ses [premiers pas](docs/fr/book/first.md#premiers-pas) et
[des guides](docs/fr/guides/). Une formule : $n^2$.

> [!TIP]
> Le site montre cette page comme son README.

```cesia
use std/http
http.Serve(http.App(), port = 8080)
```

```python
from http.server import HTTPServer, BaseHTTPRequestHandler
HTTPServer(("127.0.0.1", 8080), BaseHTTPRequestHandler).serve_forever()
```
