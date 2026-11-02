use http
use net
use sys

crlf = "$(Char(13))$(Char(10))"
handle(r) = {Status: 200, Body: "ok"}

defn statusOf(request)
  c = net.Connect("127.0.0.1", 18092)?
  net.Write(c, request)?
  reply = net.Read(c)?
  net.Close(c)
  Ok(Split(crlf, reply)[1])
end

bigHeader = "GET / HTTP/1.1$(crlf)X-Big: $(Join("", Fill("0123456789abcdef", 1100)))$(crlf)$crlf"
bigBody = "POST / HTTP/1.1$(crlf)Content-Length: 2097152$(crlf)$crlf"
chunked = "POST / HTTP/1.1$(crlf)Transfer-Encoding: chunked$(crlf)$crlf"
badHeader = "GET / HTTP/1.1$(crlf)no colon here$(crlf)$crlf"

twoSizes = "POST / HTTP/1.1$(crlf)Content-Length: 3$(crlf)Content-Length: 1$(crlf)$(crlf)abc"

Spawn(() -> http.Serve(handle, port = 18092))
sys.Sleep(0)
Print(statusOf("garbage$crlf$crlf"))
Print(statusOf(bigHeader))
Print(statusOf(bigBody))
Print(statusOf(chunked))
Print(statusOf(badHeader))
Print(statusOf(twoSizes))
