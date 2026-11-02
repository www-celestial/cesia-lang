-- Runs forever: tools/reload_test.sh edits the files of its package while it runs.
use pack
use sys

defn watching(last)
  v = pack.Value()
  if not Equal(v, last)
    Print("pack $v")
  end
  sys.Sleep(0.001)
  watching(v)
end

watching(missing)
