dir=$(mktemp -d)
trap 'rm -rf "$dir"' EXIT
cd "$dir"
awk 'BEGIN {
  print "[project]\nname = \"chain\""
  for (i = 0; i < 19999; i++) printf "[tasks.t%d]\nneeds = [\"t%d\"]\nrun = [\"true\"]\n", i, i + 1
  print "[tasks.t19999]\nrun = [\"true\"]"
}' > cesia.toml
cesia do | wc -l | tr -d ' '
