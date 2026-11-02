use tests/sdl/probe
use sdl
use sys

defn tick(event, state)
  if event.Seconds <= 0.0 or event.Seconds > 0.05
    Print("bad seconds $(event.Seconds)")
  end
  if state.Left == 3
    sys.Sleep(0.07)
  end
  {Left: state.Left - 1}
end

defn update(event, state)
  match event
    {Kind: "quit"} -> missing
    {Kind: "tick"} -> tick(event, state)
    else -> state
  end
end

defn view(state)
  Print("view $(state.Left)")
  [{Kind: "clear", Color: 0x000000}]
end

defn later()
  sys.Sleep(0.1)
  probe.PushQuit()
end

defn check()
  w = sdl.Open("test", 320, 200, "../../examples/fonts/JetBrainsMono-Regular.ttf")?
  Spawn(later)
  last = sdl.Run({Left: 5}, update, view, w, moving = s -> s.Left > 0)
  Print(last.Left)
  Ok("ran")
end

Print(check())
