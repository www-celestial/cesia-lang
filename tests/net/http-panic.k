use http
use net
use sys

crlf = "$(Char(13))$(Char(10))"
handle(r) = if r.Path == "/boom" Panic("broken") else {Status: 200, Body: "fine"} end

defn get(path)
  c = net.Connect("127.0.0.1", 18093)?
  net.Write(c, "GET $path HTTP/1.1$(crlf)Host: a$(crlf)$crlf")?
  reply = net.Read(c)?
  net.Close(c)
  Ok(Split(crlf, reply)[1])
end

Spawn(() -> http.Serve(handle, port = 18093))
sys.Sleep(0)
Print(get("/boom"))
Print(get("/next"))
