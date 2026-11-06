cd isolation
pwd > where.txt
cesia test $no_spec tests > ../out.txt 2>&1
code=$?
sed -E 's#[^ ]*cesia-test-[0-9]+-[0-9a-f]+/#TMP/#' ../out.txt
echo "exit $code"
# The folders kept by the failed tests, which a real run leaves to look at.
grep -o '/[^ ]*cesia-test-[0-9]*-[0-9a-f]*' ../out.txt | sort -u | xargs rm -rf
rm -f ../out.txt where.txt
cat outside/target.txt
