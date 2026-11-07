cd links
ln -sfn .. tests/up
ln -sfn ../elsewhere tests/out
cesia test $no_spec tests
echo "exit $?"
cesia test $no_spec tests/up/tests
echo "exit $?"
rm tests/up tests/out
