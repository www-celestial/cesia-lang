-- A window under --watch that ends on a quit event, from a stop signal or from a closed window. See tools/reload-test.sh.
use c
use sdl

run() = 1
-- How many quit events end the program: an editor with unsaved text asks first, and goes on.
needed() = 1
-- Does the window close by itself, as a click on its cross does: a close request, then a quit event?
closing() = false

defn update(event, state)
  if event.Kind != "quit"
    state
  else
    Print("quit $(state.Quits + 1)")
    if state.Quits + 1 == needed() missing else {Quits: state.Quits + 1} end
  end
end

view(state) = [{Kind: "clear", Color: 0x000000}]

defn send(code, push, event)
  c.Set("u32", 0, code, event)
  push(event)
end

defn main()
  lib = c.Open("SDL3", version = 0)?
  push = c.Fn("SDL_PushEvent", ["ptr"], "bool", lib)?
  window = sdl.Open("test", 320, 200, "font.ttf")?
  event = c.Alloc(128)
  if closing()
    send(0x210, push, event)
    send(0x100, push, event)
  end
  Print("open $(run())")
  sdl.Run({Quits: 0}, update, view, window)
  sdl.Close(window)
  Print("ended $(run())")
  Ok(missing)
end

Print(main())
