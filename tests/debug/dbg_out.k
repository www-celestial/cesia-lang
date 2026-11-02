defn OnStop(stop)
  Print("$(stop.File):$(stop.Line) $(stop.Reason)")
  if stop.Line == 2 "out" else "step" end
end
