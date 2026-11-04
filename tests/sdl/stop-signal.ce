-- Without --watch, a stop signal is a quit event, and it is one no longer once the window is closed. See stop-signal.cmd.
use tests/sdl/probe
use sdl
use sys

defn update(event, state)
  if event.Kind == "quit" or event.Kind == "text"
    Print(if event.Kind == "quit" "quit" else "no quit" end)
    missing
  else
    state
  end
end

view(state) = [{Kind: "clear", Color: 0x000000}]

-- So that a test that fails doesn't hang.
defn giveUp()
  sys.Sleep(3)
  probe.PushText([0x61])
end

defn main()
  window = sdl.Open("test", 320, 200, "../../examples/fonts/JetBrainsMono-Regular.ttf")?
  Spawn(giveUp)
  Print("open")
  sdl.Run(0, update, view, window)
  sdl.Close(window)
  Print("closed")
  sys.Sleep(3)
  Print("not stopped")
  Ok(missing)
end

Print(main())
