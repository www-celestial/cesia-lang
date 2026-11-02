-- Web applications on http: routes, parameters, middleware, JSON, cookies, static files and templates.
use http
use json
use encode
use sys
use websocket as ws

-- An application with no route and no middleware.
App() = {Routes: [], Middleware: []}

segments(path) = Filter(s -> s != "", Split("/", path))

-- An application with a route added. The pattern may hold :name parts, which the handler finds in its params, and a final * for the rest of the path.
defn Route(method, pattern, handler, a)
  entry = {Method: method, Parts: segments(pattern), Handler: handler}
  {Routes: Append(entry, a.Routes), Middleware: a.Middleware}
end

-- An application with a GET route added: Handler(request) gives a response.
Get(pattern, handler, a) = Route("GET", pattern, handler, a)
-- An application with a POST route added.
Post(pattern, handler, a) = Route("POST", pattern, handler, a)
-- An application with a PUT route added.
PutRoute(pattern, handler, a) = Route("PUT", pattern, handler, a)
-- An application with a DELETE route added.
Delete(pattern, handler, a) = Route("DELETE", pattern, handler, a)
-- An application with a route added that takes any method.
AnyMethod(pattern, handler, a) = Route("*", pattern, handler, a)

-- A middleware is f(next, request), and calls next(request) to go on.
Wrap(f, a) = {Routes: a.Routes, Middleware: Append(f, a.Middleware)}

-- A plain text response. The functions below build the other responses.
Plain(s, status = 200) = {Status: status, Body: s, Headers: [type("text/plain; charset=utf-8")]}
-- An HTML response.
Html(s, status = 200) = {Status: status, Body: s, Headers: [type("text/html; charset=utf-8")]}
-- A response with the JSON text of a value.
SendJson(value, status = 200) = {Status: status, Body: json.Text(value), Headers: [type("application/json")]}
-- A response that sends the client to another URL.
Redirect(url, status = 302) = {Status: status, Body: "", Headers: [{Name: "location", Value: url}]}
-- A 404 response.
NotFound() = Plain("Not Found", status = 404)
type(value) = {Name: "content-type", Value: value}

-- A response with one more header.
defn WithHeader(name, value, response)
  headers = match response
    {Headers: headers} -> headers
    else -> []
  end
  out = response
  out.Headers = Append({Name: name, Value: value}, headers)
  out
end

-- A response with a cookie set. The value is URL-encoded.
defn SetCookie(name, value, response, options = "Path=/; HttpOnly; SameSite=Lax")
  WithHeader("set-cookie", "$name=$(encode.UrlEncode(value)); $options", response)
end

defn cookies(headers)
  line = GetHeader("cookie", headers)
  out = Dict()
  if IsMissing(line)
    return out
  end
  for part in Split(";", line)
    pair = Split("=", Trim(part))
    if Len(pair) == 2
      out[pair[1]] = encode.UrlDecode(pair[2])
    end
  end
  out
end

-- The value of a header by its name in lower case, or missing.
GetHeader(name, headers) = http.HeaderValue(name, headers)

-- Binds :name parts, and a final * takes what remains. The parameters, or missing if the path doesn't match.
defn matchPath(parts, path)
  out = Dict()
  n = Len(parts)
  for k in 1:n
    part = parts[k]
    if part == "*"
      out["*"] = Join("/", Skip(k - 1, path))
      return out
    end
    if k > Len(path)
      return missing
    end
    if StartsWith(":", part)
      out[ByteSlice(2, ByteLength(part), part)] = encode.UrlDecode(path[k])
    else if part != path[k]
      return missing
    end
  end
  if n == Len(path) out else missing end
end

defn enrich(request, params)
  {Method: request.Method, Path: request.Path, Query: encode.ParseQuery(request.Query), Params: params,
   Headers: request.Headers, Body: request.Body, Cookies: cookies(request.Headers)}
end

-- The body of a form, or of JSON.
Form(request) = encode.ParseQuery(request.Body)
-- The body of a request read as JSON: an Ok of the value, or an Err.
BodyJson(request) = json.Parse(request.Body)

defn result(value)
  match value
    Ok(v) -> v
    Err(e) -> Plain("Internal Server Error", status = 500)
    else -> value
  end
end

defn dispatch(a, request)
  path = segments(request.Path)
  allowed = false
  for r in a.Routes
    params = matchPath(r.Parts, path)
    if not IsMissing(params)
      if r.Method == "*" or r.Method == request.Method or (r.Method == "GET" and request.Method == "HEAD")
        return result(r.Handler(enrich(request, params)))
      end
      allowed = true
    end
  end
  if allowed Plain("Method Not Allowed", status = 405) else NotFound() end
end

-- Built once: a request only goes through it.
defn chain(a, k)
  if k == 0
    r -> dispatch(a, r)
  else
    next = chain(a, k - 1)
    f = a.Middleware[k]
    r -> f(next, r)
  end
end

-- The function of a request that http.Serve takes: the routes behind the middleware.
Handler(a) = chain(a, Len(a.Middleware))

-- Serves until a stop signal. Options go to http.Serve.
defn Serve(a, port = 8080, host = "127.0.0.1", timeout = http.DefaultTimeout, maxBody = http.DefaultMaxBody, wrap = http.Plain)
  http.Serve(Handler(a), port = port, host = host, timeout = timeout, maxBody = maxBody, wrap = wrap)
end

-- A WebSocket route: onMessage(text, send) runs for each message, and send(text) answers.
Websocket(pattern, onMessage, a, idle = ws.DefaultIdle) = Get(pattern, req -> ws.Accept(req.Headers, onMessage, idle = idle), a)

-- Middleware.
defn Logger(next, request)
  response = next(request)
  Print("$(request.Method) $(request.Path) $(response.Status)")
  response
end

-- A middleware that lets a given origin read the responses.
defn Cors(origin)
  (next, request) -> WithHeader("access-control-allow-origin", origin, next(request))
end

-- Static files under a folder. A path can't leave it.
types = {"html": "text/html; charset=utf-8", "css": "text/css", "js": "text/javascript", "json": "application/json",
  "png": "image/png", "jpg": "image/jpeg", "svg": "image/svg+xml", "txt": "text/plain; charset=utf-8"}

-- The response with the content of a file, typed by its extension, or a 404 if it can't be read.
defn FileResponse(path)
  parts = Split(".", path)
  kind = GetOr(Lower(parts[Len(parts)]), "application/octet-stream", types)
  match sys.Read(path)
    Ok(data) -> {Status: 200, Body: data, Headers: [type(kind)]}
    else -> NotFound()
  end
end

-- An application with a route added that serves the files of a folder under a URL prefix. A path can't leave the folder.
defn Static(prefix, folder, a)
  serveFile(request) = static(folder, request.Params["*"])
  Get("$prefix/*", serveFile, a)
end

defn static(folder, rest)
  if ".." in Split("/", rest) or rest == ""
    NotFound()
  else
    FileResponse("$folder/$rest")
  end
end

-- HTML: Escape() for what comes from outside, and {{name}} in a template, escaped.
Escape(s) = Replace("'", "&#39;", Replace("\"", "&quot;", Replace(">", "&gt;", Replace("<", "&lt;", Replace("&", "&amp;", Text(s))))))

-- One pass: a value that holds {{name}} isn't read again.
defn Template(source, values)
  parts = Split("{{", source)
  out = Fill("", Len(parts))
  out[1] = parts[1]
  for k in 2:Len(parts)
    part = parts[k]
    close = ByteFind("}}", 1, part)
    name = if IsMissing(close) missing else Trim(if close == 1 "" else ByteSlice(1, close - 1, part) end) end
    if IsMissing(name) or not Has(name, values)
      out[k] = "{{$part"
    else
      rest = close + 2
      tail = if rest > ByteLength(part) "" else ByteSlice(rest, ByteLength(part), part) end
      out[k] = "$(Escape(values[name]))$tail"
    end
  end
  Join("", out)
end
