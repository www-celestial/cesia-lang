# Every shape of a grant of read= and write=: a file or a folder, written from the root or from the current folder, with a
# last /, ., a link to a file or to a folder, a folder whose path goes through a link, ~ as a name; each act of
# grant-shapes.ce on the paths it names, written as they are, with ./, from the root, or with .. on the way. What each
# gives is what Cesia 4e5c0d8 gave, before the acts opened from the folder of the grant: the expected output is its own.
dir=$(mktemp -d)
trap 'chmod -R u+rwx "$dir"; rm -rf "$dir"' EXIT
here=$(pwd)
run() {  # grant, paths...
  local grant=$1 d top
  shift
  d=$(mktemp -d "$dir/run.XXXXXX")
  cd "$d" || exit 1
  top=$(pwd -P)
  printf 'x\n' > f.txt
  mkdir -p data/sub real/sub outside "~/h"
  printf 'x\n' > data/in.txt
  printf 'x\n' > data/sub/s.txt
  printf 'x\n' > real/x.txt
  printf 'x\n' > real/sub/y.txt
  printf 'x\n' > outside/o.txt
  printf 'x\n' > "~/h/t.txt"
  ln -s f.txt flink
  ln -s data dlink
  ln -s real alias
  grant=${grant//TOP/$top}
  local args=()
  for p in "$@"; do args+=("${p//TOP/$top}"); done
  echo "== --allow $grant" | sed "s|$top|TOP|g"
  cesia run $no_spec --allow "$grant" "$here/grant-shapes.ce" "${args[@]}" 2> /dev/null | sed "s|$top|TOP|g"
  echo "-- after: $(find . -name '*.copy' | LC_ALL=C sort | tr '\n' ' ')$(ls -ld f.txt data/in.txt 2> /dev/null | cut -c 1-10 | tr '\n' ' ')"
  cd "$here" || exit 1
}
run "read=f.txt" f.txt ./f.txt TOP/f.txt data/../f.txt flink data/in.txt
run "read=TOP/f.txt" f.txt ./f.txt TOP/f.txt data/../f.txt
run "read=f.txt,write=f.txt" f.txt ./f.txt TOP/f.txt data/../f.txt
run "read=TOP/f.txt,write=TOP/f.txt" f.txt TOP/f.txt
run "write=f.txt" f.txt
run "read=new.txt,write=new.txt" new.txt ./new.txt
run "write=TOP/new.txt" new.txt
run "read=data,write=data" data data/ ./data TOP/data data/in.txt ./data/in.txt TOP/data/in.txt data/sub/../in.txt data/sub dlink/in.txt f.txt
run "read=data/,write=data/" data data/in.txt
run "read=TOP/data/,write=TOP/data" data data/in.txt TOP/data/sub/s.txt
run "read=.,write=." f.txt data/in.txt . ./ flink dlink/in.txt outside/o.txt
run "read=./,write=./" f.txt . ./
run "read=TOP,write=TOP" f.txt TOP/f.txt .
run "read=flink,write=flink" flink f.txt
run "read=dlink,write=dlink" dlink dlink/in.txt data/in.txt dlink/
run "read=alias/x.txt,write=alias/x.txt" alias/x.txt real/x.txt TOP/alias/x.txt
run "read=alias/sub,write=alias/sub" alias/sub alias/sub/y.txt real/sub/y.txt
run "read=~/h,write=~/h" "~/h/t.txt" "~/h"
run "read=f.txt,write=data" f.txt data/in.txt
run "read=data,write=f.txt" f.txt data/in.txt
