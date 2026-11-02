-- The worst case of a window: every line of a full screen changes at every frame. Run through tools/frame_bench.sh.
use sdl
use sys

lines = 55
columns = 200
frames = 300
letters = Join("", Fill("abcdefghijklmnopqrstuvwxyz", 12))

-- A line taken from a long text, as an editor would, and different at each frame.
defn line(row, n)
  from = 1 + Mod(row * 3 + n, 26)
  {Kind: "text", X: 8, Y: 8 + (row - 1) * 19, Text: Slice(from, from + columns - 1, letters), Color: 0xE0E0E0}
end

view(n) = [if k == 0 {Kind: "clear", Color: 0x1E1E1E} else line(k, n) end for k in 0:lines]

defn run(window, n)
  if n > frames window else run(sdl.Frame(view(n), window), n + 1) end
end

defn measure()
  window = sdl.Open("Kepler speed gate", 1920, 1080, "examples/fonts/JetBrainsMono-Regular.ttf", vsync = false)?
  start = sys.Now()
  last = run(window, 1)
  seconds = sys.Now() - start
  sdl.Close(last)
  Ok(frames / seconds)
end

match measure()
  Ok(rate) -> Print("frames per second: $(Floor(rate))")
  Err(e) -> Print(e.Message)
end
