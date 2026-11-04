dir=$(mktemp -d)
trap 'rm -rf "$dir"' EXIT
mkdir "$dir/src"
cd "$dir"
printf 'Print("runs")\n' > src/main.ce
project() {
  printf '[project]\nname = "p"\ncesia = %s\n\n[tasks.run]\nfile = "src/main.ce"\n' "$1" > cesia.toml
}
for needed in '"99.0"' '"0.1"' '2' '"latest"'; do
  project "$needed"
  echo "cesia = $needed"
  cesia run src/main.ce
  echo "run: $?"
  cesia do run
  echo "do: $?"
done
