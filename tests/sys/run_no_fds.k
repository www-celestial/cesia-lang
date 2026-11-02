use sys
Print(sys.Run("true") then MapErr(it.Kind))
Print(IsOk(sys.Read("run_no_fds.k")))
