rm -f ../../.cesia/failures/tests-testing-caught.test.ce-*
cesia test $no_spec --seed 1 caught.test.ce
echo "exit $?"
rm -f ../../.cesia/failures/tests-testing-caught.test.ce-*
echo "== examples after an error"
cesia test $no_spec caught-examples.ce
