defn OnStop(stop)
  if stop.Line == 2
    for f in stop.Frames
      Print("frame $(f.Function) $(f.File):$(f.Line)")
      for v in f.Vars
        Print("$(v.Name) = $(v.Value)")
      end
    end
  end
  "step"
end
