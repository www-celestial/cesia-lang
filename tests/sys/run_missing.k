use sys
Print(sys.Run("no-such-command-kepler") then MapErr(it.Kind))
