LC_ALL=C
for d in checks/*/; do
  echo "== $(basename "$d")"
  (cd "$d" && cesia do)
  echo "exit $?"
done
