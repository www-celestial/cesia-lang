defn OnStop(stop)
  Print("$(stop.File):$(stop.Line) $(stop.Reason)")
  "next"
end
