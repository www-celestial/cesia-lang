-- The speed gate of the interface: the whole scene of the material editor, in a real window, without vsync. Run through
-- tools/frame_bench.sh. Each frame moves a node, so the curves are rewritten.
use sdl
use sys
use examples/scene as scene

frames = 300

defn opened()
  first = sdl.Open("Kepler speed gate", 1280, 720, "examples/fonts/AdwaitaSans-Regular.ttf", size = 13, vsync = false, light = true)?
  second = sdl.AddFont("strong", "examples/fonts/NotoSans-Medium.ttf", 13, first, light = true)?
  third = sdl.AddFont("code", "examples/fonts/JetBrainsMono-Regular.ttf", 13, second)?
  sdl.AddFont("large", "examples/fonts/AdwaitaSans-Regular.ttf", 42, third, light = true)
end

defn moved(state, n)
  s = state
  s.Nodes[4].X = 560 + Mod(n, 40)
  s
end

-- Draws the frames and gives the time of each, in milliseconds.
defn measure(begun, sphere)
  state = begun.State
  window = begun.Window
  times = []
  for n in 1:frames
    start = sys.Now()
    state = moved(state, n)
    if sphere
      state.Rough = 0.2 + Mod(n, 60) / 100.0
      state.ShownRough = state.Rough
      state = scene.Update({Kind: "tick", Seconds: 0.016}, state)
    end
    window = sdl.Frame(scene.View(state), window)
    times = Append((sys.Now() - start) * 1000.0, times)
  end
  times
end

defn report(name, times)
  sorted = Sort(times)
  total = Reduce((a, b) -> a + b, 0.0, times)
  Print("$name: $(Floor(frames * 1000.0 / total)) frames/s, 99% under $(Floor(sorted[Div(frames * 99, 100)] * 10.0) / 10.0) ms, worst $(Floor(Last(sorted) * 10.0) / 10.0) ms")
end

defn main()
  begun = scene.Start(opened()?)?
  report("scene", measure(begun, false))
  report("scene and small sphere", measure(begun, true))
  start = sys.Now()
  scene.ShadeSphere(begun.State.Images.Sharp.Pixels, 208, 0.5, 0.5, 0.3)
  Print("sharp sphere: $(Floor((sys.Now() - start) * 1000.0)) ms")
  sdl.Close(begun.Window)
  Ok(missing)
end

Print(main())
