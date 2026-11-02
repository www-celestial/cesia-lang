use http
use net
use sys

handle(request) = match sys.Read("page.html")
  Ok(text) -> {Status: 200, Body: text}
  Err(e) -> {Status: 404, Body: e.Message}
end

crlf = "$(Char(13))$(Char(10))"

defn client()
  c = net.Connect("127.0.0.1", 18096)?
  net.Write(c, "GET / HTTP/1.1$(crlf)Host: a$(crlf)$crlf")?
  net.Read(c) then MapOk(r -> Split(crlf, r))
end

Spawn(() -> http.Serve(handle, port = 18096))
sys.Sleep(0)
Print(client())
