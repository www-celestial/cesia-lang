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
rm -rf "$t"
