# The book of a tiny project: its pages as the site writes them, then a build from the cache, which runs nothing again.
t=$(mktemp -d)
cp -r proj "$t/"
cd "$t/proj"
export XDG_CACHE_HOME="$t/cache"
cesia doc --site > /dev/null
echo "built: $?"
for page in index first files; do
  echo "== $page.html"
  sed -n '/<main/,/<\/main>/p' "site/$page.html"
done
echo "== the columns of a method: its module, then its struct, then itself"
sed -n '/<nav class="side"/,/<\/nav>/p' site/ref/src/greet/Greeter.Say.html | grep -E 'greet|Greeter|Say|Hello'
grep -o '<nav class="trail".*</nav>' site/ref/src/greet/Greeter.Say.html
rm -r site/.run
cesia doc --site > /dev/null
if [ -e site/.run ]; then echo "a page ran again"; else echo "nothing ran again"; fi
echo "== a second book, under its own name, and a folder of docs/ without pages, which is none"
grep -o '<a href="guides/index.html"[^>]*>Guides</a>' site/index.html
grep -o 'href="deploy.html">deploying</a>\|href="../first.html">the first steps</a>' site/guides/index.html
grep -o '2</span>' site/guides/deploy.html | head -1
ls site | grep -c images
echo "== a build keeps the pages whose sources didn't change, and makes again the others"
sed -i.bak 's/A greeting for a name/A warm greeting for a name/' src/greet/greet.ce
sed -i.bak 's/^# Files$/# Files and folders/' docs/book/files.md
cesia doc --site > /dev/null
grep -o 'A warm greeting for a name' site/ref/src/greet/Hello.html
grep -o 'files.html">Files and folders' site/first.html
rm -rf "$t"
