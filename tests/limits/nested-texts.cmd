# A text in the code of a text, 300,000 deep: the lexer refuses it at the first level past the limit of nesting, as the
# parser would, before the tokens and buffers of each level take 150 times the file's size. Its line, without the path.
deep=$(mktemp)
{ printf 'use std/io\nio.Print('; printf '"$(%.0s' $(seq 300000); printf 'x'; printf ')"%.0s' $(seq 300000); printf ')\n'; } > "$deep"
out=$(cesia run $no_spec "$deep" 2>&1); code=$?
echo "${out%%$'\n'*}" | sed 's|^[^:]*:||'
out=$(cesia check "$deep" 2>&1)
echo "${out%%$'\n'*}" | sed 's|^[^:]*:||'
rm -f "$deep"
(exit $code)
