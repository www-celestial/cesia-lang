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
echo "== the tabs, for tools/tabs.ce: each with what its cesia block showed"
sed "s#$t#TMP#g" site/.tabs; echo
echo "== the columns of a method: its module, then its struct, then itself"
sed -n '/<nav class="side"/,/<\/nav>/p' site/ref/src/greet/Greeter.Say.html | grep -E 'greet|Greeter|Say|Hello'
grep -o '<nav class="trail".*</nav>' site/ref/src/greet/Greeter.Say.html
rm -r .cesia/site
cesia doc --site > /dev/null
if [ -e .cesia/site ]; then echo "a page ran again"; else echo "nothing ran again"; fi
echo "== a second book, under its own name, and a folder of docs/ without pages, which is none"
grep -o '<a href="guides/index.html"[^>]*>Guides</a>' site/index.html
grep -o 'href="deploy.html">deploying</a>\|href="../first.html">the first steps</a>' site/guides/index.html
grep -o '2</span>' site/guides/deploy.html | head -1
ls site | grep -c images
echo "== the packages of deps/ have their pages, as those of src/ and std/"
grep -o 'How many words a text holds\.' site/ref/deps/someone/tools/src/count/Words.html
echo "== a build keeps the pages whose sources didn't change, and makes again the others"
sed -i.bak 's/A greeting for a name/A warm greeting for a name/' src/greet/greet.ce
sed -i.bak 's/^# Files$/# Files and folders/' docs/book/files.md
cesia doc --site > /dev/null
grep -o 'A warm greeting for a name' site/ref/src/greet/Hello.html
grep -o 'files.html">Files and folders' site/first.html
echo "== a site outside the project, with nothing in the cache: its pages still run as files of the project"
XDG_CACHE_HOME="$t/fresh" cesia doc --site "$t/outside" > /dev/null
echo "built: $?"
grep -o '<code>Hello, Ana!</code>' "$t/outside/first.html"
echo "== formulas, GitHub's alerts and a table, in the colors of the project, and the font of formulas with its licence"
sed -n '/<main/,/<\/main>/p' site/math.html
grep -o '^:root { --accent[^}]*}' site/site.css
grep -c '@font-face { font-family: "STIX Two Math"; src: url("math.woff2")' site/site.css
cmp -s site/math.woff2 "$root/src/tools/math.woff2" && grep -o 'SIL OPEN FONT LICENSE Version 1.1' site/math-OFL.txt
echo "== the README, a page made from README.md, in the side of every page"
sed -n '/<main/,/<\/main>/p' site/readme.html
grep -o '<a href="readme.html">README</a>' site/index.html
echo "== the French site: a page translated, with the values of its blocks on its own lines, and one not yet"
sed -n '/<main/,/<\/main>/p' site/fr/first.html
sed -n '/<main/,/<h1/p' site/fr/files.html
grep -o '<nav class="langs".*</nav>' site/first.html site/fr/first.html site/ref/index.html
grep -o '<html lang="fr">' site/fr/index.html
grep -o '<a class="ref" href="../ref/index.html">[^<]*</a>' site/fr/index.html
grep -o '<a href="../ref/index.html">référence</a>' site/fr/index.html
head -c 70 site/fr/search.js; echo
rm -rf "$t"
