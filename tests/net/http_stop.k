use http
use sys

defn handle(r)
  sys.Sleep(0.2)
  {Status: 200, Body: "slow"}
end

Print(http.Serve(handle, port = 18095))
Print("stopped")
