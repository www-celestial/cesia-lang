defn OnStop(stop)
  Print("$(stop.Line) $(stop.Frames.Function) $(stop.Frames[1].Vars.Name)")
  "step"
end
