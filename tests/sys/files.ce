use sys

dir = "./tmp_files/a/b"
path = "$dir/note.txt"

defn roundTrip()
  sys.Mkdir(dir)?
  sys.Mkdir(dir)?
  sys.Write(path, "one")?
  sys.Append(path, " two")?
  text = sys.Read(path)?
  names = sys.List(dir)?
  sys.Remove(path)?
  sys.Remove(dir)?
  sys.Remove("./tmp_files/a")?
  sys.Remove("./tmp_files")?
  Ok([text, names, sys.Exists(path)])
end
Print(roundTrip())
