LC_ALL=C
for d in checks/*/; do
  echo "== $(basename "$d")"
  (cd "$d" && kepler do)
  echo "exit $?"
done
