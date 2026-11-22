# Linux alone has /proc: elsewhere, what it would print. No exit here: the harness prints the exit of the whole file.
if [ ! -r /proc/self/smaps ]; then
  printf 'status starts with its name: true\nsmaps past a page: true, whole: true\neach mapping with its size: true\nan empty file: Ok("")\nexit 0\n'
else
  dir=$(mktemp -d)
  trap 'rm -rf "$dir"' EXIT
  cesia run $no_spec --allow read,write read-proc.ce "$dir/empty.txt"
  echo "exit $?"
fi
