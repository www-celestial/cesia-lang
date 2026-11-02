defn OnStop(stop)
  if stop.Line == 3
    v = stop.Frames[1].Vars
    a = v[1].Value
    a[1] = 99.0
    v[1].Value = 7
  end
  "step"
end
