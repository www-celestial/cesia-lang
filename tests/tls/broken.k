-- One client's garbage leaves the others alone, a silent TCP close is an error, and a client that says nothing is closed.
use tls
use web
use http
use net
use sys

crlf = "\r\n"

defn garbage()
  c = net.Connect("127.0.0.1", 18208)?
  net.Write(c, "this is not TLS at all")?
  net.Read(c)
  net.Close(c)
  Ok(missing)
end

defn mute()
  c = net.Connect("127.0.0.1", 18208)?
  got = net.Read(c)
  net.Close(c)
  Print("mute client closed", IsOk(got) and ByteLength(got.Value) == 0)
  Ok(missing)
end

defn truncating(wrap)
  listener = net.Listen(18209)?
  c = net.Accept(listener)?
  io = wrap(c)?
  io.Read()?
  io.Write("HTTP/1.1 200 OK$crlf$(crlf)partial")?
  net.Close(c)
  net.Close(listener)
  Ok(missing)
end

defn main()
  api = tls.Open()?
  wrap = tls.Server(Args[1], Args[2], api)?
  a = web.Get("/", req -> web.Plain("over tls"), web.App())
  Spawn(() -> web.Serve(a, port = 18208, wrap = wrap, timeout = 0.2))
  sys.Sleep(0.05)
  client = tls.Client(api, verify = false)
  for k in 1:20
    garbage()?
  end
  Print(http.Get("https://127.0.0.1:18208/", secure = client) then MapOk(it.Body))
  mute()?
  Spawn(() -> truncating(wrap))
  sys.Sleep(0.02)
  Print(http.Get("https://127.0.0.1:18209/", secure = client) then MapErr(it.Message))
  Ok(missing)
end

Print(main())
