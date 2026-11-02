use debug

defn OnStop(stop)
  Print("$(stop.File):$(stop.Line) $(stop.Reason)")
  if stop.Reason == "start"
    debug.SetBreak("break.k", 4)
  end
  "continue"
end
