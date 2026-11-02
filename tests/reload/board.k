-- Runs forever: tools/reload-test.sh edits it and its packages while it runs. In sorted order it comes before commands, which
-- comes before view: what calls reloads before what it calls.
use commands
use sys

shown() = commands.Value()

defn watching(last)
  v = shown()
  if not Equal(v, last)
    Print("board $v")
  end
  sys.Sleep(0.001)
  watching(v)
end

watching(missing)
