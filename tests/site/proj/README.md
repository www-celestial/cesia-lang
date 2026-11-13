# Proj

A tiny project with [a book](docs/book/index.md), its [first steps](docs/book/first.md#first-steps) and
[guides](docs/guides/). A formula: $n^2$.

> [!TIP]
> The site shows this page as its README.

```cesia
use std/http
http.Serve(http.App(), port = 8080)
```

```python
from http.server import HTTPServer, BaseHTTPRequestHandler
HTTPServer(("127.0.0.1", 8080), BaseHTTPRequestHandler).serve_forever()
```
