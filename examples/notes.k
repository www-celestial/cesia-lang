-- A small web app: GET shows the notes, POST adds one.
--   kepler run --allow read=notes.txt,write=notes.txt,net=:8080 examples/notes.k
--   curl -d "buy milk" localhost:8080
--   curl localhost:8080
use http
use sys

file = "notes.txt"

defn handle(request)
  if request.Method == "POST"
    sys.Append(file, "$(request.Body)$(Char(10))")?
  end
  notes = if sys.Exists(file) sys.Read(file)? else "" end
  Ok({Status: 200, Body: notes})
end

reply(request) = match handle(request)
  Ok(response) -> response
  Err(e) -> {Status: 500, Body: e.Message}
end

Print(http.Serve(reply, port = 8080))
