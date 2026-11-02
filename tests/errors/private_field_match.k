use tests/errors/priv/fields as f
Print(match f.New()
  {key: k} -> k
  else -> "no"
end)
