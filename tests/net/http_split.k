use http
use net
use sys

crlf = "$(Char(13))$(Char(10))"
request = "GET /x HTTP/1.1$(crlf)Host: a$(crlf)$crlf"
handle(r) = {Status: 200, Body: r.Path}

count(text) = Len(Split("HTTP/1.1", text)) - 1

defn readUntil(c, wanted, got)
  if count(got) >= wanted
    Ok(got)
  else
    more = net.Read(c)?
    readUntil(c, wanted, "$got$more")
  end
end

defn client()
  c = net.Connect("127.0.0.1", 18091)?
  net.Write(c, "GET /x HT")?
  sys.Sleep(0.01)
  net.Write(c, Slice(10, Len(request), request))?
  first = readUntil(c, 1, "")?
  net.Write(c, "$request$request")?
  both = readUntil(c, 2, "")?
  Ok([count(first), count(both)])
end

Spawn(() -> http.Serve(handle, port = 18091))
sys.Sleep(0)
Print(client())
