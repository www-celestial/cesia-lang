# The appendices of the book stay complete: docs/book/commands.md names every command and option of the usage text, and
# docs/book/permissions.md every permission and limit that cesia run takes.
missing=0
check() { grep -q -F -- "$2" "$root/docs/book/$1" || { echo "book/$1 doesn't name $2"; missing=1; }; }
usage=$(cesia 2>&1)
for w in $(printf '%s\n' "$usage" | sed -n 's/^ *\(usage: \)\{0,1\}cesia \([a-z]*\).*/\2/p' | sort -u); do check commands.md "cesia $w"; done
for w in $(printf '%s\n' "$usage" | grep -o -E -- '--[a-z-]+' | sort -u); do check commands.md "$w"; done
for w in $(grep -o -E '^  \| "[a-z]+" -> Some Types' "$root/src/bin/main.ml" | grep -o -E '"[a-z]+"' | tr -d '"') all; do
  check permissions.md "\`$w"
done
for w in $(grep -o -E '\| "[a-z]+" -> \{ l with' "$root/src/bin/main.ml" | grep -o -E '"[a-z]+"' | tr -d '"'); do
  check permissions.md "\`$w="
done
echo "checked, missing: $missing"
