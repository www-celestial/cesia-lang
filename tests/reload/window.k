-- A window under --watch: its state must survive a reload. See tools/reload-test.sh.
use c
use sdl
use sys

version() = 1
finished() = false

defn update(event, state)
  if event.Kind == "tick"
    sys.Sleep(0.005)
  end
  if finished() missing else {Count: state.Count + 1} end
end

defn view(state)
  Print("version $(version()) $(state.Count)")
  [{Kind: "clear", Color: 0x000000}]
end

defn feed(send, event)
  send(event)
  sys.Sleep(0.02)
  feed(send, event)
end

defn main()
  lib = c.Open("SDL3", version = 0)?
  send = c.Fn("SDL_PushEvent", ["ptr"], "bool", lib)?
  window = sdl.Open("test", 320, 200, "font.ttf")?
  event = c.Alloc(128)
  c.Set("u32", 0, 0x206, event)
  Spawn(() -> feed(send, event))
  last = sdl.Run({Count: 0}, update, view, window, moving = s -> true)
  sdl.Close(window)
  Print("ended $(last.Count)")
  Ok(missing)
end

main()
