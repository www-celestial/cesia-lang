use sys

defn main()
  sys.Write("stat_a.txt", "hello")?
  s = sys.Stat("stat_a.txt")?
  Print(s.Size, s.IsDir, s.Modified > 1000000000)
  sys.Rename("stat_a.txt", "stat_b.txt")?
  Print(sys.Exists("stat_a.txt"), sys.Read("stat_b.txt"))
  Print(sys.Stat(".")?.IsDir)
  Print(IsErr(sys.Stat("no_such_file")))
  sys.Remove("stat_b.txt")?
  Ok(missing)
end

Print(main())
