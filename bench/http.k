use http

handle(request) = {Status: 200, Body: "Kepler"}
http.Serve(handle, port = 19100)
